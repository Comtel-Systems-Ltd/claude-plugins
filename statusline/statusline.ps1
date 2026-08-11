#Requires -Version 5.1
<#  Claude Code custom statusline.
    Shows: model · context usage · effort · path · git branch/status · caveman badge.
    Reads the Status hook JSON from stdin; pulls live context/effort from the
    session transcript tail (statusline stdin does not carry those). Fails soft:
    on any error it prints what it has and exits 0 so the prompt never breaks. #>

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$Esc = [char]27

function Colorize {
    param([string]$Code, [string]$Text)
    return "${Esc}[${Code}m${Text}${Esc}[0m"
}

# --- Read + parse stdin JSON ------------------------------------------------
$json = $null
try {
    $raw = [Console]::In.ReadToEnd()
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
        $json = $raw | ConvertFrom-Json
    }
} catch {
    $json = $null
}

# --- Model ------------------------------------------------------------------
$modelName = "Claude"
$modelId = ""
if ($null -ne $json -and $null -ne $json.model) {
    if ($json.model.display_name) { $modelName = [string]$json.model.display_name }
    if ($json.model.id) { $modelId = [string]$json.model.id }
}

# 1M context variants carry "1m" / "[1m]" in the id (or display name).
# Fable models (claude-fable-5, etc.) always have a 1M window regardless of tag.
$ctxWindow = 200000
if ($modelId -match '1m' -or $modelName -match '1M' -or $modelId -match 'fable' -or $modelName -match 'fable') { $ctxWindow = 1000000 }

# --- Context + effort from transcript tail ----------------------------------
$ctxTokens = $null
$effort = $null
$transcript = $null
if ($null -ne $json -and $json.transcript_path) { $transcript = [string]$json.transcript_path }

if ($transcript -and (Test-Path -LiteralPath $transcript)) {
    try {
        $tail = Get-Content -LiteralPath $transcript -Tail 250 -ErrorAction Stop
        for ($i = $tail.Count - 1; $i -ge 0; $i--) {
            $line = $tail[$i]
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -notmatch '"usage"') { continue }
            try {
                $obj = $line | ConvertFrom-Json
            } catch {
                continue
            }
            if ($obj.type -ne 'assistant') { continue }
            $u = $obj.message.usage
            if ($null -eq $u) { continue }
            $inp = [int64]($u.input_tokens)
            $cc  = [int64]($u.cache_creation_input_tokens)
            $cr  = [int64]($u.cache_read_input_tokens)
            $ctxTokens = $inp + $cc + $cr
            if ($obj.effort) { $effort = [string]$obj.effort }
            break
        }
        # Effort may live on a newer line than the last usage-bearing one.
        if (-not $effort) {
            for ($i = $tail.Count - 1; $i -ge 0; $i--) {
                $line = $tail[$i]
                if ($line -notmatch '"effort"') { continue }
                try { $obj = $line | ConvertFrom-Json } catch { continue }
                if ($obj.effort) { $effort = [string]$obj.effort; break }
            }
        }
    } catch {
        # leave ctxTokens/effort null
    }
}

# --- Build segments ---------------------------------------------------------
$parts = @()

# Model — cyan
$parts += Colorize '38;5;39' $modelName

# Context — green/yellow/red by fill
if ($null -ne $ctxTokens) {
    $pct = [int][math]::Round(($ctxTokens / $ctxWindow) * 100)
    $usedK = [int][math]::Round($ctxTokens / 1000)
    $winLabel = if ($ctxWindow -ge 1000000) { "$([int]($ctxWindow / 1000000))M" } else { "$([int]($ctxWindow / 1000))k" }
    $color = if ($pct -lt 50) { '38;5;76' } elseif ($pct -lt 80) { '38;5;178' } else { '38;5;196' }
    $parts += Colorize $color ("ctx {0}k/{1} {2}%" -f $usedK, $winLabel, $pct)
}

# Effort — magenta
if ($effort) {
    $parts += Colorize '38;5;170' ("effort {0}" -f $effort)
}

# --- Current path -------------------------------------------------------
$cwd = $null
if ($null -ne $json -and $json.workspace -and $json.workspace.current_dir) {
    $cwd = [string]$json.workspace.current_dir
} elseif ($null -ne $json -and $json.cwd) {
    $cwd = [string]$json.cwd
}

if ($cwd) {
    $displayPath = $cwd
    if ($HOME -and $cwd.StartsWith($HOME, [System.StringComparison]::OrdinalIgnoreCase)) {
        $displayPath = "~" + $cwd.Substring($HOME.Length)
    }
    $displayPath = $displayPath -replace '\\', '/'
    $parts += Colorize '38;5;244' $displayPath
}

# --- Git branch + dirty status ----------------------------------------------
if ($cwd -and (Test-Path -LiteralPath $cwd)) {
    try {
        $gitDir = & git --no-optional-locks -C "$cwd" rev-parse --is-inside-work-tree 2>$null
        if ($LASTEXITCODE -eq 0 -and $gitDir -eq 'true') {
            $branch = & git --no-optional-locks -C "$cwd" branch --show-current 2>$null
            if ([string]::IsNullOrWhiteSpace($branch)) {
                $branch = & git --no-optional-locks -C "$cwd" rev-parse --short HEAD 2>$null
            }
            if ($branch) {
                $statusOut = & git --no-optional-locks -C "$cwd" status --porcelain 2>$null
                $dirty = -not [string]::IsNullOrWhiteSpace(($statusOut -join ""))
                $gitLabel = "git:{0}" -f $branch.Trim()
                if ($dirty) { $gitLabel += "*" }
                $gitColor = if ($dirty) { '38;5;214' } else { '38;5;71' }
                $parts += Colorize $gitColor $gitLabel
            }
        }
    } catch {
        # no git segment on error
    }
}

# --- Caveman badge (mirrors caveman plugin's own statusline) ----------------
try {
    $ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME ".claude" }
    $Flag = Join-Path $ClaudeDir ".caveman-active"
    if (Test-Path -LiteralPath $Flag) {
        $Item = Get-Item -LiteralPath $Flag -Force -ErrorAction Stop
        if (-not ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and $Item.Length -le 64) {
            $Raw = Get-Content -LiteralPath $Flag -TotalCount 1 -ErrorAction Stop
            $Mode = ([string]$Raw).Trim().ToLowerInvariant() -replace '[^a-z0-9-]', ''
            $Valid = @('off','lite','full','ultra','wenyan-lite','wenyan','wenyan-full','wenyan-ultra','commit','review','compress')
            if ($Valid -contains $Mode) {
                if ($Mode -eq 'full') {
                    $parts += Colorize '38;5;172' '[CAVEMAN]'
                } elseif ($Mode -ne 'off') {
                    $parts += Colorize '38;5;172' ("[CAVEMAN:{0}]" -f $Mode.ToUpperInvariant())
                }
            }
        }
    }
} catch {
    # no badge on error
}

# --- Emit -------------------------------------------------------------------
$sep = Colorize '38;5;240' '  |  '
[Console]::Write(($parts -join $sep))
exit 0
