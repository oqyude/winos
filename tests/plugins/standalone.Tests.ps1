BeforeAll {
    # Two levels up, not one: this file sits in tests/plugins/, and the repo root
    # is above tests/. A single ".." would resolve to tests/ and every Test-Path
    # below would silently fail against the wrong tree.
    $script:RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "../..")
}

Describe "Phase 0 scaffolding" {

    It "src/init.ps1 exists" {
        Test-Path (Join-Path $script:RepoRoot "src/init.ps1") | Should -Be $true
    }

    It "src/vars.ps1 exists" {
        Test-Path (Join-Path $script:RepoRoot "src/vars.ps1") | Should -Be $true
    }

    It "src/modules/plugins/plugin-manager.ps1 exists" {
        Test-Path (Join-Path $script:RepoRoot "src/modules/plugins/plugin-manager.ps1") | Should -Be $true
    }

    It ".pspsscriptanalyzer.psd1 exists" {
        Test-Path (Join-Path $script:RepoRoot ".pspsscriptanalyzer.psd1") | Should -Be $true
    }

    It "init.ps1 sets `$root to the repo root when sourced" {
        # Spawn a child pwsh that sources init.ps1 and echoes the variable.
        $root = $null
        $outPath = Join-Path $env:TEMP "powerlinks-init-root.txt"
        $errPath = Join-Path $env:TEMP "powerlinks-init-err.txt"

        $proc = Start-Process -FilePath "pwsh" -ArgumentList @(
            "-NoProfile", "-Command",
            "& { . '$($script:RepoRoot)\src\init.ps1' ; Write-Output `$root }"
        ) -Wait -PassThru -NoNewWindow -RedirectStandardOutput $outPath -RedirectStandardError $errPath

        $proc.ExitCode | Should -Be 0
        (Get-Content $errPath -Raw) | Should -Not -Match "Cannot bind argument"
        ((Get-Content $outPath -Raw).Trim()) | Should -Be $script:RepoRoot.Path

        Remove-Item $outPath, $errPath -ErrorAction SilentlyContinue
    }

    It "plugin-manager.ps1 self-bootstraps and echoes action=plan" {
        $script = Join-Path $script:RepoRoot "src/modules/plugins/plugin-manager.ps1"
        $outPath = Join-Path $env:TEMP "powerlinks-pm-stdout.txt"
        $errPath = Join-Path $env:TEMP "powerlinks-pm-stderr.txt"

        $proc = Start-Process -FilePath "pwsh" -ArgumentList @(
            "-NoProfile", "-File", $script, "-action", "plan"
        ) -Wait -PassThru -NoNewWindow -RedirectStandardOutput $outPath -RedirectStandardError $errPath

        $proc.ExitCode | Should -Be 0
        $stdout = Get-Content $outPath -Raw
        $stdout | Should -Match "plan"
        $stdout | Should -Match "Summary"

        Remove-Item $outPath, $errPath -ErrorAction SilentlyContinue
    }

    It "plugin-manager.ps1 rejects an unknown action verb" {
        $script = Join-Path $script:RepoRoot "src/modules/plugins/plugin-manager.ps1"
        $outPath = Join-Path $env:TEMP "powerlinks-pm-bad-stdout.txt"
        $errPath = Join-Path $env:TEMP "powerlinks-pm-bad-stderr.txt"

        $proc = Start-Process -FilePath "pwsh" -ArgumentList @(
            "-NoProfile", "-File", $script, "-action", "bogus"
        ) -Wait -PassThru -NoNewWindow -RedirectStandardOutput $outPath -RedirectStandardError $errPath

        # ValidateSet should reject before our code runs -- exit code nonzero.
        $proc.ExitCode | Should -Not -Be 0

        Remove-Item $outPath, $errPath -ErrorAction SilentlyContinue
    }

    It "state/plugin-deployment.json exists with valid schema" {
        $stateFile = Join-Path $script:RepoRoot "state/plugin-deployment.json"
        Test-Path $stateFile | Should -Be $true
        $content = Get-Content -Raw -Path $stateFile | ConvertFrom-Json
        $content.version | Should -Be 1
        $content.PSObject.Properties.Name | Should -Contain 'plugins'
    }

    It "plugin-manager.ps1 -action plan runs against the empty seed" {
        $script = Join-Path $script:RepoRoot "src/modules/plugins/plugin-manager.ps1"
        $outPath = Join-Path $env:TEMP "powerlinks-pm-plan-stdout.txt"
        $errPath = Join-Path $env:TEMP "powerlinks-pm-plan-stderr.txt"

        $proc = Start-Process -FilePath "pwsh" -ArgumentList @(
            "-NoProfile", "-File", $script, "-action", "plan"
        ) -Wait -PassThru -NoNewWindow -RedirectStandardOutput $outPath -RedirectStandardError $errPath

        $proc.ExitCode | Should -Be 0
        $stdout = Get-Content $outPath -Raw
        $stdout | Should -Match "plan"
        $stdout | Should -Match "Summary"

        Remove-Item $outPath, $errPath -ErrorAction SilentlyContinue
    }

    It "plugin-manager.ps1 -action snapshot writes a snapshot file" {
        $script = Join-Path $script:RepoRoot "src/modules/plugins/plugin-manager.ps1"
        $snapshot = Join-Path $script:RepoRoot "state/plugin-deployment-snapshot.json"
        $snapshotBackup = $snapshot + ".bak"

        # Move any existing snapshot aside so we can verify a fresh one is created.
        if (Test-Path $snapshot) { Move-Item $snapshot $snapshotBackup -Force }

        $outPath = Join-Path $env:TEMP "powerlinks-pm-snap-stdout.txt"
        $errPath = Join-Path $env:TEMP "powerlinks-pm-snap-stderr.txt"

        $proc = Start-Process -FilePath "pwsh" -ArgumentList @(
            "-NoProfile", "-File", $script, "-action", "snapshot"
        ) -Wait -PassThru -NoNewWindow -RedirectStandardOutput $outPath -RedirectStandardError $errPath

        $proc.ExitCode | Should -Be 0
        Test-Path $snapshot | Should -Be $true
        $snap = Get-Content -Raw -Path $snapshot | ConvertFrom-Json
        $snap.timestamp | Should -Not -BeNullOrEmpty
        $snap.tool_version | Should -Not -BeNullOrEmpty

        # Restore backup
        Remove-Item $snapshot -Force -ErrorAction SilentlyContinue
        if (Test-Path $snapshotBackup) { Move-Item $snapshotBackup $snapshot -Force }
        Remove-Item $outPath, $errPath -ErrorAction SilentlyContinue
    }
}
