<#
  restore-code-tab-sessions.ps1
  --------------------------------------------------------------------------
  Make your Claude Code transcripts show up again in the Claude Desktop
  "Code" tab -- including after you log in with a DIFFERENT Claude account,
  or for sessions you started from the CLI / VS Code that never appeared.

  WHY SESSIONS GO MISSING
    The Code tab does not list transcripts directly. It lists per-session
    "cards" stored per-account at:
      %APPDATA%\Claude\claude-code-sessions\<accountId>\<orgId>\local_*.json
    Each card links to a real transcript through its "cliSessionId" field.
    Cards contain no account field -- only their FOLDER location scopes them.
    So sessions created under another account live in that account's folder
    and never show under your current login; CLI / VS Code sessions may have
    no card at all. (Transcripts themselves live, untouched, in
    %USERPROFILE%\.claude\projects\<encoded-cwd>\<sessionId>.jsonl and are
    never account-bound.)

  WHAT THIS DOES (idempotent + reversible)
    1. Backs up the whole card index first.
    2. Copies cards that exist under OTHER account folders into yours.
    3. (default) Generates fresh cards for transcripts that have none anywhere
       -- pulling each session's real title from its transcript.

  USAGE
    Close Claude Desktop completely (system tray too), then:
      powershell -NoProfile -ExecutionPolicy Bypass -File .\restore-code-tab-sessions.ps1

  OPTIONS
    -ExistingCardsOnly  Only migrate sessions that were ORIGINALLY created in
                        the desktop Code tab (copy existing cards from other
                        accounts). Skips CLI / VS Code sessions. Use this when
                        moving between accounts and you don't want CLI sessions.
    -DestRoot <path>    Write cards here instead of the live folder (testing).
    -IgnoreRunning      Don't abort if Claude appears to be running.
    -NoBackup           Skip the index backup (testing only).

  Windows + Windows PowerShell 5.1 (or PowerShell 7). Unofficial tool that
  works with documented-by-observation app files; backs up before writing and
  is fully reversible. Use at your own risk. MIT licensed.
#>
param(
  [switch]$ExistingCardsOnly,
  [string]$DestRoot,
  [switch]$IgnoreRunning,
  [switch]$NoBackup
)
$ErrorActionPreference = 'Stop'
$projRoot = Join-Path $env:USERPROFILE '.claude\projects'
$appBase  = Join-Path $env:APPDATA  'Claude\claude-code-sessions'

function Say($m,$c='Gray'){ Write-Host $m -ForegroundColor $c }
Say "== Claude Code -> Code-tab session restorer ==" 'White'

# 1) Claude must be closed (it rewrites this folder on exit)
if(-not $IgnoreRunning){
  $proc = Get-Process -Name 'Claude' -ErrorAction SilentlyContinue
  if($proc){ Say "Claude Desktop is still running (PID $($proc.Id -join ', ')). Close it COMPLETELY (check the system tray -> right-click -> Quit), then re-run." 'Yellow'; exit 1 }
}

# 2) Resolve destination = <accountId>\<orgId> for the logged-in account
if($DestRoot){
  $dest = $DestRoot
} else {
  $cjPath = Join-Path $env:USERPROFILE '.claude.json'
  if(-not (Test-Path $cjPath)){ Say "Can't find $cjPath -- is Claude Code installed for this user?" 'Yellow'; exit 1 }
  $cj = Get-Content $cjPath -Raw
  $m = [regex]::Match($cj, '"oauthAccount"\s*:\s*\{[\s\S]*?"accountUuid"\s*:\s*"([0-9a-fA-F\-]+)"[\s\S]*?"organizationUuid"\s*:\s*"([0-9a-fA-F\-]+)"')
  if(-not $m.Success){ Say "Couldn't read the logged-in account from .claude.json (are you signed in?)." 'Yellow'; exit 1 }
  $acct = $m.Groups[1].Value; $org = $m.Groups[2].Value
  $dest = Join-Path (Join-Path $appBase $acct) $org
  Say ("Logged-in account : {0}" -f $acct) 'Cyan'
  Say ("Organization      : {0}" -f $org)  'Cyan'
}
Say ("Target card folder: {0}" -f $dest) 'Cyan'
if(-not (Test-Path $dest)){ New-Item -ItemType Directory -Path $dest -Force | Out-Null }

# 3) Back up the entire card index
if(-not $NoBackup -and (Test-Path $appBase)){
  $bk = $appBase + '_backup_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
  Copy-Item $appBase $bk -Recurse -Force
  Say ("Backed up Code-tab index -> {0}" -f $bk) 'Green'
}

# --- helpers -------------------------------------------------------------
function Get-EpochMs($iso,$fileUtc){
  if($iso){ try { return ([DateTimeOffset]::Parse($iso,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal)).ToUnixTimeMilliseconds() } catch {} }
  return ([DateTimeOffset]$fileUtc).ToUnixTimeMilliseconds()
}
function Get-Meta($path){
  $cwd=$null;$created=$null;$ai=$null;$sum=$null;$usr=$null;$i=0
  foreach($line in [IO.File]::ReadLines($path)){
    $i++; if($i -gt 400){ break }
    if([string]::IsNullOrWhiteSpace($line)){ continue }
    $o=$null; try{ $o=$line|ConvertFrom-Json }catch{ continue }
    if(-not $created -and $o.timestamp){ $created=$o.timestamp }
    if(-not $cwd -and $o.cwd){ $cwd=$o.cwd }
    if(-not $ai -and $o.type -eq 'ai-title' -and $o.aiTitle){ $ai=$o.aiTitle }
    if(-not $sum -and $o.type -eq 'summary' -and $o.summary){ $sum=$o.summary }
    if(-not $usr -and $o.type -eq 'user' -and $o.message){
      $c=$o.message.content; $txt=$null
      if($c -is [string]){ $txt=$c } else { $txt=($c|Where-Object{ $_.type -eq 'text' }|Select-Object -First 1).text }
      if($txt -and $txt -notmatch '^\s*<' -and $txt -notmatch '^This session is being continued' -and $txt -notmatch '^\s*Caveat:' -and $txt -notmatch '^Base directory for this skill'){ $usr=$txt }
    }
    # stop early only once we have the ideal title (aiTitle); otherwise keep scanning for it
    if($cwd -and $created -and $ai){ break }
  }
  $title=$null
  if($ai){ $title=$ai } elseif($sum){ $title=($sum -replace '\s+',' ') } elseif($usr){ $title=($usr -replace '\s+',' ') }
  if($title -and $title.Length -gt 80){ $title=$title.Substring(0,80) }
  [pscustomobject]@{ cwd=$cwd; created=$created; title=$title }
}

# 4) Template for model/effort/MCP defaults (clone an existing card if present)
$tmplFile = Get-ChildItem $appBase -Recurse -Filter 'local_*.json' -File -ErrorAction SilentlyContinue | Sort-Object Length | Select-Object -First 1
$tmpl=$null; if($tmplFile){ try{ $tmpl=Get-Content $tmplFile.FullName -Raw|ConvertFrom-Json }catch{} }
$defModel  = if($tmpl -and $tmpl.model){ $tmpl.model } else { 'claude-opus-4-8' }
$defEffort = if($tmpl -and $tmpl.effort){ $tmpl.effort } else { 'high' }
$defChrome = if($tmpl -and $tmpl.chromePermissionMode){ $tmpl.chromePermissionMode } else { 'default' }
$defMcp    = if($tmpl){ $tmpl.remoteMcpServersConfig } else { $null }

# 5) cliSessionIds already carded in dest
$have=@{}
foreach($f in (Get-ChildItem $dest -Filter 'local_*.json' -File -ErrorAction SilentlyContinue)){
  $o=$null; try{ $o=Get-Content $f.FullName -Raw|ConvertFrom-Json }catch{}
  if($o -and $o.cliSessionId){ $have[$o.cliSessionId.ToString().ToLower()]=$true }
}

# 6) Copy cards from OTHER account/org folders into dest
$copied=0
foreach($f in (Get-ChildItem $appBase -Recurse -Filter 'local_*.json' -File -ErrorAction SilentlyContinue)){
  if($f.DirectoryName -ieq $dest){ continue }
  $o=$null; try{ $o=Get-Content $f.FullName -Raw|ConvertFrom-Json }catch{}
  if(-not $o -or -not $o.cliSessionId){ continue }
  $key=$o.cliSessionId.ToString().ToLower()
  if($have.ContainsKey($key)){ continue }
  $target = Join-Path $dest $f.Name
  if(Test-Path $target){ $target = Join-Path $dest ("local_{0}.json" -f [guid]::NewGuid()) }
  Copy-Item $f.FullName $target -Force
  $have[$key]=$true; $copied++
}
Say ("Copied {0} card(s) from other account folders." -f $copied) 'Green'

# 7) Generate cards for transcripts that still have none (unless -ExistingCardsOnly)
$generated=0;$skipped=0
if($ExistingCardsOnly){
  Say "-ExistingCardsOnly set: skipping generation for CLI / VS Code sessions." 'Yellow'
} else {
  $utf8 = New-Object System.Text.UTF8Encoding($false)   # UTF-8, no BOM
  Get-ChildItem $projRoot -Recurse -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Directory.Name -ne 'subagents' } | ForEach-Object {
    $cli=$_.BaseName; $key=$cli.ToLower()
    if($have.ContainsKey($key)){ $skipped++; return }
    $meta = Get-Meta $_.FullName
    $cwd  = if($meta.cwd){ $meta.cwd } else { '' }
    $created = Get-EpochMs $meta.created $_.CreationTimeUtc
    $last    = ([DateTimeOffset]$_.LastWriteTimeUtc).ToUnixTimeMilliseconds()
    $title   = $meta.title
    if(-not $title){ $leaf = if($cwd){ Split-Path $cwd -Leaf } else { 'session' }; $title = "$leaf (recovered)" }
    $guid = [guid]::NewGuid().ToString()
    $rec = [ordered]@{
      sessionId=("local_{0}" -f $guid); cliSessionId=$cli; cwd=$cwd; originCwd=$cwd
      lastFocusedAt=$last; createdAt=$created; lastActivityAt=$last
      model=$defModel; effort=$defEffort; isArchived=$false
      title=$title; titleSource='auto'; permissionMode='auto'
      remoteMcpServersConfig=$defMcp; chromePermissionMode=$defChrome
      completedTurns=1; alwaysAllowedReasons=$null; sessionPermissionUpdates=$null; classifierSummaryEnabled=$true
    }
    $json = ([pscustomobject]$rec) | ConvertTo-Json -Depth 64 -Compress
    [IO.File]::WriteAllText((Join-Path $dest ("local_{0}.json" -f $guid)), $json, $utf8)
    $have[$key]=$true; $generated++
  }
  Say ("Generated {0} new card(s); skipped {1} already present." -f $generated,$skipped) 'Green'
}

$total = (Get-ChildItem $dest -Filter 'local_*.json' -File -ErrorAction SilentlyContinue).Count
Say ("DONE. This account's Code tab now has {0} session card(s)." -f $total) 'White'
Say "Start Claude Desktop, open the Code tab -> your sessions should be listed." 'Cyan'
