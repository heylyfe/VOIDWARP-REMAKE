extends RefCounted
#
# litter.gd - script curse (ticket T-051; DESIGN.md section 7.1 row "litter").
# Rule sentence (spec, verbatim): "each cat is followed by a kitten (60% size,
# 2.4 u/s, kills on contact) 6 u behind".

# Counter-play: "a kitten's ceiling is 0.30 (2.7 u/s, SR-5) - it always trails its
# cat: hurdle cat then kitten in one rhythm, or kite them into a line and cross".
#
# Reading (recorded in DECISIONS.md, D-KIWI-SLOW-1 owner ruling 2026-11-17): the kitten is a real kiwi_cat row, spawned
# through api.spawn_enemy (guarded - a stubbed harness schedules it for the next
# tick instead of failing) with a scaled cfg: 60% of the cat's body, base 2.4 u/s,
# pursuit ceiling 0.30 (2.7 u/s, the counter-play's own number, SR-5), contact kill
# on, death code D-KIWI (it is still a cat). It is placed 6 u BEHIND its cat -
# farther from the nearest player along the cat->player line, so it always trails
# (the "kite them into a line and cross" geometry). One kitten per cat; the spawn
# marker lives in state["curse_st"], never a global. A kitten is never faster than
# its cat: 2.4 < 3.0 base, 2.7 < 3.6 cap.

const CURSE_ID := "litter"

const KIWI_ID := "kiwi_cat"       # the enemy the curse attaches to (content names content)
const KITTEN_SIZE := 0.6          # 60% of the cat's size (the rule sentence)
const KITTEN_SPEED := 2.4         # u/s (the rule sentence; D-KIWI-SLOW-1: 0.8x the cat's 3.0)
const KITTEN_CEILING := 0.30      # SR-5 pursuit ceiling, 2.7 u/s - never faster than its cat
const TRAIL_U := 6.0              # u behind the cat (the rule sentence)
const SPAWN_FADE_TICKS := 30      # the common fade (same anim spawn row, D-056)
const DEATH_CODE := "D-KIWI"      # a kitten is still a kiwi cat
const ST_KEY := "litter_kittens"  # per-level scratch: {cat row index: true}


## Stacks the run holds; >= 1 while the curse is picked (max_stacks 1).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## The kitten's cfg: the cat's cfg scaled to 60%, with the kitten's own speed,
## SR-5 ceiling and trail numbers. Pure helper - the test target.
static func kitten_cfg(cat_cfg: Dictionary) -> Dictionary:
	return {
		"base_speed": KITTEN_SPEED,
		"pursuit_ceiling": KITTEN_CEILING,
		"burst_ceiling": float(cat_cfg.get("burst_ceiling", 1.0)) * KITTEN_SIZE,
		"climb_u_per_s": float(cat_cfg.get("climb_u_per_s", 2.0)),
		"world_height": float(cat_cfg.get("world_height", 1.0)) * KITTEN_SIZE,
		"body_height": float(cat_cfg.get("body_height", 1.0)) * KITTEN_SIZE,
		"hit_diameter": float(cat_cfg.get("hit_diameter", 0.9)) * KITTEN_SIZE,
		"preferred_kind": str(cat_cfg.get("preferred_kind", "nook")),
		"meow_period_ticks": 0,           # kittens do not meow (ENEMIES.md: only the CAT meows)
		"meow_range_u": 0.0,
		"meow_ticks": 0,
		"contact_kill": true,             # "kills on contact" (the rule sentence)
		"death_code": DEATH_CODE,
		"cycle_s": 0.0,
		"cycle_ticks": 0,
		"frame_w": int(cat_cfg.get("frame_w", 256)),
		"frame_h": int(cat_cfg.get("frame_h", 256)),
		"body_rect": cat_cfg.get("body_rect", [16, 16, 224, 224]),
	}


## The trailing point: 6 u behind the cat on the cat->player line - the player side
## is "ahead", so the kitten sits on the cat's tail. Pure helper - the test target.
static func trail_point(cat: Dictionary, player: Dictionary) -> Vector3:
	var cx := float(cat.get("x", 0.0))
	var cz := float(cat.get("z", 0.0))
	if player.is_empty():
		return Vector3(cx, float(cat.get("y", 0.0)), cz)   # no player: sit on the cat
	var dx := cx - float(player.get("x", 0.0))
	var dz := cz - float(player.get("z", 0.0))
	var d := sqrt(dx * dx + dz * dz)
	if d <= 1e-6:
		return Vector3(cx, float(cat.get("y", 0.0)), cz)
	return Vector3(cx + dx / d * TRAIL_U, float(cat.get("y", 0.0)), cz + dz / d * TRAIL_U)


## on_tick: one kitten per cat, 6 u behind, spawned through api.spawn_enemy.
static func on_tick(state: Dictionary, api) -> void:
	if held_stacks(state) <= 0:
		return
	var rt = state.get("enemy_runtime")
	if rt == null:
		return
	var st: Dictionary = state.get("curse_st", {})
	var spawned: Dictionary = st.get(ST_KEY, {})
	for i in range(rt.enemies.size()):
		var row = rt.enemies[i]
		if str(row.get("id", "")) != KIWI_ID:
			continue
		var key := "%d" % i
		if spawned.has(key):
			continue
		var near: Dictionary = {}
		if api.has_method("nearest_player"):
			near = api.nearest_player(Vector3(float(row["x"]), float(row["y"]), float(row["z"])))
		var p := trail_point(row, near)
		var def: Dictionary = {
			"id": KIWI_ID, "name": "kitten", "copy_index": 0, "copies": 1,
			"x": p.x, "y": p.y, "z": p.z,
			"cfg": kitten_cfg(row.get("cfg", {})),
			"spawn_fade_ticks": SPAWN_FADE_TICKS,
		}
		if api.has_method("spawn_enemy"):
			spawned[key] = true
			api.spawn_enemy(def)
		# spawn_enemy missing (stub harness): stay unscheduled, retry next tick
	st[ST_KEY] = spawned
