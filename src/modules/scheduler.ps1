<#
.SYNOPSIS
    Declared Windows scheduled tasks, compared with the live ones and applied.

.DESCRIPTION
    A scheduled task is a piece of configuration, and configuration belongs in
    the repository. This module holds the DECLARATION of every task winos is
    responsible for (an XML template per task) and answers three questions
    about it:

      plan    how do the live tasks differ from the declarations?
      apply   bring the declared tasks in line with the declarations
      status  what is the state of the declared tasks?

    The rules the module follows:

    * IT TOUCHES ONLY THE DECLARED TASKS. A machine may carry tasks winos
      knows nothing about -- a screen-capture helper, a browser launcher, a
      watchdog. They are none of the module's business: it never unregisters
      a task it did not declare. A declaration is a promise about one task,
      not a licence to tidy the machine.
    * BUT IT DOES LOOK FOR THEM UNDER ANOTHER NAME. "Never tidy" is not
      "never notice": a live task that runs the same launcher, or whose name
      merely extends a declared one, is reported as UNDECLARED by plan and
      status. Before 2026-11-04 the module looked for the literal file name
      only -- the declaration said OpenCodeServe, the hosts said
      "OpenCode Serve" and "opencode-serve", so the drift was invisible by
      construction and the server was dead while the report said "missing".
    * THE COMPARISON IS SEMANTIC, NOT TEXTUAL, AND PER FIELD. Task Scheduler
      writes a URI, an Author and a Date into every task it exports; a
      hand-written declaration does not have them. The comparison covers what
      carries the meaning -- who runs the task, when it runs (including the
      battery flags, the execution time limit and the restart budget), what
      it runs and where -- and each of those is its own dimension, named in
      the report. See src/modules/scheduler/State.ps1.
    * THE NAME IS MATCHED BY KEY, NOT BY SPELLING. OpenCodeServe.xml,
      "OpenCode Serve" and "opencode-serve" are one task: the key is the name
      without case, spaces, dashes and underscores. A declaration is one file
      with one name, and the spelling a host uses is the host's business.
    * A TASK THAT ALREADY MATCHES IS NOT TOUCHED. Apply registers the ones
      that differ and leaves the rest alone -- under the name the host
      already uses, so it updates that task instead of creating a second one.

.EXAMPLE
    pwsh -File src/modules/scheduler.ps1 -action plan

.EXAMPLE
    pwsh -File src/modules/scheduler.ps1 -action apply -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("plan", "apply", "status")]
    [string]$action
)

# Self-bootstrap: if vars.ps1 hasn't been sourced (run directly), source it.
if (-not $Storage) {
    . (Join-Path $PSScriptRoot "..\init.ps1")
}

# The pure half: the diff, the placeholder resolution, the registration.
. (Join-Path $PSScriptRoot "scheduler\State.ps1")

$taskTemplateDir = Join-Path $PSScriptRoot "scheduler\tasks"

function Get-SchedulerHostTokenValues {
    # The per-host tokens, resolved once. The data root and the tools
    # directory come from the host declaration (src/host-paths.ps1), the rest
    # from the environment.
    $user = if ($env:COMPUTERNAME) { "$env:COMPUTERNAME\$env:USERNAME" } else { $env:USERNAME }
    return (Get-SchedulerHostValues -DataRoot $data -ToolsDir $toolsDir -UserProfile $env:USERPROFILE -User $user)
}

function Get-LiveTaskNames {
    # Every task in the ROOT folder, by name. Empty when this host has no
    # Task Scheduler at all (Linux, a container, CI): the module then reports
    # every declaration as missing, which is the truth there.
    #
    # Reading the list is what makes the name mismatch visible: asking for one
    # literal name can only answer "yes" or "no", and "no" was the blind spot.
    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) { return @() }

    try {
        $tasks = Get-ScheduledTask -TaskPath '\' -ErrorAction Stop
    } catch {
        return @()
    }

    return @(@($tasks) | ForEach-Object { [string]$_.TaskName } | Where-Object { $_ } | Sort-Object)
}

function Get-LiveTaskXml {
    # The exported XML of the live task, or an empty string when there is no
    # such task (or no Task Scheduler on this host at all).
    param([string]$Name)

    if (-not $Name) { return '' }
    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) { return '' }
    if (-not (Get-Command Export-ScheduledTask -ErrorAction SilentlyContinue)) { return '' }

    $task = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
    if (-not $task) { return '' }

    try {
        return [string](Export-ScheduledTask -TaskName $Name -ErrorAction Stop)
    } catch {
        return ''
    }
}

function Test-SchedulerActionTarget {
    # Is the file the task runs on disk?
    #
    # Two spellings have to be tried: the declaration names the script the way
    # bash needs it (/c/Users/...), and Test-Path only understands the Windows
    # spelling (C:\Users\...). Checking the wrong one would make apply skip a
    # healthy task and say the launcher does not exist.
    param([string]$Path)

    if (-not $Path) { return $true }
    if (Test-Path -LiteralPath $Path) { return $true }

    $windows = ConvertFrom-BashPath -Path $Path
    if ($windows -and $windows -ne $Path -and (Test-Path -LiteralPath $windows)) { return $true }
    return $false
}

function Get-SchedulerDiffReport {
    # One diff per declared task, plus the live tasks that carry no
    # declaration. The live task is fetched here, so the Windows-only call
    # stays in one place.
    param($Declarations)

    $liveNames = Get-LiveTaskNames

    $entries = @()
    foreach ($declaration in $Declarations) {
        $resolution = Resolve-LiveTaskName -DeclaredName $declaration.Name -LiveNames $liveNames
        $taskName = if ($resolution.Name) { $resolution.Name } else { $declaration.Name }

        if (@($resolution.Matches).Count -gt 1) {
            # Two tasks with the same key: two servers, one port. Neither can
            # be picked without guessing, so the report says so and apply
            # leaves the machine alone.
            $diff = [pscustomobject]@{
                Name        = $declaration.Name
                State       = 'Duplicate'
                Differences = @([pscustomobject]@{
                    Kind     = 'TaskName'
                    Declared = $declaration.Name
                    Actual   = (@($resolution.Matches) -join ', ')
                })
                Declared    = (Get-TaskFacts -Xml $declaration.Xml)
                DeclaredXml = $declaration.Xml
                Actual      = $null
            }
        } else {
            $live = Get-LiveTaskXml -Name $taskName
            $diff = Get-TaskDiff -Name $taskName -DeclaredXml $declaration.Xml -LiveXml $live
        }

        $entries += [pscustomobject]@{
            Declaration = $declaration.Name
            TaskName    = $taskName
            Resolution  = $resolution
            Diff        = $diff
            ActionPath  = $declaration.ActionTarget
        }
    }

    # Which live tasks are none of the declarations' business? Only the ones
    # that are NOT covered by a declaration key need their XML read -- the
    # rest are already being compared.
    $declaredKeys = @($Declarations | ForEach-Object { Get-TaskNameKey -Name $_.Name })
    $orphans = @()
    foreach ($name in $liveNames) {
        if ($declaredKeys -contains (Get-TaskNameKey -Name $name)) { continue }
        $orphans += [pscustomobject]@{ Name = $name; Xml = (Get-LiveTaskXml -Name $name) }
    }
    $undeclared = Get-UndeclaredTaskFindings -Declared $Declarations -Live $orphans

    return [pscustomobject]@{
        Entries    = $entries
        Undeclared = $undeclared
        LiveNames  = $liveNames
    }
}

function Write-SchedulerDiff {
    # Print one diff in the shape the rest of the tool uses: what the
    # declaration says, what the machine has, and whether that is a problem.
    param($Entry)

    $diff = $Entry.Diff
    switch ($diff.State) {
        'Matches' {
            Write-Host ("  [ OK ] {0} - matches the declaration" -f $diff.Name) -ForegroundColor Green
            if ($Entry.TaskName -ne $Entry.Declaration) {
                Write-Host ("         the live task is called '{0}', the declaration is {1}.xml" -f $Entry.TaskName, $Entry.Declaration) -ForegroundColor DarkGray
            }
        }
        'Missing' {
            Write-Host ("  [MISS] {0} - not registered on this machine" -f $Entry.Declaration) -ForegroundColor Yellow
            Write-Host ("         looked for '{0}' (any spelling: case, spaces, - and _ do not count)" -f $Entry.Declaration) -ForegroundColor DarkGray
        }
        'Duplicate' {
            Write-Host ("  [DUPL] {0} - the machine carries this task more than once: {1}" -f $Entry.Declaration, (@($diff.Differences)[0].Actual)) -ForegroundColor Red
            Write-Host ("         two copies mean two servers on one port; resolve by hand" ) -ForegroundColor DarkGray
        }
        default {
            Write-Host ("  [DIFF] {0}" -f $diff.Name) -ForegroundColor Yellow
            foreach ($difference in $diff.Differences) {
                Write-Host ("         {0}: declared '{1}' / actual '{2}'" -f $difference.Kind, $difference.Declared, $difference.Actual) -ForegroundColor DarkGray
            }
        }
    }
    if ($Entry.ActionPath -and -not (Test-SchedulerActionTarget -Path $Entry.ActionPath)) {
        Write-Host ("         the action target does not exist: {0}" -f $Entry.ActionPath) -ForegroundColor Yellow
    }
}

function Write-SchedulerUndeclared {
    # A live task that could be one of ours and is not declared.
    param($Findings)

    foreach ($finding in @($Findings) | Where-Object { $_ }) {
        Write-Host ("  [UNDECLARED] {0} - {1}" -f $finding.Name, $finding.Reason) -ForegroundColor Red
        Write-Host ("               declare it in src/modules/scheduler/tasks/, or remove it by hand") -ForegroundColor DarkGray
    }
}

switch ($action) {

    "plan" {
        $values = Get-SchedulerHostTokenValues
        $declarations = Get-SchedulerTaskDeclarations -TemplateDir $taskTemplateDir -Values $values
        if (-not $declarations) {
            Write-Host ("No task declarations in {0}" -f $taskTemplateDir) -ForegroundColor Yellow
            return
        }

        Write-Host ""
        Write-Host ("  winos :: scheduler plan") -ForegroundColor Cyan
        Write-Host ("  " + ("-" * 32))
        Write-Host ""

        $report = Get-SchedulerDiffReport -Declarations $declarations
        foreach ($entry in $report.Entries) {
            Write-SchedulerDiff -Entry $entry
        }
        Write-SchedulerUndeclared -Findings $report.Undeclared

        $drift = @($report.Entries | Where-Object { $_.Diff.State -ne 'Matches' })
        $undeclaredCount = @($report.Undeclared).Count
        Write-Host ""
        if ($drift.Count -eq 0 -and $undeclaredCount -eq 0) {
            Write-Host ("    {0} declared task(s), all match" -f @($report.Entries).Count) -ForegroundColor Green
        } else {
            Write-Host ("    {0} of {1} declared task(s) differ, {2} live task(s) carry no declaration" -f $drift.Count, @($report.Entries).Count, $undeclaredCount) -ForegroundColor Yellow
        }
        Write-Host ""
    }

    "apply" {
        $values = Get-SchedulerHostTokenValues
        $declarations = Get-SchedulerTaskDeclarations -TemplateDir $taskTemplateDir -Values $values
        if (-not $declarations) {
            Write-Host ("No task declarations in {0}" -f $taskTemplateDir) -ForegroundColor Yellow
            return
        }

        Write-Host ""
        Write-Host ("  winos :: scheduler apply") -ForegroundColor Cyan
        Write-Host ("  " + ("-" * 32))
        Write-Host ""

        $report = Get-SchedulerDiffReport -Declarations $declarations
        foreach ($entry in $report.Entries) {
            if ($entry.Diff.State -eq 'Matches') {
                Write-Host ("  [ OK ] {0} - matches the declaration, left alone" -f $entry.Diff.Name) -ForegroundColor Green
                continue
            }
            if ($entry.Diff.State -eq 'Duplicate') {
                Write-Host ("  [SKIP] {0} - registered more than once on this machine, resolve by hand" -f $entry.Declaration) -ForegroundColor Red
                continue
            }
            # A task that runs a file that is not there would start and die.
            # Registering it would be worse than not registering it.
            if (-not (Test-SchedulerActionTarget -Path $entry.ActionPath)) {
                Write-Host ("  [SKIP] {0} - the action target does not exist: {1}" -f $entry.Diff.Name, $entry.ActionPath) -ForegroundColor Yellow
                continue
            }
            # Register under the name the host already uses: the same task
            # under a second spelling would be two tasks, one port.
            if (Set-Task -Name $entry.TaskName -Xml $entry.Diff.DeclaredXml) {
                Write-Host ("  [DONE] {0} - registered from the declaration" -f $entry.TaskName) -ForegroundColor Green
            }
        }
        Write-SchedulerUndeclared -Findings $report.Undeclared
        Write-Host ""
    }

    "status" {
        $values = Get-SchedulerHostTokenValues
        $declarations = Get-SchedulerTaskDeclarations -TemplateDir $taskTemplateDir -Values $values
        if (-not $declarations) {
            Write-Host ("No task declarations in {0}" -f $taskTemplateDir) -ForegroundColor Yellow
            return
        }

        Write-Host ""
        Write-Host ("  winos :: scheduler status") -ForegroundColor Cyan
        Write-Host ("  " + ("-" * 32))
        Write-Host ""

        $report = Get-SchedulerDiffReport -Declarations $declarations
        $problems = 0
        foreach ($entry in $report.Entries) {
            $diff = $entry.Diff
            if ($diff.State -eq 'Missing') {
                $problems++
                Write-Host ("  {0}: NOT REGISTERED" -f $entry.Declaration) -ForegroundColor Red
                continue
            }
            if ($diff.State -eq 'Duplicate') {
                $problems++
                Write-Host ("  {0}: REGISTERED MORE THAN ONCE ({1})" -f $entry.Declaration, (@($diff.Differences)[0].Actual)) -ForegroundColor Red
                continue
            }

            $facts = $diff.Actual
            Write-Host ("  {0}:" -f $entry.TaskName) -ForegroundColor Cyan
            Write-Host ("    logon:   {0} ({1}, user {2})" -f $facts.LogonType, $facts.RunLevel, $facts.UserId)
            Write-Host ("    trigger: {0}" -f (@($facts.Triggers) -join ', '))
            Write-Host ("    action:  {0} {1}" -f $facts.Command, $facts.Arguments)
            Write-Host ("    folder:  {0}" -f $facts.WorkingDirectory)
            Write-Host ("    limits:  batteries start/stop = {0}/{1}, time limit = {2}, restart = {3} every {4}, start-when-available = {5}" -f `
                $facts.DisallowStartIfOnBatteries, $facts.StopIfGoingOnBatteries, $facts.ExecutionTimeLimit, `
                $facts.RestartCount, $(if ($facts.RestartInterval) { $facts.RestartInterval } else { '-' }), $facts.StartWhenAvailable)
            if ($diff.State -ne 'Matches') {
                $problems++
                Write-Host ("    differs from the declaration in: {0} (run plan)" -f ((@($diff.Differences | ForEach-Object { $_.Kind })) -join ', ')) -ForegroundColor Yellow
            }
        }

        Write-SchedulerUndeclared -Findings $report.Undeclared
        $problems += @($report.Undeclared).Count
        Write-Host ""

        if ($problems -gt 0) {
            Write-Host ("    {0} problem(s)" -f $problems) -ForegroundColor Yellow
            exit 1
        }
    }

    default {
        Write-Host "Usage: scheduler.ps1 -action <plan|apply|status>" -ForegroundColor Yellow
    }
}
