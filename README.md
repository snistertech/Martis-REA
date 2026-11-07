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
  artifacts/
  runs/
```

Raw captures and exported REA bundles belong under `artifacts`. Agent JSONL and final messages belong under `runs`. Credentials, cookies, tokens, license material, and device identifiers never belong in session Markdown.

