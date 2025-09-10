
function Get-UserHome {
    <#
    .SYNOPSIS
    Retorna o diretório home do usuário de forma cross-platform.
    #>
    param()

    if ($env:USERPROFILE) { return $env:USERPROFILE }
    if ($env:HOME) { return $env:HOME }
    return [Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
}

function Get-TempDir {
    <#
    .SYNOPSIS
    Retorna um diretório temporário apropriado para a plataforma.
    #>
    param()

    if ($env:TEMP) { return $env:TEMP }
    if ($env:TMP) { return $env:TMP }
    if ($env:TMPDIR) { return $env:TMPDIR }
    return "/tmp"
}

Export-ModuleMember -Function Get-UserHome, Get-TempDir
