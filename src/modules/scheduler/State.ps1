# scheduler/State.ps1 -- the pure half of the scheduler module.
#
# Everything in this file works on XML strings and never calls the Task
# Scheduler, so the diff can be exercised on any host: Windows, Linux, a
# container, a CI runner. The module (src/modules/scheduler.ps1) adds the
# Windows-only calls around it -- Get-ScheduledTask, Export-ScheduledTask,
# Register-ScheduledTask -- and this file is what the tests actually drive.
#
# Why a diff and not a plain compare: two task definitions that MEAN the same
# thing are never byte-identical. Task Scheduler writes a URI, an Author, a
# Date and a whole Settings block that a hand-written declaration does not
# have. Comparing the raw XML would report a difference on every field that
# does not matter and bury the one that does. So the comparison is over the
# facts that carry the meaning:
#
#   * who runs it   -- UserId, LogonType, RunLevel
#   * when it runs  -- the set of triggers, and the settings that decide
#                      whether a start happens at all: the battery flags, the
#                      execution time limit, the restart-on-failure budget,
#                      StartWhenAvailable, Enabled
#   * what it runs  -- Command, Arguments, WorkingDirectory
#
# EVERY FIELD ABOVE IS ITS OWN DIMENSION, AND THE REPORT NAMES IT. That is
# not cosmetic (2026-11-04): the owner found a laptop whose server had died
# because the LIVE task carried DisallowStartIfOnBatteries=True,
# StopIfGoingOnBatteries=True, ExecutionTimeLimit=PT72H and RestartCount=0
# while the declaration said false/false/PT0S/5. The old Settings dimension
# lumped the four into one string -- "declared 'IgnoreNew/5/PT0S/true' /
# actual 'IgnoreNew/0/PT72H/true'" -- a line nobody can act on. They are four
# findings now, each printed with its own field name.
#
# WHAT IS IGNORED, AND WHY (the table is in docs/scheduler.md):
#
#   * RegistrationInfo -- URI, Author, Date, Description. Task Scheduler
#     writes them into every export; a hand-written declaration has none.
#   * the Delay of a boot trigger, and the whole IdleSettings block: they
#     matter only to a task that runs on idle, and this one does not.
#   * UseUnifiedSchedulingEngine, AllowHardTerminate, Priority, Hidden,
#     WakeToRun, RunOnlyIfNetworkAvailable, AllowStartOnDemand,
#     RunOnlyIfIdle -- the declaration does not name them, so they keep the
#     scheduler's own default on every host. There is nothing to drift from
#     and nothing is silently rewritten: apply registers the declaration,
#     which does not mention them either.
#   * the version attribute of <Task>.
#   * an account written as a SID. The exporter writes
#     <UserId>S-1-5-21-...</UserId> for the principal while the declaration
#     writes DOMAIN\user; the two cannot be compared without asking Windows
#     to translate them, and a difference that fires on EVERY host is worse
#     than no comparison -- it teaches the reader to ignore the report. The
#     account is still pinned: apply re-registers it from the declaration.
#
# AND THE DEFAULTS ARE FACTS. Task Scheduler OMITS a setting that carries the
# schema default, so "the element is absent" means "the default", never "not
# declared". This is the trap that made the drift invisible, so the defaults
# are spelled out here and every one of them is normalised on read:
#
#   ExecutionTimeLimit          PT72H     <- the one that killed the server
#   DisallowStartIfOnBatteries  true      <- and this one
#   StopIfGoingOnBatteries      true      <- and this one
#   MultipleInstancesPolicy     IgnoreNew
#   RestartOnFailure            disabled (count 0)
#   StartWhenAvailable          false
#   Enabled                     true
#   Principal/LogonType         InteractiveToken
#   Principal/RunLevel          LeastPrivilege
#   Trigger/Enabled             true
#
# A declaration that says PT0S, compared with a live task that has no
# <ExecutionTimeLimit> element at all, therefore reports PT0S vs PT72H --
# which is the truth: that task stops after 72 hours.
#
# THE NAME. A declaration is a file (OpenCodeServe.xml); the live task may be
# spelled "OpenCode Serve" (lamet) or "opencode-serve" (vetymae). The file
# name is the declaration ID and the ONLY source of truth for the name; a
# live task is the same task when its name has the same KEY, i.e. the name
# with case, spaces, dashes and underscores removed (Get-TaskNameKey). An
# alias table was the alternative and was rejected: it needs one entry per
# host and goes stale the day a third host spells it "opencode_serve". A
# live task whose key is NOT the declared key but which runs the same
# launcher (or whose key merely extends the declared one) is reported as
# UNDECLARED -- never ignored (Get-UndeclaredTaskFindings).

# Get-XmlNodeText -- the text of the first node under $Node matching $XPath.
#
# The XPath uses local-name() everywhere: Task Scheduler's XML carries a
# default namespace, and a namespace-blind query is the only one that works
# on both a hand-written declaration and an exported task.
function Get-XmlNodeText {
    param($Node, [string]$XPath)

    if (-not $Node) { return '' }
    $found = $Node.SelectSingleNode($XPath)
    if (-not $found) { return '' }
    return [string]$found.InnerText
}

# Get-TaskFacts -- the comparable facts of one task definition.
#
# An empty or unparsable XML yields the same shape with empty values, so the
# caller never has to special-case a missing task. A document that IS a task
# gets the scheduler's defaults filled in first (see the header): a missing
# element is a default, not an absence.
function Get-TaskFacts {
    param([string]$Xml)

    $facts = [ordered]@{
        UserId                     = ''
        LogonType                  = ''
        RunLevel                   = ''
        Triggers                   = @()
        Command                    = ''
        Arguments                  = ''
        WorkingDirectory           = ''
        MultipleInstances          = ''
        DisallowStartIfOnBatteries = ''
        StopIfGoingOnBatteries     = ''
        StartWhenAvailable         = ''
        ExecutionTimeLimit         = ''
        RestartCount               = ''
        RestartInterval            = ''
        Enabled                    = ''
    }

    if (-not $Xml) { return [pscustomobject]$facts }

    $doc = $null
    try { $doc = [xml]$Xml } catch { return [pscustomobject]$facts }

    $task = $doc.SelectSingleNode("/*[local-name()='Task']")
    if (-not $task) { return [pscustomobject]$facts }

    # The schema defaults, assigned before the document is read: what the
    # document says wins over them below.
    $facts.LogonType                  = 'InteractiveToken'
    $facts.RunLevel                   = 'LeastPrivilege'
    $facts.MultipleInstances          = 'IgnoreNew'
    $facts.DisallowStartIfOnBatteries = 'true'
    $facts.StopIfGoingOnBatteries     = 'true'
    $facts.StartWhenAvailable         = 'false'
    $facts.ExecutionTimeLimit         = 'PT72H'
    $facts.RestartCount               = '0'
    $facts.RestartInterval            = ''
    $facts.Enabled                    = 'true'

    $principal = $task.SelectSingleNode("*[local-name()='Principals']/*[local-name()='Principal']")
    if ($principal) {
        $facts.LogonType = Get-XmlNodeText -Node $principal -XPath "*[local-name()='LogonType']"
        $facts.RunLevel  = Get-XmlNodeText -Node $principal -XPath "*[local-name()='RunLevel']"
        $facts.UserId    = Get-XmlNodeText -Node $principal -XPath "*[local-name()='UserId']"
        if (-not $facts.LogonType) { $facts.LogonType = 'InteractiveToken' }
        if (-not $facts.RunLevel)  { $facts.RunLevel  = 'LeastPrivilege' }
    }

    # The triggers are a SET: a task with the same two triggers in a different
    # order is the same task. A DISABLED trigger is not in the set -- it never
    # fires, so declaring it says nothing about when the task runs.
    $triggers = @()
    foreach ($trigger in $task.SelectNodes("*[local-name()='Triggers']/*")) {
        $enabled = Get-XmlNodeText -Node $trigger -XPath "*[local-name()='Enabled']"
        if ($enabled -and $enabled -eq 'false') { continue }

        $userId = Get-XmlNodeText -Node $trigger -XPath "*[local-name()='UserId']"
        switch ($trigger.LocalName) {
            'LogonTrigger' { $triggers += "Logon:$userId" }
            'BootTrigger'  { $triggers += 'Boot' }
            'IdleTrigger'  { $triggers += 'Idle' }
            'TimeTrigger'  { $triggers += ('Time:' + (Get-XmlNodeText -Node $trigger -XPath "*[local-name()='StartBoundary']")) }
            default        { $triggers += $trigger.LocalName }
        }
    }
    $facts.Triggers = @($triggers | Sort-Object)

    $exec = $task.SelectSingleNode("*[local-name()='Actions']/*[local-name()='Exec']")
    if ($exec) {
        $facts.Command          = Get-XmlNodeText -Node $exec -XPath "*[local-name()='Command']"
        $facts.Arguments        = Get-XmlNodeText -Node $exec -XPath "*[local-name()='Arguments']"
        $facts.WorkingDirectory = Get-XmlNodeText -Node $exec -XPath "*[local-name()='WorkingDirectory']"
    }

    $settings = $task.SelectSingleNode("*[local-name()='Settings']")
    if ($settings) {
        $facts.MultipleInstances          = Get-XmlNodeText -Node $settings -XPath "*[local-name()='MultipleInstancesPolicy']"
        $facts.DisallowStartIfOnBatteries = Get-XmlNodeText -Node $settings -XPath "*[local-name()='DisallowStartIfOnBatteries']"
        $facts.StopIfGoingOnBatteries     = Get-XmlNodeText -Node $settings -XPath "*[local-name()='StopIfGoingOnBatteries']"
        $facts.StartWhenAvailable         = Get-XmlNodeText -Node $settings -XPath "*[local-name()='StartWhenAvailable']"
        $facts.ExecutionTimeLimit         = Get-XmlNodeText -Node $settings -XPath "*[local-name()='ExecutionTimeLimit']"
        $facts.Enabled                    = Get-XmlNodeText -Node $settings -XPath "*[local-name()='Enabled']"

        $restart = $settings.SelectSingleNode("*[local-name()='RestartOnFailure']")
        if ($restart) {
            $facts.RestartCount    = Get-XmlNodeText -Node $restart -XPath "*[local-name()='Count']"
            $facts.RestartInterval = Get-XmlNodeText -Node $restart -XPath "*[local-name()='Interval']"
            if (-not $facts.RestartCount) { $facts.RestartCount = '0' }
        }

        # Re-apply the defaults the document omitted, now that it has been
        # read: an empty element says nothing, it does not say "false".
        if (-not $facts.MultipleInstances)          { $facts.MultipleInstances          = 'IgnoreNew' }
        if (-not $facts.DisallowStartIfOnBatteries) { $facts.DisallowStartIfOnBatteries = 'true' }
        if (-not $facts.StopIfGoingOnBatteries)     { $facts.StopIfGoingOnBatteries     = 'true' }
        if (-not $facts.StartWhenAvailable)         { $facts.StartWhenAvailable         = 'false' }
        if (-not $facts.ExecutionTimeLimit)         { $facts.ExecutionTimeLimit         = 'PT72H' }
        if (-not $facts.Enabled)                    { $facts.Enabled                    = 'true' }
    }

    return [pscustomobject]$facts
}

# Get-AccountFact -- an account as far as it can be compared.
#
# The exporter writes a SID for the principal (S-1-5-21-...) and a name for a
# trigger (LAMET\oqyude); a declaration writes a name in both places. A SID
# and a name cannot be compared without asking Windows to translate one into
# the other, so a SID becomes the empty string: "this fact says nothing".
# Get-TaskDiff skips a dimension whose either side is empty (see below).
function Get-AccountFact {
    param([string]$Value)

    $text = ([string]$Value).Trim()
    if ($text -match '^S-\d-\d+(-\d+)+$') { return '' }
    return $text
}

# Get-TaskNameKey -- the task name with the punctuation removed.
#
#   OpenCodeServe  ==  OpenCode Serve  ==  opencode-serve
#
# Task Scheduler keeps a task's name verbatim; the hosts spell the same task
# in three ways, and every hole this module had came from trusting a literal
# name. The key is the comparison, the literal name is only presentation.
# A path is not part of the name: "\winos\OpenCodeServe" is the task
# "OpenCodeServe" in a folder.
function Get-TaskNameKey {
    param([string]$Name)

    if (-not $Name) { return '' }
    $leaf = @($Name -split '[\\/]' | Where-Object { $_ }) | Select-Object -Last 1
    if (-not $leaf) { return '' }
    return ([string]$leaf -replace '[^0-9A-Za-z]', '').ToLowerInvariant()
}

# Resolve-LiveTaskName -- which live task is this declaration about?
#
#   Name     the live name when exactly ONE live task has the declared key,
#            otherwise an empty string ("there is no such task here")
#   Matches  every live name with that key -- two of them means the machine
#            carries the same task twice, which is drift of its own
#
# An empty list is a declaration that was never registered; a list of two is
# a machine where somebody imported the task under a second spelling and
# both copies may be running. The caller decides, from Matches.
function Resolve-LiveTaskName {
    param(
        [Parameter(Mandatory)][string]$DeclaredName,
        [string[]]$LiveNames = @()
    )

    $key = Get-TaskNameKey -Name $DeclaredName
    $matches = @()
    if ($key) {
        $matches = @($LiveNames | Where-Object { $_ -and (Get-TaskNameKey -Name $_) -eq $key })
    }

    return [pscustomobject]@{
        DeclaredName = $DeclaredName
        Key          = $key
        Name         = $(if ($matches.Count -eq 1) { [string]$matches[0] } else { '' })
        Matches      = $matches
    }
}

# Get-UndeclaredTaskFindings -- live tasks that could be OURS without a
# declaration.
#
# The module never tidies a machine (a declaration is a promise about one
# task), but "never tidy" must not mean "never notice": a task that runs the
# same launcher under another name is the drift that made this module blind.
# A live task is reported when
#
#   * its name KEY extends a declared key -- OpenCodeServeOld, my-OpenCode-Serve
#   * its action runs the same file as a declaration -- the launcher by name
#
# and it is NOT reported when its key equals a declared key (that task is
# already being compared, under whatever spelling the host uses) or when it
# shares neither the name nor the target: OpenCodeCaptureScreen and friends
# are somebody else's business.
function Get-UndeclaredTaskFindings {
    param(
        $Declared = @(),
        $Live = @()
    )

    $declaredKeys = @()
    $declaredTargets = @()
    foreach ($entry in @($Declared)) {
        $key = Get-TaskNameKey -Name ([string]$entry.Name)
        if ($key) { $declaredKeys += $key }
        if ($entry.ActionTarget) {
            $declaredTargets += (Get-TargetLeaf -Path ([string]$entry.ActionTarget))
        }
    }

    $findings = @()
    foreach ($live in @($Live)) {
        if (-not $live -or -not $live.Name) { continue }
        $key = Get-TaskNameKey -Name ([string]$live.Name)
        if (-not $key) { continue }
        if ($declaredKeys -contains $key) { continue }

        $reason = ''
        foreach ($declaredKey in $declaredKeys) {
            # A short key ("oc") would match half the machine; a name that
            # merely CONTAINS a declared name is what we are after.
            if ($declaredKey.Length -ge 5 -and $key.Contains($declaredKey)) {
                $reason = "the name spells a declared task with something added ('$declaredKey')"
                break
            }
        }

        if (-not $reason) {
            $facts = Get-TaskFacts -Xml ([string]$live.Xml)
            $target = Get-TaskActionTarget -Facts $facts
            if ($target) {
                $leaf = Get-TargetLeaf -Path $target
                if ($leaf -and ($declaredTargets -contains $leaf)) {
                    $reason = "it runs the declared launcher ($leaf)"
                }
            }
        }

        if ($reason) {
            $findings += [pscustomobject]@{
                Name   = [string]$live.Name
                Key    = $key
                Reason = $reason
            }
        }
    }
    # The comma keeps an empty result an ARRAY: a bare empty list unrolls to
    # nothing, and the caller then reads $null as "one unnamed finding".
    return ,@($findings)
}

# Get-TargetLeaf -- the file name of a path in any spelling.
#
# The paths in a declaration are bash paths (/c/Users/...) and the paths in an
# export are Windows paths (C:\Users\...); [System.IO.Path]::GetFileName is
# platform-bound and returns the whole string here on Linux. This is the
# separator-agnostic version, used only for comparing two actions.
function Get-TargetLeaf {
    param([string]$Path)

    if (-not $Path) { return '' }
    $parts = @((($Path -replace '\\', '/') -split '/') | Where-Object { $_ })
    if ($parts.Count -eq 0) { return '' }
    return ([string]$parts[-1]).ToLowerInvariant()
}

# Get-TaskActionTarget -- the file the task runs, when it runs a file.
#
# A task that runs `bash -lc "<script>"` names the file it REALLY runs in the
# ARGUMENTS: the Command is only the interpreter (bash.exe), and it is the
# script whose absence proves the task would start and die. So the arguments
# are read first and the Command is the last resort.
#
# Returns an empty string when the action is a bare command name (nothing to
# check on disk) or when no path-shaped candidate is found.
function Get-TaskActionTarget {
    param($Facts)

    if (-not $Facts) { return '' }

    # Word by word first: a quoted `"bash <script>"` is one chunk and two
    # words, and the path is the word -- returning the chunk would give
    # "bash /c/Users/.../launcher.sh" as if that were a file name.
    $quoted = @([regex]::Matches([string]$Facts.Arguments, '"([^"]+)"') |
                ForEach-Object { $_.Groups[1].Value })

    $candidates = @()
    foreach ($chunk in $quoted) { $candidates += @($chunk -split '\s+') }
    foreach ($word in ([string]$Facts.Arguments -split '\s+')) { $candidates += $word.Trim('"', "'") }
    $candidates += $quoted
    if ($Facts.Command) { $candidates += [string]$Facts.Command }

    foreach ($candidate in $candidates) {
        $text = ([string]$candidate).Trim('"', "'")
        # A bare command name ("notepad.exe", "bash") is not a file on disk:
        # it is resolved through PATH, and there is nothing to check there.
        # Only a path-shaped candidate counts.
        if ($text -notmatch '\.(sh|cmd|bat|ps1|exe)$') { continue }
        if ($text -notmatch '[\\/]') { continue }
        return $text
    }
    return ''
}

# ConvertTo-BashPath -- a Windows path the way bash spells it.
#
#   C:\Users\oqyude  ->  /c/Users/oqyude
#
# The declared action is `bash -lc "bash <script>"`, so the script path that
# reaches bash must be in bash's own spelling; a declaration that used the
# Windows spelling would diff against every live task on every host.
function ConvertTo-BashPath {
    param([string]$Path)

    if (-not $Path) { return '' }
    $slash = $Path -replace '\\', '/'
    if ($slash -match '^([A-Za-z]):(.*)$') {
        return ('/' + $Matches[1].ToLowerInvariant() + $Matches[2])
    }
    return $slash
}

# ConvertFrom-BashPath -- the inverse, for checking that the file exists.
#
# Test-Path cannot open "/c/Users/oqyude/x.sh" on Windows: that is a path of
# the bash world.   /c/Users/oqyude/x.sh -> C:\Users\oqyude\x.sh
function ConvertFrom-BashPath {
    param([string]$Path)

    if (-not $Path) { return '' }
    if ($Path -match '^/([A-Za-z])/(.*)$') {
        return ($Matches[1].ToUpperInvariant() + ':\' + ($Matches[2] -replace '/', '\'))
    }
    return $Path
}

# Get-GitBashPath -- the bash.exe of Git for Windows.
#
# The task does NOT run the .cmd wrapper (which finds bash itself); it runs
# bash.exe directly, because it has to pass -lc. The lookup order is the one
# src/host-scripts/opencode-serve.cmd uses: the Git for Windows install in
# Program Files first, because on Windows "where bash" finds the WSL bash
# often enough, and the WSL bash cannot see the Windows filesystem the way
# the Git Bash does. The last resort is the standard location: a declaration
# still has to name a command on a machine where Git is not installed yet,
# and the diff will say the target is missing.
function Get-GitBashPath {
    param(
        [string]$ProgramFiles = '',
        [string]$ProgramFilesX86 = '',
        [string]$LocalAppData = ''
    )

    if (-not $ProgramFiles)    { $ProgramFiles    = $env:ProgramFiles }
    if (-not $ProgramFilesX86) { $ProgramFilesX86 = ${env:ProgramFiles(x86)} }
    if (-not $LocalAppData)    { $LocalAppData    = $env:LOCALAPPDATA }

    foreach ($base in @($ProgramFiles,
                        $ProgramFilesX86,
                        $(if ($LocalAppData) { $LocalAppData + '\Programs' } else { '' }))) {
        if (-not $base) { continue }
        $candidate = $base.TrimEnd('\', '/') + '\Git\bin\bash.exe'
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return 'C:\Program Files\Git\bin\bash.exe'
}

# Get-TaskDiff -- compare a declaration with the live task.
#
#   -Name         the task name that was COMPARED (the live spelling), for the
#                 report; the resolution from declaration to live name happens
#                 in Resolve-LiveTaskName and in the module
#   -DeclaredXml  the declaration, with the placeholders already resolved
#   -LiveXml      the exported task; empty when the task does not exist
#
# The result is a plain object so the tests can assert on it without a
# Windows host:
#
#   State         Matches | Differs | Missing
#   Differences   one entry per FIELD that differs (Kind/Declared/Actual)
#   Declared      the facts of the declaration
#   DeclaredXml   the declaration itself, with the placeholders resolved
#   Actual        the facts of the live task ($null when it is missing)
#
# DeclaredXml travels with the diff because the caller needs it to register
# the task again: the facts say WHAT is different, the XML says WHAT to
# register.
function Get-TaskDiff {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$DeclaredXml,
        [string]$LiveXml
    )

    $declared = Get-TaskFacts -Xml $DeclaredXml

    if (-not $LiveXml) {
        return [pscustomobject]@{
            Name        = $Name
            State       = 'Missing'
            Differences = @()
            Declared    = $declared
            DeclaredXml = $DeclaredXml
            Actual      = $null
        }
    }

    $actual = Get-TaskFacts -Xml $LiveXml
    $differences = @()

    # One entry per FIELD. The action is one dimension, not two: a different
    # Command and a different Arguments are the same difference ("it runs
    # something else"), and splitting them would report one problem twice.
    $dimensions = @(
        @{ Kind = 'UserId';                     Declared = (Get-AccountFact $declared.UserId);  Actual = (Get-AccountFact $actual.UserId); SkipWhenEmpty = $true }
        @{ Kind = 'LogonType';                  Declared = $declared.LogonType;                  Actual = $actual.LogonType }
        @{ Kind = 'RunLevel';                   Declared = $declared.RunLevel;                   Actual = $actual.RunLevel }
        @{ Kind = 'Triggers';                   Declared = (@($declared.Triggers) -join '|');    Actual = (@($actual.Triggers) -join '|') }
        @{ Kind = 'Action';                     Declared = "$($declared.Command) $($declared.Arguments)"; Actual = "$($actual.Command) $($actual.Arguments)" }
        @{ Kind = 'WorkingDirectory';           Declared = $declared.WorkingDirectory;           Actual = $actual.WorkingDirectory }
        @{ Kind = 'MultipleInstances';          Declared = $declared.MultipleInstances;          Actual = $actual.MultipleInstances }
        @{ Kind = 'DisallowStartIfOnBatteries'; Declared = $declared.DisallowStartIfOnBatteries; Actual = $actual.DisallowStartIfOnBatteries }
        @{ Kind = 'StopIfGoingOnBatteries';     Declared = $declared.StopIfGoingOnBatteries;     Actual = $actual.StopIfGoingOnBatteries }
        @{ Kind = 'ExecutionTimeLimit';         Declared = $declared.ExecutionTimeLimit;         Actual = $actual.ExecutionTimeLimit }
        @{ Kind = 'RestartOnFailure';           Declared = "$($declared.RestartCount)/$($declared.RestartInterval)"; Actual = "$($actual.RestartCount)/$($actual.RestartInterval)" }
        @{ Kind = 'StartWhenAvailable';         Declared = $declared.StartWhenAvailable;         Actual = $actual.StartWhenAvailable }
        @{ Kind = 'Enabled';                    Declared = $declared.Enabled;                    Actual = $actual.Enabled }
    )

    foreach ($dimension in $dimensions) {
        $left  = [string]$dimension.Declared
        $right = [string]$dimension.Actual

        # A dimension with nothing on one side says nothing (a SID against an
        # account name). Only the dimensions that marked themselves optional
        # are skipped; for the rest an empty side IS the difference.
        if ($dimension.SkipWhenEmpty -and ((-not $left) -or (-not $right))) { continue }

        if ($left -ne $right) {
            $differences += [pscustomobject]@{
                Kind     = $dimension.Kind
                Declared = $left
                Actual   = $right
            }
        }
    }

    return [pscustomobject]@{
        Name        = $Name
        State       = $(if ($differences.Count -eq 0) { 'Matches' } else { 'Differs' })
        Differences = $differences
        Declared    = $declared
        DeclaredXml = $DeclaredXml
        Actual      = $actual
    }
}

# Set-Task -- register the task from its declaration.
#
# -Force is what makes this an UPDATE rather than a create: the declared
# tasks are re-applied on purpose, and the ones that already match are not
# touched at all (the module skips them before calling this).
#
# The ShouldProcess call lives HERE, at the layer that actually changes
# something, so -WhatIf propagates through the module instead of being
# consumed on the way down.
function Set-Task {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Xml
    )

    if (-not $PSCmdlet.ShouldProcess($Name, 'Register scheduled task from the declaration')) {
        return $false
    }

    Register-ScheduledTask -TaskName $Name -Xml $Xml -Force | Out-Null
    return $true
}

# Get-SchedulerHostValues -- the per-host tokens a declaration may use.
#
# The values are passed in rather than read from a global scope, so the
# function is testable and the module stays the only place that knows what
# this host's paths are.
function Get-SchedulerHostValues {
    # The parameter is UserProfile and not Home: $HOME is a read-only
    # automatic variable, and a parameter with that name cannot be bound.
    param(
        [string]$DataRoot = '',
        [string]$ToolsDir = '',
        [string]$UserProfile = '',
        [string]$User = '',
        [string]$GitBash = ''
    )

    if (-not $GitBash) { $GitBash = Get-GitBashPath }

    return [ordered]@{
        '__DATA_ROOT__'   = $DataRoot
        '__TOOLS_DIR__'   = $ToolsDir
        '__HOME__'        = $UserProfile
        '__HOME_POSIX__'  = (ConvertTo-BashPath -Path $UserProfile)
        '__GIT_BASH__'    = $GitBash
        '__USER__'        = $User
    }
}

# Resolve-SchedulerPlaceholders -- substitute the tokens in a template.
#
# Longest token first: a template may carry a future __HOME_XXX__ next to
# __HOME__, and replacing the short one first would leave a fragment behind.
function Resolve-SchedulerPlaceholders {
    param(
        [string]$Text,
        $Values
    )

    if (-not $Text) { return $Text }
    if (-not $Values) { return $Text }

    $keys = @($Values.Keys | Sort-Object -Property Length -Descending)
    foreach ($key in $keys) {
        $Text = $Text.Replace([string]$key, [string]$Values[$key])
    }
    return $Text
}

# Get-SchedulerTaskDeclarations -- the declared tasks, with the placeholders
# resolved.
#
# The task NAME is the file name: Task Scheduler addresses a task by the name
# of the file it was imported from, so the declaration and the file have to
# agree. The URI inside the XML is a separate thing and is left as declared.
#
# The base name is a DECLARATION ID, not necessarily the spelling the host
# uses: OpenCodeServe.xml describes the task called "OpenCode Serve" on one
# host and "opencode-serve" on the other, and Resolve-LiveTaskName matches
# them by key. One file, one truth, any spelling.
function Get-SchedulerTaskDeclarations {
    param(
        [string]$TemplateDir,
        $Values
    )

    $declarations = @()
    if (-not $TemplateDir -or -not (Test-Path -LiteralPath $TemplateDir)) { return $declarations }

    foreach ($file in (Get-ChildItem -LiteralPath $TemplateDir -Filter '*.xml' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $raw = Get-Content -Raw -LiteralPath $file.FullName
        $xml = Resolve-SchedulerPlaceholders -Text $raw -Values $Values
        $declarations += [pscustomobject]@{
            Name         = $file.BaseName
            Path         = $file.FullName
            Raw          = $raw
            Xml          = $xml
            ActionTarget = (Get-TaskActionTarget -Facts (Get-TaskFacts -Xml $xml))
        }
    }
    return $declarations
}
