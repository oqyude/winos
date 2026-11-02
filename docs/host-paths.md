# Per-host paths

`winos` used to carry a handful of absolute Windows paths in its source:
`S:\Git` (the working directory of a scheduled task), `C:\Tools` (where the
`opencode-computer-use` venv lives) and `S:\Plugins` (the plugin library).
Each of them rotted the moment the tool ran on a host whose layout differed,
and nothing said so: the tool kept using the path, the path was not there,
and the failure surfaced as "the service does not start" hours later.

The paths are **declared per host** now.

## The declaration file

```
<data dir>\hosts\<COMPUTERNAME>.json
```

* `<data dir>` is the synced store, `%USERPROFILE%\Storage\winos\data`, when
  it exists; the repository's own `data\` directory otherwise. The precedence
  is the one that was already in `src/vars.ps1` — it has not changed, it is
  only now visible.
* `<COMPUTERNAME>` is the Windows computer name (`hostname` off Windows).
* The file is machine-local: one file per host, all of them in the same
  synced store, each named after the machine it describes.
* It holds paths and nothing else. No secrets.

```json
{
  "projectsDir": "D:\\Git",
  "toolsDir": "D:\\Tools",
  "pluginRoot": "D:\\Plugins",
  "taskWorkingDirectory": "D:\\Git"
}
```

`hosts/example.json` in the repository root is the same shape, filled in for a
host that keeps everything on `D:`.

| Field | Meaning | Built-in default |
|---|---|---|
| `projectsDir` | the checkout root of this host | `S:\Git` |
| `toolsDir` | where the tools live (`opencode-computer-use` sits here) | `C:\Tools` |
| `pluginRoot` | the plugin library — read-only, never written to | `S:\Plugins`, else `%USERPROFILE%\Plugins` |
| `taskWorkingDirectory` | the working directory a scheduled task starts in | follows `projectsDir` |
| `tasks` | optional per-task overrides (`script`, `errorLog`) | none |

`%VAR%` and `$env:VAR` are expanded in every path, and `%USERPROFILE%` is
expanded even where Windows does not define it.

## When the declaration is missing

The tool does not stop. It falls back to the built-in defaults and says so —
once per session, naming the file it looked for:

```
WARNING: No host declaration for 'DESKTOP-X': C:\Users\me\Storage\winos\data\hosts\DESKTOP-X.json not found - falling back to the built-in defaults (S:\Git, C:\Tools, S:\Plugins).
```

and, on every load, one summary line:

```
winos: data dir = C:\Users\me\Storage\winos\data (machine store); host declaration = ...\hosts\DESKTOP-X.json (missing - defaults used)
```

A missing declaration is therefore a **visible** condition, never a silent
one. That is the whole point: the next host whose `S:\Git` does not exist
finds out from the tool, not from a service that will not start.

## Where the resolution lives

`src/host-paths.ps1` is the only file that knows the defaults and the only
file that reports a missing declaration. `src/vars.ps1` calls it and exposes
the result as `$projectsDir`, `$toolsDir`, `$pluginRoot`,
`$taskWorkingDirectory`, `$hostDeclarationFile` and `$hostDeclarationFound`.

The plugin module (`src/modules/plugins/vars.ps1`) used to resolve
`S:\Plugins` itself, with its own fallback chain; it now takes the value from
the same resolution, so there is one list of defaults instead of two.

`scripts/install-opencode.ps1` resolves `$ToolsDir` the same way — it used to
carry `C:\Tools` inline.

## Related

* Task T24 in `.agent/tasks/manifest.md` — the `$data` switch that used to be
  silent. The precedence is unchanged; the choice is now printed.
* Task T25 in `.agent/tasks/manifest.md` — `0.0.0.0` as a silent default of
  a service. Still open; the service declarations that fix it come with the
  scheduler module.
