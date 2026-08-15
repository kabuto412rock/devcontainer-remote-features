#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "codex-remote: SSH startup helper must run as root." >&2
    exit 1
fi

install -d -m 0755 /run/sshd

# The Feature entrypoint can be invoked more than once while Dev Container
# Features are being tested. Serialize startup so concurrent invocations do not
# both try to create the host key or launch sshd.
LOCK_FILE="/run/codex-remote-sshd.lock"
exec 9>"$LOCK_FILE"
flock 9

if nc -z 127.0.0.1 22 >/dev/null 2>&1; then
    exit 0
fi

HOST_KEY="/etc/ssh/ssh_host_ed25519_key"
if [ ! -s "$HOST_KEY" ]; then
    rm -f "$HOST_KEY" "$HOST_KEY.pub"
    ssh-keygen -q -t ed25519 -N '' -f "$HOST_KEY"
fi
/usr/sbin/sshd -t -h "$HOST_KEY"
/usr/sbin/sshd -h "$HOST_KEY"
