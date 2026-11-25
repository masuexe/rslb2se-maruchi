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

$pids = @()
for ($i = 1; $i -le $Count; $i++) {
    $env:MARUCHI_NAME = "Player$i"
    $env:MARUCHI_ACTOR_ID = "$i"
    Write-Host "[maruchi] Launching Game.exe instance #$i (Host=${HostAddr}:${Port}, AutoJoin=$AutoJoin, DebugConsole=$DebugConsole)..."
    if ($ArgList.Count -gt 0) {
        $p = Start-Process -FilePath $GameExe -WorkingDirectory $GameDir -ArgumentList $ArgList -PassThru
    } else {
        $p = Start-Process -FilePath $GameExe -WorkingDirectory $GameDir -PassThru
    }
    $pids += $p.Id
    if ($i -lt $Count) {
        Start-Sleep -Milliseconds 800
    }
}

# Wait briefly for RGSS Player windows to appear, then tile them side-by-side and bring to front
Start-Sleep -Seconds 3
$pidCsv = ($pids -join ",")
python -c @"
import ctypes, ctypes.wintypes as wt, time
user32 = ctypes.windll.user32
pids = [int(x) for x in '$pidCsv'.split(',') if x.strip()]
for attempt in range(10):
    found = {}
    @ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)
    def cb(hwnd, _):
        wpid = wt.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(wpid))
        if wpid.value in pids:
            cls = ctypes.create_unicode_buffer(64)
            user32.GetClassNameW(hwnd, cls, 64)
            if cls.value == 'RGSS Player':
                found[wpid.value] = hwnd
        return True
    user32.EnumWindows(cb, 0)
    if len(found) == len(pids):
        break
    time.sleep(0.5)

SW_SHOW = 5
SW_RESTORE = 9
HWND_TOPMOST = -1
HWND_NOTOPMOST = -2
SWP_NOSIZE = 0x0001
SWP_NOMOVE = 0x0002
SWP_SHOWWINDOW = 0x0040
for idx, pid in enumerate(pids):
    hwnd = found.get(pid)
    if not hwnd:
        print(f'[maruchi] WARN: RGSS Player window not found for PID {pid}')
        continue
    rect = wt.RECT()
    user32.GetWindowRect(hwnd, ctypes.byref(rect))
    w = max(rect.right - rect.left, 550)
    h = max(rect.bottom - rect.top, 445)
    x = 80 + idx * (w + 24)
    y = 140
    user32.ShowWindow(hwnd, SW_RESTORE)
    user32.ShowWindow(hwnd, SW_SHOW)
    user32.MoveWindow(hwnd, x, y, w, h, True)
    user32.SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW)
    user32.SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW)
    user32.SetForegroundWindow(hwnd)
    print(f'[maruchi] Positioned P{idx+1} (PID {pid}) at ({x},{y}) {w}x{h} visible={bool(user32.IsWindowVisible(hwnd))}')
"@
