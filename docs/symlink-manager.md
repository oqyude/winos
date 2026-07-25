# Symlink Manager

State-aware symlink orchestration for `~/Storage/persist/` → app data directories.

## Goals

1. **Idempotent**: running `apply` multiple times produces the same result.
2. **Safe for active programs**: open file handles are not invalidated by `noop` actions.
3. **Explicit semantics**: `enabled: true/false` makes intent clear in the config.
4. **Audit**: state is captured in `data/state/symlink-snapshot.json` for inspection.

## Mental model

For each entry in `data.json` (excluding `archived`), the manager decides a **desired state** for the target:

| `enabled` | Desired state | Meaning |
|---|---|---|
| `true` | `symlink` | Target should be a symlink pointing to the source |
| `false` | `missing` | Target should not exist (break the connection) |
| `archived: true` | (skipped) | Entry is not managed at all |

The manager probes the **actual state** at the target, compares with desired, and picks an action.

## Action matrix

| Desired | Actual kind | Actual matches? | Action |
|---|---|---|---|
| `symlink` | `missing` | n/a | `create` |
| `symlink` | `symlink` | yes | `noop` |
| `symlink` | `symlink` | no | `replace` (skipped, requires `--force`) |
| `symlink` | `broken-symlink` | n/a | `replace` (skipped, requires `--force`) |
| `symlink` | `file` | n/a | `conflict` (skipped, requires `--force`) |
| `symlink` | `directory` | n/a | `conflict` (skipped, requires `--force`) |
| `missing` | `missing` | n/a | `noop` |
| `missing` | `symlink` | n/a | `drop` (remove symlink) |
| `missing` | `broken-symlink` | n/a | `drop` (remove broken symlink) |
| `missing` | `file` | n/a | `drop` (remove real file) |
| `missing` | `directory` | n/a | `drop` (remove real directory) |

Actions `create` and `drop` run automatically. `replace` and `conflict` are skipped (require `--force`, not yet implemented).

## Why `noop` is safe for active programs

`noop` means "the file at the target is already what config wants — do nothing".

The manager does NOT call `New-Item -Force` on a noop target. It does NOT touch the timestamp. The file handle held by an active program (e.g. AIMP reading its config) remains valid.

This is the key difference from imperative `deploy/clean/redeploy` which always recreate.

## Why `drop` is safe for source data

When `enabled: false` and the target is a symlink, `drop` removes the **link itself**, not the source:

```powershell
$item = Get-Item -LiteralPath $sub.to -Force
if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
    $item.Delete()    # remove just the symlink, do not follow
}
```

`Get-Item.Delete()` on a symlink removes the link without following it. The source directory and its files are untouched.

For a real file/dir at the target, `drop` falls back to `Remove-Item -Recurse -Force`. The user's real data IS removed — this is the intent of `enabled: false`.

## Path resolution

Config entries use template variables:

```json
{
  "name": "AIMP",
  "enabled": true,
  "from": "$persist\\$name",
  "to": "$env:APPDATA\\$name",
  "mappings": [
    { "from": "AudioLibrary", "to": "AudioLibrary" }
  ]
}
```

Variables expanded in `Resolve-EntryPath` via `$ExecutionContext.InvokeCommand.ExpandString`:

| Variable | Source | Example |
|---|---|---|
| `$persist` | `vars.ps1` | `C:\Users\oqyude\Storage\persist` |
| `$storage` | `vars.ps1` | `C:\Users\oqyude\Storage` |
| `$env:USERPROFILE` | PowerShell | `C:\Users\oqyude` |
| `$env:APPDATA` | PowerShell | `C:\Users\oqyude\AppData\Roaming` |
| `$env:LOCALAPPDATA` | PowerShell | `C:\Users\oqyude\AppData\Local` |
| `$env:COMPUTERNAME` | PowerShell | `VETYMAE` |
| `$root` | `init.ps1` | `S:\Git\winos` |
| `$name` | entry.name | `AIMP` |

**Important**: `$root` is normalized via `Split-Path -Parent` in `init.ps1` (no literal `..` suffix). Without this, the state probe would mis-compare paths.

## State file

`data/state/symlink-snapshot.json` (gitignored):

```json
{
  "timestamp": "2026-07-25T16:00:00Z",
  "tool_version": "1.0.0",
  "entries": [
    {
      "name": "AIMP",
      "method": "symlink",
      "from": "C:\\Users\\oqyude\\Storage\\persist\\AIMP",
      "to": "C:\\Users\\oqyude\\AppData\\Roaming\\AIMP",
      "subentries": [
        {
          "from": "C:\\...\\AIMP.ini",
          "to":   "C:\\...\\AIMP.ini",
          "state": { "exists": true, "kind": "symlink", "target": "C:\\...\\AIMP.ini", "matches": true },
          "action": "noop"
        }
      ]
    }
  ]
}
```

Saved automatically as a side effect of every `plan`, `apply`, and `snapshot` action. Use for audit and drift detection.

## Invocation

```powershell
# Interactive (main.ps1 menu):
.\main.ps1
  → Symlink Manager
  → [1] plan       # probe + show table + save snapshot
  → [2] apply      # probe + apply safe actions + save snapshot
  → [3] snapshot   # probe + save snapshot (no plan output)

# Direct CLI:
pwsh -File .\src\modules\symlink-manager.ps1 -action plan
pwsh -File .\src\modules\symlink-manager.ps1 -action apply
pwsh -File .\src\modules\symlink-manager.ps1 -action snapshot
```

## Components

| File | Role |
|---|---|
| `src/modules/common/State.ps1` | Pure functions: `Get-SymlinkSubState`, `Compare-State`, `Invoke-SafeAction`, `Format-Plan`, `Save-Snapshot` |
| `src/modules/symlink-manager.ps1` | Entry point. Wires data.json → State.ps1 → output |
| `src/init.ps1` | Bootstraps vars (`$root`, `$persist`, `$jsonConfig`, `$statePath`) |
| `src/vars.ps1` | Defines `$persist`, `$jsonConfig`, `$statePath` |
| `data/data.json` | Source of truth (entries with `name`, `enabled`, `from`, `to`, `mappings`, `method`) |
| `data/state/symlink-snapshot.json` | Per-machine actual state (gitignored) |

## Tests

| File | Coverage |
|---|---|
| `tests/state.Tests.ps1` | 16 tests: probe, compare (5 desired×actual combinations), drop action with symlink, Resolve-EntryPath |
| `tests/vars.Tests.ps1` | `$statePath` defined and under `$data` |
| `tests/standalone.Tests.ps1` | symlink-manager.ps1 self-bootstraps |

## Adding a new entry

1. Edit `data/data.json`:
   ```json
   {
     "name": "MyApp",
     "method": "symlink",
     "enabled": true,
     "from": "$persist\\$name",
     "to": "$env:APPDATA\\$name",
     "mappings": []
   }
   ```
2. Run `.\main.ps1` → "Symlink Manager" → `[2] apply`
3. The target symlink is created. Future runs show `noop` for it.

## Disabling an entry

1. Edit `data/data.json`: set `enabled: false`
2. Run `.\main.ps1` → "Symlink Manager" → `[2] apply`
3. The symlink is removed (`drop`). Future runs show `noop` (target already absent).

## Future work

- `--force` flag to apply `replace` and `conflict` actions
- `isolate` method state probing (currently skipped; EqualizerAPO handled manually)
- Backward diff (compare current snapshot to previous)
- CI hook: exit 1 on drift detected
