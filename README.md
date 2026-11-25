# rslb2se-maruchi

Online Co-op & PvP Multiplayer Mod for **RMzas&SMS_最终的战斗 2 Special Edition (v2.30)** (RPG Maker VX / RGSS2 + XAS).

## Current Release: `v0.1.0`

### Features
- **Cross-Platform Authoritative Headless Server (`server/`)** — Runs natively on **Linux** and **Windows** using Ruby 3.2+ with a headless RGSS2 runtime (no GUI, Wine, or Xvfb), reusing the original game scripts and `Data/*.rvdata`.
- **32-bit Native Network & Background 60fps DLL (`native/maruchi_net/`)** — Rust `maruchi_net.dll` performs non-blocking length-prefixed TCP I/O on a background OS thread and subclasses the RGSS Player window so unfocused clients keep running at 60fps with focus-gated input.
- **Authoritative Co-op & PvP Gameplay (`client/mods/`)**:
  - Smooth remote player interpolation, action poses, overhead name/HP bars, and top-right party HP/MP HUD.
  - Server-authoritative XAS projectiles (`Token_Bullet`), item drops, multi-player Anti-Lag, enemy AI/defeat/rewards, combat animations, damage popups, knockback, and SE/BGM sync.
  - Independent HP/MP, 5-second down/revive (4× faster when an ally stands nearby in Co-op), and live CO-OP ↔ PVP mode switching.
  - Party-wide map transfers, per-player same-map teleports, shared switches/variables/self-switches, synchronized NPC/event interaction (`REQ_INTERACT`), and host-driven cutscene dialogue & choices.
  - In-game **Multiplayer Lobby Menu (`F8`)**: switch between all 137 characters, warp party to featured or any map, toggle CO-OP/PVP, reconnect/disconnect.

---

## Player Quick Start (Release Patch)

1. Download and extract `rslb2se-maruchi-v0.1.0-client.zip` into your original v2.30 game directory (back up `Data/Scripts.rvdata` first).
2. Edit `maruchi.ini` in the game folder to set `host`, `port`, and `name`.
3. Launch `Game.exe`:
   - **`F7`** — Connect / Reconnect to server (or set `auto_join = 1` in `maruchi.ini`).
   - **`F8`** — Open / Close Multiplayer Lobby Menu (Character / Map / CO-OP or PVP).
   - **Confirm (`Z` / `Enter` / `Space`)** — Interact with NPCs, chests, and switches (synced via server).

---

## Hosting a Dedicated Server

See [server/README.md](server/README.md) for full Linux & Windows instructions. Quick command:

```bash
ruby server/server.rb --host 0.0.0.0 --port 27890 --map 116 --mode coop
```

---

## Developer Workflow

### Repository Layout
- `client/` — RGSS2 client scripts (**strictly Ruby 1.8.1 syntax**)
  - `loader.rb` — External script bootstrapper & file logger
  - `config.rb` — Config loader (`ENV` > `maruchi.ini` > defaults) & mod toggles
  - `core/net.rb` — `Win32API` bridge to `maruchi_net.dll`
  - `mods/` — Independent mods (`00_maruchi_banner.rb`, `05_background_run.rb`, `10_coop_mvp.rb`, `12_coop_menu.rb`)
- `native/maruchi_net/` — 32-bit Rust DLL (`i686-pc-windows-msvc`)
- `server/` — Cross-platform headless RGSS2 runtime & authoritative multiplayer server
- `shared/` — Wire protocol (`protocol.rb`, **strictly Ruby 1.8.1 & Ruby 3.x compatible**)
- `tools/` — Game extractor, `Scripts.rvdata` Marshal 4.8 injector, dev launcher, and release packager
- `maruchi.ini.example` — Player configuration template
- `.local/`, `game/`, `dist/`, `logs/` — Ignored by git

### Local Setup & Testing
1. Place the original v2.30 game zip in `.local/` and extract it:
   ```powershell
   python tools/extract_game.py
   ```
2. Inject the external script loader into `game/Data/Scripts.rvdata` (pristine backup stays at `game/Data/Scripts.rvdata.orig`):
   ```powershell
   python tools/rvdata_scripts.py inject
   ```
3. Start the headless server:
   ```powershell
   ruby server/server.rb --map 116 --mode coop
   ```
4. Launch 1 or 2 local game clients (auto-tiled side-by-side):
   ```powershell
   .\tools\dev_launch.ps1 -Count 2 -AutoJoin -DebugConsole
   ```
5. Build `v0.1.0` client & server release archives into `dist/`:
   ```powershell
   python tools/package_release.py
   ```
6. Restore pristine vanilla `Scripts.rvdata` at any time:
   ```powershell
   python tools/rvdata_scripts.py restore
   ```

---

## Known Limitations (`v0.1.0`)
- Mouse support QoL mod (`:mouse_support`) is planned for a future release.
- Switching characters resets vitals to full; full server-side inventory/equipment/save persistence is planned for `v0.2+`.
- Single-room server instance per process (multi-room lobby & in-game chat planned for `v0.2+`).
