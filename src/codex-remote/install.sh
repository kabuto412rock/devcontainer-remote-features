#!/bin/sh
set -eu

INSTALL_CODEX="${INSTALLCODEX:-true}"
INSTALL_CLAUDE_CODE="${INSTALLCLAUDECODE:-false}"

CODEX_INSTALLER_URL="https://chatgpt.com/codex/install.sh"
CLAUDE_INSTALLER_URL="https://claude.ai/install.sh"
CODEX_DATA_DIR="/usr/local/share/codex-data"
CLAUDE_DATA_DIR="/usr/local/share/claude-data"
CODEX_INSTALL_DIR_VALUE="/opt/codex-remote/codex"
SHARE_DIR="/usr/local/share/codex-remote"

if [ "$(id -u)" -ne 0 ]; then
    echo "codex-remote: Feature installation must run as root." >&2
    exit 1
fi

case "$INSTALL_CODEX:$INSTALL_CLAUDE_CODE" in
    true:true|true:false|false:true|false:false) ;;
    *)
        echo "codex-remote: installCodex and installClaudeCode must be true or false." >&2
        exit 1
        ;;
esac

if [ ! -r /etc/os-release ]; then
    echo "codex-remote: /etc/os-release is missing; only Debian/Ubuntu images are supported." >&2
    exit 1
fi

. /etc/os-release
case "${ID:-}:${ID_LIKE:-}" in
    debian:*|ubuntu:*|*:debian*|*:ubuntu*) ;;
    *)
        echo "codex-remote: unsupported distribution '${ID:-unknown}'. Debian/Ubuntu is required." >&2
        exit 1
        ;;
esac

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    netcat-openbsd \
    openssh-server \
    sudo \
    util-linux
rm -rf /var/lib/apt/lists/*

REMOTE_USER_NAME="${_REMOTE_USER:-${USERNAME:-root}}"
if ! id "$REMOTE_USER_NAME" >/dev/null 2>&1; then
    echo "codex-remote: remote user '$REMOTE_USER_NAME' does not exist." >&2
    exit 1
fi

REMOTE_USER_HOME="${_REMOTE_USER_HOME:-}"
if [ -z "$REMOTE_USER_HOME" ]; then
    REMOTE_USER_HOME="$(getent passwd "$REMOTE_USER_NAME" | cut -d: -f6)"
fi
if [ -z "$REMOTE_USER_HOME" ] || [ ! -d "$REMOTE_USER_HOME" ]; then
    echo "codex-remote: home directory for '$REMOTE_USER_NAME' was not found." >&2
    exit 1
fi
REMOTE_USER_GROUP="$(id -gn "$REMOTE_USER_NAME")"

# Runs a command as the Dev Container user with a predictable environment.
as_remote_user() {
    if [ "$REMOTE_USER_NAME" = root ]; then
        env HOME="$REMOTE_USER_HOME" "$@"
    else
        runuser -u "$REMOTE_USER_NAME" -- env HOME="$REMOTE_USER_HOME" "$@"
    fi
}

download_installer() {
    TARGET="$1"
    URL="$2"
    if ! curl --proto '=https' --tlsv1.2 -fsSL "$URL" -o "$TARGET"; then
        echo "codex-remote: failed to download $URL." >&2
        exit 1
    fi
    chmod 0755 "$TARGET"
}

install -d -m 0755 "$SHARE_DIR" /run/sshd
printf '%s\n' "$REMOTE_USER_NAME" > "$SHARE_DIR/remote-user"
printf '%s\n' "$INSTALL_CODEX" > "$SHARE_DIR/install-codex"
printf '%s\n' "$INSTALL_CLAUDE_CODE" > "$SHARE_DIR/install-claude-code"
rm -f "$SHARE_DIR/initialize-codex.sh"

install -m 0755 entrypoint.sh "$SHARE_DIR/entrypoint.sh"
install -m 0755 initialize-data.sh "$SHARE_DIR/initialize-data.sh"
install -m 0755 start-sshd.sh "$SHARE_DIR/start-sshd.sh"
install -m 0755 authorize-key.sh /usr/local/sbin/codex-remote-authorize

# A new named volume copies ownership from the image directory, so a fresh
# volume is writable by the remote user without a runtime chown.
install -d -m 0755 -o "$REMOTE_USER_NAME" -g "$REMOTE_USER_GROUP" \
    "$CODEX_DATA_DIR" "$CLAUDE_DATA_DIR"

WORK_DIR="$(mktemp -d)"
chmod 0755 "$WORK_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM

SSH_ENV=""
if [ "$INSTALL_CODEX" = true ]; then
    install -d -m 0755 -o "$REMOTE_USER_NAME" -g "$REMOTE_USER_GROUP" \
        "$CODEX_INSTALL_DIR_VALUE"
    # The installer keeps the real binary under CODEX_HOME/packages, so give it
    # a permanent home in the image, separate from the mounted data directory.
    TEMP_CODEX_HOME="/opt/codex-remote/codex-home"
    install -d -m 0755 -o "$REMOTE_USER_NAME" -g "$REMOTE_USER_GROUP" "$TEMP_CODEX_HOME"
    download_installer "$WORK_DIR/codex-install.sh" "$CODEX_INSTALLER_URL"
    if ! as_remote_user \
        CODEX_HOME="$TEMP_CODEX_HOME" \
        CODEX_INSTALL_DIR="$CODEX_INSTALL_DIR_VALUE" \
        CODEX_NON_INTERACTIVE=1 \
        sh "$WORK_DIR/codex-install.sh" </dev/null; then
        echo "codex-remote: the official Codex installer failed." >&2
        exit 1
    fi
    if [ ! -x "$CODEX_INSTALL_DIR_VALUE/codex" ]; then
        echo "codex-remote: the official installer did not create $CODEX_INSTALL_DIR_VALUE/codex." >&2
        exit 1
    fi
    ln -sfn "$CODEX_INSTALL_DIR_VALUE/codex" /usr/local/bin/codex
    SSH_ENV="$SSH_ENV CODEX_HOME=$CODEX_DATA_DIR"
else
    rm -f /usr/local/bin/codex
fi

if [ "$INSTALL_CLAUDE_CODE" = true ]; then
    TEMP_CLAUDE_CONFIG="$WORK_DIR/claude-config"
    install -d -m 0700 -o "$REMOTE_USER_NAME" -g "$REMOTE_USER_GROUP" "$TEMP_CLAUDE_CONFIG"
    download_installer "$WORK_DIR/claude-install.sh" "$CLAUDE_INSTALLER_URL"
    if ! as_remote_user \
        CLAUDE_CONFIG_DIR="$TEMP_CLAUDE_CONFIG" \
        bash "$WORK_DIR/claude-install.sh" </dev/null; then
        echo "codex-remote: the official Claude Code installer failed." >&2
        exit 1
    fi
    CLAUDE_BIN="$REMOTE_USER_HOME/.local/bin/claude"
    if [ ! -x "$CLAUDE_BIN" ]; then
        echo "codex-remote: the official installer did not create $CLAUDE_BIN." >&2
        exit 1
    fi
    # Claude Code updates itself under the user's home; the symlink follows.
    ln -sfn "$CLAUDE_BIN" /usr/local/bin/claude
    SSH_ENV="$SSH_ENV CLAUDE_CONFIG_DIR=$CLAUDE_DATA_DIR"
else
    rm -f /usr/local/bin/claude
fi

if [ "$REMOTE_USER_NAME" != "root" ]; then
    cat > /etc/sudoers.d/codex-remote <<EOF
$REMOTE_USER_NAME ALL=(root) NOPASSWD: $SHARE_DIR/initialize-data.sh, $SHARE_DIR/start-sshd.sh
EOF
    chmod 0440 /etc/sudoers.d/codex-remote
    visudo -cf /etc/sudoers.d/codex-remote >/dev/null
fi

install -d -m 0755 /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-codex-remote.conf <<EOF
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin prohibit-password
PubkeyAuthentication yes
AllowTcpForwarding no
X11Forwarding no
PermitTunnel no
GatewayPorts no
EOF
# SSH sessions do not inherit the container environment, so pass the data
# directories explicitly to remote clients.
if [ -n "$SSH_ENV" ]; then
    printf 'SetEnv%s\n' "$SSH_ENV" >> /etc/ssh/sshd_config.d/99-codex-remote.conf
fi

{
    echo '# Generated by the codex-remote Dev Container Feature.'
    [ "$INSTALL_CODEX" = true ] && echo "export CODEX_HOME=$CODEX_DATA_DIR"
    [ "$INSTALL_CLAUDE_CODE" = true ] && echo "export CLAUDE_CONFIG_DIR=$CLAUDE_DATA_DIR"
    true
} > /etc/profile.d/codex-remote.sh
chmod 0644 /etc/profile.d/codex-remote.sh

# A container rebuild receives a fresh host key instead of reusing an image key.
rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub

echo "codex-remote: installed for remote user '$REMOTE_USER_NAME' (Codex: $INSTALL_CODEX, Claude Code: $INSTALL_CLAUDE_CODE)."
