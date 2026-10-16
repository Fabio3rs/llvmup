Describe 'LLVMUP package installation' {
    BeforeAll {
        $script:repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    }
    BeforeEach {
        $script:case = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:package = Join-Path $case 'llvmup'
        $script:destination = Join-Path $case 'custom install'
        $script:profileFile = Join-Path $case 'profile.ps1'
        $null = New-Item -ItemType Directory -Path $package -Force
        Copy-Item -LiteralPath (Join-Path $repo 'packaging') -Destination $package -Recurse
        foreach ($line in Get-Content (Join-Path $repo 'packaging/runtime-files.tsv')) {
            $parts = $line -split '\s+'
            if ($parts[0] -in @('common','powershell')) { Copy-Item -LiteralPath (Join-Path $repo $parts[2]) -Destination $package }
        }
        'v0.0.0-test' | Set-Content (Join-Path $package 'VERSION')
        '# existing profile' | Set-Content $profileFile
        $script:installer = Join-Path $package 'packaging/Install-Llvmup.ps1'
    }
    It 'installs and repeats in custom paths without changing the profile' {
        $before = Get-FileHash $profileFile
        & $installer -InstallDir $destination -NoProfile -ProfilePath $profileFile
        & $installer -InstallDir $destination -NoProfile -ProfilePath $profileFile
        (Get-FileHash $profileFile).Hash | Should -Be $before.Hash
        Test-Path (Join-Path $destination 'Llvm-Doctor.psm1') | Should -BeTrue
        Test-Path (Join-Path $destination 'Uninstall-Llvmup.ps1') | Should -BeTrue
        (Get-Content (Join-Path $destination 'llvmup-version')).Trim() | Should -Be 'v0.0.0-test'
    }
    It 'resolves relative destinations against the PowerShell location' {
        Push-Location $case
        try { & $installer -InstallDir './relative install' -ProfilePath './relative-profile.ps1' }
        finally { Pop-Location }
        Test-Path (Join-Path $case 'relative install/Llvm-Functions.psm1') | Should -BeTrue
        (Get-Content (Join-Path $case 'relative-profile.ps1') -Raw) | Should -Match 'relative install'
    }
    It 'configures a single profile block and uninstalls without the source package' {
        & $installer -InstallDir $destination -ProfilePath $profileFile
        & $installer -InstallDir $destination -ProfilePath $profileFile
        $content = Get-Content $profileFile -Raw
        ([regex]::Matches($content, '# LLVMUP module - Start')).Count | Should -Be 1
        $content | Should -Match '# existing profile'
        'keep' | Set-Content (Join-Path $destination 'unrelated')
        $null = New-Item -ItemType Directory -Path (Join-Path $destination 'toolchains/keep') -Force
        Remove-Item -LiteralPath $package -Recurse -Force
        & (Join-Path $destination 'Uninstall-Llvmup.ps1') -ProfilePath $profileFile
        Test-Path (Join-Path $destination 'Llvm-Functions.psm1') | Should -BeFalse
        Test-Path (Join-Path $destination 'toolchains/keep') | Should -BeTrue
        Get-Content (Join-Path $destination 'unrelated') | Should -Be keep
        (Get-Content $profileFile -Raw) | Should -Not -Match '# LLVMUP module - Start'
        (Get-Content $profileFile -Raw) | Should -Match '# existing profile'
    }
    It 'rejects an incomplete package before changing installed files' {
        & $installer -InstallDir $destination -NoProfile
        $before = (Get-FileHash (Join-Path $destination 'Llvm-Functions.psm1')).Hash
        'broken' | Set-Content (Join-Path $package 'Llvm-Functions.psm1')
        Remove-Item (Join-Path $package 'Llvm-Doctor.psm1')
        { & $installer -InstallDir $destination -NoProfile } | Should -Throw '*Missing runtime file*'
        (Get-FileHash (Join-Path $destination 'Llvm-Functions.psm1')).Hash | Should -Be $before
    }
    It 'rolls back a failed replacement and leaves the profile untouched' {
        & $installer -InstallDir $destination -NoProfile
        $before = (Get-FileHash (Join-Path $destination 'Activate-Llvm.ps1')).Hash
        'changed' | Set-Content (Join-Path $package 'Activate-Llvm.ps1')
        Mock Copy-Item { throw 'Simulated replacement failure' } -ParameterFilter { $Destination -like '*custom install*Activate-LlvmVsCode.ps1' -and $LiteralPath -notlike '*.backup' }
        { & $installer -InstallDir $destination -ProfilePath $profileFile } | Should -Throw '*Simulated replacement failure*'
        (Get-FileHash (Join-Path $destination 'Activate-Llvm.ps1')).Hash | Should -Be $before
        (Get-Content $profileFile -Raw) | Should -Not -Match '# LLVMUP module - Start'
        Test-Path (Join-Path $destination '.llvmup-install.lock') | Should -BeFalse
    }
    It 'installs from a verified ZIP using mocked network requests' {
        $assets = Join-Path $TestDrive 'bootstrap-assets'
        $null = New-Item -ItemType Directory -Path $assets
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::Open((Join-Path $assets 'llvmup-windows.zip'), 'Create')
        try {
            foreach ($file in Get-ChildItem -LiteralPath $package -File -Recurse) {
                $name = 'llvmup/' + $file.FullName.Substring($package.Length + 1).Replace('\', '/')
                $null = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $name)
            }
        } finally { $zip.Dispose() }
        $hash = (Get-FileHash (Join-Path $assets 'llvmup-windows.zip')).Hash
        "$hash  llvmup-windows.zip" | Set-Content (Join-Path $assets 'SHA256SUMS')
        Mock Invoke-WebRequest {
            Copy-Item -LiteralPath (Join-Path (Join-Path $TestDrive 'bootstrap-assets') (([string]$Uri).Split('/')[-1])) -Destination $OutFile
        }
        & (Join-Path $repo 'packaging/bootstrap.ps1') -Version v0.0.0-test -InstallDir $destination -NoProfile
        Test-Path (Join-Path $destination 'Llvm-Functions.psm1') | Should -BeTrue
        Should -Invoke Invoke-WebRequest -Times 2 -Exactly -ParameterFilter { $Uri -like 'https://github.com/Fabio3rs/llvmup/releases/download/v0.0.0-test/*' -and $TimeoutSec -eq 120 }
    }
    It 'rejects a bad checksum without installing anything' {
        Mock Invoke-WebRequest {
            if ($Uri -like '*/SHA256SUMS') { (('0' * 64) + '  llvmup-windows.zip') | Set-Content $OutFile }
            else { 'corrupted' | Set-Content $OutFile }
        }
        { & (Join-Path $repo 'packaging/bootstrap.ps1') -Version v0.0.0-test -InstallDir $destination -NoProfile } | Should -Throw '*checksum mismatch*'
        Test-Path $destination | Should -BeFalse
    }
    It 'rejects interrupted downloads and invalid versions' {
        Mock Invoke-WebRequest { throw 'Interrupted download' }
        { & (Join-Path $repo 'packaging/bootstrap.ps1') -Version v0.0.0-test -InstallDir $destination -NoProfile } | Should -Throw '*Interrupted download*'
        { & (Join-Path $repo 'packaging/bootstrap.ps1') -Version '../bad' -InstallDir $destination -NoProfile } | Should -Throw '*supply -Version*'
        Test-Path $destination | Should -BeFalse
    }
}
