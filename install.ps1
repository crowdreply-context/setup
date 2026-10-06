# CrowdReply context bank: one-command setup for Windows. Safe to run again at any time.
#   irm https://raw.githubusercontent.com/crowdreply-context/setup/main/install.ps1 | iex
$ErrorActionPreference = 'Continue'

$Org = 'crowdreply-context'
$Repo = "$Org/context"
$Dir = Join-Path $HOME 'crowdreply-context'
$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }

function Step($t) { Write-Host "`n$t" -ForegroundColor White }
function Ok($t)   { Write-Host "  [ok] $t" -ForegroundColor Green }
function Note($t) { Write-Host "  [!] $t" -ForegroundColor Yellow }
function Refresh-Path {
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}
function Has($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }
function Read-Json($path) {
  if (-not (Test-Path $path)) { return [pscustomobject]@{} }
  $raw = [IO.File]::ReadAllText($path)
  if (-not $raw.Trim()) { return [pscustomobject]@{} }
  return $raw | ConvertFrom-Json
}
function Write-Json($path, $obj) {
  New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
  [IO.File]::WriteAllText($path, ($obj | ConvertTo-Json -Depth 32))   # UTF-8 without BOM
}
function Ensure-Prop($obj, $name, $value) {
  if (-not ($obj.PSObject.Properties.Name -contains $name)) { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value }
  return $obj.$name
}

& {
  # ------------------------------------------------------------ 1. Git and GitHub CLI
  Step '1/5  Git and GitHub CLI'
  foreach ($p in @(@{ cmd = 'git'; id = 'Git.Git'; url = 'https://git-scm.com' }, @{ cmd = 'gh'; id = 'GitHub.cli'; url = 'https://cli.github.com' })) {
    if (-not (Has $p.cmd)) {
      if (Has 'winget') {
        winget install --id $p.id -e --silent --accept-source-agreements --accept-package-agreements | Out-Null
        Refresh-Path
      }
    }
    if (Has $p.cmd) { Ok "$($p.cmd) ready" }
    else { Note "Couldn't install $($p.cmd). Install it from $($p.url), then run this command again."; return }
  }

  # ------------------------------------------------------------ 2. GitHub login
  Step '2/5  GitHub login'
  $login = gh api user --jq .login 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $login) {
    Write-Host '  A browser window opens. The code is already copied: paste it there and click Authorize.'
    gh auth login -h github.com -p https --web --clipboard --skip-ssh-key
    $login = gh api user --jq .login 2>$null
    if (-not $login) { Note 'GitHub login did not finish. Run this command again.'; return }
  }
  Ok "logged in as $login"
  gh auth setup-git -h github.com 2>$null | Out-Null

  # ------------------------------------------------------------ 3. Team invite
  Step '3/5  CrowdReply team access'
  $state = gh api "user/memberships/orgs/$Org" --jq .state 2>$null
  if ($state -eq 'pending') {
    gh api -X PATCH "user/memberships/orgs/$Org" -f state=active 2>$null | Out-Null
    $state = gh api "user/memberships/orgs/$Org" --jq .state 2>$null
    if ($state -ne 'active') {
      Write-Host '  Accept the invite in the browser window that opens, then come back here.'
      Start-Process "https://github.com/orgs/$Org/invitation"
      Read-Host '  Press Enter once you have accepted' | Out-Null
      $state = gh api "user/memberships/orgs/$Org" --jq .state 2>$null
    }
  }
  if ($state -ne 'active') {
    Note "No access yet for GitHub user '$login'."
    Note 'Post that username in the CrowdReply Slack, wait for the invite email, then run this command again.'
    return
  }
  Ok "member of $Org"

  # ------------------------------------------------------------ 4. The context bank
  Step '4/5  Context bank'
  if (Test-Path (Join-Path $Dir '.git')) { git -C $Dir pull --ff-only --quiet; Ok "updated $Dir" }
  else { gh repo clone $Repo $Dir -- --quiet; Ok "downloaded to $Dir" }

  $targets = @()
  if (Test-Path (Join-Path $HOME '.cursor')) { $targets += (Join-Path $HOME '.cursor\skills') }
  if ((Test-Path (Join-Path $HOME '.agents')) -or (Test-Path (Join-Path $HOME '.codex'))) { $targets += (Join-Path $HOME '.agents\skills') }
  foreach ($t in $targets) {
    New-Item -ItemType Directory -Force -Path $t | Out-Null
    Get-ChildItem (Join-Path $Dir 'skills') -Directory | ForEach-Object {
      $dest = Join-Path $t $_.Name
      if (-not (Test-Path $dest)) { New-Item -ItemType Junction -Path $dest -Target $_.FullName | Out-Null }
    }
  }
  if ($targets.Count) { Ok "skills linked for Cursor/Codex in: $($targets -join ', ')" } else { Ok 'no Cursor or Codex found (skip)' }

  # ------------------------------------------------------------ 5. Claude Code
  Step '5/5  Claude Code'
  if (Has 'claude') {
    $known = claude plugin marketplace list 2>$null | Out-String
    if ($known -notmatch 'crowdreply') { claude plugin marketplace add $Repo | Out-Null }
    claude plugin install crowdreply@crowdreply 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { claude plugin update crowdreply@crowdreply 2>$null | Out-Null }
    try {
      $settingsPath = Join-Path $ClaudeDir 'settings.json'
      $s = Read-Json $settingsPath
      $ekm = Ensure-Prop $s 'extraKnownMarketplaces' ([pscustomobject]@{})
      $cr = Ensure-Prop $ekm 'crowdreply' ([pscustomobject]@{ source = [pscustomobject]@{ source = 'github'; repo = $Repo } })
      if ($cr.PSObject.Properties.Name -contains 'autoUpdate') { $cr.autoUpdate = $true } else { $cr | Add-Member -NotePropertyName autoUpdate -NotePropertyValue $true }
      Write-Json $settingsPath $s

      $knownPath = Join-Path $ClaudeDir 'plugins\known_marketplaces.json'
      if (Test-Path $knownPath) {
        $k = Read-Json $knownPath
        if ($k.PSObject.Properties.Name -contains 'crowdreply') {
          if ($k.crowdreply.PSObject.Properties.Name -contains 'autoUpdate') { $k.crowdreply.autoUpdate = $true }
          else { $k.crowdreply | Add-Member -NotePropertyName autoUpdate -NotePropertyValue $true }
          Write-Json $knownPath $k
        }
      }
      Ok 'plugin installed, auto-update on'
    } catch {
      Note 'Plugin installed. Turn on auto-update in Claude Code: /plugin > Marketplaces > crowdreply'
    }
  } else {
    Note "Claude Code isn't installed. Install it, then run this command again:"
    Note '  irm https://claude.ai/install.ps1 | iex'
    Note 'CrowdReply covers your Claude subscription (Max plan). Ask in Slack for help with the payment.'
  }

  Step 'Done'
  Write-Host '  Restart Claude Code / Cursor, then ask:'
  Write-Host '  "What does CrowdReply''s Growth plan include, and what colour do we use for accent text?"'
  Write-Host '  It should answer from the context bank and name the files it used.'
}
