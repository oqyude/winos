BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "../../src/modules/herdr-serve.ps1"

    # ScheduledTasks module must be importable so Pester Mock can hook its cmdlets.
    if (Get-Module -ListAvailable -Name ScheduledTasks) {
        Import-Module ScheduledTasks -ErrorAction SilentlyContinue
    }

    # Pre-set the variables the module expects via its self-bootstrap guard
    # (`if (-not $Storage) { . (Join-Path $PSScriptRoot '..\init.ps1') }`).
    # Setting them here keeps the test hermetic and avoids touching init.ps1.
    $storage = Join-Path $env:TEMP "winos-herdr-serve-tests"
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

Describe "herdr-serve.ps1" {

    It "loads without parse errors and exposes -action with ValidateSet" {
        $parseErrors.Count | Should -Be 0

        $cmd = Get-Command $scriptPath
        $cmd.Parameters.ContainsKey("action") | Should -Be $true

        $actionAttr = $cmd.Parameters["action"].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $actionAttr | Should -Not -BeNullOrEmpty
        ($actionAttr.ValidValues -join ",") | Should -Be "setup,remove,status,start,stop"
    }

    It "supports -WhatIf and -Confirm via SupportsShouldProcess" {
        # herdr-serve's setup/remove/start/stop gate behind ShouldProcess so an
        # operator can dry-run setup without writing config.json or registering
        # a scheduled task, and remove without touching the file system. The
        # attribute is what the runner uses -- Pester does not need to invoke
        # the action to verify it.
        $cmd = Get-Command $scriptPath
        $cmd.Parameters.ContainsKey("WhatIf") | Should -Be $true
        $cmd.Parameters.ContainsKey("Confirm") | Should -Be $true
    }

    It "setup writes config.json and registers the scheduled task" {
        # Clean slate for deterministic behavior.
        $cfgDir = Join-Path $data "herdr-serve"
        if (Test-Path $cfgDir) {
            Remove-Item $cfgDir -Recurse -Force
        }

        # Pester Mock cannot bypass the CIM argument-transformation attribute on
        # Register-ScheduledTask -Action/-Trigger/-Settings, so shadow every
        # external dependency with a function in the test scope. Functions take
        # precedence over cmdlets at name-resolution time, so the dot-sourced
        # module calls our stub instead of the real one. No Task Scheduler, no
        # CIM, no real herdr binary is touched.
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
            [pscustomobject]@{ Source = 'C:\fake\herdr.exe' }
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
        $cfg.herdr | Should -Be 'C:\fake\herdr.exe'
        $cfg.allowUnelevatedClients | Should -Be $true
    }

    It "setup with -WhatIf writes nothing and registers nothing" {
        $cfgDir = Join-Path $data "herdr-serve"
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
            [pscustomobject]@{ Source = 'C:\fake\herdr.exe' }
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
        Mock -CommandName 'Get-ScheduledTask' -ParameterFilter { $TaskName -eq 'HerdrServe' } -MockWith {
            [pscustomobject]@{ TaskName = 'HerdrServe'; State = 'Ready' }
        }
        Mock -CommandName 'Stop-ScheduledTask' -ParameterFilter { $TaskName -eq 'HerdrServe' } -MockWith { }
        Mock -CommandName 'Unregister-ScheduledTask' -ParameterFilter { $TaskName -eq 'HerdrServe' } -MockWith { }

        $cfgDir = Join-Path $data "herdr-serve"
        if (-not (Test-Path $cfgDir)) {
            New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
        }
        'placeholder' | Set-Content -Path (Join-Path $cfgDir 'config.json')

        . $scriptPath -action remove

        Should -Invoke Stop-ScheduledTask -ParameterFilter { $TaskName -eq 'HerdrServe' } -Times 1 -Exactly
        Should -Invoke Unregister-ScheduledTask -ParameterFilter { $TaskName -eq 'HerdrServe' } -Times 1 -Exactly
        Test-Path $cfgDir | Should -BeFalse
    }

    It "start and stop invoke the scheduled task cmdlets" {
        Mock -CommandName 'Start-ScheduledTask' -ParameterFilter { $TaskName -eq 'HerdrServe' } -MockWith { }
        Mock -CommandName 'Stop-ScheduledTask'  -ParameterFilter { $TaskName -eq 'HerdrServe' } -MockWith { }

        . $scriptPath -action start
        Should -Invoke Start-ScheduledTask -ParameterFilter { $TaskName -eq 'HerdrServe' } -Times 1 -Exactly

        . $scriptPath -action stop
        Should -Invoke Stop-ScheduledTask  -ParameterFilter { $TaskName -eq 'HerdrServe' } -Times 1 -Exactly
    }

    It "rejects invalid -action values via ValidateSet" {
        # ValidateSet rejects at parameter-binding time, before the script body runs,
        # so the test only needs to bind the argument and catch the binding exception.
        { & $scriptPath -action bad } |
            Should -Throw -ErrorId 'ParameterArgumentValidationError,*'
    }
}
