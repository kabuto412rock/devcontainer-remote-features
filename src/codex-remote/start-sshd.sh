#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "codex-remote: SSH startup helper must run as root." >&2
    exit 1
fi

install -d -m 0755 /run/sshd
HOST_KEY="/etc/ssh/ssh_host_ed25519_key"
if [ ! -s "$HOST_KEY" ]; then
    rm -f "$HOST_KEY" "$HOST_KEY.pub"
    ssh-keygen -q -t ed25519 -N '' -f "$HOST_KEY"
fi
/usr/sbin/sshd -t -h "$HOST_KEY"
/usr/sbin/sshd -h "$HOST_KEY"
