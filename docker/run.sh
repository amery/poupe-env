#!/bin/sh

set -eu

# run.sh relies on docker-builder-run behaviour introduced in v1.23;
# refuse to trampoline through an older release that lacks it. The
# minimum is stored pre-encoded: 102300 is ver_to_num's rendering of
# 1.23 (major*100000 + minor*100 + patch).
RUN_MIN_VERSION=102300

# ver_to_num <major.minor.patch>
# Fold a dotted version into one comparable integer,
# major*100000 + minor*100 + patch, so "1.23" and "1.23.0" both become
# 102300. A missing minor or patch counts as 0; minor spans 0-999 and
# patch 0-99 before they would carry into the next field.
ver_to_num() {
	oldifs=$IFS
	IFS=.
	# split the dotted version into the positional parameters
	# shellcheck disable=SC2086
	set -- $1
	IFS=$oldifs
	echo $(( ${1:-0} * 100000 + ${2:-0} * 100 + ${3:-0} ))
}

# require_run_version <docker-builder-run> <min-decimal>
# Succeed when the resolved docker-builder-run is at least <min-decimal>
# (a ver_to_num-encoded minimum). Its -V banner prints
# "docker-builder-run <version>" on stderr before exiting non-zero, so
# merge stderr and read the version off that first line.
require_run_version() {
	ver=$("$1" -V 2>&1 | sed -n 's/^docker-builder-run //p')

	if [ -z "$ver" ]; then
		echo "docker-builder-run: cannot determine version" >&2
		return 1
	fi

	if [ "$(ver_to_num "$ver")" -lt "$2" ]; then
		echo "docker-builder-run $ver is too old, need >= 1.23" >&2
		return 1
	fi
}

if [ -f /.dockerenv ]; then
	: # inside container, pass-through silently
elif ! command -v docker > /dev/null 2>&1; then
	echo "docker: command not found" >&2
elif ! DOCKER_BUILDER_RUN=$(command -v docker-builder-run); then
	echo "docker-builder-run: command not found" >&2
elif ! require_run_version "$DOCKER_BUILDER_RUN" "$RUN_MIN_VERSION"; then
	: # require_run_version reported the reason on stderr
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

	# forward GPG agent socket for commit signing
	GPG_SOCK_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gnupg"
	if [ -d "$GPG_SOCK_DIR" ]; then
		export DOCKER_EXTRA_OPTS="${DOCKER_EXTRA_OPTS:+$DOCKER_EXTRA_OPTS }-v '$GPG_SOCK_DIR:$GPG_SOCK_DIR'"
	fi

	# expose host as host.docker.internal — Docker resolves the
	# host-gateway sentinel to the bridge gateway IP at container
	# start, replacing the brittle pattern of hard-coding 172.17.0.1.
	export DOCKER_EXTRA_OPTS="${DOCKER_EXTRA_OPTS:+$DOCKER_EXTRA_OPTS }--add-host=host.docker.internal:host-gateway"
fi

[ $# -gt 0 ] || set -- "${SHELL:-/bin/sh}"
exec "$@"
