# PowerShell initialization script for Windows devcontainer support
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-ErrorMessage {
    param([string]$Message)
    Write-Host "E: $Message" -ForegroundColor Red
}

function Stop-WithError {
    param([string]$Message)
    Write-ErrorMessage $Message
    exit 1
}

# Change to parent directory
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location (Split-Path -Parent $scriptPath)

$B = ".devcontainer"
$C = ".docker-run-cache"

# Get user and home information
if (-not $env:USERNAME) {
    Stop-WithError "no USERNAME environment variable"
}
# Sanitize username for Linux compatibility
# Replace spaces and invalid characters with underscores, convert to lowercase
$USER = $env:USERNAME -replace '[^a-zA-Z0-9._-]', '_' -replace '^[0-9]', '_$0' | ForEach-Object { $_.ToLower() }

if (-not $env:USERPROFILE) {
    Stop-WithError "no USERPROFILE"
}
# $HOME is an automatic variable; under Set-StrictMode shadowing it is a
# hazard. $UserHome is the real Windows home (e.g. C:\Users\amery); the
# container-side path is derived separately with ConvertTo-ContainerPath.
$UserHome = $env:USERPROFILE

# Function to rename file if different
function Rename-IfDifferent {
    param(
        [string]$TempFile,
        [string]$TargetFile
    )

    if (-not (Test-Path $TargetFile) -or (Get-Item $TargetFile).Length -eq 0) {
        Move-Item -Force $TempFile $TargetFile
    } elseif ((Get-FileHash $TempFile).Hash -ne (Get-FileHash $TargetFile).Hash) {
        Move-Item -Force $TempFile $TargetFile
    } else {
        Remove-Item $TempFile
    }
}

# Dockerfile generation
$DOCKERFILE = "docker/Dockerfile"

function Get-BaseImage {
    param([string]$FILE)

    Get-Content $FILE | Where-Object { $_ -match '^\s*FROM\s+(\S+)\s*$' } |
        ForEach-Object { $matches[1] } | Select-Object -Last 1
}

# docker inspect only sees local images; pull on first run so the base
# image's metadata label is readable instead of silently lost.
function Initialize-Image {
    param([string]$FROM)

    & docker image inspect $FROM 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { return }

    & docker pull $FROM
    if ($LASTEXITCODE -ne 0) {
        Stop-WithError "could not pull $FROM"
    }
}

function Get-Metadata {
    param([string]$FROM)

    try {
        $metadata = & docker inspect --format='{{index .Config.Labels "devcontainer.metadata"}}' $FROM 2>$null
        if ($LASTEXITCODE -ne 0) { return '[]' }
        return $metadata
    } catch {
        return '[]'
    }
}

function Get-UpdatedMetadata {
    param([string]$FROM)

    $metadata = Get-Metadata $FROM
    # ConvertFrom-Json yields $null for `[]` and a bare object for a
    # single-entry array, and Windows PowerShell 5.1's ConvertTo-Json unwraps a
    # one-element array back to a bare object. Force array context, then
    # serialise each entry and assemble the array by hand so
    # devcontainer.metadata stays a JSON array regardless of entry count or
    # PowerShell version.
    $items = @($metadata | ConvertFrom-Json)
    $items += @{containerUser = $USER}
    $parts = $items | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 10 }
    return "[$($parts -join ',')]"
}

# Function to translate Windows path to container path
function ConvertTo-ContainerPath {
    param([string]$WindowsPath)
    
    # Check if Docker is using WSL backend
    $dockerInfo = & docker version --format json 2>$null | ConvertFrom-Json
    $isWSL = $false
    
    if ($dockerInfo -and $dockerInfo.Server) {
        # Check for WSL in Docker context or OS info
        if ($dockerInfo.Server.Os -match 'linux' -and 
            ($env:WSL_DISTRO_NAME -or (& docker context ls 2>$null | Select-String 'wsl'))) {
            $isWSL = $true
        }
    }
    
    # Convert path based on Docker backend
    if ($isWSL) {
        # WSL format: /mnt/c/Users/...
        return $WindowsPath -replace '^([A-Z]):\\', '/mnt/$1/' -replace '\\', '/' | 
               ForEach-Object { $_.ToLower() }
    } else {
        # Docker Desktop format: /c/Users/...
        return $WindowsPath -replace '^([A-Z]):\\', '/$1/' -replace '\\', '/'
    }
}

# Generate Dockerfile content
function New-Dockerfile {
    param([string]$FROM)

    $baseContent = Get-Content $DOCKERFILE -Raw
    $metadata = Get-UpdatedMetadata $FROM
    # Translate Windows home path to container path
    $containerHome = ConvertTo-ContainerPath $env:USERPROFILE

    return @"
$baseContent

# bypassed entrypoint
#
RUN /devcontainer-init.sh "$USER" "$containerHome" && rm -f /devcontainer-init.sh

# run as user
#
LABEL devcontainer.metadata='$metadata'

USER $USER
"@
}

# Write Dockerfile
$FROM = Get-BaseImage $DOCKERFILE
Initialize-Image $FROM
$F = "$B/Dockerfile"
$T = "$F.tmp"
New-Dockerfile $FROM | Out-File -Encoding UTF8 -NoNewline $T
Rename-IfDifferent $T $F

# Generate JSON overlay
function New-JsonOverlay {
    # Note: VSCode variables will be resolved at runtime
    # Translate Windows paths to container paths
    
    # Translate paths
    $containerHome = ConvertTo-ContainerPath $env:USERPROFILE
    $workspaceFolder = ConvertTo-ContainerPath $PWD.Path
    
    $overlay = @{
        containerEnv = @{
            GOPATH = $workspaceFolder
            WS = $workspaceFolder
            CURDIR = $workspaceFolder
        }
        workspaceMount = 'source=${localWorkspaceFolder},target=' + $workspaceFolder + ',type=bind,consistency=cached'
        workspaceFolder = $workspaceFolder
        mounts = @(
            @{
                # The sandboxed-home source cannot use the ${localEnv:USERPROFILE}
                # token: it resolves to C:\Users\... and would embed a drive
                # colon mid-path. Bake the translated container path instead.
                source = '${localWorkspaceFolder}/' + $C + $containerHome
                target = $containerHome
                type = 'bind'
            },
            @{
                source = '${localEnv:USERPROFILE}/.claude'
                target = "$containerHome/.claude"
                type = 'bind'
            },
            @{
                source = '${localEnv:USERPROFILE}/.claude.json'
                target = "$containerHome/.claude.json"
                type = 'bind'
            }
        )
    }
    return $overlay | ConvertTo-Json -Depth 10
}

# Merge JSON files
function Merge-JsonFiles {
    param(
        [string]$BaseFile,
        [string]$OverlayContent
    )

    $base = Get-Content $BaseFile | ConvertFrom-Json
    $overlay = $OverlayContent | ConvertFrom-Json

    # Simple merge - overlay wins
    foreach ($key in $overlay.PSObject.Properties.Name) {
        $base.$key = $overlay.$key
    }

    return $base | ConvertTo-Json -Depth 10
}

# Update devcontainer.json
$F = "$B/devcontainer.json"
$TEMPLATE = "$B/devcontainer.json.template"

# Use template if devcontainer.json doesn't exist
if (-not (Test-Path $F) -and (Test-Path $TEMPLATE)) {
    Copy-Item $TEMPLATE $F
}

$T = "$F.tmp"
$overlayJson = New-JsonOverlay
$mergedJson = Merge-JsonFiles $F $overlayJson
$mergedJson | Out-File -Encoding UTF8 -NoNewline $T
Rename-IfDifferent $T $F

# Create mount points
#
# Cache-side mount points live under $C keyed by the *container* (translated,
# POSIX-style) path, so they match the overlay's resolved mount sources; real
# host directories and files are created at their Windows paths. On Linux the
# two coincide, on Windows they diverge, so each entry carries both.
$containerHome = ConvertTo-ContainerPath $env:USERPROFILE
$workspaceFolder = ConvertTo-ContainerPath $PWD.Path

# Bound directory (sandboxed home)
New-Item -ItemType Directory -Force -Path "$C$containerHome" | Out-Null

# Host-bound directories: the real host path plus its cache-side mount point
@(
    @{ Host = $PWD.Path;           Container = $workspaceFolder },
    @{ Host = "$UserHome/.claude"; Container = "$containerHome/.claude" }
) | ForEach-Object {
    New-Item -ItemType Directory -Force -Path "$C$($_.Container)" | Out-Null
    New-Item -ItemType Directory -Force -Path $_.Host | Out-Null
}

# Host-bound files
@(
    @{ Host = "$UserHome/.claude.json"; Container = "$containerHome/.claude.json" }
) | ForEach-Object {
    New-Item -ItemType File -Force -Path "$C$($_.Container)" | Out-Null

    if ($_.Host -match '\.json$') {
        if (-not (Test-Path $_.Host) -or (Get-Item $_.Host).Length -eq 0) {
            '{}' | Out-File -Encoding UTF8 -NoNewline $_.Host
        }
    } else {
        New-Item -ItemType File -Force -Path $_.Host | Out-Null
    }
}

Write-Host "Devcontainer initialization completed successfully"
