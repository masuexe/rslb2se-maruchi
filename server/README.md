# Maruchi Headless Server (Cross-Platform: Linux & Windows)

Planned architecture (Step 2+):
- Runs a cross-platform Ruby headless RGSS2 runtime shim (`Table`, `Color`, `Tone`, `Rect`, `RPG::*`, and headless no-op rendering/audio stubs) that directly loads the original game's `Data/*.rvdata` and core gameplay/XAS scripts.
- Runs authoritative map/event/XAS/AI ticks without a GUI or display server on both Linux and Windows.
- Exposes TCP/UDP multiplayer rooms to Windows `Game.exe` clients.
