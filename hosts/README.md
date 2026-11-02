# Per-host path declaration

Example of the file a host declares its absolute paths in.

Copy it to `<data dir>\hosts\<COMPUTERNAME>.json` and edit the values for the
machine it belongs to. `COMPUTERNAME` is the Windows computer name
(`hostname` off Windows). The data dir is the synced store
(`%USERPROFILE%\Storage\winos\data`) when it exists, and the repository's own
`data\` directory otherwise -- the tool prints which one it used on every run.

No secrets belong in this file. It holds paths and nothing else.

| Field | Meaning | Built-in default |
|---|---|---|
| `projectsDir` | the checkout root of this host | `S:\Git` |
| `toolsDir` | where the tools live (`opencode-computer-use` sits here) | `C:\Tools` |
| `pluginRoot` | the plugin library -- read-only, never written to | `S:\Plugins`, else `%USERPROFILE%\Plugins` |
| `taskWorkingDirectory` | the working directory a scheduled task starts in | follows `projectsDir` |
| `tasks` | optional per-task overrides (`script`, `errorLog`) | none |

`%VAR%` and `$env:VAR` are expanded in every path.
