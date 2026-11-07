# One-step local smoke test: copies the Feature source, (re)builds the test
# Dev Container, installs the SSH alias, and checks the CLIs over SSH.
#   .\test\local-devcontainer\run.ps1            # reuse a running container
#   .\test\local-devcontainer\run.ps1 -Rebuild   # recreate the container
param(
    [switch]$Rebuild
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$workspace = $PSScriptRoot
$alias = 'codex-remote-local-test'
$featureCopy = Join-Path $workspace '.devcontainer\codex-remote'

foreach ($tool in 'docker.exe', 'devcontainer') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "$tool was not found on PATH."
    }
}

# Local Features must live under .devcontainer, so copy the current source.
if (Test-Path -LiteralPath $featureCopy) {
    Remove-Item -LiteralPath $featureCopy -Recurse -Force
}
Copy-Item -LiteralPath (Join-Path $repoRoot 'src\codex-remote') -Destination $featureCopy -Recurse

$upArgs = @('up', '--workspace-folder', $workspace, '--no-lockfile')
if ($Rebuild) {
    $upArgs += '--remove-existing-container'
}
& devcontainer @upArgs
if ($LASTEXITCODE -ne 0) {
    throw 'devcontainer up failed.'
}

& (Join-Path $repoRoot 'scripts\install-host.ps1') $alias $workspace vscode

# Git for Windows can shadow Windows OpenSSH on PATH; the alias needs the latter.
$ssh = Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'
& $ssh $alias 'printf "codex: "; codex --version; echo CODEX_HOME=$CODEX_HOME'
if ($LASTEXITCODE -ne 0) {
    throw "SSH check through '$alias' failed."
}
Write-Host "OK: connect with 'ssh $alias'."
