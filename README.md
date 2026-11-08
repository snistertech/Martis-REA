# MARTIS REA

MARTIS is a reusable evidence-session layer for REA investigations. It works with local native/managed programs, Electron/JavaScript, APKs, archives, firmware, websites, open browser runtimes, and retained captures.

## Install from GitHub

Clone and install the command plus Codex/Claude skill links:

```powershell
git clone https://github.com/snistertech/Martis-REA.git "$HOME\Martis-REA"
& "$HOME\Martis-REA\install.ps1"
```

Open a new PowerShell window. The short command is then available:

```powershell
martis start test
```

## Project-local workshops

Open a terminal inside any project and initialize its durable workshop:

```powershell
cd 'C:\work\target-project'
martis init
martis rea -Goal 'Map the shipped application and preserve evidence'
```

MARTIS creates `.martis` in that project. Later Codex or Claude sessions can run `martis rea` from the same project or any child directory. The nearest parent `.martis` workshop is selected automatically.

Initialize a project from an existing global MARTIS session:

```powershell
martis init -SourceSession borneo-workshop
```

Inspect the current project workshop:

```powershell
martis status
```

Create a portable pack and import it on another computer:

```powershell
martis export -Output 'D:\transfer\target-project.martis.zip'

cd 'C:\work\target-project'
martis import 'D:\transfer\target-project.martis.zip'
martis rea -Goal 'Continue the current investigation'
```

The project files and `.martis` directory together provide the portable continuation. The original Codex rollout remains the authoritative conversation archive when the workshop was built from an imported thread.

Codex skill-only installation using the built-in third-party installer:

```powershell
py "$HOME\.codex\skills\.system\skill-installer\scripts\install-skill-from-github.py" `
  --repo snistertech/Martis-REA --path . --name martis-rea
```

Restart Codex after a skill-only installation. That method provides `$martis-rea`; run `install.ps1` when the global `martis` PowerShell command and Claude Code link are also wanted.

## Three values

- **Session name** chooses the durable folder: `.session/<name>`.
- **Workspace** is where source code, reconstruction work, or requested output belongs.
- **Target** is the shipped artifact, URL, runtime, or capture being investigated.

They may point to different places. MARTIS evidence always stays in this library.

## Command line

Interactive start:

```powershell
martis start test
```

Prepared start:

```powershell
& 'C:\Users\Administrator\Desktop\Martis REA\martis.ps1' start test `
  -Workspace 'C:\work\test' `
  -Target 'C:\Program Files\Example\app.exe' `
  -Goal 'Build a baseline feature and network map'
```

Start and launch an agent:

```powershell
& 'C:\Users\Administrator\Desktop\Martis REA\martis.ps1' start test `
  -Workspace 'C:\work\test' `
  -Target 'https://example.test' `
  -Agent codex -Run
```

Continue later:

```powershell
& 'C:\Users\Administrator\Desktop\Martis REA\martis.ps1' resume test `
  -Goal 'Trace the login request and record the evidence' `
  -Agent claude -Run
```

Inspect saved state:

```powershell
& 'C:\Users\Administrator\Desktop\Martis REA\martis.ps1' status test
```

Import a dated portion of a Codex thread as portable continuation state:

```powershell
martis import-codex borneo-workshop `
  -SessionFile "$HOME\.codex\sessions\2026\10\28\rollout-THREAD.jsonl" `
  -From '2026-10-28' `
  -To '2026-11-05' `
  -Force `
  -Workspace 'C:\Borneo Schematics'

martis resume borneo-workshop -Goal 'Continue the current task'
```

The date range uses local calendar dates and includes the entire `-To` day. The importer retains user/assistant dialogue, redacts common credential forms, replaces image payloads with markers, and creates `CONTINUATION.md`, `TIMELINE.md`, `DECISIONS.md`, and `WORKSPACES.md`. Keep the original Codex rollout JSONL as the authoritative archive.

## Agent commands

- Codex: `$martis-rea start test`
- Claude Code: `/martis-rea start test`

Both use the same master skill and `.session` tree. A new agent reads the files instead of depending on old chat history.

## Session contents

```text
.session/test/
  SESSION.json
  STATE.md
  REQUEST.md
  EVIDENCE.md
  TODO.md
  AGENT_PROMPT.md
  CONTINUATION.md
  TIMELINE.md
  DECISIONS.md
  WORKSPACES.md
  artifacts/
  runs/
```

Raw captures and exported REA bundles belong under `artifacts`. Agent JSONL and final messages belong under `runs`. Credentials, cookies, tokens, license material, and device identifiers never belong in session Markdown.

