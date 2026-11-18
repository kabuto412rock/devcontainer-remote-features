#!/bin/bash
# Shared checks for the codex-remote Feature tests. Each test script sources
# this file and calls check_feature with the CLIs it expects to be installed.

# shellcheck disable=SC1091
source dev-container-features-test-lib

SHARE_DIR=/usr/local/share/codex-remote
SSHD_CONFIG=/etc/ssh/sshd_config.d/99-codex-remote.conf

as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo -n "$@"
    fi
}

# Writes a marker into a data directory, re-runs initialization, and checks
# that the marker survives.
data_is_preserved() {
    marker="$1/.codex-remote-test-$$"
    printf '%s\n' preserved > "$marker" &&
        as_root "$SHARE_DIR/initialize-data.sh" &&
        [ "$(cat "$marker")" = preserved ]
    status=$?
    rm -f "$marker"
    return "$status"
}

not_installed() {
    ! command -v "$1" >/dev/null 2>&1
}

check_feature() {
    expect_codex="$1"
    expect_claude="$2"

    check "installCodex recorded" test "$(cat "$SHARE_DIR/install-codex")" = "$expect_codex"
    check "installClaudeCode recorded" test "$(cat "$SHARE_DIR/install-claude-code")" = "$expect_claude"
    check "helpers installed" test -x "$SHARE_DIR/entrypoint.sh" -a -x "$SHARE_DIR/initialize-data.sh" -a -x "$SHARE_DIR/start-sshd.sh"
    check "authorize helper installed" test -x /usr/local/sbin/codex-remote-authorize
    check "remote user recorded" test -s "$SHARE_DIR/remote-user"
    check "CODEX_HOME" test "$CODEX_HOME" = /usr/local/share/codex-data
    check "CLAUDE_CONFIG_DIR" test "$CLAUDE_CONFIG_DIR" = /usr/local/share/claude-data

    # Feature tests run with the image entrypoint overridden, so run it explicitly.
    check "entrypoint" "$SHARE_DIR/entrypoint.sh" true
    check "sshd installed" command -v sshd
    check "sshd listening" nc -z 127.0.0.1 22

    if [ "$expect_codex" = true ]; then
        check "codex version" codex --version
        check "CODEX_HOME writable" test -w "$CODEX_HOME"
        check "Codex data preserved" data_is_preserved "$CODEX_HOME"
        check "SSH gets CODEX_HOME" grep -q "CODEX_HOME=/usr/local/share/codex-data" "$SSHD_CONFIG"
    else
        check "codex not installed" not_installed codex
    fi

    if [ "$expect_claude" = true ]; then
        check "claude version" bash -c 'claude --version | grep -q "Claude Code"'
        check "CLAUDE_CONFIG_DIR writable" test -w "$CLAUDE_CONFIG_DIR"
        check "Claude data preserved" data_is_preserved "$CLAUDE_CONFIG_DIR"
        check "SSH gets CLAUDE_CONFIG_DIR" grep -q "CLAUDE_CONFIG_DIR=/usr/local/share/claude-data" "$SSHD_CONFIG"
    else
        check "claude not installed" not_installed claude
    fi
}
