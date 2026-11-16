"""Generates game/tests/parity_cases.json for the GDScript terrain-port parity test.

Cases:
  - seeds 100..119 at level 1+(seed%30), players=1, extra_mines=0
  - seeds 200..209 at level 12, players=2, extra_mines=0
  - seeds 300..309 at level 20, players=1, extra_mines=6
  - the 16 pinned gallery (seed, level) pairs from terrain_ref/gallery.json, hashed with the
    LIVE voidgen.py (gallery.json itself is stale if voidgen.py was edited after the last
    gallery regeneration; the live oracle wins).

Each record: {"seed", "level", "players", "extra_mines", "hash"}
Run from the repo root:  python game/tools/make_parity_cases.py
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.abspath(os.path.join(HERE, "..", "..", "terrain_ref")))

import voidgen  # noqa: E402


def rec(seed, level, players, extra_mines):
    return {"seed": seed, "level": level, "players": players, "extra_mines": extra_mines,
            "hash": voidgen.level_hash(voidgen.generate(seed, level, players, extra_mines))}


def main():
    cases = []
    for seed in range(100, 120):
        cases.append(rec(seed, 1 + (seed % 30), 1, 0))
    for seed in range(200, 210):
        cases.append(rec(seed, 12, 2, 0))
    for seed in range(300, 310):
        cases.append(rec(seed, 20, 1, 6))
    gallery_path = os.path.abspath(os.path.join(HERE, "..", "..", "terrain_ref", "gallery.json"))
    with open(gallery_path, "r", newline="\n") as f:
        gallery = json.load(f)
    for g in gallery:
        cases.append(rec(int(g["seed"]), int(g["level"]), 1, 0))
    out = os.path.abspath(os.path.join(HERE, "..", "tests", "parity_cases.json"))
    with open(out, "w", newline="\n") as f:
        json.dump(cases, f, separators=(",", ":"))
    print("wrote %d cases to %s" % (len(cases), out))


if __name__ == "__main__":
    main()
