#!/usr/bin/env pwsh
<#
.SYNOPSIS
    One-time setup: create a Mudlet dev profile pre-configured for fed2-tools testing.

.DESCRIPTION
    Creates a Mudlet profile with Fed2 connection details pre-filled so you never
    type the host/port/login again. Works on Windows, Linux, and macOS.

    FIRST TIME:
      Run this script once.
      Open Mudlet -> select the profile -> enter password -> connect.
      Install the package via Package Manager -> Install from file (path shown at end).

    ONGOING:
      ./build.ps1 -Profile <name>   (builds + deploys to profile)
      Package auto-reloads in Mudlet within 30 seconds.
      Or type: f2t reload   for an immediate reload.

.PARAMETER ProfileName
    Name for the Mudlet profile (default: fed2-dev)

.PARAMETER Username
    Fed2 character name (pre-fills login field; you still enter the password once)

.PARAMETER GameHost
    Game server hostname (default: play.federation2.com)

.PARAMETER GamePort
    Game server port (default: 30003)

.PARAMETER MudletConfigPath
    Override Mudlet config directory if auto-detection fails

.PARAMETER NoBuild
    Skip building and deploying the package (just create the profile)

.EXAMPLE
    ./setup-dev-profile.ps1 -Username jackrungh
    ./setup-dev-profile.ps1 -ProfileName jane-dev -Username jane
    ./setup-dev-profile.ps1 -MudletConfigPath /home/user/.config/mudlet
#>

[CmdletBinding()]
param(
    [string]$ProfileName = "fed2-dev",
    [string]$Username = "",
    [string]$GameHost = "play.federation2.com",
    [int]$GamePort = 30003,
    [string]$MudletConfigPath = "",
    [switch]$NoBuild
)

# Find the Mudlet config directory across OS/install variations
function Find-MudletConfigPath {
    $candidates = @()

    # XDG / Linux / Windows with HOME set
    if ($env:XDG_CONFIG_HOME) {
        $candidates += Join-Path $env:XDG_CONFIG_HOME "mudlet"
    }
    if ($HOME) {
        $candidates += Join-Path $HOME ".config" "mudlet"
        $candidates += Join-Path $HOME ".config" "Mudlet"
        # macOS
        $candidates += Join-Path $HOME "Library" "Application Support" "mudlet"
        $candidates += Join-Path $HOME "Library" "Application Support" "Mudlet"
    }

    # Windows AppData fallbacks
    if ($env:APPDATA) {
        $candidates += Join-Path $env:APPDATA "Mudlet"
        $candidates += Join-Path $env:APPDATA "mudlet"
    }
    if ($env:LOCALAPPDATA) {
        $candidates += Join-Path $env:LOCALAPPDATA "Mudlet"
    }

    foreach ($path in $candidates) {
        if ($path -and (Test-Path (Join-Path $path "profiles"))) {
            return $path
        }
    }
    return $null
}

# Write a string in Mudlet's binary profile format:
#   4-byte big-endian byte-length prefix + UTF-16 BE encoded string body
function Write-MudletString {
    param([string]$FilePath, [string]$Value)

    if ($Value -eq "") {
        [System.IO.File]::WriteAllBytes($FilePath, [byte[]]@(0, 0, 0, 0))
        return
    }

    $utf16Bytes = [System.Text.Encoding]::BigEndianUnicode.GetBytes($Value)
    $len = $utf16Bytes.Length
    $header = [byte[]]@(
        [byte](($len -shr 24) -band 0xFF),
        [byte](($len -shr 16) -band 0xFF),
        [byte](($len -shr 8) -band 0xFF),
        [byte]($len -band 0xFF)
    )
    $combined = New-Object byte[] ($header.Length + $utf16Bytes.Length)
    [Array]::Copy($header, 0, $combined, 0, $header.Length)
    [Array]::Copy($utf16Bytes, 0, $combined, $header.Length, $utf16Bytes.Length)
    [System.IO.File]::WriteAllBytes($FilePath, $combined)
}

# ---- Main ----

Write-Host ""
Write-Host "=== Fed2-Tools Dev Profile Setup ===" -ForegroundColor Cyan
Write-Host ""

# Locate Mudlet config directory
$mudletConfig = if ($MudletConfigPath) { $MudletConfigPath } else { Find-MudletConfigPath }

if (-not $mudletConfig) {
    Write-Host "ERROR: Could not auto-detect Mudlet config directory." -ForegroundColor Red
    Write-Host ""
    Write-Host "Tried the following locations:" -ForegroundColor Yellow
    Write-Host "  ~/.config/mudlet      (Linux / Windows with HOME)" -ForegroundColor DarkGray
    Write-Host "  ~/Library/Application Support/mudlet  (macOS)" -ForegroundColor DarkGray
    Write-Host "  %APPDATA%\Mudlet      (Windows AppData)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Solutions:" -ForegroundColor Yellow
    Write-Host "  1. Launch Mudlet at least once to initialize its config directory." -ForegroundColor White
    Write-Host "  2. Re-run with: ./setup-dev-profile.ps1 -MudletConfigPath <path>" -ForegroundColor White
    exit 1
}

Write-Host "Mudlet config: $mudletConfig" -ForegroundColor DarkGray

# Create or update the profile directory
$profileDir = Join-Path $mudletConfig "profiles" $ProfileName
$profileExists = Test-Path $profileDir

if ($profileExists) {
    Write-Host "Profile '$ProfileName' already exists - updating connection settings." -ForegroundColor Yellow
} else {
    New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
    Write-Host "Created profile: $ProfileName" -ForegroundColor Green
}

# Write connection files in Mudlet's binary format
Write-MudletString -FilePath (Join-Path $profileDir "url") -Value $GameHost
Write-MudletString -FilePath (Join-Path $profileDir "port") -Value "$GamePort"
Write-MudletString -FilePath (Join-Path $profileDir "description") -Value ""

if ($Username) {
    Write-MudletString -FilePath (Join-Path $profileDir "login") -Value $Username
}

Write-Host "Connection settings:" -ForegroundColor Green
Write-Host "  Host:     $GameHost" -ForegroundColor DarkGray
Write-Host "  Port:     $GamePort" -ForegroundColor DarkGray
if ($Username) {
    Write-Host "  Username: $Username" -ForegroundColor DarkGray
} else {
    Write-Host "  Username: (not set - enter it in Mudlet's profile dialog)" -ForegroundColor DarkGray
}

# Build and deploy
if (-not $NoBuild) {
    Write-Host ""
    Write-Host "Building and deploying package..." -ForegroundColor Cyan

    $buildScript = Join-Path $PSScriptRoot "build.ps1"
    if (-not (Test-Path $buildScript)) {
        Write-Host "Warning: build.ps1 not found in script directory. Skipping build." -ForegroundColor Yellow
    } else {
        & $buildScript -Profile $ProfileName
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Build failed." -ForegroundColor Red
            exit 1
        }
    }
}

# Instructions
$profileMpackage = Join-Path $profileDir "fed2-tools.mpackage"

Write-Host ""
Write-Host "=== Done! ===" -ForegroundColor Cyan
Write-Host ""

if (-not $profileExists) {
    Write-Host "FIRST-TIME ONLY (do once per developer machine):" -ForegroundColor Yellow
    Write-Host "  1. Open Mudlet" -ForegroundColor White
    Write-Host "  2. Select profile: '$ProfileName'" -ForegroundColor White
    if ($Username) {
        Write-Host "  3. Enter password (username '$Username' pre-filled), connect" -ForegroundColor White
    } else {
        Write-Host "  3. Enter username + password, connect" -ForegroundColor White
    }
    Write-Host "  4. Toolbox -> Package Manager -> Install from file:" -ForegroundColor White
    Write-Host "     $profileMpackage" -ForegroundColor Cyan
    Write-Host ""
}

Write-Host "ONGOING DEV WORKFLOW:" -ForegroundColor Yellow
Write-Host "  ./build.ps1 -Profile $ProfileName" -ForegroundColor Cyan
Write-Host "  The package auto-reloads in Mudlet within ~30 seconds." -ForegroundColor DarkGray
Write-Host "  Or type in Mudlet: f2t reload   for an immediate reload." -ForegroundColor DarkGray
Write-Host ""
