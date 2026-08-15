#!/bin/sh
set -eu

CODEX_HOME_DIR="/usr/local/share/codex-data"
CODEX_INSTALL_DIR_VALUE="$CODEX_HOME_DIR/bin"
CODEX_BIN="$CODEX_INSTALL_DIR_VALUE/codex"
CODEX_INSTALLER_URL="https://chatgpt.com/codex/install.sh"

if [ "$(id -u)" -ne 0 ]; then
    echo "codex-remote: Codex initialization helper must run as root." >&2
    exit 1
fi

INSTALL_CODEX="$(cat /usr/local/share/codex-remote/install-codex)"
if [ "$INSTALL_CODEX" != "true" ]; then
    exit 0
fi

REMOTE_USER_NAME="$(cat /usr/local/share/codex-remote/remote-user)"
REMOTE_USER_HOME="$(getent passwd "$REMOTE_USER_NAME" | cut -d: -f6)"
REMOTE_USER_GROUP="$(id -gn "$REMOTE_USER_NAME")"
if [ -z "$REMOTE_USER_HOME" ] || [ ! -d "$REMOTE_USER_HOME" ]; then
    echo "codex-remote: home directory for '$REMOTE_USER_NAME' was not found." >&2
    exit 1
fi

install -d -m 0755 "$CODEX_HOME_DIR" "$CODEX_INSTALL_DIR_VALUE"
chown "$REMOTE_USER_NAME:$REMOTE_USER_GROUP" "$CODEX_HOME_DIR" "$CODEX_INSTALL_DIR_VALUE"

if [ -x "$CODEX_BIN" ]; then
    exit 0
fi

LOCK_FILE="$CODEX_HOME_DIR/.install.lock"
exec 9>"$LOCK_FILE"
flock 9

# Another container may have completed the installation while this one waited.
if [ -x "$CODEX_BIN" ]; then
    exit 0
fi

INSTALLER="$(mktemp)"
trap 'rm -f "$INSTALLER"' EXIT HUP INT TERM
if ! curl --proto '=https' --tlsv1.2 -fsSL "$CODEX_INSTALLER_URL" -o "$INSTALLER"; then
    echo "codex-remote: failed to download the official Codex installer." >&2
    exit 1
fi
chmod 0755 "$INSTALLER"

if [ "$REMOTE_USER_NAME" = "root" ]; then
    if ! env \
        HOME="$REMOTE_USER_HOME" \
        CODEX_HOME="$CODEX_HOME_DIR" \
        CODEX_INSTALL_DIR="$CODEX_INSTALL_DIR_VALUE" \
        CODEX_NON_INTERACTIVE=1 \
        sh "$INSTALLER" </dev/null; then
        echo "codex-remote: the official Codex installer failed." >&2
        exit 1
    fi
else
    if ! runuser -u "$REMOTE_USER_NAME" -- \
        env \
        HOME="$REMOTE_USER_HOME" \
        CODEX_HOME="$CODEX_HOME_DIR" \
        CODEX_INSTALL_DIR="$CODEX_INSTALL_DIR_VALUE" \
        CODEX_NON_INTERACTIVE=1 \
        sh "$INSTALLER" </dev/null; then
        echo "codex-remote: the official Codex installer failed." >&2
        exit 1
    fi
fi

if [ ! -x "$CODEX_BIN" ]; then
    echo "codex-remote: the official installer did not create $CODEX_BIN." >&2
    exit 1
fi
