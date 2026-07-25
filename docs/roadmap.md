# Roadmap

Last updated: 2026-07-25

This document tracks pending work for `winos`. Items are grouped by priority and area.

## Quick wins (1-2 hours, low risk)

### F1. `--force` flag for drift/conflict actions
State-probe currently skips `replace` (drift) and `conflict` actions. Implement `-Force` switch that allows them.

- `src/modules/common/State.ps1` `Invoke-SafeAction`: take `-Force` parameter
- `replace`: delete existing symlink, create new
- `conflict`: rename or delete existing, then create
- `src/modules/symlink-manager.ps1`: pass `-Force:$Force`
- `scripts/snapshot.ps1`: same

### F2. Snapshot diff (compare with previous)
Useful for audit: "what changed since last snapshot?"

- Read previous snapshot from `data/state/symlink-snapshot.prev.json`
- Compare with current: which entries appeared/changed/disappeared
- Pretty-print as delta

### F3. README.md
Currently missing. Document:
- What `winos` does (symlink orchestrator)
- How to install (clone repo, edit `data/data.json`, run `apply`)
- Architecture (state-probe model)
- Configuration reference

## State-probe enhancements

### F4. Isolate method state probing
Currently `isolate` entries (EqualizerAPO) are skipped by state-probe. Extend `Get-SymlinkEntryState` to:
- Probe `HKLM:\SOFTWARE\EqualizerAPO\ConfigPath` for EqualizerAPO
- Probe VST link state
- Probe ACL state
- Categorize: `noop` / `deploy` / `clean` / `repair-acl`

This will allow `EqualizerAPO` to be fully state-aware.

### F5. Per-mapping enabled flag
Currently `enabled` is on the entry. For entries with mappings, individual mappings might need different enable state.

```json
{
  "name": "AIMP",
  "enabled": true,
  "mappings": [
    { "from": "AIMP.ini", "to": "AIMP.ini", "enabled": true },
    { "from": "CDDB.db", "to": "CDDB.db", "enabled": false }
  ]
}
```

Backward-compat: missing `enabled` defaults to parent's `enabled`.

### F6. Backward compat alias
Old imperative actions (`deploy`, `clean`, `redeploy`) are gone. Add as aliases:
- `deploy` = plan + apply (skip drop)
- `clean` = apply with all entries enabled=false
- `redeploy` = clean + deploy

This helps migration for users familiar with old syntax.

## Architecture / quality

### F7. Move common to module
`src/modules/common/State.ps1` has ~411 LOC. It mixes probing, comparison, application, formatting. Split:
- `src/modules/common/State/Probe.ps1` — probe functions
- `src/modules/common/State/Compare.ps1` — compare + categorize
- `src/modules/common/State/Apply.ps1` — apply + format

Or keep one file but add structured sections.

### F8. CI integration
Add `.gitea/workflows/lint-test.yml` (or `.github/workflows/`):
- trigger: push to `dev`, PR to `master`
- steps: PSScriptAnalyzer, Pester

### F9. Drift detection exit code
`snapshot.ps1 -Plan` should exit 1 if drift/conflict detected (for CI):
```powershell
if ($summary.replace -gt 0 -or $summary.conflict -gt 0) { exit 1 }
```

### F10. Logging / audit
Add log file output for `apply`:
- `data/state/apply-YYYY-MM-DD.log`
- Includes: timestamp, action, from, to, status, error
- Rotating by date

## Tests

### F11. Integration tests for symlink-manager.ps1
Currently only smoke tests. Add:
- Test with real temp directory: create entry, run apply, verify symlink
- Test enabled=false: run apply, verify deletion
- Test archive: verify skip
- Test drift: pre-create wrong symlink, verify skip + warn

### F12. Tests for EqualizerAPO
Add tests for `data/isolate/EqualizerAPO.ps1`:
- Argument validation (no From, no To)
- Action routing (deploy, clean, redeploy)
- ShouldProcess support

### F13. Pester configuration file
Add `tests/PesterConfig.psd1` or `.ps1` for shared settings (CI mode, output format).

## Documentation

### F14. Architecture overview
Document the system as a whole:
- `docs/architecture.md` — components, data flow, lifecycle
- Diagrams (ASCII or Mermaid)

### F15. Configuration reference
Document `data/data.json` schema:
- `docs/config-reference.md` — every field, allowed values, examples

### F16. Changelog
Add `CHANGELOG.md` with versions and major changes.

## Refactoring (older ideas, lower priority)

### F17. Replace `Resolve-Path` calls with normalized paths
Currently some paths use `..` or have inconsistent casing. Normalize everywhere.

### F18. Configuration validation
Add `scripts/validate-config.ps1`:
- Check all entries have `name`, `enabled`, `from`, `to`
- Verify paths expand correctly
- Detect duplicates
- Run in CI

### F19. Scoop manifest management
`bucket/` has JSON manifests. Add:
- `scripts/update-bucket.ps1` to bump versions
- Validate JSON schema

## Status legend

| Symbol | Meaning |
|---|---|
| ✅ done | merged to `dev` |
| 🔧 in progress | currently being worked on |
| 📋 planned | documented but not started |
| 💡 idea | not yet prioritized |

## Priority order (recommended)

1. **F1** `--force` flag (most asked feature)
2. **F3** README.md (lowest barrier for new users)
3. **F8** CI integration (catches regressions)
4. **F4** Isolate method state probing (completes the state model)
5. **F11** Integration tests (validate behavior)
6. **F2** Snapshot diff (audit)
7. **F9** Drift detection exit code (CI readiness)
8. Other items as needed

## Estimated effort

| Bucket | Effort |
|---|---|
| Quick wins (F1-F3) | 3-5 hours |
| State enhancements (F4-F6) | 8-12 hours |
| Architecture (F7-F9) | 6-10 hours |
| Tests (F11-F13) | 6-8 hours |
| Documentation (F14-F16) | 4-6 hours |
| **Total backlog** | **~30-45 hours** |