Describe "Discovery.ps1" {
    BeforeAll {
        . (Join-Path $PSScriptRoot "../../src/init.ps1")
        . (Join-Path $PSScriptRoot "../../src/modules/plugins/common/Sandbox.ps1")
        . (Join-Path $PSScriptRoot "../../src/modules/plugins/common/Discovery.ps1")
        . (Join-Path $PSScriptRoot "../../src/modules/plugins/common/StateFile.ps1")
        . (Join-Path $PSScriptRoot "../../src/modules/common/State.ps1")

        # Build a mock pluginRoot under %TEMP% so we don't touch S:\Plugins.
        $script:MockRoot = Join-Path $env:TEMP "powerlinks-discovery-test"
        if (Test-Path $script:MockRoot) { Remove-Item $script:MockRoot -Recurse -Force }
        New-Item -ItemType Directory -Path $script:MockRoot -Force | Out-Null

        # Plugin A: simple VST2/VST3 structure (like FabFilter)
        $a = Join-Path $script:MockRoot "VendorA"
        New-Item -ItemType Directory -Path (Join-Path $a "VST2\VendorA") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $a "VST3\VendorA") -Force | Out-Null
        "x" | Out-File -FilePath (Join-Path $a "VST2\VendorA\plugin.dll") -Encoding utf8

        # Plugin B: C\ subtree (like Waves, Neural DSP)
        $b = Join-Path $script:MockRoot "VendorB"
        New-Item -ItemType Directory -Path (Join-Path $b "C\Program Files\VSTPlugins\VendorB") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $b "C\Program Files\Common Files\VST3\VendorB") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $b "C\ProgramData\VendorB") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $b "C\Users\(Current User Name)\AppData\Roaming\VendorB") -Force | Out-Null

        # Plugin C: only C\ subtree with x86 path
        $c = Join-Path $script:MockRoot "VendorC"
        New-Item -ItemType Directory -Path (Join-Path $c "C\Program Files (x86)\VendorC") -Force | Out-Null

        # Plugin D: empty (no VST2/VST3, no C\)
        $d = Join-Path $script:MockRoot "VendorD"
        New-Item -ItemType Directory -Path $d -Force | Out-Null

        # Hidden folder should be ignored
        $hidden = Join-Path $script:MockRoot ".hidden"
        New-Item -ItemType Directory -Path $hidden -Force | Out-Null
    }
    AfterAll {
        if (Test-Path $script:MockRoot) {
            Remove-Item $script:MockRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Get-PluginFolders" {
        It "lists top-level subdirectories, skipping hidden" {
            $folders = Get-PluginFolders -PluginRoot $script:MockRoot
            $names = $folders | ForEach-Object { Split-Path -Leaf $_ }
            $names | Should -Contain "VendorA"
            $names | Should -Contain "VendorB"
            $names | Should -Contain "VendorC"
            $names | Should -Contain "VendorD"
            $names | Should -Not -Contain ".hidden"
        }

        It "returns empty when pluginRoot does not exist" {
            $missing = Join-Path $env:TEMP "powerlinks-missing-xyz"
            $folders = Get-PluginFolders -PluginRoot $missing
            $folders.Count | Should -Be 0
        }
    }

    Context "Discover-Plugin" {
        It "discovers VST2/VST3 mappings for VendorA" {
            $a = Join-Path $script:MockRoot "VendorA"
            $result = Discover-Plugin -PluginDir $a
            $result.Name | Should -Be "VendorA"
            $result.Mappings.Count | Should -Be 2

            $vst2 = $result.Mappings | Where-Object { $_.From -like "*\VST2\VendorA" }
            $vst2 | Should -Not -BeNullOrEmpty
            $vst2.To | Should -Be (Join-Path $env:PROGRAMFILES "VSTPlugins\VendorA")
            $vst2.Kind | Should -Be "Junction"

            $vst3 = $result.Mappings | Where-Object { $_.From -like "*\VST3\VendorA" }
            $vst3.To | Should -Be (Join-Path $env:COMMONPROGRAMFILES "VST3\VendorA")
        }

        It "does not infer links from a C:\\ mirror tree" {
            # VendorB has only the C:\ layout. Discovery must return nothing for it:
            # the subtree mixes install locations with vendor content trees, and no
            # depth threshold separates them. Such plugins need a manifest.
            $b = Join-Path $script:MockRoot "VendorB"
            $result = Discover-Plugin -PluginDir $b
            $result.Mappings.Count | Should -Be 0
        }

        It "returns empty mappings for empty plugin folder" {
            $d = Join-Path $script:MockRoot "VendorD"
            $result = Discover-Plugin -PluginDir $d
            $result.Mappings.Count | Should -Be 0
        }
    }

    Context "Invoke-Adopt" {
        BeforeAll {
            # Set up a temp state file outside the repo so the test is hermetic.
            $script:MockState = Join-Path $env:TEMP "powerlinks-discovery-test-state.json"
            if (Test-Path $script:MockState) { Remove-Item $script:MockState -Force }

            # We'll override $env:COMMONPROGRAMFILES with a writable temp dir for tests
            # that need to create real junctions. This mirrors the production scenario
            # where CommonProgramFiles is a system-protected path requiring admin.
            $script:TempCommonFiles = Join-Path $env:TEMP "powerlinks-test-commonfiles"
        }
        BeforeEach {
            # Reset the writable target dir before each test.
            if (Test-Path $script:TempCommonFiles) { Remove-Item $script:TempCommonFiles -Recurse -Force }
            New-Item -ItemType Directory -Path (Join-Path $script:TempCommonFiles "VST3") -Force | Out-Null
        }
        AfterAll {
            if (Test-Path $script:MockState) { Remove-Item $script:MockState -Force }
            if (Test-Path $script:TempCommonFiles) { Remove-Item $script:TempCommonFiles -Recurse -Force }
        }

        It "returns an empty plugins list when no junctions exist in standard roots" {
            # Don't override env: no junctions, regardless of where we look.
            $result = Invoke-Adopt -PluginRoot $script:MockRoot -StateFile $script:MockState
            $result.plugins.Count | Should -Be 0
        }

        It "captures a junction pointing under pluginRoot as one plugin entry" {
            $origCF = $env:COMMONPROGRAMFILES
            $env:COMMONPROGRAMFILES = $script:TempCommonFiles
            try {
                $source = Join-Path $script:MockRoot "VendorA\VST3\VendorA"
                $target = Join-Path $env:COMMONPROGRAMFILES "VST3\VendorA"
                New-Item -ItemType Junction -Path $target -Value $source -Force | Out-Null

                $result = Invoke-Adopt -PluginRoot $script:MockRoot -StateFile $script:MockState
                $result.plugins.Count | Should -Be 1
                $result.plugins[0].Name | Should -Be "VendorA"
                $result.plugins[0].Link | Should -Be $true
                $result.plugins[0].Mappings.Count | Should -Be 1
                $result.plugins[0].Mappings[0].From | Should -Be $source
                $result.plugins[0].Mappings[0].To   | Should -Be $target
            } finally {
                $env:COMMONPROGRAMFILES = $origCF
            }
        }

        It "finds a junction nested one level below the scan root" {
            $origCF = $env:COMMONPROGRAMFILES
            $env:COMMONPROGRAMFILES = $script:TempCommonFiles
            try {
                # iZotope sits at <root>\VST3\iZotope\Ozone 11 rather than
                # directly under VST3. A non-recursive scan misses it entirely,
                # which made the audit report iZotope as having no links at all.
                $source = Join-Path $script:MockRoot "VendorA\VST3\iZotope\Ozone 11"
                New-Item -ItemType Directory -Path $source -Force | Out-Null
                $target = Join-Path $env:COMMONPROGRAMFILES "VST3\iZotope\Ozone 11"
                New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
                New-Item -ItemType Junction -Path $target -Value $source -Force | Out-Null

                $result = Invoke-Adopt -PluginRoot $script:MockRoot -StateFile $script:MockState
                $entry = $result.plugins | Where-Object { $_.Name -eq 'VendorA' }
                $entry | Should -Not -BeNullOrEmpty
                $entry.Mappings.To | Should -Contain $target

                cmd /c rmdir "$target" 2>&1 | Out-Null
            } finally {
                $env:COMMONPROGRAMFILES = $origCF
            }
        }

        It "groups multiple junctions for the same plugin into one entry" {
            $origCF = $env:COMMONPROGRAMFILES
            $env:COMMONPROGRAMFILES = $script:TempCommonFiles
            try {
                # Two junctions for VendorA: VST3 path
                $source1 = Join-Path $script:MockRoot "VendorA\VST3\VendorA"
                $target1 = Join-Path $env:COMMONPROGRAMFILES "VST3\VendorA"
                New-Item -ItemType Junction -Path $target1 -Value $source1 -Force | Out-Null

                # And a fake second junction also under VendorA (in a different sub-target)
                $extraTargetDir = Join-Path $script:TempCommonFiles "Avid\Audio\Plug-Ins"
                New-Item -ItemType Directory -Path $extraTargetDir -Force | Out-Null
                $source2 = Join-Path $script:MockRoot "VendorA\extra"
                New-Item -ItemType Directory -Path $source2 -Force | Out-Null
                $target2 = Join-Path $extraTargetDir "VendorA"
                New-Item -ItemType Junction -Path $target2 -Value $source2 -Force | Out-Null

                $result = Invoke-Adopt -PluginRoot $script:MockRoot -StateFile $script:MockState
                $result.plugins.Count | Should -Be 1
                $result.plugins[0].Name | Should -Be "VendorA"
                $result.plugins[0].Mappings.Count | Should -Be 2
            } finally {
                $env:COMMONPROGRAMFILES = $origCF
            }
        }

        It "ignores junctions pointing outside pluginRoot" {
            $origCF = $env:COMMONPROGRAMFILES
            $env:COMMONPROGRAMFILES = $script:TempCommonFiles
            $outsideSource = Join-Path $env:TEMP "powerlinks-outside-plugin"
            try {
                # Create a junction pointing to a path NOT under $script:MockRoot
                New-Item -ItemType Directory -Path $outsideSource -Force | Out-Null
                $target = Join-Path $env:COMMONPROGRAMFILES "VST3\OutsidePlugin"
                New-Item -ItemType Junction -Path $target -Value $outsideSource -Force | Out-Null

                $result = Invoke-Adopt -PluginRoot $script:MockRoot -StateFile $script:MockState
                $result.plugins.Count | Should -Be 0
            } finally {
                $env:COMMONPROGRAMFILES = $origCF
                # The decoy source is created outside the sandbox root, so the
                # outer AfterAll never reaches it.
                if (Test-Path -LiteralPath $outsideSource) {
                    Remove-Item -LiteralPath $outsideSource -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        It "writes state.json that round-trips through Read-PowerLinksState" {
            $origCF = $env:COMMONPROGRAMFILES
            $env:COMMONPROGRAMFILES = $script:TempCommonFiles
            try {
                $source = Join-Path $script:MockRoot "VendorA\VST3\VendorA"
                $target = Join-Path $env:COMMONPROGRAMFILES "VST3\VendorA"
                New-Item -ItemType Junction -Path $target -Value $source -Force | Out-Null

                Invoke-Adopt -PluginRoot $script:MockRoot -StateFile $script:MockState | Out-Null
                $read = Read-PowerLinksState -Path $script:MockState
                $read.plugins.Count | Should -Be 1
                $read.plugins[0].name | Should -Be "VendorA"
                $read.plugins[0].link | Should -Be $true
                $read.plugins[0].mappings.Count | Should -Be 1
            } finally {
                $env:COMMONPROGRAMFILES = $origCF
            }
        }
    }
}
