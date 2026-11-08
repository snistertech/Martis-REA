# PowerShell, file: import-codex-session.ps1, target: Windows PowerShell 5.1+
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$SessionFile,
    [Parameter(Mandatory = $true)][datetime]$From,
    [Parameter(Mandatory = $true)][datetime]$To,
    [Parameter(Mandatory = $true)][string]$SessionRoot,
    [string]$Workspace = (Get-Location).Path,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, $Content, $utf8)
}

function Get-SharedSha256([string]$Path) {
    $stream = New-Object IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash($stream)
        return ([BitConverter]::ToString($bytes) -replace '-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
        $stream.Dispose()
    }
}

function Redact-Text([string]$Text) {
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $value = $Text
    $patterns = @(
        '(?im)(password\s*[:=]\s*)[^\s\r\n]+',
        '(?im)(secret(?:\s+access)?\s*key\s*[:=]\s*)[^\s\r\n]+',
        '(?im)(access\s+key(?:\s+id)?\s*[:=]\s*)[^\s\r\n]+',
        '(?im)(api\s*key\s*[:=]\s*)[^\s\r\n]+',
        '(?im)(token(?:\s+value)?\s*[:=]\s*)[^\s\r\n]+',
        '(?i)Bearer\s+[A-Za-z0-9._~+\-/]+=*',
        '(?i)cfat_[A-Za-z0-9_-]+',
        '(?i)AKIA[0-9A-Z]{16}'
    )
    foreach ($pattern in $patterns) {
        $value = [regex]::Replace($value, $pattern, {
            param($match)
            if ($match.Groups.Count -gt 1 -and $match.Groups[1].Success) {
                $label = $match.Groups[1].Value -replace '[:=]\s*$', ''
                return $label + ' [REDACTED]'
            }
            return '[REDACTED]'
        })
    }
    return $value
}

function Get-MessageText($Payload) {
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($part in @($Payload.content)) {
        if ($part.type -in @('input_text', 'output_text', 'text') -and $null -ne $part.text) {
            $parts.Add([string]$part.text)
        } elseif ($part.type -in @('input_image', 'image')) {
            $parts.Add('[image attachment omitted; inspect the original thread when pixels are required]')
        }
    }
    return ($parts -join "`r`n")
}

if ($To.Date -lt $From.Date) { throw '-To must be the same day as or later than -From.' }
if (-not (Test-Path -LiteralPath $SessionFile -PathType Leaf)) { throw "Codex session file not found: $SessionFile" }
if (-not (Test-Path -LiteralPath $Workspace -PathType Container)) { throw "Workspace not found: $Workspace" }

$safe_name = $Name.Trim().ToLowerInvariant() -replace '[^a-z0-9._-]+', '-'
$safe_name = $safe_name.Trim('-', '.')
if ([string]::IsNullOrWhiteSpace($safe_name)) { throw 'Session name must contain a letter or number.' }

$destination = Join-Path $SessionRoot $safe_name
if ((Test-Path -LiteralPath $destination) -and (Test-Path -LiteralPath (Join-Path $destination 'SESSION.json')) -and -not $Force) {
    throw "Session '$safe_name' already exists: $destination"
}
[IO.Directory]::CreateDirectory((Join-Path $destination 'artifacts')) | Out-Null
[IO.Directory]::CreateDirectory((Join-Path $destination 'runs')) | Out-Null

$messages = New-Object System.Collections.Generic.List[object]
$source_stream = New-Object IO.FileStream($SessionFile, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
$reader = New-Object IO.StreamReader($source_stream)
try {
    while (-not $reader.EndOfStream) {
        $line = $reader.ReadLine()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $record = $line | ConvertFrom-Json } catch { continue }
        if ($record.type -ne 'response_item' -or $record.payload.type -ne 'message') { continue }
        if ($record.payload.role -notin @('user', 'assistant')) { continue }
        $stamp = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse([string]$record.timestamp, [ref]$stamp)) { continue }
        $local_date = $stamp.ToLocalTime().Date
        if ($local_date -lt $From.Date -or $local_date -gt $To.Date) { continue }
        $text = Redact-Text (Get-MessageText $record.payload)
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $messages.Add([pscustomobject][ordered]@{
            timestamp = $stamp.ToString('o')
            local_time = $stamp.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss zzz')
            role = [string]$record.payload.role
            text = $text.Trim()
        })
    }
} finally {
    $reader.Dispose()
    $source_stream.Dispose()
}

if ($messages.Count -eq 0) { throw 'No user or assistant messages matched the selected date range.' }

$artifact_path = Join-Path $destination 'artifacts\codex-dialogue.jsonl'
$json_lines = New-Object System.Collections.Generic.List[string]
foreach ($message in $messages) { $json_lines.Add(($message | ConvertTo-Json -Compress -Depth 8)) }
Write-Utf8NoBom $artifact_path (($json_lines -join "`r`n") + "`r`n")

$timeline = New-Object Text.StringBuilder
[void]$timeline.AppendLine('# Imported Codex timeline')
[void]$timeline.AppendLine()
[void]$timeline.AppendLine("- Range: $($From.ToString('yyyy-MM-dd')) through $($To.ToString('yyyy-MM-dd')) (local calendar dates, inclusive)")
[void]$timeline.AppendLine("- Source: $SessionFile")
[void]$timeline.AppendLine("- Messages: $($messages.Count)")
[void]$timeline.AppendLine('- Secrets were redacted and image payloads were replaced with markers.')
foreach ($message in $messages) {
    [void]$timeline.AppendLine()
    [void]$timeline.AppendLine("## $($message.local_time) - $($message.role)")
    [void]$timeline.AppendLine()
    [void]$timeline.AppendLine($message.text)
}
Write-Utf8NoBom (Join-Path $destination 'TIMELINE.md') $timeline.ToString()

$thread_id = $null
if ([regex]::IsMatch((Split-Path -Leaf $SessionFile), '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl$', 'IgnoreCase')) {
    $thread_id = [regex]::Match((Split-Path -Leaf $SessionFile), '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl$', 'IgnoreCase').Groups[1].Value
}

$now = [DateTimeOffset]::Now.ToString('o')
$session = [ordered]@{
    schema = 2
    name = $safe_name
    status = 'imported'
    created_at = $now
    updated_at = $now
    workspace = (Resolve-Path -LiteralPath $Workspace).Path
    target_display = "Codex thread $thread_id"
    target = [ordered]@{
        kind = 'codex-session-import'
        source_file = $SessionFile
        source_sha256 = Get-SharedSha256 $SessionFile
        thread_id = $thread_id
        from = $From.ToString('yyyy-MM-dd')
        to = $To.ToString('yyyy-MM-dd')
    }
    current_goal = 'Continue the imported workshop from durable evidence and recorded decisions.'
    last_run = $null
}
Write-Utf8NoBom (Join-Path $destination 'SESSION.json') ($session | ConvertTo-Json -Depth 12)
Write-Utf8NoBom (Join-Path $destination 'STATE.md') @"
# State

- Status: imported and ready to resume
- Current goal: Continue the imported workshop from durable evidence and recorded decisions.
- Exact next action: read CONTINUATION.md, then consult TIMELINE.md only for the relevant project or decision.
- Source thread: $thread_id
- Imported range: $($From.ToString('yyyy-MM-dd')) through $($To.ToString('yyyy-MM-dd'))
"@
Write-Utf8NoBom (Join-Path $destination 'REQUEST.md') @"
# Request history

## Imported history

Continue the Codex work recorded from $($From.ToString('yyyy-MM-dd')) through $($To.ToString('yyyy-MM-dd')). The chronological dialogue is in TIMELINE.md and the machine-readable copy is in artifacts/codex-dialogue.jsonl.
"@
Write-Utf8NoBom (Join-Path $destination 'EVIDENCE.md') @"
# Evidence ledger

## E-CODEX-001 — Imported dialogue

- Classification: Observed
- Authority: original local Codex rollout transcript
- Coverage: user and assistant message text from $($From.ToString('yyyy-MM-dd')) through $($To.ToString('yyyy-MM-dd'))
- Location: TIMELINE.md and artifacts/codex-dialogue.jsonl
- Limitation: tool payloads, hidden reasoning, binary attachments, and image pixels are excluded; secrets are redacted.
"@
Write-Utf8NoBom (Join-Path $destination 'TODO.md') @"
# Continuation questions

- [ ] Read CONTINUATION.md before beginning new work.
- [ ] Identify the active project named in the next request.
- [ ] Consult only the relevant TIMELINE.md entries.
- [ ] Move new durable findings into EVIDENCE.md.
- [ ] Keep STATE.md synchronized with the exact next action.
"@
Write-Utf8NoBom (Join-Path $destination 'DECISIONS.md') @"
# Decisions

This file is the durable decision register. Promote confirmed decisions from TIMELINE.md here when they become relevant to resumed work.
"@
Write-Utf8NoBom (Join-Path $destination 'WORKSPACES.md') @"
# Workspaces

- Primary imported workspace: $((Resolve-Path -LiteralPath $Workspace).Path)
- Historical paths remain in TIMELINE.md and must be verified on the current computer before editing.
"@
Write-Utf8NoBom (Join-Path $destination 'CONTINUATION.md') @"
# Continuation context

Resume MARTIS session **$safe_name** as a continuation of Codex thread **$thread_id**.

Read STATE.md, REQUEST.md, EVIDENCE.md, DECISIONS.md, WORKSPACES.md, and TODO.md first. Search TIMELINE.md for the project, path, error text, or feature named in the current request. Do not load the entire timeline unless the request spans multiple historical projects. Treat imported dialogue as historical context, verify mutable filesystem and runtime facts, reuse existing evidence, redact secrets, and update the durable files before finishing.
"@
Write-Utf8NoBom (Join-Path $destination 'AGENT_PROMPT.md') @"
Use the MARTIS REA skill and resume session **$safe_name**.

Session path: $destination
Workspace: $((Resolve-Path -LiteralPath $Workspace).Path)
Source thread: $thread_id

Read CONTINUATION.md and the durable session files before acting. Query TIMELINE.md narrowly for the current task. Continue from recorded state rather than restarting completed work. Update STATE.md, EVIDENCE.md, DECISIONS.md, and TODO.md before finishing.
"@

Write-Output "Imported MARTIS session: $destination"
Write-Output "Messages retained: $($messages.Count)"
Write-Output "Timeline: $(Join-Path $destination 'TIMELINE.md')"
Write-Output "Resume: martis resume $safe_name -Goal '<next task>'"
