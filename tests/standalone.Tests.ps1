BeforeAll {
    # Test that modules can be invoked standalone (without main.ps1/init.ps1)
    $script:RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
}

Describe "module standalone execution" {
    It "symlink-manager.ps1 loads $jsonConfig via self-bootstrap" {
        $script = Join-Path $script:RepoRoot "src/modules/symlink-manager.ps1"
        $proc = Start-Process -FilePath "pwsh" -ArgumentList @(
            "-NoProfile", "-File", $script, "-action", "clean", "-WhatIf"
        ) -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\winos-symlink-stdout.txt" -RedirectStandardError "$env:TEMP\winos-symlink-stderr.txt"
        $proc.ExitCode | Should -Be 0

        $stderr = Get-Content "$env:TEMP\winos-symlink-stderr.txt" -Raw
        $stderr | Should -Not -Match "Cannot bind argument to parameter 'Path' because it is null"
        $stderr | Should -Not -Match "Get-Content"

        Remove-Item "$env:TEMP\winos-symlink-stdout.txt", "$env:TEMP\winos-symlink-stderr.txt" -ErrorAction SilentlyContinue
    }

    It "essentials.ps1 self-bootstraps $Storage" {
        $script = Join-Path $script:RepoRoot "src/modules/essentials.ps1"
        # Run with -action install. Either INF is found (success) or INF not found
        # with a real, non-null path. Either way, the script must NOT crash on
        # `$InfPath` being null due to missing bootstrap.
        $proc = Start-Process -FilePath "pwsh" -ArgumentList @(
            "-NoProfile", "-File", $script, "-action", "install"
        ) -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\winos-essentials-stdout.txt" -RedirectStandardError "$env:TEMP\winos-essentials-stderr.txt"
        $stderr = Get-Content "$env:TEMP\winos-essentials-stderr.txt" -Raw
        $stdout = Get-Content "$env:TEMP\winos-essentials-stdout.txt" -Raw

        # Must not crash on null Storage
        $stderr | Should -Not -Match "Cannot bind argument"
        $stderr | Should -Not -Match "Value cannot be null"
        # Must not produce a null-ish path (e.g. "\Windows\...")
        $stdout | Should -Not -Match "INF file not found: \\Windows"

        Remove-Item "$env:TEMP\winos-essentials-stdout.txt", "$env:TEMP\winos-essentials-stderr.txt" -ErrorAction SilentlyContinue
    }
}
