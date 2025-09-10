Import-Module Pester
$result = Invoke-Pester tests/unit/*.Tests.ps1 -Output Detailed -PassThru
exit $result.FailedCount
