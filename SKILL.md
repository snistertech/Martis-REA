---
name: martis-rea
description: Start, resume, and preserve evidence-led REA investigations for shipped programs, managed apps, Electron/JavaScript, APKs, archives, firmware, websites, browser runtimes, and captures. Use for MARTIS sessions and portable reverse-engineering handoffs; skip ordinary source-only repository analysis.
---

# MARTIS REA

Keep durable investigation state in `.session/<name>` beneath this installed skill so another compatible agent can continue from evidence rather than chat history.

## Invocation

Treat these forms equivalently:

- `MARTIS start <name>`
- `MARTIS resume <name> <goal>`
- `MARTIS status <name>`
- Codex: `$martis-rea ...`
- Claude Code: `/martis-rea ...`

A new session needs a session name, workspace directory, target, and optional initial goal. An empty goal means baseline identification and routing only.

## Session command

Resolve this skill directory first, then run its `martis.ps1`:

```powershell
& '<installed-skill-directory>\martis.ps1' start <name> -Workspace '<directory>' -Target '<artifact-or-url>' -Goal '<goal>'
& '<installed-skill-directory>\martis.ps1' resume <name> -Goal '<next goal>'
```

Add `-Agent codex -Run` or `-Agent claude -Run` only when explicitly requested.

## Workflow

1. Read the session's `SESSION.json`, `STATE.md`, `REQUEST.md`, `EVIDENCE.md`, and `TODO.md`.
2. Read [references/routing.md](references/routing.md) before choosing the first REA operation.
3. Verify target identity; treat a changed local-file hash as a new build record.
4. Reuse matching evidence before repeating expensive analysis.
5. Use available REA tools summary-first and question-driven.
6. Separate Observed, Derived, Inferred, and Unknown claims. Preserve evidence IDs, locations, coverage, limitations, and artifact hashes.
7. Redact credentials, tokens, cookies, license material, catalog keys, and device identifiers.
8. Save findings with `scripts/save-finding.ps1` or update the session Markdown directly.
9. Store reusable REA evidence bundles under `artifacts` when useful.
10. Close active native REA sessions at completion.

## Completion

- Update `STATE.md` with status and exact next action.
- Append supported claims to `EVIDENCE.md`.
- Mark `TODO.md` questions answered, partial, or unresolved.
- Store wrapper-launched traces and final messages under `runs`.

