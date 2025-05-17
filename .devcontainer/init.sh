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

cd "$(dirname "$0")/.."

B=".devcontainer"
C=".docker-run-cache"


[ -n "${USER:-}" ] || USER=$(id -un)
[ -d "${HOME:-}" ] || die "no HOME"

DOCKERFILE=docker/Dockerfile

get_metadata() {
	local FROM=$(sed -n -e 's|^[\t ]*FROM[\t ]\+\([^\t ]\+\)[\t ]*$|\1|p' "$DOCKERFILE" | tail -n1)

	${DOCKER:-docker} inspect --format='{{index .Config.Labels "devcontainer.metadata"}}' "$FROM" || echo '[]'
}

metadata() {
	get_metadata | jq -c '. + [{"remoteUser": $user}]' --arg user "$USER"
}

rename() {
	local T="$1" F="$2"

	if ! test -s "$F" || ! diff -u "$F" "$T" >&2; then
		mv "$T" "$F"
	else
		rm -f "$T"
	fi
}

gen_dockerfile() {
	cat "$DOCKERFILE"

	cat <<EOT

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

mkdir -p "$C${HOME}" "$C${PWD}"
