Describe 'Llvm Completion Module' {
    BeforeAll {
    # Determine a portable temp root (TEMP may be unset on some platforms)
    if ($env:TEMP) { $tempRoot = $env:TEMP } elseif ($env:TMPDIR) { $tempRoot = $env:TMPDIR } else { $tempRoot = '/tmp' }

    # Setup a fake toolchains dir in temp BEFORE importing the module so the module
    # can pick up the mocked Get-UserHome if it resolves on import.
    $script:testDir = Join-Path $tempRoot 'llvmup_test_toolchains'
        Remove-Item -Path $script:testDir -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path $script:testDir -ItemType Directory | Out-Null
        New-Item -Path (Join-Path $script:testDir 'llvmorg-18.1.8') -ItemType Directory | Out-Null
        New-Item -Path (Join-Path $script:testDir 'llvmorg-19.1.0') -ItemType Directory | Out-Null

        # Mock Get-UserHome to point to our test dir
        function Get-UserHome { return $script:testDir }

    # Load the completion module (use Import-Module to avoid dot-sourcing path issues)
    $modulePath = Join-Path $PSScriptRoot '..\..\Llvm-Completion.psm1'
    $resolved = Resolve-Path -Path $modulePath -ErrorAction SilentlyContinue
    if ($resolved) { Import-Module -Force $resolved.Path } else { Import-Module -Force $modulePath }

    # Compute cache path used by module so cleanup can run even if Get-UserHome changes
    $script:cachePath = Join-Path $script:testDir '.cache/llvmup/remote_versions.cache'
    }

    It 'Get-LlvmLocalVersions returns local toolchains' {
        $locals = Get-LlvmLocalVersions
        $locals | Should -Contain 'llvmorg-18.1.8'
        $locals | Should -Contain 'llvmorg-19.1.0'
    }

    It 'Get-LlvmRemoteVersions returns a list (fallback works)' {
        $remotes = Get-LlvmRemoteVersions
        $remotes | Should -Not -BeNullOrEmpty
    }

    It 'Activate-Llvm completer provides completions' {
        $comps = Get-ArgumentCompleter -CommandName 'Activate-Llvm' -ErrorAction SilentlyContinue
        $comps | Should -Not -BeNullOrEmpty
        # Execute the scriptblock to get results (simulate user typing 'llvmorg-1')
        $sb = $comps[0].ScriptBlock
        $res = & $sb 'Activate-Llvm' 'Version' 'llvmorg' $null $null
        # The scriptblock returns CompletionResult objects when completions exist
        $res | Should -Not -BeNullOrEmpty
    }

    AfterAll {
        # cleanup
        Remove-Item -Path $script:testDir -Recurse -Force -ErrorAction SilentlyContinue
    if ($script:cachePath) { Remove-Item -Path $script:cachePath -ErrorAction SilentlyContinue }
    }
}
