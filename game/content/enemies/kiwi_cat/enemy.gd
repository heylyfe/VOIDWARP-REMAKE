extends RefCounted
#
# kiwi cat behavior module (ticket T-030; owner ruling 2026-11-17, D-KIWI-SLOW-1: the cat is
# SLOW - a lazy follower, not a predator; J6 owner ruling 2026-11-18: half again - 1.5 u/s,
# never dashes). The LEVEL-1 STARTER enemy: slowly follows the
# player; death on contact. Numbers (DESIGN.md section 5.1, FINAL via SR-2/SR-5; D-KIWI-SLOW-1;
# D-KIWI-J6-1):
#   - base pursuit speed 1.5 u/s (17% of run speed), pursuit ceiling 0.20 -> never above
#     1.8 u/s after ALL multipliers (SR-5; overflow becomes tempo, FloatBody's job);
#   - body 1.0 u tall, hit diameter 0.9 u (SR-2; hurdle-able - a jump clears its 1.5 u reach);
#   - feet ease toward the target's feet at 2.0 u/s (SR-1, NEVER multiplied);
#   - Contact = kill (the framework checks the cylinder every tick);
#   - meow every 3.0 s (180 ticks) while within 14 u - ENEMIES.md "cat meow when near player";
#   - the Zoomies burst does NOT exist for the cat: no multiplier ever makes it sprint or lunge
#     (J6). The behavior cancels any active burst on its FloatBody every tick, and the cfg
#     burst ceiling sits at the pursuit ceiling anyway (belt and braces).
#
# Content id lives here, never under sim/ (DESIGN.md section 12). The row dict is the only
# state; the behavior only touches its own row through the api. The frame/anim wiring lives
# in the view (game/view/kiwi_cat_view.gd) - sprites and billboarding are view-layer only.

const RT := preload("res://sim/enemy_runtime.gd")

## Roster numbers (DESIGN.md section 5.1 / SR-2 / SR-5; D-KIWI-SLOW-1 owner ruling 2026-11-17;
## J6 owner ruling 2026-11-18; the runtime constants match).
const BASE_SPEED := 1.5            # J6: twice as slow - a lazy follower, ~1/6 of base run speed
const PURSUIT_CEILING := 0.2       # SR-5: never above 1.8 u/s (0.20 x 9.0) after multipliers
const BURST_CEILING := 0.2         # J6: the Zoomies burst has NO effect on the cat; kept at the
                                   # pursuit ceiling so the data path can never bound a sprint
                                   # (the behavior cancels any active burst outright)
const BODY_HEIGHT := 1.0
const HIT_DIAMETER := 0.9
const CLIMB := 2.0                   # SR-1 vertical easing, u/s, never multiplied
const MEOW_PERIOD_TICKS := 180       # 3.0 s (binding, DESIGN.md section 5.1 + the T-083 anim block)
const MEOW_RANGE_U := 14.0
const MEOW_TICKS := 12               # the scale pulse spans the 12-tick cue
const MIN_LEVEL := 1
const MAX_VOTES := 4
const DEATH_CODE := "D-KIWI"         # DESIGN.md section 3.1 (FINAL)
const PREFERRED_KIND := "nook"


## The runtime cfg this enemy hands to EnemyRuntime.plan()/spawn_at(): everything the
## framework needs to place, size, move and kill-check the body. Mirror of enemy.json's
## stats block - the test asserts the two agree.
static func cfg() -> Dictionary:
	return {
		"base_speed": BASE_SPEED,
		"pursuit_ceiling": PURSUIT_CEILING,
		"burst_ceiling": BURST_CEILING,
		"climb_u_per_s": CLIMB,
		"world_height": BODY_HEIGHT,
		"body_height": BODY_HEIGHT,
		"hit_diameter": HIT_DIAMETER,
		"preferred_kind": PREFERRED_KIND,
		"meow_period_ticks": MEOW_PERIOD_TICKS,
		"meow_range_u": MEOW_RANGE_U,
		"meow_ticks": MEOW_TICKS,
		"contact_kill": true,
		"death_code": DEATH_CODE,
		"cycle_s": 0.0,
		"cycle_ticks": 0,
		"frame_w": 256,
		"frame_h": 256,
		"body_rect": [16, 16, 224, 224],   # the T-016 TBD sheet's tight body bbox
	}


## The behavior. Every tick: float at the nearest player (1.5 u/s, SR-5 ceiling via the
## runtime's FloatBody; any active Zoomies burst is cancelled first - J6: the cat never
## dashes), then the meow - one 12-tick "meow" telegraph every 180 ticks while
## the nearest player is within 14 u (D-T030-3/D-T030-5: the telegraph is the cue channel
## the view renders as the scale pulse and the audio layer renders as the meow; the
## zero-radius circle never registers as a targeted footprint for SR-4).
class KiwiCatBehavior:
	extends RT.EnemyBehavior

	func on_spawn(row: Dictionary, _api) -> void:
		# ticks until the next meow; 0 = the first tick in range meows at once (D-T030-5)
		row["meow_left"] = 0

	func tick(row: Dictionary, api, dt_ticks: int) -> void:
		var near: Dictionary = api.nearest_player(
				Vector3(float(row["x"]), float(row["y"]), float(row["z"])))
		if near.is_empty():
			return   # no players: the cat holds still
		var fb: Variant = row.get("float", null)
		if fb == null:
			fb = RT.FloatBody.from_cfg(row["cfg"])
			row["float"] = fb
		# J6: the Zoomies burst does not exist for the cat - cancel any active burst so no
		# curse (or test) can make it dash or lunge; it always rides the pursuit path
		fb.burst_ticks_left = 0
		fb.burst_mult = 1.0
		fb.step(row, api, dt_ticks, float(near["x"]), float(near["z"]))
		var dist := float(near["dist"])
		if dist <= MEOW_RANGE_U:
			var left := int(row.get("meow_left", 0)) - dt_ticks
			if left <= 0:
				api.telegraph("meow", {"shape": "circle", "cx": float(row["x"]),
						"cz": float(row["z"]), "r": 0.0}, MEOW_TICKS)
				left = MEOW_PERIOD_TICKS
			row["meow_left"] = left
		else:
			row["meow_left"] = 0   # re-arm: the first tick back in range meows at once

