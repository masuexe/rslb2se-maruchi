#!/usr/bin/env python3
"""Read, extract, diff, and inject scripts in RPG Maker VX Data/Scripts.rvdata (Ruby Marshal 4.8)."""

from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import sys
import zlib
from dataclasses import dataclass
from pathlib import Path
from typing import Any, List, Tuple

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_RVDATA = ROOT / "game" / "Data" / "Scripts.rvdata"
DEFAULT_ORIG = ROOT / "game" / "Data" / "Scripts.rvdata.orig"
LOADER_SCRIPT_ID = 99990001
LOADER_SCRIPT_TITLE = "▼ Maruchi Loader"


@dataclass
class ScriptEntry:
    script_id: int
    title: str
    code: bytes  # UTF-8 / raw bytes as stored in Scripts.rvdata


class MarshalReader:
    """Minimal Ruby Marshal 4.8 reader supporting types found in Scripts.rvdata."""

    def __init__(self, data: bytes) -> None:
        self.data = data
        self.pos = 0
        self.symbols: List[bytes] = []
        self.objects: List[Any] = []

    def read_byte(self) -> int:
        b = self.data[self.pos]
        self.pos += 1
        return b

    def read_bytes(self, n: int) -> bytes:
        chunk = self.data[self.pos : self.pos + n]
        if len(chunk) != n:
            raise EOFError(f"Unexpected EOF reading {n} bytes at {self.pos}")
        self.pos += n
        return chunk

    def read_fixnum(self) -> int:
        c = self.read_byte()
        if c == 0:
            return 0
        if c >= 128:
            c -= 256
        if 5 <= c <= 127:
            return c - 5
        if -128 <= c <= -5:
            return c + 5
        if 1 <= c <= 4:
            val = 0
            for i in range(c):
                val |= self.read_byte() << (8 * i)
            return val
        if -4 <= c <= -1:
            n = -c
            val = -1
            for i in range(n):
                val &= ~(0xFF << (8 * i))
                val |= self.read_byte() << (8 * i)
            return val
        raise ValueError(f"Invalid Marshal fixnum header byte: {c}")

    def read_value(self) -> Any:
        tag = chr(self.read_byte())
        if tag == "0":
            return None
        if tag == "T":
            return True
        if tag == "F":
            return False
        if tag == "i":
            return self.read_fixnum()
        if tag == '"':
            length = self.read_fixnum()
            raw = self.read_bytes(length)
            self.objects.append(raw)
            return raw
        if tag == ":":
            length = self.read_fixnum()
            sym = self.read_bytes(length)
            self.symbols.append(sym)
            return sym
        if tag == ";":
            idx = self.read_fixnum()
            return self.symbols[idx]
        if tag == "@":
            idx = self.read_fixnum()
            return self.objects[idx]
        if tag == "[":
            length = self.read_fixnum()
            arr: List[Any] = []
            self.objects.append(arr)
            for _ in range(length):
                arr.append(self.read_value())
            return arr
        if tag == "I":
            inner = self.read_value()
            ivar_count = self.read_fixnum()
            for _ in range(ivar_count):
                _k = self.read_value()
                _v = self.read_value()
            return inner
        raise ValueError(f"Unsupported Marshal tag {tag!r} at offset {self.pos - 1}")

    def load(self) -> Any:
        major = self.read_byte()
        minor = self.read_byte()
        if (major, minor) != (4, 8):
            raise ValueError(f"Unsupported Marshal version {major}.{minor}")
        return self.read_value()


class MarshalWriter:
    """Ruby 1.8.1-compatible Marshal 4.8 writer for Scripts.rvdata (no IVAR encoding tags)."""

    def __init__(self) -> None:
        self.buf = bytearray(b"\x04\x08")

    def write_fixnum(self, n: int) -> None:
        if n == 0:
            self.buf.append(0)
            return
        if 1 <= n <= 122:
            self.buf.append(n + 5)
            return
        if -123 <= n <= -1:
            self.buf.append((n - 5) & 0xFF)
            return
        if n > 0:
            b = []
            x = n
            while x > 0:
                b.append(x & 0xFF)
                x >>= 8
            if len(b) > 4:
                raise OverflowError(f"Fixnum too large: {n}")
            self.buf.append(len(b))
            self.buf.extend(b)
        else:
            # Negative multi-byte two's complement
            for length in range(1, 5):
                min_val = -(1 << (8 * length))
                if n >= min_val:
                    raw = n & ((1 << (8 * length)) - 1)
                    b = [(raw >> (8 * i)) & 0xFF for i in range(length)]
                    self.buf.append((-length) & 0xFF)
                    self.buf.extend(b)
                    return
            raise OverflowError(f"Negative fixnum too small: {n}")

    def write_string(self, data: bytes) -> None:
        self.buf.append(ord('"'))
        self.write_fixnum(len(data))
        self.buf.extend(data)

    def write_scripts(self, entries: List[ScriptEntry]) -> bytes:
        self.buf.append(ord("["))
        self.write_fixnum(len(entries))
        for entry in entries:
            self.buf.append(ord("["))
            self.write_fixnum(3)
            self.buf.append(ord("i"))
            self.write_fixnum(entry.script_id)
            self.write_string(entry.title.encode("utf-8"))
            compressed = zlib.compress(entry.code)
            self.write_string(compressed)
        return bytes(self.buf)


def load_scripts(path: Path) -> List[ScriptEntry]:
    raw = path.read_bytes()
    parsed = MarshalReader(raw).load()
    if not isinstance(parsed, list):
        raise ValueError("Top-level Scripts.rvdata object is not an Array")
    entries: List[ScriptEntry] = []
    for idx, item in enumerate(parsed):
        if not isinstance(item, list) or len(item) != 3:
            raise ValueError(f"Invalid script tuple at index {idx}")
        script_id, title_bytes, code_z = item
        title = title_bytes.decode("utf-8", errors="replace") if isinstance(title_bytes, bytes) else str(title_bytes)
        code = zlib.decompress(code_z) if code_z else b""
        entries.append(ScriptEntry(int(script_id), title, code))
    return entries


def save_scripts(path: Path, entries: List[ScriptEntry]) -> None:
    data = MarshalWriter().write_scripts(entries)
    # Round-trip sanity check before touching disk
    check = MarshalReader(data).load()
    assert len(check) == len(entries), "Round-trip length mismatch"
    path.write_bytes(data)


def sanitize_filename(title: str) -> str:
    cleaned = re.sub(r'[\\/:*?"<>|]+', "_", title).strip()
    return cleaned if cleaned else "untitled"


def cmd_list(args: argparse.Namespace) -> int:
    entries = load_scripts(args.rvdata)
    print(f"Total scripts in {args.rvdata}: {len(entries)}")
    for idx, e in enumerate(entries):
        lines = e.code.count(b"\n") + (1 if e.code else 0)
        print(f"{idx:03d}  id={e.script_id:<10d}  lines={lines:<5d}  {e.title}")
    return 0


def cmd_extract(args: argparse.Namespace) -> int:
    entries = load_scripts(args.rvdata)
    out_dir: Path = args.out
    out_dir.mkdir(parents=True, exist_ok=True)
    for idx, e in enumerate(entries):
        fname = f"{idx:03d}_{sanitize_filename(e.title)}.rb"
        (out_dir / fname).write_bytes(e.code)
    print(f"Extracted {len(entries)} scripts -> {out_dir}")
    return 0


def cmd_compare(args: argparse.Namespace) -> int:
    entries = load_scripts(args.rvdata)
    other_dir: Path = args.other_dir
    other_files = sorted(other_dir.glob("*.rb"))
    print(f"Scripts.rvdata count : {len(entries)}")
    print(f"Other dir count      : {len(other_files)} ({other_dir})")

    rv_by_title = {}
    for idx, e in enumerate(entries):
        rv_by_title.setdefault(e.title, []).append((idx, e))

    def norm(b: bytes) -> bytes:
        return b.replace(b"\r\n", b"\n").strip()

    # Compare by index up to min length and also match by content hash
    rv_hashes = {hashlib.sha1(norm(e.code)).hexdigest(): (idx, e.title) for idx, e in enumerate(entries) if norm(e.code)}
    other_hashes = {}
    for p in other_files:
        h = hashlib.sha1(norm(p.read_bytes())).hexdigest()
        other_hashes[h] = p.name

    only_in_rv = [(idx, e.title, len(e.code)) for idx, e in enumerate(entries) if norm(e.code) and hashlib.sha1(norm(e.code)).hexdigest() not in other_hashes]
    only_in_other = [(p.name, p.stat().st_size) for p in other_files if norm(p.read_bytes()) and hashlib.sha1(norm(p.read_bytes())).hexdigest() not in rv_hashes]

    print(f"\nNon-empty scripts only/modified in Scripts.rvdata ({len(only_in_rv)}):")
    for idx, title, sz in only_in_rv:
        print(f"  [{idx:03d}] {title} ({sz} bytes)")

    print(f"\nNon-empty scripts only/modified in {other_dir.name} ({len(only_in_other)}):")
    for name, sz in only_in_other:
        print(f"  {name} ({sz} bytes)")
    return 0


def build_bootstrap_code(loader_rel_path: str) -> bytes:
    code = f"""#==============================================================================
# Maruchi External Script Loader Bootstrap
# Auto-injected by tools/rvdata_scripts.py (do not edit in RMVX Editor)
#==============================================================================
module MaruchiBootstrap
  LOADER_CANDIDATES = [
    File.expand_path("{loader_rel_path}", Dir.pwd),
    File.expand_path("../{loader_rel_path}", Dir.pwd),
    "{loader_rel_path}"
  ]

  def self.boot
    path = nil
    LOADER_CANDIDATES.each do |candidate|
      if File.exist?(candidate)
        path = candidate
        break
      end
    end
    if path.nil?
      return
    end
    begin
      $MARUCHI_LOADER_PATH = path
      src = File.open(path, "rb") {{ |f| f.read }}
      eval(src, TOPLEVEL_BINDING, path, 1)
    rescue Exception => e
      msg = "[MaruchiBootstrap] Failed to load #{{path}}:\\n#{{e.class}}: #{{e.message}}\\n#{{(e.backtrace || []).first(10).join(\"\\n\")}}"
      begin
        File.open("maruchi_boot_error.log", "wb") {{ |f| f.write(msg) }}
      rescue Exception
      end
      raise
    end
  end
end

MaruchiBootstrap.boot
"""
    return code.replace("\n", "\r\n").encode("utf-8")


def cmd_inject(args: argparse.Namespace) -> int:
    orig_path: Path = args.orig
    out_path: Path = args.out
    if not orig_path.exists():
        raise FileNotFoundError(f"Original Scripts backup not found: {orig_path}")

    entries = load_scripts(orig_path)
    # Remove any previous Maruchi loader entry if present
    entries = [e for e in entries if e.script_id != LOADER_SCRIPT_ID and e.title != LOADER_SCRIPT_TITLE]

    # Insert right before Main (last non-empty script named 'Main')
    insert_idx = len(entries)
    for idx in range(len(entries) - 1, -1, -1):
        if entries[idx].title.strip().lower() == "main":
            insert_idx = idx
            break

    bootstrap = ScriptEntry(
        script_id=LOADER_SCRIPT_ID,
        title=LOADER_SCRIPT_TITLE,
        code=build_bootstrap_code(args.loader_path),
    )
    entries.insert(insert_idx, bootstrap)
    save_scripts(out_path, entries)
    print(f"[inject] Inserted '{LOADER_SCRIPT_TITLE}' at index {insert_idx} (before '{entries[insert_idx + 1].title if insert_idx + 1 < len(entries) else 'EOF'}')")
    print(f"[inject] Wrote {len(entries)} scripts -> {out_path}")
    return 0


def cmd_restore(args: argparse.Namespace) -> int:
    shutil.copy2(args.orig, args.out)
    print(f"[restore] Restored {args.out} from {args.orig}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_list = sub.add_parser("list", help="List scripts in Scripts.rvdata")
    p_list.add_argument("--rvdata", type=Path, default=DEFAULT_RVDATA)
    p_list.set_defaults(func=cmd_list)

    p_ext = sub.add_parser("extract", help="Extract scripts to .rb files")
    p_ext.add_argument("--rvdata", type=Path, default=DEFAULT_ORIG)
    p_ext.add_argument("--out", type=Path, required=True)
    p_ext.set_defaults(func=cmd_extract)

    p_cmp = sub.add_parser("compare", help="Compare Scripts.rvdata against an exported folder")
    p_cmp.add_argument("--rvdata", type=Path, default=DEFAULT_ORIG)
    p_cmp.add_argument("other_dir", type=Path)
    p_cmp.set_defaults(func=cmd_compare)

    p_inj = sub.add_parser("inject", help="Inject Maruchi external script loader into Scripts.rvdata")
    p_inj.add_argument("--orig", type=Path, default=DEFAULT_ORIG)
    p_inj.add_argument("--out", type=Path, default=DEFAULT_RVDATA)
    p_inj.add_argument("--loader-path", default="client/loader.rb")
    p_inj.set_defaults(func=cmd_inject)

    p_res = sub.add_parser("restore", help="Restore pristine Scripts.rvdata from backup")
    p_res.add_argument("--orig", type=Path, default=DEFAULT_ORIG)
    p_res.add_argument("--out", type=Path, default=DEFAULT_RVDATA)
    p_res.set_defaults(func=cmd_restore)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
