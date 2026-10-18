# Package the Windows x64 CLI and GPUI desktop as dsh-windows-x86_64.zip.
#
#   pwsh -NoProfile -File scripts/package-windows-desktop.ps1
#   pwsh -NoProfile -File scripts/package-windows-desktop.ps1 `
#       -Cli _build/native/release/build/cmd/dsh/dsh.exe `
#       -Desktop _build/native/release/build/desktop/windows/windows.exe
#
# The staging directory is checked for build caches, credentials and session
# data before the archive is created. The SHA-256 is printed and written next
# to the archive.

param(
    [string]$Cli = "_build/native/release/build/cmd/dsh/dsh.exe",
    [string]$Desktop = "_build/native/release/build/desktop/windows/windows.exe",
    [string]$Output = "release/dsh-windows-x86_64"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Resolve-Input([string]$path) {
    if (-not (Test-Path $path -PathType Leaf)) {
        throw "required file is missing: $path"
    }
    return (Resolve-Path $path).Path
}

$cli = Resolve-Input $Cli
$desktop = Resolve-Input $Desktop
$out = [IO.Path]::GetFullPath((Join-Path $root $Output))
$release = Split-Path -Parent $out
$zip = "$out.zip"

if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force $out | Out-Null
New-Item -ItemType Directory -Force $release | Out-Null

Copy-Item $cli (Join-Path $out "dsh.exe")
Copy-Item $desktop (Join-Path $out "dsh-desktop.exe")
foreach ($name in @("LICENSE", "THIRD_PARTY_NOTICES.md")) {
    $source = Join-Path $root $name
    if (Test-Path $source -PathType Leaf) { Copy-Item $source $out }
}
if (Test-Path (Join-Path $root "licenses")) {
    Copy-Item (Join-Path $root "licenses") $out -Recurse
}

$readme = @'
# dsh for Windows x64

Windows 11 x64. No Node.js, WSL, or remote service is required.

    dsh.exe run "Create and verify a durable file." --demo --approve-writes `
      --data-dir C:\dsh-data --workspace C:\work
    dsh.exe web --demo --port 3210
    dsh.exe desktop --demo

`dsh desktop` starts `dsh-desktop.exe` from the same directory, or accepts
`--app-path C:\path\to\dsh-desktop.exe`. `dsh.exe` also serves the browser UI
at the printed loopback URL.

Supported: demo and API-key providers, read / write / edit / glob, durable
sessions, approvals, and the loopback web UI. The data directory is protected
with a current-user-only ACL.

Unsupported on this profile: shell / grep, external MCP, LSP, command hooks,
subagents, ACP, and ChatGPT SIWC. Use `--demo` or an API key.

This build is unsigned. Windows SmartScreen may warn; verify the published
SHA-256 before running it. IME composition is not implemented; paste works.
'@
Set-Content -Path (Join-Path $out "README-windows.md") -Value $readme -Encoding utf8

$forbidden = @(
    "_build", ".git", "node_modules", ".dsh.mbt", "sessions.json",
    "siwc-auth.json", "host.lock", "host-id", "server-id", "workspace-id"
)
$offenders = Get-ChildItem $out -Recurse -Force | Where-Object {
    $forbidden -contains $_.Name
}
if ($offenders) {
    throw "staging directory contains build or credential artifacts: " + (($offenders | ForEach-Object Name) -join ", ")
}
foreach ($required in @("dsh.exe", "dsh-desktop.exe", "README-windows.md")) {
    if (-not (Test-Path (Join-Path $out $required) -PathType Leaf)) {
        throw "staging directory is missing $required"
    }
}

if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip -CompressionLevel Optimal
$hash = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLowerInvariant()
Write-Host "Packaged $zip ($((Get-Item $zip).Length) bytes)"
Write-Host "SHA-256 $hash"
