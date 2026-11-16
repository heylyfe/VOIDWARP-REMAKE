# VOIDWRAP RUN

A collectathon roguelite platformer: endless seeded levels of checkered causeways over a foggy void.
Collect every black gift to open the beacon — then leave safe, or linger for gold while the pressure
rises. You carry two void charges: a fall spends one, the beacon gives one back, and the third fall is
the end of the run. The world is serious. The enemies are not.

**VOIDWRAP RUN is a personal, non-commercial project — no money is involved, and it is not affiliated with, endorsed by, or connected to any person, brand, character, or IP referenced or depicted in the game.**

## Where things are

| file | what |
|---|---|
| `DECISIONS.md` | every significant decision with its why — read first |
| `TERRAIN_SPEC.md` / `TERRAIN_REF.md` | the terrain generator spec and its working reference |
| `DESIGN.md` | game design: loop, economy, enemies, curses, upgrades, lobby, architecture |
| `FLEET_PACK.md` | instructions and tickets for the multi-agent build run |
| `ENEMIES.md` | the fixed enemy roster and its hard rules (owner file) |
| `terrain_ref/` | Python reference generator + validator (stdlib only) |
| `game/` | the Godot 4.7.2 project |
| `game/data/` | tunable data (offering schedule, …) |
| `assets_src/enemies/` | drop the 17 enemy source images here, with the exact filenames from ENEMIES.md |
| `research/` | Nullscape wiki facts, the v1 retrospective |

## Quick start

```powershell
# engine: see tools/godot/README.md (portable Godot 4.7.2, not committed)
python terrain_ref\voidgen.py --seed 1 --level 1 --ascii      # look at a level
python terrain_ref\gallery.py --check                          # 16 pinned levels
python terrain_ref\validate.py --seeds 0:5000                  # all invariants, 5,000 seeds
python terrain_ref\render.py --seed 7 --level 30 --out terrain_ref\out\l30.png
```

Engine: Godot 4.7.2 (MIT). Language: GDScript. Ships as a native Windows executable.
