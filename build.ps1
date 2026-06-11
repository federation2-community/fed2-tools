<#
.SYNOPSIS
    Build the fed2-tools package.
.DESCRIPTION
    Derives version from git tags, reads muxlet_version from mfile, patches
    mfile and init.lua temporarily, runs muddle, then restores everything so
    committed values stay clean.

    Local builds always use the Muxlet prerelease URL (bare tag, no "v" prefix).
    Production builds (exact v* tag at HEAD, normally a CI scenario) use the
    v-prefixed production Muxlet URL.

    The Muxlet version is controlled solely by "muxlet_version" in mfile.
    To test against a different Muxlet build, change muxlet_version in mfile.
.PARAMETER Profile
    Deploy the built package to this Mudlet profile directory and write a
    rebuild stamp file (triggers auto-reload within ~30 seconds via the dev
    watcher in init.lua).
.PARAMETER MudletConfigPath
    Override the Mudlet config directory.  Auto-detected from APPDATA when not
    specified.
.EXAMPLE
    ./build.ps1
.EXAMPLE
    ./build.ps1 -Profile fed2-dev
#>

[CmdletBinding()]
param(
    [string]$Profile          = "",
    [string]$MudletConfigPath = ""
)

$ErrorActionPreference = "Stop"
$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Definition
$mfilePath  = Join-Path $scriptDir "mfile"
$initPath   = Join-Path $scriptDir "src\scripts\init.lua"
$srcPackage = Join-Path $scriptDir "build\fed2-tools.mpackage"

Write-Host ""
Write-Host "=== fed2-tools build ===" -ForegroundColor Cyan

# ── Read mfile ────────────────────────────────────────────────────────────────

$mfileJson     = Get-Content $mfilePath -Raw | ConvertFrom-Json
$muxletVersion = $mfileJson.muxlet_version
if (-not $muxletVersion) {
    Write-Error "mfile is missing 'muxlet_version' field."
}

# ── Derive fed2-tools version from git ───────────────────────────────────────

$exactTag = & git describe --tags --exact-match HEAD 2>$null
if ($LASTEXITCODE -eq 0 -and $exactTag -match '^v(.+)$') {
    $Version   = $Matches[1]
    $IsRelease = $true
} else {
    $lastTag     = & git describe --tags --match "v*" --abbrev=0 2>$null
    $baseVersion = if ($LASTEXITCODE -eq 0 -and $lastTag) { $lastTag -replace '^v', '' } else { "0.0.0" }
    $shortSha    = & git rev-parse --short HEAD 2>$null
    $Version     = "$baseVersion-$shortSha"
    $IsRelease   = $false
}

Write-Host "Version       : $Version" -ForegroundColor Green

# ── Build Muxlet URL ──────────────────────────────────────────────────────────
# Local builds target the prerelease Muxlet (bare tag = no "v").
# IsRelease=true only for an exact v* tag at HEAD; use the production Muxlet URL.

$muxletTag = if ($IsRelease) { "v$muxletVersion" } else { $muxletVersion }
$muxletUrl = "https://github.com/tmtocloud/Muxlet/releases/download/$muxletTag/Muxlet.mpackage"

Write-Host "Muxlet        : $muxletVersion  ($muxletUrl)" -ForegroundColor Green

# ── Patch mfile temporarily ───────────────────────────────────────────────────

$originalMfile = Get-Content $mfilePath -Raw
$patchedMfile  = $originalMfile -replace '"version":\s*"[^"]*"', ('"version": "' + $Version + '"')
Set-Content $mfilePath $patchedMfile -NoNewline
Write-Host "mfile         : version set to $Version" -ForegroundColor Gray

# ── Inject into init.lua temporarily ─────────────────────────────────────────

$originalInit = Get-Content $initPath -Raw
$patchedInit  = $originalInit `
    -replace 'local F2T_REQUIRED_MUXLET = nil', "local F2T_REQUIRED_MUXLET = `"$muxletVersion`"" `
    -replace 'local MUXLET_URL = nil',           "local MUXLET_URL = `"$muxletUrl`""
Set-Content $initPath $patchedInit -NoNewline
Write-Host "init.lua      : injected F2T_REQUIRED_MUXLET=$muxletVersion, MUXLET_URL" -ForegroundColor Gray

# ── Run muddle ────────────────────────────────────────────────────────────────

try {
    & muddle
    if ($LASTEXITCODE -ne 0) { throw "muddle exited with code $LASTEXITCODE" }
    Write-Host "Output        : $srcPackage" -ForegroundColor Green
} finally {
    Set-Content $mfilePath $originalMfile -NoNewline
    Write-Host "mfile         : restored" -ForegroundColor Gray
    Set-Content $initPath $originalInit -NoNewline
    Write-Host "init.lua      : restored" -ForegroundColor Gray
}

# ── Deploy to profile (optional) ─────────────────────────────────────────────

if ($Profile -eq "") {
    Write-Host ""
    exit 0
}

Write-Host ""
Write-Host "=== Deploying to profile: $Profile ===" -ForegroundColor Cyan

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
    Write-Host "After this one-time install, fed2-tools reloads automatically on each build."
    Write-Host ""
}

Write-Host "WORKFLOW:" -ForegroundColor Cyan
Write-Host "  ./build.ps1 -Profile $Profile"
Write-Host "  fed2-tools auto-reloads within ~30 seconds via the dev stamp watcher."
Write-Host ""
