#!/usr/bin/env python3
"""T-014a verifier: proves every DESIGN.md section 7 table row has a curse file
and that every numeric field equals the table. Stdlib only.

Usage: python tools/verify_curses.py   (exit 0 = all checks pass)
"""
import json, sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
design = (REPO / "DESIGN.md").read_text(encoding="utf-8")

sec71 = design.split("### 7.1 Enemy-linked (24)")[1].split("### 7.2")[0]
sec72 = design.split("### 7.2 General (22)")[1].split("## 8.")[0]

ENEMY_ID = {
    "kiwi cat": "kiwi_cat", "coil": "coil", "thicc ben": "thicc_ben",
    "Isagi": "isagi", "nuke": "nuke", "YOU?!": "you",
    "gift Larper": "gift_larper", "toucher": "toucher", "seal": "seal",
    "address me": "address_me", "Claude": "claude", "gin ichimaru": "gin_ichimaru",
}
SEV = {"M": "mild", "H": "harsh", "B": "brutal"}
# Curses whose rules are expressed as modifiers (the rest carry "script": true).
MODIFIER_IDS = {"thick_fog", "lights_out", "tarnish", "short_chain", "inflation",
                "brittle", "hungry_void", "weighed_down", "rush_hour", "long_night", "hasty"}

def rows(section):
    out = []
    for line in section.splitlines():
        line = line.strip()
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if cells[0] == "id" or set(cells[0]) <= set("- "):
            continue
        out.append(cells)
    return out

def expected(cells, linked):
    if linked:
        cid, name, needs, min_lvl, sev, st, rule, counter = cells
        req = ENEMY_ID[needs]
    else:
        cid, name, min_lvl, sev, st, rule, counter = cells
        req = None
    return {"id": cid, "name": name, "severity": SEV[sev], "min_level": int(min_lvl),
            "requires_enemy": req, "max_stacks": int(st), "rule": rule,
            "counter_play": counter}

failures = []
def check(cond, msg):
    if not cond:
        failures.append(msg)
        print("FAIL", msg)

table = [(c, True) for c in rows(sec71)] + [(c, False) for c in rows(sec72)]
check(len(table) == 46, f"table rows: expected 46, got {len(table)}")

curse_dir = REPO / "game" / "content" / "curses"
files = {p.stem: p for p in curse_dir.glob("*.json")}

for cells, linked in table:
    exp = expected(cells, linked)
    cid = exp["id"]
    path = files.get(cid)
    if path is None:
        failures.append(f"{cid}: missing file")
        print("FAIL missing", cid)
        continue
    try:
        got = json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:
        failures.append(f"{cid}: unreadable JSON ({e})")
        print("FAIL json", cid)
        continue
    for key in ("id", "name", "severity", "min_level", "requires_enemy",
                "max_stacks", "rule", "counter_play"):
        check(got.get(key) == exp[key], f"{cid}: {key} mismatch\n  table={exp[key]!r}\n  file ={got.get(key)!r}")
    mods = got.get("modifiers")
    check(isinstance(mods, list), f"{cid}: modifiers must be a list")
    if cid in MODIFIER_IDS:
        check(len(mods) > 0, f"{cid}: expected non-empty modifiers[]")
        check(not got.get("script"), f"{cid}: script flag set on a modifier curse")
    else:
        check(mods == [], f"{cid}: expected empty modifiers[]")
        check(got.get("script") is True, f"{cid}: expected \"script\": true")
    check(got.get("hooks") == [], f"{cid}: hooks must be [] (no .gd handlers yet)")

expected_ids = {expected(c, l)["id"] for c, l in table}
for stem in files:
    check(stem in expected_ids, f"{stem}: file with no table row")
check(len(files) == 46, f"file count: expected 46, got {len(files)}")

if failures:
    print(f"\nVERIFY FAILED: {len(failures)} problem(s)")
    sys.exit(1)
print(f"VERIFY OK: 46/46 curse files match DESIGN.md section 7.1 + 7.2 (names, severity, min_level, requires_enemy, max_stacks, rule, counter_play; modifiers xor script)")
