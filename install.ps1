# install.ps1
# Restored script: requires Administrator. Performs a forced git update, reads config.json mappings,
# expands targets (handles $PROFILE and $env:VAR), prompts before deleting existing targets,
# and uses mklink (requires admin) to create symbolic links.

# Determine script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

function Test-IsAdmin {
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($current)
    return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Expand-Target($t) {
    if ($null -eq $t) { return $t }
    # Replace $env:NAME with the environment variable value
    $regex = [regex] '\$env:([A-Za-z0-9_]+)'
    $expanded = $regex.Replace($t, { param($m)
        $name = $m.Groups[1].Value
        $val = [Environment]::GetEnvironmentVariable($name)
        if ($null -eq $val) { return '' } else { return $val }
    })

    # Replace $PROFILE with PowerShell $PROFILE value
    $expanded = $expanded -replace '\$PROFILE', [Regex]::Escape($PROFILE) -replace '[\\]$',''

    # Normalize slashes to backslashes
    $expanded = $expanded -replace '/', '\\'

    return $expanded
}

function Run-GitUpdate($path) {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Warning "git not found in PATH. Skipping git update."
        return
    }

    Write-Host "Updating repository at: $path"
    try {
        # fetch and reset to origin/HEAD (force update)
        & git -C "$path" fetch --all --prune 2>&1 | ForEach-Object { Write-Host $_ }
        & git -C "$path" reset --hard origin/HEAD 2>&1 | ForEach-Object { Write-Host $_ }
        Write-Host "Git update finished."
    }
    catch {
        Write-Warning "Git update failed: $_"
    }
}

function Create-Link($source, $target) {
    # Determine if source is directory or file
    if (-not (Test-Path -LiteralPath $source)) {
        Write-Warning "Source does not exist: $source. Skipping."
        return
    }

    $isDir = (Get-Item -LiteralPath $source).PSIsContainer

    # Ensure parent directory of target exists
    $parent = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $parent)) {
        Write-Host "Creating parent directory: $parent"
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    # Build mklink command. Use /D for directory symbolic links.
    $flag = ''
    if ($isDir) { $flag = '/D' }

    # mklink syntax: mklink [options] "Link" "Target"
    $cmd = "mklink $flag `"$target`" `"$source`""

    Write-Host "Running: cmd.exe /c $cmd"
    $proc = Start-Process -FilePath cmd.exe -ArgumentList "/c", $cmd -NoNewWindow -Wait -PassThru
    if ($proc.ExitCode -eq 0) {
        Write-Host "Created link: $target -> $source"
    }
    else {
        Write-Error "mklink failed with exit code $($proc.ExitCode)."
    }
}

# --- Script entry ---
if (-not (Test-IsAdmin)) {
    Write-Error "This script must be run as Administrator. Please re-run from an elevated PowerShell prompt."
    exit 1
}

# Update repo
Run-GitUpdate -path $ScriptDir

# Read config.json
$configPath = Join-Path $ScriptDir 'config.json'
if (-not (Test-Path -LiteralPath $configPath)) {
    Write-Error "config.json not found at $configPath"
    exit 2
}

try {
    $mappings = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
}
catch {
    Write-Error "Failed to read or parse config.json: $_"
    exit 3
}

foreach ($map in $mappings) {
    $srcRel = $map.source
    $source = Join-Path $ScriptDir $srcRel
    $targetRaw = $map.target
    $targetExpanded = Expand-Target $targetRaw

    # If the expanded target is not rooted, treat it as relative to script dir
    if (-not [System.IO.Path]::IsPathRooted($targetExpanded)) {
        $targetExpanded = Join-Path $ScriptDir $targetExpanded
    }

    $targetExpanded = [System.IO.Path]::GetFullPath($targetExpanded)

    Write-Host "\nProcessing mapping:`n  Source: $source`n  Target: $targetExpanded"

    if (-not (Test-Path -LiteralPath $source)) {
        Write-Warning "Source path does not exist: $source. Skipping this entry."
        continue
    }

    if (Test-Path -LiteralPath $targetExpanded) {
        $ans = Read-Host "Target already exists. Delete it and create link? (y/N)"
        if ($ans -match '^(y|Y|yes|YES)$') {
            try {
                Remove-Item -LiteralPath $targetExpanded -Recurse -Force -ErrorAction Stop
                Write-Host "Removed existing target: $targetExpanded"
            }
            catch {
                Write-Warning "Failed to remove existing target: $_. Skipping this entry."
                continue
            }
        }
        else {
            Write-Host "User chose not to remove existing target. Skipping."
            continue
        }
    }

    # Create the symlink using mklink (requires admin)
    Create-Link -source $source -target $targetExpanded
}

Write-Host "\nAll mappings processed."

