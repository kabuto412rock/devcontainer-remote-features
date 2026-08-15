param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$SshAlias,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$WorkspacePath,

    [Parameter(Mandatory = $true, Position = 2)]
    [string]$RemoteUser
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($SshAlias -notmatch '^[A-Za-z0-9._-]+$') {
    throw 'SSH alias may contain only letters, digits, dot, underscore, and dash.'
}
if ($RemoteUser -notmatch '^[A-Za-z0-9._-]+$') {
    throw 'Invalid remote user.'
}
if (-not (Get-Command docker.exe -ErrorAction SilentlyContinue)) {
    throw 'docker.exe was not found on PATH.'
}
if (-not (Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue)) {
    throw 'ssh-keygen.exe was not found on PATH.'
}
if (-not (Get-Command icacls.exe -ErrorAction SilentlyContinue)) {
    throw 'icacls.exe was not found on PATH.'
}
if (-not (Test-Path -LiteralPath $WorkspacePath -PathType Container)) {
    throw "Workspace does not exist: $WorkspacePath"
}

$WorkspacePath = (Resolve-Path -LiteralPath $WorkspacePath).ProviderPath.TrimEnd('\')

& docker.exe volume inspect codex-data *> $null
if ($LASTEXITCODE -eq 0) {
    Write-Host 'Reusing shared Docker volume: codex-data'
} else {
    & docker.exe volume create codex-data *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create the shared Docker volume 'codex-data'. Check that Docker Desktop is running."
    }
    Write-Host 'Created shared Docker volume: codex-data'
}

$binDir = Join-Path $HOME '.local\bin'
$configDir = if ($env:XDG_CONFIG_HOME) {
    Join-Path $env:XDG_CONFIG_HOME 'codex-devcontainer-remote'
} else {
    Join-Path $HOME '.config\codex-devcontainer-remote'
}
$sshDir = Join-Path $HOME '.ssh'
$fragmentDir = Join-Path $sshDir 'config.d\codex-devcontainers'
$sshConfig = Join-Path $sshDir 'config'
$keyFile = Join-Path $sshDir 'codex-devcontainer_ed25519'
$proxyFile = Join-Path $binDir 'codex-devcontainer-proxy.ps1'
$projectsFile = Join-Path $configDir 'projects'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

function Protect-UserFile([string]$Path) {
    & icacls.exe $Path /inheritance:r /grant:r "${currentIdentity}:(F)" *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to restrict file permissions: $Path"
    }
}

New-Item -ItemType Directory -Force -Path $binDir, $configDir, $sshDir, $fragmentDir | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'codex-devcontainer-proxy.ps1') -Destination $proxyFile -Force
Protect-UserFile $proxyFile

if (-not (Test-Path -LiteralPath $keyFile -PathType Leaf)) {
    # Windows PowerShell 5.1 drops a native empty-string argument. Passing a
    # quoted empty value preserves it for ssh-keygen's own argument parser.
    & ssh-keygen.exe -q -t ed25519 -f $keyFile -N '""' -C 'codex-devcontainer-remote'
    if ($LASTEXITCODE -ne 0) {
        throw 'ssh-keygen.exe failed.'
    }
}
Protect-UserFile $keyFile
Protect-UserFile "$keyFile.pub"

$projects = if (Test-Path -LiteralPath $projectsFile) {
    @(Get-Content -LiteralPath $projectsFile)
} else {
    @()
}
if ($WorkspacePath -notin $projects) {
    $projects += $WorkspacePath
}
[System.IO.File]::WriteAllText($projectsFile, (($projects -join "`r`n") + "`r`n"), $utf8NoBom)
Protect-UserFile $projectsFile

$includePath = (Join-Path $fragmentDir '*.conf') -replace '\\', '/'
$includeLine = "Include $includePath"
$existingConfig = if (Test-Path -LiteralPath $sshConfig) {
    [System.IO.File]::ReadAllText($sshConfig)
} else {
    ''
}
$remainingConfig = @(($existingConfig -split "`r?`n") | Where-Object {
    $_.Trim() -ne $includeLine
}) -join "`r`n"
$remainingConfig = $remainingConfig.Trim()
$newConfig = if ($remainingConfig) {
    "$includeLine`r`n`r`n$remainingConfig`r`n"
} else {
    "$includeLine`r`n"
}
[System.IO.File]::WriteAllText($sshConfig, $newConfig, $utf8NoBom)
Protect-UserFile $sshConfig

$identityPath = $keyFile -replace '\\', '/'
$proxyPath = $proxyFile -replace '\\', '/'
$fragment = @"
Host $SshAlias
    HostName $SshAlias
    Port 22
    User $RemoteUser
    IdentityFile $identityPath
    IdentitiesOnly yes
    PreferredAuthentications publickey
    PasswordAuthentication no
    StrictHostKeyChecking no
    UserKnownHostsFile NUL
    ProxyCommand powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$proxyPath" "$WorkspacePath" %r "$identityPath"
"@
$fragmentFile = Join-Path $fragmentDir "$SshAlias.conf"
[System.IO.File]::WriteAllText($fragmentFile, ($fragment.Trim() + "`r`n"), $utf8NoBom)
Protect-UserFile $fragmentFile

Write-Host "Installed SSH alias: $SshAlias"
Write-Host "Workspace allowlisted: $WorkspacePath"
Write-Host "Test after rebuilding the container: ssh $SshAlias"
