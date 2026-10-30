# Claude Code Session Restorer — fix missing sessions in the Claude Desktop "Code" tab

Restore Claude Code chat sessions that disappeared from the **Claude Desktop "Code" tab** —
most commonly **after logging in with a different Claude account**, or for sessions you
started from the **CLI / VS Code** that never showed up in the app. A safe, **reversible**
tool for Windows (PowerShell), macOS, and Linux (Bash) — also packaged as a Claude skill.

![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-blue)
![License](https://img.shields.io/badge/license-MIT-green)

> **TL;DR** — Your conversations were never deleted. The Code tab just can't see them
> because its session list is stored **per account**. This rebuilds the list for the
> account you're currently logged into. Run it with Claude Desktop closed.

---

## What's included

Each tool ships as two implementations — PowerShell for Windows, Bash for macOS/Linux —
with the same behavior, options, and safety guarantees:

| Script | Use it when |
|--------|-------------|
| **`restore-code-tab-sessions.ps1`** (Windows) / **`restore-code-tab-sessions.sh`** (macOS/Linux) | Your transcripts exist but don't show in the Code tab (you switched accounts, or started sessions from the CLI / VS Code). Rebuilds the per-account session index. |
| **`claude-code-backup-restore.ps1`** (Windows) / **`claude-code-backup-restore.sh`** (macOS/Linux) | You want a full backup of your transcripts + index (disaster recovery, new machine, before reinstalling, or to beat the 30-day auto-cleanup) — and to restore it anywhere. |

## The problem

You open Claude Desktop, switch to the **Code** tab… and most of your sessions are gone.
This typically happens when:

- you **logged into a different Claude account** (the Code tab only lists the *current*
  account's sessions);
- you **logged out and back in**, or reinstalled;
- you started sessions from the **`claude` CLI or the VS Code extension**, and they never
  appeared in the desktop app.

The conversations themselves are **not lost** — only the app's *index* of them.

## Why it happens

Claude Code stores every conversation as a transcript on disk:

```
~/.claude/projects/<encoded-working-dir>/<sessionId>.jsonl              (macOS/Linux)
%USERPROFILE%\.claude\projects\<encoded-working-dir>\<sessionId>.jsonl  (Windows)
```

These transcripts are keyed by **project folder** and carry **no account information** —
switching accounts never touches them.

But the **Code tab doesn't read those transcripts directly.** It reads small per-session
"card" files, stored **per account** (see [Compatibility](#compatibility) for the exact
path per OS):

```
%APPDATA%\Claude\claude-code-sessions\<accountId>\<organizationId>\local_*.json   (Windows)
~/Library/Application Support/Claude/claude-code-sessions/<accountId>/<organizationId>/local_*.json  (macOS)
```

Each card points back to a transcript via a `cliSessionId` field. The cards contain **no
account field** — they're scoped purely by which account folder they live in. So:

- sessions created under **another account** sit in *that* account's folder → invisible now;
- sessions started from the **CLI / VS Code** often have **no card at all** → never listed.

## What this tool does

Run with Claude Desktop closed, it will (all **idempotent** and **reversible**):

1. **Back up** the entire Code-tab card index first.
2. **Copy** cards that exist under other account folders into your current account's folder.
3. **Generate** fresh cards for transcripts that have no card anywhere — reading each
   session's real title straight from its transcript (`aiTitle`).

It auto-detects your currently logged-in account from `.claude.json`, so you don't pass
any IDs. Re-running is safe — it never creates duplicates.

## Usage

1. **Quit Claude Desktop completely.** Also check the system tray / menu bar → **Quit**.
   (The app rewrites this folder when it exits, so it must be closed.)
2. Run it:

   ```powershell
   # Windows
   powershell -NoProfile -ExecutionPolicy Bypass -File .\restore-code-tab-sessions.ps1
   ```

   ```bash
   # macOS / Linux
   bash ./restore-code-tab-sessions.sh
   ```

3. **Reopen Claude Desktop → Code tab.** Your sessions should be listed.

### Options

The two implementations take the same options under platform-conventional names:

| Windows (`.ps1`) | macOS/Linux (`.sh`) | Effect |
|---|---|---|
| `-ExistingCardsOnly` | `--existing-cards-only` | Only migrate sessions **originally created in the desktop Code tab** (copy existing cards from other accounts). **Skips CLI / VS Code sessions.** Use this when moving between accounts and you don't want CLI sessions cluttering the list. |
| `-DestRoot <path>` | `--dest-root <path>` | Write cards to a throwaway folder instead of the live one (dry run / testing). |
| `-IgnoreRunning` | `--ignore-running` | Don't abort if Claude appears to be running. |
| `-NoBackup` | `--no-backup` | Skip the index backup (testing only). |

Example — migrate only real Code-tab sessions between accounts:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\restore-code-tab-sessions.ps1 -ExistingCardsOnly
```

```bash
bash ./restore-code-tab-sessions.sh --existing-cards-only
```

## Is it safe? Can I undo it?

- **Backup first:** before writing anything, it copies the whole index to
  `…/claude-code-sessions_backup_<timestamp>`.
- **Non-destructive:** it only *adds* cards; it never edits or deletes your transcripts.
- **To undo:** delete the cards it added (or restore the `_backup_` folder over
  `claude-code-sessions`), then restart Claude Desktop.

It's also wise to back up `~/.claude/projects` (your actual transcripts) once, independent
of this tool.

## A note on transcript retention

Claude Code auto-deletes old transcripts after a number of days (`cleanupPeriodDays`,
default 30). To keep history longer, add this to `~/.claude/settings.json`
(`%USERPROFILE%\.claude\settings.json` on Windows):

```json
{ "cleanupPeriodDays": 3650 }
```

## Full backup & restore (the "everything" tool)

`claude-code-backup-restore.ps1` / `.sh` backs up and restores everything that matters —
your **transcripts** (`~/.claude/projects`), the **Code-tab index**, and `settings.json`.
Transcripts carry no account info, so a backup restores cleanly under **any account, on
any machine**.

**Back up** (creates `claude-code-backup_<timestamp>/` under the path you choose; defaults
to your home folder):

```powershell
# Windows
powershell -NoProfile -ExecutionPolicy Bypass -File .\claude-code-backup-restore.ps1 -Path D:\Backups
```

```bash
# macOS / Linux
bash ./claude-code-backup-restore.sh --path ~/Backups
```

**Restore** (merges; it never deletes, and won't overwrite a newer local file unless you
pass `-Force` / `--force`):

```powershell
# Windows
powershell -NoProfile -ExecutionPolicy Bypass -File .\claude-code-backup-restore.ps1 -Restore -Path "D:\Backups\claude-code-backup_YYYYMMDD_HHMMSS"
```

```bash
# macOS / Linux
bash ./claude-code-backup-restore.sh --restore --path "~/Backups/claude-code-backup_YYYYMMDD_HHMMSS"
```

Close Claude Desktop before restoring the Code-tab index (the script skips it automatically
if Claude is running). Options: `-TranscriptsOnly`/`--transcripts-only`, `-Force`/`--force`,
`-IgnoreRunning`/`--ignore-running`. After restoring under a different account, run
`restore-code-tab-sessions.ps1`/`.sh` to make the sessions appear in the Code tab.

## Resuming without the app

Independently of the Code tab, you can always resume on the command line. From the
project's folder:

```bash
claude --resume            # pick from a list
claude --resume <sessionId>
claude --continue          # most recent session in this folder
```

The resume list is scoped to the **current folder**, not the account.

## Use as a Claude skill

This repo doubles as a Claude skill — see [`SKILL.md`](./SKILL.md). Drop the folder into
your skills directory and Claude can run the restore for you when you say things like
*"my Claude Code sessions disappeared after switching accounts."*

## Compatibility

- **Windows**: `restore-code-tab-sessions.ps1` / `claude-code-backup-restore.ps1` — Windows
  PowerShell 5.1 or PowerShell 7. No extra install needed.
- **macOS**: `restore-code-tab-sessions.sh` / `claude-code-backup-restore.sh` — plain Bash,
  plus `jq`, `uuidgen`, and `rsync`. All three are already present on a stock macOS install
  (recent macOS even ships `jq` at `/usr/bin/jq`); if `jq` is missing, `brew install jq`
  gets it with no admin prompt. Verified against the real on-disk layout: card index at
  `~/Library/Application Support/Claude/claude-code-sessions/…`, transcripts and settings
  at `~/.claude/…`.
- **Linux**: same `.sh` scripts and dependencies as macOS (`jq`, `uuidgen` — usually from
  `uuid-runtime` — and `rsync`; install via your package manager if any are missing, e.g.
  `apt install jq uuid-runtime rsync`). The card index path follows the XDG convention used
  by known community Linux builds of Claude Desktop —
  `${XDG_CONFIG_HOME:-~/.config}/Claude/claude-code-sessions/…` — but this **has not been
  verified against a real install** (there's no official Linux build, and this machine
  can't test one). If your Linux install uses a different path, open an issue or PR with
  the real location.

The `.sh` scripts use `rsync -a`/`--update` in place of Windows's `robocopy /E /COPY:DAT`/
`/XO` for the full backup/restore tool — same contract (recursive, preserves timestamps,
never overwrites a newer destination file on restore unless you pass `--force`).

## How it works (technical)

A Code-tab card (`local_<desktopId>.json`) is a small JSON object. The fields that matter:

| Field | Meaning |
|-------|---------|
| `sessionId` | The desktop card id (`local_<guid>`), also the filename. |
| `cliSessionId` | The **transcript** id — the `<sessionId>.jsonl` on disk. This is the link. |
| `cwd` / `originCwd` | Working directory of the session. |
| `createdAt` / `lastActivityAt` / `lastFocusedAt` | Epoch milliseconds. |
| `title` / `titleSource` | Display title (we use the transcript's `aiTitle`). |
| `model`, `effort`, `permissionMode`, `isArchived` | Session settings. |
| `remoteMcpServersConfig` | Cached MCP server config (cloned from an existing card). |

To surface a transcript, the tool ensures a card with the matching `cliSessionId` exists in
the current account's folder — copying it from another account when one exists, or building
a fresh one (UTF‑8, no BOM) when it doesn't.

## Disclaimer

Unofficial, community tool. It is **not** affiliated with or endorsed by Anthropic. It works
with on-disk files whose format was determined by observation and may change between app
versions. It backs up before writing and is reversible, but you use it at your own risk.

## License

[MIT](./LICENSE)
