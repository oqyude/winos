Describe "symlink-manager.ps1 loads" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot "../../src/modules/symlink-manager.ps1"
    }

    It "exists" {
        Test-Path $scriptPath | Should -Be $true
    }

    It "is valid PowerShell" {
        $errors = $null
        $tokens = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
        $errors.Count | Should -Be 0
    }

    It "supports -WhatIf (state-changing)" {
        $cmd = Get-Command $scriptPath
        $cmd.Parameters.ContainsKey("WhatIf") | Should -Be $true
    }

    It "supports -Confirm (state-changing)" {
        $cmd = Get-Command $scriptPath
        $cmd.Parameters.ContainsKey("Confirm") | Should -Be $true
    }
}
