<#
.SYNOPSIS
    Build the fed2-tools package.
.DESCRIPTION
    Derives version from git tags, patches mfile, runs muddle, then restores
    mfile so the committed value stays clean.

    For release builds (exact git tag at HEAD):    version = "0.2.0"
    For dev builds (no exact tag):                version = "0.2.0-a3f91cd"

    Pass -MuxletTag to override where Muxlet is installed from.  The override
    is injected into the build copy of init.lua only — the source file is never
    modified.  Omit -MuxletTag to use the Mudlet Package Repository (default).
.PARAMETER Profile
    Deploy the built package to this Mudlet profile directory and write a
    rebuild stamp file (triggers reload within ~30 seconds if auto-reload is
    configured).
.PARAMETER MuxletTag
    Override the Muxlet install source with a specific GitHub release tag.
    e.g. "1.0.6"  → pre-release build  (no v prefix)
         "v1.0.6" → production build
    Omit to install Muxlet from the Mudlet Package Repository (default).
.PARAMETER MudletConfigPath
    Override the Mudlet config directory.  Auto-detected from APPDATA when not
    specified.  Required on non-Windows or unusual Mudlet installs.
.EXAMPLE
    ./build.ps1
.EXAMPLE
    ./build.ps1 -Profile fed2-dev
.EXAMPLE
    ./build.ps1 -MuxletTag "1.0.6" -Profile fed2-dev
#>

[CmdletBinding()]
param(
    [string]$Profile          = "",
    [string]$MuxletTag        = "",
    [string]$MudletConfigPath = ""
)

$ErrorActionPreference = "Stop"
$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Definition
$mfilePath   = Join-Path $scriptDir "mfile"
$initPath    = Join-Path $scriptDir "src\scripts\init.lua"
$srcPackage  = Join-Path $scriptDir "build\fed2-tools.mpackage"

Write-Host ""
Write-Host "=== fed2-tools build ===" -ForegroundColor Cyan

# ── Derive version from git ───────────────────────────────────────────────────

$exactTag = & git describe --tags --exact-match HEAD 2>$null
if ($LASTEXITCODE -eq 0 -and $exactTag -match '^v(.+)$') {
    $Version = $Matches[1]
} else {
    $lastTag     = & git describe --tags --match "v*" --abbrev=0 2>$null
    $baseVersion = if ($LASTEXITCODE -eq 0 -and $lastTag) { $lastTag -replace '^v', '' } else { "0.0.0" }
    $shortSha    = & git rev-parse --short HEAD 2>$null
    $Version     = "$baseVersion-$shortSha"
}

Write-Host "Version       : $Version" -ForegroundColor Green

# ── Patch mfile temporarily ───────────────────────────────────────────────────

$originalMfile = Get-Content $mfilePath -Raw
$patchedMfile  = $originalMfile -replace '"version":\s*"[^"]*"', ('"version": "' + $Version + '"')
Set-Content $mfilePath $patchedMfile -NoNewline
Write-Host "mfile         : version set to $Version" -ForegroundColor Gray

# ── Optionally inject Muxlet dev URL into init.lua ───────────────────────────

$originalInit = Get-Content $initPath -Raw

if ($MuxletTag -ne "") {
    $devUrl     = "https://github.com/tmtocloud/Muxlet/releases/download/$MuxletTag/Muxlet.mpackage"
    $patchedInit = $originalInit -replace 'local MUXLET_DEV_URL = nil', "local MUXLET_DEV_URL = `"$devUrl`""
    Set-Content $initPath $patchedInit -NoNewline
    Write-Host "Muxlet URL    : $devUrl" -ForegroundColor Yellow
} else {
    Write-Host "Muxlet source : MPR (default)" -ForegroundColor Gray
}

# ── Run muddle ────────────────────────────────────────────────────────────────

try {
    & muddle
    if ($LASTEXITCODE -ne 0) { throw "muddle exited with code $LASTEXITCODE" }
    Write-Host "Output        : $srcPackage" -ForegroundColor Green
} finally {
    Set-Content $mfilePath $originalMfile -NoNewline
    Write-Host "mfile         : restored" -ForegroundColor Gray

    if ($MuxletTag -ne "") {
        Set-Content $initPath $originalInit -NoNewline
        Write-Host "init.lua      : restored" -ForegroundColor Gray
    }
}

# ── Deploy to profile (optional) ─────────────────────────────────────────────

if ($Profile -eq "") {
    Write-Host ""
    exit 0
}

Write-Host ""
Write-Host "=== Deploying to profile: $Profile ===" -ForegroundColor Cyan

# Find Mudlet config directory
if ($MudletConfigPath -eq "") {
    $candidates = @(
        "$env:APPDATA\Mudlet",
        "$env:USERPROFILE\.config\mudlet"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path (Join-Path $candidate "profiles")) {
            $MudletConfigPath = $candidate
            break
        }
    }
}

if ($MudletConfigPath -eq "") {
    Write-Error ("Could not find Mudlet config directory.`n" +
                 "Launch Mudlet at least once, or pass -MudletConfigPath explicitly.")
}

Write-Host "Mudlet config : $MudletConfigPath"

$profileDir = Join-Path $MudletConfigPath "profiles\$Profile"
$firstTime  = $false

if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Force $profileDir | Out-Null
    Write-Host "Created profile: $Profile"
    $firstTime = $true
} else {
    Write-Host "Profile       : $Profile"
}

if (-not (Test-Path $srcPackage)) {
    Write-Error "build/fed2-tools.mpackage not found after build step."
}

$destPackage = Join-Path $profileDir "fed2-tools.mpackage"
Copy-Item $srcPackage $destPackage -Force
Write-Host "Deployed      : $destPackage"

$stampPath = Join-Path $profileDir "fed2-tools-rebuild.stamp"
[DateTimeOffset]::UtcNow.ToUnixTimeSeconds() | Set-Content $stampPath
Write-Host "Stamp written : $stampPath"

Write-Host ""

if ($firstTime) {
    Write-Host "FIRST-TIME SETUP:" -ForegroundColor Yellow
    Write-Host "  1. Open Mudlet"
    Write-Host "  2. Select profile: '$Profile'"
    Write-Host "  3. Toolbox -> Package Manager -> Install from file:"
    Write-Host "     $destPackage"
    Write-Host ""
    Write-Host "After this one-time install, fed2-tools loads automatically."
    Write-Host ""
}

Write-Host "WORKFLOW:" -ForegroundColor Cyan
Write-Host "  ./build.ps1 -Profile $Profile"
Write-Host "  Reinstall the package in Mudlet to pick up changes."
Write-Host ""
