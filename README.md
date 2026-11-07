# Dev Container Remote Features

## Codex / Claude Code Remote SSH (`codex-remote`)

A Dev Container Feature for Debian/Ubuntu images that:

- installs **Codex CLI**, **Claude Code**, or both, using the official installers;
- keeps their login and settings in a Docker volume or a host folder you choose;
- runs a key-only SSH server inside the container, with no published port, so
  ChatGPT Desktop, Claude Desktop, or any SSH client can connect.

### Quick start

**1. Add the Feature** to `devcontainer.json`, or for every project to
`dev.containers.defaultFeatures` in your VS Code **User** settings:

```jsonc
"features": {
  "ghcr.io/kabuto412rock/devcontainer-remote-features/codex-remote:0": {
    "installCodex": true,
    "installClaudeCode": true
  }
}
```

**2. Install the SSH alias** once per project, from the project folder:

```powershell
# Windows PowerShell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\path\to\this-repo\scripts\install-host.ps1
```

```sh
# macOS / Linux
/path/to/this-repo/scripts/install-host.sh
```

By default the alias is `<folder name>-devcontainer` and the SSH user is
`vscode`. You can pass `[SshAlias] [WorkspacePath] [RemoteUser]` to change them.
For a WSL2 project, run the Windows script from the project's
`\\wsl.localhost\...` path.

**3. Rebuild and connect.** Rebuild the Dev Container, then run:

```sh
ssh my-project-devcontainer
```

Add the same alias in your desktop app's SSH connection settings.

### Options

| Option | Default | Description |
| --- | --- | --- |
| `installCodex` | `true` | Install Codex CLI (`https://chatgpt.com/codex/install.sh`) |
| `installClaudeCode` | `false` | Install Claude Code (`https://claude.ai/install.sh`) |

The CLIs are installed into the image when it is built, so updates arrive when
you rebuild the container. Claude Code can also update itself until then.

### Where login and settings are stored

| Tool | Container path | Environment variable | Default Docker volume |
| --- | --- | --- | --- |
| Codex | `/usr/local/share/codex-data` | `CODEX_HOME` | `codex-data` |
| Claude Code | `/usr/local/share/claude-data` | `CLAUDE_CONFIG_DIR` | `claude-data` |

**Docker volume (default).** Every image-based Dev Container on the same Docker
daemon shares these volumes, so you log in once.

**Host folder.** To use a host folder instead, add a mount with the same
`target` to the project's `devcontainer.json`. It replaces the Feature's volume.
The folder must already exist:

```jsonc
"mounts": [
  // Windows: ${localEnv:USERPROFILE}   macOS/Linux: ${localEnv:HOME}
  { "type": "bind", "source": "${localEnv:USERPROFILE}/.codex",  "target": "/usr/local/share/codex-data" },
  { "type": "bind", "source": "${localEnv:USERPROFILE}/.claude", "target": "/usr/local/share/claude-data" }
]
```

You can set this per tool, so one tool can use a volume and the other a host
folder. Notes:

- Host folders shared with your local CLIs also share their login. Claude Code
  keeps its macOS login in the Keychain, so log in once inside the container.
- The Feature never changes ownership of files in a host folder.

**Docker Compose** scopes volume names per project. To share the global volumes,
declare them as external in `docker-compose.yml`. `install-host` creates them:

```yaml
volumes:
  codex-data:
    name: codex-data
    external: true
  claude-data:
    name: claude-data
    external: true
```

These volumes hold credentials and history. Mount them only in containers you
trust.

### Troubleshooting

- **`Could not resolve hostname`**: run `ssh -G ALIAS` and check that
  `proxycommand` points at `codex-devcontainer-proxy`. On Windows, use Windows
  OpenSSH (`C:\Windows\System32\OpenSSH\ssh.exe`), not Git for Windows' `ssh`.
- **`Expected one running container ... found 0`**: start the Dev Container.
  The path given to `install-host` must match the folder VS Code opened, which
  is the container's `devcontainer.local_folder` label.
- **Upgrading from 0.1**: an existing `codex-data` volume is reused as-is. Its
  `bin/` folder is no longer used, so you can delete it.

### How it works and the trust model

`install-host` creates a dedicated SSH key, allowlists the workspace path, and
writes an SSH config fragment under `~/.ssh/config.d/codex-devcontainers/`. On
each connection, the local proxy finds the running container whose
`devcontainer.local_folder` label matches, authorizes the key, and tunnels SSH
through `docker exec`. Password and root login are disabled. Host-key checking
is off for these aliases because every rebuild creates a new host key. The
trust instead rests on the local Docker daemon, the allowlist, and the
dedicated key. Docker access is effectively administrator access on the host,
so keep these files writable only by your account.

## Development

- Local end-to-end test on Windows: `.\test\local-devcontainer\run.ps1 -Rebuild`
- CI runs the Feature tests and scenarios in `test/codex-remote/`.
- Release: run the **Release dev container features** workflow. It publishes
  `ghcr.io/kabuto412rock/devcontainer-remote-features/codex-remote:0`.
