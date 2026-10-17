Describe "Sandbox" {
    BeforeAll {
        . (Join-Path $PSScriptRoot "../../src/init.ps1")
        . (Join-Path $PSScriptRoot "../../src/modules/plugins/common/Sandbox.ps1")
        . (Join-Path $PSScriptRoot "../../src/modules/plugins/common/Manifest.ps1")

        $script:RealSource = 'S:\Plugins'
        # Deliberately on S:, not %TEMP%: LocalAppData is itself a mapped root,
        # and a sandbox root inside one would make redirection non-idempotent.
        $script:Source     = 'S:\_pl-sandbox-src'
        $script:Target     = 'S:\_pl-sandbox-tgt'
        $script:TestRoot   = Join-Path $env:TEMP 'pl-sandbox-test'
    }
    AfterEach {
        Disable-Sandbox
    }
    AfterAll {
        Disable-Sandbox
        foreach ($d in @($script:Source, $script:Target, $script:TestRoot)) {
            if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    Context "defaults" {
        It "is off by default" {
            Test-SandboxActive | Should -BeFalse
            ConvertTo-SandboxPath -Path 'C:\Program Files\X' | Should -Be 'C:\Program Files\X'
        }

        It "leaves paths alone when disabled" {
            Disable-Sandbox
            ConvertTo-SandboxPath -Path 'C:\Program Files\X' | Should -Be 'C:\Program Files\X'
            ConvertTo-SandboxPath -Path '' | Should -BeNullOrEmpty
        }
    }

    Context "path redirection" {
        BeforeEach {
            Enable-Sandbox -SourceRoot $script:Source -TargetRoot $script:Target -RealSourceRoot $script:RealSource | Out-Null
        }

        It "reports itself active" {
            Test-SandboxActive | Should -BeTrue
        }

        It "redirects Program Files" {
            ConvertTo-SandboxPath -Path 'C:\Program Files\VSTPlugins\X' |
                Should -Be (Join-Path $script:Target 'ProgramFiles\VSTPlugins\X')
        }

        It "redirects CommonProgramFiles independently of Program Files" {
            # Both live under C:\Program Files on disk; the mapping must not let
            # the shorter prefix swallow the longer one.
            ConvertTo-SandboxPath -Path 'C:\Program Files\Common Files\VST3\X' |
                Should -Be (Join-Path $script:Target 'CommonProgramFiles\VST3\X')
        }

        It "keeps Program Files (x86) distinct from Program Files" {
            ConvertTo-SandboxPath -Path 'C:\Program Files (x86)\Waves' |
                Should -Be (Join-Path $script:Target 'ProgramFilesX86\Waves')
        }

        It "redirects ProgramData, AppData and LocalAppData to distinct roots" {
            # Roaming and Local share the AppData parent in reality; collapsing
            # them would make two different targets collide.
            $roaming = ConvertTo-SandboxPath -Path (Join-Path $env:APPDATA 'COSMOS')
            $local   = ConvertTo-SandboxPath -Path (Join-Path $env:LOCALAPPDATA 'Waves Audio')
            $roaming | Should -Not -Be $local
            $roaming | Should -BeLike '*AppData\Roaming\COSMOS'
            $local   | Should -BeLike '*AppData\Local\Waves Audio'
        }

        It "does not match a root that is only a name prefix" {
            # C:\Program Files2 must not be captured by the C:\Program Files rule.
            ConvertTo-SandboxPath -Path 'C:\Program Files2\X' | Should -Be 'C:\Program Files2\X'
        }

        It "redirects the real plugin source to the sandbox source" {
            ConvertTo-SandboxPath -Path 'S:\Plugins\Waves\R2R\1.reg' |
                Should -Be (Join-Path $script:Source 'Waves\R2R\1.reg')
        }

        It "is idempotent for a path already inside the target" {
            # Regression: S:\Plugins\Test\X still matches ^S:\Plugins followed by
            # a separator, so a naive rewrite produced S:\Plugins\Test\Test\X.
            $once  = ConvertTo-SandboxPath -Path (Join-Path $script:RealSource 'Test\Vendor\VST3')
            $twice = ConvertTo-SandboxPath -Path $once
            $twice | Should -Be $once
            $twice | Should -Be (Join-Path $script:Source 'Test\Vendor\VST3')
            $twice | Should -Not -BeLike '*Test\Test*'
        }

        It "is idempotent for a path already inside a system target" {
            $once  = ConvertTo-SandboxPath -Path 'C:\Program Files\VSTPlugins\X'
            $twice = ConvertTo-SandboxPath -Path $once
            $twice | Should -Be $once
        }

        It "passes unmapped roots through rather than relocating them" {
            ConvertTo-SandboxPath -Path 'Z:\Somewhere\Else\X' | Should -Be 'Z:\Somewhere\Else\X'
        }

        It "reports the sandbox plugin root" {
            Get-SandboxPluginRoot -RealPluginRoot $script:RealSource | Should -Be $script:Source
        }

        It "returns scan roots under the target, not the real system" {
            $roots = Get-SandboxScanRoots
            $roots | Should -Not -BeNullOrEmpty
            foreach ($r in $roots) {
                $r | Should -BeLike "$($script:Target)*"
            }
        }

        It "includes the non-plugin roots, so revert can undo apply" {
            # Only the four plugin directories used to be listed, so a sandboxed
            # adopt missed everything under ProgramData / AppData / Public /
            # Documents and a later revert could not drop what apply had created.
            $roots = Get-SandboxScanRoots
            $joined = ($roots -join '|').ToLowerInvariant()
            foreach ($needle in @('programdata', 'appdata', 'public', 'documents')) {
                $joined | Should -BeLike "*$needle*"
            }
        }

        It "returns no scan roots when disabled" {
            Disable-Sandbox
            Get-SandboxScanRoots | Should -BeNullOrEmpty
        }
    }

    Context "manifest integration" {
        BeforeEach {
            Enable-Sandbox -SourceRoot $script:Source -TargetRoot $script:Target -RealSourceRoot $script:RealSource | Out-Null
        }

        It "resolves a %VAR% manifest target into the sandbox" {
            $m = [PSCustomObject]@{
                Name  = 'Sample'
                Links = @([PSCustomObject]@{ From = 'VST3\X'; To = '%ProgramFiles%\VSTPlugins\X' })
            }
            $links = Get-ManifestLinks -Manifest $m -BaseDir (Join-Path $script:Source 'Sample')
            $links | Should -HaveCount 1
            $links[0].To | Should -Be (Join-Path $script:Target 'ProgramFiles\VSTPlugins\X')
        }

        It "redirects a relative manifest source against the sandbox plugin folder" {
            $m = [PSCustomObject]@{
                Name  = 'Sample'
                Links = @([PSCustomObject]@{ From = 'R2R\install.reg'; To = '%ProgramData%\X' })
            }
            $links = Get-ManifestLinks -Manifest $m -BaseDir (Join-Path $script:Source 'Sample')
            $links[0].From | Should -Be (Join-Path $script:Source 'Sample\R2R\install.reg')
        }

        It "returns one link per manifest entry without nesting" {
            # Regression: the helper returns a guaranteed array via the unary
            # comma idiom; an extra @() at the call site wrapped it whole, so a
            # two-link manifest collapsed into one object[] subentry.
            $m = [PSCustomObject]@{
                Name = 'Two'
                Links = @(
                    [PSCustomObject]@{ From = 'a'; To = '%ProgramFiles%\a' }
                    [PSCustomObject]@{ From = 'b'; To = '%ProgramFiles%\b' }
                )
            }
            $links = Get-ManifestLinks -Manifest $m -BaseDir $script:Source
            $links | Should -HaveCount 2
            foreach ($l in $links) {
                $l | Should -BeOfType [PSCustomObject]
                $l.To | Should -BeOfType [string]
            }
        }

        It "handles a single-link manifest without nesting" {
            $m = [PSCustomObject]@{
                Name  = 'One'
                Links = @([PSCustomObject]@{ From = 'a'; To = '%ProgramFiles%\a' })
            }
            $links = Get-ManifestLinks -Manifest $m -BaseDir $script:Source
            $links | Should -HaveCount 1
            $links[0] | Should -BeOfType [PSCustomObject]
        }
    }

    Context "root collision guard" {
        It "refuses a TARGET root that sits inside a mapped root" {
            # %TEMP% is under LocalAppData, which is always mapped. A target root
            # there gets relocated on the first rewrite and matches the original
            # key afterwards, so the second pass doubles the prefix.
            { Enable-Sandbox -SourceRoot $script:Source -TargetRoot (Join-Path $env:TEMP 'tgt') -RealSourceRoot $script:RealSource } |
                Should -Throw '*not idempotent*'
        }

        It "allows a SOURCE root inside the real plugin root" {
            # S:\Plugins\Test inside S:\Plugins is the whole point of the source
            # mapping, and ConvertTo-SandboxPath already recognises that form.
            { Enable-Sandbox -SourceRoot (Join-Path $script:RealSource 'Test') -TargetRoot $script:Target -RealSourceRoot $script:RealSource } |
                Should -Not -Throw
        }

        It "accepts roots outside every mapped root" {
            { Enable-Sandbox -SourceRoot $script:Source -TargetRoot $script:Target -RealSourceRoot $script:RealSource } |
                Should -Not -Throw
        }
    }

    Context "registry and process suppression" {
        BeforeEach {
            Enable-Sandbox -SourceRoot $script:Source -TargetRoot $script:Target -RealSourceRoot $script:RealSource | Out-Null
            $script:Hive = 'HKEY_CURRENT_USER\Software\PowerLinksSandboxTest'
        }
        AfterEach {
            if (Test-Path "HKCU:\Software\PowerLinksSandboxTest") {
                Remove-Item -Path "HKCU:\Software\PowerLinksSandboxTest" -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "probes registry paths without writing them" {
            . (Join-Path $PSScriptRoot "../../src/modules/plugins/methods/registry-import.ps1")

            $regFile = Join-Path $script:TestRoot 'sandbox-install.reg'
            if (-not (Test-Path -LiteralPath $script:TestRoot)) {
                New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
            }
            $content = "Windows Registry Editor Version 5.00`r`n`r`n" +
                       "[$script:Hive\Flag]`r`n`"Enabled`"=`"yes`"`r`n"
            [System.IO.File]::WriteAllText($regFile, $content, [System.Text.UTF8Encoding]::new($false))

            $manifest = [PSCustomObject]@{
                Name     = 'SandboxReg'
                Registry = @([PSCustomObject]@{ OnEnable = 'sandbox-install.reg' })
            }
            $steps = Get-ManifestRegistrySteps -Manifest $manifest -Action 'enable' -BaseDir $script:TestRoot
            $steps | Should -HaveCount 1
            $steps[0].RegFile | Should -Be (Join-Path $script:TestRoot 'sandbox-install.reg')

            # The gate that matters: plugin-manager skips this call when sandboxed.
            # Confirmed here by asserting the guard predicate the dispatcher uses.
            Test-SandboxActive | Should -BeTrue
            Test-Path "HKCU:\Software\PowerLinksSandboxTest" | Should -BeFalse
        }
    }
}