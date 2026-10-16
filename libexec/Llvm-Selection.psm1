function Get-LlvmPython {
    foreach ($name in @('python3', 'python', 'py')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) {
            & $command.Source --version 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { return $command.Source }
        }
    }
    throw 'Selective installation requires Python 3.'
}

function Get-LlvmSelectionConfig {
    param([string]$Path = '.llvmup-config')
    $result = @{ Profile = ''; Components = @() }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $result }
    $section = ''
    $array = $null
    foreach ($raw in Get-Content -LiteralPath $Path) {
        $line = $raw.Trim()
        if (-not $line -or $line -match '^[#;]') { continue }
        if ($null -ne $array) { $array += ' ' + $line }
        elseif ($line -match '^\[([^]]+)\]$') { $section = $matches[1]; continue }
        elseif ($section -eq 'profile' -and $line -match '^type\s*=\s*(.+)$') {
            $result.Profile = $matches[1].Trim().Trim('"').Trim("'")
        } elseif ($section -eq 'components' -and $line -match '^include\s*=\s*(.+)$') {
            $array = $matches[1]
        }
        if ($null -ne $array -and $array.TrimEnd().EndsWith(']')) {
            $result.Components = @($array.Trim().TrimStart('[').TrimEnd(']') -split ',' | ForEach-Object { $_.Trim().Trim('"').Trim("'") } | Where-Object { $_ })
            $array = $null
        }
    }
    if ($null -ne $array) { throw 'Unterminated components.include array in .llvmup-config' }
    return $result
}

function Get-LlvmSelection {
    param([string]$Profile, [string[]]$Components = @(), [switch]$Strip, [switch]$Source)
    $arguments = @()
    if ($Profile) { $arguments += @('--profile', $Profile) }
    foreach ($component in $Components) { $arguments += @('--component', $component) }
    if ($Strip) { $arguments += '--strip' }
    if ($Source) { $arguments += '--source' }
    if ((-not $Profile -or $Profile -eq 'full') -and -not $Components.Count -and -not $Strip) {
        return [pscustomobject]@{ selective = $false; enabled = $false; key = 'full'; arguments = $arguments }
    }
    $python = Get-LlvmPython
    $json = & $python (Join-Path $PSScriptRoot 'llvmup-selection.py') selection @arguments
    if ($LASTEXITCODE -ne 0) { throw 'Invalid installation selection' }
    $selection = $json | ConvertFrom-Json
    $selection | Add-Member -NotePropertyName enabled -NotePropertyValue $true
    $selection | Add-Member -NotePropertyName arguments -NotePropertyValue $arguments
    return $selection
}

function Invoke-LlvmSelection {
    param([string]$Operation, [string]$Root, [string]$Archive, $Selection)
    if (-not $Selection.enabled) {
        $marker = Join-Path $Root '.llvmup-installation.json'
        if ($Operation -eq 'check' -and (Test-Path -LiteralPath $marker)) {
            $recorded = Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json
            if ($recorded.schema -ne 1 -or $recorded.strip -or ($recorded.components -join ',') -ne '*') {
                throw 'Installed components/strip differ; use another --name or remove it explicitly.'
            }
        }
        if ($Operation -eq 'finalize') {
            @{ schema = 1; profile = 'full'; components = @('*'); strip = $false; key = 'full'; files = @() } |
                ConvertTo-Json | Set-Content -LiteralPath $marker -Encoding UTF8
        }
        return
    }
    $python = Get-LlvmPython
    $arguments = @($Operation, '--root', $Root) + @($Selection.arguments)
    if ($Archive) { $arguments += @('--archive', $Archive) }
    & $python (Join-Path $PSScriptRoot 'llvmup-selection.py') @arguments
    if ($LASTEXITCODE -ne 0) { throw "Selection operation failed: $Operation" }
}

function Write-LlvmSpaceSnapshot {
    param([string]$Label, [string[]]$Paths, [bool]$Enabled)
    if (-not $Enabled) { return }
    Write-Host "Disk usage: $Label"
    Get-PSDrive -PSProvider FileSystem | Select-Object Name, Used, Free | Format-Table | Out-Host
    foreach ($path in $Paths) {
        if (-not $path -or -not (Test-Path -LiteralPath $path)) { continue }
        $files = @(Get-ChildItem -LiteralPath $path -File -Recurse -ErrorAction SilentlyContinue)
        $total = ($files | Measure-Object -Property Length -Sum).Sum
        Write-Host "$path : $total bytes"
        $files | Sort-Object Length -Descending | Select-Object -First 20 Length, FullName | Format-Table -AutoSize | Out-Host
    }
}

Export-ModuleMember -Function Get-LlvmSelection, Get-LlvmSelectionConfig, Invoke-LlvmSelection, Write-LlvmSpaceSnapshot
