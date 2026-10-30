#!/usr/bin/env bash
#
# claude-code-backup-restore.sh
# --------------------------------------------------------------------------
# macOS / Linux port of claude-code-backup-restore.ps1. Full local BACKUP &
# RESTORE for Claude Code. Protects/moves the data that actually matters:
#   - ~/.claude/projects                                  all transcripts (.jsonl)
#   - ~/Library/Application Support/Claude/claude-code-sessions   the Code-tab
#     card index (macOS); ${XDG_CONFIG_HOME:-~/.config}/Claude/claude-code-sessions
#     on Linux (best-effort, unverified -- see README)
#   - ~/.claude/settings.json                             your settings
#
# Use it for disaster recovery, moving to a new machine, before reinstalling,
# or to guard against the 30-day transcript auto-cleanup. Transcripts are
# account-independent, so a backup restores cleanly under ANY account.
#
# BACK UP (default) -- writes claude-code-backup_<timestamp>/ under --path
#   bash ./claude-code-backup-restore.sh
#   bash ./claude-code-backup-restore.sh --path ~/Backups
#
# RESTORE
#   bash ./claude-code-backup-restore.sh --restore --path "<backup-folder>"
#
# SAFETY
#   - Restore MERGES: it never deletes, and by default never overwrites a NEWER
#     local file (pass --force to overwrite everything from the backup).
#   - Close Claude Desktop before restoring the Code-tab index (it rewrites that
#     folder on exit). The script skips the index if Claude is running.
#   - After restoring transcripts under a different account, run
#     restore-code-tab-sessions.sh so they appear in the Code tab.
#
# Options: --transcripts-only (skip the Code-tab index), --force, --ignore-running.
# Requires: bash, rsync (both preinstalled on macOS; on Linux, rsync is nearly
# always preinstalled, otherwise e.g. `apt install rsync`). No sudo/admin needed.
# macOS: tested. Linux: best-effort / unverified (XDG card path).
# For Windows, use claude-code-backup-restore.ps1 instead. MIT. Unofficial;
# use at your own risk.
set -u

RESTORE=0
BPATH=""
TRANSCRIPTS_ONLY=0
FORCE=0
IGNORE_RUNNING=0

while [ $# -gt 0 ]; do
  case "$1" in
    --restore) RESTORE=1; shift ;;
    --path) BPATH="${2:-}"; shift 2 ;;
    --path=*) BPATH="${1#*=}"; shift ;;
    --transcripts-only) TRANSCRIPTS_ONLY=1; shift ;;
    --force) FORCE=1; shift ;;
    --ignore-running) IGNORE_RUNNING=1; shift ;;
    -h|--help)
      sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

UNAME=$(uname -s)
PROJ_DIR="$HOME/.claude/projects"
if [ "$UNAME" = "Darwin" ]; then
  IDX_DIR="$HOME/Library/Application Support/Claude/claude-code-sessions"
else
  XDG_BASE="${XDG_CONFIG_HOME:-$HOME/.config}"
  IDX_DIR="$XDG_BASE/Claude/claude-code-sessions"   # Linux, best-effort/unverified
fi
SET_FILE="$HOME/.claude/settings.json"

say() {
  local msg="$1" color="${2:-}"
  case "$color" in
    green)  printf '\033[32m%s\033[0m\n' "$msg" ;;
    yellow) printf '\033[33m%s\033[0m\n' "$msg" ;;
    cyan)   printf '\033[36m%s\033[0m\n' "$msg" ;;
    white)  printf '\033[1m%s\033[0m\n' "$msg" ;;
    *)      printf '%s\n' "$msg" ;;
  esac
}

# NOTE: GNU stat's -f means "show filesystem info" (not BSD's "-f FORMAT"), so
# it exits 0 with the wrong output instead of failing over -- branch on $UNAME
# explicitly rather than chaining with `||`.
get_size() {
  if [ "$UNAME" = "Darwin" ]; then stat -f %z "$1"; else stat -c %s "$1"; fi
}

is_claude_running() {
  if [ "$UNAME" = "Darwin" ]; then
    pgrep -x Claude >/dev/null 2>&1
  else
    pgrep -f Claude >/dev/null 2>&1   # Linux, best-effort (no official build to verify the process name)
  fi
}

# Native equivalent of robocopy /E /COPY:DAT [/XO]. $3=1 means "never
# overwrite a newer destination file" (/XO); otherwise overwrite unconditionally.
sync_tree() {
  local src="$1" dst="$2" noclobber="$3" out
  if [ ! -e "$src" ]; then printf 'skipped (source not present)'; return 0; fi
  mkdir -p "$dst"
  if [ "$noclobber" = "1" ]; then
    out=$(rsync -a --update "$src/" "$dst/" 2>&1)
  else
    out=$(rsync -a "$src/" "$dst/" 2>&1)
  fi
  if [ $? -eq 0 ]; then
    printf 'ok'
  else
    printf 'ERROR (%s)' "$(printf '%s' "$out" | tail -1)"
  fi
}

if [ "$RESTORE" = "1" ]; then
  say "== Claude Code RESTORE ==" white
  if [ -z "$BPATH" ] || [ ! -d "$BPATH/projects" ]; then
    say "Pass --path to an existing backup folder (the one that contains a 'projects' subfolder)." yellow
    exit 1
  fi
  noclobber=1
  [ "$FORCE" = "1" ] && noclobber=0
  res=$(sync_tree "$BPATH/projects" "$PROJ_DIR" "$noclobber")
  say "transcripts -> $PROJ_DIR : $res" green
  if [ "$TRANSCRIPTS_ONLY" != "1" ]; then
    if is_claude_running && [ "$IGNORE_RUNNING" != "1" ]; then
      say "Skipping Code-tab index: Claude Desktop is running. Close it and re-run (or pass --ignore-running) to restore the index." yellow
    else
      res=$(sync_tree "$BPATH/claude-code-sessions" "$IDX_DIR" "$noclobber")
      say "code-tab index -> $IDX_DIR : $res" green
    fi
  fi
  if [ -f "$BPATH/settings.json" ] && [ ! -f "$SET_FILE" ]; then
    mkdir -p "$(dirname "$SET_FILE")"
    cp "$BPATH/settings.json" "$SET_FILE"
    say "settings.json restored (was missing locally)." green
  fi
  say "Restore complete. If sessions don't appear in the Code tab, run restore-code-tab-sessions.sh." cyan
  exit 0
fi

# ---- BACKUP ----
say "== Claude Code BACKUP ==" white
stamp=$(date +%Y%m%d_%H%M%S)
root="${BPATH:-$HOME}"
mkdir -p "$root"
dest="$root/claude-code-backup_$stamp"
mkdir -p "$dest"

res=$(sync_tree "$PROJ_DIR" "$dest/projects" 0)
say "transcripts    : $res" green
if [ "$TRANSCRIPTS_ONLY" != "1" ]; then
  res=$(sync_tree "$IDX_DIR" "$dest/claude-code-sessions" 0)
  say "code-tab index : $res" green
fi
if [ -f "$SET_FILE" ]; then
  cp "$SET_FILE" "$dest/settings.json"
  say "settings.json  : ok" green
fi

tx_count=0
tx_bytes=0
if [ -d "$dest/projects" ]; then
  while IFS= read -r -d '' f; do
    tx_count=$((tx_count + 1))
    tx_bytes=$((tx_bytes + $(get_size "$f")))
  done < <(find "$dest/projects" -type f -name '*.jsonl' -print0 2>/dev/null)
fi
mb=$(awk -v b="$tx_bytes" 'BEGIN{printf "%.1f", b/1048576}')

{
  echo "Claude Code backup"
  echo "created     : $(date -u '+%Y-%m-%d %H:%M:%SZ')"
  echo "transcripts : $tx_count sessions, $mb MB"
  echo ""
  echo "Restore with:"
  echo "  bash ./claude-code-backup-restore.sh --restore --path \"$dest\""
} > "$dest/MANIFEST.txt"

say "" ''
say "Backed up $tx_count transcript(s), $mb MB -> $dest" white
say "Restore later:  ...--restore --path \"$dest\"" cyan
