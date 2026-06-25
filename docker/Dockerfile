# syntax=docker/dockerfile:1
FROM quay.io/amery/docker-apptly-builder:latest

# Bake the host-Ollama profile snippet in inline (not COPY/bind-mount) so it
# behaves identically under docker-builder-run and the generated devcontainer
# build. Quoted heredoc tag keeps $vars literal — they expand at login.
RUN cat > /etc/profile.d/ollama.sh <<'SH'
# Point CLI clients at the host's Ollama daemon, reachable inside the
# container as host.docker.internal, not localhost. POSIX sh, no `set -e`
# (runs in the caller's login shell).
if test -z "${OLLAMA_HOST:-}" && getent hosts host.docker.internal >/dev/null; then
	export OLLAMA_HOST=host.docker.internal:11434
fi

# srclight has no Ollama-host override, so it rides Ollama's OpenAI-compat
# API. Derive the base URL from OLLAMA_HOST (no trailing /v1 — the provider
# appends /v1/embeddings). Skip if a real OpenAI endpoint was set earlier.
if [ -z "${OPENAI_BASE_URL:-}" -a -n "${OLLAMA_HOST:-}" ]; then
	export OPENAI_BASE_URL="http://$OLLAMA_HOST"
	export OPENAI_API_KEY=ollama
	export SRCLIGHT_EMBED_REQUEST_TIMEOUT="${SRCLIGHT_EMBED_REQUEST_TIMEOUT:-120}"
fi
SH
