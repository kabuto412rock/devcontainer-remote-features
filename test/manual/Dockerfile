ARG BASE_IMAGE=debian:bookworm
FROM ${BASE_IMAGE}

ARG REMOTE_USER=vscode
ARG INSTALL_CODEX=true

RUN if [ "$REMOTE_USER" != root ] && ! id "$REMOTE_USER" >/dev/null 2>&1; then \
        useradd --create-home --shell /bin/bash "$REMOTE_USER"; \
        passwd -d "$REMOTE_USER"; \
    fi

COPY src/codex-remote /tmp/codex-remote-feature

RUN cd /tmp/codex-remote-feature \
    && _REMOTE_USER="$REMOTE_USER" \
       _REMOTE_USER_HOME="$(getent passwd "$REMOTE_USER" | cut -d: -f6)" \
       INSTALLCODEX="$INSTALL_CODEX" \
       sh ./install.sh \
    && rm -rf /tmp/codex-remote-feature

ENV CODEX_HOME=/usr/local/share/codex-data
ENV CODEX_INSTALL_DIR=/usr/local/share/codex-data/bin
VOLUME ["/usr/local/share/codex-data"]

USER ${REMOTE_USER}
ENTRYPOINT ["/usr/local/share/codex-remote/entrypoint.sh"]
CMD ["sleep", "infinity"]
