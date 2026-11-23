extends "res://sim/enemy_runtime.gd".EnemyBehavior
#
# claude behavior module - the CYCLE 7 REVAMP (track T4; D-T4-1..D-T4-8).
#
# The owner's words (CYCLE7_BRIEF.md T4, verbatim): "Claude enemy revamp (spawns 5-15 clawds, collect to calm,
# warning sounds at 1 and 2 min, insta-kill at 3 min)". "Claude does NOTHING by himself: no attack, no movement."
#
# So this module is a BODY and nothing else. The old musical kit (drums / strings / wind, the beat clock, the
# agitation meter, the clawd Crab plushies) is deleted, not disabled: a disabled attack that still runs its clock
# is a lie in the state hash. What the module still does:
#   - the 30-tick spawn fade (the anim block's `spawn` row: alpha 0 -> 1, scale 0.8 -> 1.0, and the body cannot
#     touch or kill until it completes), then the `idle` state forever;
#   - the body: 2.0 u tall, hit diameter 1.6 u (SR-2), contact kills (the framework's cylinder check, unchanged).
# It never moves, never telegraphs, never fires, never kills by its own action.
#
# THE SWARM AND THE TIMER ARE NOT HERE. They live in sim/clawds.gd (D-T4-2), because the anger timer must be in
# the state hash and enemy rows are not hashed. This module's job is to hand that module its numbers:
# `clawd_cfg()` returns the data block below, and app/world.gd / tools/bot_run.gd probe the voted roster modules
# for that method by name (the idiom extra_mines() already uses), so no content id is named outside content/.
#
# KILL TESTS RUN WITH LAST LIGHT ALREADY SPENT (D-057). No arbiter block: SR-4's scheduling gates are address
# me's and gin ichimaru's alone (D-067).

const RT := preload("res://sim/enemy_runtime.gd")

## Roster numbers (DESIGN.md section 5.11 / SR-2 / SR-5; mirrors enemy.json's stats - the test asserts the two
## agree). base_speed and pursuit_ceiling stay at their SR-5 table values because tools/check_enemy_data.gd
## compares the file to the table; the behavior simply never calls the float body, so they are inert data.
const BODY_HEIGHT := 2.0
const HIT_DIAMETER := 1.6          # SR-2's FINAL row (0.8 x the 2.0 u body width)
const BASE_SPEED := 4.0
const PURSUIT_CEILING := 0.55
const BURST_CEILING := 1.0
const MIN_LEVEL := 15
const MAX_VOTES := 1
const DEATH_CODE := "D-CLAUDE"     # DESIGN.md section 3.1 (FINAL); death.gd's map
const KILLER_ID := "Claude"        # the runtime derives "D-CLAUDE" from this too

## The spawn fade (the anim block's spawn row).
const SPAWN_FADE_TICKS := 30

## The clawd swarm + the anger timer (D-T4-3..D-T4-5). These are the numbers the sim module runs on; they mirror
## enemy.json's stats block and the test asserts the two agree.
const CLAWD_COUNT_MIN := 5
const CLAWD_COUNT_MAX := 15
const CLAWD_COUNT_BY_TILES := [
	{"tiles": 0, "count": 5}, {"tiles": 800, "count": 7}, {"tiles": 1100, "count": 10},
	{"tiles": 1400, "count": 12}, {"tiles": 1700, "count": 15},
]
const CLAWD_MIN_SPACING_TILES := 8
const CLAWD_PICKUP_RADIUS := 1.6   # the gift pickup radius (data/economy.json gold_phase.gift_pickup_radius)
const ANGER_WARNING_TICKS := [3600, 7200]   # 60 s and 120 s at the fixed 60 Hz tick
const ANGER_KILL_TICKS := 10800             # 180 s
const ANGER_PAUSE_WHEN_BEACON_OPEN := true
const CUE_WARNING_1 := "claude_warning_1"
const CUE_WARNING_2 := "claude_warning_2"


## The runtime cfg this enemy hands to EnemyRuntime.plan()/spawn_at(): the stats block of
## content/enemies/claude/enemy.json. Mirror - the test asserts the two agree.
static func cfg() -> Dictionary:
	return {
		"base_speed": BASE_SPEED,
		"pursuit_ceiling": PURSUIT_CEILING,
		"burst_ceiling": BURST_CEILING,
		"world_height": BODY_HEIGHT,
		"body_height": BODY_HEIGHT,
		"hit_diameter": HIT_DIAMETER,
		"preferred_kind": "open",
		"spawn_fade_ticks": SPAWN_FADE_TICKS,
		"contact_kill": true,
		"death_code": DEATH_CODE,
		"cycle_s": 0.0,
		"cycle_ticks": 0,
		"frame_w": 256,
		"frame_h": 256,
		"body_rect": [16, 16, 224, 224],   # the T-016 TBD sheet's tight body bbox
	}


## The clawd swarm + the anger timer data block (D-T4-2). app/world.gd and tools/bot_run.gd probe the voted
## roster modules for this method and hand the result to sim/clawds.gd's attach(); a module without it owns no
## swarm. Mirror of enemy.json's stats - the test asserts the two agree.
static func clawd_cfg() -> Dictionary:
	return {
		"count_min": CLAWD_COUNT_MIN,
		"count_max": CLAWD_COUNT_MAX,
		"count_by_tiles": CLAWD_COUNT_BY_TILES.duplicate(true),
		"min_spacing_tiles": CLAWD_MIN_SPACING_TILES,
		"pickup_radius": CLAWD_PICKUP_RADIUS,
		"warning_ticks": ANGER_WARNING_TICKS.duplicate(),
		"kill_ticks": ANGER_KILL_TICKS,
		"pause_when_beacon_open": ANGER_PAUSE_WHEN_BEACON_OPEN,
		"killer_id": KILLER_ID,
		"death_code": DEATH_CODE,
		"cues": [CUE_WARNING_1, CUE_WARNING_2],
	}


func _init() -> void:
	id = "claude"
	display_name = "Claude"


func on_spawn(row: Dictionary, _api) -> void:
	row["age"] = 0
	row["anim_state"] = "spawn"
	row["anim_state_t"] = 0
	# the spawn fade blocks contact (the anim block's spawn row): no body contact until the fade completes -
	# the framework reads row diameter_u, so zero it
	row["diameter_full"] = float(row["diameter_u"])
	row["diameter_u"] = 0.0


## One 60 Hz tick: the fade, then nothing. No movement, no attack, no clock (D-T4-1).
func tick(row: Dictionary, api, dt_ticks: int) -> void:
	for _i in range(maxi(dt_ticks, 0)):
		_tick_one(row, api)


func _tick_one(row: Dictionary, api) -> void:
	row["age"] = int(row["age"]) + 1
	# the anim block's spawn row blocks contact for its 30 ticks (the anim's own contact_blocked covers
	# ticks_in_state 0..29): the body returns at age 31
	if int(row["age"]) == SPAWN_FADE_TICKS + 1:
		row["diameter_u"] = float(row["diameter_full"])   # the fade is done: contact kills
	_pick_anim_state(row)


## Two states only: the spawn fade, then idle forever. The sheet's other seven states stay as dormant art data
## (D-T4-1) - nothing here can reach them.
func _pick_anim_state(row: Dictionary) -> void:
	var st := "spawn" if int(row["age"]) < SPAWN_FADE_TICKS else "idle"
	if st != str(row["anim_state"]):
		row["anim_state"] = st
		row["anim_state_t"] = 0
	else:
		row["anim_state_t"] = int(row["anim_state_t"]) + 1
