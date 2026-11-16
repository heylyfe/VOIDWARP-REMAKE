# Godot (portable)

- Tag: 4.7.2-stable
- Download URL: https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip
- Source release page: https://github.com/godotengine/godot/releases/tag/4.7.2-stable
- Build: standard (NOT the .NET/mono build), Windows 64-bit editor.

## Files

- `godot.exe` — the full editor binary. `--headless` works; when stdout is piped/redirected (e.g. CI, PowerShell pipes) it prints output and exits with the correct code.
- `godot_gui.exe` — identical copy of the full editor binary (kept under its original-style name).
- `godot_console.exe` — the official `*_win64_console.exe` wrapper. It attaches a console so output is visible in an interactive terminal. It must keep a `_console.exe`-style name: it locates the real editor by stripping `_console.exe` from its own filename, so it cannot be renamed to `godot.exe` (it fails with `Invalid wrapper executable name.`).

Note: as of Godot 4.x the `*_console.exe` asset is a thin wrapper around the main `*_win64.exe`, not a standalone full build. `godot.exe` therefore ships the full editor binary.

## Reproduce on a fresh machine (PowerShell)

```powershell
Invoke-WebRequest -Uri "https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip" -OutFile "tools\godot\Godot_v4.7.2-stable_win64.exe.zip"
Expand-Archive -Force "tools\godot\Godot_v4.7.2-stable_win64.exe.zip" "tools\godot"
Copy-Item "tools\godot\Godot_v4.7.2-stable_win64.exe" "tools\godot\godot_gui.exe" -Force; Copy-Item "tools\godot\godot_gui.exe" "tools\godot\godot.exe" -Force; Copy-Item "tools\godot\Godot_v4.7.2-stable_win64_console.exe" "tools\godot\godot_console.exe" -Force; Remove-Item "tools\godot\Godot_v4.7.2-stable_win64.exe*" -Force
```

Then verify:

```powershell
tools\godot\godot.exe --headless --version
```
