Describe "main.ps1 entry point" {
    BeforeAll {
        $script:MainScript = (Resolve-Path (Join-Path $PSScriptRoot "../main.ps1")).Path
        $script:PowerShellPath = (Get-Command "pwsh" -ErrorAction Stop).Source

        function Invoke-MainUnderTest {
            param(
                [string[]]$CliArguments = @(),
                [string[]]$MenuInput = @()
            )

            # Menu runs answer prompts through Read-Host. Piping stdin would work
            # too, but Read-Host swallows it, so the answers travel as an env var
            # that the stub in the bootstrap script pops one at a time. JSON, not
            # a newline-joined string: the bootstrap is emitted through an
            # expandable here-string where an `n escape would be expanded into a
            # real newline and break the emitted literal.
            $env:WINOS_MAIN_TEST_INPUT = if ($MenuInput.Count -gt 0) {
                $MenuInput | ConvertTo-Json -Compress
            } else {
                # An empty pipeline emits nothing at all, which would leave the
                # variable unset -- and ConvertFrom-Json on unset input throws,
                # turning a clean "exit on closed stdin" into exit code 1.
                '[]'
            }
            try {
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
            } finally {
                Remove-Item Env:\WINOS_MAIN_TEST_INPUT -ErrorAction SilentlyContinue
            }
        }

        # Count of modules the menu actually invoked, and whether it exited cleanly.
        function Get-InvocationLog {
            if (-not (Test-Path -LiteralPath $script:InvocationLog)) { return @() }
            @(Get-Content -LiteralPath $script:InvocationLog)
        }
    }

    BeforeEach {
        $script:InvocationLog = Join-Path $TestDrive "module-invocation.txt"
        Remove-Item -LiteralPath $script:InvocationLog -Force -ErrorAction SilentlyContinue

        $script:SymlinkStub = Join-Path $TestDrive "symlink-manager.ps1"
        $script:PluginStub = Join-Path $TestDrive "plugin-manager.ps1"
        $script:EssentialsStub = Join-Path $TestDrive "essentials.ps1"
        $script:OpenCodeServeStub = Join-Path $TestDrive "opencode-serve.ps1"
        $script:BootstrapScript = Join-Path $TestDrive "invoke-main.ps1"

        @'
param([string]$action)
Add-Content -LiteralPath $env:WINOS_MAIN_TEST_LOG -Value "Config Persistence|$action"
'@ | Set-Content -LiteralPath $script:SymlinkStub -Encoding utf8

        @'
param([string]$action)
Add-Content -LiteralPath $env:WINOS_MAIN_TEST_LOG -Value "Plugin Deployment|$action"
# Lets a test drive the module into a non-zero exit so the menu's
# $LASTEXITCODE handling can be observed. Logging happens first, so a "failed"
# invocation is still recorded -- which is how the not-run assertions work.
if ($env:WINOS_MAIN_TEST_FAIL) { exit 1 }
'@ | Set-Content -LiteralPath $script:PluginStub -Encoding utf8

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
        $pluginPath = $script:PluginStub.Replace("'", "''")
        $essentialsPath = $script:EssentialsStub.Replace("'", "''")
        $openCodeServePath = $script:OpenCodeServeStub.Replace("'", "''")

        @"
`$forwardArguments = @(`$args)
`$env:WINOS_MAIN_TEST_LOG = '$logPath'
`$modules = @{
    "Config Persistence" = @{
        Alias       = "symlink-manager"
        Path        = '$symlinkPath'
        Actions     = @("plan", "apply", "snapshot")
        Destructive = @()
        Description = "Symlinks"
    }
    "Plugin Deployment" = @{
        Alias       = "plugin-manager"
        Path        = '$pluginPath'
        Actions     = @("plan", "apply", "revert", "snapshot", "status", "adopt", "verify")
        Destructive = @("revert", "adopt")
        Description = "Plugins"
    }
    "Essentials" = @{
        Alias       = "essentials"
        Path        = '$essentialsPath'
        Actions     = @("install", "uninstall")
        Destructive = @("uninstall")
        Description = "Essentials"
    }
    "Service Manager" = @{
        Path        = '$openCodeServePath'
        Actions     = @("setup", "remove", "status", "start", "stop")
        Destructive = @("remove")
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

    # Answers arrive as a JSON array in WINOS_MAIN_TEST_INPUT and are consumed
    # one per call. JSON rather than a newline-joined string on purpose: this
    # bootstrap is emitted through an EXPANDABLE here-string, so any backtick
    # escape below -- including one that merely appears inside a comment --
    # would be expanded before the file is written, and a newline escape becomes
    # a literal line break that splits the next statement.
    # When the script runs dry this returns empty -- the same signal a closed
    # stdin gives Read-Choice -- so an under-specified test exits instead of
    # spinning.
    if (-not `$script:InitDone) {
        # A separate flag, not a test of the array itself: an EMPTY array is
        # falsy in PowerShell, so guarding on the array re-reads the env var the
        # moment the answers run out and starts the whole sequence again.
        `$script:InitDone = `$true
        `$raw = `$env:WINOS_MAIN_TEST_INPUT
        `$script:Answers = if ([string]::IsNullOrWhiteSpace(`$raw)) {
            @()
        } else {
            @(`$raw | ConvertFrom-Json)
        }
    }
    if (`$script:Answers.Count -eq 0) { return "" }
    `$next = `$script:Answers[0]
    # Consume the answer. Without this the stub hands back the SAME value on
    # every call: Read-Choice consumes its number, then the confirmation prompt
    # receives a number again, rejects it, asks again, and never terminates.
    `$script:Answers = @(`$script:Answers | Select-Object -Skip 1)
    return `$next.Trim()
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

    It "routes symlink-manager plan to Config Persistence" {
        $result = Invoke-MainUnderTest -CliArguments @("symlink-manager", "plan")

        $result.ExitCode | Should -Be 0
        (Get-Content -LiteralPath $script:InvocationLog -Raw).Trim() |
            Should -Be "Config Persistence|plan"
    }

    It "routes plugin-manager apply to Plugin Deployment" {
        $result = Invoke-MainUnderTest -CliArguments @("plugin-manager", "apply")

        $result.ExitCode | Should -Be 0
        (Get-Content -LiteralPath $script:InvocationLog -Raw).Trim() |
            Should -Be "Plugin Deployment|apply"
    }

    It "routes plugin-manager revert to Plugin Deployment" {
        $result = Invoke-MainUnderTest -CliArguments @("plugin-manager", "revert")

        $result.ExitCode | Should -Be 0
        (Get-Content -LiteralPath $script:InvocationLog -Raw).Trim() |
            Should -Be "Plugin Deployment|revert"
    }

    It "rejects an invalid plugin-manager action" {
        $result = Invoke-MainUnderTest -CliArguments @("plugin-manager", "bad-action")

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match "Invalid action"
    }

    It "keeps Service Manager out of the flat module namespace" {
        # Service Manager carries no Alias in the registry, so the two-level
        # `service <name> <action>` grammar stays the only way in. If it were
        # reachable as a flat module, the alias->name mapping would be skipped.
        $result = Invoke-MainUnderTest -CliArguments @("service-manager", "setup")

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match "Unknown module"
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
        # Read the expected version out of main.ps1 rather than hardcoding it.
        # A literal here goes stale on the next bump and then fails for a reason
        # unrelated to routing -- which is exactly how v0.1.2 shipped while this
        # assertion still asked for v0.1.0.
        $source    = Get-Content -LiteralPath $script:MainScript -Raw
        $expected  = [regex]::Match($source, 'winos v(?<ver>[0-9]+\.[0-9]+\.[0-9]+)').Groups['ver'].Value
        $expected  | Should -Not -BeNullOrEmpty -Because "main.ps1 should carry a version literal"
        $result.Output | Should -Match ("v" + [regex]::Escape($expected))
    }

    It "rejects missing actions for modules and services" {
        $moduleResult = Invoke-MainUnderTest -CliArguments @("symlink-manager")
        $serviceResult = Invoke-MainUnderTest -CliArguments @("service", "opencode-serve")

        $moduleResult.ExitCode | Should -Be 1
        $moduleResult.Output | Should -Match "requires an action"
        $serviceResult.ExitCode | Should -Be 1
        $serviceResult.Output | Should -Match "requires an action"
    }

    # --- interactive menu -----------------------------------------------------
    # Module order is Sort-Object on the display names, so:
    #   1 Config Persistence | 2 Essentials | 3 Plugin Deployment | 4 Service Manager
    # Plugin Deployment verbs: 1 plan, 2 apply, 3 revert, 4 snapshot, 5 status,
    #                          6 adopt, 7 verify.  Destructive: revert, adopt.

    It "invokes the module and verb picked from the menu" {
        $result = Invoke-MainUnderTest -MenuInput @("1", "1")

        $result.ExitCode | Should -Be 0
        Get-InvocationLog | Should -Be @("Config Persistence|plan")
    }

    It "treats 0 at the verb level as Back and invokes nothing" {
        $result = Invoke-MainUnderTest -MenuInput @("1", "0", "0")

        $result.ExitCode | Should -Be 0
        Get-InvocationLog | Should -BeNullOrEmpty
        # Back must land on the module list again, not exit.
        ([regex]::Matches($result.Output, "Config Persistence -")).Count | Should -BeGreaterThan 0
    }

    It "exits without invoking anything on empty input" {
        $result = Invoke-MainUnderTest -MenuInput @()

        $result.ExitCode | Should -Be 0
        Get-InvocationLog | Should -BeNullOrEmpty
    }

    It "refuses to run a destructive verb when confirmation is declined" {
        # revert is the third Plugin Deployment verb. Both answers are "n".
        $result = Invoke-MainUnderTest -MenuInput @("3", "3", "n", "n")

        $result.ExitCode | Should -Be 0
        Get-InvocationLog | Should -BeNullOrEmpty
        $result.Output | Should -Match "Cancelled"
    }

    It "runs a destructive verb as a preview when the user asks for -WhatIf" {
        $result = Invoke-MainUnderTest -MenuInput @("3", "3", "y")

        $result.ExitCode | Should -Be 0
        Get-InvocationLog | Should -Be @("Plugin Deployment|revert")
        # The preview path must not have asked for a second confirmation.
        $result.Output | Should -Not -Match "Cancelled"
    }

    It "surfaces a non-zero exit code instead of bouncing back silently" {
        $env:WINOS_MAIN_TEST_FAIL = "1"
        try {
            # apply is not destructive, so it runs straight through and the stub
            # exits 1 on the way out.
            $result = Invoke-MainUnderTest -MenuInput @("3", "2")

            $result.ExitCode | Should -Be 0
            $result.Output | Should -Match "exit code 1"
        } finally {
            Remove-Item Env:\WINOS_MAIN_TEST_FAIL -ErrorAction SilentlyContinue
        }
    }

    It "re-prompts when a confirmation is answered with something other than y or n" {
        # Garbage must not be read as consent. Empty input is also not consent.
        $result = Invoke-MainUnderTest -MenuInput @("3", "3", "maybe", "", "n", "n")

        $result.ExitCode | Should -Be 0
        Get-InvocationLog | Should -BeNullOrEmpty
        $result.Output | Should -Match "Answer y or n"
    }
}
