#!/usr/bin/env bash
#
# restore-code-tab-sessions.sh
# --------------------------------------------------------------------------
# macOS / Linux port of restore-code-tab-sessions.ps1. Makes your Claude Code
# transcripts show up again in the Claude Desktop "Code" tab -- including
# after you log in with a DIFFERENT Claude account, or for sessions started
# from the CLI / VS Code that never appeared.
#
# WHY SESSIONS GO MISSING
#   The Code tab does not list transcripts directly. It lists per-session
#   "cards" stored per-account at:
#     ~/Library/Application Support/Claude/claude-code-sessions/<accountId>/<orgId>/local_*.json   (macOS)
#     ${XDG_CONFIG_HOME:-~/.config}/Claude/claude-code-sessions/...                                  (Linux, best-effort)
#   Each card links to a real transcript through its "cliSessionId" field.
#   Cards contain no account field -- only their FOLDER location scopes them.
#   So sessions created under another account live in that account's folder
#   and never show under your current login; CLI / VS Code sessions may have
#   no card at all. (Transcripts themselves live, untouched, in
#   ~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl and are never
#   account-bound.)
#
# WHAT THIS DOES (idempotent + reversible)
#   1. Backs up the whole card index first.
#   2. Copies cards that exist under OTHER account folders into yours.
#   3. (default) Generates fresh cards for transcripts that have none anywhere
#      -- pulling each session's real title from its transcript.
#
# USAGE
#   Close Claude Desktop completely, then:
#     bash ./restore-code-tab-sessions.sh
#
# OPTIONS
#   --existing-cards-only  Only migrate sessions that were ORIGINALLY created in
#                          the desktop Code tab (copy existing cards from other
#                          accounts). Skips CLI / VS Code sessions. Use this when
#                          moving between accounts and you don't want CLI sessions.
#   --dest-root <path>     Write cards here instead of the live folder (testing).
#   --ignore-running       Don't abort if Claude appears to be running.
#   --no-backup            Skip the index backup (testing only).
#
# Requires: bash, jq, uuidgen. uuidgen is preinstalled on every macOS version;
# jq ships at /usr/bin/jq on macOS 15+ (run `brew install jq` on macOS 14 and
# earlier). On Linux: `apt install jq uuid-runtime` or equivalent. No
# sudo/admin needed.
# macOS: tested. Linux: best-effort / unverified (XDG card path).
# For Windows, use restore-code-tab-sessions.ps1 instead. Unofficial tool that
# works with documented-by-observation app files; backs up before writing and
# is fully reversible. Use at your own risk. MIT licensed.
set -u

EXISTING_CARDS_ONLY=0
DEST_ROOT=""
IGNORE_RUNNING=0
NO_BACKUP=0

while [ $# -gt 0 ]; do
  case "$1" in
    --existing-cards-only) EXISTING_CARDS_ONLY=1; shift ;;
    --dest-root)
      if [ $# -lt 2 ]; then echo "--dest-root requires a path argument" >&2; exit 1; fi
      DEST_ROOT="$2"; shift 2 ;;
    --dest-root=*) DEST_ROOT="${1#*=}"; shift ;;
    --ignore-running) IGNORE_RUNNING=1; shift ;;
    --no-backup) NO_BACKUP=1; shift ;;
    -h|--help)
      sed -n '2,42p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

for dep in jq uuidgen; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    echo "This script needs '$dep'. Install it (e.g. 'brew install $dep' on macOS, 'apt install $dep' / 'apt install uuid-runtime' on Linux) and re-run." >&2
    exit 1
  fi
done

UNAME=$(uname -s)
PROJ_ROOT="$HOME/.claude/projects"
if [ "$UNAME" = "Darwin" ]; then
  APP_BASE="$HOME/Library/Application Support/Claude/claude-code-sessions"
else
  XDG_BASE="${XDG_CONFIG_HOME:-$HOME/.config}"
  APP_BASE="$XDG_BASE/Claude/claude-code-sessions"   # Linux, best-effort/unverified
fi

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
lower() { tr '[:upper:]' '[:lower:]'; }
new_guid() { uuidgen | lower; }

say "== Claude Code -> Code-tab session restorer ==" white

# 1) Claude must be closed (it rewrites this folder on exit)
if [ "$IGNORE_RUNNING" != "1" ]; then
  if [ "$UNAME" = "Darwin" ]; then
    pids=$(pgrep -x Claude || true)
  else
    pids=$(pgrep -f Claude || true)   # Linux, best-effort
  fi
  if [ -n "$pids" ]; then
    say "Claude Desktop is still running (PID $(printf '%s' "$pids" | tr '\n' ' ')). Close it COMPLETELY (check the menu bar / system tray -> Quit), then re-run." yellow
    exit 1
  fi
fi

# 2) Resolve destination = <accountId>/<orgId> for the logged-in account
if [ -n "$DEST_ROOT" ]; then
  dest="$DEST_ROOT"
else
  cj_path="$HOME/.claude.json"
  if [ ! -f "$cj_path" ]; then
    say "Can't find $cj_path -- is Claude Code installed for this user?" yellow
    exit 1
  fi
  acct=$(jq -r '.oauthAccount.accountUuid // empty' "$cj_path" 2>/dev/null)
  org=$(jq -r '.oauthAccount.organizationUuid // empty' "$cj_path" 2>/dev/null)
  if [ -z "$acct" ] || [ -z "$org" ]; then
    say "Couldn't read the logged-in account from .claude.json (are you signed in?)." yellow
    exit 1
  fi
  dest="$APP_BASE/$acct/$org"
  say "Logged-in account : $acct" cyan
  say "Organization      : $org" cyan
fi
say "Target card folder: $dest" cyan
mkdir -p "$dest"

# 3) Back up the entire card index
if [ "$NO_BACKUP" != "1" ] && [ -d "$APP_BASE" ]; then
  bk="${APP_BASE}_backup_$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$bk"
  if ! cp -Rp "$APP_BASE/." "$bk/"; then
    say "Index backup failed or is incomplete: $bk. Stopped before copying cards." yellow
    exit 1
  fi
  say "Backed up Code-tab index -> $bk" green
fi

# --- helpers -------------------------------------------------------------
# NOTE: GNU stat's -f means "show filesystem info" (not BSD's "-f FORMAT"), so
# it exits 0 with the wrong output instead of failing over -- branch on $UNAME
# explicitly rather than chaining with `||`.
get_size() {
  if [ "$UNAME" = "Darwin" ]; then stat -f %z "$1"; else stat -c %s "$1"; fi
}
get_mtime_epoch() {
  if [ "$UNAME" = "Darwin" ]; then stat -f %m "$1"; else stat -c %Y "$1"; fi
}
get_ctime_epoch() {
  local t
  if [ "$UNAME" = "Darwin" ]; then
    t=$(stat -f %B "$1" 2>/dev/null) || t=""
  else
    t=$(stat -c %W "$1" 2>/dev/null) || t=""   # GNU: birth time, "0" or "-" if unsupported by the fs
  fi
  if [ -n "$t" ] && [ "$t" != "0" ] && [ "$t" != "-" ]; then printf '%s' "$t"; else get_mtime_epoch "$1"; fi
}
iso_to_epoch_ms() {
  local iso="$1" clean secs
  clean=$(printf '%s' "$iso" | sed -E 's/\.[0-9]+Z$/Z/; s/\.[0-9]+$//')
  secs=$(jq -n --arg t "$clean" 'try ($t | fromdateiso8601) catch empty' 2>/dev/null)
  if [ -n "$secs" ] && [ "$secs" != "null" ]; then printf '%s' $((secs * 1000)); fi
}
# Reads up to the first 400 lines of a transcript, sets META_CWD/META_CREATED_ISO/META_TITLE.
get_meta() {
  local file="$1" i=0 line ai="" summ="" usr="" t c a s u
  META_CWD=""; META_CREATED_ISO=""; META_TITLE=""
  while IFS= read -r line && [ "$i" -lt 400 ]; do
    i=$((i + 1))
    [ -z "$line" ] && continue
    printf '%s' "$line" | jq -e . >/dev/null 2>&1 || continue
    if [ -z "$META_CREATED_ISO" ]; then
      t=$(printf '%s' "$line" | jq -r '.timestamp // empty' 2>/dev/null)
      [ -n "$t" ] && META_CREATED_ISO="$t"
    fi
    if [ -z "$META_CWD" ]; then
      c=$(printf '%s' "$line" | jq -r '.cwd // empty' 2>/dev/null)
      [ -n "$c" ] && META_CWD="$c"
    fi
    if [ -z "$ai" ]; then
      a=$(printf '%s' "$line" | jq -r 'select(.type=="ai-title") | .aiTitle // empty' 2>/dev/null)
      [ -n "$a" ] && ai="$a"
    fi
    if [ -z "$summ" ]; then
      s=$(printf '%s' "$line" | jq -r 'select(.type=="summary") | .summary // empty' 2>/dev/null)
      [ -n "$s" ] && summ="$s"
    fi
    if [ -z "$usr" ]; then
      u=$(printf '%s' "$line" | jq -r '
        select(.type=="user" and .message != null) | .message.content as $c |
        if ($c|type)=="string" then $c
        else ([$c[]? | select(.type=="text") | .text][0] // empty) end
      ' 2>/dev/null)
      if [ -n "$u" ] && ! printf '%s' "$u" | grep -qE '^[[:space:]]*<|^This session is being continued|^[[:space:]]*Caveat:|^Base directory for this skill'; then
        usr="$u"
      fi
    fi
    if [ -n "$META_CWD" ] && [ -n "$META_CREATED_ISO" ] && [ -n "$ai" ]; then break; fi
  done < "$file"

  if [ -n "$ai" ]; then META_TITLE="$ai"
  elif [ -n "$summ" ]; then META_TITLE=$(printf '%s' "$summ" | tr -s '[:space:]' ' ')
  elif [ -n "$usr" ]; then META_TITLE=$(printf '%s' "$usr" | tr -s '[:space:]' ' ')
  fi
  if [ -n "$META_TITLE" ] && [ "${#META_TITLE}" -gt 80 ]; then
    META_TITLE="${META_TITLE:0:80}"
  fi
}

# 4) Template for model/effort/MCP defaults (clone an existing card if present)
tmpl_file=""; tmpl_size=-1
if [ -d "$APP_BASE" ]; then
  while IFS= read -r -d '' f; do
    sz=$(get_size "$f")
    if [ "$tmpl_size" -lt 0 ] || [ "$sz" -lt "$tmpl_size" ]; then tmpl_size="$sz"; tmpl_file="$f"; fi
  done < <(find "$APP_BASE" -type f -name 'local_*.json' -print0 2>/dev/null)
fi
DEF_MODEL="claude-opus-4-8"; DEF_EFFORT="high"; DEF_CHROME="default"; DEF_MCP_JSON="null"
if [ -n "$tmpl_file" ]; then
  v=$(jq -r '.model // empty' "$tmpl_file" 2>/dev/null); [ -n "$v" ] && DEF_MODEL="$v"
  v=$(jq -r '.effort // empty' "$tmpl_file" 2>/dev/null); [ -n "$v" ] && DEF_EFFORT="$v"
  v=$(jq -r '.chromePermissionMode // empty' "$tmpl_file" 2>/dev/null); [ -n "$v" ] && DEF_CHROME="$v"
  v=$(jq -c '.remoteMcpServersConfig // null' "$tmpl_file" 2>/dev/null); [ -n "$v" ] && DEF_MCP_JSON="$v"
fi

# 5) cliSessionIds already carded in dest (plain-text set -- stays compatible with bash 3.2 on macOS)
HAVE_FILE=$(mktemp)
trap 'rm -f "$HAVE_FILE"' EXIT
if [ -d "$dest" ]; then
  while IFS= read -r -d '' f; do
    key=$(jq -r '.cliSessionId // empty' "$f" 2>/dev/null | lower)
    [ -n "$key" ] && printf '%s\n' "$key" >> "$HAVE_FILE"
  done < <(find "$dest" -maxdepth 1 -type f -name 'local_*.json' -print0 2>/dev/null)
fi
have() { grep -Fxq "$1" "$HAVE_FILE" 2>/dev/null; }
add_have() { printf '%s\n' "$1" >> "$HAVE_FILE"; }

# 6) Copy cards from OTHER account/org folders into dest
copied=0
if [ -d "$APP_BASE" ]; then
  while IFS= read -r -d '' f; do
    [ "$(dirname "$f")" = "$dest" ] && continue
    key=$(jq -r '.cliSessionId // empty' "$f" 2>/dev/null | lower)
    [ -z "$key" ] && continue
    have "$key" && continue
    target="$dest/$(basename "$f")"
    if [ -e "$target" ]; then target="$dest/local_$(new_guid).json"; fi
    if cp "$f" "$target"; then
      add_have "$key"
      copied=$((copied + 1))
    else
      say "Failed to copy $f to $target." yellow
    fi
  done < <(find "$APP_BASE" -type f -name 'local_*.json' -print0 2>/dev/null)
fi
say "Copied $copied card(s) from other account folders." green

# 7) Generate cards for transcripts that still have none (unless --existing-cards-only)
generated=0; skipped=0
if [ "$EXISTING_CARDS_ONLY" = "1" ]; then
  say "--existing-cards-only set: skipping generation for CLI / VS Code sessions." yellow
else
  if [ -d "$PROJ_ROOT" ]; then
    while IFS= read -r -d '' f; do
      [ "$(basename "$(dirname "$f")")" = "subagents" ] && continue
      base=$(basename "$f" .jsonl)
      key=$(printf '%s' "$base" | lower)
      if have "$key"; then skipped=$((skipped + 1)); continue; fi

      get_meta "$f"
      cwd="$META_CWD"
      created_ms=""
      [ -n "$META_CREATED_ISO" ] && created_ms=$(iso_to_epoch_ms "$META_CREATED_ISO")
      if [ -z "$created_ms" ]; then created_ms=$(( $(get_ctime_epoch "$f") * 1000 )); fi
      last_ms=$(( $(get_mtime_epoch "$f") * 1000 ))

      title="$META_TITLE"
      if [ -z "$title" ]; then
        if [ -n "$cwd" ]; then leaf=$(basename "$cwd"); else leaf="session"; fi
        title="$leaf (recovered)"
      fi

      guid=$(new_guid)
      jq -n \
        --arg sessionId "local_$guid" --arg cliSessionId "$base" --arg cwd "$cwd" \
        --argjson createdAt "$created_ms" --argjson lastActivityAt "$last_ms" --argjson lastFocusedAt "$last_ms" \
        --arg model "$DEF_MODEL" --arg effort "$DEF_EFFORT" --arg title "$title" \
        --arg chromePermissionMode "$DEF_CHROME" --argjson remoteMcpServersConfig "$DEF_MCP_JSON" \
        '{
          sessionId: $sessionId, cliSessionId: $cliSessionId, cwd: $cwd, originCwd: $cwd,
          lastFocusedAt: $lastFocusedAt, createdAt: $createdAt, lastActivityAt: $lastActivityAt,
          model: $model, effort: $effort, isArchived: false,
          title: $title, titleSource: "auto", permissionMode: "auto",
          remoteMcpServersConfig: $remoteMcpServersConfig, chromePermissionMode: $chromePermissionMode,
          completedTurns: 1, alwaysAllowedReasons: null, sessionPermissionUpdates: null, classifierSummaryEnabled: true
        }' > "$dest/local_$guid.json"

      add_have "$key"
      generated=$((generated + 1))
    done < <(find "$PROJ_ROOT" -type f -name '*.jsonl' -print0 2>/dev/null)
  fi
  say "Generated $generated new card(s); skipped $skipped already present." green
fi

total=$(find "$dest" -maxdepth 1 -type f -name 'local_*.json' 2>/dev/null | wc -l | tr -d ' ')
say "DONE. This account's Code tab now has $total session card(s)." white
say "Start Claude Desktop, open the Code tab -> your sessions should be listed." cyan
