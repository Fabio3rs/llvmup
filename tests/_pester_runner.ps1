param([string[]]$Path = @('tests/unit/*.Tests.ps1'))
$pester = $null
if ($env:LLVMUP_PESTER_PATH -and (Test-Path -LiteralPath $env:LLVMUP_PESTER_PATH)) {
    $pester = Import-Module $env:LLVMUP_PESTER_PATH -Force -PassThru
} else {
    $available = Get-Module -ListAvailable Pester | Where-Object { $_.Version.Major -ge 5 } | Sort-Object Version -Descending | Select-Object -First 1
    if ($available) {
        $pester = Import-Module $available.Path -Force -PassThru
    } else {
        $pester = Import-Module Pester -Force -PassThru
    }
}
if ($pester.Version.Major -ge 5) {
    $result = Invoke-Pester -Path $Path -Output Detailed -PassThru
} else {
    $result = Invoke-Pester -Script $Path -PassThru
}
if ($null -eq $result) { exit 1 }
if ($result.FailedCount -gt 0) { exit $result.FailedCount }
if ($result.Result -and $result.Result -ne 'Passed') { exit 1 }
exit 0
