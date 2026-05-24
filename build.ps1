#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Build script for fed2-tools Mudlet package

.DESCRIPTION
    This script reads components from the src/ directory (each subdirectory is a component)
    and generates a Mudlet package (.mpackage) that can be imported into Mudlet.
    Each component gets its own folder in Mudlet containing its triggers, aliases, scripts, etc.

.EXAMPLE
    ./build.ps1
#>

[CmdletBinding()]
param(
    [string]$Version,
    [string]$Profile = "fed2-dev"  # Mudlet profile name to deploy to after building (triggers auto-reload)
)

# Configuration — all paths anchored to script location so .NET ZipFile APIs
# resolve correctly regardless of the shell's working directory.
$ProjectFile = Join-Path $PSScriptRoot "project.json"
$SrcDir      = Join-Path $PSScriptRoot "src"
$BuildDir    = Join-Path $PSScriptRoot "build"

# Load project configuration
function Get-ProjectConfig {
    if (-not (Test-Path $ProjectFile)) {
        throw "Could not find $ProjectFile"
    }
    return Get-Content $ProjectFile -Raw | ConvertFrom-Json
}

# Get all component directories in priority order
function Get-Components {
    if (-not (Test-Path $SrcDir)) {
        return @()
    }

    # Priority components that must load first (in order)
    $priorityComponents = @("shared")

    $allComponents = Get-ChildItem -Path $SrcDir -Directory
    $orderedComponents = @()

    # Add priority components first (if they exist)
    foreach ($priorityName in $priorityComponents) {
        $component = $allComponents | Where-Object { $_.Name -eq $priorityName }
        if ($component) {
            $orderedComponents += $component
        }
    }

    # Add remaining components alphabetically
    $remainingComponents = $allComponents | Where-Object { $_.Name -notin $priorityComponents } | Sort-Object Name
    $orderedComponents += $remainingComponents

    return $orderedComponents
}

# Get all Lua files from a directory recursively
function Get-LuaFiles {
    param([string]$Path)

    if (Test-Path $Path) {
        return Get-ChildItem -Path $Path -Filter "*.lua" -Recurse
    }
    return @()
}

# Get all resource files from a component's resources directory
function Get-ResourceFiles {
    param([string]$Path)

    if (Test-Path $Path) {
        return Get-ChildItem -Path $Path -File -Recurse
    }
    return @()
}

# Escape XML special characters
function ConvertTo-XmlSafe {
    param([string]$Text)

    return $Text -replace '&', '&amp;' `
                -replace '<', '&lt;' `
                -replace '>', '&gt;' `
                -replace '"', '&quot;' `
                -replace "'", '&apos;'
}

# Parse metadata from Lua file comments
function Get-LuaMetadata {
    param([string]$FilePath)

    $metadata = @{}
    $content = Get-Content $FilePath -Raw

    # Check for multi-pattern YAML format (@patterns:)
    if ($content -match '(?ms)^--\s*@patterns:\s*\r?\n((?:--\s+.*\r?\n)+)') {
        $patternsBlock = $matches[1]
        $patterns = @()

        # Parse each pattern entry (indented with dashes)
        $lines = $patternsBlock -split "\r?\n"
        $currentPattern = $null

        foreach ($line in $lines) {
            if (-not $line) { continue }

            # Match pattern line: --   - pattern: <value>
            if ($line -match '^--\s+-\s+pattern:\s*(.+)$') {
                if ($currentPattern) {
                    $patterns += $currentPattern
                }
                $currentPattern = @{
                    pattern = $matches[1].Trim()
                    type = 'regex'  # Default
                }
            }
            # Match type line: --     type: <value>
            elseif ($line -match '^--\s+type:\s*(.+)$') {
                if ($currentPattern) {
                    $currentPattern.type = $matches[1].Trim()
                }
            }
        }

        # Add last pattern
        if ($currentPattern) {
            $patterns += $currentPattern
        }

        if ($patterns.Count -gt 0) {
            $metadata['patterns'] = $patterns
        }
    }

    # Extract single-line metadata (format: -- @key: value)
    # Key can contain letters, numbers, underscores, and hyphens
    if ($content -match '(?m)^--\s*@([\w-]+):\s*(.+)$') {
        $content -split "`n" | ForEach-Object {
            if ($_ -match '^--\s*@([\w-]+):\s*(.+)$') {
                # Skip if this is the @patterns: line itself
                if ($matches[1] -ne 'patterns') {
                    $metadata[$matches[1]] = $matches[2].Trim()
                }
            }
        }
    }

    return $metadata
}

# Generate XML for a folder
function New-FolderXml {
    param(
        [string]$Type,
        [string]$Name,
        [string]$Content
    )

    switch ($Type) {
        "Script" {
            return @"
    <Script isActive="yes" isFolder="yes">
      <name>$Name</name>
      <packageName></packageName>
      <script></script>
      <eventHandlerList />
$Content
    </Script>
"@
        }
        "Trigger" {
            return @"
    <TriggerGroup isActive="yes" isFolder="yes" isTempTrigger="no" isMultiline="no" isPerlSlashGOption="no" isColorizerTrigger="no" isFilterTrigger="no" isSoundTrigger="no" isColorTrigger="no" isColorTriggerFg="no" isColorTriggerBg="no">
      <name>$Name</name>
      <script></script>
      <triggerType>0</triggerType>
      <conditonLineDelta>0</conditonLineDelta>
      <mStayOpen>0</mStayOpen>
      <mCommand></mCommand>
      <packageName></packageName>
      <mFgColor>#ff0000</mFgColor>
      <mBgColor>#ffff00</mBgColor>
      <mSoundFile></mSoundFile>
      <colorTriggerFgColor>#000000</colorTriggerFgColor>
      <colorTriggerBgColor>#000000</colorTriggerBgColor>
      <regexCodeList />
      <regexCodePropertyList />
$Content
    </TriggerGroup>
"@
        }
        "Alias" {
            return @"
    <AliasGroup isActive="yes" isFolder="yes">
      <name>$Name</name>
      <script></script>
      <command></command>
      <packageName></packageName>
      <regex></regex>
$Content
    </AliasGroup>
"@
        }
        "Timer" {
            return @"
    <TimerGroup isActive="yes" isTempTimer="no" isFolder="yes">
      <name>$Name</name>
      <script></script>
      <command></command>
      <packageName></packageName>
      <time>00:00:00.00</time>
$Content
    </TimerGroup>
"@
        }
        "Key" {
            return @"
    <KeyGroup isActive="yes" isFolder="yes">
      <name>$Name</name>
      <script></script>
      <command></command>
      <packageName></packageName>
      <keyCode>-1</keyCode>
      <keyModifier>-1</keyModifier>
$Content
    </KeyGroup>
"@
        }
    }
}

# Generate XML for a script
function New-ScriptXml {
    param(
        [string]$Name,
        [string]$Code,
        [int]$Indent = 4
    )

    $SafeCode = ConvertTo-XmlSafe -Text $Code
    $spaces = " " * $Indent
    return @"
$spaces<Script isActive="yes" isFolder="no">
$spaces  <name>$Name</name>
$spaces  <packageName></packageName>
$spaces  <script>$SafeCode</script>
$spaces  <eventHandlerList />
$spaces</Script>
"@
}

# Generate XML for a trigger
function New-TriggerXml {
    param(
        [string]$Name,
        [string]$Code,
        [hashtable]$Metadata = @{},
        [int]$Indent = 4
    )

    $SafeCode = ConvertTo-XmlSafe -Text $Code
    $spaces = " " * $Indent

    # Helper function to convert pattern type string to integer
    function Get-PatternTypeInt {
        param([string]$Type)
        # Pattern type: 0=substring, 1=perl regex, 2=exact match, 3=lua function, 7=prompt
        switch ($Type) {
            'substring' { return 0 }
            'perl' { return 1 }
            'regex' { return 1 }
            'exact' { return 2 }
            'lua' { return 3 }
            'prompt' { return 7 }
            default { return 1 }
        }
    }

    # Check for multi-pattern format
    if ($Metadata.patterns -and $Metadata.patterns.Count -gt 0) {
        # Multiple patterns
        $patternStrings = @()
        $patternTypes = @()
        $isPromptTrigger = $false

        foreach ($p in $Metadata.patterns) {
            $patternStrings += "$spaces    <string>$($p.pattern)</string>"
            $typeInt = Get-PatternTypeInt -Type $p.type
            $patternTypes += "$spaces    <integer>$typeInt</integer>"
            if ($p.type -eq 'prompt') {
                $isPromptTrigger = $true
            }
        }

        $regexCodeList = $patternStrings -join "`n"
        $regexCodePropertyList = $patternTypes -join "`n"
        $triggerType = if ($isPromptTrigger) { 1 } else { 0 }
    }
    else {
        # Single pattern (legacy format)
        $isPromptTrigger = $false
        $patternType = if ($Metadata.'pattern-type') {
            $typeInt = Get-PatternTypeInt -Type $Metadata.'pattern-type'
            if ($Metadata.'pattern-type' -eq 'prompt') {
                $isPromptTrigger = $true
            }
            $typeInt
        } else { 1 }

        $triggerType = if ($isPromptTrigger) { 1 } else { 0 }
        $pattern = if ($Metadata.pattern) { $Metadata.pattern } else { ".*" }

        $regexCodeList = "$spaces    <string>$pattern</string>"
        $regexCodePropertyList = "$spaces    <integer>$patternType</integer>"
    }

    # Check for multiline flag
    $isMultiline = if ($Metadata.multiline -eq 'true') { "yes" } else { "no" }

    return @"
$spaces<Trigger isActive="yes" isFolder="no" isTempTrigger="no" isMultiline="$isMultiline" isPerlSlashGOption="no" isColorizerTrigger="no" isFilterTrigger="no" isSoundTrigger="no" isColorTrigger="no" isColorTriggerFg="no" isColorTriggerBg="no">
$spaces  <name>$Name</name>
$spaces  <script>$SafeCode</script>
$spaces  <triggerType>$triggerType</triggerType>
$spaces  <conditonLineDelta>0</conditonLineDelta>
$spaces  <mStayOpen>0</mStayOpen>
$spaces  <mCommand></mCommand>
$spaces  <packageName></packageName>
$spaces  <mFgColor>#ff0000</mFgColor>
$spaces  <mBgColor>#ffff00</mBgColor>
$spaces  <mSoundFile></mSoundFile>
$spaces  <colorTriggerFgColor>#000000</colorTriggerFgColor>
$spaces  <colorTriggerBgColor>#000000</colorTriggerBgColor>
$spaces  <regexCodeList>
$regexCodeList
$spaces  </regexCodeList>
$spaces  <regexCodePropertyList>
$regexCodePropertyList
$spaces  </regexCodePropertyList>
$spaces</Trigger>
"@
}

# Generate XML for an alias
function New-AliasXml {
    param(
        [string]$Name,
        [string]$Code,
        [hashtable]$Metadata = @{},
        [int]$Indent = 4
    )

    $SafeCode = ConvertTo-XmlSafe -Text $Code
    $spaces = " " * $Indent

    # Extract regex pattern from @patterns: format or legacy @regex:
    $regex = if ($Metadata.patterns -and $Metadata.patterns.Count -gt 0) {
        # Use first pattern from @patterns: array (aliases only support single pattern)
        $Metadata.patterns[0].pattern
    } elseif ($Metadata.regex) {
        # Legacy @regex: format
        $Metadata.regex
    } else {
        # Default: exact match on name
        "^$Name$"
    }

    return @"
$spaces<Alias isActive="yes" isFolder="no">
$spaces  <name>$Name</name>
$spaces  <script>$SafeCode</script>
$spaces  <command></command>
$spaces  <packageName></packageName>
$spaces  <regex>$regex</regex>
$spaces</Alias>
"@
}

# Generate XML for a timer
function New-TimerXml {
    param(
        [string]$Name,
        [string]$Code,
        [int]$Indent = 4
    )

    $SafeCode = ConvertTo-XmlSafe -Text $Code
    $spaces = " " * $Indent
    return @"
$spaces<Timer isActive="yes" isTempTimer="no" isFolder="no">
$spaces  <name>$Name</name>
$spaces  <script>$SafeCode</script>
$spaces  <command></command>
$spaces  <packageName></packageName>
$spaces  <time>00:00:00.00</time>
$spaces</Timer>
"@
}

# Generate XML for a keybinding
function New-KeybindingXml {
    param(
        [string]$Name,
        [string]$Code,
        [hashtable]$Metadata = @{},
        [int]$Indent = 4
    )

    $SafeCode = ConvertTo-XmlSafe -Text $Code
    $spaces = " " * $Indent
    $keyCode = if ($Metadata -and $Metadata.ContainsKey('keyCode')) { [int]$Metadata.keyCode } else { -1 }
    $keyModifier = if ($Metadata -and $Metadata.ContainsKey('keyModifier')) { [int]$Metadata.keyModifier } else { -1 }
    return @"
$spaces<Key isActive="yes" isFolder="no">
$spaces  <name>$Name</name>
$spaces  <script>$SafeCode</script>
$spaces  <command></command>
$spaces  <packageName></packageName>
$spaces  <keyCode>$keyCode</keyCode>
$spaces  <keyModifier>$keyModifier</keyModifier>
$spaces</Key>
"@
}

# Process a single component
function Get-ComponentData {
    param([System.IO.DirectoryInfo]$Component)

    $data = @{
        Name = $Component.Name
        Scripts = @()
        Triggers = @()
        Aliases = @()
        Timers = @()
        Keybindings = @()
        Resources = @()
    }

    # Scan each item type
    foreach ($file in Get-LuaFiles -Path (Join-Path $Component.FullName "scripts")) {
        $data.Scripts += @{
            Name = $file.BaseName
            Code = Get-Content $file.FullName -Raw
        }
    }

    foreach ($file in Get-LuaFiles -Path (Join-Path $Component.FullName "triggers")) {
        $data.Triggers += @{
            Name = $file.BaseName
            Code = Get-Content $file.FullName -Raw
            Metadata = Get-LuaMetadata -FilePath $file.FullName
        }
    }

    foreach ($file in Get-LuaFiles -Path (Join-Path $Component.FullName "aliases")) {
        $data.Aliases += @{
            Name = $file.BaseName
            Code = Get-Content $file.FullName -Raw
            Metadata = Get-LuaMetadata -FilePath $file.FullName
        }
    }

    foreach ($file in Get-LuaFiles -Path (Join-Path $Component.FullName "timers")) {
        $data.Timers += @{
            Name = $file.BaseName
            Code = Get-Content $file.FullName -Raw
        }
    }

    foreach ($file in Get-LuaFiles -Path (Join-Path $Component.FullName "keybindings")) {
        $data.Keybindings += @{
            Name = $file.BaseName
            Code = Get-Content $file.FullName -Raw
            Metadata = Get-LuaMetadata -FilePath $file.FullName
        }
    }

    # Scan for resource files
    $resourcesPath = Join-Path $Component.FullName "resources"
    foreach ($file in Get-ResourceFiles -Path $resourcesPath) {
        $data.Resources += @{
            SourcePath = $file.FullName
            RelativePath = $file.FullName.Substring($resourcesPath.Length + 1)
        }
    }

    return $data
}

# Map files to copy to shared resources during build
$MapFiles = @(
    "starter_map.json",
    "starter_map_with_exchanges.json",
    "galaxy_brief.json"
)

# Copy map files to shared resources
function Copy-MapFiles {
    $mapsDir = Join-Path $PSScriptRoot "maps"
    $destDir = Join-Path $SrcDir "shared" "resources"

    # Ensure destination directory exists
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    $copiedCount = 0
    foreach ($mapFile in $MapFiles) {
        $sourcePath = Join-Path $mapsDir $mapFile
        if (Test-Path $sourcePath) {
            $destPath = Join-Path $destDir $mapFile
            Copy-Item -Path $sourcePath -Destination $destPath -Force
            Write-Host "  - Copied $mapFile to shared/resources/" -ForegroundColor Gray
            $copiedCount++
        } else {
            Write-Host "  - Warning: $mapFile not found in maps/" -ForegroundColor Yellow
        }
    }

    return $copiedCount
}

# Clean up copied map files from shared resources
function Remove-MapFiles {
    $destDir = Join-Path $SrcDir "shared" "resources"

    foreach ($mapFile in $MapFiles) {
        $filePath = Join-Path $destDir $mapFile
        if (Test-Path $filePath) {
            Remove-Item -Path $filePath -Force
        }
    }
}

# Find the Mudlet config directory across OS/install variations
function Find-MudletConfigPath {
    $candidates = @()

    if ($env:XDG_CONFIG_HOME) {
        $candidates += Join-Path $env:XDG_CONFIG_HOME "mudlet"
    }
    if ($HOME) {
        $candidates += Join-Path $HOME ".config" "mudlet"
        $candidates += Join-Path $HOME ".config" "Mudlet"
        $candidates += Join-Path $HOME "Library" "Application Support" "mudlet"
        $candidates += Join-Path $HOME "Library" "Application Support" "Mudlet"
    }
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

# Deploy built package to a Mudlet profile directory and write a rebuild stamp
# so the in-game auto-reload timer can detect the new build
function Deploy-ToProfile {
    param([string]$PackageName, [string]$PackageFile, [string]$ProfileName)

    $mudletConfig = Find-MudletConfigPath
    if (-not $mudletConfig) {
        Write-Host "Warning: Could not find Mudlet config directory. Skipping deploy." -ForegroundColor Yellow
        Write-Host "  Run setup-dev-profile.ps1 first, or pass -MudletConfigPath to it." -ForegroundColor DarkGray
        return
    }

    $profileDir = Join-Path $mudletConfig "profiles" $ProfileName
    if (-not (Test-Path $profileDir)) {
        Write-Host "Warning: Profile '$ProfileName' not found at $profileDir" -ForegroundColor Yellow
        Write-Host "  Run: ./setup-dev-profile.ps1 -ProfileName '$ProfileName'" -ForegroundColor DarkGray
        return
    }

    $destPackage = Join-Path $profileDir "$PackageName.mpackage"
    Copy-Item $PackageFile -Destination $destPackage -Force
    Write-Host "Deployed to '$ProfileName': $destPackage" -ForegroundColor Green

    $stampFile = Join-Path $profileDir "$PackageName-rebuild.stamp"
    [System.DateTime]::UtcNow.ToString("o") | Set-Content $stampFile -Encoding UTF8
    Write-Host "Rebuild stamp written (Mudlet auto-reload will trigger within ~30s)" -ForegroundColor DarkGray
}

# Main build function
function Invoke-Build {
    Write-Host "Building Mudlet package..." -ForegroundColor Cyan

    # Copy map files to shared resources before scanning components
    Write-Host "Copying map files..." -ForegroundColor Cyan
    $mapsCopied = Copy-MapFiles
    if ($mapsCopied -gt 0) {
        Write-Host "Copied $mapsCopied map file(s)" -ForegroundColor Green
    }

    # Load project config
    $config = Get-ProjectConfig
    Write-Host "Package name: $($config.name)" -ForegroundColor Green
    if ($Version) {
        Write-Host "Version: $Version" -ForegroundColor Green
    } else {
        Write-Host "Version: (development)" -ForegroundColor Yellow
    }

    # Ensure build directory exists
    if (-not (Test-Path $BuildDir)) {
        New-Item -ItemType Directory -Path $BuildDir | Out-Null
    }

    # Get all components
    $components = Get-Components
    if ($components.Count -eq 0) {
        Write-Host "Warning: No components found in $SrcDir" -ForegroundColor Yellow
    }

    Write-Host "Found $($components.Count) component(s)" -ForegroundColor Cyan

    # Process each component
    $componentData = @()
    $totalCounts = @{
        Scripts = 0
        Triggers = 0
        Aliases = 0
        Timers = 0
        Keybindings = 0
        Resources = 0
    }

    foreach ($component in $components) {
        $data = Get-ComponentData -Component $component
        $componentData += $data

        Write-Host "  - $($component.Name): Scripts=$($data.Scripts.Count), Triggers=$($data.Triggers.Count), Aliases=$($data.Aliases.Count), Timers=$($data.Timers.Count), Keys=$($data.Keybindings.Count), Resources=$($data.Resources.Count)" -ForegroundColor Gray

        $totalCounts.Scripts += $data.Scripts.Count
        $totalCounts.Triggers += $data.Triggers.Count
        $totalCounts.Aliases += $data.Aliases.Count
        $totalCounts.Timers += $data.Timers.Count
        $totalCounts.Keybindings += $data.Keybindings.Count
        $totalCounts.Resources += $data.Resources.Count
    }

    # Resolve the effective version for this build.
    # Dev builds (no -Version) derive "<last-tag>-dev" from git so the in-game
    # update checker treats them as pre-release and suppresses the update popup.
    if ($Version) {
        $effectiveVersion = $Version
    } else {
        $lastTag = & git describe --tags --match "v*" --abbrev=0 2>$null
        $baseVersion = if ($lastTag) { $lastTag -replace '^v', '' } else { "0.0.0" }
        $effectiveVersion = "$baseVersion-dev"
    }

    # Always inject F2T_VERSION so the update checker always has a usable version.
    $versionScript = @{
        Name = "00_version"
        Code = "F2T_VERSION = `"$effectiveVersion`""
    }
    $sharedComponent = $componentData | Where-Object { $_.Name -eq "shared" }
    if ($sharedComponent) {
        $sharedComponent.Scripts = @($versionScript) + $sharedComponent.Scripts
        $totalCounts.Scripts += 1
        Write-Host "  - Version: $effectiveVersion" -ForegroundColor Gray
    }

    # Build XML
    $xmlParts = @(
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<!DOCTYPE MudletPackage>',
        '<MudletPackage version="1.001">'
    )

    # Add scripts by component
    if ($totalCounts.Scripts -gt 0) {
        $xmlParts += '  <ScriptPackage>'
        foreach ($comp in $componentData) {
            if ($comp.Scripts.Count -gt 0) {
                $scriptItems = @()
                foreach ($item in $comp.Scripts) {
                    $scriptItems += New-ScriptXml -Name $item.Name -Code $item.Code -Indent 6
                }
                $xmlParts += New-FolderXml -Type "Script" -Name $comp.Name -Content ($scriptItems -join "`n")
            }
        }
        $xmlParts += '  </ScriptPackage>'
    }

    # Add triggers by component
    if ($totalCounts.Triggers -gt 0) {
        $xmlParts += '  <TriggerPackage>'
        foreach ($comp in $componentData) {
            if ($comp.Triggers.Count -gt 0) {
                $triggerItems = @()
                foreach ($item in $comp.Triggers) {
                    $triggerItems += New-TriggerXml -Name $item.Name -Code $item.Code -Metadata $item.Metadata -Indent 6
                }
                $xmlParts += New-FolderXml -Type "Trigger" -Name $comp.Name -Content ($triggerItems -join "`n")
            }
        }
        $xmlParts += '  </TriggerPackage>'
    }

    # Add aliases by component
    if ($totalCounts.Aliases -gt 0) {
        $xmlParts += '  <AliasPackage>'
        foreach ($comp in $componentData) {
            if ($comp.Aliases.Count -gt 0) {
                $aliasItems = @()
                foreach ($item in $comp.Aliases) {
                    $aliasItems += New-AliasXml -Name $item.Name -Code $item.Code -Metadata $item.Metadata -Indent 6
                }
                $xmlParts += New-FolderXml -Type "Alias" -Name $comp.Name -Content ($aliasItems -join "`n")
            }
        }
        $xmlParts += '  </AliasPackage>'
    }

    # Add timers by component
    if ($totalCounts.Timers -gt 0) {
        $xmlParts += '  <TimerPackage>'
        foreach ($comp in $componentData) {
            if ($comp.Timers.Count -gt 0) {
                $timerItems = @()
                foreach ($item in $comp.Timers) {
                    $timerItems += New-TimerXml -Name $item.Name -Code $item.Code -Indent 6
                }
                $xmlParts += New-FolderXml -Type "Timer" -Name $comp.Name -Content ($timerItems -join "`n")
            }
        }
        $xmlParts += '  </TimerPackage>'
    }

    # Add keybindings by component
    if ($totalCounts.Keybindings -gt 0) {
        $xmlParts += '  <KeyPackage>'
        foreach ($comp in $componentData) {
            if ($comp.Keybindings.Count -gt 0) {
                $keyItems = @()
                foreach ($item in $comp.Keybindings) {
                    $itemMetadata = if ($item.Metadata) { $item.Metadata } else { @{} }
                    $keyItems += New-KeybindingXml -Name $item.Name -Code $item.Code -Metadata $itemMetadata -Indent 6
                }
                $xmlParts += New-FolderXml -Type "Key" -Name $comp.Name -Content ($keyItems -join "`n")
            }
        }
        $xmlParts += '  </KeyPackage>'
    }

    $xmlParts += '</MudletPackage>'

    $xmlFile = Join-Path $BuildDir "$($config.name).xml"
    $xmlParts -join "`n" | Set-Content -Path $xmlFile -Encoding UTF8
    Write-Host "Generated XML: $xmlFile" -ForegroundColor Green

    # Write config.lua (fields required by the Mudlet package repository validator)
    $configLua = Join-Path $BuildDir "config.lua"
    $configVersion = $effectiveVersion
    $configCreated = (Get-Date -Format "yyyy-MM-dd")
    $configContent = @"
mpackage = "$($config.name)"
title = "$($config.title)"
version = "$configVersion"
created = "$configCreated"
author = "$($config.author)"
description = "$($config.description)"
"@
    # Include icon filename if project declares a screenshot and the file exists.
    # reindex.lua extracts it from .mudlet/Icon/<name> inside the mpackage.
    $iconPath = if ($config.icon) { Join-Path $PSScriptRoot $config.icon } else { $null }
    $iconFile = if ($iconPath -and (Test-Path $iconPath)) { $iconPath } else { $null }
    if ($iconFile) {
        $iconLeaf = Split-Path $iconFile -Leaf
        $configContent += "`nicon = `"$iconLeaf`""
    }
    $configContent | Set-Content -Path $configLua -Encoding UTF8
    Write-Host "Generated config: $configLua" -ForegroundColor Green

    # Copy resource files to build directory
    $copiedResources = @()
    if ($totalCounts.Resources -gt 0) {
        Write-Host "Copying resource files..." -ForegroundColor Cyan
        foreach ($comp in $componentData) {
            if ($comp.Resources.Count -gt 0) {
                foreach ($resource in $comp.Resources) {
                    # Create destination path: build/component-name/relative-path
                    $destPath = Join-Path $BuildDir $comp.Name $resource.RelativePath
                    $destDir = Split-Path $destPath -Parent

                    # Ensure destination directory exists
                    if (-not (Test-Path $destDir)) {
                        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                    }

                    # Copy the resource file
                    Copy-Item -Path $resource.SourcePath -Destination $destPath -Force
                    $copiedResources += (Get-Item $destPath)
                    Write-Host "  - $($comp.Name)/$($resource.RelativePath)" -ForegroundColor Gray
                }
            }
        }
    }

    # Create .mpackage (zip file)
    # Write to a temp path first so the build always succeeds even if the final
    # file is momentarily locked (OneDrive sync, antivirus, etc.), then replace.
    $packageFile = Join-Path $BuildDir "$($config.name).mpackage"
    $packageTemp = Join-Path $BuildDir "$($config.name).mpackage.tmp"

    # Build a temp staging directory containing everything the archive needs,
    # then zip it with ZipFile::CreateFromDirectory. This guarantees all files
    # sit at the archive root (Compress-Archive wildcard behavior is buggy in
    # PS 5.1 and it also rejects non-.zip extensions).
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $tempZipDir = Join-Path $BuildDir "temp_zip"
    if (Test-Path $tempZipDir) { Remove-Item $tempZipDir -Recurse -Force }
    New-Item -ItemType Directory -Path $tempZipDir | Out-Null

    Copy-Item $configLua -Destination $tempZipDir
    Copy-Item $xmlFile   -Destination $tempZipDir

    foreach ($comp in $componentData) {
        if ($comp.Resources.Count -gt 0) {
            $compDir = Join-Path $BuildDir $comp.Name
            if (Test-Path $compDir) {
                Copy-Item $compDir -Destination $tempZipDir -Recurse
            }
        }
    }

    if (Test-Path $packageTemp) { Remove-Item $packageTemp -Force }
    [System.IO.Compression.ZipFile]::CreateFromDirectory($tempZipDir, $packageTemp)
    Remove-Item $tempZipDir -Recurse -Force

    # Replace final package — -Force overwrites; if still locked, error is clear
    Move-Item $packageTemp $packageFile -Force

    # Bundle icon inside mpackage at .mudlet/Icon/<filename> so reindex.lua can extract it
    if ($iconFile) {
        $iconLeaf = Split-Path $iconFile -Leaf
        $entryPath = ".mudlet/Icon/$iconLeaf"
        $zip = $null
        try {
            $zip = [System.IO.Compression.ZipFile]::Open($packageFile, 'Update')
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $iconFile, $entryPath) | Out-Null
        } finally {
            if ($zip) { $zip.Dispose() }
        }
        Write-Host "  - Bundled icon: $entryPath" -ForegroundColor Gray
    }

    # Clean up copied map files from src/shared/resources
    Remove-MapFiles

    Write-Host "`nBuild complete: $packageFile" -ForegroundColor Green
    Write-Host "Total items - Scripts: $($totalCounts.Scripts), Triggers: $($totalCounts.Triggers), Aliases: $($totalCounts.Aliases), Timers: $($totalCounts.Timers), Keybindings: $($totalCounts.Keybindings), Resources: $($totalCounts.Resources)" -ForegroundColor Cyan

    # Deploy to the Mudlet profile. Defaults to "fed2-dev" locally; CI runners
    # have no Mudlet install so Deploy-ToProfile exits early with a warning.
    if ($Profile) {
        Deploy-ToProfile -PackageName $config.name -PackageFile $packageFile -ProfileName $Profile
    }
}

# Run the build
try {
    Invoke-Build
    exit 0
}
catch {
    Write-Host "Build failed: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
