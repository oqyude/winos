BeforeAll {
    $script:modulePath = Join-Path $PSScriptRoot "../../src/modules/scheduler.ps1"
    $script:statePath  = Join-Path $PSScriptRoot "../../src/modules/scheduler/State.ps1"

    # The tests must run unattended: no confirmation prompt, no question.
    $ConfirmPreference = 'None'

    # Parse both files once up front so authoring errors surface everywhere.
    foreach ($path in @($script:modulePath, $script:statePath)) {
        $errors = $null
        $tokens = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $path, [ref]$tokens, [ref]$errors) | Out-Null
    }

    # The declared task, as the scheduler sees it.
    $script:DeclaredXml = @'
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <URI>\OpenCodeServe</URI>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>HOST\user</UserId>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>HOST\user</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Enabled>true</Enabled>
    <RestartOnFailure>
      <Interval>PT1M</Interval>
      <Count>5</Count>
    </RestartOnFailure>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>bash</Command>
      <Arguments>"C:\root\tools\host-scripts\opencode-serve.sh"</Arguments>
      <WorkingDirectory>C:\root</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
'@

    # The same task as Task Scheduler exports it: the same facts, plus the
    # Author/Date/Description noise that an exported document always carries.
    $script:LiveXml = @'
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Date>2026-11-03T09:00:00.0000000</Date>
    <Author>HOST\user</Author>
    <Description>opencode serve on 0.0.0.0:4096</Description>
    <URI>\OpenCodeServe</URI>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>HOST\user</UserId>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>HOST\user</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Enabled>true</Enabled>
    <RestartOnFailure>
      <Interval>PT1M</Interval>
      <Count>5</Count>
    </RestartOnFailure>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>bash</Command>
      <Arguments>"C:\root\tools\host-scripts\opencode-serve.sh"</Arguments>
      <WorkingDirectory>C:\root</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
'@

    # The same task, but the logon type is the one that drifted between the
    # two hosts (S4U against InteractiveToken).
    $script:LiveS4U = $script:LiveXml -replace '<LogonType>InteractiveToken</LogonType>', '<LogonType>S4U</LogonType>'

    # The same task, but it runs something else.
    $script:LiveOtherAction = $script:LiveXml -replace 'bash', 'cmd.exe' `
                                    -replace 'host-scripts\\opencode-serve\.sh', 'local\bin\oc-serve-task.sh'

    # The pure half of the module: functions over XML strings, no Task
    # Scheduler involved.
    . $script:statePath
}

Describe "scheduler/State.ps1" {

    It "reads the facts that carry the meaning out of a task document" {
        $facts = Get-TaskFacts -Xml $script:DeclaredXml

        $facts.LogonType        | Should -Be 'InteractiveToken'
        $facts.RunLevel         | Should -Be 'LeastPrivilege'
        $facts.UserId           | Should -Be 'HOST\user'
        $facts.Command          | Should -Be 'bash'
        $facts.WorkingDirectory | Should -Be 'C:\root'
        $facts.RestartCount     | Should -Be '5'
        @($facts.Triggers)      | Should -Be @('Logon:HOST\user')
    }

    It "reads the same facts out of an exported task" {
        # The exported document carries Author/Date/Description the
        # declaration does not have. The facts must come out the same.
        $declared = Get-TaskFacts -Xml $script:DeclaredXml
        $actual   = Get-TaskFacts -Xml $script:LiveXml

        $actual.LogonType        | Should -Be $declared.LogonType
        $actual.RunLevel         | Should -Be $declared.RunLevel
        $actual.UserId           | Should -Be $declared.UserId
        $actual.Command          | Should -Be $declared.Command
        $actual.Arguments        | Should -Be $declared.Arguments
        $actual.WorkingDirectory | Should -Be $declared.WorkingDirectory
        @($actual.Triggers)      | Should -Be @($declared.Triggers)
    }

    It "survives an empty or broken document" {
        (Get-TaskFacts -Xml '').LogonType | Should -Be ''
        (Get-TaskFacts -Xml '<not-xml').LogonType | Should -Be ''
    }

    It "finds the file the action runs" {
        $facts = Get-TaskFacts -Xml $script:DeclaredXml
        Get-TaskActionTarget -Facts $facts |
            Should -Be 'C:\root\tools\host-scripts\opencode-serve.sh'
    }

    It "reports no target when the action is a bare command" {
        $facts = [pscustomobject]@{ Command = 'notepad.exe'; Arguments = '' }
        Get-TaskActionTarget -Facts $facts | Should -Be ''
    }
}

Describe "Get-TaskDiff" {

    It "reports a match when the declaration and the live task agree" {
        $diff = Get-TaskDiff -Name 'OpenCodeServe' -DeclaredXml $script:DeclaredXml -LiveXml $script:LiveXml

        $diff.State       | Should -Be 'Matches'
        @($diff.Differences).Count | Should -Be 0
    }

    It "reports the logon type difference" {
        $diff = Get-TaskDiff -Name 'OpenCodeServe' -DeclaredXml $script:DeclaredXml -LiveXml $script:LiveS4U

        $diff.State | Should -Be 'Differs'
        $kinds = @($diff.Differences | ForEach-Object { $_.Kind })
        $kinds | Should -Contain 'LogonType'

        $logon = $diff.Differences | Where-Object { $_.Kind -eq 'LogonType' }
        $logon.Declared | Should -Be 'InteractiveToken'
        $logon.Actual   | Should -Be 'S4U'
    }

    It "reports the action difference" {
        $diff = Get-TaskDiff -Name 'OpenCodeServe' -DeclaredXml $script:DeclaredXml -LiveXml $script:LiveOtherAction

        $diff.State | Should -Be 'Differs'
        $action = $diff.Differences | Where-Object { $_.Kind -eq 'Action' }
        $action | Should -Not -BeNullOrEmpty
        $action.Declared | Should -BeLike '*bash*'
        $action.Actual   | Should -BeLike '*cmd.exe*'
    }

    It "reports a missing task" {
        $diff = Get-TaskDiff -Name 'OpenCodeServe' -DeclaredXml $script:DeclaredXml -LiveXml ''

        $diff.State       | Should -Be 'Missing'
        $diff.Actual      | Should -BeNullOrEmpty
        @($diff.Differences).Count | Should -Be 0
    }

    It "reports a trigger difference when the task fires at another time" {
        $other = $script:LiveXml -replace '<LogonTrigger>', '<BootTrigger>' -replace '</LogonTrigger>', '</BootTrigger>'
        $diff = Get-TaskDiff -Name 'OpenCodeServe' -DeclaredXml $script:DeclaredXml -LiveXml $other

        $diff.State | Should -Be 'Differs'
        $kinds = @($diff.Differences | ForEach-Object { $_.Kind })
        $kinds | Should -Contain 'Triggers'
    }
}

Describe "the declared tasks" {

    It "ships a declaration for the opencode serve task" {
        $templateDir = Join-Path $PSScriptRoot "../../src/modules/scheduler/tasks"
        Test-Path -LiteralPath $templateDir | Should -BeTrue

        $declarations = Get-SchedulerTaskDeclarations -TemplateDir $templateDir -Values (Get-SchedulerHostValues)
        $declarations.Count | Should -BeGreaterThan 0
        $declarations.Name | Should -Contain 'OpenCodeServe'
    }

    It "resolves the per-host placeholders" {
        $templateDir = Join-Path $PSScriptRoot "../../src/modules/scheduler/tasks"
        $values = Get-SchedulerHostValues -DataRoot 'C:\data' -ToolsDir 'C:\Tools' -UserProfile 'C:\Users\u' -User 'HOST\u'

        $declarations = Get-SchedulerTaskDeclarations -TemplateDir $templateDir -Values $values
        $declaration = $declarations | Where-Object { $_.Name -eq 'OpenCodeServe' }

        $declaration.Xml | Should -Not -Match '__[A-Z_]+__'
        $declaration.Xml | Should -BeLike '*C:\data*'
        $declaration.Xml | Should -BeLike '*HOST\u*'
    }

    It "declares an interactive logon, a logon trigger, an action and a folder" {
        $templateDir = Join-Path $PSScriptRoot "../../src/modules/scheduler/tasks"
        $values = Get-SchedulerHostValues -DataRoot 'C:\data' -ToolsDir 'C:\Tools' -UserProfile 'C:\Users\u' -User 'HOST\u'
        $declaration = (Get-SchedulerTaskDeclarations -TemplateDir $templateDir -Values $values) |
            Where-Object { $_.Name -eq 'OpenCodeServe' }

        $facts = Get-TaskFacts -Xml $declaration.Xml
        $facts.LogonType        | Should -Be 'InteractiveToken'
        $facts.RunLevel         | Should -Be 'LeastPrivilege'
        $facts.Command          | Should -Be 'bash'
        $facts.WorkingDirectory | Should -Be 'C:\data'
        @($facts.Triggers)      | Should -Be @('Logon:HOST\u')
    }
}

Describe "scheduler.ps1" {

    BeforeEach {
        # The module reads these; set them so the test does not depend on
        # the host's own layout.
        $storage = Join-Path ([System.IO.Path]::GetTempPath()) "winos-scheduler-tests"
        if (-not (Test-Path $storage)) { New-Item -ItemType Directory -Path $storage -Force | Out-Null }
        $data = $storage
        $toolsDir = Join-Path $storage "tools"

        # The account the task runs as. The declaration resolves __USER__ from
        # the environment, and the live task in this test says "HOST\user" --
        # so the environment has to say the same thing, or every comparison
        # would report a difference in the account that is not there.
        $script:SavedUserName      = $env:USERNAME
        $script:SavedComputerName  = $env:COMPUTERNAME
        $env:USERNAME      = 'user'
        $env:COMPUTERNAME  = 'HOST'

        # The file the declared action runs has to EXIST: the module refuses
        # to register a task that would start and die, and it says so. The
        # path is built exactly the way the declaration builds it, so it is
        # the same string on every host.
        $script:ActionTarget = "$data\tools\host-scripts\opencode-serve.sh"
        New-Item -ItemType File -Path $script:ActionTarget -Force | Out-Null

        # The live task, resolved against THIS host's data root: the same
        # document the declaration produces, plus the noise an export adds.
        $script:LiveXmlForHost  = $script:LiveXml.Replace('C:\root', $data)
        $script:LiveS4UForHost = $script:LiveS4U.Replace('C:\root', $data)

        $script:Calls = [ordered]@{
            'Get-ScheduledTask'      = 0
            'Export-ScheduledTask'   = 0
            'Register-ScheduledTask'  = 0
            'Unregister-ScheduledTask'= 0
        }
        $script:StubLiveXml = $null
    }

    AfterEach {
        # The environment is the test's own; put it back the way it was.
        if ($null -eq $script:SavedUserName) { Remove-Item Env:\USERNAME -ErrorAction SilentlyContinue }
        else { $env:USERNAME = $script:SavedUserName }
        if ($null -eq $script:SavedComputerName) { Remove-Item Env:\COMPUTERNAME -ErrorAction SilentlyContinue }
        else { $env:COMPUTERNAME = $script:SavedComputerName }
    }

    It "loads without parse errors and exposes -action with ValidateSet" {
        $errors = $null
        $tokens = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:modulePath, [ref]$tokens, [ref]$errors) | Out-Null
        $errors.Count | Should -Be 0

        $cmd = Get-Command $script:modulePath
        $cmd.Parameters.ContainsKey("action") | Should -BeTrue

        $actionAttr = $cmd.Parameters["action"].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $actionAttr | Should -Not -BeNullOrEmpty
        ($actionAttr.ValidValues -join ",") | Should -Be "plan,apply,status"
    }

    It "plan compares the declaration with the live task" {
        # Test doubles for the whole Task Scheduler surface. Functions take
        # precedence over cmdlets at name-resolution time, so the module calls
        # these instead. No task scheduler is touched, on any host.
        function Get-Command {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Test double')]
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Signature must match the real cmdlet')]
            param([Parameter(Position = 0)][string]$Name)
            if ($Name -eq 'Get-ScheduledTask' -or $Name -eq 'Export-ScheduledTask') {
                return [pscustomobject]@{ Source = 'stub' }
            }
            return $null
        }
        function Get-ScheduledTask {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Signature must match the real cmdlet')]
            param([string]$TaskName)
            $script:Calls['Get-ScheduledTask']++
            return [pscustomobject]@{ TaskName = $TaskName }
        }
        function Export-ScheduledTask {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Signature must match the real cmdlet')]
            param([string]$TaskName)
            $script:Calls['Export-ScheduledTask']++
            return $script:StubLiveXml
        }

        # The exported document from the outer scope: the live task agrees
        # with the declaration, so the plan has nothing to report.
        $script:StubLiveXml = $script:LiveXmlForHost

        $output = (. $script:modulePath -action plan 6>&1 | Out-String)

        $script:Calls['Get-ScheduledTask']  | Should -BeGreaterThan 0
        $script:Calls['Export-ScheduledTask'] | Should -BeGreaterThan 0
        # The module must never go looking for tasks to clean up.
        $script:Calls['Unregister-ScheduledTask'] | Should -Be 0
        # The declaration and the live task carry the same facts, so the plan
        # reports a match -- and not a difference invented by the host the
        # test happens to run on.
        $output | Should -Match 'matches the declaration'
    }

    It "apply with -WhatIf registers nothing" {
        function Get-Command {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Test double')]
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Signature must match the real cmdlet')]
            param([Parameter(Position = 0)][string]$Name)
            if ($Name -eq 'Get-ScheduledTask' -or $Name -eq 'Export-ScheduledTask') {
                return [pscustomobject]@{ Source = 'stub' }
            }
            return $null
        }
        function Get-ScheduledTask {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Signature must match the real cmdlet')]
            param([string]$TaskName)
            $script:Calls['Get-ScheduledTask']++
            return [pscustomobject]@{ TaskName = $TaskName }
        }
        function Export-ScheduledTask {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Signature must match the real cmdlet')]
            param([string]$TaskName)
            $script:Calls['Export-ScheduledTask']++
            return $script:StubLiveXml
        }
        function Register-ScheduledTask {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Signature must match the real cmdlet')]
            param([string]$TaskName, [string]$Xml, [switch]$Force)
            $script:Calls['Register-ScheduledTask']++
        }
        function Unregister-ScheduledTask {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Signature must match the real cmdlet')]
            param([string]$TaskName)
            $script:Calls['Unregister-ScheduledTask']++
        }

        # The live task DIFFERS from the declaration (the logon type drifted
        # between the two hosts), so without -WhatIf the module would register
        # it. That is what makes this test about -WhatIf and not about a task
        # that matched anyway.
        $script:StubLiveXml = $script:LiveS4UForHost

        . $script:modulePath -action apply -WhatIf | Out-Null

        $script:Calls['Register-ScheduledTask'] | Should -Be 0
        $script:Calls['Unregister-ScheduledTask'] | Should -Be 0
    }

    It "apply registers only the declared task" {
        # The module refuses to register a task whose action target is not on
        # disk: a task that starts and dies is worse than no task. The target
        # is the launcher under the (test) data root, so it has to exist.
        $target = Join-Path $data 'tools\host-scripts\opencode-serve.sh'
        $targetDir = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
        Set-Content -LiteralPath $target -Value "# stub launcher" -Encoding ASCII

        function Get-Command {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Test double')]
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Signature must match the real cmdlet')]
            param([Parameter(Position = 0)][string]$Name)
            if ($Name -eq 'Get-ScheduledTask' -or $Name -eq 'Export-ScheduledTask') {
                return [pscustomobject]@{ Source = 'stub' }
            }
            return $null
        }
        function Get-ScheduledTask {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Signature must match the real cmdlet')]
            param([string]$TaskName)
            $script:Calls['Get-ScheduledTask']++
            return [pscustomobject]@{ TaskName = $TaskName }
        }
        function Export-ScheduledTask {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Signature must match the real cmdlet')]
            param([string]$TaskName)
            $script:Calls['Export-ScheduledTask']++
            return $script:StubLiveXml
        }
        function Register-ScheduledTask {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Signature must match the real cmdlet')]
            param([string]$TaskName, [string]$Xml, [switch]$Force)
            $script:Calls['Register-ScheduledTask']++
            $script:RegisteredName = $TaskName
        }
        function Unregister-ScheduledTask {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Signature must match the real cmdlet')]
            param([string]$TaskName)
            $script:Calls['Unregister-ScheduledTask']++
        }

        # The live task differs from the declaration, so the module has to
        # register it.
        $script:StubLiveXml = $script:LiveS4UForHost

        . $script:modulePath -action apply | Out-Null

        # Exactly one registration: the declared task. Nothing else is
        # unregistered -- the machine may carry tasks winos knows nothing
        # about, and they are none of the module's business.
        $script:Calls['Register-ScheduledTask'] | Should -Be 1
        $script:RegisteredName             | Should -Be 'OpenCodeServe'
        $script:Calls['Unregister-ScheduledTask'] | Should -Be 0
    }
}
