<#
  claude-code-backup-restore.ps1
  --------------------------------------------------------------------------
  Full local BACKUP & RESTORE for Claude Code on Windows. Protects/moves the
  data that actually matters:
    - %USERPROFILE%\.claude\projects          all session transcripts (.jsonl)
    - %APPDATA%\Claude\claude-code-sessions    the Code-tab card index
    - %USERPROFILE%\.claude\settings.json      your settings

  Use it for disaster recovery, moving to a new machine, before reinstalling,
  or to guard against the 30-day transcript auto-cleanup. Transcripts are
  account-independent, so a backup restores cleanly under ANY account.

  BACK UP (default)  -- writes claude-code-backup_<timestamp>\ under -Path
    powershell -NoProfile -ExecutionPolicy Bypass -File .\claude-code-backup-restore.ps1
    powershell ... -File .\claude-code-backup-restore.ps1 -Path D:\Backups

  RESTORE
    powershell ... -File .\claude-code-backup-restore.ps1 -Restore -Path "<backup-folder>"

  SAFETY
    - Restore MERGES: it never deletes, and by default never overwrites a NEWER
      local file (pass -Force to overwrite everything from the backup).
    - Close Claude Desktop before restoring the Code-tab index (it rewrites that
      folder on exit). The script skips the index if Claude is running.
    - After restoring transcripts under a different account, run
      restore-code-tab-sessions.ps1 so they appear in the Code tab.

  Options: -TranscriptsOnly (skip the Code-tab index), -Force, -IgnoreRunning.
  Windows + Windows PowerShell 5.1 / PowerShell 7. MIT. Unofficial; use at your own risk.
#>
param(
  [switch]$Restore,
  [string]$Path,
  [switch]$TranscriptsOnly,
  [switch]$Force,
  [switch]$IgnoreRunning
)
$ErrorActionPreference = 'Stop'
$projDir = Join-Path $env:USERPROFILE '.claude\projects'
$idxDir  = Join-Path $env:APPDATA  'Claude\claude-code-sessions'
$setFile = Join-Path $env:USERPROFILE '.claude\settings.json'

function Say($m,$c='Gray'){ Write-Host $m -ForegroundColor $c }
function Invoke-Robo($src,$dst,$extra){
  if(-not (Test-Path $src)){ return 'skipped (source not present)' }
  $rcArgs = @($src,$dst,'/E','/COPY:DAT','/R:1','/W:1','/NFL','/NDL','/NP','/NJH') + $extra
  robocopy @rcArgs | Out-Null
  if($LASTEXITCODE -ge 8){ return ("ERROR (robocopy code {0})" -f $LASTEXITCODE) }
  return 'ok'
}
function Test-ClaudeRunning(){ [bool](Get-Process -Name 'Claude' -ErrorAction SilentlyContinue) }

if($Restore){
  Say "== Claude Code RESTORE ==" 'White'
  if(-not $Path -or -not (Test-Path (Join-Path $Path 'projects'))){
    Say "Pass -Path to an existing backup folder (the one that contains a 'projects' subfolder)." 'Yellow'; exit 1
  }
  $xo = if($Force){ @() } else { @('/XO') }   # /XO = never overwrite a newer local file
  Say ("transcripts -> {0} : {1}" -f $projDir, (Invoke-Robo (Join-Path $Path 'projects') $projDir $xo)) 'Green'
  if(-not $TranscriptsOnly){
    if((Test-ClaudeRunning) -and -not $IgnoreRunning){
      Say "Skipping Code-tab index: Claude Desktop is running. Close it and re-run (or pass -IgnoreRunning) to restore the index." 'Yellow'
    } else {
      Say ("code-tab index -> {0} : {1}" -f $idxDir, (Invoke-Robo (Join-Path $Path 'claude-code-sessions') $idxDir $xo)) 'Green'
    }
  }
  $bset = Join-Path $Path 'settings.json'
  if((Test-Path $bset) -and -not (Test-Path $setFile)){ Copy-Item $bset $setFile -Force; Say "settings.json restored (was missing locally)." 'Green' }
  Say "Restore complete. If sessions don't appear in the Code tab, run restore-code-tab-sessions.ps1." 'Cyan'
  exit 0
}

# ---- BACKUP ----
Say "== Claude Code BACKUP ==" 'White'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$root  = if($Path){ $Path } else { $env:USERPROFILE }
if(-not (Test-Path $root)){ New-Item -ItemType Directory -Path $root -Force | Out-Null }
$dest = Join-Path $root ("claude-code-backup_" + $stamp)
New-Item -ItemType Directory -Path $dest -Force | Out-Null

Say ("transcripts    : {0}" -f (Invoke-Robo $projDir (Join-Path $dest 'projects') @())) 'Green'
if(-not $TranscriptsOnly){
  Say ("code-tab index : {0}" -f (Invoke-Robo $idxDir (Join-Path $dest 'claude-code-sessions') @())) 'Green'
}
if(Test-Path $setFile){ Copy-Item $setFile (Join-Path $dest 'settings.json') -Force; Say "settings.json  : ok" 'Green' }

$tx = Get-ChildItem (Join-Path $dest 'projects') -Recurse -Filter *.jsonl -File -ErrorAction SilentlyContinue
$mb = [math]::Round((($tx | Measure-Object Length -Sum).Sum)/1MB,1)
$mani = @(
  "Claude Code backup",
  ("created     : {0}" -f (Get-Date -Format 'u')),
  ("transcripts : {0} sessions, {1} MB" -f $tx.Count, $mb),
  "",
  "Restore with:",
  ('  powershell -NoProfile -ExecutionPolicy Bypass -File .\claude-code-backup-restore.ps1 -Restore -Path "' + $dest + '"')
)
[IO.File]::WriteAllLines((Join-Path $dest 'MANIFEST.txt'), $mani)
Say ("`nBacked up {0} transcript(s), {1} MB -> {2}" -f $tx.Count, $mb, $dest) 'White'
Say ('Restore later:  ...-File .\claude-code-backup-restore.ps1 -Restore -Path "' + $dest + '"') 'Cyan'
