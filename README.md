# Claude Code Session Restorer — fix missing sessions in the Claude Desktop "Code" tab

Restore Claude Code chat sessions that disappeared from the **Claude Desktop "Code" tab** —
most commonly **after logging in with a different Claude account**, or for sessions you
started from the **CLI / VS Code** that never showed up in the app. A safe, **reversible**
Windows PowerShell tool (also packaged as a Claude skill).

![Platform](https://img.shields.io/badge/platform-Windows-blue)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)

> **TL;DR** — Your conversations were never deleted. The Code tab just can't see them
> because its session list is stored **per account**. This rebuilds the list for the
> account you're currently logged into. Run it with Claude Desktop closed.

---

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
%USERPROFILE%\.claude\projects\<encoded-working-dir>\<sessionId>.jsonl
```

These transcripts are keyed by **project folder** and carry **no account information** —
switching accounts never touches them.

But the **Code tab doesn't read those transcripts directly.** It reads small per-session
"card" files, stored **per account**:

```
%APPDATA%\Claude\claude-code-sessions\<accountId>\<organizationId>\local_*.json
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

1. **Quit Claude Desktop completely.** Also check the system tray → right-click → **Quit**.
   (The app rewrites this folder when it exits, so it must be closed.)
2. Open **PowerShell** and run:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\restore-code-tab-sessions.ps1
   ```

3. **Reopen Claude Desktop → Code tab.** Your sessions should be listed.

### Options

| Flag | Effect |
|------|--------|
| `-ExistingCardsOnly` | Only migrate sessions **originally created in the desktop Code tab** (copy existing cards from other accounts). **Skips CLI / VS Code sessions.** Use this when moving between accounts and you don't want CLI sessions cluttering the list. |
| `-DestRoot <path>` | Write cards to a throwaway folder instead of the live one (dry run / testing). |
| `-IgnoreRunning` | Don't abort if Claude appears to be running. |
| `-NoBackup` | Skip the index backup (testing only). |

Example — migrate only real Code-tab sessions between accounts:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\restore-code-tab-sessions.ps1 -ExistingCardsOnly
```

## Is it safe? Can I undo it?

- **Backup first:** before writing anything, it copies the whole index to
  `…\claude-code-sessions_backup_<timestamp>`.
- **Non-destructive:** it only *adds* cards; it never edits or deletes your transcripts.
- **To undo:** delete the cards it added (or restore the `_backup_` folder over
  `claude-code-sessions`), then restart Claude Desktop.

It's also wise to back up `%USERPROFILE%\.claude\projects` (your actual transcripts) once,
independent of this tool.

## A note on transcript retention

Claude Code auto-deletes old transcripts after a number of days (`cleanupPeriodDays`,
default 30). To keep history longer, add this to `%USERPROFILE%\.claude\settings.json`:

```json
{ "cleanupPeriodDays": 3650 }
```

## Resuming without the app

Independently of the Code tab, you can always resume on the command line. From the
project's folder:

```powershell
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

- **Windows** + Windows PowerShell 5.1 or PowerShell 7.
- macOS / Linux use the same card concept under different paths
  (e.g. `~/Library/Application Support/Claude/…` on macOS). Ports/PRs welcome.

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
