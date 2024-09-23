#!/bin/sh

set -eu

export DOCKER_RUN_WS="$(dirname "$0")"
export DOCKER_DIR="$(dirname "$(readlink -f "$0")")"

exec docker-builder-run "$@"
