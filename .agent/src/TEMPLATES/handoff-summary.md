# Handoff Summary

## Session Info

- **Session ID:** `{{ session_id }}`
- **Target Repo:** {{ target_repo }}
- **Goal:** {{ goal }}
- **Date:** {{ date }}
- **Project type:** {{ project_type }}

## Repo Summary

{{ repo_summary }}

## Artifacts Created

- **Analysis report:** `.agent/context/analysis-report.md`
- **Project state:** `.agent/context/project-state.md`
- **Design report:** {{ design_report_path_or_dash }}
- **Roadmap:** `.agent/roadmap/sources.md`
- **ADR:** {{ adr_summary_or_dash }}
- **Risk Register:** {{ risk_register_path_or_dash }}
- **Red Team Report:** {{ red_team_report_path_or_dash }}

## Environment Status

- **Build:** {{ build_status }}
- **Tests:** {{ tests_passed }}/{{ tests_total }} passed
- **Baseline log:** `.agent/context/baseline-test-report.log`
- **Dependencies:** {{ deps_status }}

## Task Overview

| Status | Count |
|---|---|
| Total | {{ total }} |
| Pending | {{ pending }} |
| In Progress | {{ in_progress }} |
| Completed | {{ completed }} |
| Archived | {{ archived }} |
| Failed/Skipped | {{ failed }} |

## Tasks (ordered)

{{ task_list_markdown }}

## Next Steps

Следующий агент: прочитай `.agent/context/project-state.md`, затем `.agent/tasks/manifest.json` и приступай к первой `pending` задаче.

## Caveats

{{ caveats_list }}

## Checkpoints

Файл: `.agent/checkpoints.json` — состояние фаз и список задач.
