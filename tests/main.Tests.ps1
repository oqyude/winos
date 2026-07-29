Describe "main.ps1 CLI routing" {
    BeforeAll {
        $script:MainScript = (Resolve-Path (Join-Path $PSScriptRoot "../main.ps1")).Path
        $script:PowerShellPath = (Get-Command "pwsh" -ErrorAction Stop).Source

        function Invoke-MainUnderTest {
            param([string]$Action)

            $arguments = @(
                "-NoProfile"
                "-NonInteractive"
                "-File"
                $script:BootstrapScript
            )
            if ($PSBoundParameters.ContainsKey("Action")) {
                $arguments += @("-Action", $Action)
            }

            $output = & $script:PowerShellPath @arguments 2>&1
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
        $script:BootstrapScript = Join-Path $TestDrive "invoke-main.ps1"

        @'
param([string]$action)
Add-Content -LiteralPath $env:WINOS_MAIN_TEST_LOG -Value "Symlink Manager|$action"
'@ | Set-Content -LiteralPath $script:SymlinkStub -Encoding utf8

        @'
param([string]$action)
Add-Content -LiteralPath $env:WINOS_MAIN_TEST_LOG -Value "Essentials|$action"
'@ | Set-Content -LiteralPath $script:EssentialsStub -Encoding utf8

        $mainPath = $script:MainScript.Replace("'", "''")
        $varsPath = (Join-Path (Split-Path -Parent $script:MainScript) "src/vars.ps1").Replace("'", "''")
        $logPath = $script:InvocationLog.Replace("'", "''")
        $symlinkPath = $script:SymlinkStub.Replace("'", "''")
        $essentialsPath = $script:EssentialsStub.Replace("'", "''")

        @"
param([string]`$Action)

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
if (`$PSBoundParameters.ContainsKey("Action")) {
    . '$mainPath' -action `$Action
} else {
    . '$mainPath'
}
"@ | Set-Content -LiteralPath $script:BootstrapScript -Encoding utf8
    }

    It "enters menu mode without invoking a module when no action is supplied" {
        $result = Invoke-MainUnderTest

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match "winos"
        Test-Path $script:InvocationLog | Should -Be $false
    }

    It "routes action plan to Symlink Manager" {
        $result = Invoke-MainUnderTest -Action "plan"

        $result.ExitCode | Should -Be 0
        (Get-Content -LiteralPath $script:InvocationLog -Raw).Trim() | Should -Be "Symlink Manager|plan"
    }

    It "routes action apply to Symlink Manager" {
        $result = Invoke-MainUnderTest -Action "apply"

        $result.ExitCode | Should -Be 0
        (Get-Content -LiteralPath $script:InvocationLog -Raw).Trim() | Should -Be "Symlink Manager|apply"
    }

    It "routes action install to Essentials" {
        $result = Invoke-MainUnderTest -Action "install"

        $result.ExitCode | Should -Be 0
        (Get-Content -LiteralPath $script:InvocationLog -Raw).Trim() | Should -Be "Essentials|install"
    }

    It "rejects an unsupported action through ValidateSet" {
        $errorRecord = { . $script:MainScript -action "bad" } | Should -Throw -PassThru

        $errorRecord.Exception.GetType().FullName |
            Should -Be "System.Management.Automation.ParameterBindingValidationException"
    }
}
