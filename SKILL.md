---
name: claude-session-restorer
description: >-
  Restore missing Claude Code sessions in the Claude Desktop "Code" tab — especially
  after logging into a different Claude account, after a logout/reinstall, or when sessions
  started from the CLI / VS Code don't appear in the app. Use when someone says their Claude
  Code chats or sessions "disappeared", are "missing after switching accounts", or asks how
  to recover / restore Claude Code session history on Windows. Runs a safe, reversible
  PowerShell script that rebuilds the per-account session index from the on-disk transcripts.
---

# Claude Code → Code-tab Session Restorer

## When to use this skill
Trigger when a user reports any of:
- "My Claude Code sessions / chats disappeared from the Code tab."
- "I switched / logged into another Claude account and now my old sessions are gone."
- "Sessions I started in the CLI or VS Code don't show up in the desktop app."
- "How do I recover / restore my Claude Code history?"

Platform: **Windows** (Windows PowerShell 5.1 or PowerShell 7).

## What's actually wrong (explain this to the user)
Their conversations are **not lost**. Claude Code keeps every transcript on disk at
`%USERPROFILE%\.claude\projects\<encoded-cwd>\<sessionId>.jsonl`, keyed by project folder
with **no account tag**. But the Code tab lists sessions from per-account "card" files at
`%APPDATA%\Claude\claude-code-sessions\<accountId>\<organizationId>\local_*.json`, each
linking to a transcript via `cliSessionId`. Cards are scoped by their **folder** (account),
so sessions from another account — or CLI/VS Code sessions with no card — don't appear.

## How to run it
The script `restore-code-tab-sessions.ps1` lives next to this file.

1. Tell the user to **quit Claude Desktop completely** (including the system tray icon →
   right-click → Quit). The app rewrites the card folder on exit, so it must be closed.
2. Run:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "<path-to-skill>\restore-code-tab-sessions.ps1"
   ```
3. Tell them to **reopen Claude Desktop → Code tab**. Sessions should be listed.

### Options
- `-ExistingCardsOnly` — only migrate sessions that were **originally created in the Code
  tab** (copy existing cards from other accounts); skip CLI / VS Code sessions. Recommended
  when the user is simply moving between accounts and doesn't want CLI sessions listed.
- `-DestRoot <path>` — dry run: write cards to a throwaway folder to inspect output first.
- `-IgnoreRunning` — don't abort if Claude looks like it's running.
- `-NoBackup` — skip the backup (testing only).

## What the script does (idempotent + reversible)
1. Backs up the entire card index to `…\claude-code-sessions_backup_<timestamp>`.
2. Auto-detects the logged-in account from `.claude.json` (`oauthAccount`).
3. Copies cards from other account folders into the current account's folder.
4. Unless `-ExistingCardsOnly`, generates cards for transcripts that have none — using each
   transcript's `aiTitle` for the display name, written as UTF‑8 with no BOM.

## Safety guidance to give the user
- It only **adds** cards; it never edits or deletes transcripts.
- To undo: delete the added cards or restore the `_backup_` folder, then restart the app.
- Suggest also setting `"cleanupPeriodDays": 3650` in
  `%USERPROFILE%\.claude\settings.json` so old transcripts aren't auto-deleted (default 30 days).

## Fallback (no app needed)
Sessions can always be resumed on the CLI from the project's folder:
`claude --resume`, `claude --resume <sessionId>`, or `claude --continue`. The resume list is
scoped to the current folder, not the account.

## Disclaimer
Unofficial; not affiliated with Anthropic. Works with on-disk files whose format was
determined by observation and may change between app versions. Backs up before writing.
