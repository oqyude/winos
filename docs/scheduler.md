# scheduler

Windows Scheduled Tasks are **declared**, not created by hand.

Two machines drifted apart: one runs `OpenCode Serve` (Interactive, AtLogon,
a launcher from `<data root>/tools/host-scripts`), the other runs `opencode-serve`
(S4U, Boot+Logon, a script from `~/.local/bin`). Both were made by hand, so
neither matched the repository. This module makes the declaration the source of
truth: the task lives in the repository as an XML template, the module compares
it with the machine and reports the difference, and `apply` brings the machine
in line.

## Module

- **Register key:** `Scheduled Tasks`
- **Alias:** `scheduler`
- **Path:** `src/modules/scheduler.ps1`
- **Actions:** `plan`, `apply`, `status`
- **Destructive:** none

Winos entry points:

```
winos scheduler plan
winos scheduler apply
winos scheduler status
main.ps1                                # interactive menu -> Scheduled Tasks
```

## What the module does NOT do

**It touches only the declared tasks.** A machine may carry tasks winos knows
nothing about (`OpenCodeCaptureScreen`, `OpenCodeLaunchBrave`,
`OpenCodeAdvegoWatch` and whatever else a person added for themselves). The
module never enumerates tasks to clean them up and never unregisters a task it
did not declare. A declaration is a promise about one task, not a licence to
tidy the machine. The extra tasks stay exactly where they are; removing them is
the owner's decision, made by hand.

**It does not overwrite a task that already matches.** `apply` registers the
tasks that differ and leaves the rest alone.

**It does not register a task whose action target is missing.** A task that
starts and dies immediately is worse than no task at all: the machine looks
configured and is not. `apply` reports the missing target and skips that task.

## Verbs

| Verb | Effect |
|---|---|
| `plan` | Compares every declaration with the live task and prints the difference. Read-only. |
| `apply` | Registers the declared tasks that differ. Honours `-WhatIf`. |
| `status` | Prints the live state of the declared tasks. Exits 1 if a declared task is not registered. |

All three honour `-WhatIf` (`apply` registers nothing under it).

## How a task is declared

A declaration is one XML file in `src/modules/scheduler/tasks/`. **The file name
is the task name** - Task Scheduler addresses a task by the name of the file it
was imported from, so the two have to agree.

```xml
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>__USER__</UserId>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>__USER__</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>Limited</RunLevel>
    </Principal>
  </Principals>
  <Actions Context="Author">
    <Exec>
      <Command>bash</Command>
      <Arguments>"__DATA_ROOT__\tools\host-scripts\opencode-serve.sh"</Arguments>
      <WorkingDirectory>__DATA_ROOT__</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
```

To add a task: drop a new `<TaskName>.xml` into that directory. Nothing else
has to change - the module picks the file up, and the diff starts reporting it
as missing on a machine that does not have it yet.

### Placeholders

Absolute paths rot, so a declaration never hardcodes one. The placeholders are
resolved per host, from the host declaration
(`<data dir>/hosts/<COMPUTERNAME>.json`, read by `src/host-paths.ps1`):

| Placeholder | Value |
|---|---|
| `__DATA_ROOT__` | the winos data root (the synced store when it exists, the repository's `data/` otherwise) |
| `__TOOLS_DIR__` | the host's tools directory |
| `__HOME__` | the user's profile directory |
| `__USER__` | the account, in Task Scheduler's `DOMAIN\user` form |

### The fields that carry the meaning

The diff compares these and nothing else:

| Dimension | Where it comes from |
|---|---|
| `LogonType` | `Principal/LogonType` - `InteractiveToken`, `S4U`, `Password` |
| `RunLevel` | `Principal/RunLevel` - `LeastPrivilege` or `HighestAvailable` |
| `UserId` | `Principal/UserId` |
| `Triggers` | the set of triggers, as a set: `Logon:<user>`, `Boot`, `Idle`, `Time:<start>` |
| `Action` | `Exec/Command` + `Exec/Arguments` |
| `WorkingDirectory` | `Exec/WorkingDirectory` |
| `Settings` | `MultipleInstancesPolicy`, `RestartOnFailure/Count`, `ExecutionTimeLimit`, `Enabled` |

Everything else in the document is ignored on purpose. Task Scheduler writes a
`URI`, an `Author` and a `Date` into every task it exports; a hand-written
declaration has none of them. Comparing the documents byte for byte would
report a difference on every field that does not matter and bury the one that
does. Two tasks that mean the same thing compare equal even when their XML is
nothing alike.

## The declared tasks today

| Task | Logon | Trigger | Action | Working folder |
|---|---|---|---|---|
| `OpenCodeServe` | `InteractiveToken` (Limited) | at logon | `bash "<data root>\tools\host-scripts\opencode-serve.sh"` | `<data root>` |

The launcher script under `<data root>/tools/host-scripts/` is a separate
deliverable. Until it is on disk, `plan` says so and `apply` skips the task
rather than registering one that cannot start.

**The logon type is the field that drifted.** `InteractiveToken` is the safe
choice for a server that has to reach the network: an S4U task runs without
stored credentials and may be denied network access. Moving to the other mode
is one line in the XML.

## The older, imperative way

`src/modules/opencode-serve.ps1` and `src/modules/herdr-serve.ps1` register
their own tasks with `Register-ScheduledTask` at setup time. They still work,
and they are still the only way to get a task onto a machine that has never
run the scheduler module. The scheduler module is the declarative path; when
both are used for the same task, the declaration wins and the imperative
module is the thing to retire.

## Files

| File | Purpose |
|---|---|
| `src/modules/scheduler.ps1` | the module: `plan`, `apply`, `status` |
| `src/modules/scheduler/State.ps1` | the pure half: the diff, the placeholder resolution, `Set-Task` |
| `src/modules/scheduler/tasks/*.xml` | the declarations, one file per task |
| `tests/modules/scheduler.Tests.ps1` | the diff tests - they run on any host, no Windows needed |

The diff is tested on XML strings, so the tests do not need a Windows host and
do not touch a real Task Scheduler. `apply` is tested with the scheduler
cmdlets replaced by test doubles, and the test asserts that
`Unregister-ScheduledTask` is never called.
