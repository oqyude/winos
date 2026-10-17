Describe "State.ps1" {
    BeforeAll {
        . (Join-Path $PSScriptRoot "../../src/modules/common/State.ps1")
        $script:TestDir = Join-Path $env:TEMP "powerlinks-state-test"
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

        It "junction match: returns exists=true, kind=symlink, matches=true" {
            $src = Join-Path $script:TestDir "src.txt"
            $dst = Join-Path $script:TestDir "link.txt"
            "x" | Out-File -FilePath $src -Encoding utf8
            # File targets: SymbolicLink only (Junction requires a directory).
            New-Item -ItemType SymbolicLink -Path $dst -Value $src -Force | Out-Null

            $result = Get-SymlinkSubState -From $src -To $dst
            $result.exists | Should -Be $true
            $result.kind | Should -Be 'symlink'
            $result.matches | Should -Be $true
        }

        It "junction drift: returns kind=symlink, matches=false" {
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
            $src = Join-Path $script:TestDir "src2.txt"
            $dst = Join-Path $script:TestDir "regular.txt"
            "x" | Out-File -FilePath $src -Encoding utf8
            "y" | Out-File -FilePath $dst -Encoding utf8

            $result = Get-SymlinkSubState -From $src -To $dst
            $result.kind | Should -Be 'file'
            $result.exists | Should -Be $true
        }

        It "regular dir: returns kind=directory" {
            $src = Join-Path $script:TestDir "src2"
            $dst = Join-Path $script:TestDir "dir"
            New-Item -ItemType Directory -Path $src -Force | Out-Null
            New-Item -ItemType Directory -Path $dst -Force | Out-Null

            $result = Get-SymlinkSubState -From $src -To $dst
            $result.kind | Should -Be 'directory'
        }

        It "broken junction: returns kind=broken-symlink" {
            $src = Join-Path $script:TestDir "nonexistent.txt"
            $dst = Join-Path $script:TestDir "broken.jct"
            # SymbolicLink allows nonexistent source (Junction requires a real dir).
            New-Item -ItemType SymbolicLink -Path $dst -Value $src -Force | Out-Null

            $result = Get-SymlinkSubState -From $src -To $dst
            $result.kind | Should -Be 'broken-symlink'
        }
    }

    Context "Compare-State" {
        It "missing -> create" {
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

        It "junction match -> noop" {
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

        It "junction drift -> replace" {
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

        It "regular file -> conflict" {
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

    Context "Compare-State with Desired=missing (link=false)" {
        It "missing + desired=missing -> noop" {
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

        It "junction + desired=missing -> drop" {
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

        It "regular file + desired=missing -> drop" {
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

        It "drop actually removes the junction" {
            $src = Join-Path $script:TestDir "src-for-drop"
            $dst = Join-Path $script:TestDir "link-for-drop"
            New-Item -ItemType Directory -Path $src -Force | Out-Null
            "x" | Out-File -FilePath (Join-Path $src "f.txt") -Encoding utf8
            New-Item -ItemType Junction -Path $dst -Value $src -Force | Out-Null

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
            . (Join-Path $PSScriptRoot "../../src/init.ps1")
        }

        It "expands `$pluginRoot, `$env:USERPROFILE, and `$name" {
            $entry = [PSCustomObject]@{
                name = "TestApp"
                from = '$pluginRoot\$name'
                to   = '$env:USERPROFILE\.powerlinks-test'
            }
            $result = Resolve-EntryPath -Entry $entry
            $result.From | Should -Be "$pluginRoot\TestApp"
            $result.To   | Should -Be (Join-Path $env:USERPROFILE ".powerlinks-test")
        }
    }

    Context "Invoke-SafeAction refuses a missing source" {
        BeforeAll {
            $script:GapRoot = Join-Path $env:TEMP "powerlinks-gapsrc-test"
            if (Test-Path $script:GapRoot) { Remove-Item $script:GapRoot -Recurse -Force }
            New-Item -ItemType Directory -Path $script:GapRoot -Force | Out-Null
        }
        AfterAll {
            if (Test-Path $script:GapRoot) { Remove-Item $script:GapRoot -Recurse -Force -ErrorAction SilentlyContinue }
        }

        It "reports failure instead of creating a link to nothing" {
            # Junction and SymbolicLink both accept a target that does not exist,
            # so without this guard a wrong manifest path yields a field of broken
            # links and a summary that claims success.
            $absent = Join-Path $script:GapRoot "not-there"
            $to     = Join-Path $script:GapRoot "created-anyway"

            $entry = [PSCustomObject]@{
                name   = 'GapSrc'
                method = 'symlink'
                subentries = @(
                    [PSCustomObject]@{
                        from  = $absent
                        to    = $to
                        state = Get-SymlinkSubState -From $absent -To $to
                        action = 'create'
                    }
                )
            }

            $results = Invoke-SafeAction -EntryState $entry
            $results[0].status | Should -Be 'failed'
            $results[0].note   | Should -BeLike '*does not exist*'
            Test-Path -LiteralPath $to | Should -BeFalse
        }

        It "does not touch the existing target when the source is missing" {
            $absent = Join-Path $script:GapRoot "still-not-there"
            $to     = Join-Path $script:GapRoot "existing-target"
            New-Item -ItemType Directory -Path $to -Force | Out-Null
            "keep" | Out-File -FilePath (Join-Path $to "important.txt") -Encoding utf8

            $entry = [PSCustomObject]@{
                name   = 'GapSrcReplace'
                method = 'symlink'
                subentries = @(
                    [PSCustomObject]@{
                        from  = $absent
                        to    = $to
                        state = Get-SymlinkSubState -From $absent -To $to
                        action = 'replace'
                    }
                )
            }

            $results = Invoke-SafeAction -EntryState $entry -Force
            $results[0].status | Should -Be 'failed'
            Test-Path -LiteralPath (Join-Path $to "important.txt") | Should -BeTrue
        }

        It "still creates when the source does exist" {
            $src = Join-Path $script:GapRoot "real-src"
            $to  = Join-Path $script:GapRoot "real-link"
            New-Item -ItemType Directory -Path $src -Force | Out-Null

            $entry = [PSCustomObject]@{
                name   = 'OkSrc'
                method = 'symlink'
                subentries = @(
                    [PSCustomObject]@{
                        from  = $src
                        to    = $to
                        state = Get-SymlinkSubState -From $src -To $to
                        action = 'create'
                    }
                )
            }

            $results = Invoke-SafeAction -EntryState $entry
            $results[0].status | Should -Be 'created'
            Test-Path -LiteralPath $to | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $to '.') | Should -BeTrue

            cmd /c rmdir "$to" 2>&1 | Out-Null
        }
    }

    Context "Invoke-SafeAction picks the link type from the source kind" {
        BeforeAll {
            $script:TypeRoot = Join-Path $env:TEMP "powerlinks-linktype-test"
            if (Test-Path $script:TypeRoot) { Remove-Item $script:TypeRoot -Recurse -Force }
            New-Item -ItemType Directory -Path $script:TypeRoot -Force | Out-Null
        }
        AfterAll {
            if (Test-Path $script:TypeRoot) { Remove-Item $script:TypeRoot -Recurse -Force -ErrorAction SilentlyContinue }
        }

        It "creates a Junction, not a SymbolicLink, when the source is a directory" {
            # This is the single behavioural change the plugins engine makes over
            # the winos one, and nothing asserted it. SymbolicLink needs
            # elevation or Developer Mode; a Junction needs neither, so picking
            # the right type is what keeps plugin deployment non-elevated. A
            # regression here would fail silently, at apply time on a real
            # machine, as an "access denied" no test ever saw coming.
            $src = Join-Path $script:TypeRoot "dir-src"
            $to  = Join-Path $script:TypeRoot "dir-link"
            New-Item -ItemType Directory -Path $src -Force | Out-Null

            $entry = [PSCustomObject]@{
                name   = 'TypeSrc'
                method = 'symlink'
                subentries = @(
                    [PSCustomObject]@{
                        from  = $src
                        to    = $to
                        state = Get-SymlinkSubState -From $src -To $to
                        action = 'create'
                    }
                )
            }

            $results = Invoke-SafeAction -EntryState $entry

            $results[0].status | Should -Be 'created'
            $results[0].note   | Should -Be 'Junction'
            # Independent of the reported note: ask the filesystem what it is.
            (Get-Item -LiteralPath $to -Force).LinkType | Should -Be 'Junction'

            cmd /c rmdir "$to" 2>&1 | Out-Null
        }

        It "creates a SymbolicLink when the source is a file" {
            # Junction cannot target a file at all, so this branch has no
            # alternative. Tolerates a machine without Developer Mode, which
            # cannot create file symlinks without elevation.
            $src = Join-Path $script:TypeRoot "file-src.txt"
            $to  = Join-Path $script:TypeRoot "file-link.txt"
            New-Item -ItemType File -Path $src -Force | Out-Null

            $entry = [PSCustomObject]@{
                name   = 'TypeSrc'
                method = 'symlink'
                subentries = @(
                    [PSCustomObject]@{
                        from  = $src
                        to    = $to
                        state = Get-SymlinkSubState -From $src -To $to
                        action = 'create'
                    }
                )
            }

            $results = Invoke-SafeAction -EntryState $entry

            if ($results[0].status -eq 'failed') {
                Set-ItResult -Skipped -Because "file symlinks need Developer Mode or elevation"
                return
            }

            $results[0].status | Should -Be 'created'
            $results[0].note   | Should -Be 'SymbolicLink'
            (Get-Item -LiteralPath $to -Force).LinkType | Should -Be 'SymbolicLink'

            Remove-Item -LiteralPath $to -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Get-SymlinkEntryState" {
        It "expands and probes each (from, to) pair" {
            $srcDir = Join-Path $script:TestDir "src1"
            $dstDir = Join-Path $script:TestDir "dst1"
            New-Item -ItemType Directory -Path $srcDir -Force | Out-Null
            New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
            "x" | Out-File -FilePath (Join-Path $srcDir "a.txt") -Encoding utf8
            # File sublink uses SymbolicLink.
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

    Context "Invoke-SafeAction drop variants" {
        # Each test builds a real EntryState with desired=missing, runs Invoke-SafeAction,
        # and asserts the right deletion path was taken (link-only vs full remove).

        It "drops a SymbolicLink without touching the source file" {
            $src = Join-Path $script:TestDir "src-file"
            $dst = Join-Path $script:TestDir "link-file"
            New-Item -ItemType Directory -Path $src -Force | Out-Null
            "x" | Out-File -FilePath (Join-Path $src "f.txt") -Encoding utf8
            New-Item -ItemType SymbolicLink -Path $dst -Value (Join-Path $src "f.txt") -Force | Out-Null

            $entry = [PSCustomObject]@{
                name      = "DropSymlink"
                method    = "symlink"
                from      = (Join-Path $src "f.txt")
                to        = $dst
                subentries = @(
                    [PSCustomObject]@{
                        from  = (Join-Path $src "f.txt")
                        to    = $dst
                        state = Get-SymlinkSubState -From (Join-Path $src "f.txt") -To $dst
                    }
                )
            }
            $categorized = Compare-State -EntryState $entry -Desired 'missing'
            $results = Invoke-SafeAction -EntryState $categorized

            $results[0].status | Should -Be 'removed'
            $results[0].note   | Should -BeNullOrEmpty
            Test-Path $dst | Should -Be $false
            Test-Path (Join-Path $src "f.txt") | Should -Be $true
        }

        It "drops a real file at the target" {
            $realFile = Join-Path $script:TestDir "real-file.txt"
            "x" | Out-File -FilePath $realFile -Encoding utf8

            $entry = [PSCustomObject]@{
                name      = "DropRealFile"
                method    = "symlink"
                from      = "X:\nonexistent"
                to        = $realFile
                subentries = @(
                    [PSCustomObject]@{
                        from  = "X:\nonexistent"
                        to    = $realFile
                        state = Get-SymlinkSubState -From "X:\nonexistent" -To $realFile
                    }
                )
            }
            $categorized = Compare-State -EntryState $entry -Desired 'missing'
            $results = Invoke-SafeAction -EntryState $categorized

            $results[0].status | Should -Be 'removed'
            Test-Path $realFile | Should -Be $false
        }

        It "drops a real directory at the target" {
            $realDir = Join-Path $script:TestDir "real-dir"
            New-Item -ItemType Directory -Path $realDir -Force | Out-Null
            "x" | Out-File -FilePath (Join-Path $realDir "f.txt") -Encoding utf8

            $entry = [PSCustomObject]@{
                name      = "DropRealDir"
                method    = "symlink"
                from      = "X:\nonexistent"
                to        = $realDir
                subentries = @(
                    [PSCustomObject]@{
                        from  = "X:\nonexistent"
                        to    = $realDir
                        state = Get-SymlinkSubState -From "X:\nonexistent" -To $realDir
                    }
                )
            }
            $categorized = Compare-State -EntryState $entry -Desired 'missing'
            $results = Invoke-SafeAction -EntryState $categorized

            $results[0].status | Should -Be 'removed'
            Test-Path $realDir | Should -Be $false
        }

        It "drops a broken reparse point (link with no source)" {
            $src = Join-Path $script:TestDir "broken-src.txt"   # never created
            $dst = Join-Path $script:TestDir "broken-link"
            # Junction requires an existing dir, so use SymbolicLink for the broken case.
            New-Item -ItemType SymbolicLink -Path $dst -Value $src -Force | Out-Null

            $entry = [PSCustomObject]@{
                name      = "DropBroken"
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
        }
    }

    Context "Get-StateDrift" {
        BeforeAll {
            $script:DriftRoot = Join-Path $env:TEMP "powerlinks-drift-test"
            if (Test-Path $script:DriftRoot) { Remove-Item $script:DriftRoot -Recurse -Force }
            New-Item -ItemType Directory -Path $script:DriftRoot -Force | Out-Null

            # A real link so 'symlink' vs 'missing' states are real, not mocked.
            $script:RealSrc = Join-Path $script:DriftRoot "real-src"
            $script:RealDst = Join-Path $script:DriftRoot "real-dst"
            New-Item -ItemType Directory -Path $script:RealSrc -Force | Out-Null
            "x" | Out-File -FilePath (Join-Path $script:RealSrc "f.txt") -Encoding utf8
            New-Item -ItemType Junction -Path $script:RealDst -Value $script:RealSrc -Force | Out-Null
        }
        AfterAll {
            if (Test-Path $script:RealDst) {
                cmd /c rmdir "$($script:RealDst)" 2>&1 | Out-Null
            }
            if (Test-Path $script:DriftRoot) { Remove-Item $script:DriftRoot -Recurse -Force }
        }

        It "reports nothing when current matches baseline" {
            $current = @([PSCustomObject]@{
                subentries = @([PSCustomObject]@{ to = $script:RealDst; from = $script:RealSrc; state = Get-SymlinkSubState -From $script:RealSrc -To $script:RealDst })
            })
            $baseline = [PSCustomObject]@{
                entries = @([PSCustomObject]@{
                    subentries = @([PSCustomObject]@{ to = $script:RealDst; state = Get-SymlinkSubState -From $script:RealSrc -To $script:RealDst })
                })
            }
            $drift = Get-StateDrift -Current $current -Baseline $baseline
            $drift | Should -HaveCount 0
        }

        It "reports 'added' when a link exists but baseline has no record" {
            $current = @([PSCustomObject]@{
                subentries = @([PSCustomObject]@{ to = $script:RealDst; from = $script:RealSrc; state = Get-SymlinkSubState -From $script:RealSrc -To $script:RealDst })
            })
            $baseline = [PSCustomObject]@{ entries = @() }

            $drift = Get-StateDrift -Current $current -Baseline $baseline
            $drift | Should -HaveCount 1
            $drift[0].change | Should -Be 'added'
            $drift[0].to     | Should -Be $script:RealDst
        }

        It "reports 'retargeted' when the link points elsewhere" {
            $current = @([PSCustomObject]@{
                subentries = @([PSCustomObject]@{ to = $script:RealDst; from = $script:RealSrc; state = Get-SymlinkSubState -From $script:RealSrc -To $script:RealDst })
            })
            $baseline = [PSCustomObject]@{
                entries = @([PSCustomObject]@{
                    subentries = @([PSCustomObject]@{
                        to = $script:RealDst
                        state = [PSCustomObject]@{ exists = $true; kind = 'symlink'; target = 'S:\Somewhere\Else'; matches = $false }
                    })
                })
            }

            $drift = Get-StateDrift -Current $current -Baseline $baseline
            $drift | Should -HaveCount 1
            $drift[0].change | Should -Be 'retargeted'
            $drift[0].prev   | Should -Be 'S:\Somewhere\Else'
            $drift[0].now    | Should -Be $script:RealSrc
        }

        It "reports 'removed' when the link is gone" {
            $current = @([PSCustomObject]@{
                subentries = @([PSCustomObject]@{ to = (Join-Path $script:DriftRoot "gone"); from = $script:RealSrc; state = Get-SymlinkSubState -From $script:RealSrc -To (Join-Path $script:DriftRoot "gone") })
            })
            $baseline = [PSCustomObject]@{
                entries = @([PSCustomObject]@{
                    subentries = @([PSCustomObject]@{
                        to = (Join-Path $script:DriftRoot "gone")
                        state = [PSCustomObject]@{ exists = $true; kind = 'symlink'; target = $script:RealSrc; matches = $true }
                    })
                })
            }

            $drift = Get-StateDrift -Current $current -Baseline $baseline
            $drift | Should -HaveCount 1
            $drift[0].change | Should -Be 'removed'
        }

        It "reports 'orphaned' when baseline had it but nothing probes it" {
            $current = @()
            $baseline = [PSCustomObject]@{
                entries = @([PSCustomObject]@{
                    subentries = @([PSCustomObject]@{
                        to = (Join-Path $script:DriftRoot "abandoned")
                        state = [PSCustomObject]@{ exists = $true; kind = 'symlink'; target = $script:RealSrc; matches = $true }
                    })
                })
            }

            $drift = Get-StateDrift -Current $current -Baseline $baseline
            $drift | Should -HaveCount 1
            $drift[0].change | Should -Be 'orphaned'
        }

        It "matches by target path so reordering is not drift" {
            $other = Join-Path $script:DriftRoot "other"
            New-Item -ItemType Directory -Path $other -Force | Out-Null
            $otherSrc = Join-Path $other "src"
            New-Item -ItemType Directory -Path $otherSrc -Force | Out-Null
            $otherDst = Join-Path $other "dst"
            New-Item -ItemType Junction -Path $otherDst -Value $otherSrc -Force | Out-Null

            try {
                # Current order: A, B. Baseline order: B, A.
                $current = @(
                    [PSCustomObject]@{ subentries = @([PSCustomObject]@{ to = $script:RealDst; from = $script:RealSrc; state = Get-SymlinkSubState -From $script:RealSrc -To $script:RealDst }) }
                    [PSCustomObject]@{ subentries = @([PSCustomObject]@{ to = $otherDst; from = $otherSrc; state = Get-SymlinkSubState -From $otherSrc -To $otherDst }) }
                )
                $baseline = [PSCustomObject]@{
                    entries = @(
                        [PSCustomObject]@{ subentries = @([PSCustomObject]@{ to = $otherDst; state = Get-SymlinkSubState -From $otherSrc -To $otherDst }) }
                        [PSCustomObject]@{ subentries = @([PSCustomObject]@{ to = $script:RealDst; state = Get-SymlinkSubState -From $script:RealSrc -To $script:RealDst }) }
                    )
                }

                $drift = Get-StateDrift -Current $current -Baseline $baseline
                $drift | Should -HaveCount 0
            } finally {
                cmd /c rmdir "$otherDst" 2>&1 | Out-Null
            }
        }

        It "ignores phantom null entries in either side" {
            $current = @($null, [PSCustomObject]@{
                subentries = @([PSCustomObject]@{ to = $script:RealDst; from = $script:RealSrc; state = Get-SymlinkSubState -From $script:RealSrc -To $script:RealDst })
            })
            $baseline = [PSCustomObject]@{ entries = @($null) }

            $drift = Get-StateDrift -Current $current -Baseline $baseline
            # Baseline is empty so the live link counts as added, not a crash.
            $drift | Should -HaveCount 1
            $drift[0].change | Should -Be 'added'
        }
    }
}
