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

    It "defines persist (canonical source-of-truth root)" {
        $persist | Should -Not -BeNullOrEmpty
    }

    It "persist is under storage" {
        $persist | Should -BeLike "$storage*"
    }
}

Describe "data.json schema" {
    BeforeAll {
        # Use repo's data.json (not user's $storage\winos\data)
        $script:RepoDataJson = Join-Path $PSScriptRoot "../data/data.json"
        $script:RepoConfig = Get-Content -Raw -Path $script:RepoDataJson | ConvertFrom-Json

        # Bring vars from vars.ps1 into script scope for tests
        . (Join-Path $PSScriptRoot "../src/init.ps1")
        $script:PersistRoot = $persist
    }

    It "has version 2" {
        $script:RepoConfig.version | Should -Be 2
    }

    It "has persistRoot field" {
        $script:RepoConfig.persistRoot | Should -Not -BeNullOrEmpty
    }

    It "persistRoot equals the literal '$persist'" {
        $script:RepoConfig.persistRoot | Should -Be '$persist'
    }

    It "expand(s) persistRoot to absolute path" {
        $expanded = $ExecutionContext.InvokeCommand.ExpandString($script:RepoConfig.persistRoot)
        $expanded | Should -Be $script:PersistRoot
    }

    It "every symlink entry has name, from, to" {
        foreach ($entry in $script:RepoConfig.symlinks) {
            $entry.name | Should -Not -BeNullOrEmpty -Because "every entry needs a name"
            $entry.from | Should -Not -BeNullOrEmpty -Because "every entry needs a from path"
            $entry.to   | Should -Not -BeNullOrEmpty -Because "every entry needs a to path"
        }
    }

    It "from paths expand to directories under persist (with explicit allowlist)" {
        $allowedNonPersist = @(
            "deploy-folder",     # uses $root (winos scripts deployment)
            "storage-folder",    # uses $root (Storage\winos symlink target)
            "SSH",               # uses $storage\home\ (shell config, separate from persist)
            "bash_rc",           # uses $storage\home\
            "bash_inputrc",      # uses $storage\home\
            "bash_gitconfig",    # uses $storage\home\
            "wslconfig",         # uses $storage\home\
            "continue"           # uses $storage\home\
        )
        foreach ($entry in $script:RepoConfig.symlinks) {
            if ($allowedNonPersist -contains $entry.name) { continue }
            $raw = $entry.from -replace '\\\$name', ''
            $expanded = $ExecutionContext.InvokeCommand.ExpandString($raw)
            $expanded | Should -BeLike "$($script:PersistRoot)*"
        }
    }

    It "AIMP has mappings generated for its persist contents" {
        $aimp = $script:RepoConfig.symlinks | Where-Object { $_.name -eq "AIMP" }
        $aimp.mappings | Should -Not -BeNullOrEmpty

        $validMappings = $aimp.mappings | Where-Object { $_ -ne $null -and $_.from }
        $validMappings.Count | Should -BeGreaterOrEqual 14

        $froms = $validMappings | ForEach-Object { $_.from }
        $froms | Should -Contain "AIMP.ini"
        $froms | Should -Contain "AIMP.ini.bak"
        $froms | Should -Contain "EQPresetsLibrary.ini"
        $froms | Should -Contain "AudioLibrary"
        $froms | Should -Contain "Skins"
    }
}
