#!/bin/sh
set -eu

if [ "$(id -u)" -eq 0 ]; then
    echo "install-host.sh: do not run this script with sudo; run it as your macOS user." >&2
    exit 1
fi

if [ "$#" -ne 3 ]; then
    echo "Usage: install-host.sh SSH_ALIAS WORKSPACE_PATH REMOTE_USER" >&2
    exit 2
fi

SSH_ALIAS="$1"
WORKSPACE_PATH="$2"
REMOTE_USER="$3"

case "$SSH_ALIAS" in
    *[!A-Za-z0-9._-]*|'')
        echo "install-host.sh: SSH alias may contain only letters, digits, dot, underscore, and dash." >&2
        exit 1
        ;;
esac
case "$REMOTE_USER" in
    *[!A-Za-z0-9._-]*|'')
        echo "install-host.sh: invalid remote user." >&2
        exit 1
        ;;
esac

command -v docker >/dev/null 2>&1 || {
    echo "install-host.sh: docker was not found on PATH." >&2
    exit 1
}
command -v ssh-keygen >/dev/null 2>&1 || {
    echo "install-host.sh: ssh-keygen was not found on PATH." >&2
    exit 1
}

if [ ! -d "$WORKSPACE_PATH" ]; then
    echo "install-host.sh: workspace does not exist: $WORKSPACE_PATH" >&2
    exit 1
fi
WORKSPACE_PATH="$(cd "$WORKSPACE_PATH" && pwd -P)"

if docker volume inspect codex-data >/dev/null 2>&1; then
    echo "Reusing shared Docker volume: codex-data"
elif docker volume create codex-data >/dev/null; then
    echo "Created shared Docker volume: codex-data"
else
    echo "install-host.sh: failed to create the shared Docker volume 'codex-data'. Check that the Docker daemon is running and accessible." >&2
    exit 1
fi

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/codex-devcontainer-remote"
SSH_FRAGMENT_DIR="$HOME/.ssh/config.d/codex-devcontainers"
SSH_CONFIG="$HOME/.ssh/config"
SSH_INCLUDE='Include ~/.ssh/config.d/codex-devcontainers/*.conf'
KEY_FILE="$HOME/.ssh/codex-devcontainer_ed25519"

install -d -m 0700 "$HOME/.ssh" "$SSH_FRAGMENT_DIR" "$CONFIG_DIR"
install -d -m 0755 "$BIN_DIR"
install -m 0755 "$SCRIPT_DIR/codex-devcontainer-proxy" \
    "$BIN_DIR/codex-devcontainer-proxy"

if [ ! -f "$KEY_FILE" ]; then
    ssh-keygen -q -t ed25519 -f "$KEY_FILE" -N '' \
        -C 'codex-devcontainer-remote'
fi
chmod 0600 "$KEY_FILE"
chmod 0644 "$KEY_FILE.pub"

touch "$CONFIG_DIR/projects"
chmod 0600 "$CONFIG_DIR/projects"
if ! grep -Fqx "$WORKSPACE_PATH" "$CONFIG_DIR/projects"; then
    printf '%s\n' "$WORKSPACE_PATH" >> "$CONFIG_DIR/projects"
fi

touch "$SSH_CONFIG"
chmod 0600 "$SSH_CONFIG"
if ! grep -Fqx "$SSH_INCLUDE" "$SSH_CONFIG"; then
    TEMP_CONFIG="$(mktemp)"
    trap 'rm -f "$TEMP_CONFIG"' EXIT HUP INT TERM
    {
        printf '%s\n\n' "$SSH_INCLUDE"
        cat "$SSH_CONFIG"
    } > "$TEMP_CONFIG"
    install -m 0600 "$TEMP_CONFIG" "$SSH_CONFIG"
fi

FRAGMENT="$SSH_FRAGMENT_DIR/$SSH_ALIAS.conf"
cat > "$FRAGMENT" <<EOF
Host $SSH_ALIAS
    HostName $SSH_ALIAS
    Port 22
    User $REMOTE_USER
    IdentityFile $KEY_FILE
    IdentitiesOnly yes
    PreferredAuthentications publickey
    PasswordAuthentication no
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    ProxyCommand $BIN_DIR/codex-devcontainer-proxy "$WORKSPACE_PATH" %r
EOF
chmod 0600 "$FRAGMENT"

echo "Installed SSH alias: $SSH_ALIAS"
echo "Workspace allowlisted: $WORKSPACE_PATH"
echo "Test after rebuilding the container: ssh $SSH_ALIAS"
