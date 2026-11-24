# rslb2se-maruchi

Online Co-op Multiplayer & Quality-of-Life Mod project for **RMzas&SMS_最终的战斗 2 Special Edition (v2.30)** (RPG Maker VX / RGSS2 + XAS).

## Architecture Goals

1. **Authoritative Cross-Platform Headless Server (`server/`)** — Runs on both **Linux** and **Windows** using a headless RGSS2 compatibility layer in standard Ruby, reusing the original `Data/*.rvdata` maps, events, XAS combat, and custom AI scripts.
2. **Modular Windows Game Client (`client/`)** — Injects a tiny external script loader into `game/Data/Scripts.rvdata`, allowing all co-op networking and QoL enhancements (such as mouse support) to live as clean, version-controlled `.rb` files outside RMVX Editor.

## Repository Layout

- `client/` — RGSS2 client-side scripts (**strictly Ruby 1.8.1 syntax**)
  - `loader.rb` — External script bootstrapper & logger
  - `config.rb` — Server connection and mod feature toggles
  - `core/` — Core client hooks & networking modules
  - `mods/` — Independent QoL & gameplay mods (e.g., mouse support)
- `server/` — Cross-platform headless server (Linux & Windows)
- `shared/` — Wire protocol & constants shared by client and server (**Ruby 1.8.1 compatible**)
- `tools/` — Extraction, `Scripts.rvdata` Marshal 4.8 tooling, and launch scripts
- `.local/` & `game/` — Ignored by git (original game archive and extracted game runtime)

## Quick Start (Dev Workflow)

1. Place the original v2.30 game zip in `.local/` and extract it:
   ```powershell
   python tools/extract_game.py
   ```
2. Inject the external script loader into `game/Data/Scripts.rvdata` (pristine original is preserved at `game/Data/Scripts.rvdata.orig`):
   ```powershell
   python tools/rvdata_scripts.py inject
   ```
3. Launch 1 or 2 game instances for testing:
   ```powershell
   .\tools\dev_launch.ps1 -Count 1 -DebugConsole
   .\tools\dev_launch.ps1 -Count 2 -DebugConsole
   ```
4. Check runtime logs in `logs/client_*.log`.
5. To revert `game/Data/Scripts.rvdata` back to pristine vanilla:
   ```powershell
   python tools/rvdata_scripts.py restore
   ```
