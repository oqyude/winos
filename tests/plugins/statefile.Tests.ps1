Describe "StateFile.ps1" {
    BeforeAll {
        . (Join-Path $PSScriptRoot "../../src/init.ps1")
        . (Join-Path $PSScriptRoot "../../src/modules/plugins/common/StateFile.ps1")
        $script:TestDir = Join-Path $env:TEMP "powerlinks-statefile-test"
        if (Test-Path $script:TestDir) {
            Remove-Item $script:TestDir -Recurse -Force
        }
        New-Item -ItemType Directory -Path $script:TestDir -Force | Out-Null
    }
    AfterAll {
        if (Test-Path $script:TestDir) {
            Remove-Item $script:TestDir -Recurse -Force
        }
    }

    Context "Read-PowerLinksState" {
        It "missing file returns empty default" {
            $missing = Join-Path $script:TestDir "nope.json"
            $result = Read-PowerLinksState -Path $missing
            $result.version | Should -Be $stateVersion
            $result.tool_version | Should -Be $toolVersion
            $result.plugins.Count | Should -Be 0
        }

        It "empty file returns empty default" {
            $empty = Join-Path $script:TestDir "empty.json"
            "" | Out-File -FilePath $empty -Encoding utf8
            $result = Read-PowerLinksState -Path $empty
            $result.plugins.Count | Should -Be 0
        }

        It "malformed file returns empty default and warns" {
            $bad = Join-Path $script:TestDir "bad.json"
            "{ this is not json" | Out-File -FilePath $bad -Encoding utf8
            $result = Read-PowerLinksState -Path $bad 3>$null
            $result.plugins.Count | Should -Be 0
        }

        It "parses full file and strips phantom null entries" {
            $full = Join-Path $script:TestDir "full.json"
            @"
{
  "version": 1,
  "tool_version": "0.0.1",
  "plugins": [
    { "name": "A", "link": true, "ignore": false, "from": "S:\\A", "to": "C:\\A" },
    null,
    { "name": "B", "link": false, "ignore": true },
    null
  ]
}
"@ | Out-File -FilePath $full -Encoding utf8

            $result = Read-PowerLinksState -Path $full
            $result.plugins.Count | Should -Be 2
            $result.plugins[0].name | Should -Be 'A'
            $result.plugins[1].name | Should -Be 'B'
        }
    }

    Context "Write-PowerLinksState" {
        It "creates parent dir if missing" {
            $deep = Join-Path $script:TestDir "deep\nested\file.json"
            $payload = [PSCustomObject]@{
                version = 1
                tool_version = "0.0.1"
                plugins = @()
            }
            Write-PowerLinksState -Path $deep -Data $payload
            Test-Path $deep | Should -Be $true
        }

        It "round-trips through Read-PowerLinksState" {
            $path = Join-Path $script:TestDir "roundtrip.json"
            $payload = [PSCustomObject]@{
                version = 1
                tool_version = "0.0.1"
                plugins = @(
                    [PSCustomObject]@{
                        name = "Vendor - Product"
                        link = $true
                        ignore = $false
                        from = 'S:\Plugins\Vendor - Product'
                        to = 'C:\Program Files\VSTPlugins\Vendor - Product'
                    }
                )
            }
            Write-PowerLinksState -Path $path -Data $payload
            $read = Read-PowerLinksState -Path $path
            $read.version | Should -Be 1
            $read.plugins.Count | Should -Be 1
            $read.plugins[0].name | Should -Be 'Vendor - Product'
            $read.plugins[0].link | Should -Be $true
            $read.plugins[0].from | Should -Be 'S:\Plugins\Vendor - Product'
            $read.plugins[0].to | Should -Be 'C:\Program Files\VSTPlugins\Vendor - Product'
        }
    }

    Context "Get-EnabledPlugins" {
        It "filters out ignored entries" {
            $state = [PSCustomObject]@{
                plugins = @(
                    [PSCustomObject]@{ name = "A"; link = $true;  ignore = $false },
                    [PSCustomObject]@{ name = "B"; link = $false; ignore = $true  },
                    [PSCustomObject]@{ name = "C"; link = $true;  ignore = $false }
                )
            }
            $result = Get-EnabledPlugins -State $state
            $result.Count | Should -Be 2
            $result[0].name | Should -Be 'A'
            $result[1].name | Should -Be 'C'
        }

        It "defaults missing link to false and missing ignore to false" {
            $state = [PSCustomObject]@{
                plugins = @(
                    [PSCustomObject]@{ name = "A" }
                )
            }
            $result = Get-EnabledPlugins -State $state
            $result.Count | Should -Be 1
            $result[0].link | Should -Be $false
            $result[0].ignore | Should -Be $false
        }

        It "preserves explicit ignore=true (skipped)" {
            $state = [PSCustomObject]@{
                plugins = @(
                    [PSCustomObject]@{ name = "A"; ignore = $true }
                )
            }
            $result = Get-EnabledPlugins -State $state
            $result.Count | Should -Be 0
        }
    }
}
