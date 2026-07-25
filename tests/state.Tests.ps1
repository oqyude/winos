Describe "State.ps1" {
    BeforeAll {
        . (Join-Path $PSScriptRoot "../src/modules/common/State.ps1")
        $script:TestDir = Join-Path $env:TEMP "winos-state-test"
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

    Context "Get-SymlinkSubState" {
        It "missing: returns exists=false, kind=missing" {
            $result = Get-SymlinkSubState -From "X:\nonexistent\src" -To "X:\nonexistent\dst"
            $result.exists | Should -Be $false
            $result.kind | Should -Be 'missing'
            $result.target | Should -BeNullOrEmpty
            $result.matches | Should -Be $false
        }

        It "symlink match: returns exists=true, kind=symlink, matches=true" {
            $src = Join-Path $script:TestDir "src.txt"
            $dst = Join-Path $script:TestDir "link.txt"
            "x" | Out-File -FilePath $src -Encoding utf8
            New-Item -ItemType SymbolicLink -Path $dst -Value $src -Force | Out-Null

            $result = Get-SymlinkSubState -From $src -To $dst
            $result.exists | Should -Be $true
            $result.kind | Should -Be 'symlink'
            $result.matches | Should -Be $true
        }

        It "symlink drift: returns kind=symlink, matches=false" {
            $realSrc = Join-Path $script:TestDir "real.txt"
            $wrongSrc = Join-Path $script:TestDir "wrong.txt"
            $dst = Join-Path $script:TestDir "link.txt"
            "x" | Out-File -FilePath $realSrc -Encoding utf8
            "y" | Out-File -FilePath $wrongSrc -Encoding utf8
            New-Item -ItemType SymbolicLink -Path $dst -Value $wrongSrc -Force | Out-Null

            $result = Get-SymlinkSubState -From $realSrc -To $dst
            $result.kind | Should -Be 'symlink'
            $result.matches | Should -Be $false
        }

        It "regular file: returns kind=file" {
            $src = Join-Path $script:TestDir "src.txt"
            $dst = Join-Path $script:TestDir "regular.txt"
            "x" | Out-File -FilePath $src -Encoding utf8
            "y" | Out-File -FilePath $dst -Encoding utf8

            $result = Get-SymlinkSubState -From $src -To $dst
            $result.kind | Should -Be 'file'
            $result.exists | Should -Be $true
        }

        It "regular dir: returns kind=directory" {
            $src = Join-Path $script:TestDir "src"
            $dst = Join-Path $script:TestDir "dir"
            New-Item -ItemType Directory -Path $src -Force | Out-Null
            New-Item -ItemType Directory -Path $dst -Force | Out-Null

            $result = Get-SymlinkSubState -From $src -To $dst
            $result.kind | Should -Be 'directory'
        }

        It "broken symlink: returns kind=broken-symlink" {
            $src = Join-Path $script:TestDir "nonexistent.txt"
            $dst = Join-Path $script:TestDir "broken.lnk"
            New-Item -ItemType SymbolicLink -Path $dst -Value $src -Force | Out-Null

            $result = Get-SymlinkSubState -From $src -To $dst
            $result.kind | Should -Be 'broken-symlink'
        }
    }

    Context "Compare-State" {
        It "missing → create" {
            $entry = [PSCustomObject]@{
                name      = "TestApp"
                method    = "symlink"
                from      = "X:\nonexistent"
                to        = "X:\nonexistent\dst"
                subentries = @(
                    [PSCustomObject]@{
                        from  = "X:\nonexistent\a"
                        to    = "X:\nonexistent\dst\a"
                        state = [PSCustomObject]@{ exists = $false; kind = 'missing'; target = $null; matches = $false }
                    }
                )
            }
            $result = Compare-State -EntryState $entry
            $result.subentries[0].action | Should -Be 'create'
        }

        It "symlink match → noop" {
            $entry = [PSCustomObject]@{
                name      = "TestApp"
                method    = "symlink"
                from      = "X:\src"
                to        = "X:\dst"
                subentries = @(
                    [PSCustomObject]@{
                        from  = "X:\src\a"
                        to    = "X:\dst\a"
                        state = [PSCustomObject]@{ exists = $true; kind = 'symlink'; target = "X:\src\a"; matches = $true }
                    }
                )
            }
            $result = Compare-State -EntryState $entry
            $result.subentries[0].action | Should -Be 'noop'
        }

        It "symlink drift → replace" {
            $entry = [PSCustomObject]@{
                name      = "TestApp"
                method    = "symlink"
                from      = "X:\src"
                to        = "X:\dst"
                subentries = @(
                    [PSCustomObject]@{
                        from  = "X:\src\a"
                        to    = "X:\dst\a"
                        state = [PSCustomObject]@{ exists = $true; kind = 'symlink'; target = "X:\old"; matches = $false }
                    }
                )
            }
            $result = Compare-State -EntryState $entry
            $result.subentries[0].action | Should -Be 'replace'
        }

        It "regular file → conflict" {
            $entry = [PSCustomObject]@{
                name      = "TestApp"
                method    = "symlink"
                from      = "X:\src"
                to        = "X:\dst"
                subentries = @(
                    [PSCustomObject]@{
                        from  = "X:\src\a"
                        to    = "X:\dst\a"
                        state = [PSCustomObject]@{ exists = $true; kind = 'file'; target = $null; matches = $false }
                    }
                )
            }
            $result = Compare-State -EntryState $entry
            $result.subentries[0].action | Should -Be 'conflict'
        }
    }

    Context "Compare-State with Desired=missing (enabled=false)" {
        It "missing + desired=missing → noop" {
            $entry = [PSCustomObject]@{
                name      = "TestApp"
                method    = "symlink"
                from      = "X:\src"
                to        = "X:\dst"
                subentries = @(
                    [PSCustomObject]@{
                        from  = "X:\src\a"
                        to    = "X:\dst\a"
                        state = [PSCustomObject]@{ exists = $false; kind = 'missing'; target = $null; matches = $false }
                    }
                )
            }
            $result = Compare-State -EntryState $entry -Desired 'missing'
            $result.subentries[0].action | Should -Be 'noop'
        }

        It "symlink + desired=missing → drop" {
            $entry = [PSCustomObject]@{
                name      = "TestApp"
                method    = "symlink"
                from      = "X:\src"
                to        = "X:\dst"
                subentries = @(
                    [PSCustomObject]@{
                        from  = "X:\src\a"
                        to    = "X:\dst\a"
                        state = [PSCustomObject]@{ exists = $true; kind = 'symlink'; target = "X:\src\a"; matches = $true }
                    }
                )
            }
            $result = Compare-State -EntryState $entry -Desired 'missing'
            $result.subentries[0].action | Should -Be 'drop'
        }

        It "regular file + desired=missing → drop" {
            $entry = [PSCustomObject]@{
                name      = "TestApp"
                method    = "symlink"
                from      = "X:\src"
                to        = "X:\dst"
                subentries = @(
                    [PSCustomObject]@{
                        from  = "X:\src\a"
                        to    = "X:\dst\a"
                        state = [PSCustomObject]@{ exists = $true; kind = 'file'; target = $null; matches = $false }
                    }
                )
            }
            $result = Compare-State -EntryState $entry -Desired 'missing'
            $result.subentries[0].action | Should -Be 'drop'
        }

        It "drop actually removes the symlink" {
            $src = Join-Path $script:TestDir "src-for-drop"
            $dst = Join-Path $script:TestDir "link-for-drop"
            New-Item -ItemType Directory -Path $src -Force | Out-Null
            "x" | Out-File -FilePath (Join-Path $src "f.txt") -Encoding utf8
            New-Item -ItemType SymbolicLink -Path $dst -Value $src -Force | Out-Null

            Test-Path $dst | Should -Be $true

            $entry = [PSCustomObject]@{
                name      = "DropTest"
                method    = "symlink"
                from      = $src
                to        = $dst
                subentries = @(
                    [PSCustomObject]@{
                        from  = $src
                        to    = $dst
                        state = Get-SymlinkSubState -From $src -To $dst
                    }
                )
            }
            $categorized = Compare-State -EntryState $entry -Desired 'missing'
            $results = Invoke-SafeAction -EntryState $categorized

            $results[0].status | Should -Be 'removed'
            Test-Path $dst | Should -Be $false
            # Source directory must NOT be touched
            Test-Path (Join-Path $src "f.txt") | Should -Be $true
        }
    }

    Context "Resolve-EntryPath" {
        BeforeAll {
            . (Join-Path $PSScriptRoot "../src/init.ps1")
        }

        It "expands $persist, $env:USERPROFILE, and $name" {
            $entry = [PSCustomObject]@{
                name = "TestApp"
                from = '$persist\$name'
                to   = '$env:USERPROFILE\.test'
            }
            $result = Resolve-EntryPath -Entry $entry
            $result.From | Should -Be "$persist\TestApp"
            $result.To   | Should -Be (Join-Path $env:USERPROFILE ".test")
        }
    }

    Context "Get-SymlinkEntryState" {
        It "expands and probes each (from, to) pair" {
            $srcDir = Join-Path $script:TestDir "src1"
            $dstDir = Join-Path $script:TestDir "dst1"
            New-Item -ItemType Directory -Path $srcDir -Force | Out-Null
            New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
            "x" | Out-File -FilePath (Join-Path $srcDir "a.txt") -Encoding utf8
            New-Item -ItemType SymbolicLink -Path (Join-Path $dstDir "a.txt") -Value (Join-Path $srcDir "a.txt") -Force | Out-Null

            $entry = [PSCustomObject]@{
                name     = "TestApp"
                method   = "symlink"
                from     = $srcDir
                to       = $dstDir
                mappings = @(
                    [PSCustomObject]@{ from = "a.txt"; to = "a.txt" }
                )
            }
            $result = Get-SymlinkEntryState -Entry $entry
            $result.subentries.Count | Should -Be 1
            $result.subentries[0].state.kind | Should -Be 'symlink'
            $result.subentries[0].state.matches | Should -Be $true
        }
    }
}
