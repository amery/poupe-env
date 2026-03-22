#!/bin/sh

set -eu

if [ -f /.dockerenv ]; then
	: # inside container, pass-through silently
elif ! command -v docker > /dev/null 2>&1; then
	echo "docker: command not found" >&2
elif ! DOCKER_BUILDER_RUN=$(command -v docker-builder-run); then
	echo "docker-builder-run: command not found" >&2
else
	set -- "$DOCKER_BUILDER_RUN" "$@"

	ME="$(readlink -f "$0")"
	export DOCKER_DIR="${ME%/*}"
	export DOCKER_RUN_WS="${DOCKER_DIR%/*}"

	# bind-mount Claude configuration
	export CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
	mkdir -p "$CLAUDE_CONFIG_DIR"
	[ -s "$HOME/.claude.json" ] || echo '{}' > "$HOME/.claude.json"

	export DOCKER_RUN_VOLUMES="${DOCKER_RUN_VOLUMES:+$DOCKER_RUN_VOLUMES }CLAUDE_CONFIG_DIR"
	export DOCKER_EXTRA_OPTS="${DOCKER_EXTRA_OPTS:+$DOCKER_EXTRA_OPTS }-v '$HOME/.claude.json:$HOME/.claude.json'"
fi

[ $# -gt 0 ] || set -- "${SHELL:-/bin/sh}"
exec "$@"
