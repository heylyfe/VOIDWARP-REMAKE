#!/usr/bin/env python3
"""T-014b verifier. Proves against DESIGN.md itself (not against the build script):
  1. every row of the section 8 upgrade table has game/content/upgrades/<id>.json
     and name/tier/price/max_stacks/effect match the table verbatim;
  2. exactly 36 upgrade files exist, no extras;
  3. prices sit inside their tier's range; tier pool-from levels match section 8;
  4. data/upgrade_pools.json brackets: level 1 == exactly paycheck/more/yearn_for_speed;
     every later bracket == all upgrades whose tier has entered the pool;
  5. data/economy.json carries every number from section 3.2 (incl. the income-model
     table, parsed from DESIGN.md), section 7 system and section 8 system;
  6. all JSON files parse; ids in pools exist; no duplicates in any bracket.
Exit 0 = all checks pass. Prints a line per check group.
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESIGN = os.path.join(ROOT, "DESIGN.md")
UP_DIR = os.path.join(ROOT, "game", "content", "upgrades")
DATA_DIR = os.path.join(ROOT, "game", "data")

failures = []
def check(cond, msg):
    if cond:
        print("PASS  " + msg)
    else:
        failures.append(msg)
        print("FAIL  " + msg)

with open(DESIGN, encoding="utf-8") as f:
    text = f.read()

def section(text, start_marker, end_markers):
    i = text.index(start_marker)
    ends = [text.index(m, i) for m in end_markers if m in text[i:]]
    return text[i:min(ends) if ends else len(text)]

sec8 = section(text, "## 8. Upgrades", ["## 9. Progression"])
sec32 = section(text, "### 3.2 The gold phase", ["### 3.3"])
sec7 = section(text, "## 7. Curses", ["### 7.1"])

# --- parse the section 8 upgrade table (header: | id | name | tier | price | st | effect |)
lines = sec8.splitlines()
hdr = next(i for i, l in enumerate(lines) if l.strip().startswith("| id |"))
rows = []
for l in lines[hdr + 2:]:
    s = l.strip()
    if not s.startswith("|"):
        break
    cells = [c.strip() for c in s.strip().strip("|").split("|")]
    if len(cells) != 6:
        break
    uid, name, tier, price, st, effect = cells
    rows.append({"id": uid, "name": name, "tier": tier,
                 "price": int(price.replace(",", "")), "max_stacks": int(st), "effect": effect})
check(len(rows) == 36, f"section 8 table parsed: {len(rows)} rows (expected 36)")

# --- 1+2: files exist, fields equal, no extras
files = sorted(f for f in os.listdir(UP_DIR) if f.endswith(".json"))
check(len(files) == 36, f"exactly 36 upgrade files present: {len(files)}")
check(sorted(r["id"] for r in rows) == [f[:-5] for f in files], "every table row has a file and no file lacks a row")
for r in rows:
    p = os.path.join(UP_DIR, r["id"] + ".json")
    with open(p, encoding="utf-8") as f:
        d = json.load(f)
    ok = (d.get("name") == r["name"] and d.get("tier") == r["tier"]
          and d.get("price") == r["price"] and d.get("max_stacks") == r["max_stacks"]
          and d.get("effect") == r["effect"] and d.get("id") == r["id"])
    check(ok, f"{r['id']}: name/tier/price/max_stacks/effect equal the table")

# --- 3: prices inside tier range; tier pool-from levels (section 8 tier table)
TIER = {"T1": (40, 80, 1), "T2": (120, 200, 4), "T3": (280, 400, 10), "T4": (550, 800, 18), "T5": (1100, 1500, 26)}
for r in rows:
    lo, hi, pool_from = TIER[r["tier"]]
    check(lo <= r["price"] <= hi, f"{r['id']}: price {r['price']} within {r['tier']} range {lo}-{hi}")

with open(os.path.join(DATA_DIR, "economy.json"), encoding="utf-8") as f:
    econ = json.load(f)
eco_tiers = {t["tier"]: (t["price_min"], t["price_max"], t["pool_from"]) for t in econ["shop"]["price_tiers"]}
check(eco_tiers == TIER, "economy.json price_tiers (range + pool_from) equal the section 8 tier table")

# --- 4: upgrade pools
with open(os.path.join(DATA_DIR, "upgrade_pools.json"), encoding="utf-8") as f:
    pools = json.load(f)
brackets = {b["bracket"]: b for b in pools["brackets"]}
check(list(brackets) == ["1", "2-3", "4-9", "10-17", "18-25", "26+"], f"bracket set and order: {list(brackets)}")
check(brackets["1"]["ids"] == ["paycheck", "more", "yearn_for_speed"], "level 1 pool == exactly paycheck, more, yearn_for_speed [CANON]")
tier_entered = {"T1": 1, "T2": 4, "T3": 10, "T4": 18, "T5": 26}
for label in ["2-3", "4-9", "10-17", "18-25", "26+"]:
    b = brackets[label]
    expected = [r["id"] for r in rows if tier_entered[r["tier"]] <= b["min_level"]]
    check(b["ids"] == expected, f"bracket {label} == all upgrades whose tier entered by level {b['min_level']} ({len(expected)} ids)")
    check(len(set(b["ids"])) == len(b["ids"]), f"bracket {label}: no duplicate ids")
all_ids = {r["id"] for r in rows}
check(set(brackets["26+"]["ids"]) == all_ids and len(brackets["26+"]["ids"]) == 36, "26+ bracket == all 36 upgrades")
for label in brackets:
    check(set(brackets[label]["ids"]) <= all_ids, f"bracket {label}: every id exists")
check(brackets["26+"]["max_level"] is None, "26+ bracket is open-ended")

# --- 5a: economy.json — section 3.2 numbers
gp = econ["gold_phase"]
check(gp["gold_gift_base_value"] == 2.00, "gold gift base value == 2.00 g")
ch = gp["chain"]
check((ch["start"], ch["window_s"], ch["per_gift_increment"], ch["cap"]) == (1.00, 4.0, 0.05, 2.00),
      "chain: start 1.00, window 4.0 s, +0.05/gift, cap 2.00")
ot = gp["overtime"]
check((ot["start_tier"], ot["period_s"], ot["max_tier"], ot["enemy_speed_per_tier"], ot["enemy_cooldown_per_tier"])
      == (0, 20, 8, 0.06, 0.05), "overtime: tier 0 at open, every 20 s, max 8, +6% speed / -5% cooldown per tier")
st = gp["clear_stipend"]
check((st["base"], st["per_level"]) == (10, 2), "clear stipend == 10 + 2 x level")
check(gp["income_model_average_player"]["greedy_multiplier"] == 2.4, "greedy multiplier == ~2.4x")

# income-model table parsed from DESIGN.md section 3.2
lines = sec32.splitlines()
hdr = next(i for i, l in enumerate(lines) if l.strip().startswith("| level |"))
design_rows = []
for l in lines[hdr + 2:]:
    s = l.strip()
    if not s.startswith("|"):
        break
    cells = [c.strip() for c in s.strip().strip("|").split("|")]
    design_rows.append([int(c.replace(",", "")) for c in cells])
econ_rows = [[r["level"], r["slots"], r["stipend"], r["gold_income_avg"], r["total_per_level"], r["cumulative"]]
             for r in gp["income_model_average_player"]["rows"]]
check(design_rows == econ_rows, f"income model table matches DESIGN.md 3.2 ({len(design_rows)} rows)")

# --- 5b: economy.json — section 7 system numbers
cb = econ["curse_bay"]
check(cb["offering_altars"] == 3, "3 curse altars at C bays")
check((cb["tithe"]["base"], cb["tithe"]["per_tithe_paid_this_run"]) == (100, 75), "tithe == 100 + 75 x tithes paid this run")
check((cb["bounties"]["mild"], cb["bounties"]["harsh"], cb["bounties"]["brutal"]) == (20, 45, 90),
      "bounties: Mild 20 / Harsh 45 / Brutal 90 g")
check(cb["bounties"]["level_scale"] == "floor(base * (20 + level) / 20)", "bounty scales x (1 + level/20), floored whole gold")
check(cb["free_rerolls_per_c_intermission"] == 1, "one free reroll of the whole bay per C intermission")
check(cb["safety_rule"]["max_total_run_speed_reduction"] == 0.10, "curse safety rule: <= 10% total run-speed reduction")
# the same numbers as they appear in the section 7 prose
check("100 + 75" in sec7, "DESIGN.md section 7 tithe text present for cross-reference")
check("20 g, Harsh 45 g, Brutal 90 g" in sec7, "DESIGN.md section 7 bounty text present for cross-reference")

# --- 5c: economy.json — section 8 system numbers
sh = econ["shop"]
check(sh["upgrade_altars"] == 3, "3 upgrade altars (U and REST bays)")
check(sh["sales_per_altar_per_visit"] == 1, "each altar sells once per visit")
check((sh["reroll_plinth"]["base"], sh["reroll_plinth"]["increment_per_use_that_visit"]) == (15, 15),
      "reroll plinth 15 g (+15 g per use that visit)")
check((sh["stacking"]["multiplier"], sh["stacking"]["round"]) == (1.5, "floor"),
      "stacking price x1.5^stacks, rounded DOWN to whole gold")
check(econ["gold_arithmetic"] == {"unit": "centi_gold", "rounding": "floor",
                                  "stacked_price": "floor(price * 1.5^stacks)",
                                  "bounty": "floor(base * (20 + level) / 20)"},
      "gold arithmetic: integer centi-gold, rounds down (R4 addendum)")
af = sh["affordability_filter"]
check((af["purse_multiplier"], af["floor"]) == (2, 80), "affordability filter: price <= max(2 x purse, 80)")
check(sh["draw"]["count"] == 3 and sh["draw"]["class_boost_weight"] == 2 and sh["draw"]["distinct"] is True,
      "draw: 3 distinct, weighted x2 for class-boosted items")
et = sh["economy_targets"]
check(et["avg_afford_at_least_one_offered_min"] == 0.80, "target: avg player can afford >= 1 offered item in >= 80% of shops")
check(et["avg_afford_all_three_max"] == 0.30, "target: avg player can afford all 3 in <= 30% of shops")
check((et["avg_purchases_per_run_to_level_30"]["min"], et["avg_purchases_per_run_to_level_30"]["max"]) == (18, 24),
      "target: 18-24 avg purchases per run to level 30")
check((et["cautious_purchases_per_run"]["min"], et["cautious_purchases_per_run"]["max"]) == (6, 10),
      "target: cautious player 6-10 purchases per run")
check(sh["level_1_pool"] == ["paycheck", "more", "yearn_for_speed"], "level-1 pool [CANON] recorded in economy.json")

# --- 6: class boost map equals the R4 addendum; every file parses; class_only legal
ADDENDA_BOOST = {"yearn_for_speed": ["athletic"], "spring_heels": ["athletic"], "marathon": ["athletic"],
                 "featherfall": ["glider"], "updraft": ["glider"],
                 "quick_recovery": ["dasher", "glider"], "twin_dash": ["dasher"]}
CLASS_ONLY = {"twin_dash": "dasher", "updraft": "glider", "marathon": "athletic"}
for r in rows:
    p = os.path.join(UP_DIR, r["id"] + ".json")
    with open(p, encoding="utf-8") as f:
        d = json.load(f)
    check(d["class_boost"] == ADDENDA_BOOST.get(r["id"], []), f"{r['id']}: class_boost matches the R4 addendum")
    check(d["class_only"] == CLASS_ONLY.get(r["id"]), f"{r['id']}: class_only correct")

print()
if failures:
    print(f"VERIFY FAILED: {len(failures)} check(s) failed")
    sys.exit(1)
print("VERIFY OK: all checks passed")
sys.exit(0)



