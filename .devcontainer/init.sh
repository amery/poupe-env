#!/bin/sh

set -eu

cd "$(dirname "$0")/.."

F=".devcontainer/Dockerfile"
H=".docker-run-cache/home"

exec > "$F~"
trap "rm -f '$F~'" EXIT

cat docker/Dockerfile

cat <<EOT

VOLUME [ "${HOME}" ]

# User
RUN \\
	useradd -r -s /bin/bash -d "${HOME}" ${USER} && \\
	cp -a /etc/skel "${HOME}"

USER ${USER}
EOT

if ! test -s "$F" || ! diff -u "$F" "$F~" >&2; then
	mv "$F~" "$F"
fi

for x in $USER; do
	mkdir -p "$H/$x"
done
