param(
    [int]$Count = 1,
    [switch]$DebugConsole,
    [switch]$NoInject
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

for ($i = 1; $i -le $Count; $i++) {
    Write-Host "[maruchi] Launching Game.exe instance #$i (DebugConsole=$DebugConsole)..."
    if ($ArgList.Count -gt 0) {
        Start-Process -FilePath $GameExe -WorkingDirectory $GameDir -ArgumentList $ArgList
    } else {
        Start-Process -FilePath $GameExe -WorkingDirectory $GameDir
    }
    if ($i -lt $Count) {
        Start-Sleep -Milliseconds 600
    }
}
