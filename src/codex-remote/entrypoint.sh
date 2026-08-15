#!/bin/sh
set -eu

if [ "$(id -u)" -eq 0 ]; then
    /usr/local/share/codex-remote/initialize-codex.sh
    /usr/local/share/codex-remote/start-sshd.sh
else
    sudo -n /usr/local/share/codex-remote/initialize-codex.sh
    sudo -n /usr/local/share/codex-remote/start-sshd.sh
fi

if [ "$#" -gt 0 ]; then
    exec "$@"
fi
