param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$WorkspacePath,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$RemoteUser,

    [Parameter(Mandatory = $true, Position = 2)]
    [string]$KeyFile
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Normalize-WorkspacePath([string]$Path) {
    $value = $Path
    try {
        if (Test-Path -LiteralPath $Path) {
            $value = (Resolve-Path -LiteralPath $Path).ProviderPath
        }
    } catch {
        # Docker labels can refer to paths that are not currently resolvable.
    }

    return (($value -replace '/', '\').TrimEnd('\')).ToLowerInvariant()
}

if (-not (Get-Command docker.exe -ErrorAction SilentlyContinue)) {
    throw 'docker.exe was not found on PATH.'
}
if (-not (Test-Path -LiteralPath $WorkspacePath -PathType Container)) {
    throw "Workspace does not exist: $WorkspacePath"
}
if (-not (Test-Path -LiteralPath "$KeyFile.pub" -PathType Leaf)) {
    throw "Public key not found: $KeyFile.pub"
}

$configHome = if ($env:XDG_CONFIG_HOME) {
    $env:XDG_CONFIG_HOME
} else {
    Join-Path $HOME '.config'
}
$allowlist = Join-Path $configHome 'codex-devcontainer-remote\projects'
$expectedPath = Normalize-WorkspacePath $WorkspacePath
$allowed = $false

if (Test-Path -LiteralPath $allowlist -PathType Leaf) {
    foreach ($allowedPath in Get-Content -LiteralPath $allowlist) {
        if ($allowedPath -and (Normalize-WorkspacePath $allowedPath) -eq $expectedPath) {
            $allowed = $true
            break
        }
    }
}
if (-not $allowed) {
    throw "Workspace is not allowlisted: $WorkspacePath"
}

$matches = @()
$candidateIds = @(& docker.exe ps --filter 'label=devcontainer.local_folder' --format '{{.ID}}')
if ($LASTEXITCODE -ne 0) {
    throw 'docker.exe ps failed.'
}

foreach ($candidateId in $candidateIds) {
    $labelsJson = (& docker.exe inspect --format '{{json .Config.Labels}}' $candidateId).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "docker.exe inspect failed for container $candidateId."
    }
    $labels = $labelsJson | ConvertFrom-Json
    $candidatePath = [string]$labels.'devcontainer.local_folder'
    if ((Normalize-WorkspacePath $candidatePath) -eq $expectedPath) {
        $matches += $candidateId
    }
}

if ($matches.Count -ne 1) {
    throw "Expected one running container for '$WorkspacePath', found $($matches.Count)."
}

$containerId = $matches[0]
$publicKey = (Get-Content -Raw -LiteralPath "$KeyFile.pub").Trim()

& docker.exe exec -u 0 $containerId /usr/local/sbin/codex-remote-authorize $RemoteUser $publicKey
if ($LASTEXITCODE -ne 0) {
    throw 'The container rejected the public key.'
}

for ($attempt = 0; $attempt -lt 30; $attempt++) {
    & docker.exe exec $containerId sh -c 'nc -z 127.0.0.1 22 >/dev/null 2>&1'
    if ($LASTEXITCODE -eq 0) {
        break
    }
    if ($attempt -eq 29) {
        throw 'SSH did not become ready within 30 seconds.'
    }
    Start-Sleep -Seconds 1
}

# OpenSSH uses this native process directly as its byte stream.
& docker.exe exec -i $containerId nc 127.0.0.1 22
exit $LASTEXITCODE
