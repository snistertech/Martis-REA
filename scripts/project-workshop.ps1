# PowerShell, file: project-workshop.ps1, target: Windows PowerShell 5.1+
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('init', 'rea', 'status', 'export', 'import')][string]$Command,
    [string]$Name,
    [string]$Workspace,
    [string]$Target,
    [string]$Goal,
    [ValidateSet('none', 'codex', 'claude')][string]$Agent = 'none',
    [switch]$Run,
    [string]$Output,
    [string]$InputPath,
    [string]$SourceSession,
    [switch]$Force,
    [Parameter(Mandatory = $true)][string]$BrainRoot
)

$ErrorActionPreference = 'Stop'

if ($Command -eq 'rea' -and [string]::IsNullOrWhiteSpace($Goal) -and -not [string]::IsNullOrWhiteSpace($Name)) {
    $Goal = $Name
    $Name = $null
}

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    $utf8 = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, $Content, $utf8)
}

function Get-SafeName([string]$Value, [string]$Fallback) {
    if ([string]::IsNullOrWhiteSpace($Value)) { $Value = $Fallback }
    $slug = $Value.Trim().ToLowerInvariant() -replace '[^a-z0-9._-]+', '-'
    $slug = $slug.Trim('-', '.')
    if ([string]::IsNullOrWhiteSpace($slug)) { throw 'Workshop name must contain a letter or number.' }
    return $slug
}

function Resolve-Workspace([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { $Value = (Get-Location).Path }
    if (-not (Test-Path -LiteralPath $Value -PathType Container)) { throw "Workspace not found: $Value" }
    return (Resolve-Path -LiteralPath $Value).Path
}

function Find-Workshop([string]$Start) {
    $cursor = Get-Item -LiteralPath (Resolve-Workspace $Start)
    while ($null -ne $cursor) {
        $candidate = Join-Path $cursor.FullName '.martis'
        if (Test-Path -LiteralPath (Join-Path $candidate 'SESSION.json') -PathType Leaf) { return $candidate }
        $cursor = $cursor.Parent
    }
    return $null
}

function Get-TargetIdentity([string]$Value) {
    if (Test-Path -LiteralPath $Value -PathType Leaf) {
        $item = Get-Item -LiteralPath $Value
        return [ordered]@{ kind = 'file'; path = $item.FullName; size = $item.Length; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $item.FullName).Hash.ToLowerInvariant() }
    }
    if (Test-Path -LiteralPath $Value -PathType Container) { return [ordered]@{ kind = 'directory'; path = (Resolve-Path -LiteralPath $Value).Path } }
    $uri = $null
    if ([Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri) -and $uri.Scheme -in @('http', 'https')) { return [ordered]@{ kind = 'url'; url = $uri.AbsoluteUri } }
    return [ordered]@{ kind = 'runtime-or-description'; value = $Value }
}

function Save-Session([string]$Workshop, $Session) {
    $Session.updated_at = [DateTimeOffset]::Now.ToString('o')
    Write-Utf8NoBom (Join-Path $Workshop 'SESSION.json') ($Session | ConvertTo-Json -Depth 15)
}

function Write-AgentPrompt([string]$Workshop, $Session, [string]$RequestedGoal) {
    $prompt = @"
Use the MARTIS REA skill and continue this project workshop.

Workshop: $Workshop
Workspace: $($Session.workspace)
Target: $($Session.target_display)
Goal: $RequestedGoal

Read CONTINUATION.md, SESSION.json, STATE.md, REQUEST.md, EVIDENCE.md, DECISIONS.md, WORKSPACES.md, and TODO.md. Search TIMELINE.md only when historical dialogue is relevant. Reuse matching evidence, verify mutable facts, distinguish Observed/Derived/Inferred/Unknown, redact secrets, and update the durable files before finishing.
"@
    $path = Join-Path $Workshop 'AGENT_PROMPT.md'
    Write-Utf8NoBom $path $prompt
    return $path
}

function Assert-NoSecrets([string]$Directory) {
    $patterns = @(
        '(?i)authorization\s*:\s*bearer\s+[A-Za-z0-9._~+/=-]{12,}',
        '(?i)password\s*[:=]\s*\S+',
        '(?i)secret[_ -]?access[_ -]?key\s*[:=]\s*\S+',
        '(?i)api[_ -]?key\s*[:=]\s*[A-Za-z0-9._~+/=-]{12,}'
    )
    $files = Get-ChildItem -LiteralPath $Directory -File -Recurse | Where-Object { $_.Extension -in @('.md', '.json', '.jsonl', '.txt', '.log') }
    foreach ($file in $files) {
        $content = Get-Content -Raw -LiteralPath $file.FullName
        foreach ($pattern in $patterns) {
            if ($content -match $pattern) { throw "Possible secret blocks export: $($file.FullName)" }
        }
    }
}

function Invoke-Agent([string]$Workshop, $Session, [string]$PromptPath, [string]$SelectedAgent) {
    if ($SelectedAgent -eq 'none') { throw 'Choose -Agent codex or -Agent claude when using -Run.' }
    $stamp = [DateTimeOffset]::Now.ToString('yyyyMMdd-HHmmss')
    $trace = Join-Path $Workshop "runs\$stamp-$SelectedAgent.jsonl"
    $final = Join-Path $Workshop "runs\$stamp-$SelectedAgent-final.md"
    $prompt = Get-Content -Raw -LiteralPath $PromptPath
    if ($SelectedAgent -eq 'codex') {
        & codex exec --json --sandbox workspace-write --skip-git-repo-check -C $Session.workspace --add-dir $Workshop --output-last-message $final $prompt 2>&1 | Tee-Object -FilePath $trace
    } else {
        Push-Location $Session.workspace
        try { & claude -p --output-format stream-json --permission-mode acceptEdits --add-dir $Workshop $prompt 2>&1 | Tee-Object -FilePath $trace } finally { Pop-Location }
    }
    if ($LASTEXITCODE -ne 0) { throw "$SelectedAgent exited with code $LASTEXITCODE" }
}

if ($Command -eq 'init') {
    $workspace_path = Resolve-Workspace $Workspace
    $workshop = Join-Path $workspace_path '.martis'
    if (Test-Path -LiteralPath $workshop) { throw "Workshop already exists: $workshop" }

    if (-not [string]::IsNullOrWhiteSpace($SourceSession)) {
        $source = Join-Path (Join-Path $BrainRoot '.session') (Get-SafeName $SourceSession $SourceSession)
        if (-not (Test-Path -LiteralPath (Join-Path $source 'SESSION.json') -PathType Leaf)) { throw "Source session not found: $source" }
        Copy-Item -LiteralPath $source -Destination $workshop -Recurse
        $session = Get-Content -Raw -LiteralPath (Join-Path $workshop 'SESSION.json') | ConvertFrom-Json
        $session.workspace = $workspace_path
        $session.status = 'ready'
        Save-Session $workshop $session
        Add-Content -LiteralPath (Join-Path $workshop 'WORKSPACES.md') -Value "`r`n- Current imported workspace: $workspace_path`r`n" -Encoding UTF8
    } else {
        [IO.Directory]::CreateDirectory((Join-Path $workshop 'artifacts')) | Out-Null
        [IO.Directory]::CreateDirectory((Join-Path $workshop 'runs')) | Out-Null
        $fallback = Split-Path -Leaf $workspace_path
        $safe_name = Get-SafeName $Name $fallback
        if ([string]::IsNullOrWhiteSpace($Target)) { $Target = $workspace_path }
        if ([string]::IsNullOrWhiteSpace($Goal)) { $Goal = 'Baseline identification and routing only.' }
        $now = [DateTimeOffset]::Now.ToString('o')
        $session = [pscustomobject][ordered]@{ schema = 2; name = $safe_name; status = 'initialized'; created_at = $now; updated_at = $now; workspace = $workspace_path; target_display = $Target; target = (Get-TargetIdentity $Target); current_goal = $Goal; last_run = $null }
        Save-Session $workshop $session
        Write-Utf8NoBom (Join-Path $workshop 'STATE.md') "# State`r`n`r`n- Status: initialized`r`n- Current goal: $Goal`r`n- Exact next action: identify and route the target with REA.`r`n"
        Write-Utf8NoBom (Join-Path $workshop 'REQUEST.md') "# Request history`r`n`r`n## $([DateTimeOffset]::Now.ToString('yyyy-MM-dd HH:mm:ss zzz'))`r`n`r`n$Goal`r`n"
        Write-Utf8NoBom (Join-Path $workshop 'EVIDENCE.md') "# Evidence ledger`r`n`r`nNo findings recorded.`r`n"
        Write-Utf8NoBom (Join-Path $workshop 'DECISIONS.md') "# Decisions`r`n`r`nNo decisions recorded.`r`n"
        Write-Utf8NoBom (Join-Path $workshop 'TODO.md') "# Investigation questions`r`n`r`n- [ ] Pin the target identity.`r`n- [ ] Route the target to the correct REA workflow.`r`n- [ ] Record evidence and limitations.`r`n- [ ] Keep the exact next action current.`r`n"
        Write-Utf8NoBom (Join-Path $workshop 'WORKSPACES.md') "# Workspaces`r`n`r`n- Current workspace: $workspace_path`r`n"
        Write-Utf8NoBom (Join-Path $workshop 'TIMELINE.md') "# Timeline`r`n`r`nNo imported dialogue.`r`n"
        Write-Utf8NoBom (Join-Path $workshop 'CONTINUATION.md') "# Continuation context`r`n`r`nThis project owns its MARTIS workshop. Read the durable files, reuse evidence, verify mutable facts, and update the workshop before finishing.`r`n"
    }
    $prompt_path = Write-AgentPrompt $workshop $session $session.current_goal
    Write-Output "Project workshop: $workshop"
    Write-Output "Agent prompt: $prompt_path"
    exit 0
}

if ($Command -eq 'import') {
    $workspace_path = Resolve-Workspace $Workspace
    $workshop = Join-Path $workspace_path '.martis'
    if ([string]::IsNullOrWhiteSpace($InputPath)) { $InputPath = $Name }
    if ([string]::IsNullOrWhiteSpace($InputPath) -or -not (Test-Path -LiteralPath $InputPath -PathType Leaf)) { throw "Pack not found: $InputPath" }
    if (Test-Path -LiteralPath $workshop) { throw "Workshop already exists: $workshop" }
    $temp = Join-Path ([IO.Path]::GetTempPath()) ("martis-import-" + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($temp) | Out-Null
    try {
        Expand-Archive -LiteralPath $InputPath -DestinationPath $temp
        $session_file = Join-Path $temp 'SESSION.json'
        if (-not (Test-Path -LiteralPath $session_file -PathType Leaf)) { throw 'Invalid MARTIS pack: SESSION.json is missing from the archive root.' }
        Move-Item -LiteralPath $temp -Destination $workshop
        [IO.Directory]::CreateDirectory((Join-Path $workshop 'artifacts')) | Out-Null
        [IO.Directory]::CreateDirectory((Join-Path $workshop 'runs')) | Out-Null
        $session = Get-Content -Raw -LiteralPath (Join-Path $workshop 'SESSION.json') | ConvertFrom-Json
        $session.workspace = $workspace_path
        $session.status = 'ready'
        Save-Session $workshop $session
        Add-Content -LiteralPath (Join-Path $workshop 'WORKSPACES.md') -Value "`r`n- Current imported workspace: $workspace_path`r`n" -Encoding UTF8
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
    }
    Write-Output "Imported project workshop: $workshop"
    exit 0
}

$workshop = Find-Workshop $Workspace
if ($Command -eq 'export' -and -not [string]::IsNullOrWhiteSpace($Name)) {
    $named = Join-Path (Join-Path $BrainRoot '.session') (Get-SafeName $Name $Name)
    if (Test-Path -LiteralPath (Join-Path $named 'SESSION.json') -PathType Leaf) { $workshop = $named }
}
if ($null -eq $workshop) { throw 'No .martis workshop found. Run martis init in the project directory.' }
$session = Get-Content -Raw -LiteralPath (Join-Path $workshop 'SESSION.json') | ConvertFrom-Json

if ($Command -eq 'status') {
    $session | ConvertTo-Json -Depth 15
    Get-Content -Raw -LiteralPath (Join-Path $workshop 'STATE.md')
    exit 0
}

if ($Command -eq 'export') {
    Assert-NoSecrets $workshop
    if ([string]::IsNullOrWhiteSpace($Output)) {
        $base = Get-SafeName $session.name 'martis-workshop'
        $Output = Join-Path (Split-Path -Parent $session.workspace) "$base.martis.zip"
    }
    $output_path = [IO.Path]::GetFullPath($Output)
    if (Test-Path -LiteralPath $output_path) {
        if (-not $Force) { throw "Export already exists: $output_path. Add -Force to replace it." }
        Remove-Item -LiteralPath $output_path -Force
    }
    Compress-Archive -Path (Join-Path $workshop '*') -DestinationPath $output_path -CompressionLevel Optimal
    Write-Output "MARTIS pack: $output_path"
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Goal)) { $Goal = [string]$session.current_goal }
$session.current_goal = $Goal
$session.status = 'active'
Save-Session $workshop $session
Add-Content -LiteralPath (Join-Path $workshop 'REQUEST.md') -Value "`r`n## $([DateTimeOffset]::Now.ToString('yyyy-MM-dd HH:mm:ss zzz'))`r`n`r`n$Goal`r`n" -Encoding UTF8
Write-Utf8NoBom (Join-Path $workshop 'STATE.md') "# State`r`n`r`n- Status: active`r`n- Current goal: $Goal`r`n- Exact next action: continue from the recorded evidence and update this workshop.`r`n"
$prompt_path = Write-AgentPrompt $workshop $session $Goal
Write-Output "Project workshop: $workshop"
Write-Output "Agent prompt: $prompt_path"
if ($Run) { Invoke-Agent $workshop $session $prompt_path $Agent }

