# Dev Container Remote Features

## Codex Remote SSH (`codex-remote`)

A Dev Container Feature for Debian/Ubuntu images that:

- installs **Codex CLI** using OpenAI's official installer;
- keeps Codex's login and settings in a Docker volume, or in a host folder you choose;
- runs a key-only SSH server inside the container, with no published port, so
  ChatGPT Desktop or any SSH client can connect.

To use Claude Code in the same container, add Anthropic's official Feature
`ghcr.io/anthropics/devcontainer-features/claude-code:1` alongside this one.

### Quick start

**1. Add the Feature** to `devcontainer.json`, or for every project to
`dev.containers.defaultFeatures` in your VS Code **User** settings:

```jsonc
"features": {
  "ghcr.io/kabuto412rock/devcontainer-remote-features/codex-remote:0": {}
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
codex --version
```

Add the same alias in ChatGPT Desktop under **Settings → Connections → SSH**.

### Options

| Option | Default | Description |
| --- | --- | --- |
| `installCodex` | `true` | Install Codex CLI (`https://chatgpt.com/codex/install.sh`) |

Codex is installed into the image when it is built, so a new version arrives
when you rebuild the container.

### Where login and settings are stored

Codex uses `/usr/local/share/codex-data` (`CODEX_HOME`) inside the container.

**Docker volume (default).** The Feature mounts the `codex-data` volume. Every
image-based Dev Container on the same Docker daemon shares it, so you log in
once. You don't need to create it in advance.

**Host folder.** To use a host folder instead, add a mount with the same
`target` to the project's `devcontainer.json`. It replaces the Feature's volume.
The folder must already exist:

```jsonc
"mounts": [
  // Windows: ${localEnv:USERPROFILE}   macOS/Linux: ${localEnv:HOME}
  { "type": "bind", "source": "${localEnv:USERPROFILE}/.codex", "target": "/usr/local/share/codex-data" }
]
```

A host `~/.codex` also shares its login with Codex on the host. The Feature
never changes ownership of files in a host folder.

**Docker Compose** scopes volume names per project. To share the global volume,
declare it as external in `docker-compose.yml`. `install-host` creates it:

```yaml
volumes:
  codex-data:
    name: codex-data
    external: true
```

The volume holds credentials and history. Mount it only in containers you
trust.

### Troubleshooting

- **`Could not resolve hostname`**: run `ssh -G ALIAS` and check that
  `proxycommand` points at `codex-devcontainer-proxy`. On Windows, use Windows
  OpenSSH (`C:\Windows\System32\OpenSSH\ssh.exe`), not Git for Windows' `ssh`.
- **`Expected one running container ... found 0`**: start the Dev Container.
  The path given to `install-host` must match the folder VS Code opened, which
  is the container's `devcontainer.local_folder` label.
- **`data directory ... is not writable`**: the volume was created by a
  container whose user has a different UID, such as a WSL2 project versus a
  Windows project. Use a separate volume name in a mount override for one of
  them, or use a host folder.
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
- CI runs the Feature tests in `test/codex-remote/`.
- Release: run the **Release dev container features** workflow. It publishes
  `ghcr.io/kabuto412rock/devcontainer-remote-features/codex-remote:0`.
