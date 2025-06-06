# PowerShell initialization script for Windows devcontainer support
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Error-Message {
    param([string]$Message)
    Write-Host "E: $Message" -ForegroundColor Red
}

function Exit-With-Error {
    param([string]$Message)
    Write-Error-Message $Message
    exit 1
}

# Change to parent directory
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location (Split-Path -Parent $scriptPath)

$B = ".devcontainer"
$C = ".docker-run-cache"

# Get user and home information
if (-not $env:USERNAME) {
    Exit-With-Error "no USERNAME environment variable"
}
# Sanitize username for Linux compatibility
# Replace spaces and invalid characters with underscores, convert to lowercase
$USER = $env:USERNAME -replace '[^a-zA-Z0-9._-]', '_' -replace '^[0-9]', '_$0' | ForEach-Object { $_.ToLower() }

if (-not $env:USERPROFILE) {
    Exit-With-Error "no USERPROFILE"
}
$HOME = $env:USERPROFILE

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

function Get-Metadata {
    $FROM = Get-Content $DOCKERFILE | Where-Object { $_ -match '^\s*FROM\s+(.+)\s*$' } |
            ForEach-Object { $matches[1] } | Select-Object -Last 1

    try {
        $metadata = & docker inspect --format='{{index .Config.Labels "devcontainer.metadata"}}' $FROM 2>$null
        if ($LASTEXITCODE -ne 0) { return '[]' }
        return $metadata
    } catch {
        return '[]'
    }
}

function Get-UpdatedMetadata {
    $metadata = Get-Metadata
    # Convert to JSON object, add containerUser, convert back
    $jsonObj = $metadata | ConvertFrom-Json
    $jsonObj += @{containerUser = $USER}
    return ($jsonObj | ConvertTo-Json -Compress)
}

# Function to translate Windows path to container path
function Convert-ToContainerPath {
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
function Generate-Dockerfile {
    $baseContent = Get-Content $DOCKERFILE -Raw
    $metadata = Get-UpdatedMetadata
    # Translate Windows home path to container path
    $containerHome = Convert-ToContainerPath $env:USERPROFILE

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
$F = "$B/Dockerfile"
$T = "$F.tmp"
Generate-Dockerfile | Out-File -Encoding UTF8 -NoNewline $T
Rename-IfDifferent $T $F

# Generate JSON overlay
function Generate-JsonOverlay {
    # Note: VSCode variables will be resolved at runtime
    # Translate Windows paths to container paths
    
    # Translate paths
    $containerHome = Convert-ToContainerPath $env:USERPROFILE
    $workspaceFolder = Convert-ToContainerPath $PWD.Path
    
    $overlay = @{
        containerEnv = @{
            GOPATH = $workspaceFolder
            WS = $workspaceFolder
            CURDIR = $workspaceFolder
        }
        workspaceMount = "source=${localWorkspaceFolder},target=$workspaceFolder,type=bind,consistency=cached"
        workspaceFolder = $workspaceFolder
        mounts = @(
            @{
                source = '${localWorkspaceFolder}/.docker-run-cache/${localEnv:USERPROFILE}'
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
$overlayJson = Generate-JsonOverlay
$mergedJson = Merge-JsonFiles $F $overlayJson
$mergedJson | Out-File -Encoding UTF8 -NoNewline $T
Rename-IfDifferent $T $F

# Create mount points
# Bound directories (sandboxed)
New-Item -ItemType Directory -Force -Path "$C$HOME" | Out-Null

# Host-bound directories
@(
    $PWD.Path,
    "$HOME/.claude"
) | ForEach-Object {
    New-Item -ItemType Directory -Force -Path "$C$_" | Out-Null
    New-Item -ItemType Directory -Force -Path $_ | Out-Null
}

# Host-bound files
@(
    "$HOME/.claude.json"
) | ForEach-Object {
    $cachePath = "$C$_"
    New-Item -ItemType File -Force -Path $cachePath | Out-Null

    if ($_ -match '\.json$') {
        if (-not (Test-Path $_) -or (Get-Item $_).Length -eq 0) {
            '{}' | Out-File -Encoding UTF8 -NoNewline $_
        }
    } else {
        New-Item -ItemType File -Force -Path $_ | Out-Null
    }
}

Write-Host "Devcontainer initialization completed successfully"
