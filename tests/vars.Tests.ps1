Describe "vars.ps1 loads" {
    BeforeAll {
        . (Join-Path $PSScriptRoot "../src/init.ps1")
    }

    It "defines modules" {
        $modules | Should -Not -BeNullOrEmpty
    }

    It "has 2 module entries" {
        $modules.Count | Should -Be 2
    }

    It "contains Symlink Manager" {
        $modules.ContainsKey("Symlink Manager") | Should -Be $true
    }

    It "contains Essentials" {
        $modules.ContainsKey("Essentials") | Should -Be $true
    }

    It "defines tempFolder" {
        $tempFolder | Should -Not -BeNullOrEmpty
    }

    It "defines storage" {
        $storage | Should -Not -BeNullOrEmpty
    }

    It "defines jsonConfig" {
        $jsonConfig | Should -Not -BeNullOrEmpty
    }
}
