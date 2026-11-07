# Local Dev Container smoke test

From the repository root in Windows PowerShell, with Docker Desktop and the
Dev Container CLI installed:

```powershell
.\test\local-devcontainer\run.ps1 -Rebuild
```

The script copies `src/codex-remote` into `.devcontainer/codex-remote` (ignored
by Git), runs `devcontainer up`, installs the `codex-remote-local-test` SSH
alias, and prints `codex --version` over SSH. Omit
`-Rebuild` to reuse a running container.

Edit `.devcontainer/devcontainer.json` to try other options or host-folder
mounts.
