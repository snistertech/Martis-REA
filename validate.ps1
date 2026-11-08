# PowerShell, file: validate.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$required = @(
    'README.md',
    'SKILL.md',
    'agents\openai.yaml',
    'install.ps1',
    'martis.ps1',
    'references\routing.md',
    'scripts\save-finding.ps1',
    'scripts\import-codex-session.ps1',
    'scripts\project-workshop.ps1',
    'martis.cmd',
    'skills\martis-rea\SKILL.md',
    'skills\martis-rea\references\routing.md',
    'skills\martis-rea\scripts\save-finding.ps1'
)

foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf)) {
        throw "Missing MARTIS file: $relative"
    }
}

$secret_patterns = @(
    '(?i)authorization\s*:\s*bearer\s+[A-Za-z0-9._~+/=-]{12,}',
    '(?i)password\s*[:=]\s*\S+',
    '(?i)secret[_ -]?access[_ -]?key\s*[:=]\s*\S+',
    '(?i)api[_ -]?key\s*[:=]\s*[A-Za-z0-9._~+/=-]{12,}'
)

$text_files = Get-ChildItem -LiteralPath $root -File -Recurse | Where-Object { $_.Extension -in @('.md', '.json', '.ps1', '.cmd') }
foreach ($file in $text_files) {
    $content = Get-Content -Raw -LiteralPath $file.FullName
    foreach ($pattern in $secret_patterns) {
        if ($content -match $pattern) { throw "Possible secret in $($file.FullName)" }
    }
}

Write-Output "MARTIS validation passed: $($required.Count) required files."

