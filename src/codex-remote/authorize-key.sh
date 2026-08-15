#!/bin/sh
set -eu

EXPECTED_USER="$(cat /usr/local/share/codex-remote/remote-user)"
REQUESTED_USER="${1:-}"
PUBLIC_KEY="${2:-}"

if [ -z "$REQUESTED_USER" ] || [ "$REQUESTED_USER" != "$EXPECTED_USER" ]; then
    echo "codex-remote: requested SSH user does not match the Dev Container remote user." >&2
    exit 1
fi

case "$PUBLIC_KEY" in
    ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-nistp256\ *|ecdsa-sha2-nistp384\ *|ecdsa-sha2-nistp521\ *) ;;
    *)
        echo "codex-remote: unsupported or malformed SSH public key." >&2
        exit 1
        ;;
esac

USER_HOME="$(getent passwd "$EXPECTED_USER" | cut -d: -f6)"
USER_GROUP="$(id -gn "$EXPECTED_USER")"
if [ -z "$USER_HOME" ] || [ ! -d "$USER_HOME" ]; then
    echo "codex-remote: remote user home directory was not found." >&2
    exit 1
fi

install -d -m 0700 -o "$EXPECTED_USER" -g "$USER_GROUP" "$USER_HOME/.ssh"
KEY_FILE="$USER_HOME/.ssh/authorized_keys"
touch "$KEY_FILE"
chown "$EXPECTED_USER:$USER_GROUP" "$KEY_FILE"
chmod 0600 "$KEY_FILE"

if ! grep -Fqx "$PUBLIC_KEY" "$KEY_FILE"; then
    printf '%s\n' "$PUBLIC_KEY" >> "$KEY_FILE"
fi

