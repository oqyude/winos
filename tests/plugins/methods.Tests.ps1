Describe "Methods (registry / copy / process / manifest)" {
    BeforeAll {
        . (Join-Path $PSScriptRoot "../../src/init.ps1")
        . (Join-Path $PSScriptRoot "../../src/modules/plugins/common/Sandbox.ps1")
        . (Join-Path $PSScriptRoot "../../src/modules/plugins/common/Manifest.ps1")
        . (Join-Path $PSScriptRoot "../../src/modules/plugins/methods/registry-import.ps1")
        . (Join-Path $PSScriptRoot "../../src/modules/plugins/methods/copy-tree.ps1")
        . (Join-Path $PSScriptRoot "../../src/modules/plugins/methods/process-kill.ps1")

        $script:TestRoot = Join-Path $env:TEMP "powerlinks-methods-test"
        if (Test-Path $script:TestRoot) { Remove-Item $script:TestRoot -Recurse -Force }
        New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null

        # reg.exe uses HKEY_CURRENT_USER\ in reg files (not HKCU:\ with colon).
        $script:TestKey = "HKEY_CURRENT_USER\Software\PowerLinksTest\Phase3"
        $script:PsTestKey = "HKCU:\Software\PowerLinksTest\Phase3"   # for PowerShell access (Test-Path etc.)
    }
    AfterAll {
        # Cleanup registry test key (use the PS-form for Test-Path/Remove-Item)
        if (Test-Path $script:PsTestKey) { Remove-Item -Path $script:PsTestKey -Recurse -Force }

        if (Test-Path $script:TestRoot) { Remove-Item $script:TestRoot -Recurse -Force }
    }

    Context "Import-RegistryFile" {
        It "imports a .reg file that adds a key" {
            $regPath = Join-Path $script:TestRoot "add.reg"
            $content = "Windows Registry Editor Version 5.00`r`n`r`n[$script:TestKey\Add]`r`n`"TestValue`"=`"hello`"`r`n"
            $content | Out-File -FilePath $regPath -Encoding utf8

            $r = Import-RegistryFile -Path $regPath
            $r.Status | Should -Be 'imported'
            $keyPath = "$script:PsTestKey\Add"
            Test-Path $keyPath | Should -Be $true
            (Get-ItemProperty -Path $keyPath -Name TestValue -ErrorAction SilentlyContinue).TestValue | Should -Be 'hello'
        }

        It "imports a .reg file that deletes a key (- prefix)" {
            New-Item -Path "$script:PsTestKey\DeleteMe" -Force | Out-Null
            Test-Path "$script:PsTestKey\DeleteMe" | Should -Be $true

            $regPath = Join-Path $script:TestRoot "delete.reg"
            $content = "Windows Registry Editor Version 5.00`r`n`r`n[-$script:TestKey\DeleteMe]`r`n"
            $content | Out-File -FilePath $regPath -Encoding utf8

            $r = Import-RegistryFile -Path $regPath
            $r.Status | Should -Be 'imported'
            Test-Path "$script:PsTestKey\DeleteMe" | Should -Be $false
        }

        It "skips with Status=skipped when reg file does not exist" {
            $r = Import-RegistryFile -Path (Join-Path $script:TestRoot "nope.reg")
            $r.Status | Should -Be 'skipped'
        }

        It "honors -WhatIf and reports Status=skipped" {
            $regPath = Join-Path $script:TestRoot "noop.reg"
            $content = "Windows Registry Editor Version 5.00`r`n`r`n[$script:TestKey\WhatIf]`r`n`"TestValue`"=`"x`"`r`n"
            $content | Out-File -FilePath $regPath -Encoding utf8

            $r = Import-RegistryFile -Path $regPath -WhatIf
            $r.Status | Should -Be 'skipped'
            Test-Path "$script:PsTestKey\WhatIf" | Should -Be $false
        }
    }

    Context "Invoke-CopyTree / Remove-CopyTree" {
        It "mirrors source files to target" {
            $src = Join-Path $script:TestRoot "src1"
            $dst = Join-Path $script:TestRoot "dst1"
            New-Item -ItemType Directory -Path $src -Force | Out-Null
            "hello" | Out-File -FilePath (Join-Path $src "a.txt") -Encoding utf8
            "world" | Out-File -FilePath (Join-Path $src "b.txt") -Encoding utf8

            $r = Invoke-CopyTree -From $src -To $dst
            $r.Status | Should -Be 'copied'
            Test-Path (Join-Path $dst "a.txt") | Should -Be $true
            Test-Path (Join-Path $dst "b.txt") | Should -Be $true
        }

        It "creates parent directories that don't exist" {
            $src = Join-Path $script:TestRoot "src2"
            $dst = Join-Path $script:TestRoot "deep\nested\dst2"
            New-Item -ItemType Directory -Path $src -Force | Out-Null
            "x" | Out-File -FilePath (Join-Path $src "f.txt") -Encoding utf8

            $r = Invoke-CopyTree -From $src -To $dst
            $r.Status | Should -Be 'copied'
            Test-Path (Join-Path $dst "f.txt") | Should -Be $true
        }

        It "skips with Status=skipped when source is missing" {
            $missing = Join-Path $script:TestRoot "no-such-source"
            $dst = Join-Path $script:TestRoot "dst-x"
            $r = Invoke-CopyTree -From $missing -To $dst
            $r.Status | Should -Be 'skipped'
        }

        It "Remove-CopyTree deletes a copied tree" {
            $src = Join-Path $script:TestRoot "src3"
            $dst = Join-Path $script:TestRoot "dst3"
            New-Item -ItemType Directory -Path $src -Force | Out-Null
            "x" | Out-File -FilePath (Join-Path $src "f.txt") -Encoding utf8
            Invoke-CopyTree -From $src -To $dst | Out-Null
            Test-Path $dst | Should -Be $true

            $r = Remove-CopyTree -Path $dst
            $r.Status | Should -Be 'removed'
            Test-Path $dst | Should -Be $false
        }
    }

    Context "Invoke-ProcessScript" {
        It "invokes a .ps1 script and reports exit code" {
            $marker = Join-Path $script:TestRoot "process-marker.txt"
            $script = Join-Path $script:TestRoot "marker.ps1"
            "Set-Content -Path '$marker' -Value 'invoked' -Encoding utf8" | Out-File -FilePath $script -Encoding utf8

            $r = Invoke-ProcessScript -ScriptPath $script -WorkDir $script:TestRoot
            $r.Status | Should -Be 'invoked'
            Test-Path $marker | Should -Be $true
            (Get-Content $marker -Raw).Trim() | Should -Be 'invoked'
        }

        It "invokes a .cmd script" {
            $marker = Join-Path $script:TestRoot "cmd-marker.txt"
            $script = Join-Path $script:TestRoot "marker.cmd"
            "@echo done > `"$marker`"" | Out-File -FilePath $script -Encoding utf8

            $r = Invoke-ProcessScript -ScriptPath $script -WorkDir $script:TestRoot
            $r.Status | Should -Be 'invoked'
            Test-Path $marker | Should -Be $true
        }

        It "reports Status=failed on non-zero exit" {
            $script = Join-Path $script:TestRoot "fail.ps1"
            "exit 7" | Out-File -FilePath $script -Encoding utf8

            $r = Invoke-ProcessScript -ScriptPath $script -WorkDir $script:TestRoot
            $r.Status | Should -Be 'failed'
            $r.Note | Should -Match 'exit 7'
        }

        It "skips with Status=skipped when script is missing" {
            $r = Invoke-ProcessScript -ScriptPath (Join-Path $script:TestRoot "nope.ps1") -WorkDir $script:TestRoot
            $r.Status | Should -Be 'skipped'
        }
    }

    Context "Get-PluginManifest" {
        BeforeAll {
            $script:ManifestDir = Join-Path $script:TestRoot "manifests"
            New-Item -ItemType Directory -Path $script:ManifestDir -Force | Out-Null
        }

        It "loads a .json manifest and normalizes missing sections to $null" {
            $json = Join-Path $script:ManifestDir "Minimal.json"
            '{ "Name": "Minimal" }' | Out-File -FilePath $json -Encoding utf8

            $m = Get-PluginManifest -Name 'Minimal' -ManifestDir $script:ManifestDir
            $m.Name | Should -Be 'Minimal'
            $m.PSObject.Properties.Name | Should -Contain 'Links'
            $m.PSObject.Properties.Name | Should -Contain 'Copy'
            $m.PSObject.Properties.Name | Should -Contain 'Registry'
            $m.PSObject.Properties.Name | Should -Contain 'Process'
            $m.Links | Should -BeNullOrEmpty
        }

        It "returns $null when manifest does not exist" {
            $m = Get-PluginManifest -Name 'DoesNotExist' -ManifestDir $script:ManifestDir
            $m | Should -BeNullOrEmpty
        }

        It "returns $null and warns on malformed JSON" {
            $json = Join-Path $script:ManifestDir "Broken.json"
            '{ "Name": "Broken", ' | Out-File -FilePath $json -Encoding utf8

            $m = Get-PluginManifest -Name 'Broken' -ManifestDir $script:ManifestDir
            $m | Should -BeNullOrEmpty
        }

        It "returns $null for an empty file" {
            $json = Join-Path $script:ManifestDir "Empty.json"
            '' | Out-File -FilePath $json -Encoding utf8

            $m = Get-PluginManifest -Name 'Empty' -ManifestDir $script:ManifestDir
            $m | Should -BeNullOrEmpty
        }

        It "treats a single-element JSON array as a one-item section" {
            # ConvertFrom-Json unwraps [ { .. } ] into a bare object. The loader must
            # normalize that back into an array or single-link manifests break.
            $json = Join-Path $script:ManifestDir "Single.json"
            $content = '{ "Name": "Single", "Links": [ { "From": "a", "To": "b" } ] }'
            $content | Out-File -FilePath $json -Encoding utf8

            $m = Get-PluginManifest -Name 'Single' -ManifestDir $script:ManifestDir
            $m | Should -Not -BeNullOrEmpty
            $section = Get-ManifestSection -Manifest $m -Name 'Links'
            $section -is [System.Array] | Should -Be $true
            $section | Should -HaveCount 1
            $section[0].From | Should -Be 'a'
        }
    }

    Context "Test-Manifest validation" {
        It "accepts a well-formed manifest" {
            $m = [PSCustomObject]@{
                Name     = 'Good'
                Links    = @([PSCustomObject]@{ From = 'a'; To = 'b' })
                Registry = @([PSCustomObject]@{ OnEnable = 'x.reg' })
            }
            Test-Manifest -Manifest $m -Path 'good.json' | Should -Be $true
        }

        It "rejects a Links entry missing From" {
            $m = [PSCustomObject]@{
                Name  = 'BadLinks'
                Links = @([PSCustomObject]@{ To = 'b' })
            }
            Test-Manifest -Manifest $m -Path 'badlinks.json' 3>$null | Should -Be $false
        }

        It "rejects a Registry entry with neither OnEnable nor OnDisable" {
            $m = [PSCustomObject]@{
                Name     = 'BadReg'
                Registry = @([PSCustomObject]@{ SomethingElse = 'x' })
            }
            Test-Manifest -Manifest $m -Path 'badreg.json' 3>$null | Should -Be $false
        }

        It "rejects a Process entry missing BeforeRevert" {
            $m = [PSCustomObject]@{
                Name    = 'BadProc'
                Process = @([PSCustomObject]@{ Other = 'x' })
            }
            Test-Manifest -Manifest $m -Path 'badproc.json' 3>$null | Should -Be $false
        }

        It "rejects a top-level array" {
            $m = @([PSCustomObject]@{ Name = 'x' })
            Test-Manifest -Manifest $m -Path 'arr.json' 3>$null | Should -Be $false
        }

        It "rejects $null" {
            Test-Manifest -Manifest $null -Path 'null.json' 3>$null | Should -Be $false
        }

        It "rejects a section that is not an array" {
            $m = [PSCustomObject]@{ Name = 'BadShape'; Links = 'not-an-array' }
            Test-Manifest -Manifest $m -Path 'badshape.json' 3>$null | Should -Be $false
        }
    }

    Context "Expand-PathTokens" {
        It "expands a simple env token" {
            Expand-PathTokens -Path '%ProgramFiles%\VSTPlugins\Foo' |
                Should -Be (Join-Path $env:PROGRAMFILES 'VSTPlugins\Foo')
        }

        It "expands a token whose name contains parentheses" {
            # %ProgramFiles(x86)% is the one that breaks naive parsers.
            Expand-PathTokens -Path '%ProgramFiles(x86)%\VSTPlugins' |
                Should -Be (Join-Path ([Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) 'VSTPlugins')
        }

        It "expands several tokens in one path" {
            $r = Expand-PathTokens -Path '%APPDATA%\Foo'
            $r | Should -Be (Join-Path $env:APPDATA 'Foo')
        }

        It "leaves an unknown token verbatim instead of blanking it" {
            # Blanking would silently turn the path relative and link the wrong place.
            Expand-PathTokens -Path '%NoSuchVarXYZ%\Foo' | Should -Be '%NoSuchVarXYZ%\Foo'
        }

        It "passes through a path with no tokens unchanged" {
            Expand-PathTokens -Path 'C:\plain\path' | Should -Be 'C:\plain\path'
        }

        It "returns empty input unchanged" {
            Expand-PathTokens -Path '' | Should -BeNullOrEmpty
        }
    }

    Context "Resolve-ManifestPath" {
        It "expands tokens before deciding rootedness" {
            $r = Resolve-ManifestPath -Path '%ProgramFiles%\X' -BaseDir 'C:\should\not\appear'
            $r | Should -Be (Join-Path $env:PROGRAMFILES 'X')
        }

        It "joins a relative path onto the plugin folder" {
            Resolve-ManifestPath -Path 'Reg\Install.reg' -BaseDir 'S:\Plugins\Foo' |
                Should -Be 'S:\Plugins\Foo\Reg\Install.reg'
        }

        It "keeps an absolute path as-is" {
            Resolve-ManifestPath -Path 'C:\absolute\x' -BaseDir 'S:\Plugins\Foo' |
                Should -Be 'C:\absolute\x'
        }
    }

    Context "Get-Prop case-insensitivity" {
        It "reads PascalCase and camelCase keys alike" {
            $o = [PSCustomObject]@{ From = 'pascal'; to = 'lower' }
            Get-Prop $o 'from' | Should -Be 'pascal'
            Get-Prop $o 'To'   | Should -Be 'lower'
        }

        It "returns $null for a missing key" {
            $o = [PSCustomObject]@{ A = 1 }
            Get-Prop $o 'Nope' | Should -BeNullOrEmpty
        }

        It "reads dictionary keys too" {
            $h = @{ OnEnable = 'x.reg' }
            Get-Prop $h 'onenable' | Should -Be 'x.reg'
        }
    }

    Context "Get-Manifest*Steps" {
        BeforeAll {
            $script:ManifestDir = Join-Path $script:TestRoot "manifests-steps"
            New-Item -ItemType Directory -Path $script:ManifestDir -Force | Out-Null
            $script:PluginRoot = Join-Path $script:TestRoot "fake-plugin"
            New-Item -ItemType Directory -Path $script:PluginRoot -Force | Out-Null

            $absFrom = Join-Path $script:PluginRoot 'abs1'
            $absTo   = Join-Path $env:TEMP 'PowerLinksTestAbs'
            $json    = Join-Path $script:ManifestDir "Sample.json"

            $obj = [PSCustomObject]@{
                Name = 'Sample'
                Links = @(
                    [PSCustomObject]@{ From = 'rel1\file.txt'; To = 'rel2\file.txt' }
                    [PSCustomObject]@{ From = $absFrom; To = $absTo }
                )
                Copy = @(
                    [PSCustomObject]@{ From = 'copy-src'; To = 'copy-dst' }
                )
                Registry = @(
                    [PSCustomObject]@{ OnEnable = 'Reg\install.reg' }
                    [PSCustomObject]@{ OnDisable = 'Reg\uninstall.reg' }
                )
                Process = @(
                    [PSCustomObject]@{ BeforeRevert = 'kill.cmd' }
                )
            }
            $obj | ConvertTo-Json -Depth 10 | Out-File -FilePath $json -Encoding utf8

            $script:Manifest = Get-PluginManifest -Name 'Sample' -ManifestDir $script:ManifestDir
        }

        It "loads the Sample manifest successfully" {
            $script:Manifest | Should -Not -BeNullOrEmpty
            $script:Manifest.Name | Should -Be 'Sample'
        }

        It "Get-ManifestLinks resolves relative paths to plugin root and preserves absolute" {
            $links = Get-ManifestLinks -Manifest $script:Manifest -BaseDir $script:PluginRoot
            $links.Count | Should -Be 2
            $links[0].From | Should -Be (Join-Path $script:PluginRoot 'rel1\file.txt')
            $links[0].To   | Should -Be (Join-Path $script:PluginRoot 'rel2\file.txt')
            $links[1].From | Should -Be (Join-Path $script:PluginRoot 'abs1')
            $links[1].To   | Should -Be (Join-Path $env:TEMP 'PowerLinksTestAbs')
        }

        It "Get-ManifestCopySteps returns Copy entries" {
            $steps = Get-ManifestCopySteps -Manifest $script:Manifest -BaseDir $script:PluginRoot
            $steps.Count | Should -Be 1
            $steps[0].From | Should -Be (Join-Path $script:PluginRoot 'copy-src')
        }

        It "Get-ManifestRegistrySteps returns OnEnable or OnDisable" {
            $enable  = Get-ManifestRegistrySteps -Manifest $script:Manifest -Action 'enable'  -BaseDir $script:PluginRoot
            $disable = Get-ManifestRegistrySteps -Manifest $script:Manifest -Action 'disable' -BaseDir $script:PluginRoot
            $enable.Count  | Should -Be 1
            $disable.Count | Should -Be 1
            $enable[0].RegFile  | Should -BeLike '*\Reg\install.reg'
            $disable[0].RegFile | Should -BeLike '*\Reg\uninstall.reg'
        }

        It "Get-ManifestProcessSteps returns beforeRevert scripts" {
            $steps = Get-ManifestProcessSteps -Manifest $script:Manifest -Trigger 'beforeRevert' -BaseDir $script:PluginRoot
            $steps.Count | Should -Be 1
            $steps[0].Script | Should -BeLike '*\kill.cmd'
        }

        It "returns empty arrays for absent sections" {
            $minimal = [PSCustomObject]@{ Name = 'OnlyName' }
            Get-ManifestLinks         -Manifest $minimal -BaseDir $script:PluginRoot | Should -HaveCount 0
            Get-ManifestCopySteps     -Manifest $minimal -BaseDir $script:PluginRoot | Should -HaveCount 0
            Get-ManifestProcessSteps  -Manifest $minimal -BaseDir $script:PluginRoot -Trigger beforeRevert | Should -HaveCount 0
            Get-ManifestRegistrySteps -Manifest $minimal -BaseDir $script:PluginRoot -Action enable | Should -HaveCount 0
        }
    }

    Context "Manifest paths resolve against the plugin folder" {
        # Regression guard: manifest-relative paths are relative to the plugin's own
        # folder (S:\Plugins\<Name>), NOT the global plugin root. Passing the global
        # root turned "Reg\Install.reg" into "<root>\Reg\Install.reg", which silently
        # missed the file at runtime.
        BeforeAll {
            $script:RootCase = Join-Path $script:TestRoot "manifests-nesting"
            New-Item -ItemType Directory -Path $script:RootCase -Force | Out-Null
            $json = Join-Path $script:RootCase "Vendor - Product.json"
            $content = '{ "Name": "Vendor - Product", "Registry": [ { "OnEnable": "Reg\\Install.reg" } ] }'
            $content | Out-File -FilePath $json -Encoding utf8
            $script:NestedManifest = Get-PluginManifest -Name 'Vendor - Product' -ManifestDir $script:RootCase
        }

        It "keeps the plugin name segment when joined" {
            $globalRoot = Join-Path $script:TestRoot "plugins"
            $pluginDir  = Join-Path $globalRoot 'Vendor - Product'

            $steps = Get-ManifestRegistrySteps -Manifest $script:NestedManifest -Action 'enable' -BaseDir $pluginDir
            $steps.Count | Should -Be 1
            $steps[0].RegFile | Should -Be (Join-Path $pluginDir 'Reg\Install.reg')
            $steps[0].RegFile | Should -BeLike '*\Vendor - Product\Reg\Install.reg'
        }

        It "does not collapse to the global root" {
            $globalRoot = Join-Path $script:TestRoot "plugins"
            $pluginDir  = Join-Path $globalRoot 'Vendor - Product'

            $steps = Get-ManifestRegistrySteps -Manifest $script:NestedManifest -Action 'enable' -BaseDir $pluginDir
            $steps[0].RegFile | Should -Not -Be (Join-Path $globalRoot 'Reg\Install.reg')
        }
    }
}
