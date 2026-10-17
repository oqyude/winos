# herdr-serve

Scheduled-task lifecycle for `herdr server` on Windows logon.

`herdr` — terminal workspace manager for AI coding agents ([herdr.dev](https://herdr.dev)). The `herdr server` subcommand runs it headless on a local socket (`~\AppData\Roaming\herdr\herdr.sock`); ordinary same-account clients (terminals, IDE plugins) attach to that socket to drive agents, panes, and workspaces.

The module registers a `HerdrServe` scheduled task that runs at logon under the current user (Limited, not elevated) and launches `herdr server --allow-unelevated-clients` through `runner.ps1`. The flag closes the elevated panescope and opens the socket to other clients.

## Module

- **Register key:** `herdr-serve`
- **Alias:** `herdr-serve`
- **Path:** `src/modules/herdr-serve.ps1`
- **Actions:** `setup`, `remove`, `status`, `start`, `stop`
- **Destructive:** `remove` (the menu asks for confirmation before running it)

Winos entry points:

```
winos herdr-serve <action>
winos service herdr-serve <action>      # two-level grammar, still supported
main.ps1                                # interactive menu → 4 herdr-serve
```

## Verbs

| Verb | Effect |
|---|---|
| `setup` | Writes `data/herdr-serve/config.json` (herdr path + `allowUnelevatedClients=true`) and registers the `HerdrServe` Scheduled Task at logon. Starts the task immediately. Errors if `herdr` is not in `PATH`. |
| `remove` | Stops the task, unregisters it, deletes `data/herdr-serve/`. |
| `status` | Prints the task State/Last Run/Next Run and whether `herdr.exe` is currently running. Exits 1 if the task is not registered. |
| `start` | Manually starts the task. |
| `stop` | Manually stops the task. |

Both `setup`, `remove`, `start`, and `stop` gate behind `SupportsShouldProcess`, so `-WhatIf` is honoured everywhere. `setup -WhatIf` does not write `config.json` and does not register the task; `remove -WhatIf` does not delete anything.

## Files written

| File | Backed up? | Purpose |
|---|---|---|
| `data/herdr-serve/config.json` | gitignored (machine-specific) | One record: `{ herdr, allowUnelevatedClients }`. Lets a future `setup` rerun reproduce the same flag. |
| `data/herdr-serve/.env` | not used | (reserved for future per-host overrides) |

`HerdrServe` is the Scheduled Task name; the runner is `src/modules/herdr-serve/runner.ps1`, which reads `config.json` and exec's `herdr server [--allow-unelevated-clients]`.

## Differences from `opencode-serve`

Both modules follow the same shape (Scheduled Task at logon, Limited user, runner.ps1 in the repo, `SupportsShouldProcess`). What differs:

| | `opencode-serve` | `herdr-serve` |
|---|---|---|
| Binary | `opencode` (HTTP server) | `herdr` (headless, socket-only) |
| `config.json` fields | `hostname`, `port`, `username`, `opencode` | `herdr`, `allowUnelevatedClients` |
| Required flag | none | `--allow-unelevated-clients` (else ordinary clients blocked) |
| Service name (Task Scheduler) | `OpenCodeServe` | `HerdrServe` |
| Port | 4096 | none — socket at `~\AppData\Roaming\herdr\herdr.sock` |
| Password | `.env` + `OPENCODE_SERVER_PASSWORD` | none |

## See also

- [opencode-serve reference implementation](src%5Cmodules%5Copencode-serve.ps1) — both modules are this same skeleton with the right verb substitutions.
- [herdr official guide](https://herdr.dev) — what `herdr` does and how clients connect.
