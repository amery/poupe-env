#!/bin/sh

set -eu

err() {
	if [ $# -eq 0 ]; then
		cat
	else
		echo "$*"
	fi | sed -e 's|^|E:|g' >&2
}

die() {
	err "$@"
	exit 1
}

# Detect OS type
detect_os() {
	case "$(uname -s)" in
		Linux*)  echo "linux" ;;
		Darwin*) echo "macos" ;;
		*)       echo "unknown" ;;
	esac
}

OS_TYPE=$(detect_os)

# Platform-specific checks
case "$OS_TYPE" in
	macos)
		# Check for Homebrew on macOS
		if ! command -v brew >/dev/null 2>&1; then
			die <<-EOT
			Homebrew is required on macOS. Install from https://brew.sh
			Run: /bin/bash -c "\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
			EOT
		fi

		# Check for jq, offer to install if missing
		if ! command -v jq >/dev/null 2>&1; then
			die <<-EOT
			jq is required but not installed.
			Install with: brew install jq
			EOT
		fi

		# Docker socket location on macOS
		DOCKER_SOCKET="/var/run/docker.sock"
		if [ ! -S "$DOCKER_SOCKET" ]; then
			DOCKER_SOCKET="$HOME/.docker/run/docker.sock"
			if [ ! -S "$DOCKER_SOCKET" ]; then
				die <<-EOT
				Docker socket not found. Ensure Docker Desktop is running.
				Checked locations:
				  - /var/run/docker.sock
				  - $HOME/.docker/run/docker.sock
				EOT
			fi
		fi
		;;

	linux)
		# Check for jq on Linux
		if ! command -v jq >/dev/null 2>&1; then
			die <<-EOT
			jq is required but not installed.
			Install with:
			  Debian/Ubuntu: sudo apt-get install jq
			  RHEL/CentOS: sudo yum install jq
			  Arch: sudo pacman -S jq
			EOT
		fi

		# Check Docker permissions
		if ! docker info >/dev/null 2>&1; then
			die <<-EOT
			Cannot connect to Docker daemon. Ensure Docker is running and you have permissions.
			You may need to add your user to the docker group:
			  sudo usermod -aG docker $USER
			Then log out and back in.
			EOT
		fi
		;;

	*)
		die "Unsupported operating system: $(uname -s)"
		;;
esac

cd "$(dirname "$0")/.."

B=".devcontainer"
C=".docker-run-cache"

[ -n "${USER:-}" ] || USER=$(id -un)
[ -d "${HOME:-}" ] || die "no HOME"

# Renames a file only if the target file does not exist or differs from the source file.
#
# Args:
#   $1 - Temporary file path (source)
#   $2 - Target file path
#
# Behavior:
#   - If the target file is empty or different from the source, moves the source file to the target
#   - If the target file is identical, removes the source file
#   - Useful for atomic file updates with minimal changes
rename() {
	local T="$1" F="$2"

	if ! test -s "$F" || ! diff -u "$F" "$T" >&2; then
		mv "$T" "$F"
	else
		rm -f "$T"
	fi
}

# Dockerfile
#
DOCKERFILE=docker/Dockerfile

get_metadata() {
	local FROM=$(sed -n -e 's|^[\t ]*FROM[\t ]\+\([^\t ]\+\)[\t ]*$|\1|p' "$DOCKERFILE" | tail -n1)

	${DOCKER:-docker} inspect --format='{{index .Config.Labels "devcontainer.metadata"}}' "$FROM" || echo '[]'
}

metadata() {
	get_metadata | jq -c '. + [{"containerUser": $USER}]' --arg USER "$USER"
}

gen_dockerfile() {
	cat <<EOT
$(cat "$DOCKERFILE")

# bypassed entrypoint
#
RUN /devcontainer-init.sh "$USER" "$HOME" && rm -f /devcontainer-init.sh

# run as user
#
LABEL devcontainer.metadata='$(metadata)'

USER ${USER}
EOT
}

F="$B/Dockerfile"
T="$F.$$"
trap "rm -f '$T'" EXIT
gen_dockerfile > "$T"
rename "$T" "$F"

# devcontainer.json
#
gen_json_overlay() {
	local ws='${localWorkspaceFolder}'
	local home='${localEnv:HOME}'

	cat <<EOT
{
	"containerEnv": {
		"GOPATH": "$ws",
		"WS": "$ws",
		"CURDIR": "$ws"
	},
	"workspaceMount": "source=$ws,target=$ws,type=bind,consistency=cached",
	"workspaceFolder": "$ws",
	"mounts": [{
		"source": "$ws/$C/$home",
		"target": "$home",
		"type": "bind"
	}, {
		"source": "$home/.claude",
		"target": "$home/.claude",
		"type": "bind"
	}, {
		"source": "$home/.claude.json",
		"target": "$home/.claude.json",
		"type": "bind"
	}]
}
EOT
}


json_sanitize() {
	sed -e 's|//.*||g' -e '/^[[:space:]]*$/d' "$1" | jq -e .
}

json_merge() {
	jq -e -s '.[0] * .[1]' "$@" --indent 2
}

# devcontainer.json must exist in version control
F="$B/devcontainer.json"
[ -s "$F" ] || die "devcontainer.json not found or empty."

T0="$F.0.$$"
T1="$F.1.$$"
T2="$F.2.$$"
trap "rm -f '$T0' '$T1' '$T2'" EXIT

json_sanitize "$F" > "$T0"
gen_json_overlay > "$T1"
json_merge "$T0" "$T1" > "$T2"
rename "$T2" "$F"
rm -f "$T0" "$T1"

#
# mount points
#

# Bound directories (sandboxed)
for x in \
	"$HOME" \
	; do
	mkdir -p "$C$x"
done

# Host-bound directories
for x in \
	"$PWD" \
	"$HOME/.claude" \
	; do
	mkdir -p "$C$x" "$x"
done

# Host-bound files
for x in \
	"$HOME/.claude.json" \
	; do
	touch "$C$x"
	case "$x" in
	*.json)
		[ -s "$x" ] || echo '{}' > "$x"
		;;
	*)
		touch "$x"
		;;
	esac
done

echo "Devcontainer initialization completed successfully"
