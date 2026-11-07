#!/bin/sh
set -eu

SHARE_DIR="/usr/local/share/codex-remote"

if [ "$(id -u)" -ne 0 ]; then
    echo "codex-remote: data initialization helper must run as root." >&2
    exit 1
fi

REMOTE_USER_NAME="$(cat "$SHARE_DIR/remote-user")"
REMOTE_USER_GROUP="$(id -gn "$REMOTE_USER_NAME")"

# The data directory is either a Docker volume or a bind-mounted host folder.
# Only take ownership of a root-owned directory (a volume created by an older
# Feature version or by Docker itself); never rewrite host-owned files.
prepare_data_dir() {
    DIR="$1"
    NAME="$2"
    install -d -m 0755 "$DIR"
    if [ "$REMOTE_USER_NAME" != root ] && [ "$(stat -c %u "$DIR")" = 0 ]; then
        chown "$REMOTE_USER_NAME:$REMOTE_USER_GROUP" "$DIR"
    fi
    if ! runuser -u "$REMOTE_USER_NAME" -- test -w "$DIR"; then
        echo "codex-remote: warning: $NAME data directory $DIR (owner UID $(stat -c %u "$DIR")) is not writable by '$REMOTE_USER_NAME' (UID $(id -u "$REMOTE_USER_NAME"))." >&2
    fi
}

if [ "$(cat "$SHARE_DIR/install-codex")" = true ]; then
    prepare_data_dir /usr/local/share/codex-data Codex
fi
if [ "$(cat "$SHARE_DIR/install-claude-code" 2>/dev/null || echo false)" = true ]; then
    prepare_data_dir /usr/local/share/claude-data "Claude Code"
fi
