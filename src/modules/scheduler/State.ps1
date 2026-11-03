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
#   * who runs it   -- LogonType, RunLevel, UserId
#   * when it runs -- the set of triggers
#   * what it runs  -- Command, Arguments, WorkingDirectory
#   * how it behaves-- the settings that are worth pinning
#
# Everything else in the document is ignored on purpose.

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
# caller never has to special-case a missing task.
function Get-TaskFacts {
    param([string]$Xml)

    $facts = [ordered]@{
        LogonType          = ''
        RunLevel           = ''
        UserId             = ''
        Triggers           = @()
        Command            = ''
        Arguments          = ''
        WorkingDirectory   = ''
        MultipleInstances  = ''
        RestartCount       = ''
        ExecutionTimeLimit = ''
        Enabled            = ''
    }

    if (-not $Xml) { return [pscustomobject]$facts }

    $doc = $null
    try { $doc = [xml]$Xml } catch { return [pscustomobject]$facts }

    $task = $doc.SelectSingleNode("/*[local-name()='Task']")
    if (-not $task) { return [pscustomobject]$facts }

    $principal = $task.SelectSingleNode("*[local-name()='Principals']/*[local-name()='Principal']")
    if ($principal) {
        $facts.LogonType = Get-XmlNodeText -Node $principal -XPath "*[local-name()='LogonType']"
        $facts.RunLevel  = Get-XmlNodeText -Node $principal -XPath "*[local-name()='RunLevel']"
        $facts.UserId    = Get-XmlNodeText -Node $principal -XPath "*[local-name()='UserId']"
    }

    # The triggers are a SET: a task with the same two triggers in a different
    # order is the same task.
    $triggers = @()
    foreach ($trigger in $task.SelectNodes("*[local-name()='Triggers']/*")) {
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
        $facts.MultipleInstances  = Get-XmlNodeText -Node $settings -XPath "*[local-name()='MultipleInstancesPolicy']"
        $facts.RestartCount       = Get-XmlNodeText -Node $settings -XPath "*[local-name()='RestartOnFailure']/*[local-name()='Count']"
        $facts.ExecutionTimeLimit = Get-XmlNodeText -Node $settings -XPath "*[local-name()='ExecutionTimeLimit']"
        $facts.Enabled            = Get-XmlNodeText -Node $settings -XPath "*[local-name()='Enabled']"
    }

    return [pscustomobject]$facts
}

# Get-TaskActionTarget -- the file the task runs, when it runs a file.
#
# A task that runs `bash "<script>"` names its target in the ARGUMENTS, not
# in the Command. Returns an empty string when the action is a bare command
# name (nothing to check on disk) or when no path-shaped argument is found.
function Get-TaskActionTarget {
    param($Facts)

    if (-not $Facts) { return '' }

    $candidates = @()
    if ($Facts.Command) { $candidates += [string]$Facts.Command }
    foreach ($match in [regex]::Matches([string]$Facts.Arguments, '"([^"]+)"')) {
        $candidates += $match.Groups[1].Value
    }
    foreach ($candidate in $candidates) {
        # A bare command name ("notepad.exe", "bash") is not a file on disk:
        # it is resolved through PATH, and there is nothing to check there.
        # Only a path-shaped candidate counts.
        if ($candidate -notmatch '\.(sh|cmd|bat|ps1|exe)$') { continue }
        if ($candidate -notmatch '[\\/]') { continue }
        return $candidate
    }
    return ''
}

# Get-TaskDiff -- compare a declaration with the live task.
#
#   -DeclaredXml  the declaration, with the placeholders already resolved
#   -LiveXml      the exported task; empty when the task does not exist
#
# The result is a plain object so the tests can assert on it without a
# Windows host:
#
#   State         Matches | Differs | Missing
#   Differences   one entry per dimension that differs
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

    # The action is one dimension, not two: a different Command and a
    # different Arguments are the same difference ("it runs something else").
    $declaredAction = "$($declared.Command) $($declared.Arguments)"
    $actualAction   = "$($actual.Command) $($actual.Arguments)"

    $dimensions = @(
        @{ Kind = 'LogonType';        Declared = $declared.LogonType;        Actual = $actual.LogonType }
        @{ Kind = 'RunLevel';         Declared = $declared.RunLevel;         Actual = $actual.RunLevel }
        @{ Kind = 'UserId';           Declared = $declared.UserId;           Actual = $actual.UserId }
        @{ Kind = 'Triggers';         Declared = (@($declared.Triggers) -join '|'); Actual = (@($actual.Triggers) -join '|') }
        @{ Kind = 'Action';           Declared = $declaredAction;            Actual = $actualAction }
        @{ Kind = 'WorkingDirectory'; Declared = $declared.WorkingDirectory; Actual = $actual.WorkingDirectory }
        @{ Kind = 'Settings';         Declared = "$($declared.MultipleInstances)/$($declared.RestartCount)/$($declared.ExecutionTimeLimit)/$($declared.Enabled)"; Actual = "$($actual.MultipleInstances)/$($actual.RestartCount)/$($actual.ExecutionTimeLimit)/$($actual.Enabled)" }
    )

    foreach ($dimension in $dimensions) {
        if ([string]$dimension.Declared -ne [string]$dimension.Actual) {
            $differences += [pscustomobject]@{
                Kind     = $dimension.Kind
                Declared = [string]$dimension.Declared
                Actual   = [string]$dimension.Actual
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
        [string]$User = ''
    )

    return [ordered]@{
        '__DATA_ROOT__' = $DataRoot
        '__TOOLS_DIR__'  = $ToolsDir
        '__HOME__'      = $UserProfile
        '__USER__'      = $User
    }
}

# Resolve-SchedulerPlaceholders -- substitute the tokens in a template.
function Resolve-SchedulerPlaceholders {
    param(
        [string]$Text,
        $Values
    )

    if (-not $Text) { return $Text }
    if (-not $Values) { return $Text }

    foreach ($key in $Values.Keys) {
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
function Get-SchedulerTaskDeclarations {
    param(
        [string]$TemplateDir,
        $Values
    )

    $declarations = @()
    if (-not $TemplateDir -or -not (Test-Path -LiteralPath $TemplateDir)) { return $declarations }

    foreach ($file in (Get-ChildItem -LiteralPath $TemplateDir -Filter '*.xml' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $raw = Get-Content -Raw -LiteralPath $file.FullName
        $declarations += [pscustomobject]@{
            Name = $file.BaseName
            Path = $file.FullName
            Raw  = $raw
            Xml  = (Resolve-SchedulerPlaceholders -Text $raw -Values $Values)
        }
    }
    return $declarations
}
