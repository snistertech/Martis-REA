---
name: martis-rea
description: Start, resume, and preserve reusable evidence-led REA investigations for programs, managed apps, Electron/JavaScript, APKs, archives, firmware, websites, browser runtimes, and captures. Use when asked to run MARTIS, create an REA project/session, continue saved reverse-engineering evidence, or analyze a shipped target with portable handoff state. Do not use for ordinary source-only repository analysis.
---

# MARTIS REA

MARTIS stores portable investigation state in the repository's `.session\<name>` directory so Codex, Claude Code, or another capable agent can continue from evidence rather than conversation memory.

## Invocation

Interpret these forms equivalently:

- `MARTIS start <name>`
- `MARTIS resume <name> <goal>`
- `MARTIS status <name>`
- `MARTIS import-codex <name> -SessionFile <rollout.jsonl> -From <date> -To <date>`
- `MARTIS init` creates `.martis` in the current project.
- `MARTIS rea <goal>` resumes the nearest project workshop.
- `MARTIS export` and `MARTIS import` move a workshop between computers.
- Codex: `$martis-rea ...`
- Claude Code: `/martis-rea ...`

When a required value is absent, ask only for that value. A new session needs a session name, workspace directory, target, and optional initial goal. An empty goal means baseline identification and routing only.

## Session command

Resolve the repository root two directories above this skill, then create or update sessions with its deterministic script:

```powershell
& '<repository-root>\martis.ps1' start <name> -Workspace '<directory>' -Target '<artifact-or-url>' -Goal '<goal>'
& '<repository-root>\martis.ps1' resume <name> -Goal '<next goal>'
& '<repository-root>\martis.ps1' init -Workspace '<project-directory>'
& '<repository-root>\martis.ps1' rea -Workspace '<project-directory>' -Goal '<next goal>'
```

Prefer a project-local `.martis` workshop when one exists. Search from the current directory upward. Use global `.session\<name>` state for named legacy sessions and Codex transcript imports.

Add `-Agent codex -Run` or `-Agent claude -Run` only when explicitly asked to launch another agent. Otherwise prepare/update the session and perform the work in the current agent.

## Workflow

1. Read `SESSION.json`, `STATE.md`, `REQUEST.md`, `EVIDENCE.md`, and `TODO.md`.
   For imported Codex sessions, read `CONTINUATION.md`, `DECISIONS.md`, and `WORKSPACES.md`, then search `TIMELINE.md` narrowly for the active task.
2. Read `references/routing.md` when choosing the first REA operation.
3. Verify target identity. A changed local-file hash starts a new build record.
4. Reuse matching evidence before repeating expensive analysis.
5. Use the REA skill and available REA tools, summary-first and question-driven.
6. Separate Observed, Derived, Inferred, and Unknown claims. Preserve Evidence IDs, locations, authority, coverage, limitations, and artifact hashes.
7. Redact credentials, tokens, cookies, license material, catalog keys, and device identifiers.
8. Save durable findings with `scripts/save-finding.ps1` or update session Markdown directly.
9. Export reusable REA evidence bundles into `artifacts` when supported and useful.
10. Close active native REA sessions at completion.

## Completion contract

- Update `STATE.md` with status and exact next action.
- Append supported claims to `EVIDENCE.md`.
- Mark `TODO.md` questions answered, partial, or unresolved.
- Store wrapper-launched traces and final messages under `runs`.
- Keep requested unresolved questions visible.

