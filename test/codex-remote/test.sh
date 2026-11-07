#!/bin/sh
set -eu

SHARE_DIR=/usr/local/share/codex-remote

test "$(cat "$SHARE_DIR/install-codex")" = true
test -x "$SHARE_DIR/entrypoint.sh"
test -x "$SHARE_DIR/initialize-data.sh"
test -x "$SHARE_DIR/start-sshd.sh"
test -x /usr/local/sbin/codex-remote-authorize
test -s "$SHARE_DIR/remote-user"
test "$CODEX_HOME" = /usr/local/share/codex-data

# Feature tests run with the image entrypoint overridden, so run it explicitly.
"$SHARE_DIR/entrypoint.sh" true

command -v sshd
command -v nc
nc -z 127.0.0.1 22

command -v codex
codex --version
test -w "$CODEX_HOME"

# A second initialization must preserve data in the mounted directory.
MARKER="$CODEX_HOME/.codex-remote-test-$$"
trap 'rm -f "$MARKER"' EXIT HUP INT TERM
printf '%s\n' preserved > "$MARKER"
if [ "$(id -u)" -eq 0 ]; then
    "$SHARE_DIR/initialize-data.sh"
else
    sudo -n "$SHARE_DIR/initialize-data.sh"
fi
test "$(cat "$MARKER")" = preserved

# SSH sessions receive the data directory through sshd SetEnv.
grep -q "SetEnv CODEX_HOME=/usr/local/share/codex-data" \
    /etc/ssh/sshd_config.d/99-codex-remote.conf
