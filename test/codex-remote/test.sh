#!/bin/sh
set -eu

test -x /usr/local/share/codex-remote/entrypoint.sh
test -x /usr/local/share/codex-remote/initialize-codex.sh
test -x /usr/local/share/codex-remote/start-sshd.sh
test -x /usr/local/sbin/codex-remote-authorize
test -s /usr/local/share/codex-remote/remote-user
test "$CODEX_HOME" = /usr/local/share/codex-data
test "$CODEX_INSTALL_DIR" = /usr/local/share/codex-data/bin

# Feature tests run with the image entrypoint overridden, so initialize the
# runtime volume explicitly before checking the lazily installed CLI.
/usr/local/share/codex-remote/entrypoint.sh true

command -v sshd
command -v ssh-keygen
command -v nc
command -v codex
test -x "$CODEX_INSTALL_DIR/codex"

# A second initialization must reuse the executable and preserve shared state.
CODEX_INODE="$(stat -c %i "$CODEX_INSTALL_DIR/codex")"
CODEX_MARKER="$CODEX_HOME/.codex-remote-test-$$"
trap 'rm -f "$CODEX_MARKER"' EXIT HUP INT TERM
printf '%s\n' preserved > "$CODEX_MARKER"
if [ "$(id -u)" -eq 0 ]; then
    /usr/local/share/codex-remote/initialize-codex.sh
else
    sudo -n /usr/local/share/codex-remote/initialize-codex.sh
fi
test "$(stat -c %i "$CODEX_INSTALL_DIR/codex")" = "$CODEX_INODE"
test "$(cat "$CODEX_MARKER")" = preserved
nc -z 127.0.0.1 22
codex --version
