# CrowdReply team setup

One command connects your AI tools to the CrowdReply context bank. The bank is the company's
approved product, positioning, brand and design context, plus its shared AI skills.

**Before you start:** have a GitHub account and post your username in the CrowdReply Slack so you
get invited.

## Mac or Linux

Open Terminal and paste:

```bash
curl -fsSL https://raw.githubusercontent.com/crowdreply-context/setup/main/install.sh | bash
```

## Windows

Open PowerShell and paste:

```powershell
irm https://raw.githubusercontent.com/crowdreply-context/setup/main/install.ps1 | iex
```

## What it does

1. Installs Git and the GitHub CLI if you don't have them.
2. Logs you in to GitHub. A browser window opens; the one-time code is already copied, so paste it
   and click **Authorize**.
3. Accepts your invite to the team.
4. Downloads the context bank and links its skills for Cursor and Codex, if you use them.
5. Connects Claude Code with auto-update on, if you have it installed.

It's safe to run again at any time, for example after installing Claude Code or Cursor later.

The full guide (how to use it, prompts by role, Figma, troubleshooting) is inside the context bank
at `docs/GETTING-STARTED.md`.
