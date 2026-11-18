#!/bin/sh
# Bind-mounts single host config files (AGENTS.md, CLAUDE.md, settings.json)
# read-only on top of the data directories, as the README documents, and
# checks that the CLIs can read them, the data directories stay writable, and
# the Feature never changes the files' ownership.
set -eu

case "$(uname -s)" in
    MINGW*|MSYS*) export MSYS_NO_PATHCONV=1 ;;
esac

IMAGE="codex-remote-config-mounts-test"
CONTAINER="codex-remote-config-mounts-test-$$"
HOST_DIR="$(mktemp -d)"

cleanup() {
    docker rm -f -v "$CONTAINER" >/dev/null 2>&1 || true
    rm -rf "$HOST_DIR"
}
trap cleanup EXIT HUP INT TERM

# Docker Desktop on Windows needs a Windows path for bind mounts.
host_path() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$1"
    else
        printf '%s\n' "$1"
    fi
}

printf '%s\n' '# codex agents' > "$HOST_DIR/AGENTS.md"
printf '%s\n' '# claude memory' > "$HOST_DIR/CLAUDE.md"
printf '%s\n' '{"model": "test"}' > "$HOST_DIR/settings.json"
chmod 0644 "$HOST_DIR"/*

docker build -q -f test/manual/Dockerfile \
    --build-arg BASE_IMAGE="${BASE_IMAGE:-debian:bookworm}" \
    --build-arg INSTALL_CODEX=true \
    --build-arg INSTALL_CLAUDE_CODE=true \
    -t "$IMAGE" . >/dev/null

docker run -d --name "$CONTAINER" \
    --mount "type=bind,source=$(host_path "$HOST_DIR/AGENTS.md"),target=/usr/local/share/codex-data/AGENTS.md,readonly" \
    --mount "type=bind,source=$(host_path "$HOST_DIR/CLAUDE.md"),target=/usr/local/share/claude-data/CLAUDE.md,readonly" \
    --mount "type=bind,source=$(host_path "$HOST_DIR/settings.json"),target=/usr/local/share/claude-data/settings.json,readonly" \
    "$IMAGE" >/dev/null

# The entrypoint initializes the data directories and starts sshd.
TRIES=0
until docker exec "$CONTAINER" nc -z 127.0.0.1 22 >/dev/null 2>&1; do
    TRIES=$((TRIES + 1))
    if [ "$TRIES" -ge 30 ] || [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER")" != true ]; then
        docker logs "$CONTAINER" >&2 || true
        echo "config-mounts test: container did not start sshd." >&2
        exit 1
    fi
    sleep 1
done

docker exec "$CONTAINER" sh -eu -c '
    test "$(cat "$CODEX_HOME/AGENTS.md")" = "# codex agents"
    test "$(cat "$CLAUDE_CONFIG_DIR/CLAUDE.md")" = "# claude memory"
    test "$(cat "$CLAUDE_CONFIG_DIR/settings.json")" = "{\"model\": \"test\"}"
    # Login state is still written next to the read-only files.
    touch "$CODEX_HOME/.login-test" "$CLAUDE_CONFIG_DIR/.login-test"
    # The files are mounted read-only, so the container cannot change them.
    ! sh -c ": >> \"$CODEX_HOME/AGENTS.md\"" 2>/dev/null
    codex --version >/dev/null
    claude --version >/dev/null
'

# A restart runs initialization again; the host files must be untouched.
docker restart "$CONTAINER" >/dev/null
docker exec "$CONTAINER" test -f /usr/local/share/codex-data/.login-test
docker exec "$CONTAINER" test -f /usr/local/share/claude-data/.login-test
EXPECTED_OWNER="$(id -u)"
for FILE in AGENTS.md CLAUDE.md settings.json; do
    test "$(stat -c %u "$HOST_DIR/$FILE")" = "$EXPECTED_OWNER"
done
test "$(cat "$HOST_DIR/AGENTS.md")" = "# codex agents"

echo "config-mounts test: passed."
