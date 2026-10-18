BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "../../src/modules/opencode-serve.ps1"

    # Force non-interactive mode for every test in this file. Pester happens
    # to suppress ShouldProcess prompts in its runner today, but relying on
    # that silently makes a future Pester upgrade (or running the same action
    # paths outside Pester) start asking for confirmation. Setting it here
    # makes the intent explicit: the tests must run unattended, no matter
    # what the host's $ConfirmPreference is.
    $ConfirmPreference = 'None'

    # ScheduledTasks module must be importable so Pester Mock can hook its cmdlets.
    if (Get-Module -ListAvailable -Name ScheduledTasks) {
        Import-Module ScheduledTasks -ErrorAction SilentlyContinue
    }

    # Pre-set the variables the module expects via its self-bootstrap guard
    # (`if (-not $Storage) { . (Join-Path $PSScriptRoot '..\init.ps1') }`).
    # Setting them here keeps the test hermetic and avoids touching init.ps1.
    $storage = Join-Path $env:TEMP "winos-opencode-serve-tests"
    if (-not (Test-Path $storage)) {
        New-Item -ItemType Directory -Path $storage -Force | Out-Null
    }
    $data = Join-Path $storage "data"
    if (-not (Test-Path $data)) {
        New-Item -ItemType Directory -Path $data -Force | Out-Null
    }

    # Parse the script once up-front so authoring errors surface in every test.
    $parseErrors = $null
    $tokens = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
}

Describe "opencode-serve.ps1" {

    It "loads without parse errors and exposes -action with ValidateSet" {
        $parseErrors.Count | Should -Be 0

        $cmd = Get-Command $scriptPath
        $cmd.Parameters.ContainsKey("action") | Should -Be $true

        $actionAttr = $cmd.Parameters["action"].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $actionAttr | Should -Not -BeNullOrEmpty
        ($actionAttr.ValidValues -join ",") | Should -Be "setup,remove,status,start,stop"
    }

    It "setup writes config.json and registers the scheduled task" {
        # Clean slate for deterministic behavior.
        $cfgDir = Join-Path $data "opencode-serve"
        if (Test-Path $cfgDir) {
            Remove-Item $cfgDir -Recurse -Force
        }

        # Pester Mock cannot bypass the CIM argument-transformation attribute on
        # Register-ScheduledTask -Action/-Trigger/-Settings, so shadow every
        # external dependency with a function in the test scope. Functions take
        # precedence over cmdlets at name-resolution time, so the dot-sourced
        # module calls our stub instead of the real one. No Task Scheduler, no
        # CIM, no real opencode binary is touched.
        $script:Calls = [ordered]@{
            'Get-Command'             = 0
            'Register-ScheduledTask' = 0
            'Start-ScheduledTask'    = 0
        }
        # These are test doubles. The parameter lists are load-bearing: the real
        # cmdlets accept named parameters (-TaskName, -Action, -User...), so a
        # stub that dropped them would reject the very calls it exists to record.
        # Overriding Get-Command and Read-Host is the isolation technique itself,
        # not an accident. Suppressed per function so the rules stay enforced
        # everywhere else in the repo.
        function Get-Command {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Test double')]
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Signature must match the real cmdlet')]
            param([Parameter(Position = 0)][string]$Name)
            $script:Calls['Get-Command']++
            [pscustomobject]@{ Source = 'C:\fake\opencode.exe' }
        }
        function Read-Host {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Test double')]
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Signature must match the real cmdlet')]
            param([string]$Prompt) ''
        }
        function New-ScheduledTaskAction { [pscustomobject]@{} }
        function New-ScheduledTaskTrigger { [pscustomobject]@{} }
        function New-ScheduledTaskSettingsSet { [pscustomobject]@{} }
        function Register-ScheduledTask {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Signature must match the real cmdlet')]
            param([string]$TaskName, $Action, $Trigger, $Settings,
                  [string]$User, [switch]$Force, $RunLevel)
            $script:Calls['Register-ScheduledTask']++
        }
        function Start-ScheduledTask {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Signature must match the real cmdlet')]
            param([string]$TaskName)
            $script:Calls['Start-ScheduledTask']++
        }

        . $scriptPath -action setup

        $script:Calls['Get-Command']              | Should -Be 1
        $script:Calls['Register-ScheduledTask']   | Should -Be 1
        $script:Calls['Start-ScheduledTask']      | Should -Be 1

        Test-Path (Join-Path $cfgDir 'config.json') | Should -BeTrue
        $cfg = Get-Content (Join-Path $cfgDir 'config.json') -Raw | ConvertFrom-Json
        $cfg.port | Should -Be 4096
        $cfg.username | Should -Be 'opencode'
        $cfg.opencode | Should -Be 'C:\fake\opencode.exe'
    }

    It "setup with -WhatIf writes nothing and registers nothing" {
        # Same stub strategy as the positive test above: shadow every external
        # dependency the module calls so a ShouldProcess-skipping -WhatIf must
        # leave all of them at 0 invocations. Mirrors the corresponding test
        # in herdr-serve.Tests.ps1 (the contract this aligns to).
        $cfgDir = Join-Path $data "opencode-serve"
        if (Test-Path $cfgDir) {
            Remove-Item $cfgDir -Recurse -Force
        }

        $script:Calls = [ordered]@{
            'Get-Command'             = 0
            'Register-ScheduledTask' = 0
            'Start-ScheduledTask'    = 0
        }
        function Get-Command {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Test double')]
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Signature must match the real cmdlet')]
            param([Parameter(Position = 0)][string]$Name)
            $script:Calls['Get-Command']++
            [pscustomobject]@{ Source = 'C:\fake\opencode.exe' }
        }
        function Read-Host {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Test double')]
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Signature must match the real cmdlet')]
            param([string]$Prompt) ''
        }
        function New-ScheduledTaskAction { [pscustomobject]@{} }
        function New-ScheduledTaskTrigger { [pscustomobject]@{} }
        function New-ScheduledTaskSettingsSet { [pscustomobject]@{} }
        function Register-ScheduledTask {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Signature must match the real cmdlet')]
            param([string]$TaskName, $Action, $Trigger, $Settings,
                  [string]$User, [switch]$Force, $RunLevel)
            $script:Calls['Register-ScheduledTask']++
        }
        function Start-ScheduledTask {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Signature must match the real cmdlet')]
            param([string]$TaskName)
            $script:Calls['Start-ScheduledTask']++
        }

        . $scriptPath -action setup -WhatIf

        $script:Calls['Get-Command']            | Should -Be 0
        $script:Calls['Register-ScheduledTask'] | Should -Be 0
        $script:Calls['Start-ScheduledTask']    | Should -Be 0
        Test-Path $cfgDir | Should -BeFalse
    }

    It "status without a task exits 1 and prints NOT INSTALLED" {
        # `exit 1` is a flow-control keyword that Pester cannot intercept in-process,
        # so run the action in a child pwsh. Function-shadowed Get-ScheduledTask
        # returns $null so the real Windows Task Scheduler is never queried.
        $wrapper = @'
function Get-ScheduledTask { param([string]$TaskName) return $null }
$storage = '__STORAGE__'
$data = '__DATA__'
. '__SCRIPT__' -action status
'@ -replace '__STORAGE__', $storage `
       -replace '__DATA__',    $data `
       -replace '__SCRIPT__',  $scriptPath

        $output = & pwsh -NoProfile -Command $wrapper 2>&1
        $LASTEXITCODE | Should -Be 1
        ($output -join "`n") | Should -Match 'NOT INSTALLED'
    }

    It "remove stops the task, unregisters it, and deletes the config directory" {
        # Mock the scheduler interactions so we never touch real tasks.
        Mock -CommandName 'Get-ScheduledTask' -ParameterFilter { $TaskName -eq 'OpenCodeServe' } -MockWith {
            [pscustomobject]@{ TaskName = 'OpenCodeServe'; State = 'Ready' }
        }
        Mock -CommandName 'Stop-ScheduledTask' -ParameterFilter { $TaskName -eq 'OpenCodeServe' } -MockWith { }
        Mock -CommandName 'Unregister-ScheduledTask' -ParameterFilter { $TaskName -eq 'OpenCodeServe' } -MockWith { }

        # Pre-create the config dir so remove has something concrete to delete.
        $cfgDir = Join-Path $data "opencode-serve"
        if (-not (Test-Path $cfgDir)) {
            New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
        }
        'placeholder' | Set-Content -Path (Join-Path $cfgDir 'config.json')

        . $scriptPath -action remove

        Should -Invoke Stop-ScheduledTask -ParameterFilter { $TaskName -eq 'OpenCodeServe' } -Times 1 -Exactly
        Should -Invoke Unregister-ScheduledTask -ParameterFilter { $TaskName -eq 'OpenCodeServe' } -Times 1 -Exactly
        Test-Path $cfgDir | Should -BeFalse
    }

    It "start and stop invoke the scheduled task cmdlets" {
        Mock -CommandName 'Start-ScheduledTask' -ParameterFilter { $TaskName -eq 'OpenCodeServe' } -MockWith { }
        Mock -CommandName 'Stop-ScheduledTask'  -ParameterFilter { $TaskName -eq 'OpenCodeServe' } -MockWith { }

        . $scriptPath -action start
        Should -Invoke Start-ScheduledTask -ParameterFilter { $TaskName -eq 'OpenCodeServe' } -Times 1 -Exactly

        . $scriptPath -action stop
        Should -Invoke Stop-ScheduledTask  -ParameterFilter { $TaskName -eq 'OpenCodeServe' } -Times 1 -Exactly
    }

    It "rejects invalid -action values via ValidateSet" {
        # ValidateSet rejects at parameter-binding time, before the script body runs,
        # so the test only needs to bind the argument and catch the binding exception.
        { & $scriptPath -action bad } |
            Should -Throw -ErrorId 'ParameterArgumentValidationError,*'
    }
}
