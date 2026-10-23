# winos

**Symlink orchestrator and Windows configuration manager.**

`winos` keeps application configuration in one place and links it into where
each application expects to find it. It also manages a small set of Windows
integrations (cursor themes) and background services that start at logon.

The model is *state-probe*: `winos` looks at what is on disk right now,
compares it with what the configuration declares, and reports the difference.
Nothing is applied that was not declared, and every write is reported.

---

## Requirements

- Windows
- PowerShell 5.1 or newer (`pwsh` recommended)
- For development only: [Pester](https://pester.dev) 5.x+, [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer)

No administrator rights are required. Creating a junction for a directory does
not need elevation; creating a *symbolic link* on some Windows configurations
does — see [Symlinks](#symlinks-and-elevation).

## Install

```powershell
git clone https://github.com/oqyude/winos
cd winos
.\main.ps1 --help
```

Or through Scoop, using the manifest in `bucket/winos.json`:

```powershell
scoop install winos
```

`winos.cmd` is a thin launcher that calls `main.ps1` with the same arguments,
so `winos symlink-manager plan` and `.\main.ps1 symlink-manager plan` are
equivalent.

## Usage

### Command line

```
winos <module> <action>
winos service <name> <action>
```

Running `winos` with no arguments opens an interactive menu.

| Module | Alias | Actions | Destructive |
|---|---|---|---|
| Config Persistence | `symlink-manager` | `plan`, `apply`, `snapshot` | — |
| Plugin Deployment | `plugin-manager` | `plan`, `apply`, `revert`, `snapshot`, `status`, `adopt`, `verify` | `revert`, `adopt` |
| Essentials | `essentials` | `install`, `uninstall` | `uninstall` |
| opencode-serve | `opencode-serve` | `setup`, `remove`, `status`, `start`, `stop` | `remove` |
| herdr-serve | `herdr-serve` | `setup`, `remove`, `status`, `start`, `stop` | `remove` |

The two `*-serve` modules are also reachable through the two-level
`winos service <name> <action>` grammar, which exists for callers that think
in services rather than in module verbs.

```powershell
winos symlink-manager plan
winos plugin-manager status
winos service herdr-serve status
```

### Flags

| Flag | Where | Meaning |
|---|---|---|
| `-Force` | `main.ps1` | passed through to the module: allows replacing a drifted link instead of reporting it |
| `-WhatIf` | interactive menu | preview only. The menu offers it before every destructive verb. On the command line, preview the equivalent verb first (`plan`, `status`) |
| `--help`, `--version` | `main.ps1` | usage and version |

### Destructive verbs

`revert`, `adopt`, `uninstall` and `remove` change system state. In the
interactive menu they are never reachable with a single keypress: the menu
offers a preview first and requires the word `y` to run for real.

## Configuration

### Application config — `data/data.json`

Schema version 2:

```json
{
  "version": 2,
  "persistRoot": "$persist",
  "symlinks": [
    {
      "name": "AIMP",
      "enabled": true,
      "from": "$persist\\$name",
      "to": "$env:USERPROFILE\\scoop\\persist\\aimp\\Profile",
      "mappings": [
        { "from": "AudioLibrary", "to": "AudioLibrary" }
      ]
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `version` | schema version, currently `2` |
| `persistRoot` | root all persisted config lives under |
| `symlinks[].name` | application name; also the folder name under the persist root |
| `symlinks[].enabled` | `false` breaks the link instead of maintaining it |
| `symlinks[].from` | source path — tokens: `$persist`, `$env:USERPROFILE`, `$name` |
| `symlinks[].to` | destination path the application reads |
| `symlinks[].mappings[]` | per-file entries under `from` to link individually |

`from` must live under `$persist`; the exceptions are listed explicitly in
`tests/vars.Tests.ps1`.

### Plugin manifests — `manifests/<Plugin Folder>.json`

One file per plugin folder. Sections:

| Section | Meaning |
|---|---|
| `Name`, `Description` | human-readable identity |
| `Links` | junctions to create — tokens use the `%VAR%` form (`%ProgramFiles%`) |
| `Copy` | trees to copy out of the vendor installer |
| `Registry` | `.reg` files to import |
| `Process` | scripts to run (before revert, after apply) |

The plugin library itself is treated as **read-only** — `winos` never writes
into it. It is expected at `S:\Plugins`, falling back to
`%USERPROFILE%\Plugins`.

### Scoop bucket — `bucket/`

Scoop manifests, including `bucket/winos.json` for installing `winos` itself.
`bucket/*.json` are kept current automatically by CI
(`.gitea/workflows/auto-update.yml`); `manifests/*.json` are plugin manifests
and are maintained by hand.

## State

| File | Tracked? | Meaning |
|---|---|---|
| `data/state/symlink-snapshot.json` | no (machine-local) | last observed state of every config symlink; the baseline for drift detection |
| `state/plugin-deployment.json` | yes | allowlist of deployed plugins |
| `state/plugin-deployment-snapshot.json` | no (machine-local) | last observed plugin deployment, regenerated on every run |

Snapshots are written as a side effect of every action, including `plan`.

## Development

```powershell
.\scripts\test.ps1    # Pester suite
.\scripts\lint.ps1    # PSScriptAnalyzer over src/, tests/, scripts/
```

Both scripts exit non-zero on failure, and both fail loudly when their tool or
their target tree is missing — a green run means the tree was actually
examined.

## Repository layout

```
winos/
  main.ps1              # entry point: CLI routing + interactive menu
  winos.cmd             # launcher
  src/
    init.ps1            # bootstrap: sets $root, never changes the working directory
    vars.ps1            # module registry + shared paths
    modules/
      symlink-manager.ps1
      essentials.ps1
      herdr-serve.ps1        + herdr-serve/runner.ps1
      opencode-serve.ps1     + opencode-serve/runner.ps1
      common/State.ps1       # symlink engine: probe, compare, apply, report
      methods/               # symlink.ps1, isolate.ps1
      plugins/               # plugin deployment module
  data/                 # data.json + per-application isolate scripts
  manifests/            # one manifest per plugin folder
  bucket/               # Scoop manifests
  scripts/              # lint, test and maintenance scripts
  tests/                # Pester suite
  docs/                 # per-module documentation
```

## Symlinks and elevation

The symlink engine probes what exists and creates the link that matches the
declared state. On Windows, creating a **symbolic link** for a file needs
either administrator rights or Developer Mode; creating a **junction** for a
directory does not. The engine creates junctions for directories and symbolic
links for files, so the elevation requirement depends on the entry.

## License

MIT — see [LICENSE](LICENSE).
