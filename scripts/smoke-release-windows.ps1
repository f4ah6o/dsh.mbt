# Smoke the packaged dsh-windows-x86_64.zip from an unrelated directory.
#
#   pwsh -NoProfile -File scripts/smoke-release-windows.ps1 release/dsh-windows-x86_64.zip
#
# Extracts into a path containing spaces and non-ASCII characters, then runs
# the CLI demo, the loopback web server, `dsh desktop --app-path`, and sibling
# desktop discovery.

param(
    [Parameter(Mandatory = $true)][string]$Zip
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $Zip -PathType Leaf)) {
    throw "release archive is missing: $Zip"
}
$zipPath = (Resolve-Path $Zip).Path
$temp = Join-Path $env:TEMP ("dsh zip smoke 日本語 " + [guid]::NewGuid().ToString("N"))
$extract = Join-Path $temp "dsh-windows-x86_64"
$workspace = Join-Path $temp "ワークスペース"
$data = Join-Path $temp "data"
New-Item -ItemType Directory -Force $extract, $workspace | Out-Null

function Invoke-Checked([string]$exe, [string[]]$arguments) {
    & $exe @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$exe exited with $LASTEXITCODE for: $($arguments -join ' ')"
    }
}

try {
    Expand-Archive -Path $zipPath -DestinationPath $extract
    $cli = Join-Path $extract "dsh.exe"
    $desktop = Join-Path $extract "dsh-desktop.exe"
    if (-not (Test-Path $cli)) { throw "dsh.exe is missing from the archive" }
    if (-not (Test-Path $desktop)) { throw "dsh-desktop.exe is missing from the archive" }

    Invoke-Checked $cli @(
        "run", "Create and verify a durable file.", "--demo", "--approve-writes",
        "--data-dir", $data, "--workspace", $workspace
    )
    if (-not (Test-Path (Join-Path $workspace "native-demo.txt"))) {
        throw "demo run did not create native-demo.txt"
    }

    # Start-Process joins -ArgumentList with spaces without quoting, which
    # breaks the UTF-8/space path in this smoke directory. Use ArgumentList on
    # ProcessStartInfo so each argument stays intact.
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $cli
    foreach ($argument in @(
        "web", "--demo", "--port", "0", "--data-dir", $data, "--workspace", $workspace
    )) {
        $psi.ArgumentList.Add($argument)
    }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $web = [Diagnostics.Process]::Start($psi)
    try {
        $url = $null
        $deadline = [DateTime]::UtcNow.AddSeconds(45)
        while (-not $url -and [DateTime]::UtcNow -lt $deadline -and -not $web.HasExited) {
            $read = $web.StandardOutput.ReadLineAsync()
            if ($read.Wait(1000) -and $read.Result -match 'https?://[^\s]+') {
                $url = $Matches[0]
            }
        }
        if (-not $url) {
            $stderr = $web.StandardError.ReadToEnd()
            throw "dsh web did not print a loopback URL: $stderr"
        }
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15
        if ($response.StatusCode -ne 200 -or $response.Content.Length -eq 0) {
            throw "dsh web did not return a nonempty HTTP 200 response"
        }
    }
    finally {
        if (-not $web.HasExited) { $web.Kill() }
    }

    $env:GPUI_NATIVE_E2E = "1"
    $frame = Join-Path $temp "frame.ppm"
    Invoke-Checked $cli @(
        "desktop", "--app-path", $desktop, "--offline-e2e",
        "--data-dir", $data, "--workspace", $workspace, "--frame-output", $frame
    )
    if (-not (Test-Path $frame)) { throw "desktop E2E did not write frame evidence" }

    Invoke-Checked $cli @(
        "desktop", "--smoke", "--data-dir", $data, "--workspace", $workspace
    )
    Write-Host "PASS: packaged CLI demo and desktop launch (explicit and sibling discovery)"
}
finally {
    Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue
}
