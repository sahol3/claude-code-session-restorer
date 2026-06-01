# Contributing

Thanks for helping improve **Claude Code Session Restorer**! It's a small, focused, community
tool — contributions of every size are welcome, from typo fixes to a full macOS/Linux port.

> **Ground rule:** this project touches people's local Claude Code data. Every change must stay
> **safe by default** (back up first, never delete, never clobber newer data) and must **never**
> commit anyone's personal data.

## Good first contributions

- 🍎🐧 **macOS / Linux port** — the most-wanted. See *Porting to other OSes* below.
- 🐛 **App-version compatibility** — if a Claude Desktop update changes the card format or
  folder layout, a fix here helps everyone.
- 📝 **Docs** — clearer steps, troubleshooting, screenshots/GIFs.
- ✅ **Safer testing** — anything that makes it easier to verify before running against live data.

## Project layout

| File | What it is |
|------|------------|
| `restore-code-tab-sessions.ps1` | Rebuilds the per-account Code-tab session index. |
| `claude-code-backup-restore.ps1` | Full backup & restore of transcripts + index + settings. |
| `SKILL.md` | Claude skill wrapper. |
| `README.md` | User documentation. |

## How it works (reference for contributors)

Claude Code stores **transcripts** (the conversations) here, on every OS:

```
~/.claude/projects/<encoded-working-dir>/<sessionId>.jsonl
```

The Claude Desktop **Code tab** does not read those directly — it reads per-account "card"
files. On **Windows**:

```
%APPDATA%\Claude\claude-code-sessions\<accountId>\<organizationId>\local_<desktopId>.json
```

Each card links to a transcript through its `cliSessionId` field, and cards carry **no account
field** — they're scoped only by their folder. Notable fields:

| Field | Meaning |
|-------|---------|
| `sessionId` | Desktop card id (`local_<guid>`), also the filename. |
| `cliSessionId` | The transcript id — the `<sessionId>.jsonl` on disk. The link. |
| `cwd` / `originCwd` | Working directory. |
| `createdAt` / `lastActivityAt` / `lastFocusedAt` | Epoch milliseconds. |
| `title` / `titleSource` | Display title (we use the transcript's `aiTitle`). |
| `model`, `effort`, `permissionMode`, `isArchived` | Session settings. |
| `remoteMcpServersConfig` | Cached MCP config (cloned from an existing card). |

New cards must be written as **UTF-8 without a BOM**.

## Porting to other OSes

The transcript path (`~/.claude/projects/`) is the same everywhere — only the Code-tab card
index location differs. The values below are **unverified** — please confirm on a real install
and update the docs in your PR:

| OS | Likely card-index base |
|----|------------------------|
| Windows | `%APPDATA%\Claude\claude-code-sessions` |
| macOS | `~/Library/Application Support/Claude/claude-code-sessions` *(confirm)* |
| Linux | `~/.config/Claude/claude-code-sessions` *(confirm)* |

A port can be a Bash/Python script that mirrors the PowerShell logic, or a cross-platform
rewrite — just keep the same safety guarantees.

## Development & testing

**Never test against your only copy of your data.** Both scripts have safe dry-run paths:

```powershell
# Restorer: write cards to a throwaway folder instead of the live one
.\restore-code-tab-sessions.ps1 -DestRoot .\_dryrun -IgnoreRunning -NoBackup

# Backup/restore: back up to a temp folder (restore merges and won't clobber newer files)
.\claude-code-backup-restore.ps1 -Path .\_test
```

Checklist before opening a PR:

- [ ] Backs up before writing; **never deletes**; doesn't overwrite newer data without `-Force`.
- [ ] **Idempotent** — safe to run twice (no duplicate cards).
- [ ] Writes JSON as UTF-8 **without a BOM**.
- [ ] Windows scripts stay **Windows PowerShell 5.1**–compatible (no PS7-only syntax).
- [ ] Tested against a dry-run/temp folder — say what you tested in the PR.

## Privacy rules (important)

This repo must contain **zero** personal data. Before you commit:

- Never commit transcripts (`*.jsonl`), backups (`*_backup_*`), `.claude/`, or `.claude.json`
  — `.gitignore` already blocks these; don't override it.
- Never hardcode user paths, account/organization IDs, emails, or machine names. Use
  `$env:USERPROFILE`, `$env:APPDATA`, `$HOME`, etc.
- When filing issues, **redact** your account/organization IDs and email.

## Submitting changes

1. Fork and branch: `git checkout -b fix/short-description`.
2. Make the change and test it via a dry-run/temp folder.
3. Commit with a clear message and open a PR describing **what changed** and **how you tested it**.
4. For app-format changes, note the **Claude Desktop version** you observed.

Be kind in issues and reviews — assume good intent.

## License

By contributing, you agree your contributions are licensed under the [MIT License](./LICENSE).
