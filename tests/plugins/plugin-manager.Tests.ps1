Describe "plugin-manager.ps1 integration (with manifests)" {
    BeforeAll {
        . (Join-Path $PSScriptRoot "../../src/init.ps1")
        . (Join-Path $PSScriptRoot "../../src/modules/plugins/common/Sandbox.ps1")
        . (Join-Path $PSScriptRoot "../../src/modules/common/State.ps1")
        . (Join-Path $PSScriptRoot "../../src/modules/plugins/common/StateFile.ps1")
        . (Join-Path $PSScriptRoot "../../src/modules/plugins/common/Discovery.ps1")
        . (Join-Path $PSScriptRoot "../../src/modules/plugins/common/Manifest.ps1")
        . (Join-Path $PSScriptRoot "../../src/modules/plugins/methods/registry-import.ps1")
        . (Join-Path $PSScriptRoot "../../src/modules/plugins/methods/copy-tree.ps1")
        . (Join-Path $PSScriptRoot "../../src/modules/plugins/methods/process-kill.ps1")

        $script:Sandbox = Join-Path $env:TEMP "powerlinks-pm-integration"
        if (Test-Path $script:Sandbox) { Remove-Item $script:Sandbox -Recurse -Force }
        New-Item -ItemType Directory -Path $script:Sandbox -Force | Out-Null

        # Mock pluginRoot: a fake "Vendor - Product" with VST3 subdir
        $script:FakePluginRoot = Join-Path $script:Sandbox "FakePlugin"
        $script:VST3Dir = Join-Path $script:FakePluginRoot "VST3\FakeVendor"
        New-Item -ItemType Directory -Path $script:VST3Dir -Force | Out-Null
        "x" | Out-File -FilePath (Join-Path $script:VST3Dir "plugin.vst3") -Encoding ascii

        # Mock Reg\Install.reg with HKCU key
        $script:RegDir = Join-Path $script:FakePluginRoot "Reg"
        New-Item -ItemType Directory -Path $script:RegDir -Force | Out-Null
        $script:RegFile = Join-Path $script:RegDir "Install.reg"
        $regKey = "HKEY_CURRENT_USER\Software\PowerLinksTest\Integration"
        $content = "Windows Registry Editor Version 5.00" + "`r`n" +
                   "" + "`r`n" +
                   "[$regKey\EnableTest]" + "`r`n" +
                   '"Flag"="enabled"' + "`r`n"
        [System.IO.File]::WriteAllText($script:RegFile, $content, [System.Text.UTF8Encoding]::new($false))

        $script:RegKeyPs = "HKCU:\Software\PowerLinksTest\Integration"  # for PS access

        # Mock R2R\kill.cmd that creates a marker file
        $script:R2RDir = Join-Path $script:FakePluginRoot "R2R"
        New-Item -ItemType Directory -Path $script:R2RDir -Force | Out-Null
        $script:ProcessScript = Join-Path $script:R2RDir "kill.cmd"
        $script:ProcessMarker = Join-Path $script:Sandbox "process-was-here.txt"
        "@echo processed > `"$($script:ProcessMarker)`"" | Out-File -FilePath $script:ProcessScript -Encoding ascii

        # Mock copy source
        $script:CopySrc = Join-Path $script:FakePluginRoot "copy-src"
        $script:CopyDst = Join-Path $script:Sandbox "copy-dst"
        New-Item -ItemType Directory -Path $script:CopySrc -Force | Out-Null
        "copy-content" | Out-File -FilePath (Join-Path $script:CopySrc "data.txt") -Encoding ascii

        # Mock manifest pointing at our fake plugin
        $script:FakeManifestDir = Join-Path $script:Sandbox "manifests"
        New-Item -ItemType Directory -Path $script:FakeManifestDir -Force | Out-Null
        $script:FakeManifest = Join-Path $script:FakeManifestDir "FakePlugin.json"

        $manifestObj = [PSCustomObject]@{
            Name     = 'FakePlugin'
            Links    = @([PSCustomObject]@{ From = 'VST3\FakeVendor'; To = 'C:\Windows\Temp\FakeVendor'; Kind = 'Junction' })
            Copy     = @([PSCustomObject]@{ From = 'copy-src'; To = $script:CopyDst })
            Registry = @(
                [PSCustomObject]@{ OnEnable  = 'Reg\Install.reg' }
                [PSCustomObject]@{ OnDisable = 'Reg\Uninstall.reg' }
            )
            Process  = @([PSCustomObject]@{ BeforeRevert = 'R2R\kill.cmd' })
        }
        $manifestObj | ConvertTo-Json -Depth 10 | Out-File -FilePath $script:FakeManifest -Encoding utf8

        # Mock state.json (build via PSCustomObject -> JSON to avoid escape bugs)
        $script:FakeState = Join-Path $script:Sandbox "powerlinks.json"
        $stateObj = [PSCustomObject]@{
            version      = 1
            tool_version = '0.0.1'
            plugins      = @(
                [PSCustomObject]@{
                    name     = 'FakePlugin'
                    link     = $true
                    ignore   = $false
                    mappings = @(
                        [PSCustomObject]@{
                            from = $script:VST3Dir
                            to   = 'C:\Windows\Temp\FakeVendor'
                            kind = 'Junction'
                        }
                    )
                }
            )
        }
        $stateObj | ConvertTo-Json -Depth 10 | Out-File -FilePath $script:FakeState -Encoding utf8
    }
    AfterAll {
        # Cleanup
        if (Test-Path $script:RegKeyPs) {
            Remove-Item -Path $script:RegKeyPs -Recurse -Force -ErrorAction SilentlyContinue
        }
        # Junction removal: cmd rmdir is the only reliable way on Windows
        if (Test-Path 'C:\Windows\Temp\FakeVendor') {
            cmd /c rmdir 'C:\Windows\Temp\FakeVendor' 2>&1 | Out-Null
        }
        if (Test-Path $script:Sandbox) {
            Remove-Item $script:Sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "apply runs manifest reg-enable and copy after link creation" {
        $manifestDir = $script:FakeManifestDir
        $pluginRoot  = $script:FakePluginRoot

        $entries = Get-EnabledPlugins -State (Read-PowerLinksState -Path $script:FakeState)
        $entries.Count | Should -Be 1

        # Inline the equivalent of Build-Delta + Invoke-Reconcile
        foreach ($entry in $entries) {
            $entryState = Get-SymlinkEntryState -Entry $entry
            $desired = if ($entry.link) { 'symlink' } else { 'missing' }
            $categorized = Compare-State -EntryState $entryState -Desired $desired

            $results = Invoke-SafeAction -EntryState $categorized
            foreach ($r in $results) {
                if ($r.status -eq 'created' -or $r.status -eq 'replaced') {
                    # Good -- link or junction created
                }
            }
        }
        Test-Path 'C:\Windows\Temp\FakeVendor' | Should -Be $true

        # Manifest step -- enable
        $manifest = Get-PluginManifest -Name 'FakePlugin' -ManifestDir $manifestDir
        $manifest | Should -Not -BeNullOrEmpty

        foreach ($c in (Get-ManifestCopySteps -Manifest $manifest -BaseDir $pluginRoot)) {
            $r = Invoke-CopyTree -From $c.From -To $c.To
            $r.Status | Should -Be 'copied'
            Test-Path (Join-Path $c.To "data.txt") | Should -Be $true
        }

        foreach ($s in (Get-ManifestRegistrySteps -Manifest $manifest -Action 'enable' -BaseDir $pluginRoot)) {
            $r = Import-RegistryFile -Path $s.RegFile
            $r.Status | Should -Be 'imported'
        }
        Test-Path "$($script:RegKeyPs)\EnableTest" | Should -Be $true
    }

    It "revert runs process script before reg-disable" {
        $manifestDir = $script:FakeManifestDir
        $pluginRoot  = $script:FakePluginRoot

        $manifest = Get-PluginManifest -Name 'FakePlugin' -ManifestDir $manifestDir

        # Process step first
        foreach ($s in (Get-ManifestProcessSteps -Manifest $manifest -Trigger 'beforeRevert' -BaseDir $pluginRoot)) {
            $r = Invoke-ProcessScript -ScriptPath $s.Script -WorkDir $pluginRoot
            $r.Status | Should -Be 'invoked'
        }
        Test-Path $script:ProcessMarker | Should -Be $true

        # Reg disable (Reg\Uninstall.reg doesn't exist -- should skip gracefully)
        foreach ($s in (Get-ManifestRegistrySteps -Manifest $manifest -Action 'disable' -BaseDir $pluginRoot)) {
            $r = Import-RegistryFile -Path $s.RegFile
            $r.Status | Should -Be 'skipped'
        }
    }
}
