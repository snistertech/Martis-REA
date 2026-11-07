# PowerShell, file: martis.ps1, target: Windows PowerShell 5.1+
[CmdletBinding()]
param(
    [Parameter(Position = 0)][ValidateSet('start', 'resume', 'status', 'prompt')][string]$Command = 'start',
    [Parameter(Position = 1)][string]$Name,
    [string]$Workspace,
    [string]$Target,
    [string]$Goal,
    [ValidateSet('none', 'codex', 'claude')][string]$Agent = 'none',
    [switch]$Run
)

$ErrorActionPreference = 'Stop'
$brain_root = Split-Path -Parent $MyInvocation.MyCommand.Path
$session_root = Join-Path $brain_root '.session'

function Get-SafeName([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { $Value = Read-Host 'Session name' }
    $slug = $Value.Trim().ToLowerInvariant() -replace '[^a-z0-9._-]+', '-'
    $slug = $slug.Trim('-', '.')
    if ([string]::IsNullOrWhiteSpace($slug)) { throw 'Session name must contain a letter or number.' }
    return $slug
}

function Get-TargetIdentity([string]$Value) {
    if (Test-Path -LiteralPath $Value -PathType Leaf) {
        $item = Get-Item -LiteralPath $Value
        return [ordered]@{
            kind = 'file'
            path = $item.FullName
            size = $item.Length
            modified = $item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $item.FullName).Hash.ToLowerInvariant()
        }
    }
    if (Test-Path -LiteralPath $Value -PathType Container) {
        return [ordered]@{ kind = 'directory'; path = (Resolve-Path -LiteralPath $Value).Path }
    }
    $uri = $null
    if ([Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri) -and $uri.Scheme -in @('http', 'https')) {
        return [ordered]@{ kind = 'url'; url = $uri.AbsoluteUri }
    }
    return [ordered]@{ kind = 'runtime-or-description'; value = $Value }
}

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, $Content, $utf8)
}

function Read-Session([string]$Path) {
    $json_path = Join-Path $Path 'SESSION.json'
    if (-not (Test-Path -LiteralPath $json_path -PathType Leaf)) { throw "Session not found: $Path" }
    return Get-Content -Raw -LiteralPath $json_path | ConvertFrom-Json
}

function Save-Session([string]$Path, $Session) {
    $Session.updated_at = [DateTimeOffset]::Now.ToString('o')
    Write-Utf8NoBom (Join-Path $Path 'SESSION.json') ($Session | ConvertTo-Json -Depth 12)
}

function New-AgentPrompt([string]$Path, $Session, [string]$RequestedGoal) {
    $prompt_path = Join-Path $Path 'AGENT_PROMPT.md'
    $text = @"
Use the MARTIS REA skill for this investigation.

Session: $($Session.name)
Session path: $Path
Workspace: $($Session.workspace)
Target: $($Session.target_display)
Goal: $RequestedGoal

Read SESSION.json, STATE.md, REQUEST.md, EVIDENCE.md, and TODO.md before producing analysis. Reuse matching evidence. Route the target with REA, distinguish Observed/Derived/Inferred/Unknown, preserve Evidence IDs and limitations, redact secrets, and update the session files before finishing. If this is baseline-only, identify and route the target, capture the smallest useful overview, then mark STATE.md ready_for_goal. Close active native REA sessions at completion.
"@
    Write-Utf8NoBom $prompt_path $text
    return $prompt_path
}

function Invoke-AgentRun([string]$Path, $Session, [string]$PromptPath, [string]$SelectedAgent) {
    $run_stamp = [DateTimeOffset]::Now.ToString('yyyyMMdd-HHmmss')
    $runs = Join-Path $Path 'runs'
    $trace = Join-Path $runs "$run_stamp-$SelectedAgent.jsonl"
    $final = Join-Path $runs "$run_stamp-$SelectedAgent-final.md"
    $prompt_text = Get-Content -Raw -LiteralPath $PromptPath

    if ($SelectedAgent -eq 'codex') {
        & codex exec --json --sandbox workspace-write --skip-git-repo-check -C $Session.workspace --add-dir $brain_root --output-last-message $final $prompt_text 2>&1 | Tee-Object -FilePath $trace
        if ($LASTEXITCODE -ne 0) { throw "Codex exited with code $LASTEXITCODE" }
    } elseif ($SelectedAgent -eq 'claude') {
        Push-Location $Session.workspace
        try {
            & claude -p --output-format stream-json --permission-mode acceptEdits --add-dir $brain_root --name "martis-$($Session.name)" $prompt_text 2>&1 | Tee-Object -FilePath $trace
            if ($LASTEXITCODE -ne 0) { throw "Claude exited with code $LASTEXITCODE" }
        } finally {
            Pop-Location
        }
        $result_line = Get-Content -LiteralPath $trace | Select-Object -Last 1
        Write-Utf8NoBom $final $result_line
    }

    $Session.last_run = [pscustomobject][ordered]@{
        agent = $SelectedAgent
        trace = $trace
        final = $final
        completed_at = [DateTimeOffset]::Now.ToString('o')
    }
    Save-Session $Path $Session
}

$slug = Get-SafeName $Name
$path = Join-Path $session_root $slug

if ($Command -eq 'start') {
    if (Test-Path -LiteralPath $path) { throw "Session '$slug' already exists. Use: martis resume $slug" }
    if ([string]::IsNullOrWhiteSpace($Workspace)) { $Workspace = Read-Host 'Workspace/project directory' }
    if (-not (Test-Path -LiteralPath $Workspace -PathType Container)) { throw "Workspace directory not found: $Workspace" }
    $Workspace = (Resolve-Path -LiteralPath $Workspace).Path
    if ([string]::IsNullOrWhiteSpace($Target)) { $Target = Read-Host 'Target file, URL, open runtime, or capture' }
    if ([string]::IsNullOrWhiteSpace($Target)) { throw 'Target is required.' }
    if ($null -eq $Goal) { $Goal = Read-Host 'Initial goal (Enter for baseline analysis only)' }
    $identity = Get-TargetIdentity $Target

    New-Item -ItemType Directory -Path (Join-Path $path 'artifacts') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $path 'runs') -Force | Out-Null
    $session = [pscustomobject][ordered]@{
        schema = 1
        name = $slug
        status = 'initialized'
        created_at = [DateTimeOffset]::Now.ToString('o')
        updated_at = [DateTimeOffset]::Now.ToString('o')
        workspace = $Workspace
        target_display = $Target
        target = $identity
        current_goal = if ([string]::IsNullOrWhiteSpace($Goal)) { 'Baseline identification and routing only.' } else { $Goal }
        last_run = $null
    }
    Save-Session $path $session
    Write-Utf8NoBom (Join-Path $path 'STATE.md') "# State`r`n`r`n- Status: initialized`r`n- Current goal: $($session.current_goal)`r`n- Next action: run the MARTIS REA baseline or requested investigation.`r`n"
    Write-Utf8NoBom (Join-Path $path 'REQUEST.md') "# Request history`r`n`r`n## $([DateTimeOffset]::Now.ToString('yyyy-MM-dd HH:mm:ss zzz'))`r`n`r`n$($session.current_goal)`r`n"
    Write-Utf8NoBom (Join-Path $path 'EVIDENCE.md') "# Evidence ledger`r`n`r`nNo findings recorded.`r`n"
    Write-Utf8NoBom (Join-Path $path 'TODO.md') "# Investigation questions`r`n`r`n- [ ] Identify and pin the target.`r`n- [ ] Route the target to the correct REA workflow.`r`n- [ ] Answer the current goal with cited evidence.`r`n- [ ] Record limitations and the next evidence-producing action.`r`n"
    $prompt_path = New-AgentPrompt $path $session $session.current_goal
} else {
    $session = Read-Session $path
    if ($Command -eq 'status') {
        $session | ConvertTo-Json -Depth 12
        Get-Content -Raw -LiteralPath (Join-Path $path 'STATE.md')
        exit 0
    }
    if ($null -eq $Goal) { $Goal = Read-Host 'Next goal' }
    if ([string]::IsNullOrWhiteSpace($Goal)) { throw 'A resume goal is required.' }
    $session.current_goal = $Goal
    $session.status = 'active'
    Save-Session $path $session
    Write-Utf8NoBom (Join-Path $path 'STATE.md') "# State`r`n`r`n- Status: active`r`n- Current goal: $Goal`r`n- Next action: run the requested investigation and update the evidence ledger.`r`n"
    Add-Content -LiteralPath (Join-Path $path 'REQUEST.md') -Value "`r`n## $([DateTimeOffset]::Now.ToString('yyyy-MM-dd HH:mm:ss zzz'))`r`n`r`n$Goal`r`n" -Encoding UTF8
    $prompt_path = New-AgentPrompt $path $session $Goal
}

Write-Output "MARTIS session: $path"
Write-Output "Agent prompt: $prompt_path"
if ($Run) {
    if ($Agent -eq 'none') { throw 'Choose -Agent codex or -Agent claude when using -Run.' }
    Invoke-AgentRun $path $session $prompt_path $Agent
} else {
    Write-Output 'Prepared only. Continue in the current agent or add -Agent codex|claude -Run.'
}

