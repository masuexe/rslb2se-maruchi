#!/usr/bin/env python3
"""Package v0.1.0 release archives for players (client patch) and server hosts."""

from __future__ import annotations

import argparse
import shutil
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import rvdata_scripts as rs  # noqa: E402

VERSION = "0.1.0"

PLAYER_README = f"""====================================================================
  rslb2se-maruchi v{VERSION} — 联机客户端补丁包 (玩家版)
  适用游戏：RMzas&SMS_最终的战斗 2 Special Edition (v2.30)
====================================================================

【一、安装步骤】
1. 备份你原版游戏目录下的 Data\\Scripts.rvdata（方便随时还原单机原版）。
2. 将本压缩包内的所有文件和文件夹解压并覆盖到原版游戏根目录（与 Game.exe 同级）：
   - Data\\Scripts.rvdata
   - maruchi_net.dll
   - maruchi\\
   - maruchi.ini
3. 用记事本打开游戏根目录下的 maruchi.ini，修改：
   - host = 服务器 IP（或域名）
   - port = 服务器端口（默认 27890）
   - name = 你的昵称（支持中文）
4. 双击 Game.exe 启动游戏！

【二、联机快捷键与操作】
- F7 ：连接 / 重连服务器（也可在 maruchi.ini 中设 auto_join = 1 自动连接）
- F8 ：打开联机大厅菜单
       * 切换角色（支持全部 137 名角色）
       * 全队传送地图（含推荐战斗/Boss 图及全地图列表）
       * 实时切换 CO-OP（合作） / PVP（对战）模式
       * 重连 / 断开服务器
- 确定键 (Z / Enter / Space) ：调查 NPC、宝箱、机关（已同步至服务端）
- 倒地复活：HP 归零后 5 秒自动复活，合作模式下队友靠近可 4 倍加速复活
- 剧情过场：由房主（队伍列表带 [H] 标记）控制对话翻页与选项，全队同步观看
- 后台运行：窗口失焦时仍保持 60fps 联机同步，且不会误触按键

【三、排错】
- 运行日志位于：maruchi\\logs\\client_*.log
- 如提示 "Ver mismatch!"，请确保客户端与服务端为同一版本（v{VERSION}）。
- 如需恢复纯单机原版，将第 1 步备份的 Scripts.rvdata 覆盖回 Data\\ 即可。
"""

SERVER_README = f"""====================================================================
  rslb2se-maruchi v{VERSION} — 跨平台无头联机服务端 (Linux / Windows)
====================================================================

【一、环境要求】
- Ruby 3.2+（Linux: sudo apt install -y ruby；Windows: RubyInstaller 3.2+）
- 原版游戏文件：将原版游戏的 Data\\ 目录（含 Scripts.rvdata 与各 Map*.rvdata）
  以及 Graphics\\（可选，用于精准读取精灵尺寸）放到本目录的 game\\ 下：
    game/Data/Scripts.rvdata.orig   (或直接命名为 Scripts.rvdata)
    game/Data/Actors.rvdata
    game/Data/Map001.rvdata ...

  注意：server/rgss2/runtime.rb 默认读取 game/Data/Scripts.rvdata.orig，
  如果只有原版 Scripts.rvdata，请复制一份命名为 Scripts.rvdata.orig。

【二、启动服务端】
  ruby server/server.rb --host 0.0.0.0 --port 27890 --map 116 --mode coop

常用参数：
  --host HOST      监听地址（默认 0.0.0.0）
  --port PORT      TCP 端口（默认 27890，云服务器请放行 TCP 27890）
  --game-dir DIR   游戏资源目录路径（默认 ./game）
  --map ID         初始地图 ID（默认 116）
  --mode MODE      初始模式：coop 或 pvp（默认 coop）
  --tick-rate HZ   逻辑帧率（默认 60）
  --snap-rate HZ   状态快照频率（默认 30）
"""


def find_dll() -> Path:
    candidates = [
        ROOT / "native" / "maruchi_net" / "target" / "i686-pc-windows-msvc" / "release" / "maruchi_net.dll",
        ROOT / "game" / "maruchi_net.dll",
    ]
    for p in candidates:
        if p.is_file():
            return p
    raise FileNotFoundError(
        "maruchi_net.dll not found. Build it first with: "
        "cargo build --manifest-path native/maruchi_net/Cargo.toml --target i686-pc-windows-msvc --release"
    )


def zip_dir(src_dir: Path, out_zip: Path) -> None:
    if out_zip.exists():
        out_zip.unlink()
    with zipfile.ZipFile(out_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for path in sorted(src_dir.rglob("*")):
            if path.is_file():
                zf.write(path, path.relative_to(src_dir))


def build_client_package(
    dist_dir: Path,
    version: str,
    host: str = "127.0.0.1",
    port: int = 27890,
    auto_join: bool = False,
) -> Path:
    pkg_dir = dist_dir / f"rslb2se-maruchi-v{version}-client"
    if pkg_dir.exists():
        shutil.rmtree(pkg_dir)
    pkg_dir.mkdir(parents=True)

    # 1. Inject Scripts.rvdata from pristine original
    orig_rvdata = rs.DEFAULT_ORIG
    if not orig_rvdata.is_file():
        raise FileNotFoundError(f"Original Scripts.rvdata.orig not found at {orig_rvdata}")
    data_dir = pkg_dir / "Data"
    data_dir.mkdir(parents=True)
    inj_args = argparse.Namespace(
        orig=orig_rvdata,
        out=data_dir / "Scripts.rvdata",
        loader_path="maruchi/client/loader.rb",
    )
    rs.cmd_inject(inj_args)

    # 2. Copy maruchi_net.dll
    dll_path = find_dll()
    shutil.copy2(dll_path, pkg_dir / "maruchi_net.dll")

    # 3. Copy client/ and shared/ under maruchi/
    maruchi_dir = pkg_dir / "maruchi"
    shutil.copytree(
        ROOT / "client",
        maruchi_dir / "client",
        ignore=shutil.ignore_patterns(".gitkeep", "*.log", "__pycache__"),
    )
    shutil.copytree(
        ROOT / "shared",
        maruchi_dir / "shared",
        ignore=shutil.ignore_patterns("README.md", "__pycache__"),
    )

    # 4. Render maruchi.ini and player README
    ini_text = (ROOT / "maruchi.ini.example").read_text(encoding="utf-8")
    ini_text = ini_text.replace("host = 127.0.0.1", f"host = {host}", 1)
    ini_text = ini_text.replace("port = 27890", f"port = {port}", 1)
    ini_text = ini_text.replace("auto_join = 0", f"auto_join = {1 if auto_join else 0}", 1)
    (pkg_dir / "maruchi.ini").write_text(ini_text, encoding="utf-8")
    (pkg_dir / "README_PLAYER.txt").write_text(PLAYER_README, encoding="utf-8")

    out_zip = dist_dir / f"rslb2se-maruchi-v{version}-client.zip"
    zip_dir(pkg_dir, out_zip)
    print(f"[package] Built client release -> {out_zip} ({out_zip.stat().st_size} bytes, host={host}:{port}, auto_join={auto_join})")
    return out_zip


def build_server_package(dist_dir: Path, version: str) -> Path:
    pkg_dir = dist_dir / f"rslb2se-maruchi-v{version}-server"
    if pkg_dir.exists():
        shutil.rmtree(pkg_dir)
    pkg_dir.mkdir(parents=True)

    shutil.copytree(
        ROOT / "server",
        pkg_dir / "server",
        ignore=shutil.ignore_patterns("poc_headless.rb", "__pycache__"),
    )
    shutil.copytree(
        ROOT / "shared",
        pkg_dir / "shared",
        ignore=shutil.ignore_patterns("__pycache__"),
    )
    (pkg_dir / "README_SERVER.txt").write_text(SERVER_README, encoding="utf-8")

    out_zip = dist_dir / f"rslb2se-maruchi-v{version}-server.zip"
    zip_dir(pkg_dir, out_zip)
    print(f"[package] Built server release -> {out_zip} ({out_zip.stat().st_size} bytes)")
    return out_zip


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default=VERSION, help=f"Release version tag (default: {VERSION})")
    parser.add_argument("--out", type=Path, default=ROOT / "dist", help="Output directory (default: dist/)")
    parser.add_argument("--host", default="127.0.0.1", help="Default server host written into client maruchi.ini")
    parser.add_argument("--port", type=int, default=27890, help="Default server port written into client maruchi.ini")
    parser.add_argument("--auto-join", action="store_true", help="Enable auto_join = 1 in client maruchi.ini")
    args = parser.parse_args()

    args.out.mkdir(parents=True, exist_ok=True)
    build_client_package(args.out, args.version, host=args.host, port=args.port, auto_join=args.auto_join)
    build_server_package(args.out, args.version)
    return 0


if __name__ == "__main__":
    sys.exit(main())
