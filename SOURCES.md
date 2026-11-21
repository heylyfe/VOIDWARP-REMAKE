# SOURCES

Where the game's non-generated assets come from. One row per asset, so anyone can trace an
image back to its origin and know what it may be used for. Per-enemy art keeps its own
`game/content/enemies/<id>/SOURCES.md`; this file covers everything else.

| asset | path | origin | licence / note |
|---|---|---|---|
| The Master (death-screen host) | `game/assets/characters/the_master.png` | The owner's supplied image (`the_master_cat.png`, a tabby cat in a white collar and a red striped tie), cropped to the bust and edge-faded to transparent by a scratch Godot script (2026-11-21) | Supplied by the owner for use in VOIDWARP RUN; no third-party licence recorded. Keep it out of any redistribution beyond the game until the owner confirms the rights |
| Class icons (dasher, glider, athletic) | `game/assets/icons/classes/<id>.png` | Rasterised at 256 px from the repo's own `docs/classes/<id>.svg` (`Image.load_svg_from_string` at 0.5x, blended onto the altar card colour #0D1229) | Project-made art, same terms as the SVGs |
