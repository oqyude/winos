Describe "main.ps1 CLI routing" {
    BeforeAll {
        $script:MainScript = (Resolve-Path (Join-Path $PSScriptRoot "../main.ps1")).Path
        $script:PowerShellPath = (Get-Command "pwsh" -ErrorAction Stop).Source

        function Invoke-MainUnderTest {
            param([string[]]$CliArguments = @())

            $processArguments = @(
                "-NoProfile"
                "-NonInteractive"
                "-File"
                $script:BootstrapScript
            )
            if ($CliArguments.Count -gt 0) {
                $processArguments += $CliArguments
            }

            $output = & $script:PowerShellPath @processArguments 2>&1
            [PSCustomObject]@{
                ExitCode = $LASTEXITCODE
                Output   = ($output | Out-String)
            }
        }
    }

    BeforeEach {
        $script:InvocationLog = Join-Path $TestDrive "module-invocation.txt"
        Remove-Item -LiteralPath $script:InvocationLog -Force -ErrorAction SilentlyContinue

        $script:SymlinkStub = Join-Path $TestDrive "symlink-manager.ps1"
        $script:EssentialsStub = Join-Path $TestDrive "essentials.ps1"
        $script:OpenCodeServeStub = Join-Path $TestDrive "opencode-serve.ps1"
        $script:BootstrapScript = Join-Path $TestDrive "invoke-main.ps1"

        @'
param([string]$action)
Add-Content -LiteralPath $env:WINOS_MAIN_TEST_LOG -Value "Symlink Manager|$action"
'@ | Set-Content -LiteralPath $script:SymlinkStub -Encoding utf8

        @'
param([string]$action)
Add-Content -LiteralPath $env:WINOS_MAIN_TEST_LOG -Value "Essentials|$action"
'@ | Set-Content -LiteralPath $script:EssentialsStub -Encoding utf8

        @'
param([string]$action)
Add-Content -LiteralPath $env:WINOS_MAIN_TEST_LOG -Value "OpenCode Serve|$action"
'@ | Set-Content -LiteralPath $script:OpenCodeServeStub -Encoding utf8

        $mainPath = $script:MainScript.Replace("'", "''")
        $varsPath = (Join-Path (Split-Path -Parent $script:MainScript) "src/vars.ps1").Replace("'", "''")
        $logPath = $script:InvocationLog.Replace("'", "''")
        $symlinkPath = $script:SymlinkStub.Replace("'", "''")
        $essentialsPath = $script:EssentialsStub.Replace("'", "''")
        $openCodeServePath = $script:OpenCodeServeStub.Replace("'", "''")

        @"
`$forwardArguments = @(`$args)
`$env:WINOS_MAIN_TEST_LOG = '$logPath'
`$modules = @{
    "Symlink Manager" = @{
        Path        = '$symlinkPath'
        Actions     = @("plan", "apply", "snapshot")
        Description = "Symlinks"
    }
    "Essentials" = @{
        Path        = '$essentialsPath'
        Actions     = @("install", "uninstall")
        Description = "Essentials"
    }
    "OpenCode Serve" = @{
        Path        = '$openCodeServePath'
        Actions     = @("setup", "remove", "status", "start", "stop")
        Description = "OpenCode service"
    }
}

function Test-Path {
    param([Parameter(Position = 0)][string]`$Path)

    if (`$Path -eq '$varsPath') {
        return `$false
    }
    Microsoft.PowerShell.Management\Test-Path -Path `$Path
}

function Read-Host {
    param([string]`$Prompt)

    return "0"
}

`$WarningPreference = "SilentlyContinue"
`$ErrorActionPreference = "Stop"
try {
    . '$mainPath' @forwardArguments
} catch {
    `[Console]::Error.WriteLine(`$_.Exception.Message)
    exit 1
}
"@ | Set-Content -LiteralPath $script:BootstrapScript -Encoding utf8
    }

    It "enters menu mode when no arguments are supplied" {
        $result = Invoke-MainUnderTest

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match "winos"
        Test-Path -LiteralPath $script:InvocationLog | Should -BeFalse
    }

    It "routes symlink-manager plan to Symlink Manager" {
        $result = Invoke-MainUnderTest -CliArguments @("symlink-manager", "plan")

        $result.ExitCode | Should -Be 0
        (Get-Content -LiteralPath $script:InvocationLog -Raw).Trim() |
            Should -Be "Symlink Manager|plan"
    }

    It "routes essentials install to Essentials" {
        $result = Invoke-MainUnderTest -CliArguments @("essentials", "install")

        $result.ExitCode | Should -Be 0
        (Get-Content -LiteralPath $script:InvocationLog -Raw).Trim() |
            Should -Be "Essentials|install"
    }

    It "routes service opencode-serve setup to OpenCode Serve" {
        $result = Invoke-MainUnderTest -CliArguments @("service", "opencode-serve", "setup")

        $result.ExitCode | Should -Be 0
        (Get-Content -LiteralPath $script:InvocationLog -Raw).Trim() |
            Should -Be "OpenCode Serve|setup"
    }

    It "routes service opencode-serve status to OpenCode Serve" {
        $result = Invoke-MainUnderTest -CliArguments @("service", "opencode-serve", "status")

        $result.ExitCode | Should -Be 0
        (Get-Content -LiteralPath $script:InvocationLog -Raw).Trim() |
            Should -Be "OpenCode Serve|status"
    }

    It "rejects an unknown module" {
        $result = Invoke-MainUnderTest -CliArguments @("bad-module", "plan")

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match "Unknown module"
    }

    It "rejects an invalid module action" {
        $result = Invoke-MainUnderTest -CliArguments @("symlink-manager", "bad-action")

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match "Invalid action"
    }

    It "rejects an unknown service" {
        $result = Invoke-MainUnderTest -CliArguments @("service", "bad-svc", "start")

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match "Unknown service"
    }

    It "rejects an invalid service action" {
        $result = Invoke-MainUnderTest -CliArguments @("service", "opencode-serve", "bad-action")

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match "(?s)Invalid action.*for service"
    }

    It "shows detailed help for --help" {
        $result = Invoke-MainUnderTest -CliArguments @("--help")

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match "SYNOPSIS"
        $result.Output | Should -Match "winos"
    }

    It "shows the CLI version for --version" {
        $result = Invoke-MainUnderTest -CliArguments @("--version")

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match "v0\.1\.0"
    }

    It "rejects missing actions for modules and services" {
        $moduleResult = Invoke-MainUnderTest -CliArguments @("symlink-manager")
        $serviceResult = Invoke-MainUnderTest -CliArguments @("service", "opencode-serve")

        $moduleResult.ExitCode | Should -Be 1
        $moduleResult.Output | Should -Match "requires an action"
        $serviceResult.ExitCode | Should -Be 1
        $serviceResult.Output | Should -Match "requires an action"
    }
}
