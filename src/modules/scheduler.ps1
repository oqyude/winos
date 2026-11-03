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
      watchdog. They are none of the module's business: it never enumerates
      tasks to clean them up, and it never unregisters a task it did not
      declare. A declaration is a promise about one task, not a licence to
      tidy the machine.
    * THE COMPARISON IS SEMANTIC, NOT TEXTUAL. Task Scheduler writes a URI,
      an Author and a Date into every task it exports; a hand-written
      declaration does not have them. Comparing the documents byte for byte
      would report a difference on every field that does not matter. The
      comparison covers what carries the meaning: who runs the task, when it
      runs, what it runs, where it runs from, and the settings that are worth
      pinning. See src/modules/scheduler/State.ps1.
    * A TASK THAT ALREADY MATCHES IS NOT TOUCHED. Apply registers the ones
      that differ and leaves the rest alone.

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

function Get-LiveTaskXml {
    # The exported XML of the live task, or an empty string when there is no
    # such task (or no Task Scheduler on this host at all).
    param([string]$Name)

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

function Get-SchedulerDiffReport {
    # One diff per declared task. The live task is fetched here, so the
    # Windows-only call stays in one place.
    param($Declarations)

    $report = @()
    foreach ($declaration in $Declarations) {
        $live = Get-LiveTaskXml -Name $declaration.Name
        $diff = Get-TaskDiff -Name $declaration.Name -DeclaredXml $declaration.Xml -LiveXml $live
        $report += [pscustomobject]@{
            Name       = $declaration.Name
            Diff       = $diff
            ActionPath = (Get-TaskActionTarget -Facts $diff.Declared)
        }
    }
    return $report
}

function Write-SchedulerDiff {
    # Print one diff in the shape the rest of the tool uses: what the
    # declaration says, what the machine has, and whether that is a problem.
    param($Entry)

    $diff = $Entry.Diff
    switch ($diff.State) {
        'Matches' {
            Write-Host ("  [ OK ] {0} - matches the declaration" -f $diff.Name) -ForegroundColor Green
        }
        'Missing' {
            Write-Host ("  [MISS] {0} - not registered on this machine" -f $diff.Name) -ForegroundColor Yellow
        }
        default {
            Write-Host ("  [DIFF] {0}" -f $diff.Name) -ForegroundColor Yellow
            foreach ($difference in $diff.Differences) {
                Write-Host ("         {0}: declared '{1}' / actual '{2}'" -f $difference.Kind, $difference.Declared, $difference.Actual) -ForegroundColor DarkGray
            }
        }
    }
    if ($Entry.ActionPath -and -not (Test-Path -LiteralPath $Entry.ActionPath)) {
        Write-Host ("         the action target does not exist: {0}" -f $Entry.ActionPath) -ForegroundColor Yellow
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
        foreach ($entry in $report) {
            Write-SchedulerDiff -Entry $entry
        }

        $drift = @($report | Where-Object { $_.Diff.State -ne 'Matches' })
        Write-Host ""
        if ($drift.Count -eq 0) {
            Write-Host ("    {0} declared task(s), all match" -f $report.Count) -ForegroundColor Green
        } else {
            Write-Host ("    {0} of {1} declared task(s) differ" -f $drift.Count, $report.Count) -ForegroundColor Yellow
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
        foreach ($entry in $report) {
            if ($entry.Diff.State -eq 'Matches') {
                Write-Host ("  [ OK ] {0} - matches the declaration, left alone" -f $entry.Diff.Name) -ForegroundColor Green
                continue
            }
            # A task that runs a file that is not there would start and die.
            # Registering it would be worse than not registering it.
            if ($entry.ActionPath -and -not (Test-Path -LiteralPath $entry.ActionPath)) {
                Write-Host ("  [SKIP] {0} - the action target does not exist: {1}" -f $entry.Diff.Name, $entry.ActionPath) -ForegroundColor Yellow
                continue
            }
            if (Set-Task -Name $entry.Diff.Name -Xml $entry.Diff.DeclaredXml) {
                Write-Host ("  [DONE] {0} - registered from the declaration" -f $entry.Diff.Name) -ForegroundColor Green
            }
        }
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

        $missing = 0
        foreach ($declaration in $declarations) {
            $live = Get-LiveTaskXml -Name $declaration.Name
            if (-not $live) {
                $missing++
                Write-Host ("  {0}: NOT REGISTERED" -f $declaration.Name) -ForegroundColor Red
                continue
            }
            $facts = Get-TaskFacts -Xml $live
            Write-Host ("  {0}:" -f $declaration.Name) -ForegroundColor Cyan
            Write-Host ("    logon:   {0} ({1}, user {2})" -f $facts.LogonType, $facts.RunLevel, $facts.UserId)
            Write-Host ("    trigger: {0}" -f (@($facts.Triggers) -join ', '))
            Write-Host ("    action:  {0} {1}" -f $facts.Command, $facts.Arguments)
            Write-Host ("    folder:  {0}" -f $facts.WorkingDirectory)
        }
        Write-Host ""

        if ($missing -gt 0) {
            Write-Host ("    {0} declared task(s) are not registered" -f $missing) -ForegroundColor Yellow
            exit 1
        }
    }

    default {
        Write-Host "Usage: scheduler.ps1 -action <plan|apply|status>" -ForegroundColor Yellow
    }
}
