param([string[]]$Path = @('tests/unit/*.Tests.ps1'))
Import-Module Pester
$result = Invoke-Pester -Path $Path -Output Detailed -PassThru
exit $result.FailedCount
