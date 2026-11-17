#!/usr/bin/env python3
"""T-014b build script: writes game/content/upgrades/<id>.json (36 files),
game/data/upgrade_pools.json and game/data/economy.json from the DESIGN.md
section 8 table (verbatim names/prices/stacks/effects). Deterministic; re-runnable.
Paths are relative to the repo root; run from anywhere: python tickets/T-014b.build.py
"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UP_DIR = os.path.join(ROOT, "game", "content", "upgrades")
DATA_DIR = os.path.join(ROOT, "game", "data")

# id, name, tier, price, max_stacks, class_only, effect, modifiers, hooks, script
# modifiers use only the closed stat list named in DESIGN.md section 12
# (run_speed, void_charges_max, void_fall_charge_cost, defuse_chance, barrier_shields,
#  glitch_slow_mul, respawn_delay, respawn_invuln, pickup_radius, gold_value,
#  chain_window, chain_cap, stipend_flat, shop_price_mul, fog_density, fill_light_range,
#  enemy_speed_mul, telegraph_mul, overtime_period). Modifiers are PER STACK.
# script: true = effect is not fully expressible as modifiers/hooks and needs a handler.
U = [
 ("paycheck", "Paycheck", "T1", 40, 3, None, "+25 g on beacon entry per stack [CANON]",
  [{"stat": "stipend_flat", "op": "add", "value": 25}], [], False),
 ("more", "More", "T1", 50, 5, None, "+10% gift yield per stack [CANON]",
  [], ["on_gift_collected"], True),
 ("yearn_for_speed", "Yearn for Speed", "T1", 60, 4, None, "+10% run speed per stack (Athletic +15%) [CANON]",
  [{"stat": "run_speed", "op": "mul", "value": 1.10}], [], False),
 ("field_dressing", "Field Dressing", "T1", 45, 2, None, "once per level per stack, a void fall costs no charge",
  [], ["on_void_fall"], True),
 ("long_reach", "Long Reach", "T1", 60, 3, None, "pickup radius +40% per stack",
  [{"stat": "pickup_radius", "op": "mul", "value": 1.40}], [], False),
 ("radar_beacon", "Radar Module: Beacon", "T1", 40, 1, None, "HUD compass and distance to the beacon",
  [], [], True),
 ("radar_gifts", "Radar Module: Gifts", "T1", 70, 2, None, "arrow to the nearest real gift within 40 u (80 u at 2)",
  [], [], True),
 ("ledge_grace", "Ledge Grace", "T1", 50, 2, None, "coyote time +0.08 s per stack",
  [], [], True),
 ("brace", "Brace", "T1", 80, 3, None,
  "coil's shockwave push and ben's eject −30% per stack (push 8 → 5.6 → 3.9 → 2.7 u/s; eject 18 → 12.6 → 9.0 → 6.3 u/s) — the launch super-jump shrinks with it",
  [], [], True),
 ("sure_foot", "Sure Foot", "T1", 70, 2, None,
  "void-fall respawn delay −0.4 s per stack (0.8 → 0.4 → 0.0 s) and respawn invulnerability +1.0 s per stack (1.0 → 2.0 → 3.0 s)",
  [{"stat": "respawn_delay", "op": "add", "value": -0.4}, {"stat": "respawn_invuln", "op": "add", "value": 1.0}], [], False),
 ("gilded_touch", "Gilded Touch", "T2", 150, 3, None, "gold gift base value +1.00 g per stack",
  [{"stat": "gold_value", "op": "add", "value": 1.00}], [], False),
 ("hot_streak", "Hot Streak", "T2", 140, 2, None, "chain window +1.0 s per stack",
  [{"stat": "chain_window", "op": "add", "value": 1.0}], [], False),
 ("nest_egg", "Nest Egg", "T2", 160, 2, None, "on beacon entry gain 5% of unspent gold, max 30 g, per stack",
  [], ["on_beacon_enter"], True),
 ("bounty_hunter", "Bounty Hunter", "T2", 130, 1, None, "curse bounties +50%",
  [], ["on_curse_draw"], True),
 ("bargain", "Bargain", "T2", 120, 2, None, "shop prices −10% per stack",
  [{"stat": "shop_price_mul", "op": "mul", "value": 0.90}], [], False),
 ("spring_heels", "Spring Heels", "T2", 180, 2, None, "+1 air jump per stack at 80% jump height (Athletic: 104%)",
  [], [], True),
 ("featherfall", "Featherfall", "T2", 150, 1, None, "hold jump to cap fall speed at 6 u/s (Glider: +1.5 s glide energy instead)",
  [], [], True),
 ("quick_recovery", "Quick Recovery", "T2", 160, 2, None, "class ability cooldown −20% per stack (Athletic: +5% speed instead)",
  [], [], True),
 ("defuse_kit", "Defuse Kit", "T2", 200, 3, None,
  "+20% chance per stack that a tripmine defuses instead of killing (cap 60%); the roll is fixed per (seed, level, slot) — §3.3 [CANON]",
  [{"stat": "defuse_chance", "op": "add", "value": 0.20}], [], False),
 ("stand_fast", "Stand Fast", "T2", 170, 1, None,
  "the first chain-breaking event each level (void fall, defused or shielded tripmine, ben's eject) does not reset the chain",
  [], ["on_void_fall", "on_mine_defused", "on_barrier_absorbed"], True),
 ("insulation", "Insulation", "T2", 150, 1, None,
  "glitched floor slows 10% instead of 20% and no longer disables class abilities",
  [{"stat": "glitch_slow_mul", "op": "mul", "value": 0.5}], [], True),
 ("radar_threats", "Radar Module: Threats", "T2", 160, 1, None, "screen-edge markers for enemies within 30 u",
  [], [], True),
 ("straggler_scope", "Straggler Scope", "T2", 140, 1, None, "straggler beams start at the last 35% instead of 20%",
  [], [], True),
 ("early_warning", "Early Warning", "T2", 180, 2, None, "enemy telegraphs last 15% longer per stack",
  [{"stat": "telegraph_mul", "op": "mul", "value": 1.15}], [], False),
 ("subspacial_barrier", "Subspacial Barrier", "T3", 350, 1, None,
  "1 shield per level, restored on beacon entry: absorbs exactly one tripmine (checked after the defuse roll), consumed; tripmines only — nothing absorbs the nuke [CANON]",
  [{"stat": "barrier_shields", "op": "add", "value": 1}], [], False),
 ("radar_mines", "Radar Module: Mines", "T3", 300, 1, None, "disguised tripmines within 14 u get a pink outline through fog [CANON]",
  [], [], True),
 ("high_ceiling", "High Ceiling", "T3", 320, 1, None, "chain cap ×2.00 → ×2.50",
  [{"stat": "chain_cap", "op": "set", "value": 2.5}], [], False),
 ("last_call", "Last Call", "T3", 300, 1, None, "the final 20% of gold gifts in a level are worth double",
  [], ["on_gift_collected"], True),
 ("slipstream", "Slipstream", "T3", 300, 1, None, "+20% speed for 2.0 s after any gift pickup",
  [], ["on_gift_collected"], True),
 ("cold_blood", "Cold Blood", "T3", 280, 1, None, "overtime tiers rise every 30 s instead of 20 s (Long Night: 21 s instead of 14 s)",
  [], [], True),
 ("twin_dash", "Twin Dash", "T3", 340, 1, "dasher", "Dasher only: 2 dash charges",
  [], [], True),
 ("updraft", "Updraft", "T3", 340, 1, "glider", "Glider only: once per glide, press jump to rise 3 u (6 s cooldown)",
  [], [], True),
 ("marathon", "Marathon", "T3", 340, 1, "athletic", "Athletic only: +2 max stacks of Yearn for Speed",
  [], [], True),
 ("cartographer", "Cartographer", "T4", 600, 1, None, "minimap of every piece within 40 u of anywhere you have stood, with real gifts",
  [], [], True),
 ("skeleton_key", "Skeleton Key", "T4", 750, 1, None, "the beacon opens at 90% of real black gifts; the rest turn gold in place",
  [], ["on_beacon_open"], True),
 ("pocket_beacon", "Pocket Beacon", "T5", 1200, 1, None, "once per level: 3.0 s channel (must stand still) to teleport to the beacon dais",
  [], [], True),
]

# R4 addendum (owner-set): draw weight x2 for items the current class boosts.
CLASS_BOOST = {
    "yearn_for_speed": ["athletic"],
    "spring_heels": ["athletic"],
    "marathon": ["athletic"],
    "featherfall": ["glider"],
    "updraft": ["glider"],
    "quick_recovery": ["dasher", "glider"],
    "twin_dash": ["dasher"],
}

TIER_POOL_FROM = {"T1": 1, "T2": 4, "T3": 10, "T4": 18, "T5": 26}

def write_json(path, obj):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(obj, f, indent=2, ensure_ascii=False)
        f.write("\n")

def main():
    os.makedirs(UP_DIR, exist_ok=True)
    os.makedirs(DATA_DIR, exist_ok=True)

    for uid, name, tier, price, st, class_only, effect, mods, hooks, script in U:
        doc = {
            "id": uid,
            "name": name,
            "tier": tier,
            "price": price,
            "max_stacks": st,
            "class_only": class_only,
            "class_boost": CLASS_BOOST.get(uid, []),
            "effect": effect,
            "modifiers": mods,
            "hooks": hooks,
            "script": script,
        }
        write_json(os.path.join(UP_DIR, uid + ".json"), doc)

    table_order = [u[0] for u in U]
    t1 = [u[0] for u in U if u[2] == "T1"]
    t2 = [u[0] for u in U if u[2] == "T2"]
    t3 = [u[0] for u in U if u[2] == "T3"]
    t4 = [u[0] for u in U if u[2] == "T4"]
    t5 = [u[0] for u in U if u[2] == "T5"]
    brackets = [
        ("1", 1, 1, ["paycheck", "more", "yearn_for_speed"]),  # LEVEL-1 POOL [CANON]: exactly these three
        ("2-3", 2, 3, t1),
        ("4-9", 4, 9, t1 + t2),
        ("10-17", 10, 17, t1 + t2 + t3),
        ("18-25", 18, 25, t1 + t2 + t3 + t4),
        ("26+", 26, None, table_order),
    ]
    pools = {
        "_doc": ("Per-level upgrade pools (DESIGN.md section 8 [CANON]). The shop never shows the full catalog; "
                 "the game maps the player's level to the bracket whose [min_level, max_level] contains it "
                 "(max_level null = open-ended). Level 1 is exactly paycheck, more, yearn_for_speed; every later "
                 "bracket lists all upgrades whose tier has entered the pool (tier pool-from levels: T1 at 1, "
                 "T2 at 4, T3 at 10, T4 at 18, T5 at 26). An upgrade also needs tier min level <= level. "
                 "Draw: 3 distinct, not at max stacks, weighted x2 for items the current class boosts "
                 "(class_boost in each upgrade file), seeded; affordability filter price <= max(2 x purse, 80)."),
        "mode": "standard",
        "brackets": [
            {"bracket": label, "min_level": lo, "max_level": hi, "ids": ids}
            for (label, lo, hi, ids) in brackets
        ],
    }
    write_json(os.path.join(DATA_DIR, "upgrade_pools.json"), pools)

    income_rows = [
        (1, 40, 12, 52, 64, 64),
        (5, 56, 20, 74, 94, 394),
        (10, 76, 30, 99, 129, 969),
        (15, 96, 40, 121, 161, 1694),
        (20, 116, 50, 146, 196, 2589),
        (25, 136, 60, 171, 231, 3660),
        (30, 156, 70, 197, 267, 4900),
    ]
    economy = {
        "_doc": ("Every number in DESIGN.md section 3.2 (gold phase), section 7 system (curse economy) and "
                 "section 8 system (shop). Percentages are fractions (0.8 = 80%). Gold is counted in integer "
                 "centi-gold and rounds DOWN (R4 addendum). Stacked price = floor(price x 1.5^stacks) in whole "
                 "gold; stacked prices and bounties are whole-gold floors. A bounty = floor(base x (20 + level) / 20)."),
        "currency": "gold",
        "gold_arithmetic": {
            "unit": "centi_gold",
            "rounding": "floor",
            "stacked_price": "floor(price * 1.5^stacks)",
            "bounty": "floor(base * (20 + level) / 20)",
        },
        "gold_phase": {
            "gold_gift_base_value": 2.00,
            "chain": {
                "start": 1.00,
                "window_s": 4.0,
                "per_gift_increment": 0.05,
                "cap": 2.00,
                "break_events": ["void_fall", "defused_or_shielded_tripmine", "thicc_ben_eject"],
            },
            "overtime": {
                "start_tier": 0,
                "period_s": 20,
                "max_tier": 8,
                "enemy_speed_per_tier": 0.06,
                "enemy_cooldown_per_tier": 0.05,
                "resets_each_level": True,
            },
            "clear_stipend": {"base": 10, "per_level": 2, "formula": "10 + 2 * level"},
            "income_model_average_player": {
                "description": "collects 50% of gold at mean chain x1.4",
                "rows": [
                    {"level": lvl, "slots": slots, "stipend": stip, "gold_income_avg": gold,
                     "total_per_level": total, "cumulative": cum}
                    for (lvl, slots, stip, gold, total, cum) in income_rows
                ],
                "greedy_multiplier": 2.4,
            },
        },
        "curse_bay": {
            "offering_altars": 3,
            "tithe": {"base": 100, "per_tithe_paid_this_run": 75, "formula": "100 + 75 * tithes_paid_this_run"},
            "bounties": {
                "mild": 20,
                "harsh": 45,
                "brutal": 90,
                "level_scale": "floor(base * (20 + level) / 20)",
                "harshest_is_richest": True,
            },
            "free_rerolls_per_c_intermission": 1,
            "safety_rule": {"max_total_run_speed_reduction": 0.10},
        },
        "shop": {
            "upgrade_altars": 3,
            "sales_per_altar_per_visit": 1,
            "reroll_plinth": {"base": 15, "increment_per_use_that_visit": 15},
            "stacking": {"multiplier": 1.5, "round": "floor", "formula": "floor(price * 1.5^stacks)"},
            "affordability_filter": {
                "purse_multiplier": 2,
                "floor": 80,
                "formula": "price <= max(2 * purse, 80)",
                "min_offered": 3,
                "fill_with": "cheapest remaining pool items",
            },
            "draw": {
                "count": 3,
                "distinct": True,
                "exclude_max_stacks": True,
                "class_boost_weight": 2,
                "seeded": True,
            },
            "price_tiers": [
                {"tier": "T1", "price_min": 40, "price_max": 80, "pool_from": 1, "intent": "foundational; one per early shop"},
                {"tier": "T2", "price_min": 120, "price_max": 200, "pool_from": 4, "intent": "a real choice vs. two T1"},
                {"tier": "T3", "price_min": 280, "price_max": 400, "pool_from": 10, "intent": "build-defining"},
                {"tier": "T4", "price_min": 550, "price_max": 800, "pool_from": 18, "intent": "must be saved for (skip a shop)"},
                {"tier": "T5", "price_min": 1100, "price_max": 1500, "pool_from": 26, "intent": "run-warping; two acts of saving"},
            ],
            "economy_targets": {
                "avg_afford_at_least_one_offered_min": 0.80,
                "avg_afford_all_three_max": 0.30,
                "avg_purchases_per_run_to_level_30": {"min": 18, "max": 24},
                "cautious_purchases_per_run": {"min": 6, "max": 10},
            },
            "level_1_pool": ["paycheck", "more", "yearn_for_speed"],
        },
    }
    write_json(os.path.join(DATA_DIR, "economy.json"), economy)

if __name__ == "__main__":
    main()

