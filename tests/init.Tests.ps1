Describe "src/init.ps1 CWD independence" {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
        $script:InitScript = Join-Path $script:RepoRoot "src/init.ps1"
        $script:MainScript = Join-Path $script:RepoRoot "main.ps1"
        $script:PowerShellPath = (Get-Command "pwsh" -ErrorAction Stop).Source
    }

    It "does not call Set-Location (static)" {
        # Static check: parses init.ps1 as PowerShell AST and asserts no
        # command call named Set-Location. Catches re-introductions even
        # if they are commented out, behind guards, or under control flow
        # the behaviour test happens to miss.
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:InitScript, [ref]$tokens, [ref]$errors)
        $parseErrors = $errors | Where-Object { $_.Severity -eq 'Error' }
        $parseErrors | Should -BeNullOrEmpty -Because "init.ps1 must parse cleanly"

        $setLocCalls = $ast.FindAll(
            { param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'Set-Location'
            },
            $true)
        ($setLocCalls | Measure-Object).Count | Should -Be 0
    }

    It "leaves the caller's CWD unchanged after dot-sourcing" {
        # Behaviour check: dot-source init.ps1 in a child pwsh whose CWD is
        # deliberately foreign (somewhere under $env:TEMP, distinct from
        # the repo). Have the child print (Get-Location).Path on both sides
        # of the dot-source. The BEFORE line should equal the foreign CWD
        # the parent set via -WorkingDirectory; the AFTER line must too --
        # if init.ps1 still had a Set-Location, AFTER would be the repo's
        # src/ directory.
        $foreignCwd = Join-Path ([IO.Path]::GetTempPath()) ("winos-init-cwd-test-" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
        New-Item -ItemType Directory -Path $foreignCwd -Force | Out-Null
        try {
            $initEsc = $script:InitScript.Replace("'", "''")
            $wrapper = @"
`$cwdBefore = (Get-Location).Path
. '$initEsc'
`$cwdAfter = (Get-Location).Path
Write-Output "BEFORE=`$cwdBefore"
Write-Output "AFTER=`$cwdAfter"
"@
            $wrapperPath = Join-Path $foreignCwd "probe.ps1"
            Set-Content -LiteralPath $wrapperPath -Value $wrapper -Encoding utf8

            $output = & $script:PowerShellPath -NoProfile -NonInteractive `
                -WorkingDirectory $foreignCwd `
                -File $wrapperPath 2>&1

            $LASTEXITCODE | Should -Be 0

            $before = ($output | ForEach-Object { "$_" } | Where-Object { $_ -match '^BEFORE=' }) -replace '^BEFORE=', ''
            $after  = ($output | ForEach-Object { "$_" } | Where-Object { $_ -match '^AFTER=' })  -replace '^AFTER=', ''

            $before | Should -Not -BeNullOrEmpty
            $after  | Should -Not -BeNullOrEmpty
            $before | Should -Be $foreignCwd
            $after  | Should -Be $foreignCwd
        } finally {
            Remove-Item $foreignCwd -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "lets main.ps1 run cleanly from a foreign CWD" {
        # Smoke test: a real CLI invocation (`--version`) from a CWD that
        # has nothing to do with the repo. Catches the user-facing symptom
        # of init.ps1 changing CWD: a parallel test runner or a wrapper
        # script that invokes main.ps1 from elsewhere would break the
        # caller's CWD.
        $foreignCwd = Join-Path ([IO.Path]::GetTempPath()) ("winos-main-cwd-test-" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
        New-Item -ItemType Directory -Path $foreignCwd -Force | Out-Null
        try {
            $output = & $script:PowerShellPath -NoProfile -NonInteractive `
                -WorkingDirectory $foreignCwd `
                -File $script:MainScript --version 2>&1

            $LASTEXITCODE | Should -Be 0
            ($output -join "`n") | Should -Match 'winos v\d'
        } finally {
            Remove-Item $foreignCwd -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
