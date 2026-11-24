param(
    [int]$Count = 1,
    [switch]$DebugConsole,
    [switch]$NoInject,
    [switch]$AutoJoin,
    [string]$HostAddr = "127.0.0.1",
    [int]$Port = 27890
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$GameDir = Join-Path $RepoRoot "game"
$GameExe = Join-Path $GameDir "Game.exe"

if (-not (Test-Path $GameExe)) {
    Write-Error "Game.exe not found at $GameExe. Run 'python tools/extract_game.py' first."
}

if (-not $NoInject) {
    Write-Host "[maruchi] Ensuring external loader is injected into game/Data/Scripts.rvdata..."
    python (Join-Path $RepoRoot "tools\rvdata_scripts.py") inject
}

$ArgList = @()
if ($DebugConsole) {
    $ArgList += "debug"
}

$env:MARUCHI_HOST = $HostAddr
$env:MARUCHI_PORT = "$Port"
if ($AutoJoin) {
    $env:MARUCHI_AUTO_JOIN = "1"
} else {
    Remove-Item Env:MARUCHI_AUTO_JOIN -ErrorAction SilentlyContinue
}

for ($i = 1; $i -le $Count; $i++) {
    $env:MARUCHI_NAME = "Player$i"
    $env:MARUCHI_ACTOR_ID = "$i"
    Write-Host "[maruchi] Launching Game.exe instance #$i (Host=${HostAddr}:${Port}, AutoJoin=$AutoJoin, DebugConsole=$DebugConsole)..."
    if ($ArgList.Count -gt 0) {
        Start-Process -FilePath $GameExe -WorkingDirectory $GameDir -ArgumentList $ArgList
    } else {
        Start-Process -FilePath $GameExe -WorkingDirectory $GameDir
    }
    if ($i -lt $Count) {
        Start-Sleep -Milliseconds 800
    }
}
