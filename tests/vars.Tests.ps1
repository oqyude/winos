Describe "vars.ps1 loads" {
    BeforeAll {
        . (Join-Path $PSScriptRoot "../src/init.ps1")
    }

    It "defines modules" {
        $modules | Should -Not -BeNullOrEmpty
    }

    It "has 5 module entries" {
        $modules.Count | Should -Be 5
    }

    It "contains Config Persistence" {
        $modules.ContainsKey("Config Persistence") | Should -Be $true
    }

    It "contains Plugin Deployment" {
        $modules.ContainsKey("Plugin Deployment") | Should -Be $true
    }

    It "renamed the two symlink modules by job, not by mechanism" {
        # Both create symlinks. If the display names still said "Symlink",
        # the menu would list two entries a user could not tell apart.
        $modules.Keys | Should -Not -Contain "Symlink Manager"
        $modules.Keys | Should -Not -Contain "Plugin Manager"
    }

    It "gives every service entry an Alias (reaches both grammars)" {
        # The `service <name> <action>` two-level grammar keys on Alias. Only
        # entries whose action set contains 'setup' are services, so only
        # those strictly need an Alias; an Alias-less module would still
        # surface in the menu and be reachable via the direct CLI grammar
        # (`winos <name> <action>`) as long as the menu maps to it. The
        # current registry happens to give every entry an Alias, which is
        # fine -- this assertion encodes the actual requirement, not the
        # coincidental fact.
        $serviceEntries = $modules.GetEnumerator() |
            Where-Object { $_.Value.Actions -contains 'setup' }
        $serviceEntries | Should -Not -BeNullOrEmpty
        foreach ($entry in $serviceEntries) {
            $entry.Value.ContainsKey('Alias') |
                Should -BeTrue -Because "$($entry.Key) must be reachable through the service grammar"
        }
        # Sanity: the legacy 'Service Manager' placeholder (a single entry that
        # pointed at opencode-serve.ps1 and had no Alias of its own) is gone --
        # its job is split between opencode-serve and herdr-serve, each with one.
        $modules.ContainsKey("Service Manager") | Should -Be $false
    }

    It "registers Plugin Deployment with all seven verbs" {
        $modules["Plugin Deployment"].Actions |
            Should -Be @("plan", "apply", "revert", "snapshot", "status", "adopt", "verify")
    }

    It "points Plugin Deployment at the isolated module root" {
        # Must NOT be src\modules\plugin-manager.ps1: that directory also holds
        # the symlink-manager's common/State.ps1, whose eight function names
        # collide with the plugin engine's.
        $modules["Plugin Deployment"].Path | Should -BeLike "*modules\plugins\plugin-manager.ps1"
    }

    It "resolves Plugin Deployment Path to a file that exists" {
        Test-Path -LiteralPath $modules["Plugin Deployment"].Path | Should -Be $true
    }

    It "declares Destructive on every module entry" {
        # The menu reads this field to decide whether to gate a verb behind a
        # confirmation. A missing key is read as $null, which is falsy, so an
        # entry that forgot the field would silently run revert unprotected.
        foreach ($name in $modules.Keys) {
            $modules[$name].ContainsKey('Destructive') | Should -Be $true -Because "$name gates on it"
        }
    }

    It "gates revert and adopt, the two verbs that destroy or overwrite" {
        # revert drops every junction; adopt rewrites state/powerlinks.json.
        $d = $modules["Plugin Deployment"].Destructive
        $d | Should -Contain "revert"
        $d | Should -Contain "adopt"
    }

    It "does not gate the read-only verbs of Plugin Deployment" {
        $d = $modules["Plugin Deployment"].Destructive
        foreach ($safe in @("plan", "snapshot", "status", "verify")) {
            $d | Should -Not -Contain $safe -Because "$safe only reads"
        }
        # apply reconciles toward the declared state and is the module's main
        # verb -- prompting on it would make the tool feel broken.
        $d | Should -Not -Contain "apply"
    }

    It "lists only verbs the module actually accepts in Destructive" {
        foreach ($name in $modules.Keys) {
            foreach ($verb in $modules[$name].Destructive) {
                $modules[$name].Actions | Should -Contain $verb -Because "$name cannot run '$verb'"
            }
        }
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

    It "defines statePath (snapshot output location)" {
        $statePath | Should -Not -BeNullOrEmpty
        $statePath | Should -BeLike "*symlink-snapshot.json"
    }

    It "statePath is under data directory" {
        $statePath | Should -BeLike "$data*"
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
            "continue",          # uses $storage\home\
            "starhip.toml"       # uses $storage\home\.config\
            "qBittorrent"        # uses $persist but to a different scoop persist path
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
        $validMappings.Count | Should -BeGreaterOrEqual 13

        $froms = $validMappings | ForEach-Object { $_.from }
        $froms | Should -Contain "AIMP.ini"
        $froms | Should -Contain "EQPresetsLibrary.ini"
        $froms | Should -Contain "AudioLibrary"
        $froms | Should -Contain "Skins"
    }
}
