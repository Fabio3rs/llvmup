
function Get-UserHome {
    <#
    .SYNOPSIS
    Returns the user home directory in a cross-platform way.
    #>
    param()

    if ($env:USERPROFILE) { return $env:USERPROFILE }
    if ($env:HOME) { return $env:HOME }
    return [Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
}

function Get-TempDir {
    <#
    .SYNOPSIS
    Returns an appropriate temporary directory for the current platform.
    #>
    param()

    if ($env:TEMP) { return $env:TEMP }
    if ($env:TMP) { return $env:TMP }
    if ($env:TMPDIR) { return $env:TMPDIR }
    return "/tmp"
}

Export-ModuleMember -Function Get-UserHome, Get-TempDir
