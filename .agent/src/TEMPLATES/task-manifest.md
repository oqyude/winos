# Task Manifest

**Session:** {{ session_id }}
**Goal:** {{ goal }}
**Date:** {{ timestamp }}

---

## Task Overview

| ID | Title | Type | Depends On | Status |
|---|---|---|---|---|
| T1 | {{ title }} | {{ type }} | — | pending |
| T2 | {{ title }} | {{ type }} | T1 | pending |

**Total tasks:** {{ count }}

---

## Task Details

### T1: {{ title }}

**Type:** {{ type }}
**Description:** {{ description }}

**Files:**
- `{{ file_path }}`

**Depends on:** —

**Acceptance Criteria:**
- [ ] {{ criterion }}
- [ ] {{ criterion }}

**Context:** {{ context }}

---

### T2: {{ title }}

...
