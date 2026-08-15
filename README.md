# Dev Container Remote Features

Dev Container Features for remote development workflows.

## Codex Remote SSH

`codex-remote` prepares a Debian/Ubuntu based Dev Container for ChatGPT
Desktop's SSH remote connection:

- installs OpenSSH from the distribution package repository;
- installs Codex CLI on first container start using OpenAI's official installer;
- persists the Codex CLI, authentication, configuration, and state in a Docker
  volume, with an opt-in shared volume for Docker Compose projects;
- starts an SSH server inside the container without publishing a host port;
- accepts a dedicated local public key only when the host proxy connects;
- does not run `codex login` during the image build.

The SSH connection is transported through `docker exec`, so projects do not
need to modify `docker-compose.yml` or publish port 22.

### 1. Install the host support and create the shared volume

#### macOS

Run once for each project on the Mac, before rebuilding its Dev Container:

```sh
./scripts/install-host.sh \
  YOUR_SSH_ALIAS \
  "/Users/YOUR_MACOS_USER/YOUR_PROJECT_PATH" \
  YOUR_REMOTE_USER
```

Replace every `YOUR_...` value: choose a unique alias, provide the macOS user
name and slash-separated project path relative to that user's home, and set
`YOUR_REMOTE_USER` to the Dev Container `remoteUser` (commonly `vscode`).

The final argument is the container's Dev Container `remoteUser`. The script
creates or reuses the global Docker volume named `codex-data`, creates a
dedicated SSH key, installs the Docker-backed proxy, adds the project to a local
allowlist, and writes a separate SSH config fragment. Running the script again
does not recreate or clear the volume.

#### Windows host with a Windows or WSL2 workspace

Run the PowerShell installer once for each project from a Windows terminal,
before rebuilding its Dev Container. For a project stored in WSL2, pass its UNC
path, not its Linux path. Replace every `YOUR_...` value before running the
command:

```powershell
.\scripts\install-host.ps1 `
  "YOUR_SSH_ALIAS" `
  "\\wsl.localhost\YOUR_WSL_DISTRO\home\YOUR_WSL_USER\YOUR_PROJECT_PATH" `
  "YOUR_REMOTE_USER"
```

Replace the placeholders as follows:

| Placeholder | Replace with |
| --- | --- |
| `YOUR_SSH_ALIAS` | A unique local SSH name, such as `my-project-devcontainer` |
| `YOUR_WSL_DISTRO` | The distribution name from `wsl.exe --list --quiet`, such as `Ubuntu` |
| `YOUR_WSL_USER` | The Linux user that owns the project inside that distribution |
| `YOUR_WINDOWS_USER` | The Windows account that owns a project stored directly on Windows |
| `YOUR_PROJECT_PATH` | The project path relative to that user's home, using backslashes on Windows; for example, `projects\my-project` |
| `YOUR_REMOTE_USER` | The Dev Container `remoteUser`; commonly `vscode` for Microsoft Dev Container images |

For example, if the Linux project path is
`/home/devuser/projects/my-project`, use `devuser` for `YOUR_WSL_USER` and
`projects\my-project` for `YOUR_PROJECT_PATH`. The completed UNC path must name
the exact directory that VS Code opened.

For a project stored directly on Windows, pass its normal Windows path instead:

```powershell
.\scripts\install-host.ps1 `
  "YOUR_SSH_ALIAS" `
  "C:\Users\YOUR_WINDOWS_USER\YOUR_PROJECT_PATH" `
  "YOUR_REMOTE_USER"
```

The Windows installer writes the SSH configuration and key under
`$HOME\.ssh`, installs the PowerShell Docker proxy under `$HOME\.local\bin`,
and records the exact workspace path under
`$HOME\.config\codex-devcontainer-remote`. Windows OpenSSH runs the proxy,
which uses Docker Desktop to enter the matching container. WSL2 is only the
workspace location; do not run the Linux host installer inside WSL2 when the
SSH client is ChatGPT Desktop or another Windows application.

The generated Windows host state is:

- `$HOME\.local\bin\codex-devcontainer-proxy.ps1`;
- `$HOME\.config\codex-devcontainer-remote\projects`;
- `$HOME\.ssh\codex-devcontainer_ed25519` and its `.pub` file;
- `$HOME\.ssh\config` with an `Include` directive;
- `$HOME\.ssh\config.d\codex-devcontainers\ALIAS.conf`;
- the Docker volume named `codex-data`.

The installer restricts generated files to the current Windows account and is
safe to rerun; it preserves the existing key and Docker volume.

If Windows PowerShell blocks local scripts, invoke the installer without
changing the machine-wide execution policy:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-host.ps1 `
  "YOUR_SSH_ALIAS" `
  "\\wsl.localhost\YOUR_WSL_DISTRO\home\YOUR_WSL_USER\YOUR_PROJECT_PATH" `
  "YOUR_REMOTE_USER"
```

The global volume must exist before a Docker Compose project can opt into it as
an external volume. If only the volume bootstrap is needed, run:

```sh
docker volume create codex-data
```

### 2. Always install the Feature

Add this to VS Code **User** settings, not to a project's settings:

```jsonc
"dev.containers.defaultFeatures": {
  "ghcr.io/kabuto412rock/devcontainer-remote-features/codex-remote:0": {}
}
```

Rebuild the Dev Container after the package has been published.

The Feature mounts `codex-data` at `/usr/local/share/codex-data` and sets both
`CODEX_HOME` and `CODEX_INSTALL_DIR` to locations under that mount. Image- and
Dockerfile-based Dev Containers use the global Docker volume named
`codex-data`, so projects on the same Docker daemon share the existing Codex
installation and state automatically.

Docker Compose scopes Feature-declared volume names to its project by default.
To share the global volume across Compose projects, add this top-level volume
declaration to each project's `docker-compose.yml`; the Feature supplies the
service-level mount:

```yaml
volumes:
  codex-data:
    name: codex-data
    external: true
```

Run the host setup above first so the external volume exists, then rebuild the
Dev Container. Without this declaration, a Compose project uses its own volume,
such as `someproject_codex-data`, and shares state only across its rebuilds.

The volume contains all user-scoped Codex data, including authentication,
configuration, skills, sessions, logs, and the standalone installation. Every
Dev Container attached to the global volume can therefore access the same
sensitive Codex credentials and history. Only share it with containers you
trust.

If a project already mounts a separate volume such as the following, remove it
to avoid split or shadowed Codex state:

```yaml
- codex-data:/home/vscode/.codex
```

An existing global `codex-data` volume containing only authentication or
configuration can be reused. The Feature preserves its contents and adds the
CLI when the shared executable is missing. Do not prune this volume unless you
intend to remove the cached login and Codex state. Likewise, do not run
`docker compose down -v` for a project-scoped volume unless you intend to
remove that project's state.

Older Docker Compose projects may have project-scoped volumes with names such
as `someproject_codex-data`. They are not merged automatically. List candidates
with:

```sh
docker volume ls --format '{{.Name}}' | grep '_codex-data$'
```

If the new global `codex-data` volume is still empty, choose exactly one old
volume as the source and copy it before starting new containers:

```sh
docker run --rm \
  -v someproject_codex-data:/from:ro \
  -v codex-data:/to \
  alpine:3.20 sh -c 'cp -a /from/. /to/'
```

Do not combine multiple old volumes or copy into a populated target without
first backing them up and resolving conflicts.

Codex is not updated automatically while
`/usr/local/share/codex-data/bin/codex` exists. To update it, rerun the official
installer with the same `CODEX_HOME` and `CODEX_INSTALL_DIR`, or remove that
executable and restart a container using the Feature.

### 3. Verify the SSH alias

Verify the connection from the same host environment where the installer ran.
On Windows, run this from PowerShell or Command Prompt, not from WSL2:

```sh
ssh YOUR_SSH_ALIAS
command -v codex
codex --version
```

Then use the same SSH host alias in ChatGPT Desktop under
**Settings → Connections → SSH**.

To inspect the effective Windows OpenSSH settings before connecting, run:

```powershell
ssh -G YOUR_SSH_ALIAS |
  Select-String '^(user|hostname|identityfile|proxycommand) '
```

The `proxycommand` must reference `codex-devcontainer-proxy.ps1`. If the proxy
reports that it found zero containers, confirm that the Dev Container is
running and inspect its `devcontainer.local_folder` label:

```powershell
docker ps --filter "label=devcontainer.local_folder" --format "{{.ID}} {{.Labels}}"
```

### Trust model

- The Feature source is the code in [`src/codex-remote`](src/codex-remote).
- Codex is fetched only from `https://chatgpt.com/codex/install.sh`.
- OpenSSH, `curl`, CA certificates, and netcat come from the container's
  Debian/Ubuntu package repository.
- No password authentication or root SSH login is enabled.
- No host port is exposed. The local proxy only selects running containers
  whose exact workspace path appears in its allowlist. The Windows proxy
  normalizes slash direction and path casing so Docker Desktop's WSL2 UNC
  labels compare correctly.
- SSH host-key checking is disabled for this alias because a rebuilt container
  generates a new key. The connection instead trusts the local Docker daemon,
  exact workspace label, allowlist, and dedicated client key.

Docker access is effectively host-administrator access. Keep the proxy and its
allowlist owned and writable only by your host account.

### Compatibility

The Feature supports Debian and Ubuntu family images with a non-root or root
Dev Container user. Other Linux distributions fail with a clear error.

The Windows host scripts require Windows OpenSSH, Windows PowerShell 5.1 or
PowerShell 7, and Docker Desktop using Linux containers. WSL2 workspaces must
be reachable through their `\\wsl.localhost\DISTRO\...` UNC path.

The shared volume requires the Dev Containers to use the same Docker daemon.
Sharing between non-root container users assumes they map to the same numeric
UID; different UIDs are not guaranteed to have compatible write permissions.
The Feature metadata uses only fields from the official Feature mount schema;
Docker Compose sharing is configured explicitly in the project's Compose file.
Projects requiring isolated Codex credentials should omit the external volume
declaration and retain their project-scoped volume.

## Release

Run the **Release dev container features** workflow manually. It publishes the
Feature to GitHub Container Registry as:

```text
ghcr.io/kabuto412rock/devcontainer-remote-features/codex-remote:0
```

The first published GHCR package may need its visibility changed to public in
GitHub package settings before unauthenticated Dev Container builds can pull it.
