BeforeAll {
    # The resolver is a plain script of functions: dot-sourced here so the
    # tests can call it with an explicit data dir and never touch the real
    # machine's declaration.
    . (Join-Path $PSScriptRoot "../src/host-paths.ps1")

    function New-DeclarationFile {
        param(
            [string]$DataDir,
            [hashtable]$Content
        )
        $hostsDir = Join-WinosPath $DataDir "hosts"
        if (-not (Test-Path -LiteralPath $hostsDir)) {
            New-Item -ItemType Directory -Path $hostsDir -Force | Out-Null
        }
        $file = Join-WinosPath $hostsDir "$(Get-WinosHostName).json"
        $Content | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $file -Encoding utf8
        return $file
    }
}

Describe "host-paths: the host name" {
    It "prefers COMPUTERNAME, the name a Windows declaration is filed under" {
        $saved = $env:COMPUTERNAME
        try {
            $env:COMPUTERNAME = 'DESKTOP-TEST'
            Get-WinosHostName | Should -Be 'DESKTOP-TEST'
        } finally {
            $env:COMPUTERNAME = $saved
        }
    }

    It "falls back to HOSTNAME when there is no COMPUTERNAME" {
        $savedComputer = $env:COMPUTERNAME
        $savedHost = $env:HOSTNAME
        try {
            $env:COMPUTERNAME = ''
            $env:HOSTNAME = 'linux-box'
            Get-WinosHostName | Should -Be 'linux-box'
        } finally {
            $env:COMPUTERNAME = $savedComputer
            $env:HOSTNAME = $savedHost
        }
    }

    It "never returns an empty name" {
        $savedComputer = $env:COMPUTERNAME
        $savedHost = $env:HOSTNAME
        try {
            $env:COMPUTERNAME = ''
            $env:HOSTNAME = ''
            Get-WinosHostName | Should -Not -BeNullOrEmpty
        } finally {
            $env:COMPUTERNAME = $savedComputer
            $env:HOSTNAME = $savedHost
        }
    }
}

Describe "host-paths: the data dir rule (T24)" {
    It "prefers the synced store when it exists" {
        $savedProfile = $env:USERPROFILE
        try {
            $root = Join-Path $TestDrive "profile"
            $store = Join-WinosPath (Join-WinosPath (Join-WinosPath $root "Storage") "winos") "data"
            New-Item -ItemType Directory -Path $store -Force | Out-Null
            $env:USERPROFILE = $root

            $result = Get-WinosDataDir -RepoRoot (Join-Path $TestDrive "repo")
            $result.Path | Should -Be $store
            $result.Source | Should -Be 'machine store'
        } finally {
            $env:USERPROFILE = $savedProfile
        }
    }

    It "falls back to the repository's own data dir when the store is absent" {
        $savedProfile = $env:USERPROFILE
        try {
            $env:USERPROFILE = Join-Path $TestDrive "empty-profile"
            $repo = Join-Path $TestDrive "repo"

            $result = Get-WinosDataDir -RepoRoot $repo
            $result.Path | Should -Be (Join-WinosPath $repo 'data')
            $result.Source | Should -Be 'repository'
        } finally {
            $env:USERPROFILE = $savedProfile
        }
    }
}

Describe "host-paths: the declaration is read" {
    It "takes every declared value" {
        $dataDir = Join-Path $TestDrive "declared"
        New-DeclarationFile -DataDir $dataDir -Content @{
            projectsDir          = 'D:\Git'
            toolsDir             = 'D:\Tools'
            pluginRoot           = 'D:\Plugins'
            taskWorkingDirectory = 'D:\Work'
        } | Out-Null

        $result = Resolve-WinosHostPaths -DataDir $dataDir -Quiet

        $result.declarationFound | Should -BeTrue
        $result.projectsDir | Should -Be 'D:\Git'
        $result.toolsDir | Should -Be 'D:\Tools'
        $result.pluginRoot | Should -Be 'D:\Plugins'
        $result.taskWorkingDirectory | Should -Be 'D:\Work'
        $result.declarationSource | Should -Match 'declaration'
    }

    It "names the file it looked for" {
        $dataDir = Join-Path $TestDrive "named"
        $result = Resolve-WinosHostPaths -DataDir $dataDir -Quiet

        $result.declarationFile | Should -Be (Join-WinosPath (Join-WinosPath $dataDir "hosts") "$(Get-WinosHostName).json")
        $result.declarationFound | Should -BeFalse
    }

    It "makes taskWorkingDirectory follow projectsDir when it is not declared" {
        $dataDir = Join-Path $TestDrive "follow"
        New-DeclarationFile -DataDir $dataDir -Content @{
            projectsDir = 'D:\Git'
        } | Out-Null

        $result = Resolve-WinosHostPaths -DataDir $dataDir -Quiet
        $result.taskWorkingDirectory | Should -Be 'D:\Git'
    }

    It "keeps a declared taskWorkingDirectory over projectsDir" {
        $dataDir = Join-Path $TestDrive "separate"
        New-DeclarationFile -DataDir $dataDir -Content @{
            projectsDir          = 'D:\Git'
            taskWorkingDirectory = 'D:\Elsewhere'
        } | Out-Null

        $result = Resolve-WinosHostPaths -DataDir $dataDir -Quiet
        $result.taskWorkingDirectory | Should -Be 'D:\Elsewhere'
    }

    It "expands %USERPROFILE% in a declared path" {
        $savedProfile = $env:USERPROFILE
        try {
            $env:USERPROFILE = 'C:\Users\declared'
            $dataDir = Join-Path $TestDrive "tokens"
            New-DeclarationFile -DataDir $dataDir -Content @{
                projectsDir = '%USERPROFILE%\Git'
            } | Out-Null

            $result = Resolve-WinosHostPaths -DataDir $dataDir -Quiet
            $result.projectsDir | Should -Be 'C:\Users\declared\Git'
        } finally {
            $env:USERPROFILE = $savedProfile
        }
    }
}

Describe "host-paths: the fallback is loud" {
    It "falls back to the built-in defaults when the declaration is absent" {
        $dataDir = Join-Path $TestDrive "missing"
        $result = Resolve-WinosHostPaths -DataDir $dataDir -Quiet

        $result.declarationFound | Should -BeFalse
        $result.declarationSource | Should -Be 'built-in defaults'
        $result.projectsDir | Should -Not -BeNullOrEmpty
        $result.toolsDir | Should -Not -BeNullOrEmpty
        $result.pluginRoot | Should -Not -BeNullOrEmpty
    }

    It "warns once, naming the file it looked for" {
        $dataDir = Join-Path $TestDrive "warned"
        $state = @{}

        $warnings = @()
        Resolve-WinosHostPaths -DataDir $dataDir -State $state -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null

        $warnings.Count | Should -BeGreaterOrEqual 1
        $expected = Join-WinosPath (Join-WinosPath $dataDir "hosts") "$(Get-WinosHostName).json"
        $warnings[0].Message | Should -Match ([regex]::Escape($expected))
        $warnings[0].Message | Should -Match 'No host declaration'
    }

    It "does not warn twice for the same state" {
        $dataDir = Join-Path $TestDrive "warned-once"
        $state = @{}

        $first = @()
        Resolve-WinosHostPaths -DataDir $dataDir -State $state -WarningVariable first -WarningAction SilentlyContinue | Out-Null
        $second = @()
        Resolve-WinosHostPaths -DataDir $dataDir -State $state -WarningVariable second -WarningAction SilentlyContinue | Out-Null

        $first.Count | Should -BeGreaterOrEqual 1
        $second.Count | Should -Be 0
    }

    It "survives an unreadable declaration instead of throwing" {
        $dataDir = Join-Path $TestDrive "broken"
        $hostsDir = Join-WinosPath $dataDir "hosts"
        New-Item -ItemType Directory -Path $hostsDir -Force | Out-Null
        '{ this is not json' | Set-Content -LiteralPath (Join-WinosPath $hostsDir "$(Get-WinosHostName).json") -Encoding utf8

        $result = Resolve-WinosHostPaths -DataDir $dataDir -Quiet
        $result.declarationFound | Should -BeFalse
        $result.projectsDir | Should -Not -BeNullOrEmpty
    }
}

Describe "host-paths: the tool exposes the resolved values" {
    BeforeAll {
        . (Join-Path $PSScriptRoot "../src/init.ps1")
    }

    It "defines the per-host paths" {
        $projectsDir | Should -Not -BeNullOrEmpty
        $toolsDir | Should -Not -BeNullOrEmpty
        $pluginRoot | Should -Not -BeNullOrEmpty
        $taskWorkingDirectory | Should -Not -BeNullOrEmpty
    }

    It "names the declaration file it looked for" {
        $hostDeclarationFile | Should -BeLike "*hosts*"
        $hostDeclarationFile | Should -BeLike "*.json"
    }

    It "keeps $data under the resolved data dir" {
        $data | Should -Be $hostPaths.dataDir
        $dataSource | Should -Not -BeNullOrEmpty
    }
}
