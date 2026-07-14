<#
Parse a DipTrace schematic export into a net connectivity map.

Supports:
  .asc  - DipTrace ASCII export (File > Export > DipTrace ASCII...)
  .xml  - DipTrace plugin exchange XML (Tools > Plugins > Export XML for Claude)

Usage:
  .\parse-diptrace.ps1 -In "schematic.asc" -Out "netmap.txt"

Output format:
  === PARTS (n) ===
  RefDes: LibName = Value [pin count]
  === NETS (n) ===
  NET[id] NetName: RefDes.PinNumber[PinName](Value) ...
#>
param(
    [Parameter(Mandatory = $true)][string]$In,
    [Parameter(Mandatory = $true)][string]$Out
)

$ErrorActionPreference = 'Stop'

function Parse-Asc {
    param([string]$Path)

    $parts = New-Object System.Collections.Generic.List[object]
    $nets = New-Object System.Collections.Generic.List[string]
    $inComponents = $false
    $inNets = $false
    $curPart = $null
    $curPin = $null

    switch -Regex -File $Path {
        '^  \(Components' { $inComponents = $true; continue }
        '^  \(Nets' { $inNets = $true; $inComponents = $false; continue }
        '^    \(Part "([^"]*)" "([^"]*)"' {
            if ($inComponents) {
                $curPart = [pscustomobject]@{ Name = $Matches[1]; RefDes = $Matches[2]; Value = ''; Pins = (New-Object System.Collections.Generic.List[object]) }
                $parts.Add($curPart)
            }
            continue
        }
        '^      \(Value "([^"]*)"\)' {
            if ($inComponents -and $curPart -and $curPart.Value -eq '') { $curPart.Value = $Matches[1] }
            continue
        }
        '^        \(Pin (\d+) ' {
            if ($inComponents -and $curPart) {
                $curPin = [pscustomobject]@{ Num = ''; PinName = ''; Net = -1 }
                $curPart.Pins.Add($curPin)
            }
            continue
        }
        '^          \(NetNumber (-?\d+)\)' {
            if ($curPin) { $curPin.Net = [int]$Matches[1] }
            continue
        }
        '^          \(Name "([^"]*)"\)' {
            if ($curPin -and $curPin.PinName -eq '') { $curPin.PinName = $Matches[1] }
            continue
        }
        '^          \(StringNumber "([^"]*)"\)' {
            if ($curPin) { $curPin.Num = $Matches[1] }
            continue
        }
        '^    \(Net "([^"]*)"' {
            if ($inNets) { $nets.Add($Matches[1]) }
            continue
        }
    }

    # Net index in file order = NetNumber referenced by pins.
    $netConn = @{}
    foreach ($p in $parts) {
        foreach ($pin in $p.Pins) {
            if ($pin.Net -ge 0) {
                if (-not $netConn.ContainsKey($pin.Net)) { $netConn[$pin.Net] = New-Object System.Collections.Generic.List[string] }
                $label = "$($p.RefDes).$($pin.Num)"
                if ($pin.PinName -and $pin.PinName -ne $pin.Num) { $label += "[$($pin.PinName)]" }
                if ($p.Value -and $p.Value -ne $p.Name) { $label += "($($p.Value))" }
                $netConn[$pin.Net].Add($label)
            }
        }
    }

    $netList = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $nets.Count; $i++) {
        $conn = if ($netConn.ContainsKey($i)) { $netConn[$i] } else { @() }
        $netList.Add([pscustomobject]@{ Id = $i; Name = $nets[$i]; Conn = $conn })
    }
    return @{ Parts = $parts; Nets = $netList }
}

function Parse-Xml {
    param([string]$Path)

    [xml]$doc = Get-Content -Raw $Path

    <#  Library section: map ComponentStyle -> ordered pin metadata per part.
        Library format mirrors the Component Editor XML (see
        DipTraceXML_CompEdit_En.pdf). We resolve pin Name/PadNumber so nets
        read as U1.7[VDD] instead of bare indices. Resolution is defensive:
        anything missing falls back to the pin index. #>
    $stylePins = @{}
    foreach ($comp in $doc.SelectNodes('//*[local-name()="Library"]//*[@ComponentStyle]')) {
        $style = $comp.GetAttribute('ComponentStyle')
        if (-not $style -or $stylePins.ContainsKey($style)) { continue }
        $partsPinLists = @()
        $pinNodes = $comp.SelectNodes('.//*[local-name()="Pins"]/*[local-name()="Pin"]')
        $list = New-Object System.Collections.Generic.List[object]
        foreach ($pn in $pinNodes) {
            $nameNode = $pn.SelectSingleNode('*[local-name()="Name"]')
            $numNode = $pn.SelectSingleNode('*[local-name()="PadNumber"]')
            $list.Add([pscustomobject]@{
                Name = if ($nameNode) { $nameNode.InnerText } else { '' }
                Num  = if ($numNode) { $numNode.InnerText } else { '' }
            })
        }
        $stylePins[$style] = $list
    }

    # Schematic parts
    $partById = @{}
    $parts = New-Object System.Collections.Generic.List[object]
    foreach ($p in $doc.SelectNodes('//*[local-name()="Components"]/*[local-name()="Part"]')) {
        $refDes = $p.SelectSingleNode('*[local-name()="RefDes"]')
        $value = $p.SelectSingleNode('*[local-name()="Value"]')
        $name = $p.SelectSingleNode('*[local-name()="Name"]')
        $obj = [pscustomobject]@{
            Id      = [int]$p.GetAttribute('Id')
            RefDes  = if ($refDes) { $refDes.InnerText } else { '?' }
            Value   = if ($value) { $value.InnerText } else { '' }
            Name    = if ($name) { $name.InnerText } else { '' }
            Style   = $p.GetAttribute('ComponentStyle')
            PinCount = $p.SelectNodes('*[local-name()="Pins"]/*[local-name()="Pin"]').Count
        }
        $parts.Add($obj)
        $partById[$obj.Id] = $obj
    }

    # Nets
    $netList = New-Object System.Collections.Generic.List[object]
    foreach ($n in $doc.SelectNodes('//*[local-name()="Nets"]/*[local-name()="Net"]')) {
        $nameNode = $n.SelectSingleNode('*[local-name()="Name"]')
        $conn = New-Object System.Collections.Generic.List[string]
        foreach ($item in $n.SelectNodes('*[local-name()="Pins"]/*[local-name()="Item"]')) {
            $partId = [int]$item.GetAttribute('Part')
            $pinIdx = [int]$item.GetAttribute('Pin')
            $part = $partById[$partId]
            if (-not $part) { $conn.Add("part$partId.$pinIdx"); continue }
            $pinNum = "$($pinIdx + 1)"
            $pinName = ''
            if ($part.Style -and $stylePins.ContainsKey($part.Style)) {
                $lp = $stylePins[$part.Style]
                if ($pinIdx -lt $lp.Count) {
                    if ($lp[$pinIdx].Num) { $pinNum = $lp[$pinIdx].Num }
                    $pinName = $lp[$pinIdx].Name
                }
            }
            $label = "$($part.RefDes).$pinNum"
            if ($pinName -and $pinName -ne $pinNum) { $label += "[$pinName]" }
            if ($part.Value -and $part.Value -ne $part.Name) { $label += "($($part.Value))" }
            $conn.Add($label)
        }
        $netList.Add([pscustomobject]@{
            Id   = [int]$n.GetAttribute('Id')
            Name = if ($nameNode) { $nameNode.InnerText } else { "Net$($n.GetAttribute('Id'))" }
            Conn = $conn
        })
    }

    $partsOut = New-Object System.Collections.Generic.List[object]
    foreach ($p in $parts) {
        $partsOut.Add([pscustomobject]@{ RefDes = $p.RefDes; Name = $p.Name; Value = $p.Value; Pins = @(1..[Math]::Max(1, $p.PinCount)) })
    }
    return @{ Parts = $partsOut; Nets = $netList }
}

# --- main ---
$isXml = $false
if ([System.IO.Path]::GetExtension($In) -ieq '.xml') {
    $isXml = $true
}
else {
    $head = Get-Content $In -TotalCount 1
    if ($head -match '^\s*<\?xml') { $isXml = $true }
}

$result = if ($isXml) { Parse-Xml $In } else { Parse-Asc $In }

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("=== PARTS ($($result.Parts.Count)) ===")
foreach ($p in $result.Parts) {
    [void]$sb.AppendLine("$($p.RefDes): $($p.Name) = $($p.Value) [$($p.Pins.Count) pins]")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("=== NETS ($($result.Nets.Count)) ===")
foreach ($n in $result.Nets) {
    $connStr = if ($n.Conn.Count -gt 0) { $n.Conn -join ' ' } else { '(no pins)' }
    [void]$sb.AppendLine("NET[$($n.Id)] $($n.Name): $connStr")
}
[System.IO.File]::WriteAllText($Out, $sb.ToString())
Write-Output "Parts: $($result.Parts.Count)  Nets: $($result.Nets.Count)  -> $Out"
