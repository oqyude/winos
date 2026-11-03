BeforeAll {
    # The launcher is declared in the repository and copied to the machine by
    # the installer. The rules it has to obey are checked here, against the
    # template itself -- a launcher is a script, and a script is only as good
    # as what it says it does.
    $script:launcherDir = Join-Path $PSScriptRoot "../../src/host-scripts"
    $script:launcherSh  = Join-Path $script:launcherDir 'opencode-serve.sh'
    $script:launcherCmd = Join-Path $script:launcherDir 'opencode-serve.cmd'
    $script:helperPath  = Join-Path $PSScriptRoot "../../scripts/opencode-launcher.ps1"

    . $script:helperPath

    $script:launcherText = Get-Content -Raw -LiteralPath $script:launcherSh
}

Describe "the launcher template" {

    It "ships in the repository with its Windows wrapper" {
        Test-Path -LiteralPath $script:launcherSh  | Should -BeTrue
        Test-Path -LiteralPath $script:launcherCmd | Should -BeTrue
    }

    It "is plain ASCII" {
        # The file travels over ssh to the Windows hosts, where a non-ASCII
        # byte in a script turns into a parse error.
        $bytes = [System.IO.File]::ReadAllBytes($script:launcherSh)
        @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }

    It "does not read the profile of the user" {
        # The whole point of the rewrite: the old launcher on one host ran
        # `bash -lc` and leaned on an alias, so its behaviour depended on
        # what ~/.bashrc happened to export that day.
        $script:launcherText | Should -Not -Match '(?m)^\s*(source|\.)\s+.*bashrc'
        $script:launcherText | Should -Not -Match 'bash\s+-l'
        $script:launcherText | Should -Not -Match '(?m)^\s*alias\s'
    }

    It "carries the proxy, the step cap and the CORS inside" {
        $script:launcherText | Should -Match 'export HTTP_PROXY='
        $script:launcherText | Should -Match 'export HTTPS_PROXY='
        $script:launcherText | Should -Match 'export NO_PROXY='
        $script:launcherText | Should -Match 'OPENCODE_CONFIG_CONTENT'
        $script:launcherText | Should -Match '"steps"'
        $script:launcherText | Should -Match 'CORS_ORIGIN'
        $script:launcherText | Should -Match '--cors'
    }

    It "writes the log with a rotation and honours the stop flag" {
        $script:launcherText | Should -Match 'opencode-serve\.log'
        $script:launcherText | Should -Match 'LOG_MAX_KB'
        $script:launcherText | Should -Match '\$LOG_FILE\.1'
        $script:launcherText | Should -Match 'opencode-serve\.stop'
    }

    It "finds the binary through the scoop junction and falls back to the PATH" {
        $script:launcherText | Should -Match 'readlink -f'
        $script:launcherText | Should -Match 'apps/opencode2/current'
        $script:launcherText | Should -Match 'command -v opencode'
    }

    It "is wrapped by a .cmd that only finds bash and hands over" {
        $cmd = Get-Content -Raw -LiteralPath $script:launcherCmd

        $cmd | Should -Match 'opencode-serve\.sh'
        $cmd | Should -Match 'bash\.exe'
        # Thin: the .cmd finds bash and forwards the arguments. It does not
        # carry a second copy of the logic.
        $cmd | Should -Not -Match 'serve --hostname'
    }
}

Describe "Get-OpenCodeLauncherState" {

    It "says the launcher is missing when it is not there" {
        $state = Get-OpenCodeLauncherState -ScriptPath (Join-Path $TestDrive 'nope/opencode-serve.sh')

        $state.Present    | Should -BeFalse
        @($state.Stray).Count | Should -Be 0
    }

    It "says the launcher is in place" {
        $dir = Join-Path $TestDrive 'host-scripts'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $script = Join-Path $dir 'opencode-serve.sh'
        Set-Content -LiteralPath $script -Value '#!/usr/bin/env bash'

        $state = Get-OpenCodeLauncherState -ScriptPath $script -ProfileDir (Join-Path $TestDrive 'profile')

        $state.Present    | Should -BeTrue
        @($state.Stray).Count | Should -Be 0
    }

    It "names the second launcher that lies in the profile" {
        # The old arrangement: the launcher in the profile of the user. It is
        # reported, never deleted.
        $profileDir = Join-Path $TestDrive 'profile'
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $profileDir 'opencode-serve.sh') -Value 'x'
        Set-Content -LiteralPath (Join-Path $profileDir 'opencode-serve.cmd') -Value 'x'
        Set-Content -LiteralPath (Join-Path $profileDir 'notes.txt') -Value 'x'

        $state = Get-OpenCodeLauncherState -ScriptPath (Join-Path $TestDrive 'host-scripts/opencode-serve.sh') -ProfileDir $profileDir

        @($state.Stray).Count | Should -Be 2
        $state.Stray | Should -Contain 'opencode-serve.sh'
        $state.Stray | Should -Contain 'opencode-serve.cmd'
        # The file that is not a launcher is none of the business.
        $state.Stray | Should -Not -Contain 'notes.txt'
    }
}

Describe "Install-OpenCodeLauncher" {

    It "copies the launcher and its wrapper to the target directory" {
        $target = Join-Path $TestDrive 'data/tools/host-scripts'

        $result = Install-OpenCodeLauncher -TemplateDir $script:launcherDir -TargetDir $target

        @($result.Missing).Count | Should -Be 0
        @($result.Written).Count | Should -Be 2
        Test-Path -LiteralPath (Join-Path $target 'opencode-serve.sh')  | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $target 'opencode-serve.cmd') | Should -BeTrue
    }

    It "reports a template that is not in the repository" {
        $result = Install-OpenCodeLauncher -TemplateDir (Join-Path $TestDrive 'no-templates') -TargetDir (Join-Path $TestDrive 'target')

        @($result.Written).Count | Should -Be 0
        @($result.Missing).Count | Should -Be 2
    }
}
