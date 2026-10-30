---
name: claude-session-restorer
description: >-
  Restore missing Claude Code sessions in the Claude Desktop "Code" tab — especially
  after logging into a different Claude account, after a logout/reinstall, or when sessions
  started from the CLI / VS Code don't appear in the app. Use when someone says their Claude
  Code chats or sessions "disappeared", are "missing after switching accounts", or asks how
  to recover / restore Claude Code session history. Runs a safe, reversible script (PowerShell
  on Windows, Bash on macOS/Linux) that rebuilds the per-account session index from the
  on-disk transcripts.
---

# Claude Code → Code-tab Session Restorer

## When to use this skill
Trigger when a user reports any of:
- "My Claude Code sessions / chats disappeared from the Code tab."
- "I switched / logged into another Claude account and now my old sessions are gone."
- "Sessions I started in the CLI or VS Code don't show up in the desktop app."
- "How do I recover / restore my Claude Code history?"

Platform: **Windows** (`.ps1`, Windows PowerShell 5.1 or PowerShell 7), **macOS** (`.sh`,
plain Bash + `jq`/`uuidgen`/`rsync`, all preinstalled on a stock macOS — verified against
the real on-disk layout), and **Linux** (`.sh`, same dependencies, best-effort/unverified —
see Compatibility in the README).

## What's actually wrong (explain this to the user)
Their conversations are **not lost**. Claude Code keeps every transcript on disk at
`~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl` (`%USERPROFILE%\.claude\projects\...`
on Windows), keyed by project folder with **no account tag**. But the Code tab lists
sessions from per-account "card" files — `%APPDATA%\Claude\claude-code-sessions\...` on
Windows, `~/Library/Application Support/Claude/claude-code-sessions/...` on macOS, and
(best-effort) `${XDG_CONFIG_HOME:-~/.config}/Claude/claude-code-sessions/...` on Linux —
each linking to a transcript via `cliSessionId`. Cards are scoped by their **folder**
(account), so sessions from another account — or CLI/VS Code sessions with no card — don't
appear.

## How to run it
`restore-code-tab-sessions.ps1` (Windows) and `restore-code-tab-sessions.sh` (macOS/Linux)
live next to this file — same behavior, platform-conventional flag names.

1. Tell the user to **quit Claude Desktop completely** (including the system tray icon /
   menu bar → Quit). The app rewrites the card folder on exit, so it must be closed.
2. Run:
   ```powershell
   # Windows
   powershell -NoProfile -ExecutionPolicy Bypass -File "<path-to-skill>\restore-code-tab-sessions.ps1"
   ```
   ```bash
   # macOS / Linux — no extra install needed on a stock macOS; on Linux, make sure
   # jq / uuidgen / rsync are present first (e.g. `apt install jq uuid-runtime rsync`)
   bash "<path-to-skill>/restore-code-tab-sessions.sh"
   ```
3. Tell them to **reopen Claude Desktop → Code tab**. Sessions should be listed.

### Options
| Windows (`.ps1`) | macOS/Linux (`.sh`) | Effect |
|---|---|---|
| `-ExistingCardsOnly` | `--existing-cards-only` | Only migrate sessions **originally created in the Code tab** (copy existing cards from other accounts); skip CLI / VS Code sessions. Recommended when the user is simply moving between accounts and doesn't want CLI sessions listed. |
| `-DestRoot <path>` | `--dest-root <path>` | Dry run: write cards to a throwaway folder to inspect output first. |
| `-IgnoreRunning` | `--ignore-running` | Don't abort if Claude looks like it's running. |
| `-NoBackup` | `--no-backup` | Skip the backup (testing only). |

## What the script does (idempotent + reversible)
1. Backs up the entire card index to `…/claude-code-sessions_backup_<timestamp>`.
2. Auto-detects the logged-in account from `.claude.json` (`oauthAccount`).
3. Copies cards from other account folders into the current account's folder.
4. Unless `-ExistingCardsOnly`/`--existing-cards-only`, generates cards for transcripts that
   have none — using each transcript's `aiTitle` for the display name, written as UTF‑8 with
   no BOM.

## Safety guidance to give the user
- It only **adds** cards; it never edits or deletes transcripts.
- To undo: delete the added cards or restore the `_backup_` folder, then restart the app.
- Suggest also setting `"cleanupPeriodDays": 3650` in `~/.claude/settings.json`
  (`%USERPROFILE%\.claude\settings.json` on Windows) so old transcripts aren't auto-deleted
  (default 30 days).

## Fallback (no app needed)
Sessions can always be resumed on the CLI from the project's folder:
`claude --resume`, `claude --resume <sessionId>`, or `claude --continue`. The resume list is
scoped to the current folder, not the account.

## Companion: full backup & restore
The repo also ships `claude-code-backup-restore.ps1` (Windows) / `.sh` (macOS/Linux) — a
full local backup/restore of the user's transcripts (`~/.claude/projects`), the Code-tab
index, and `settings.json`. Suggest it for disaster recovery, moving machines, or guarding
against the 30-day transcript auto-cleanup. Back up:
`...-File .\claude-code-backup-restore.ps1 -Path D:\Backups` (Windows) or
`bash ./claude-code-backup-restore.sh --path ~/Backups` (macOS/Linux). Restore (merges,
never clobbers newer files unless `-Force`/`--force`):
`...-File .\claude-code-backup-restore.ps1 -Restore -Path "<backup-folder>"` or
`bash ./claude-code-backup-restore.sh --restore --path "<backup-folder>"`.

## Disclaimer
Unofficial; not affiliated with Anthropic. Works with on-disk files whose format was
determined by observation and may change between app versions. Backs up before writing.
