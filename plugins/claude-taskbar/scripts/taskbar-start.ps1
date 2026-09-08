<#  SessionStart hook launcher (claude-taskbar plugin). Finds the claude.exe
    process that owns this session and the Windows Terminal hosting it, then
    starts taskbar-helper.ps1 hidden to watch them. Safe to run on every
    SessionStart (resume, /clear, compact): if a helper for this claude process
    is already running, it exits without starting another.
    Set CLAUDE_TASKBAR_TRAY_ICON=1 to also get a notification-area icon. #>
param(
    [int]$WatchPid = 0,
    [string]$Title = ""
)

$showNotificationIcon = ($env:CLAUDE_TASKBAR_TRAY_ICON -eq '1')

$ErrorActionPreference = 'SilentlyContinue'

# Hook input arrives as JSON on stdin; use cwd for the tooltip.
$cwd = ""
try {
    $raw = [Console]::In.ReadToEnd()
    if ($raw) { $cwd = ($raw | ConvertFrom-Json).cwd }
} catch {}

function Get-ParentPid([int]$id) {
    (Get-CimInstance Win32_Process -Filter "ProcessId=$id").ParentProcessId
}

# Walk up from this hook shell: first claude.exe, then the Windows Terminal hosting it.
$WtPid = 0
$cur = $PID
for ($i = 0; $i -lt 12; $i++) {
    $cur = Get-ParentPid $cur
    if (-not $cur) { break }
    $p = Get-Process -Id $cur
    if (-not $p) { break }
    # Auto-update renames the running binary to claude.exe.old.<ts>, so prefix-match.
    if (-not $WatchPid -and $p.ProcessName -match '^claude(\.|$)') { $WatchPid = $cur; continue }
    if ($WatchPid -and $p.ProcessName -eq 'WindowsTerminal') { $WtPid = $cur; break }
}
if (-not $WatchPid) { $WatchPid = Get-ParentPid $PID }
if (-not $WatchPid) { exit 0 }

if (-not $Title) {
    $Title = if ($cwd) { "Claude Code - " + (Split-Path $cwd -Leaf) } else { "Claude Code" }
}

# Pid files live outside the plugin cache so plugin updates never wipe them.
$runDir = Join-Path $env:LOCALAPPDATA 'claude-taskbar'
New-Item -ItemType Directory -Force $runDir | Out-Null
$pidFile = Join-Path $runDir "$WatchPid.pid"

# Already have a live tray helper for this claude process? Then nothing to do.
if (Test-Path $pidFile) {
    $existing = [int](Get-Content $pidFile -Raw).Trim()
    $ep = Get-Process -Id $existing
    if ($ep -and $ep.ProcessName -match '^(pwsh|powershell)$') { exit 0 }
    Remove-Item $pidFile -Force
}

$shell = (Get-Command pwsh).Source
if (-not $shell) { $shell = (Get-Command powershell).Source }
$script = Join-Path $PSScriptRoot 'taskbar-helper.ps1'

$args = @(
    '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
    '-File', "`"$script`"",
    '-WatchPid', $WatchPid,
    '-WtPid', $WtPid,
    '-Title', "`"$Title`"",
    '-PidFile', "`"$pidFile`""
)
if (-not $showNotificationIcon) { $args += '-NoTrayIcon' }
$proc = Start-Process -FilePath $shell -ArgumentList $args -WindowStyle Hidden -PassThru
if ($proc) { Set-Content -Path $pidFile -Value $proc.Id -NoNewline }
exit 0
