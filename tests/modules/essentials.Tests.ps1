Describe "essentials.ps1 loads" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot "../../src/modules/essentials.ps1"
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
