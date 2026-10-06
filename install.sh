#!/usr/bin/env bash
# CrowdReply context bank: one-command setup for Mac and Linux. Safe to run again at any time.
#   curl -fsSL https://raw.githubusercontent.com/crowdreply-context/setup/main/install.sh | bash
set -euo pipefail

ORG="crowdreply-context"
REPO="$ORG/context"
DIR="$HOME/crowdreply-context"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

step() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
note() { printf '  \033[33m!\033[0m %s\n' "$*"; }
json_set() { # json_set FILE PY_EXPR : edit a JSON file in place (python3 is present wherever git is)
  python3 - "$1" "$2" <<'PY'
import json, sys, os
p, expr = sys.argv[1], sys.argv[2]
d = json.load(open(p)) if os.path.exists(p) and os.path.getsize(p) else {}
exec(expr)
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump(d, open(p, "w"), indent=2)
PY
}

# ---------------------------------------------------------------- 0. git
if ! git --version >/dev/null 2>&1 || ! python3 -c 1 >/dev/null 2>&1; then
  if [ "$(uname -s)" = Darwin ]; then
    echo "Apple's developer tools are needed first (git). A window opens: click Install, wait for it to finish,"
    echo "then run this same command again."
    xcode-select --install 2>/dev/null || true
  else
    echo "Install git and python3 with your package manager, then run this again."
  fi
  exit 1
fi

# ---------------------------------------------------------------- 1. GitHub CLI
step "1/5  GitHub CLI"
export PATH="$HOME/.local/bin:$PATH"
if command -v gh >/dev/null 2>&1; then
  ok "already installed"
else
  if command -v brew >/dev/null 2>&1; then
    brew install gh
  else
    tag=$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest | grep -m1 '"tag_name"' | cut -d'"' -f4)
    v=${tag#v}; tmp=$(mktemp -d); mkdir -p "$HOME/.local/bin"
    case "$(uname -m)" in x86_64) a=amd64 ;; arm64|aarch64) a=arm64 ;; *) a=$(uname -m) ;; esac
    if [ "$(uname -s)" = Darwin ]; then
      curl -fsSL -o "$tmp/gh.zip" "https://github.com/cli/cli/releases/download/$tag/gh_${v}_macOS_${a}.zip"
      unzip -q "$tmp/gh.zip" -d "$tmp"
    else
      curl -fsSL "https://github.com/cli/cli/releases/download/$tag/gh_${v}_linux_${a}.tar.gz" | tar -xz -C "$tmp"
    fi
    cp "$tmp"/gh_*/bin/gh "$HOME/.local/bin/gh" && chmod +x "$HOME/.local/bin/gh"
    for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
      [ -f "$rc" ] && ! grep -q '.local/bin' "$rc" && echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc"
    done
  fi
  ok "installed ($(gh --version | head -1))"
fi

# ---------------------------------------------------------------- 2. GitHub login
step "2/5  GitHub login"
if gh api user --jq .login >/dev/null 2>&1; then
  ok "logged in as $(gh api user --jq .login)"
else
  echo "  A browser window opens. The code is already copied: paste it there and click Authorize."
  gh auth login -h github.com -p https --web --clipboard --skip-ssh-key </dev/tty
  ok "logged in as $(gh api user --jq .login)"
fi
gh auth setup-git -h github.com >/dev/null 2>&1 || true

# ---------------------------------------------------------------- 3. Team invite
step "3/5  CrowdReply team access"
state=$(gh api "user/memberships/orgs/$ORG" --jq .state 2>/dev/null || echo none)
if [ "$state" = pending ]; then
  if gh api -X PATCH "user/memberships/orgs/$ORG" -f state=active >/dev/null 2>&1; then
    state=active
  else
    echo "  Accept the invite in the browser window that opens, then come back here."
    (open "https://github.com/orgs/$ORG/invitation" 2>/dev/null || xdg-open "https://github.com/orgs/$ORG/invitation" 2>/dev/null) || echo "  https://github.com/orgs/$ORG/invitation"
    read -r -p "  Press Enter once you've accepted… " _ </dev/tty
    state=$(gh api "user/memberships/orgs/$ORG" --jq .state 2>/dev/null || echo none)
  fi
fi
if [ "$state" != active ]; then
  note "No access yet for GitHub user '$(gh api user --jq .login)'."
  note "Post that username in the CrowdReply Slack, wait for the invite email, then run this command again."
  exit 1
fi
ok "member of $ORG"

# ---------------------------------------------------------------- 4. The context bank
step "4/5  Context bank"
if [ -d "$DIR/.git" ]; then git -C "$DIR" pull --ff-only --quiet; ok "updated $DIR"
else gh repo clone "$REPO" "$DIR" -- --quiet; ok "downloaded to $DIR"; fi

# Cursor, Codex and other agents read skills from these folders. Link only where the tool exists.
linked=""
for target in "$HOME/.cursor:skills" "$HOME/.agents:skills" "$HOME/.codex:../.agents/skills"; do
  base=${target%%:*}; sub=${target#*:}
  [ -d "$base" ] || continue
  dest=$(cd "$base" && mkdir -p "$sub" && cd "$sub" && pwd)
  for s in "$DIR"/skills/*/; do
    n=$(basename "$s"); [ -e "$dest/$n" ] || ln -s "${s%/}" "$dest/$n"
  done
  case "$linked" in *"$dest"*) ;; *) linked="$linked $dest" ;; esac
done
[ -n "$linked" ] && ok "skills linked for Cursor/Codex in:$linked" || ok "no Cursor or Codex found (skip)"

# ---------------------------------------------------------------- 5. Claude Code
step "5/5  Claude Code"
if command -v claude >/dev/null 2>&1; then
  claude plugin marketplace list 2>/dev/null | grep -q crowdreply || claude plugin marketplace add "$REPO" >/dev/null
  claude plugin install crowdreply@crowdreply >/dev/null 2>&1 || claude plugin update crowdreply@crowdreply >/dev/null 2>&1 || true
  json_set "$CLAUDE_DIR/settings.json" "d.setdefault('extraKnownMarketplaces',{}).setdefault('crowdreply',{'source':{'source':'github','repo':'$REPO'}})['autoUpdate']=True" \
    && json_set "$CLAUDE_DIR/plugins/known_marketplaces.json" "d.get('crowdreply',{}) and d['crowdreply'].update({'autoUpdate': True})" \
    && ok "plugin installed, auto-update on" \
    || note "plugin installed. Turn on auto-update in Claude Code: /plugin → Marketplaces → crowdreply"
else
  note "Claude Code isn't installed. Install it, then run this command again:"
  note "  curl -fsSL https://claude.ai/install.sh | bash"
  note "CrowdReply covers your Claude subscription (Max plan). Ask in Slack for help with the payment."
fi

step "Done"
echo "  Restart Claude Code / Cursor, then ask:"
echo "  \"What does CrowdReply's Growth plan include, and what colour do we use for accent text?\""
echo "  It should answer from the context bank and name the files it used."
