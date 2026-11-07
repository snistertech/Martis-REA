# PowerShell, file: install.ps1, target: Windows PowerShell 5.1+
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$skill_source = Join-Path $root 'skills\martis-rea'

if (-not (Test-Path -LiteralPath (Join-Path $skill_source 'SKILL.md') -PathType Leaf)) {
    throw "MARTIS skill is missing: $skill_source"
}

$skill_links = @(
    (Join-Path $env:USERPROFILE '.agents\skills\martis-rea'),
    (Join-Path $env:USERPROFILE '.codex\skills\martis-rea'),
    (Join-Path $env:USERPROFILE '.claude\skills\martis-rea')
)

foreach ($skill_link in $skill_links) {
    $parent = Split-Path -Parent $skill_link
    [System.IO.Directory]::CreateDirectory($parent) | Out-Null

    if (Test-Path -LiteralPath $skill_link) {
        $item = Get-Item -LiteralPath $skill_link -Force
        $current_target = [string]$item.Target
        if ($current_target -and ([System.IO.Path]::GetFullPath($current_target) -eq [System.IO.Path]::GetFullPath($skill_source))) {
            Write-Output "Skill link already installed: $skill_link"
            continue
        }
        throw "Install target already exists and was preserved: $skill_link"
    }

    New-Item -ItemType Junction -Path $skill_link -Target $skill_source | Out-Null
    Write-Output "Installed skill link: $skill_link"
}

$profile_path = $PROFILE.CurrentUserAllHosts
$profile_parent = Split-Path -Parent $profile_path
[System.IO.Directory]::CreateDirectory($profile_parent) | Out-Null

$profile_marker = '# MARTIS REA command'
$profile_block = @"

$profile_marker
function martis {
    & '$root\martis.ps1' @args
}
"@

$profile_content = if (Test-Path -LiteralPath $profile_path) {
    Get-Content -LiteralPath $profile_path -Raw
} else {
    ''
}

if ($profile_content -notmatch '(?m)^# MARTIS REA command$') {
    Add-Content -LiteralPath $profile_path -Value $profile_block -Encoding UTF8
    Write-Output "Installed PowerShell command in: $profile_path"
} else {
    Write-Output "PowerShell command already installed: $profile_path"
}

Write-Output 'MARTIS REA installation complete. Open a new PowerShell window, then run: martis start test'
