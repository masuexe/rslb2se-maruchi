# Maruchi Headless Server (Cross-Platform: Linux & Windows)

Cross-platform authoritative headless RGSS2 server built on standard Ruby 3.2+ (runs identically on **Linux** and **Windows** with zero GUI, Wine, or Xvfb).

## Components

- `server.rb` — Main authoritative multiplayer server (TCP length-prefixed framing, 60Hz world/XAS simulation, 30Hz snapshots, host-driven cutscenes, protocol version check, idle timeout cleanup).
- `rgss2/ruby18_compat.rb` — Ruby 1.8.1 (RGSS2) to Ruby 3.x compatibility shims and Marshal UTF-8 string normalization.
- `rgss2/primitives.rb` — Exact RGSS2 binary Marshal `_load` / `_dump` implementations for `Table`, `Color`, `Tone`, plus `Rect` and `RGSSError`.
- `rgss2/rpg.rb` — Complete RMVX `RPG::*` data classes (headless-safe audio/BGM/SE).
- `rgss2/headless_stubs.rb` — Headless `Graphics`, programmatic `Input`, `Audio`, `Bitmap` (reads PNG IHDR dimensions when present), `Sprite`, `Viewport`, `Plane`, `Tilemap`, `Window`, `Win32API`, and `load_data` (with case-insensitive fallback for Linux).
- `rgss2/runtime.rb` — Boots the headless RGSS2 runtime directly from `game/Data/Scripts.rvdata.orig` (or `Scripts.rvdata`).
- `poc_headless.rb` — Standalone headless combat verification script (Map #116).

## Running the Multiplayer Server

### Prerequisites
- Ruby 3.2+ (`sudo apt update && sudo apt install -y ruby` on Ubuntu/Debian; RubyInstaller 3.2+ on Windows).
- Original v2.30 game `Data/` (and optional `Graphics/`) placed under `game/`.

### Start Command (Linux & Windows)
```bash
ruby server/server.rb --host 0.0.0.0 --port 27890 --map 116 --mode coop
```

### CLI Options
| Flag | Default | Description |
| --- | --- | --- |
| `--host HOST` | `0.0.0.0` | Bind address |
| `--port PORT` | `27890` | TCP port (allow inbound TCP on firewall/security group) |
| `--game-dir DIR` | `./game` | Path to extracted game directory |
| `--map ID` | `116` | Starting map ID |
| `--mode MODE` | `coop` | Room mode: `coop` or `pvp` |
| `--tick-rate HZ` | `60` | Authoritative simulation tick rate |
| `--snap-rate HZ` | `30` | Snapshot broadcast rate |

## Running the Headless Combat PoC
```bash
ruby server/poc_headless.rb
```
