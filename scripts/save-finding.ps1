# PowerShell, file: save-finding.ps1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SessionPath,
    [Parameter(Mandatory)][ValidateSet('Observed', 'Derived', 'Inferred', 'Unknown')][string]$Status,
    [Parameter(Mandatory)][string]$Claim,
    [Parameter(Mandatory)][string]$Evidence,
    [string]$Locations = 'Not recorded',
    [string]$Coverage = 'Not recorded',
    [string]$Limitations = 'None recorded',
    [string]$NextAction = 'None'
)

$ErrorActionPreference = 'Stop'
$resolved = (Resolve-Path -LiteralPath $SessionPath).Path
$evidence_path = Join-Path $resolved 'EVIDENCE.md'
if (-not (Test-Path -LiteralPath $evidence_path -PathType Leaf)) {
    throw "Not a MARTIS session: $resolved"
}

$stamp = [DateTimeOffset]::Now.ToString('yyyy-MM-dd HH:mm:ss zzz')
$entry = @"

## $stamp - $Status

- Claim: $Claim
- Evidence: $Evidence
- Locations: $Locations
- Coverage: $Coverage
- Limitations: $Limitations
- Next action: $NextAction
"@
Add-Content -LiteralPath $evidence_path -Value $entry -Encoding UTF8
Write-Output $evidence_path
