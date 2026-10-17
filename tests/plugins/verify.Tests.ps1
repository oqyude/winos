Describe "Verify.ps1" {
    BeforeAll {
        . (Join-Path $PSScriptRoot "../../src/init.ps1")
        . (Join-Path $PSScriptRoot "../../src/modules/plugins/common/Sandbox.ps1")
        . (Join-Path $PSScriptRoot "../../src/modules/plugins/common/Manifest.ps1")
        . (Join-Path $PSScriptRoot "../../src/modules/plugins/common/Verify.ps1")

        $script:Root = Join-Path $env:TEMP "powerlinks-verify-test"
        if (Test-Path $script:Root) { Remove-Item $script:Root -Recurse -Force }
        New-Item -ItemType Directory -Path $script:Root -Force | Out-Null

        $script:Manifests = Join-Path $script:Root "manifests"
        New-Item -ItemType Directory -Path $script:Manifests -Force | Out-Null
    }
    AfterAll {
        Disable-Sandbox
        if (Test-Path $script:Root) { Remove-Item $script:Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    Context "Get-VerifyReport" {
        It "reports no problems when every source exists" {
            $src = Join-Path $script:Root "present-src"
            New-Item -ItemType Directory -Path $src -Force | Out-Null

            $entries = @(
                [PSCustomObject]@{
                    name     = 'Good'
                    from     = $null
                    mappings = @([PSCustomObject]@{ From = $src; To = (Join-Path $script:Root 'link') })
                }
            )

            $r = Get-VerifyReport -Entries $entries -PluginRoot $script:Root -ManifestDir $script:Manifests
            $r.Problems | Should -HaveCount 0
            $r.Checked   | Should -Be 1
        }

        It "flags a link whose source is missing" {
            $entries = @(
                [PSCustomObject]@{
                    name     = 'Bad'
                    from     = $null
                    mappings = @([PSCustomObject]@{
                        From = (Join-Path $script:Root 'absent')
                        To   = (Join-Path $script:Root 'link2')
                    })
                }
            )

            $r = Get-VerifyReport -Entries $entries -PluginRoot $script:Root -ManifestDir $script:Manifests
            $r.Problems | Should -HaveCount 1
            $r.Problems[0].Kind | Should -Be 'MISSING_SRC'
            $r.Problems[0].Plugin | Should -Be 'Bad'
        }

        It "flags an entry that resolved to no mappings at all" {
            # Regression: an absent mappings property arrives as $null, and
            # @($null) is a one-element array. Counting it as an array without
            # filtering nulls makes .Count equal 1, so this check was skipped and
            # verify reported OK for entries that resolve to nothing.
            $entries = @(
                [PSCustomObject]@{ name = 'Nothing'; from = $null; mappings = $null }
            )

            $r = Get-VerifyReport -Entries $entries -PluginRoot $script:Root -ManifestDir $script:Manifests
            $r.Problems | Should -HaveCount 1
            $r.Problems[0].Kind | Should -Be 'NO_MAPPINGS'
        }

        It "treats an explicitly empty mappings array the same as null" {
            $entries = @(
                [PSCustomObject]@{ name = 'Empty'; from = $null; mappings = @() }
            )

            $r = Get-VerifyReport -Entries $entries -PluginRoot $script:Root -ManifestDir $script:Manifests
            $r.Problems | Should -HaveCount 1
            $r.Problems[0].Kind | Should -Be 'NO_MAPPINGS'
        }

        It "does not flag an entry that uses the legacy single from/to form" {
            $src = Join-Path $script:Root "legacy-src"
            New-Item -ItemType Directory -Path $src -Force | Out-Null

            $entries = @(
                [PSCustomObject]@{
                    name = 'Legacy'; from = $src; to = (Join-Path $script:Root 'legacy-link')
                    mappings = $null
                }
            )

            $r = Get-VerifyReport -Entries $entries -PluginRoot $script:Root -ManifestDir $script:Manifests
            $r.Problems | Should -HaveCount 0
        }

        It "flags a registry file the manifest points at but that is absent" {
            $plugin = Join-Path $script:Root "RegPlugin"
            New-Item -ItemType Directory -Path $plugin -Force | Out-Null

            $m = [PSCustomObject]@{
                Name = 'RegPlugin'
                Links = @([PSCustomObject]@{
                    From = (Join-Path $plugin 'VST3\Thing'); To = '%CommonProgramFiles%\VST3\Thing'
                })
                Registry = @(
                    [PSCustomObject]@{ OnEnable = 'Reg\missing.reg' }
                    [PSCustomObject]@{ OnDisable = 'Reg\missing.reg' }
                )
            }
            $m | ConvertTo-Json -Depth 10 | Out-File -FilePath (Join-Path $script:Manifests 'RegPlugin.json') -Encoding utf8

            $entries = @(
                [PSCustomObject]@{
                    name     = 'RegPlugin'
                    from     = $null
                    mappings = @([PSCustomObject]@{
                        From = (Join-Path $plugin 'VST3\Thing'); To = (Join-Path $script:Root 'vst3-thing')
                    })
                }
            )

            $r = Get-VerifyReport -Entries $entries -PluginRoot $script:Root -ManifestDir $script:Manifests
            # one MISSING_REG per direction (enable + disable), plus MISSING_SRC for the link
            ($r.Problems | Where-Object { $_.Kind -eq 'MISSING_REG' }) | Should -HaveCount 2
        }

        It "flags a missing process script" {
            $plugin = Join-Path $script:Root "ProcPlugin"
            New-Item -ItemType Directory -Path $plugin -Force | Out-Null

            $m = [PSCustomObject]@{
                Name    = 'ProcPlugin'
                Process = @([PSCustomObject]@{ BeforeRevert = 'kill.cmd' })
            }
            $m | ConvertTo-Json -Depth 10 | Out-File -FilePath (Join-Path $script:Manifests 'ProcPlugin.json') -Encoding utf8

            $entries = @([PSCustomObject]@{ name = 'ProcPlugin'; from = $plugin; mappings = $null })

            $r = Get-VerifyReport -Entries $entries -PluginRoot $script:Root -ManifestDir $script:Manifests
            $r.Problems | Where-Object { $_.Kind -eq 'MISSING_SCRIPT' } | Should -HaveCount 1
        }

        It "ignores an entry with no manifest on disk" {
            $entries = @(
                [PSCustomObject]@{
                    name = 'NoManifest'
                    from = $null
                    mappings = @([PSCustomObject]@{
                        From = (Join-Path $script:Root 'nm-src'); To = (Join-Path $script:Root 'nm-link')
                    })
                }
            )

            $r = Get-VerifyReport -Entries $entries -PluginRoot $script:Root -ManifestDir $script:Manifests
            $r.Problems | Should -HaveCount 1   # MISSING_SRC only, no manifest noise
            $r.Problems[0].Kind | Should -Be 'MISSING_SRC'
        }

        It "returns an empty report for an empty entry list" {
            $r = Get-VerifyReport -Entries @() -PluginRoot $script:Root -ManifestDir $script:Manifests
            $r.Problems | Should -HaveCount 0
            $r.Checked   | Should -Be 0
        }
    }
}