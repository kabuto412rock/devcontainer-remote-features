#!/bin/sh
set -eu

INSTALL_CODEX="${INSTALLCODEX:-true}"

if [ "$(id -u)" -ne 0 ]; then
    echo "codex-remote: Feature installation must run as root." >&2
    exit 1
fi

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

install -d -m 0755 /usr/local/share/codex-remote /run/sshd
printf '%s\n' "$REMOTE_USER_NAME" > /usr/local/share/codex-remote/remote-user

install -m 0755 entrypoint.sh /usr/local/share/codex-remote/entrypoint.sh
install -m 0755 initialize-codex.sh /usr/local/share/codex-remote/initialize-codex.sh
install -m 0755 start-sshd.sh /usr/local/share/codex-remote/start-sshd.sh
install -m 0755 authorize-key.sh /usr/local/sbin/codex-remote-authorize
printf '%s\n' "$INSTALL_CODEX" > /usr/local/share/codex-remote/install-codex

if [ "$REMOTE_USER_NAME" != "root" ]; then
    cat > /etc/sudoers.d/codex-remote <<EOF
$REMOTE_USER_NAME ALL=(root) NOPASSWD: /usr/local/share/codex-remote/initialize-codex.sh, /usr/local/share/codex-remote/start-sshd.sh
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

# A container rebuild receives a fresh host key instead of reusing an image key.
rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub

# The named volume is mounted only when the container starts. The entrypoint
# installs Codex into it on first use; this symlink remains valid across rebuilds.
ln -sfn /usr/local/share/codex-data/bin/codex /usr/local/bin/codex

echo "codex-remote: installed for remote user '$REMOTE_USER_NAME'."
