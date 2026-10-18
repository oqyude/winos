# Plugin Manager

Declarative management of audio plugin symlinks. Plugin folders live under
`S:\Plugins` (treated as read-only by the tool) and are exposed to the system
via junctions in `Program Files`, `Common Files`, `ProgramData`, and `AppData`.

## Goals

1. **Idempotent** — running `apply` multiple times produces the same result.
2. **Safe for active programs** — `noop` actions don't invalidate open file handles.
3. **Declarative** — `state/plugin-deployment.json` is the source of truth; commands reconcile the system to match.
4. **Junctions, not symlinks** — uses `New-Item -ItemType Junction` (no admin required for directories). Falls back to `SymbolicLink` for file targets.
5. **Migration-friendly** — `adopt` captures existing on-system junctions from old `.bat` scripts.

## Mental model

The state file lists each plugin with two flags:

| Field   | Type     | Default if missing | Meaning                                                      |
|---------|----------|--------------------|--------------------------------------------------------------|
| `link`  | bool     | `false`            | Desired: create junctions when true, drop when false.         |
| `ignore`| bool     | `false`            | If true, skip this entry entirely (no probe, no touch).       |
| `mappings` | array | `[]`               | List of `{from, to, kind}` pairs (absolute paths).            |

Plugins NOT in the file are treated as `ignore: true` by default — they are
never probed or touched. This makes the state file a positive allowlist.

Each `mappings` entry corresponds to one junction on the system. A plugin with
VST2 + VST3 + AAX has three mappings. Toggling `link` flips them all together.

## Action verbs

| Verb        | Purpose                                                                 |
|-------------|-------------------------------------------------------------------------|
| `plan`      | Probe + show the delta (what would change) + save snapshot.             |
| `apply`     | Reconcile the system to match `state.json` (create/drop junctions).     |
| `revert`    | Apply with all `link: false` — drop every non-ignored junction.        |
| `snapshot`  | Probe + save snapshot (no plan output, no changes).                    |
| `adopt`     | Scan system for active junctions, write `state.json`.                  |
| `status`    | Report drift since the last snapshot. Read-only.                      |
| `verify`    | Check every path apply/revert would touch. Read-only. Exit 1 if bad.   |

All destructive actions support `-WhatIf` and `-Confirm`.

## Action matrix

| Desired (`link`) | Actual kind at target | Action                                              |
|------------------|------------------------|-----------------------------------------------------|
| `true`           | `missing`              | `create`                                            |
| `true`           | `symlink`, matches     | `noop`                                              |
| `true`           | `symlink`, drift       | `replace` (skipped, requires `--Force`)             |
| `true`           | `broken-symlink`       | `replace` (skipped, requires `--Force`)             |
| `true`           | `file` / `directory`   | `conflict` (skipped, requires `--Force`)            |
| `false`          | `missing`              | `noop`                                              |
| `false`          | `symlink` (any kind)   | `drop` — removes the link, NOT the source          |
| `false`          | `file` / `directory`   | `drop` — explicit remove (deletes content)          |

`drop` is **conditional**: when the target is a junction or symlink (reparse
point), `$item.Delete()` removes just the link and leaves the source intact.
When the target is a regular file or directory, `Remove-Item -Recurse -Force`
is used (this is the user's intent when `link: false` on a non-link target).

## Why junction (not symlink)

`New-Item -ItemType Junction` works for directories without admin rights and
without Developer Mode. Junctions and symlinks both set the NTFS `ReparsePoint`
attribute, so the probe logic in `Get-SymlinkSubState` treats them identically.
For file targets (rare; e.g. `Desktop → COSMOS.exe`), the tool falls back to
`-ItemType SymbolicLink`, which may require admin or Developer Mode.

## Discovery heuristics

`Discover-Plugin` inspects a plugin folder and emits candidate mappings. **One**
pattern is recognized:

1. **Top-level `VST2\` / `VST3\` / `vst\` directories** — each subdir is one
   mapping:
   - `VST2\<vendor>` → `$env:PROGRAMFILES\VSTPlugins\<vendor>`
   - `VST3\<vendor>` → `$env:COMMONPROGRAMFILES\VST3\<vendor>`

This is unambiguous: a VST folder holding one directory per plugin cannot be
mistaken for anything else.

### The `C\` mirror heuristic was removed

Vendors like Waves and Neural DSP ship a `C\` subtree that mirrors where their
files belong on the drive. An earlier version walked that subtree and mapped
every leaf directory onto its `C:\` equivalent. Measured against the live
system it was wrong almost every time:

| plugin                | heuristic produced | actually correct |
|-----------------------|--------------------|------------------|
| Arturia FX Collection | 1603               | 3                |
| Vengeance Avenger     | 1016               | 2                |
| Toontrack             | 362                | 2                |
| Acon Digital          | 170                | 2                |
| Soundtoys             | 113                | 0                |
| iZotope Ozone 11      | 69                 | 1                |

3405 inferred mappings against 45 links that actually exist. The subtree holds
both install locations and vendor content trees, and nothing in the layout
distinguishes them — a depth threshold does not help either, since correct
mappings all sit at depth 2 but incorrect ones appear at depth 1 through 10.

So plugins with a `C\` mirror get an explicit manifest instead, and the same
applies to layouts where the VST folder *is* the payload rather than a container
of plugins (Synth1's `vst\`, Dear Reality's `VST3\`), which hold the DLL
directly and yield no subdirectories to walk.

Manifests can be written by hand, or generated from what the machine already has
linked — see [Scripts](#scripts).

## Verify: pre-flight before touching anything

`verify` reads `state.json`, resolves entries exactly the way `apply` resolves
them, and checks that every path about to be used exists. It writes nothing,
creates no links, and does not read the registry.

```powershell
pwsh -File .\src\modules\plugin-manager.ps1 -action verify
pwsh -File .\src\modules\plugin-manager.ps1 -action verify -Sandbox
```

It reports four kinds of problem:

| Kind                | Meaning                                                  |
|---------------------|----------------------------------------------------------|
| `NO_MAPPINGS`       | Entry resolved to no links and has no `from` to fall back on. |
| `MISSING_SRC`        | A link's source directory does not exist.                  |
| `MISSING_REG`        | A manifest names a `.reg` file that is not there.          |
| `MISSING_SCRIPT`     | A manifest names a `.cmd`/`.ps1` that is not there.       |
| `MISSING_COPY_SRC`   | A manifest copy step names a source tree that is absent.   |

Exit code is 1 when anything is wrong, so it can gate a script.

Scope differs from `scripts/audit-plugins.ps1`: the audit sweeps the whole
plugin library, `verify` covers only what `state.json` selects. Running
`verify -Sandbox` before `apply` without `-Sandbox` is the intended sequence —
it proves the sandbox layout matches what the real run expects.

## Adopt: capturing existing on-system state

`adopt` is the migration entry-point. It scans standard system target roots
and emits one state.json entry per **currently active** plugin folder
(distinct from a plugin folder that just sits in `S:\Plugins` unused).

Scan roots:
- `$env:PROGRAMFILES\VSTPlugins`
- `$env:COMMONPROGRAMFILES\VST3`
- `$env:COMMONPROGRAMFILES\Avid\Audio\Plug-Ins`
- `$env:PROGRAMFILES\Steinberg\VSTPlugins`

For each junction in those roots whose target is under `$pluginRoot`:
- Plugin name = first segment of target's path under `$pluginRoot`
- Mapping = `(target, junction_path)` pair

After `adopt`, every active plugin from old `.bat` scripts has an entry with
`link: true` and the discovered mappings. Inactive plugin folders are NOT
listed — they remain ignored by default. Add them manually when needed.

**Caveat**: adopt requires write access to the system roots (e.g.
`C:\Program Files\Common Files\VST3\`). Run `pwsh` elevated in production.

## Orphans: live junctions nothing accounts for

`scripts/audit-plugins.ps1` reports junctions that point into the plugin
library but that no manifest asks for. These fall into two kinds, and they
need different decisions:

| Kind         | Source exists | Meaning                                                        |
|--------------|---------------|----------------------------------------------------------------|
| `dangling`   | no            | The link is already broken. Removing it loses nothing.          |
| `undeclared` | yes           | Either the manifest is missing a link, or an installer variant ran that should not have. |

`-PruneDangling` removes the first kind only:

```powershell
pwsh -File .\scripts\audit-plugins.ps1 -PruneDangling -WhatIf   # dry run
pwsh -File .\scripts\audit-plugins.ps1 -PruneDangling           # actually remove
```

Undeclared orphans are never pruned automatically. Two plausible readings, and
the tool cannot tell them apart:

- The manifest is incomplete — the link is wanted, so add it to the manifest
  and re-run `apply`.
- The link came from the wrong installer variant — for example running a
  32-bit `.cmd` on a 64-bit host creates links under `%ProgramFiles%`
  instead of `%ProgramFiles(x86)%`. That link then points at the x86 build
  from the wrong architecture tree and should be deleted.

Deciding which requires knowing what the vendor intended, so it stays with
you rather than being guessed at.

## Manifests (Phase 3+)

For plugins with non-trivial setup (registry imports, tree copies, process
management, multiple junction targets), declare a manifest in
`manifests/<Name>.json`. Apply reads manifests at run-time and runs the
declared steps in addition to the link reconciliation.

### Schema

```json
{
  "Name":        "Waves",
  "Description": "Waves Complete",
  "Links":    [ { "From": "...", "To": "...", "Kind": "Junction" } ],
  "Copy":     [ { "From": "...", "To": "..." } ],
  "Registry": [ { "OnEnable": "...", "OnDisable": "..." } ],
  "Process":  [ { "BeforeRevert": "..." } ]
}
```

**Rules**:

- Top level must be a JSON object, not an array.
- `Links` and `Copy` entries require both `From` and `To`.
- `Registry` entries require `OnEnable` and/or `OnDisable`.
- `Process` entries require `BeforeRevert`.
- `Name` and `Description` are optional. Every other section is optional.
- Keys are read case-insensitively, so `OnEnable` and `onEnable` both work.

**Paths**:
- `%VAR%` tokens expand to environment variables, including names with
  parentheses such as `%ProgramFiles(x86)%`. An unresolved token is left
  verbatim rather than blanked, so a typo surfaces as a missing file rather
  than a silently relative path.
- `From` is relative to the plugin's own folder unless already absolute.
- `To` is used verbatim (system paths), absolute or relative to that folder.
- `$env:VAR` is **not** supported: JSON strings are literal and `ConvertFrom-Json`
  evaluates nothing. `%VAR%` is used instead because it matches the syntax the
  vendor `.bat` installers already relied on.

A manifest that fails validation is reported via warning and skipped — it never
aborts the run.

### Link precedence

For a plugin with a manifest, its junctions come from whichever source is most
explicit:

1. `mappings` in the state.json entry — explicit per-link config, always wins.
2. `Links` in the manifest — the vendor's intended install layout.
3. The single `from`/`to` form.

Without step 2 an entry carrying only `{name, link, ignore}` would probe nothing
and `apply` would silently do nothing. This matters for plugins whose vendor
installer creates more links than are currently live: `adopt` records only what
is linked, so the manifest fills in the rest when the plugin is switched on.

### Step ordering

**apply (link=true):**
1. Link reconciliation (create/replace/drop junctions per state.json)
2. `Copy` steps (mirror source trees to targets)
3. `Registry` `OnEnable` steps (import reg files)

**apply (link=false):**
1. Link reconciliation
2. `Registry` `OnDisable` steps

**revert (all link=false):**
1. `Process` `BeforeRevert` steps (kill background processes etc.)
2. Link reconciliation (drop junctions)
3. `Registry` `OnDisable` steps

`Process` runs first in revert so files are not locked when we drop junctions.

### `-WhatIf` support

Each step is a function with `[CmdletBinding(SupportsShouldProcess)]`. Pass
`-WhatIf` to `apply`/`revert` to preview without touching the system.

## State file format

```jsonc
{
  "version": 1,
  "tool_version": "0.0.1",
  "plugins": [
    {
      "name": "FabFilter - Total Bundle",
      "link": true,
      "ignore": false,
      "mappings": [
        { "from": "S:\\Plugins\\FabFilter - Total Bundle\\VST2\\FabFilter", "to": "C:\\Program Files\\VSTPlugins\\FabFilter", "kind": "Junction" },
        { "from": "S:\\Plugins\\FabFilter - Total Bundle\\VST3\\FabFilter", "to": "C:\\Program Files\\Common Files\\VST3\\FabFilter", "kind": "Junction" }
      ]
    }
  ]
}
```

For backward compatibility, the legacy single-`from`/`to` form is also accepted
but not emitted by `adopt`.

## Invocation

```powershell
# Interactive (planned, not yet wired):
.\main.ps1
  -> Plugin Manager
  -> [1] plan     # probe + show table + save snapshot
  -> [2] apply    # probe + apply safe actions + save snapshot
  -> [3] revert   # drop all non-ignored junctions
  -> [4] snapshot # probe + save snapshot only
  -> [5] adopt    # scan system, write state.json
  -> [6] status   # report drift since the last snapshot

# Direct CLI:
pwsh -File ./src/modules/plugin-manager.ps1 -action plan
pwsh -File ./src/modules/plugin-manager.ps1 -action apply
pwsh -File ./src/modules/plugin-manager.ps1 -action revert -WhatIf
pwsh -File ./src/modules/plugin-manager.ps1 -action adopt -Confirm:$false
pwsh -File ./src/modules/plugin-manager.ps1 -action snapshot
```

## Components

| File | Role |
|---|---|
| `src/init.ps1` | Bootstrap: sets `$root`, sources `vars.ps1`. |
| `src/vars.ps1` | Defines `$pluginRoot`, `$stateFile`, `$snapshotFile`, `$modules`. |
| `src/modules/common/State.ps1` | Pure functions: `Get-SymlinkSubState`, `Compare-State`, `Invoke-SafeAction`, `Format-Plan`, `Save-Snapshot`. |
| `src/modules/common/StateFile.ps1` | `Read-PluginDeploymentState`, `Write-PluginDeploymentState`, `Get-EnabledPlugins`. |
| `src/modules/common/Discovery.ps1` | `Get-PluginFolders`, `Discover-Plugin`, `Invoke-Adopt`. |
| `src/modules/common/Manifest.ps1` | `Get-PluginManifest`, `Test-Manifest`, `Get-Prop`, `Get-ManifestSection`, `Get-Manifest*Steps`, `Resolve-ManifestPath`. |
| `src/modules/common/Verify.ps1` | `Get-VerifyReport`: read-only pre-flight over resolved entries. |
| `src/modules/methods/registry-import.ps1` | `Import-RegistryFile` (reg import wrapper). |
| `src/modules/methods/copy-tree.ps1` | `Invoke-CopyTree`, `Remove-CopyTree` (robocopy /MIR). |
| `src/modules/methods/process-kill.ps1` | `Invoke-ProcessScript` (run .cmd or .ps1). |
| `manifests/<Name>.json` | Per-plugin behavior declaration. 25 shipped. |
| `scripts/audit-plugins.ps1` | Read-only audit of mappings vs the live system. |
| `scripts/generate-manifests.ps1` | Writes manifests from the links the machine already has. |
| `scripts/new-test-plugins.ps1` | Populates `S:\Plugins\Test` for sandbox runs. |
| `src/modules/plugin-manager.ps1` | Entry point with action dispatch. |
| `state/plugin-deployment.json` | Declared state (committed to git). |
| `state/plugin-deployment-snapshot.json` | Last probe (gitignored). |
| `manifests/<Name>.json` | Per-plugin behavior (Phase 3+). Tracked in git. |

## Tests

| File | Coverage |
|---|---|
| `tests/state.Tests.ps1` | 30 tests: probe (6 sub-cases), compare (4+4), drop variants (4), missing-source guard (3), Resolve-EntryPath, Get-SymlinkEntryState, Get-StateDrift (7). |
| `tests/statefile.Tests.ps1` | 9 tests: missing/empty/malformed/full Read, round-trip Write, Get-EnabledPlugins defaults. |
| `tests/discovery.Tests.ps1` | 11 tests: Get-PluginFolders, Discover-Plugin (VST layouts + C-mirror rejection), Invoke-Adopt (6 scenarios incl. nested junctions). |
| `tests/methods.Tests.ps1` | 44 tests: reg import (4), copy-tree (4), process-kill (4), manifest load (5), Test-Manifest validation (7), Get-Prop (3), Get-Manifest*Steps (6), Expand-PathTokens (6), Resolve-ManifestPath (3), sandbox redirect into manifest paths (3). |
| `tests/sandbox.Tests.ps1` | 24 tests: path mapping per root, directory-boundary matching, double-mapping guard, idempotency, root collision guard, manifest resolution under sandbox. |
| `tests/verify.Tests.ps1` | 9 tests: missing sources, registry and script references, empty vs null mappings, legacy from/to form, empty entry list. |
| `tests/plugin-manager.Tests.ps1` | 2 integration tests: apply runs reg-enable + copy after link; revert runs process before reg-disable. |
| `tests/standalone.Tests.ps1` | 10 tests: file presence, init.ps1 bootstrap, plan/snapshot via child pwsh, state schema. |

## Adding a new plugin

After adopt, inactive plugin folders are not in `state.json`. To enable one:

1. Add an entry manually:
   ```json
   {
     "name": "Vendor - Product",
     "link": true,
     "ignore": false,
     "mappings": [
       { "from": "S:\\Plugins\\Vendor - Product\\VST2\\Vendor", "to": "C:\\Program Files\\VSTPlugins\\Vendor", "kind": "Junction" }
     ]
   }
   ```
2. Run `pwsh -File src/modules/plugin-manager.ps1 -action plan` to preview.
3. Run `apply` to create the junctions.
4. The plugin is now available in your DAW.

For plugins with non-standard layouts (Waves, Neural DSP, etc.), the
heuristics may miss mappings. Run `Discover-Plugin -PluginDir <path>` from
PowerShell to see what it would produce, then either use those mappings in
state.json or wait for Phase 3 (manifests).

## Disabling a plugin

1. Edit `state/plugin-deployment.json`: set `link: false` for the plugin.
2. Run `apply` — the junctions are removed (source data is preserved when
   the target is itself a junction).
3. Future `plan`/`apply` runs show `noop` for that plugin (target already
   absent).

## Disabling everything (revert)

`revert` flips every non-ignored entry to `link: false` and runs `apply`.
Use it as a global "off switch". With `-WhatIf`, it previews without
touching the system.

## Sandbox

Symlink creation against the live `Program Files` only reveals a wrong path
after it has already been written. `-Sandbox` redirects every path so the same
code path can be exercised with nothing real at stake:

| Real                             | Sandbox                      |
|----------------------------------|------------------------------|
| `S:\Plugins`                      | `S:\Plugins\Test`             |
| `C:\Program Files`                | `C:\Test\ProgramFiles`        |
| `C:\Program Files\Common Files`   | `C:\Test\CommonProgramFiles`  |
| `C:\Program Files (x86)`          | `C:\Test\ProgramFilesX86`     |
| `C:\ProgramData`                  | `C:\Test\ProgramData`         |
| `%AppData%`                       | `C:\Test\AppData\Roaming`     |
| `%LocalAppData%`                  | `C:\Test\AppData\Local`       |
| `%Public%`                        | `C:\Test\Users\Public`        |
| `%UserProfile%`                   | `C:\Test\Users`               |

```powershell
pwsh -File .\src\modules\plugin-manager.ps1 -action apply -Sandbox
pwsh -File .\src\modules\plugin-manager.ps1 -action apply -Sandbox -SandboxTarget D:\Scratch
```

### What the sandbox does not cover

Registry imports and `beforeRevert` process scripts are **reported as skipped
and not executed**. There is no sandboxed registry to redirect into, and a
vendor kill script would terminate processes belonging to the live install.
Copy steps do run, because their destination is a filesystem path and gets
mapped like any other.

Populate the sandbox source tree with a subset:

```powershell
pwsh -File .\scripts\new-test-plugins.ps1 -WhatIf
pwsh -File .\scripts\new-test-plugins.ps1
pwsh -File .\scripts\new-test-plugins.ps1 -Include 'Waves' -MaxSizeMB 200
```

The default set is four small plugins chosen for layout variety rather than
coverage: a lowercase `vst\` payload, a VST2+VST3 pair, a nested VST3 payload,
and a plugin whose `VST3` folder is the payload itself.

### Constraints

A sandbox root may not sit inside a root the map already remaps.
`Enable-Sandbox` throws if it does, because a path under `%LocalAppData%`
matches that rule and would be rewritten a second time on the next pass,
producing doubled prefixes. Use `C:\Test` or the drive of your choice.

## Future work

- **Phase 3** — `plugin.psd1` manifests for plugins with non-standard layouts
  (registry, xcopy, process kill). The state file gains `Registry`, `Copy`,
  `Process` step types in addition to `mappings`.
- Manifests for the remaining vendors, so every `.bat` with non-trivial setup
  has an equivalent.
- `Invoke-CopyTree` is enable-only. Reverting Waves does not undo its Native
  Instruments Service Center copy, matching the old `.bat`; `Remove-CopyTree`
  exists for when that should change.
- Interactive menu in `main.ps1`, mirroring `winos`.
- `scripts/lint.ps1` and `scripts/test.ps1` shims.
