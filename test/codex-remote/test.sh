#!/bin/sh
set -eu

SHARE_DIR=/usr/local/share/codex-remote
INSTALL_CODEX="$(cat "$SHARE_DIR/install-codex")"
INSTALL_CLAUDE_CODE="$(cat "$SHARE_DIR/install-claude-code")"
EXPECT_CODEX="${EXPECT_CODEX:-true}"
EXPECT_CLAUDE_CODE="${EXPECT_CLAUDE_CODE:-false}"

test "$INSTALL_CODEX" = "$EXPECT_CODEX"
test "$INSTALL_CLAUDE_CODE" = "$EXPECT_CLAUDE_CODE"
test -x "$SHARE_DIR/entrypoint.sh"
test -x "$SHARE_DIR/initialize-data.sh"
test -x "$SHARE_DIR/start-sshd.sh"
test -x /usr/local/sbin/codex-remote-authorize
test -s "$SHARE_DIR/remote-user"
test "$CODEX_HOME" = /usr/local/share/codex-data
test "$CLAUDE_CONFIG_DIR" = /usr/local/share/claude-data

# Feature tests run with the image entrypoint overridden, so run it explicitly.
"$SHARE_DIR/entrypoint.sh" true

command -v sshd
command -v nc
nc -z 127.0.0.1 22

# A second initialization must preserve data in the mounted directories.
run_init() {
    if [ "$(id -u)" -eq 0 ]; then
        "$SHARE_DIR/initialize-data.sh"
    else
        sudo -n "$SHARE_DIR/initialize-data.sh"
    fi
}

MARKERS=""
trap 'rm -f $MARKERS' EXIT HUP INT TERM

if [ "$INSTALL_CODEX" = true ]; then
    command -v codex
    codex --version
    test -w "$CODEX_HOME"
    MARKER="$CODEX_HOME/.codex-remote-test-$$"
    MARKERS="$MARKERS $MARKER"
    printf '%s\n' preserved > "$MARKER"
else
    ! command -v codex
fi

if [ "$INSTALL_CLAUDE_CODE" = true ]; then
    command -v claude
    claude --version
    test -w "$CLAUDE_CONFIG_DIR"
    MARKER="$CLAUDE_CONFIG_DIR/.codex-remote-test-$$"
    MARKERS="$MARKERS $MARKER"
    printf '%s\n' preserved > "$MARKER"
else
    ! command -v claude
fi

run_init
for MARKER in $MARKERS; do
    test "$(cat "$MARKER")" = preserved
done

# SSH sessions receive the data directories through sshd SetEnv.
SSHD_CONFIG=/etc/ssh/sshd_config.d/99-codex-remote.conf
if [ "$INSTALL_CODEX" = true ]; then
    grep -q "CODEX_HOME=/usr/local/share/codex-data" "$SSHD_CONFIG"
fi
if [ "$INSTALL_CLAUDE_CODE" = true ]; then
    grep -q "CLAUDE_CONFIG_DIR=/usr/local/share/claude-data" "$SSHD_CONFIG"
fi
