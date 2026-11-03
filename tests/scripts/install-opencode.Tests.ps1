BeforeAll {
    # The canon of the config directory lives in its own file, and the tests
    # drive it directly: the installer is a script that runs end to end, and
    # the rules it enforces have to be checkable without a Windows host.
    $script:helperPath   = Join-Path $PSScriptRoot "../../scripts/opencode-config-dir.ps1"
    $script:installerPath = Join-Path $PSScriptRoot "../../scripts/install-opencode.ps1"
    $script:pwshPath = (Get-Command pwsh -ErrorAction Stop).Source

    . $script:helperPath

    $script:canonical = @(
        'opencode.jsonc'
        'cli.json'
        'tui.json'
        'oh-my-opencode-slim.json'
        'package.json'
        'package-lock.json'
        'service.json'
    )

    function New-ConfigDir {
        # A config directory that holds exactly the canon.
        param([string]$Path)

        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
        }
        foreach ($file in $script:canonical) {
            Set-Content -LiteralPath (Join-Path $Path $file) -Value '{}' -NoNewline
        }
        return $Path
    }

    function Invoke-Verify {
        # Run the installer in -Verify mode against a profile directory of our
        # own, with a PATH that holds nothing: the run must not reach the
        # network and must not touch the machine it runs on.
        param(
            [string]$ProfileRoot
        )

        $savedProfile = $env:USERPROFILE
        $savedPath    = $env:PATH
        try {
            $env:USERPROFILE = $ProfileRoot
            # A PATH that exists and holds nothing: the run must not reach the
            # network and must not touch the machine it runs on.
            $emptyBin = Join-Path $ProfileRoot 'empty-bin'
            if (-not (Test-Path -LiteralPath $emptyBin)) {
                New-Item -ItemType Directory -Path $emptyBin -Force | Out-Null
            }
            $env:PATH        = $emptyBin
            $output = & $script:pwshPath -NoProfile -File $script:installerPath -Verify 2>&1 | Out-String
            return [pscustomobject]@{
                Output   = $output
                ExitCode = $LASTEXITCODE
            }
        } finally {
            $env:USERPROFILE = $savedProfile
            $env:PATH        = $savedPath
        }
    }
}

Describe "the canon of the config directory" {

    It "names exactly the seven files of the canon" {
        $canon = Get-OpenCodeCanonicalConfigFiles

        $canon.Count | Should -Be 7
        foreach ($file in $script:canonical) {
            $canon | Should -Contain $file
        }
    }

    It "reports no drift for a directory that holds exactly the canon" {
        $dir = New-ConfigDir -Path (Join-Path $TestDrive 'clean')

        $state = Get-OpenCodeConfigDirState -Path $dir

        $state.Exists    | Should -BeTrue
        $state.Present.Count | Should -Be 7
        $state.Missing.Count | Should -Be 0
        $state.Extra.Count   | Should -Be 0
    }

    It "lists the files that are outside the canon" {
        $dir = New-ConfigDir -Path (Join-Path $TestDrive 'drift')
        Set-Content -LiteralPath (Join-Path $dir 'opencode.jsonc.bak-20260101-120000') -Value '{}'
        Set-Content -LiteralPath (Join-Path $dir 'cli.json.bak') -Value '{}'
        Set-Content -LiteralPath (Join-Path $dir 'lsp-install-decisions.json') -Value '{}'

        $state = Get-OpenCodeConfigDirState -Path $dir

        $state.Missing.Count | Should -Be 0
        $state.Extra.Count   | Should -Be 3
        $state.Extra | Should -Contain 'opencode.jsonc.bak-20260101-120000'
        $state.Extra | Should -Contain 'cli.json.bak'
        $state.Extra | Should -Contain 'lsp-install-decisions.json'
    }

    It "reports the canonical files that are missing" {
        # The fact that started this: vetymae has no tui.json, and nothing
        # reported it, because tui.json is not a file the installer writes.
        $dir = New-ConfigDir -Path (Join-Path $TestDrive 'incomplete')
        Remove-Item -LiteralPath (Join-Path $dir 'tui.json') -Force

        $state = Get-OpenCodeConfigDirState -Path $dir

        $state.Missing.Count | Should -Be 1
        $state.Missing | Should -Contain 'tui.json'
        $state.Present.Count | Should -Be 6
    }

    It "does not count a directory as drift" {
        # node_modules is the runtime of the plugin and skills/ is written by
        # opencode. Neither is a file the owner has to think about, and
        # reporting them would bury the real finding.
        $dir = New-ConfigDir -Path (Join-Path $TestDrive 'with-dirs')
        New-Item -ItemType Directory -Path (Join-Path $dir 'node_modules') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $dir 'skills') -Force | Out-Null

        $state = Get-OpenCodeConfigDirState -Path $dir

        $state.Extra.Count | Should -Be 0
    }

    It "fails on a missing canonical file and warns on drift alone" {
        $missingDir = New-ConfigDir -Path (Join-Path $TestDrive 'state-missing')
        Remove-Item -LiteralPath (Join-Path $missingDir 'tui.json') -Force
        $missing = Get-OpenCodeConfigDirCheckState -Path $missingDir
        $missing.State   | Should -Be 'missing'
        $missing.Message | Should -Match 'tui\.json'

        $driftDir = New-ConfigDir -Path (Join-Path $TestDrive 'state-drift')
        Set-Content -LiteralPath (Join-Path $driftDir 'notes.txt') -Value 'x'
        $drift = Get-OpenCodeConfigDirCheckState -Path $driftDir
        $drift.State   | Should -Be 'warn'
        $drift.Message | Should -Match 'notes\.txt'

        $cleanDir = New-ConfigDir -Path (Join-Path $TestDrive 'state-clean')
        (Get-OpenCodeConfigDirCheckState -Path $cleanDir).State | Should -Be 'ok'
    }
}

Describe "the backup prune" {

    BeforeEach {
        $script:PruneDir = Join-Path $TestDrive 'prune'
        New-Item -ItemType Directory -Path $script:PruneDir -Force | Out-Null

        # A backup the installer would have written 30 days ago, and one it
        # would have written yesterday.
        $script:Stale = Join-Path $script:PruneDir 'opencode.jsonc.bak-20260101-120000'
        $script:Fresh = Join-Path $script:PruneDir 'cli.json.bak-20261101-120000'
        Set-Content -LiteralPath $script:Stale -Value '{}'
        Set-Content -LiteralPath $script:Fresh -Value '{}'
        (Get-Item -LiteralPath $script:Stale).LastWriteTime = (Get-Date).AddDays(-30)
    }

    It "finds the stale backups and keeps the young ones" {
        $backups = Get-OpenCodeBackupFile -Path $script:PruneDir -OlderThanDays 14

        @($backups.Stale).Name | Should -Contain 'opencode.jsonc.bak-20260101-120000'
        @($backups.Fresh).Name | Should -Contain 'cli.json.bak-20261101-120000'
    }

    It "changes nothing in a dry run" {
        $result = Invoke-OpenCodeBackupPrune -Path $script:PruneDir -OlderThanDays 14 -DryRun

        @($result.Removed).Count | Should -Be 1
        Test-Path -LiteralPath $script:Stale | Should -BeTrue
        Test-Path -LiteralPath $script:Fresh | Should -BeTrue
    }

    It "removes the stale backup and keeps everything else" {
        $result = Invoke-OpenCodeBackupPrune -Path $script:PruneDir -OlderThanDays 14

        @($result.Removed).Count | Should -Be 1
        Test-Path -LiteralPath $script:Stale | Should -BeFalse
        Test-Path -LiteralPath $script:Fresh | Should -BeTrue
    }

    It "never removes a file that is not a backup of the installer" {
        # cli.json.bak has no stamp after the dot, and notes.txt is not a
        # backup at all. Both were made by hand; the owner has to look at them.
        $handmade = Join-Path $script:PruneDir 'cli.json.bak'
        $notes    = Join-Path $script:PruneDir 'notes.txt'
        Set-Content -LiteralPath $handmade -Value '{}'
        Set-Content -LiteralPath $notes -Value 'x'
        (Get-Item -LiteralPath $handmade).LastWriteTime = (Get-Date).AddDays(-30)
        (Get-Item -LiteralPath $notes).LastWriteTime    = (Get-Date).AddDays(-30)

        Invoke-OpenCodeBackupPrune -Path $script:PruneDir -OlderThanDays 14 | Out-Null

        Test-Path -LiteralPath $handmade | Should -BeTrue
        Test-Path -LiteralPath $notes    | Should -BeTrue
    }

    It "does not reach outside the config directory" {
        $outside = Join-Path $TestDrive 'outside.bak-20260101-120000'
        Set-Content -LiteralPath $outside -Value '{}'
        (Get-Item -LiteralPath $outside).LastWriteTime = (Get-Date).AddDays(-30)

        Invoke-OpenCodeBackupPrune -Path $script:PruneDir -OlderThanDays 14 | Out-Null

        Test-Path -LiteralPath $outside | Should -BeTrue
    }
}

Describe "install-opencode.ps1 -Verify" {

    It "reports a missing canonical file as a failure" {
        $profileRoot = Join-Path $TestDrive 'profile-missing'
        $config  = New-ConfigDir -Path (Join-Path $profileRoot '.config/opencode')
        Remove-Item -LiteralPath (Join-Path $config 'tui.json') -Force
        Set-Content -LiteralPath (Join-Path $config 'opencode.jsonc.bak-20260101-120000') -Value '{}'

        $result = Invoke-Verify -ProfileRoot $profileRoot

        $result.Output | Should -Match 'config-dir'
        $result.Output | Should -Match 'missing from the canon: tui\.json'
        # The extra files are named too: they are the drift the report is for.
        $result.Output | Should -Match 'opencode\.jsonc\.bak-20260101-120000'
        # A missing file of the canon is a failure, and the run says so.
        $result.Output | Should -Match '\[FAIL\] config-dir'
        $result.ExitCode | Should -Be 1
    }

    It "reports the files outside the canon as a warning" {
        $profileRoot = Join-Path $TestDrive 'profile-drift'
        $config  = New-ConfigDir -Path (Join-Path $profileRoot '.config/opencode')
        Set-Content -LiteralPath (Join-Path $config 'lsp-install-decisions.json') -Value '{}'

        $result = Invoke-Verify -ProfileRoot $profileRoot

        $result.Output | Should -Match '\[WARN\] config-dir'
        $result.Output | Should -Match 'lsp-install-decisions\.json'
        # The drift itself is not a failure: the exit code is decided by the
        # other checks, never by a file the installer did not write.
        $result.Output | Should -Not -Match '\[FAIL\] config-dir'
    }

    It "reports the launcher of the server and the second one in the profile" {
        # The launcher belongs to the machine state now: the report has to
        # name the new path, and it has to name the leftover in the profile.
        $profileRoot = Join-Path $TestDrive 'profile-launcher'
        $config  = New-ConfigDir -Path (Join-Path $profileRoot '.config/opencode')
        Set-Content -LiteralPath (Join-Path $profileRoot 'opencode-serve.sh') -Value 'x'

        $result = Invoke-Verify -ProfileRoot $profileRoot

        $result.Output | Should -Match 'launcher:opencode-serve\.sh'
        $result.Output | Should -Match 'host-scripts'
        $result.Output | Should -Match 'stray in the profile: opencode-serve\.sh'
    }
}
