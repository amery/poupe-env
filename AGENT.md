# Agent Development Guide

Technical implementation details for AI agents and developers working with
this codebase. For general setup instructions, see [README.md](./README.md).

**IMPORTANT**: When making changes to the DevContainer setup, initialization
process, or mount configuration, you MUST update both AGENT.md and README.md
to reflect the changes before committing. This ensures documentation stays
accurate and synchronized.

## Quick Reference

- **Container Home**: `.docker-run-cache/${HOME}`
- **Config Mounts**: `.claude/` and `.claude.json` from host
- **Init Script**: `.devcontainer/init.sh` (runs on host before container)
- **Key Files**: `devcontainer.json`, `docker/Dockerfile`, `run.sh`
- **Base Image**: `amery/docker-builder` (Ubuntu + VS Code + Go + Node.js)

## DevContainer Architecture

This project uses VS Code DevContainers with a custom sandboxed home
directory approach to provide isolated development environments while
preserving access to essential host resources.

### Security Configuration

The DevContainer runs with elevated privileges to enable advanced development
scenarios:

- **`NET_ADMIN`**: Network administration for debugging network configurations
- **`SYS_PTRACE`**: Process tracing for debugging tools (gdb, strace)
- **AppArmor Unconfined**: Disabled AppArmor restrictions
- **Seccomp Unconfined**: Unrestricted system calls

**WARNING**: These settings significantly reduce container security. This
configuration is intended ONLY for trusted development environments, not for
production use.

### Foundation: docker-builder

This project builds upon [amery/docker-builder](https://github.com/amery/docker-builder),
which provides:

- **Base Images**: The `docker-apptly-builder` image used as foundation
- **Run Script**: The `docker/run.sh` wrapper for container execution
- **Build System**: Automated Docker image building and management

See the [docker-builder documentation](https://github.com/amery/docker-builder/blob/master/AGENT.md)
for details on the underlying infrastructure.

### Sandboxed Home Directory

The container uses `.docker-run-cache/${HOME}` as an isolated home directory:

- Prevents container modifications from affecting the host home directory
- Maintains clean separation between host and container environments
- Allows persistence of container-specific configurations

### Bind Mount Strategy

The devcontainer selectively shares resources between host and container:

1. **Workspace**: Mounted at the same path as on host for consistency
2. **Sandboxed Home**: Container home at `.docker-run-cache/${HOME}`
3. **Tool Configs**: Specific directories bind-mounted from host:
   - `.claude` directory for Claude AI configuration persistence
   - `.claude.json` for Claude AI state persistence

This architecture ensures AI assistants have consistent access to their
configuration while working in an isolated container environment.

## How Initialization Works

The initialization provides cross-platform flexibility through a Node.js
entry point that detects the OS and runs platform-specific scripts:

### Execution Context

- **When**: Triggered by VS Code via `initializeCommand` before container
  creation
- **Where**: Runs on the HOST machine (not in container)
- **Entry**: `node .devcontainer/init.js` detects OS and runs appropriate
  script
- **Requirements**: Node.js (for init.js) and Docker access to inspect base
  image metadata

Key functions in platform scripts:

- `gen_dockerfile`: Extends base Dockerfile with user metadata
  - Uses `containerUser` in metadata label (not `remoteUser`)
  - Removes verbose shell execution (`sh` instead of `sh -x`)
- `gen_json_overlay`: Creates mount configuration including:
  - Sandboxed home directory mount
  - Claude directory bind mount
  - Claude JSON file bind mount
- `json_sanitize`: Strips comments from JSONC files with validation
- `json_merge`: Merges JSON configurations with 2-space formatting
- `rename`: Atomic file updates to avoid race conditions

### Step-by-Step Process

#### Common Steps (All Platforms)

1. **OS Detection** (init.js):
   - Uses `process.platform` to detect Windows (`win32`) vs Unix
   - Launches platform-specific script with appropriate interpreter

2. **Environment Setup**:
   - Navigate to project root
   - Set up directory variables:
     - `B=".devcontainer"` - DevContainer directory
     - `C=".docker-run-cache"` - Cache directory for mounts

3. **Dockerfile Generation**:
   - Reads `docker/Dockerfile` as the base
   - Extracts metadata from base image using Docker inspect
   - Appends user-specific configuration:
     - Runs `/devcontainer-init.sh` with username and home path
     - Sets container user to match host user
     - Adds devcontainer metadata label with `containerUser` field
   - **Platform differences**:
     - Linux/macOS: Uses `$HOME` directly
     - Windows: Translates paths (see Windows-specific section)

4. **JSON Configuration Merge**:
   - **Step 1**: Sanitize existing `devcontainer.json` (remove comments)
   - **Step 2**: Generate overlay with mount configurations
   - **Step 3**: Merge overlay with existing config (overlay wins)
   - **Step 4**: Write result with 2-space indentation
   - **Platform differences**:
     - Linux/macOS: Uses `${localEnv:HOME}` for paths
     - Windows: Uses `${localEnv:USERPROFILE}` with path translation

5. **Mount Point Preparation**:
   - Creates isolated container home: `${C}${HOME}` (or
     `${C}${USERPROFILE}` on Windows)
     - Note: `$HOME` includes leading slash, so becomes `.docker-run-cache/home/username`
   - Creates host-bound directories in both locations:
     - `$PWD` (current directory)
     - `$HOME/.claude` (AI config directory) or `$USERPROFILE/.claude` on
       Windows
   - Handles host-bound files:
     - `.claude.json`: Touched in cache, initialized with `{}` on host if
       empty
   - Uses case pattern to handle JSON files specially

### Platform-Specific Details

#### Windows (init.ps1)

- **Username Sanitization**: Windows usernames may contain spaces or special
  characters
  - Replaces invalid characters with underscores
  - Prepends underscore if starting with number
  - Converts to lowercase for Linux compatibility
- **Path Translation**: Converts Windows paths to container paths
  - Detects Docker backend (WSL vs Docker Desktop)
  - WSL format: `C:\Users\john` → `/mnt/c/users/john`
  - Docker Desktop: `C:\Users\john` → `/c/Users/john`
  - Applied to both workspace and home directories
- **Environment Variables**:
  - Uses `$env:USERNAME` and `$env:USERPROFILE`
  - Translates to Linux equivalents for container

#### Linux/macOS (init.sh)

- **Direct Path Usage**: Native paths work without translation
- **macOS Specifics**:
  - Checks for Docker socket in multiple locations
  - Requires Homebrew and jq installation
- **Environment Variables**: Uses standard `$HOME` and `$USER`

### Key Design Decisions

- **Cross-Platform Entry**: Node.js provides consistent OS detection
- **Atomic Updates**: Uses temp files + rename to avoid partial writes
- **Idempotent**: Can run multiple times safely
- **Non-Destructive**: Only updates files if they differ
- **Error Handling**: Strict error checking (bash `set -eu`, PowerShell
  `$ErrorActionPreference`)

### File Flow Diagram

```text
                    init.js (Node.js)
                         ↓
              ┌──────────┴──────────┐
              │                     │
         Windows               Unix/Linux/macOS
              │                     │
         init.ps1              init.sh
              │                     │
              └──────────┬──────────┘
                         ↓
docker/Dockerfile → generate_dockerfile → .devcontainer/Dockerfile
                         ↓
                  (adds user metadata)

devcontainer.json → sanitize → clean JSON
                         ↓
generate_overlay → mount config → merge → updated devcontainer.json
                         ↓
                 (platform-specific paths)
```

## Verification and Debugging

### Mount Verification

To verify mounts are working correctly inside the container:

```bash
# Check for bind mounts
mount | grep bind | grep -E "(claude|docker-run-cache)"

# Or use findmnt
findmnt -t bind | grep -E "(${USER}|claude)"
```

Expected output should show bind mounts, not ext4 filesystem mounts.

### Common Issues

1. **Mount not appearing**: Rebuild container after configuration changes
2. **Permission errors**: Ensure directories exist before container creation
3. **JSONC parsing**: The `json_sanitize` function handles VS Code's format

## Development Workflow

### Submodule Management

This project uses Git submodules. Proper initialization is critical:

1. **Recursive Clone (Recommended)**:

   ```bash
   git clone --recursive https://github.com/amery/apptly-dev
   cd apptly-dev/dev-env
   ```

2. **If You Forgot --recursive**:

   ```bash
   # From within the cloned repository
   git submodule update --init --recursive
   ```

3. **Updating Submodules**:

   ```bash
   # Update to latest commits
   git submodule update --remote --merge

   # Check submodule status
   git submodule status
   ```

**IMPORTANT**: Submodules MUST be initialized before creating the
DevContainer. The container build will fail if submodules are missing.

### First Time Setup

1. Clone the repository with submodules (see above)
2. `initializeCommand` in devcontainer.json runs init.sh automatically
3. VS Code will build and start the DevContainer

## Code Quality Standards

### Markdown Files

- All markdown files must be tested against markdownlint
- Lists under numbered items require blank lines:
  - Add blank line before starting a bullet list under a numbered item
  - Add blank line after the numbered item before the sub-list
- Use consistent indentation for nested lists:
  - Sub-items under bullets: indent 2 spaces
  - Third-level items: indent 4 spaces
- Code blocks within lists should be indented to align with list text
- Lines should be shorter than 78 characters where practical
- Files must end with a single newline
- Fix any markdownlint violations before committing
- Test with `pnpx markdownlint-cli <filename>`

#### Markdown List Format Example

```markdown
1. **First level numbered item**

- Bullet list needs blank line before it
- Another bullet at same level

2. **Second numbered item**

- Sub-list with blank line separation
  - Nested item (2 space indent)
  - Another nested item
```

### VS Code Diagnostics

- Review VS Code diagnostics for all modified files
- Address any warnings or errors reported by the IDE
- Use the `mcp__ide__getDiagnostics` tool to check for issues

### EditorConfig Rules

Key rules from `.editorconfig`:

- **All files**: UTF-8, LF line endings, final newline, trim trailing spaces
- **Markdown**: 2-space indentation, preserve trailing spaces
- **JSON/YAML**: 2-space indentation
- **Shell scripts**: Tab indentation (size 8)

When working with docker-builder:

- **docker-builder changes**: Affect all environments using its base images
- **dev-env changes**: Only affect this specific DevContainer environment
- **Coordination needed**: Major changes to docker-builder's run.sh or base
  images may require updates here

For docker-builder implementation details, see the
[docker-builder AGENT documentation][docker-builder-agent].

[docker-builder-agent]: https://github.com/amery/docker-builder/blob/master/AGENT.md
