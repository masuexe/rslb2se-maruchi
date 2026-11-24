#!/usr/bin/env python3
"""Extract the base RMVX game archive into ./game with proper GBK/UTF-8 filenames."""

from __future__ import annotations

import argparse
import shutil
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_LOCAL = ROOT / ".local"
DEFAULT_OUT = ROOT / "game"


def find_game_zip(local_dir: Path) -> Path:
    zips = sorted(local_dir.glob("*.zip"))
    if not zips:
        raise FileNotFoundError(f"No .zip archive found in {local_dir}")
    for z in zips:
        if "最终的战斗" in z.name or "RMzas" in z.name:
            return z
    return zips[0]


def extract_game(zip_path: Path, out_dir: Path, force: bool = False) -> None:
    if out_dir.exists() and (out_dir / "Game.exe").exists() and not force:
        print(f"[skip] Game already extracted at {out_dir} (use --force to overwrite)")
        return

    out_dir.mkdir(parents=True, exist_ok=True)
    print(f"[extract] {zip_path.name} -> {out_dir}")
    with zipfile.ZipFile(zip_path, "r", metadata_encoding="gbk") as zf:
        infos = zf.infolist()
        total = len(infos)
        for idx, info in enumerate(infos, 1):
            # Guard against zip-slip
            target = (out_dir / info.filename).resolve()
            if not str(target).startswith(str(out_dir.resolve())):
                raise ValueError(f"Unsafe zip entry path: {info.filename}")
            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with zf.open(info, "r") as src, open(target, "wb") as dst:
                    shutil.copyfileobj(src, dst)
            if idx % 500 == 0 or idx == total:
                print(f"  extracted {idx}/{total} entries...")

    orig_scripts = out_dir / "Data" / "Scripts.rvdata"
    backup_scripts = out_dir / "Data" / "Scripts.rvdata.orig"
    if orig_scripts.exists() and not backup_scripts.exists():
        shutil.copy2(orig_scripts, backup_scripts)
        print(f"[backup] Saved pristine backup -> {backup_scripts}")

    print("[done] Extraction complete.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zip", type=Path, default=None, help="Path to game zip archive")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="Target extraction directory")
    parser.add_argument("--force", action="store_true", help="Re-extract even if game/ exists")
    args = parser.parse_args()

    zip_path = args.zip if args.zip else find_game_zip(DEFAULT_LOCAL)
    extract_game(zip_path, args.out, force=args.force)
    return 0


if __name__ == "__main__":
    sys.exit(main())
