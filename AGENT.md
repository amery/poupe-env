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
   - `.claude` directory for Claude AI configuration
   - `.claude.json` for Claude AI state persistence

### Initialization Process

The `.devcontainer/init.sh` script prepares the environment:

1. Generates a custom Dockerfile with user-specific metadata
2. Creates JSON overlay with mount configurations
3. Merges overlay into existing `devcontainer.json`
4. Creates mount points for both sandboxed and host-bound resources
5. Handles JSONC (JSON with Comments) format used by VS Code

Key functions in `init.sh`:

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

Mount point creation:

- **Sandboxed directories**: `.docker-run-cache/$HOME`
- **Host-bound directories**: `.claude` (created in both locations)
- **Host-bound files**: `.claude.json` (touched in cache, initialized with `{}` on host if empty)

## How init.sh Works

The initialization script is the key to the DevContainer's flexibility.
Here's a detailed breakdown of its operation:

### Execution Context

- **When**: Triggered by VS Code via `initializeCommand` before container
  creation
- **Where**: Runs on the HOST machine (not in container)
- **Requirements**: Needs Docker access to inspect base image metadata

### Step-by-Step Process

1. **Environment Setup**:

   ```sh
   cd "$(dirname "$0")/.."  # Navigate to project root
   B=".devcontainer"        # DevContainer directory
   C=".docker-run-cache"    # Cache directory for mounts
   ```

2. **Dockerfile Generation**:
   - Reads `docker/Dockerfile` as the base
   - Extracts metadata from base image using Docker inspect
   - Appends user-specific configuration:
     - Runs `/devcontainer-init.sh` to bypass entrypoint (without verbose output)
     - Sets container user to match host user
     - Adds devcontainer metadata label with `containerUser` field

3. **JSON Configuration Merge**:
   - **Step 1**: Sanitize existing `devcontainer.json` (remove comments)
   - **Step 2**: Generate overlay with mount configurations
   - **Step 3**: Merge overlay with existing config (overlay wins)
   - **Step 4**: Write result with 2-space indentation

4. **Mount Point Preparation**:
   - Creates isolated container home: `$C$HOME`
   - Creates host-bound directories in both locations:
     - `$PWD` (current directory)
     - `$HOME/.claude` (AI config directory)
   - Handles host-bound files:
     - `$HOME/.claude.json`: Touched in cache, initialized with `{}` on host if empty
     - Uses case pattern to handle JSON files specially

### Key Design Decisions

- **Atomic Updates**: Uses temp files + rename to avoid partial writes
- **Idempotent**: Can run multiple times safely
- **Non-Destructive**: Only updates files if they differ
- **Error Handling**: Uses `set -eu` for strict error checking

### File Flow Diagram

```text
docker/Dockerfile → gen_dockerfile() → .devcontainer/Dockerfile
                         ↓
                    (adds user metadata)

devcontainer.json → json_sanitize() → clean JSON
                          ↓
gen_json_overlay() → mount config → json_merge() → updated JSON
                                          ↓
                                    devcontainer.json
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

1. **First Time Setup**:
   - Clone the repository
   - `initializeCommand` in devcontainer.json runs init.sh automatically

2. **Container Lifecycle**:
   - Container creation triggers init.sh via `initializeCommand`
   - init.sh runs on the HOST (not in container) with Docker access
   - Dockerfile is generated with current user metadata
   - JSON overlay is merged with existing devcontainer.json
   - Mount points created in .docker-run-cache and host as needed
   - Claude configuration files are ensured to exist

3. **Persistence**:
   - Container-specific configurations persist in `.docker-run-cache/${HOME}`
   - Claude configurations are shared via bind mounts
   - Workspace remains mounted at the same path as the host

## Code Quality Standards

### Markdown Files

- All markdown files must be tested against markdownlint
- Use 2-space indentation (per .editorconfig)
- Lines should be shorter than 78 characters
- Files must end with a single newline
- Fix any markdownlint violations before committing

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

## Integration with AI Tools

The devcontainer is configured for seamless AI assistant integration:

- `.claude` directory is bind-mounted for configuration persistence
- `.claude.json` is bind-mounted for state persistence
- Workspace path remains consistent between host and container
- Environment variables properly set (GOPATH, WS, CURDIR)

This architecture ensures AI assistants have consistent access to their
configuration while working in an isolated container environment.

## Relationship with docker-builder

This project demonstrates how to extend docker-builder for specific use cases:

1. **Base Image Usage**: Extends `quay.io/amery/docker-apptly-builder:latest`
   from docker-builder
2. **Run Script Integration**: Symlinks to docker-builder's `run.sh` for
   consistent container execution
3. **DevContainer Extension**: Adds VS Code DevContainer configuration on top
   of docker-builder's base images

When working with both projects:

- **docker-builder changes**: Affect all environments using its base images
- **dev-env changes**: Only affect this specific DevContainer environment
- **Coordination needed**: Major changes to docker-builder's run.sh or base
  images may require updates here

For docker-builder implementation details, see:
https://github.com/amery/docker-builder/blob/master/AGENT.md
