# Maruchi Headless Server (Cross-Platform: Linux & Windows)

Cross-platform authoritative headless RGSS2 server built on standard Ruby 3.2+ (runs identically on **Linux** and **Windows** with zero GUI, Wine, or Xvfb).

## Components

- `rgss2/ruby18_compat.rb` — Ruby 1.8.1 (RGSS2) to Ruby 3.x compatibility shims and Marshal UTF-8 string normalization.
- `rgss2/primitives.rb` — Exact RGSS2 binary Marshal `_load` / `_dump` implementations for `Table`, `Color`, `Tone`, plus `Rect` and `RGSSError`.
- `rgss2/rpg.rb` — Complete RMVX `RPG::*` data classes (headless-safe audio/BGM/SE).
- `rgss2/headless_stubs.rb` — Headless `Graphics`, programmatic `Input`, `Audio`, `Bitmap` (reads PNG IHDR dimensions when present), `Sprite`, `Viewport`, `Plane`, `Tilemap`, `Window`, `Win32API`, and `load_data` (with case-insensitive fallback for Linux).
- `rgss2/runtime.rb` — Boots the headless RGSS2 runtime directly from `game/Data/Scripts.rvdata.orig`.
- `poc_headless.rb` — Step 2 verification script: loads all 150 game scripts, all RMVX `.rvdata` databases, enters combat Map #116 (50 XAS enemies), and verifies virtual player movement, XAS weapon damage, and live enemy AI ticks.

## Running the Step 2 PoC

### Windows
```powershell
ruby server/poc_headless.rb
```

### Linux / WSL Ubuntu
```bash
# First time only (if Ruby is not installed):
sudo apt update && sudo apt install -y ruby

# Run the exact same headless PoC:
ruby server/poc_headless.rb
```
