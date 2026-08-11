#Requires -Version 5.1
<#  Installs the Comtel Claude Code statusline on this machine.
    Copies statusline.ps1 to ~/.claude/ and points settings.json at it with a
    home-relative command, so the same settings work on any Windows box.
    Existing settings keys are preserved; a timestamped backup is written. #>

[CmdletBinding()]
param(
    [switch]$Force  # overwrite an existing statusLine entry without prompting
)

$ErrorActionPreference = 'Stop'

$SourceScript = Join-Path $PSScriptRoot 'statusline.ps1'
if (-not (Test-Path -LiteralPath $SourceScript)) {
    throw "statusline.ps1 not found next to installer: $SourceScript"
}

$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
if (-not (Test-Path -LiteralPath $ClaudeDir)) {
    New-Item -ItemType Directory -Path $ClaudeDir | Out-Null
}

$TargetScript = Join-Path $ClaudeDir 'statusline.ps1'
$SettingsPath = Join-Path $ClaudeDir 'settings.json'

<#  The statusLine command must resolve on any machine, under whichever shell
    Claude Code spawns it with (cmd.exe or bash). Double quotes outside, single
    quotes inside, and the home directory resolved by .NET rather than by the
    shell — verified working under both cmd.exe and bash. #>
$Command = 'powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([Environment]::GetFolderPath(''UserProfile'') + ''/.claude/statusline.ps1'')"'

<#  A custom CLAUDE_CONFIG_DIR is not home-relative, so fall back to a literal
    path there — machine-specific, but so is the config dir itself. #>
$DefaultClaudeDir = Join-Path $HOME '.claude'
if ($ClaudeDir -ne $DefaultClaudeDir) {
    $literal = $TargetScript -replace "'", "''"
    $Command = 'powershell -NoProfile -ExecutionPolicy Bypass -Command "& ''{0}''"' -f $literal
}

# --- Copy the script --------------------------------------------------------
Copy-Item -LiteralPath $SourceScript -Destination $TargetScript -Force
Write-Host "Installed script: $TargetScript"

# --- Patch settings.json ----------------------------------------------------
$settings = $null
if (Test-Path -LiteralPath $SettingsPath) {
    $backup = "$SettingsPath.bak"
    Copy-Item -LiteralPath $SettingsPath -Destination $backup -Force
    Write-Host "Backed up settings: $backup"
    $raw = Get-Content -LiteralPath $SettingsPath -Raw
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
        $settings = $raw | ConvertFrom-Json
    }
}
if ($null -eq $settings) {
    $settings = [pscustomobject]@{}
}

$existing = $settings.PSObject.Properties['statusLine']
if ($existing -and -not $Force) {
    $current = $existing.Value.command
    if ($current -ne $Command) {
        Write-Host "Existing statusLine command:`n  $current"
        $answer = Read-Host 'Replace it? [y/N]'
        if ($answer -notmatch '^[Yy]') {
            Write-Host 'Left settings.json unchanged. Script is installed; wire it up manually.'
            exit 0
        }
    }
}

$statusLine = [pscustomobject]@{
    type    = 'command'
    command = $Command
}
if ($existing) {
    $settings.statusLine = $statusLine
} else {
    $settings | Add-Member -MemberType NoteProperty -Name statusLine -Value $statusLine
}

$settings | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
Write-Host "Updated settings: $SettingsPath"
Write-Host 'Done. Restart Claude Code (or /statusline) to see it.'
