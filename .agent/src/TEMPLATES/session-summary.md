# Session Summary

**Session:** {{ session_id }}
**Target:** {{ target_repo }}
**MetaAgent version:** {{ version }}
**Date:** {{ date }}

## Phase Status

| Phase | Status |
|---|---|
| INIT | {{ init_status }} |
| ANALYSE | {{ analyse_status }} |
| ROADMAP | {{ roadmap_status }} |
| DESIGN | {{ design_status }} |
| DECOMPOSITION | {{ decomposition_status }} |
| EXECUTION | {{ execution_status }} |
| METASTATE | {{ metastate_status }} |
| HANDOFF | {{ handoff_status }} |

## Tasks

| Status | Count |
|---|---|
| Total | {{ total }} |
| Pending | {{ pending }} |
| In Progress | {{ in_progress }} |
| Completed | {{ completed }} |
| Archived | {{ archived }} |
| Failed/Skipped | {{ failed }} |

**By origin:**
- user:direct: {{ user_direct_count }}
- roadmap: {{ roadmap_count }}
- adr: {{ adr_count }}
- decomposition: {{ decomposition_count }}
- (другое): {{ other_count }}

## Commands Invoked (если были)

{{ commands_invoked_list }}

## Quick Links

- Task Manifest: `.agent/tasks/manifest.json`
- Handoff Summary: `.agent/handoff-summary.md`
- Project State: `.agent/context/project-state.md`
- ADR: `.agent/decisions/`
- Risk Register: `.agent/context/risk-register.md`
- Red Team Report: `.agent/context/red-team-report.md`
