#!/bin/sh
set -eu

SHARE_DIR="/usr/local/share/codex-remote"

if [ "$(id -u)" -ne 0 ]; then
    echo "codex-remote: data initialization helper must run as root." >&2
    exit 1
fi

REMOTE_USER_NAME="$(cat "$SHARE_DIR/remote-user")"
REMOTE_USER_GROUP="$(id -gn "$REMOTE_USER_NAME")"

REMOTE_USER_UID="$(id -u "$REMOTE_USER_NAME")"
BUILD_UID="$(cat "$SHARE_DIR/build-uid" 2>/dev/null || echo "$REMOTE_USER_UID")"

# The data directory is either a Docker volume or a bind-mounted host folder.
# Take ownership only when it is not writable and is owned by root or by the
# build-time UID: a volume created by Docker, an older Feature version, or from
# the image after the Dev Container CLI changed the user's UID. Anything else
# may be host-owned and is never rewritten.
prepare_data_dir() {
    DIR="$1"
    NAME="$2"
    install -d -m 0755 "$DIR"
    OWNER_UID="$(stat -c %u "$DIR")"
    if [ "$REMOTE_USER_NAME" != root ] && \
        ! runuser -u "$REMOTE_USER_NAME" -- test -w "$DIR" && \
        { [ "$OWNER_UID" = 0 ] || [ "$OWNER_UID" = "$BUILD_UID" ]; }; then
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
