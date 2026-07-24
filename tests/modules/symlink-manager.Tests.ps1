Describe "symlink-manager.ps1 loads" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot "../../src/modules/symlink-manager.ps1"
    }

    It "exists" {
        Test-Path $scriptPath | Should Be $true
    }

    It "is valid PowerShell" {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$errors)
        $errors.Count | Should Be 0
    }
}
