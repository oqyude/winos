# Session Summary

**Session:** {{ session_id }}
**Target:** {{ target_repo }}
**Depth:** {{ depth }}
**Date:** {{ date }}

## Configuration

| Функция | Статус |
|---|---|
| ADR | {{ adr_enabled }} |
| Alternative Architecture | {{ alt_arch_enabled }} |
| Red Team | {{ red_team_enabled }} |
| Risk Register | {{ risk_register_enabled }} |
| Invariant Tests | {{ invariant_tests_enabled }} |
| Layer Structure | {{ layer_structure_enabled }} |

## Phase Status

| Phase | Status |
|---|---|
| ANALYSIS | {{ analysis_status }} |
| DESIGN | {{ design_status }} |
| RED_TEAM | {{ red_team_status }} |
| DECOMPOSITION | {{ decomposition_status }} |
| SETUP | {{ setup_status }} |
| HANDOFF | {{ handoff_status }} |

## Quick Links

- Task Manifest: `.agent/task-manifest.json`
- Handoff Summary: `.agent/handoff-summary.md`
- Design Report: `.agent/analysis-report.md`
- ADR: `.agent/layer-1/adr/` (если есть)
