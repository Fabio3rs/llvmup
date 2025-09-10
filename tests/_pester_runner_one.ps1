param(
    [Parameter(Mandatory=$false)]
    [string]$TestFile = 'tests/unit/Llvm-Completion.Tests.ps1'
)

Write-Host "Running Pester for: $TestFile" -ForegroundColor Cyan
Import-Module Pester -Force
$result = Invoke-Pester -Script $TestFile -Output Detailed -PassThru -Verbose
Write-Host "Pester result: $($result | ConvertTo-Json -Depth 2)" -ForegroundColor Yellow
exit $result.FailedCount
