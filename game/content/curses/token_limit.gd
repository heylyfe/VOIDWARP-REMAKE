extends RefCounted
#
# token_limit.gd - script curse (DESIGN.md section 7.1 row "token_limit").
# Rule sentence (spec, verbatim): "plushies remove 20 agitation instead of 35 and spawn
# every 30 s".
# Counter-play: "route for plushies".
#
# Reading: Claude's own numbers are PLUSHIE_CALM 35.0 and PLUSHIE_INTERVAL_TICKS 1500
# (25 s) in content/enemies/claude/enemy.gd, and both live on the row: a pickup
# subtracts PLUSHIE_CALM from row["agitation"] (clamped at 0) and a placement re-arms
# row["plushie_cd"] to PLUSHIE_INTERVAL_TICKS. The curse therefore corrects the row
# after the behavior has run:
#   - a placement: row["plushie_cd"] is re-armed to 1800 ticks (30 s);
#   - a pickup: the agitation is recomputed from the value the curse saw at the end of
#     the previous tick, so the net removal is exactly 20 per plushie - the behavior's
#     own clamp at 0 would otherwise leave 15 agitation behind on a calm bar.
# Nothing else about Claude moves: the rise, the beat clock, the leash and the cap are
# his own.

const CURSE_ID := "token_limit"

const CLAUDE_ID := "claude"              # the enemy the curse attaches to
const PLUSHIE_CALM_BASE := 35.0          # Claude's own PLUSHIE_CALM (5.11)
const PLUSHIE_CALM_HELD := 20.0          # the rule sentence's 20
const PLUSHIE_INTERVAL_BASE_TICKS := 1500   # Claude's own 25 s (5.11)
const PLUSHIE_INTERVAL_HELD_TICKS := 1800   # the rule sentence's 30 s
const AGITATION_RISE_PER_S := 2.0        # Claude's own rise (5.11)
const AGITATION_MAX := 100.0             # Claude's own cap (5.11)

## Per-level scratch, keyed by the row index:
##   "tl_ag_<i>" the agitation seen at the end of the previous tick
##   "tl_n_<i>"  the plushie count then   "tl_place_<i>" the last placement tick then
const ST_KEY := "token_limit"


## Stacks the run holds; >= 1 while the curse is picked (max_stacks 1).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## Agitation a plushie removes: 20 while held, Claude's own 35 otherwise.
## Pure helper - the test target.
static func plushie_calm(state: Dictionary) -> float:
	if held_stacks(state) >= 1:
		return PLUSHIE_CALM_HELD
	return PLUSHIE_CALM_BASE


## Ticks between plushies: 1800 (30 s) while held, Claude's own 1500 (25 s) otherwise.
## Pure helper - the test target.
static func plushie_interval_ticks(state: Dictionary) -> int:
	if held_stacks(state) >= 1:
		return PLUSHIE_INTERVAL_HELD_TICKS
	return PLUSHIE_INTERVAL_BASE_TICKS


## on_tick: re-arm the plushie clock at 30 s and make each pickup remove exactly 20.
static func on_tick(state: Dictionary, api) -> void:
	if held_stacks(state) <= 0:
		return
	var rt = state.get("enemy_runtime")
	if rt == null:
		return
	var st: Dictionary = state.get("curse_st", {})
	for i in range(rt.enemies.size()):
		var row = rt.enemies[i]
		if str(row.get("id", "")) != CLAUDE_ID:
			continue
		var ag_key := "tl_ag_%d" % i
		var n_key := "tl_n_%d" % i
		var place_key := "tl_place_%d" % i
		var plushies: Array = row.get("plushies", [])
		var prev_ag := float(st.get(ag_key, float(row.get("agitation", 0.0))))
		var prev_n := int(st.get(n_key, plushies.size()))
		var prev_place := int(st.get(place_key, -1))
		var now_place := int(row.get("last_plushie_tick", -1))
		var spawned := 1 if now_place != prev_place else 0
		var picked := prev_n + spawned - plushies.size()
		if picked > 0:
			# the behavior already removed 35 per plushie (clamped at 0); recompute from
			# the previous tick's value so the net removal is exactly 20 per plushie
			var rise := AGITATION_RISE_PER_S / 60.0
			row["agitation"] = clampf(prev_ag + rise - PLUSHIE_CALM_HELD * float(picked),
					0.0, AGITATION_MAX)
		if spawned > 0:
			row["plushie_cd"] = PLUSHIE_INTERVAL_HELD_TICKS
		st[ag_key] = float(row.get("agitation", 0.0))
		st[n_key] = plushies.size()
		st[place_key] = now_place
