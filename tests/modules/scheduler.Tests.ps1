BeforeAll {
    $script:modulePath = Join-Path $PSScriptRoot "../../src/modules/scheduler.ps1"
    $script:statePath  = Join-Path $PSScriptRoot "../../src/modules/scheduler/State.ps1"
    $script:templateDir = Join-Path $PSScriptRoot "../../src/modules/scheduler/tasks"

    # The tests must run unattended: no confirmation prompt, no question.
    $ConfirmPreference = 'None'

    # Parse both files once up front so authoring errors surface everywhere.
    foreach ($path in @($script:modulePath, $script:statePath)) {
        $errors = $null
        $tokens = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $path, [ref]$tokens, [ref]$errors) | Out-Null
    }

    # The declared task, in the shape the declaration has: what runs it, when,
    # as whom, and the settings that keep a server alive.
    $script:DeclaredXml = @'
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <URI>\OpenCode Serve</URI>
  </RegistrationInfo>
  <Triggers>
    <BootTrigger>
      <Enabled>true</Enabled>
    </BootTrigger>
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
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <StartWhenAvailable>true</StartWhenAvailable>
    <Enabled>true</Enabled>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <RestartOnFailure>
      <Interval>PT1M</Interval>
      <Count>5</Count>
    </RestartOnFailure>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>C:\Program Files\Git\bin\bash.exe</Command>
      <Arguments>-lc "bash /c/root/.local/share/metaagent/tools/host-scripts/opencode-serve.sh"</Arguments>
    </Exec>
  </Actions>
</Task>
'@

    # The same task as Task Scheduler exports it: the same facts, plus the
    # Author/Date/Description noise every export carries, the SID it writes
    # instead of the account name, and the elements it OMITS because they
    # carry the schema default (no RunLevel, no Settings/Enabled).
    $script:LiveXml = @'
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Date>2026-11-03T09:00:00.0000000</Date>
    <Author>HOST\user</Author>
    <Description>opencode serve on 0.0.0.0:4096</Description>
    <URI>\OpenCode Serve</URI>
  </RegistrationInfo>
  <Principals>
    <Principal id="Author">
      <UserId>S-1-5-21-3128982854-1876076413-825495757-1001</UserId>
      <LogonType>InteractiveToken</LogonType>
    </Principal>
  </Principals>
  <Settings>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RestartOnFailure>
      <Count>5</Count>
      <Interval>PT1M</Interval>
    </RestartOnFailure>
    <IdleSettings>
      <Duration>PT10M</Duration>
      <WaitTimeout>PT1H</WaitTimeout>
      <StopOnIdleEnd>true</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
  </Settings>
  <Triggers>
    <BootTrigger>
      <Delay>PT20S</Delay>
    </BootTrigger>
    <LogonTrigger>
      <UserId>HOST\user</UserId>
    </LogonTrigger>
  </Triggers>
  <Actions Context="Author">
    <Exec>
      <Command>C:\Program Files\Git\bin\bash.exe</Command>
      <Arguments>-lc "bash /c/root/.local/share/metaagent/tools/host-scripts/opencode-serve.sh"</Arguments>
    </Exec>
  </Actions>
</Task>
'@

    # The task that bit the owner on 2026-11-04: created by the wizard, never
    # imported from the declaration. Batteries on, 72-hour limit, no restart,
    # and the start missed while the machine was off is not caught up.
    $script:LiveXmlDrifted = $script:LiveXml `
        -replace '<DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>', '<DisallowStartIfOnBatteries>true</DisallowStartIfOnBatteries>' `
        -replace '<StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>', '<StopIfGoingOnBatteries>true</StopIfGoingOnBatteries>' `
        -replace '<ExecutionTimeLimit>PT0S</ExecutionTimeLimit>', '<ExecutionTimeLimit>PT72H</ExecutionTimeLimit>' `
        -replace '<Count>5</Count>', '<Count>0</Count>' `
        -replace '\s*<StartWhenAvailable>true</StartWhenAvailable>', ''

    # The same task, but the logon type is the one that drifted between the
    # two hosts (S4U against InteractiveToken).
    $script:LiveS4U = $script:LiveXml -replace '<LogonType>InteractiveToken</LogonType>', '<LogonType>S4U</LogonType>'

    # The same task, but it runs something else: a plain `-c` and the
    # vetymae launcher, i.e. the spelling the profile-sourcing declaration
    # must NOT imitate.
    $script:LiveOtherAction = $script:LiveXml -replace '-lc "bash /c/root/\.local/share/metaagent/tools/host-scripts/opencode-serve\.sh"', '-c "exec /c/Users/user/.local/bin/oc-serve-task.sh"'

    # The pure half of the module: functions over XML strings, no Task
    # Scheduler involved.
    . $script:statePath
}

Describe "scheduler/State.ps1" {

    It "reads the facts that carry the meaning out of a task document" {
        $facts = Get-TaskFacts -Xml $script:DeclaredXml

        $facts.LogonType                | Should -Be 'InteractiveToken'
        $facts.RunLevel                 | Should -Be 'LeastPrivilege'
        $facts.UserId                   | Should -Be 'HOST\user'
        $facts.Command                  | Should -Be 'C:\Program Files\Git\bin\bash.exe'
        $facts.WorkingDirectory         | Should -Be ''
        $facts.RestartCount             | Should -Be '5'
        $facts.ExecutionTimeLimit       | Should -Be 'PT0S'
        $facts.DisallowStartIfOnBatteries | Should -Be 'false'
        $facts.StopIfGoingOnBatteries   | Should -Be 'false'
        $facts.StartWhenAvailable       | Should -Be 'true'
        @($facts.Triggers)              | Should -Be @('Boot', 'Logon:HOST\user')
    }

    It "reads the same facts out of an exported task" {
        # The exported document carries Author/Date/Description the
        # declaration does not have, omits the elements that carry the schema
        # default, and writes the account as a SID. The facts must come out
        # the same.
        $declared = Get-TaskFacts -Xml $script:DeclaredXml
        $actual   = Get-TaskFacts -Xml $script:LiveXml

        $actual.LogonType                | Should -Be $declared.LogonType
        $actual.RunLevel                 | Should -Be $declared.RunLevel
        $actual.Command                  | Should -Be $declared.Command
        $actual.Arguments                | Should -Be $declared.Arguments
        $actual.WorkingDirectory         | Should -Be $declared.WorkingDirectory
        $actual.MultipleInstances        | Should -Be $declared.MultipleInstances
        $actual.DisallowStartIfOnBatteries | Should -Be $declared.DisallowStartIfOnBatteries
        $actual.StopIfGoingOnBatteries   | Should -Be $declared.StopIfGoingOnBatteries
        $actual.ExecutionTimeLimit       | Should -Be $declared.ExecutionTimeLimit
        $actual.RestartCount             | Should -Be $declared.RestartCount
        $actual.StartWhenAvailable       | Should -Be $declared.StartWhenAvailable
        @($actual.Triggers)              | Should -Be @($declared.Triggers)
    }

    It "survives an empty or broken document" {
        (Get-TaskFacts -Xml '').LogonType | Should -Be ''
        (Get-TaskFacts -Xml '<not-xml').LogonType | Should -Be ''
        (Get-TaskFacts -Xml '').ExecutionTimeLimit | Should -Be ''
    }

    It "reads an OMITTED setting as the scheduler default, not as an absence" {
        # This is the trap. Task Scheduler leaves <ExecutionTimeLimit> out of
        # an export when it carries the default, and the default is 72 hours
        # -- not "no limit". Same for the two battery flags: both default to
        # true.
        $plain = @'
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
  </Settings>
</Task>
'@
        $facts = Get-TaskFacts -Xml $plain

        $facts.ExecutionTimeLimit         | Should -Be 'PT72H'
        $facts.DisallowStartIfOnBatteries | Should -Be 'true'
        $facts.StopIfGoingOnBatteries     | Should -Be 'true'
        $facts.RestartCount               | Should -Be '0'
        $facts.StartWhenAvailable         | Should -Be 'false'
        $facts.Enabled                    | Should -Be 'true'
    }

    It "finds the file the action runs" {
        $facts = Get-TaskFacts -Xml $script:DeclaredXml
        Get-TaskActionTarget -Facts $facts |
            Should -Be '/c/root/.local/share/metaagent/tools/host-scripts/opencode-serve.sh'
    }

    It "reports no target when the action is a bare command" {
        $facts = [pscustomobject]@{ Command = 'notepad.exe'; Arguments = '' }
        Get-TaskActionTarget -Facts $facts | Should -Be ''
    }

    It "treats a SID and an account name as not comparable" {
        (Get-AccountFact -Value 'S-1-5-21-3128982854-1876076413-825495757-1001') | Should -Be ''
        (Get-AccountFact -Value 'HOST\user') | Should -Be 'HOST\user'
    }
}

Describe "the task name" {

    It "is the same task however the host spells it" {
        # lamet calls it "OpenCode Serve", vetymae "opencode-serve", the
        # declaration is OpenCodeServe.xml. One task, three spellings.
        $key = Get-TaskNameKey -Name 'OpenCodeServe'

        (Get-TaskNameKey -Name 'OpenCode Serve')  | Should -Be $key
        (Get-TaskNameKey -Name 'opencode-serve')  | Should -Be $key
        (Get-TaskNameKey -Name 'OPENCODE_SERVE')  | Should -Be $key
        (Get-TaskNameKey -Name '\OpenCode Serve') | Should -Be $key
        (Get-TaskNameKey -Name 'OpenCodeServeOld') | Should -Not -Be $key
    }

    It "resolves the declaration to the live task under its own spelling" {
        $resolution = Resolve-LiveTaskName -DeclaredName 'OpenCodeServe' `
            -LiveNames @('OpenCodeAdvegoWatch', 'OpenCode Serve', 'OpenCodeCaptureScreen')

        $resolution.Name    | Should -Be 'OpenCode Serve'
        @($resolution.Matches).Count | Should -Be 1
    }

    It "resolves to nothing when only a LONGER name exists" {
        # OpenCodeServeOld is not this task. It is not silently accepted as
        # one either -- Get-UndeclaredTaskFindings reports it.
        $resolution = Resolve-LiveTaskName -DeclaredName 'OpenCodeServe' -LiveNames @('OpenCodeServeOld')

        $resolution.Name | Should -Be ''
        @($resolution.Matches).Count | Should -Be 0
    }

    It "reports the same task registered twice" {
        $resolution = Resolve-LiveTaskName -DeclaredName 'OpenCodeServe' `
            -LiveNames @('OpenCode Serve', 'opencode-serve')

        $resolution.Name | Should -Be ''
        @($resolution.Matches).Count | Should -Be 2
    }
}

Describe "undeclared live tasks" {

    BeforeAll {
        $script:DeclaredEntry = @(
            [pscustomobject]@{
                Name         = 'OpenCodeServe'
                ActionTarget = '/c/Users/user/.local/share/metaagent/tools/host-scripts/opencode-serve.sh'
            }
        )
    }

    It "reports a task whose name merely extends a declared one" {
        $findings = Get-UndeclaredTaskFindings -Declared $script:DeclaredEntry -Live @(
            [pscustomobject]@{ Name = 'OpenCodeServeOld'; Xml = '' }
        )

        @($findings).Count | Should -Be 1
        $findings[0].Name   | Should -Be 'OpenCodeServeOld'
        $findings[0].Reason | Should -Match 'declared task with something added'
    }

    It "reports a task under an unrelated name that runs the declared launcher" {
        $xml = @'
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Actions Context="Author">
    <Exec>
      <Command>C:\Program Files\Git\bin\bash.exe</Command>
      <Arguments>-lc "bash /c/Users/user/.local/share/metaagent/tools/host-scripts/opencode-serve.sh"</Arguments>
    </Exec>
  </Actions>
</Task>
'@
        $findings = Get-UndeclaredTaskFindings -Declared $script:DeclaredEntry -Live @(
            [pscustomobject]@{ Name = 'ServeTheThing'; Xml = $xml }
        )

        @($findings).Count | Should -Be 1
        $findings[0].Name   | Should -Be 'ServeTheThing'
        $findings[0].Reason | Should -Match 'runs the declared launcher'
    }

    It "leaves the tasks of the owner alone" {
        # OpenCodeCaptureScreen and friends are somebody else's business: the
        # module reports drift, it does not audit the machine.
        $xml = @'
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-File C:\Tools\capture.ps1</Arguments>
    </Exec>
  </Actions>
</Task>
'@
        $findings = Get-UndeclaredTaskFindings -Declared $script:DeclaredEntry -Live @(
            [pscustomobject]@{ Name = 'OpenCodeCaptureScreen'; Xml = $xml }
        )

        @($findings).Count | Should -Be 0
    }

    It "does not report the task a declaration already covers" {
        $findings = Get-UndeclaredTaskFindings -Declared $script:DeclaredEntry -Live @(
            [pscustomobject]@{ Name = 'OpenCode Serve'; Xml = '' }
        )

        @($findings).Count | Should -Be 0
    }
}

Describe "the path spellings" {

    It "converts a Windows path to the way bash spells it and back" {
        ConvertTo-BashPath -Path 'C:\Users\oqyude'      | Should -Be '/c/Users/oqyude'
        ConvertTo-BashPath -Path 'C:\Users\oqyude\x.sh' | Should -Be '/c/Users/oqyude/x.sh'
        ConvertFrom-BashPath -Path '/c/Users/oqyude/x.sh' | Should -Be 'C:\Users\oqyude\x.sh'
        ConvertTo-BashPath -Path '/tmp/x'               | Should -Be '/tmp/x'
        ConvertTo-BashPath -Path ''                     | Should -Be ''
    }

    It "names the Git Bash that the wrapper would find" {
        # Same order as src/host-scripts/opencode-serve.cmd: Program Files
        # first, then the x86 install, then the per-user one.
        $path = Get-GitBashPath -ProgramFiles 'C:\Program Files'
        $path | Should -BeLike '*Git\bin\bash.exe'
    }
}

Describe "Get-TaskDiff" {

    It "reports a match when the declaration and the live task agree" {
        $diff = Get-TaskDiff -Name 'OpenCode Serve' -DeclaredXml $script:DeclaredXml -LiveXml $script:LiveXml

        $diff.State       | Should -Be 'Matches'
        @($diff.Differences).Count | Should -Be 0
    }

    It "reports the logon type difference" {
        $diff = Get-TaskDiff -Name 'OpenCode Serve' -DeclaredXml $script:DeclaredXml -LiveXml $script:LiveS4U

        $diff.State | Should -Be 'Differs'
        $kinds = @($diff.Differences | ForEach-Object { $_.Kind })
        $kinds | Should -Contain 'LogonType'

        $logon = $diff.Differences | Where-Object { $_.Kind -eq 'LogonType' }
        $logon.Declared | Should -Be 'InteractiveToken'
        $logon.Actual   | Should -Be 'S4U'
    }

    It "reports the action difference" {
        $diff = Get-TaskDiff -Name 'OpenCode Serve' -DeclaredXml $script:DeclaredXml -LiveXml $script:LiveOtherAction

        $diff.State | Should -Be 'Differs'
        $action = $diff.Differences | Where-Object { $_.Kind -eq 'Action' }
        $action | Should -Not -BeNullOrEmpty
        $action.Declared | Should -BeLike '*-lc*'
        $action.Actual   | Should -BeLike '*-c *oc-serve-task.sh*'
    }

    It "reports a missing task" {
        $diff = Get-TaskDiff -Name 'OpenCodeServe' -DeclaredXml $script:DeclaredXml -LiveXml ''

        $diff.State       | Should -Be 'Missing'
        $diff.Actual      | Should -BeNullOrEmpty
        @($diff.Differences).Count | Should -Be 0
    }

    It "reports a trigger difference when the task fires at another time" {
        $other = $script:LiveXml -replace '<BootTrigger>', '<LogonTrigger>' -replace '</BootTrigger>', '</LogonTrigger>'
        $diff = Get-TaskDiff -Name 'OpenCode Serve' -DeclaredXml $script:DeclaredXml -LiveXml $other

        $diff.State | Should -Be 'Differs'
        $kinds = @($diff.Differences | ForEach-Object { $_.Kind })
        $kinds | Should -Contain 'Triggers'
    }

    It "reports the battery flags on their own, under their own names" {
        # The three settings that killed the server: each one is its own
        # finding, because "Settings differ" is a line nobody can act on.
        $diff = Get-TaskDiff -Name 'OpenCode Serve' -DeclaredXml $script:DeclaredXml -LiveXml $script:LiveXmlDrifted

        $diff.State | Should -Be 'Differs'

        $battery = $diff.Differences | Where-Object { $_.Kind -eq 'DisallowStartIfOnBatteries' }
        $battery | Should -Not -BeNullOrEmpty
        $battery.Declared | Should -Be 'false'
        $battery.Actual   | Should -Be 'true'

        $stop = $diff.Differences | Where-Object { $_.Kind -eq 'StopIfGoingOnBatteries' }
        $stop | Should -Not -BeNullOrEmpty
        $stop.Declared | Should -Be 'false'
        $stop.Actual   | Should -Be 'true'
    }

    It "reports the 72-hour time limit with the field named" {
        $diff = Get-TaskDiff -Name 'OpenCode Serve' -DeclaredXml $script:DeclaredXml -LiveXml $script:LiveXmlDrifted

        $limit = $diff.Differences | Where-Object { $_.Kind -eq 'ExecutionTimeLimit' }
        $limit | Should -Not -BeNullOrEmpty
        $limit.Declared | Should -Be 'PT0S'
        $limit.Actual   | Should -Be 'PT72H'
    }

    It "reports a restart budget of zero with the field named" {
        $diff = Get-TaskDiff -Name 'OpenCode Serve' -DeclaredXml $script:DeclaredXml -LiveXml $script:LiveXmlDrifted

        $restart = $diff.Differences | Where-Object { $_.Kind -eq 'RestartOnFailure' }
        $restart | Should -Not -BeNullOrEmpty
        $restart.Declared | Should -Be '5/PT1M'
        $restart.Actual   | Should -Be '0/PT1M'
    }

    It "reports a start missed while the machine was off" {
        $diff = Get-TaskDiff -Name 'OpenCode Serve' -DeclaredXml $script:DeclaredXml -LiveXml $script:LiveXmlDrifted

        $start = $diff.Differences | Where-Object { $_.Kind -eq 'StartWhenAvailable' }
        $start | Should -Not -BeNullOrEmpty
        $start.Declared | Should -Be 'true'
        $start.Actual   | Should -Be 'false'
    }

    It "reports every field of the drifted task, not one lumped Settings line" {
        $diff = Get-TaskDiff -Name 'OpenCode Serve' -DeclaredXml $script:DeclaredXml -LiveXml $script:LiveXmlDrifted
        $kinds = @($diff.Differences | ForEach-Object { $_.Kind })

        $kinds | Should -Contain 'DisallowStartIfOnBatteries'
        $kinds | Should -Contain 'StopIfGoingOnBatteries'
        $kinds | Should -Contain 'ExecutionTimeLimit'
        $kinds | Should -Contain 'RestartOnFailure'
        $kinds | Should -Contain 'StartWhenAvailable'
        $kinds | Should -Not -Contain 'Settings'
    }

    It "does not report the account the exporter wrote as a SID" {
        # A dimension with nothing comparable on one side says nothing; a
        # difference that fires on every host teaches the reader to ignore
        # the report.
        $diff = Get-TaskDiff -Name 'OpenCode Serve' -DeclaredXml $script:DeclaredXml -LiveXml $script:LiveXml

        @($diff.Differences | Where-Object { $_.Kind -eq 'UserId' }).Count | Should -Be 0
    }

    It "reports an account that really is another account" {
        # The principal written as a NAME on both sides: then they can be
        # compared, and a different account is a difference.
        $other = $script:LiveXml -replace '<UserId>S-1-5-21-3128982854-1876076413-825495757-1001</UserId>', '<UserId>HOST\someoneelse</UserId>'
        $diff = Get-TaskDiff -Name 'OpenCode Serve' -DeclaredXml $script:DeclaredXml -LiveXml $other

        @($diff.Differences | Where-Object { $_.Kind -eq 'UserId' }).Count | Should -Be 1
    }
}

Describe "the declared tasks" {

    It "ships a declaration for the opencode serve task" {
        Test-Path -LiteralPath $script:templateDir | Should -BeTrue

        $declarations = Get-SchedulerTaskDeclarations -TemplateDir $script:templateDir -Values (Get-SchedulerHostValues)
        $declarations.Count | Should -BeGreaterThan 0
        $declarations.Name | Should -Contain 'OpenCodeServe'
    }

    It "resolves the per-host placeholders" {
        $values = Get-SchedulerHostValues -DataRoot 'C:\data' -ToolsDir 'C:\Tools' -UserProfile 'C:\Users\u' -User 'HOST\u'

        $declarations = Get-SchedulerTaskDeclarations -TemplateDir $script:templateDir -Values $values
        $declaration = $declarations | Where-Object { $_.Name -eq 'OpenCodeServe' }

        $declaration.Xml | Should -Not -Match '__[A-Z_]+__'
        $declaration.Xml | Should -BeLike '*C:\data*'
        $declaration.Xml | Should -BeLike '*HOST\u*'
        $declaration.Xml | Should -BeLike '*Git\bin\bash.exe*'
    }

    It "declares what the hosts really run: Git Bash in login mode" {
        # -lc is load-bearing: a login shell sources ~/.bashrc, and that is
        # where OPENCODE_SERVER_PASSWORD is exported. A plain -c (the other
        # host's spelling) is drift.
        $values = Get-SchedulerHostValues -DataRoot 'C:\data' -ToolsDir 'C:\Tools' -UserProfile 'C:\Users\u' -User 'HOST\u'
        $declaration = (Get-SchedulerTaskDeclarations -TemplateDir $script:templateDir -Values $values) |
            Where-Object { $_.Name -eq 'OpenCodeServe' }

        $facts = Get-TaskFacts -Xml $declaration.Xml
        $facts.Command   | Should -BeLike '*Git\bin\bash.exe'
        $facts.Arguments | Should -Be '-lc "bash /c/Users/u/.local/share/metaagent/tools/host-scripts/opencode-serve.sh"'
        $facts.WorkingDirectory | Should -Be ''
        $facts.LogonType | Should -Be 'InteractiveToken'
        $facts.RunLevel  | Should -Be 'LeastPrivilege'
        @($facts.Triggers) | Should -Be @('Boot', 'Logon:HOST\u')
    }

    It "pins the settings that keep the server alive" {
        $values = Get-SchedulerHostValues -DataRoot 'C:\data' -ToolsDir 'C:\Tools' -UserProfile 'C:\Users\u' -User 'HOST\u'
        $declaration = (Get-SchedulerTaskDeclarations -TemplateDir $script:templateDir -Values $values) |
            Where-Object { $_.Name -eq 'OpenCodeServe' }

        $facts = Get-TaskFacts -Xml $declaration.Xml
        $facts.DisallowStartIfOnBatteries | Should -Be 'false'
        $facts.StopIfGoingOnBatteries     | Should -Be 'false'
        $facts.ExecutionTimeLimit         | Should -Be 'PT0S'
        $facts.RestartCount               | Should -Be '5'
        $facts.StartWhenAvailable         | Should -Be 'true'
        $facts.MultipleInstances          | Should -Be 'IgnoreNew'
    }

    It "explains in its header why the name is matched by key" {
        # The one thing a reader must not have to rediscover: the file name is
        # a declaration id, and the host's spelling is the host's business.
        $raw = Get-Content -Raw -LiteralPath (Join-Path $script:templateDir 'OpenCodeServe.xml')

        $raw | Should -Match 'THE NAME'
        $raw | Should -Match 'Get-TaskNameKey'
        $raw | Should -Match '-lc'
    }
}

Describe "scheduler.ps1" {

    BeforeEach {
        # The module reads these; set them so the test does not depend on
        # the host's own layout. USERPROFILE is the profile path the declared
        # action points into, so the test owns it too.
        $storage = Join-Path ([System.IO.Path]::GetTempPath()) "winos-scheduler-tests"
        if (-not (Test-Path $storage)) { New-Item -ItemType Directory -Path $storage -Force | Out-Null }

        # The account the task runs as. The declaration resolves __USER__ from
        # the environment, and the live task in this test says "HOST\user" --
        # so the environment has to say the same thing, or every comparison
        # would report a difference in the account that is not there.
        $script:SavedUserName     = $env:USERNAME
        $script:SavedComputerName = $env:COMPUTERNAME
        $script:SavedProfile      = $env:USERPROFILE
        $env:USERNAME     = 'user'
        $env:COMPUTERNAME = 'HOST'
        $env:USERPROFILE  = $storage

        # The file the declared action runs has to EXIST: the module refuses
        # to register a task that would start and die, and it says so. The
        # path is built exactly the way the declaration builds it, so it is
        # the same string on every host.
        $script:ActionTarget = Join-Path $storage ".local/share/metaagent/tools/host-scripts/opencode-serve.sh"
        New-Item -ItemType Directory -Path (Split-Path -Parent $script:ActionTarget) -Force | Out-Null
        Set-Content -LiteralPath $script:ActionTarget -Value '# stub launcher' -Encoding ASCII

        # The live task, resolved against THIS host's profile path: the same
        # document the declaration produces, plus the noise an export adds.
        $script:LiveXmlForHost   = ($script:LiveXml         -replace '/c/root', $storage)
        $script:DriftedForHost   = ($script:LiveXmlDrifted  -replace '/c/root', $storage)
        $script:LiveS4UForHost   = ($script:LiveS4U         -replace '/c/root', $storage)

        $script:Calls = [ordered]@{
            'Get-ScheduledTask'       = 0
            'Export-ScheduledTask'    = 0
            'Register-ScheduledTask'  = 0
            'Unregister-ScheduledTask' = 0
        }
        $script:RegisteredName = $null

        # The machine the test pretends to be: name -> exported XML.
        $script:StubTasks = [ordered]@{}

        function Get-Command {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Test double')]
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Signature must match the real cmdlet')]
            param([Parameter(Position = 0)][string]$Name)
            if ($Name -eq 'Get-ScheduledTask' -or $Name -eq 'Export-ScheduledTask') {
                return [pscustomobject]@{ Source = 'stub' }
            }
            # Anything else is the real cmdlet: the test asserts on the
            # module's own -action parameter through it.
            return Microsoft.PowerShell.Core\Get-Command -Name $Name -ErrorAction SilentlyContinue
        }
        function Get-ScheduledTask {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Signature must match the real cmdlet')]
            param([string]$TaskName, [string]$TaskPath)
            $script:Calls['Get-ScheduledTask']++
            if ($TaskName) {
                if ($script:StubTasks.Contains($TaskName)) { return [pscustomobject]@{ TaskName = $TaskName } }
                return $null
            }
            # -TaskPath '\' is the enumeration the module does: every task in
            # the root folder, by name.
            return @($script:StubTasks.Keys | ForEach-Object { [pscustomobject]@{ TaskName = $_ } })
        }
        function Export-ScheduledTask {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Signature must match the real cmdlet')]
            param([string]$TaskName)
            $script:Calls['Export-ScheduledTask']++
            if ($script:StubTasks.Contains($TaskName)) { return $script:StubTasks[$TaskName] }
            return ''
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
    }

    AfterEach {
        # The environment is the test's own; put it back the way it was.
        if ($null -eq $script:SavedUserName) { Remove-Item Env:\USERNAME -ErrorAction SilentlyContinue }
        else { $env:USERNAME = $script:SavedUserName }
        if ($null -eq $script:SavedComputerName) { Remove-Item Env:\COMPUTERNAME -ErrorAction SilentlyContinue }
        else { $env:COMPUTERNAME = $script:SavedComputerName }
        if ($null -eq $script:SavedProfile) { Remove-Item Env:\USERPROFILE -ErrorAction SilentlyContinue }
        else { $env:USERPROFILE = $script:SavedProfile }
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
        # The machine calls the task by the declaration's own name here.
        $script:StubTasks['OpenCodeServe'] = $script:LiveXmlForHost

        $output = (. $script:modulePath -action plan 6>&1 | Out-String)

        $script:Calls['Get-ScheduledTask']    | Should -BeGreaterThan 0
        $script:Calls['Export-ScheduledTask'] | Should -BeGreaterThan 0
        # The module must never go looking for tasks to clean up.
        $script:Calls['Unregister-ScheduledTask'] | Should -Be 0
        $output | Should -Match 'matches the declaration'
    }

    It "plan finds the live task when the host spells the name differently" {
        # lamet calls it "OpenCode Serve". The declaration is
        # OpenCodeServe.xml. Before 2026-11-04 this ended in "not registered
        # on this machine" and the drift stayed invisible.
        $script:StubTasks['OpenCode Serve'] = $script:LiveXmlForHost

        $output = (. $script:modulePath -action plan 6>&1 | Out-String)

        $output | Should -Match 'OpenCode Serve.*matches the declaration'
        $output | Should -Not -Match 'MISS'
    }

    It "plan names the battery, the time limit and the restart drift" {
        $script:StubTasks['OpenCode Serve'] = $script:DriftedForHost

        $output = (. $script:modulePath -action plan 6>&1 | Out-String)

        $output | Should -Match 'DIFF'
        $output | Should -Match 'DisallowStartIfOnBatteries: declared .false. / actual .true.'
        $output | Should -Match 'ExecutionTimeLimit: declared .PT0S. / actual .PT72H.'
        $output | Should -Match 'RestartOnFailure: declared .5/PT1M. / actual .0/PT1M.'
    }

    It "plan reports a live task that carries no declaration" {
        $script:StubTasks['OpenCodeServe'] = $script:LiveXmlForHost
        $script:StubTasks['OpenCodeServeOld'] = $script:DriftedForHost

        $output = (. $script:modulePath -action plan 6>&1 | Out-String)

        $output | Should -Match 'UNDECLARED'
        $output | Should -Match 'OpenCodeServeOld'
    }

    It "plan reports the same task registered twice" {
        $script:StubTasks['OpenCode Serve'] = $script:LiveXmlForHost
        $script:StubTasks['opencode-serve'] = $script:DriftedForHost

        $output = (. $script:modulePath -action plan 6>&1 | Out-String)

        $output | Should -Match 'DUPL'
    }

    It "status exits 1 when a live task carries no declaration" {
        $script:StubTasks['OpenCodeServe'] = $script:LiveXmlForHost
        $script:StubTasks['OpenCodeServeOld'] = $script:DriftedForHost

        $exit = 0
        try { . $script:modulePath -action status 6>&1 | Out-Null } catch { $exit = 1 }
        if (-not $exit -and $LASTEXITCODE) { $exit = $LASTEXITCODE }

        # `status` calls `exit 1`; in-process that ends the pipeline, so the
        # assertion is on the output as well as on the code.
        $exit | Should -Be 1
    }

    It "apply with -WhatIf registers nothing" {
        # The live task DIFFERS from the declaration, so without -WhatIf the
        # module would register it. That is what makes this test about -WhatIf
        # and not about a task that matched anyway.
        $script:StubTasks['OpenCode Serve'] = $script:LiveS4UForHost

        . $script:modulePath -action apply -WhatIf | Out-Null

        $script:Calls['Register-ScheduledTask']   | Should -Be 0
        $script:Calls['Unregister-ScheduledTask'] | Should -Be 0
    }

    It "apply registers only the declared task, under the name the host uses" {
        # The live task differs from the declaration, so the module has to
        # register it -- and under the LIVE name, or the machine would end up
        # with two tasks and one port.
        $script:StubTasks['OpenCode Serve'] = $script:LiveS4UForHost

        . $script:modulePath -action apply | Out-Null

        $script:Calls['Register-ScheduledTask'] | Should -Be 1
        $script:RegisteredName                  | Should -Be 'OpenCode Serve'
        $script:Calls['Unregister-ScheduledTask'] | Should -Be 0
    }

    It "apply skips a task whose launcher is not on disk" {
        Remove-Item -LiteralPath $script:ActionTarget -Force
        $script:StubTasks['OpenCode Serve'] = $script:LiveS4UForHost

        $output = (. $script:modulePath -action apply 6>&1 | Out-String)

        $script:Calls['Register-ScheduledTask'] | Should -Be 0
        $output | Should -Match 'the action target does not exist'
    }
}
