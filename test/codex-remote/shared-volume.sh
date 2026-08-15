#!/bin/sh
set -eu

case "$(uname -s)" in
    MINGW*|MSYS*) export MSYS_NO_PATHCONV=1 ;;
esac

VOLUME_NAME="codex-data"
MOUNT_TARGET="/usr/local/share/codex-data"
PROJECT_A="codex-volume-test-a"
PROJECT_B="codex-volume-test-b"
COMPOSE_FILE="test/codex-remote/compose.shared-volume.yaml"
MARKER_NAME=".codex-remote-shared-volume-test-$$"
HOST_MARKER_NAME=".codex-remote-host-installer-test-$$"
MARKER="$MOUNT_TARGET/$MARKER_NAME"

cleanup() {
    docker compose -p "$PROJECT_A" -f "$COMPOSE_FILE" down >/dev/null 2>&1 || true
    docker compose -p "$PROJECT_B" -f "$COMPOSE_FILE" down >/dev/null 2>&1 || true
    if docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
        docker run --rm -v "$VOLUME_NAME:/data" alpine:3.20 \
            rm -f "/data/$MARKER_NAME" "/data/$HOST_MARKER_NAME" \
            >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT HUP INT TERM

node -e '
    const manifest = require("./src/codex-remote/devcontainer-feature.json");
    const mount = manifest.mounts.find(({ source }) => source === "codex-data");
    const allowedKeys = new Set(["source", "target", "type"]);
    if (!mount || mount.target !== "/usr/local/share/codex-data" ||
        mount.type !== "volume" ||
        Object.keys(mount).some((key) => !allowedKeys.has(key))) {
        process.exit(1);
    }
'

if ! docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
    if docker compose -p "$PROJECT_A" -f "$COMPOSE_FILE" up -d >/dev/null 2>&1; then
        echo "shared-volume test: Compose unexpectedly accepted a missing external volume." >&2
        exit 1
    fi
fi

if [ "${SKIP_HOST_INSTALL_TEST:-false}" != true ]; then
    TEMP_HOME="$(mktemp -d)"
    trap 'rm -rf "$TEMP_HOME"; cleanup' EXIT HUP INT TERM
    HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" \
        ./scripts/install-host.sh codex-volume-test "$PWD" test-user >/dev/null
    docker volume inspect "$VOLUME_NAME" >/dev/null
    docker run --rm -v "$VOLUME_NAME:/data" alpine:3.20 \
        sh -c 'printf "%s\n" preserved > "$1"' sh "/data/$HOST_MARKER_NAME"
    HOME="$TEMP_HOME" XDG_CONFIG_HOME="$TEMP_HOME/.config" \
        ./scripts/install-host.sh codex-volume-test "$PWD" test-user >/dev/null
    docker run --rm -v "$VOLUME_NAME:/data" alpine:3.20 \
        test -f "/data/$HOST_MARKER_NAME"
else
    docker volume create "$VOLUME_NAME" >/dev/null
fi

docker compose -p "$PROJECT_A" -f "$COMPOSE_FILE" up -d
docker compose -p "$PROJECT_B" -f "$COMPOSE_FILE" up -d

CONTAINER_A="$(docker compose -p "$PROJECT_A" -f "$COMPOSE_FILE" ps -q test)"
CONTAINER_B="$(docker compose -p "$PROJECT_B" -f "$COMPOSE_FILE" ps -q test)"

docker exec "$CONTAINER_A" sh -c "printf '%s\n' shared > '$MARKER'"
test "$(docker exec "$CONTAINER_B" cat "$MARKER")" = shared

for CONTAINER_ID in "$CONTAINER_A" "$CONTAINER_B"; do
    ACTUAL_VOLUME="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/usr/local/share/codex-data"}}{{.Name}}{{end}}{{end}}' "$CONTAINER_ID")"
    test "$ACTUAL_VOLUME" = "$VOLUME_NAME"
done
