# Build and smoke the Windows GPUI desktop.
#
#   pwsh -NoProfile -File scripts/build-desktop-windows.ps1 -Mode Build
#   pwsh -NoProfile -File scripts/build-desktop-windows.ps1 -Mode Smoke
#   pwsh -NoProfile -File scripts/build-desktop-windows.ps1 -Mode E2E
#
# Smoke opens a real window, resizes and closes it. E2E drives the demo turn
# through the approval path with GPUI_NATIVE_E2E=1 and writes frame evidence.

param(
    [ValidateSet("Build", "Smoke", "E2E")]
    [string]$Mode = "Build",
    [string]$Workspace = "",
    [string]$DataDir = "",
    [string]$FrameOutput = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    $env:PATH = $env:PATH
    moon build --target native --release desktop/windows cmd/dsh
    if ($LASTEXITCODE -ne 0) {
        throw "moon build failed with exit code $LASTEXITCODE"
    }
    $desktop = Join-Path $root "_build/native/release/build/desktop/windows/windows.exe"
    $cli = Join-Path $root "_build/native/release/build/cmd/dsh/dsh.exe"
    if (-not (Test-Path $desktop)) {
        throw "dsh-desktop.exe was not produced at $desktop"
    }
    if (-not (Test-Path $cli)) {
        throw "dsh.exe was not produced at $cli"
    }
    if ($Mode -eq "Build") {
        Write-Host "Built $desktop"
        return
    }

    if ($Workspace -eq "") {
        $Workspace = Join-Path $env:TEMP ("dsh-desktop-" + [guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force (Join-Path $Workspace "ws") | Out-Null
        $Workspace = Join-Path $Workspace "ws"
    }
    if ($DataDir -eq "") {
        $DataDir = Join-Path (Split-Path -Parent $Workspace) "data"
    }
    if ($FrameOutput -eq "") {
        $FrameOutput = Join-Path (Split-Path -Parent $Workspace) "frame.ppm"
    }
    New-Item -ItemType Directory -Force $Workspace | Out-Null
    $env:DSH_NATIVE_WORKER_BIN = $cli

    if ($Mode -eq "Smoke") {
        & $desktop --smoke --workspace $Workspace --data-dir $DataDir
        if ($LASTEXITCODE -ne 0) {
            throw "dsh-desktop smoke failed with exit code $LASTEXITCODE"
        }
        return
    }

    $env:GPUI_NATIVE_E2E = "1"
    & $desktop --offline-e2e --workspace $Workspace --data-dir $DataDir `
        --frame-output $FrameOutput
    if ($LASTEXITCODE -ne 0) {
        throw "dsh-desktop offline E2E failed with exit code $LASTEXITCODE"
    }
    if (-not (Test-Path $FrameOutput)) {
        throw "frame evidence was not written to $FrameOutput"
    }
    Write-Host "Desktop E2E passed; frame: $FrameOutput"
}
finally {
    Pop-Location
}
