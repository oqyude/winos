# scheduler

Windows Scheduled Tasks are **declared**, not created by hand.

Two machines drifted apart: one runs `OpenCode Serve` (Interactive, AtLogon,
a launcher from `<profile>/.local/share/metaagent/tools/host-scripts`), the
other runs `opencode-serve` (Boot+Logon, a script from `~/.local/bin`). Both
were made by hand, so neither matched the repository. This module makes the
declaration the source of truth: the task lives in the repository as an XML
template, the module compares it with the machine and reports the difference,
and `apply` brings the machine in line.

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
module never unregisters a task it did not declare, and `apply` never
enumerates the machine to tidy it. The extra tasks stay exactly where they
are; removing them is the owner's decision, made by hand.

**It does not overwrite a task that already matches.** `apply` registers the
tasks that differ and leaves the rest alone.

**It does not register a task whose action target is missing.** A task that
starts and dies immediately is worse than no task at all: the machine looks
configured and is not. `apply` reports the missing target and skips that
task.

## Verbs

| Verb | Effect |
|---|---|
| `plan` | Compares every declaration with the live task and prints the difference, field by field. Also reports live tasks that carry no declaration. Read-only. |
| `apply` | Registers the declared tasks that differ, under the name the host already uses. Honours `-WhatIf`. |
| `status` | Prints the live state of the declared tasks (including the settings that keep them alive) and exits 1 if something is missing, differs, is registered twice, or carries no declaration. |

All three honour `-WhatIf` (`apply` registers nothing under it).

## How a task is declared

A declaration is one XML file in `src/modules/scheduler/tasks/`. The file base
name is the **declaration id**, and it is the only source of truth for the
name.

```xml
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <BootTrigger><Enabled>true</Enabled></BootTrigger>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>__USER__</UserId>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>__USER__</UserId>
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
      <Command>__GIT_BASH__</Command>
      <Arguments>-lc "bash __HOME_POSIX__/.local/share/metaagent/tools/host-scripts/opencode-serve.sh"</Arguments>
    </Exec>
  </Actions>
</Task>
```

To add a task: drop a new `<DeclarationId>.xml` into that directory. Nothing
else has to change - the module picks the file up, and the diff starts
reporting it as missing on a machine that does not have it yet.

### The task name is matched by KEY, not by spelling

The two hosts spell the same task differently:

| Host | The task is called |
|---|---|
| lamet | `OpenCode Serve` |
| vetymae | `opencode-serve` |
| this repository | `OpenCodeServe.xml` |

Before 2026-11-04 the module asked Task Scheduler for the literal file name
(`OpenCodeServe`), got "no such task" on both hosts, and reported the
declaration as *not registered*. The drift was invisible by construction: the
report described a task that does not exist and said nothing about the one
that does.

The module now reads the **names of every task in the root folder** and
matches them by key: the name with case, spaces, dashes and underscores
removed (`Get-TaskNameKey` in `src/modules/scheduler/State.ps1`). All three
spellings above are one key, `opencodeserve`, and therefore one task.

An alias table (`OpenCodeServe` → `OpenCode Serve`) was the alternative and
was rejected: it needs one entry per host and goes stale the day a third host
spells it `opencode_serve`. The key rule is the same rule a human applies
when reading the two names, and it needs no maintenance.

Consequences, all of which the module now enforces:

- `plan` compares the declaration with the task the host actually has, and
  prints the live spelling next to the declaration id.
- `apply` registers under the **live** name, so the machine gets its task
  updated instead of a second task and a second server on one port.
- The same task registered twice under two spellings is reported as `[DUPL]`
  and `apply` refuses to guess.

### A live task with no declaration is reported

The module does not audit the machine, but "never tidy" must not mean "never
notice". A live task is reported as `[UNDECLARED]` when

- its name key **extends** a declared key (`OpenCodeServeOld`,
  `my-OpenCode-Serve`), or
- its action runs the **same launcher file** as a declaration, under any name.

It is not reported when its key is a declared key (that task is already being
compared) or when it shares neither the name nor the launcher: the owner's
`OpenCodeCaptureScreen` and friends are somebody else's business.

### Placeholders

Absolute paths rot, so a declaration never hardcodes one. The placeholders are
resolved per host by `Get-SchedulerHostValues` in
`src/modules/scheduler/State.ps1`:

| Placeholder | Value |
|---|---|
| `__DATA_ROOT__` | the winos data root (the synced store when it exists, the repository's `data/` otherwise) |
| `__TOOLS_DIR__` | the host's tools directory |
| `__HOME__` | the user's profile directory |
| `__HOME_POSIX__` | the same, in Git Bash spelling (`/c/Users/oqyude`) |
| `__GIT_BASH__` | `bash.exe` of Git for Windows; Program Files first, the same order `src/host-scripts/opencode-serve.cmd` uses |
| `__USER__` | the account, in Task Scheduler's `DOMAIN\user` form |

## What the diff compares

One dimension per **field**, and the report names the field. This is not
cosmetic: until 2026-11-04 the whole `Settings` block was one lumped string,
so the report could only say

```
Settings: declared 'IgnoreNew/5/PT0S/true' / actual 'IgnoreNew/0/PT72H/true'
```

which names nothing a reader can act on.

| Dimension | Where it comes from | Why it is here |
|---|---|---|
| `UserId` | `Principal/UserId` | who runs it |
| `LogonType` | `Principal/LogonType` | `InteractiveToken` vs `S4U` -- S4U may lose network access |
| `RunLevel` | `Principal/RunLevel` | `LeastPrivilege` / `HighestAvailable` |
| `Triggers` | the trigger set: `Boot`, `Logon:<user>`, `Idle`, `Time:<start>` | when it runs; a task that lost its logon trigger never starts |
| `Action` | `Exec/Command` + `Exec/Arguments` | what it runs (`-lc` vs `-c` is here) |
| `WorkingDirectory` | `Exec/WorkingDirectory` | where it runs from |
| `MultipleInstances` | `Settings/MultipleInstancesPolicy` | `IgnoreNew` is what stops a second server |
| `DisallowStartIfOnBatteries` | `Settings/...` | **the field that killed the server on a laptop** |
| `StopIfGoingOnBatteries` | `Settings/...` | same story, from the other side |
| `ExecutionTimeLimit` | `Settings/...` | `PT72H` means the server dies on day three |
| `RestartOnFailure` | `Settings/RestartOnFailure` `Count`/`Interval` | a server that does not come back |
| `StartWhenAvailable` | `Settings/...` | a start missed while the machine was off |
| `Enabled` | `Settings/Enabled` | the task is off |

### What is ignored, and why

| Ignored | Why |
|---|---|
| `RegistrationInfo`: `URI`, `Author`, `Date`, `Description` | Task Scheduler writes them into every export; a declaration has none |
| `BootTrigger/Delay`, the whole `IdleSettings` block | they matter only to a task that runs on idle, and this one does not |
| `UseUnifiedSchedulingEngine`, `AllowHardTerminate`, `Priority`, `Hidden`, `WakeToRun`, `RunOnlyIfNetworkAvailable`, `AllowStartOnDemand`, `RunOnlyIfIdle` | the declaration does not name them, so they keep the scheduler's default on every host; nothing to drift from and nothing silently rewritten by `apply` |
| the `version` attribute of `<Task>` | 1.3 on one host, 1.4 in the declaration, same meaning |
| an account written as a SID | the exporter writes `S-1-5-21-...` for the principal while the declaration writes `DOMAIN\user`; they cannot be compared without asking Windows to translate them, and a difference that fires on every host teaches the reader to ignore the report. The account is still pinned: `apply` re-registers it |

### Defaults are facts

Task Scheduler **omits** a setting that carries the schema default, so "the
element is absent" means "the default", never "not declared". This is the
trap that hid the drift -- a hand-made task shows no `ExecutionTimeLimit`
element at all and still stops after 72 hours:

| Element | Absent means |
|---|---|
| `ExecutionTimeLimit` | `PT72H` |
| `DisallowStartIfOnBatteries` | `true` |
| `StopIfGoingOnBatteries` | `true` |
| `MultipleInstancesPolicy` | `IgnoreNew` |
| `RestartOnFailure` | disabled (count 0) |
| `StartWhenAvailable` | `false` |
| `Enabled` | `true` |
| `Principal/LogonType` | `InteractiveToken` |
| `Principal/RunLevel` | `LeastPrivilege` |
| a trigger's `Enabled` | `true` |

So a declaration that says `PT0S`, compared with a live task that has no
`<ExecutionTimeLimit>` element, reports `PT0S` vs `PT72H` -- which is the
truth. A disabled trigger is left out of the set entirely: it never fires, so
declaring it says nothing about when the task runs.

## The declared tasks today

| Declaration | Task name on the hosts | Logon | Trigger | Action |
|---|---|---|---|---|
| `OpenCodeServe.xml` | `OpenCode Serve` (lamet), `opencode-serve` (vetymae) | `InteractiveToken` (LeastPrivilege) | Boot + at logon | `__GIT_BASH__ -lc "bash <profile>/.local/share/metaagent/tools/host-scripts/opencode-serve.sh"` |

### The action describes what really runs

`-lc` is load-bearing. A login shell sources `~/.bashrc`, and that is where
`OPENCODE_SERVER_USERNAME` / `OPENCODE_SERVER_PASSWORD` are exported. The
opencode process does not consult `service.json` when its launcher was
started from a profile-sourced shell, so without the password in the profile
the server answers 401.

The `.cmd` wrapper in `src/host-scripts/` is the winos canon (it finds bash
itself and reads no profile), and it is **not** what the task runs: on
Windows the owner keeps the profile-sourced launcher. See
[`opencode-registry.md`](opencode-registry.md#the-launcher-decision) for that
decision. The declaration therefore names Git Bash, the profile path
(`__HOME_POSIX__`) and `-lc` -- the live spelling on lamet -- and the
`-c` + `~/.local/bin/oc-serve-task.sh` spelling on vetymae is reported as
drift instead of being imitated.

The launcher script itself is a separate deliverable. Until it is on disk,
`plan` says so and `apply` skips the task rather than registering one that
cannot start. Both spellings of the path are tried (`/c/Users/...` for the
declaration, `C:\Users\...` for the file system): checking the wrong one
would make `apply` skip a healthy task.

### The logon type

`InteractiveToken` is the safe choice for a server that has to reach the
network: an S4U task runs without stored credentials and may be denied
network access. Moving to the other mode is one line in the XML.

### The 2026-11-04 incident, in one paragraph

The owner's laptop dropped off AC and its server stopped. The live task had
been made by hand and never imported from this declaration: it carried
`DisallowStartIfOnBatteries=True`, `StopIfGoingOnBatteries=True`,
`ExecutionTimeLimit=PT72H` and `RestartCount=0`, while the declaration said
`false`/`false`/`PT0S`/`5`. None of it was reported, because the module looked
for a task name the host does not use and compared the settings as one
opaque string. Both halves are fixed: the name is matched by key, and each of
those four fields is its own reported finding.

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
| `src/modules/scheduler/State.ps1` | the pure half: the facts, the defaults, the name key, the diff, the placeholder resolution, `Set-Task` |
| `src/modules/scheduler/tasks/*.xml` | the declarations, one file per task |
| `tests/modules/scheduler.Tests.ps1` | the diff tests - they run on any host, no Windows needed |

The diff is tested on XML strings, so the tests do not need a Windows host and
do not touch a real Task Scheduler -- the live fixtures are real exports from
both hosts, battery flags and 72-hour limit included. `apply` is tested with
the scheduler cmdlets replaced by test doubles, and the test asserts that
`Unregister-ScheduledTask` is never called.
