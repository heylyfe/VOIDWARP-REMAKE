extends RefCounted
#
# crescendo.gd - script curse (ticket T-051; DESIGN.md section 7.1 row "crescendo").
# Rule sentence (spec, verbatim): "agitation rises 3/s instead of 2/s".
# Counter-play: "plushies first".
#
# Reading (recorded in DECISIONS.md): Claude's behavior keeps its own base rise of
# 2/s (AGITATION_RISE_PER_S, _tick_agitation). The curse adds the missing third
# point per second itself, on the row, so the combined rate is exactly 3/s without
# a behavior edit: every tick each Claude row's agitation gains EXTRA_PER_S/60,
# still clamped at AGITATION_MAX (100, the Deadline) exactly as the base rise is.

const CURSE_ID := "crescendo"

const CLAUDE_ID := "claude"       # the enemy the curse attaches to (content names content)
const BASE_RISE_PER_S := 2.0      # the behavior's own rise (DESIGN.md 5.11)
const TOTAL_RISE_PER_S := 3.0     # the rule sentence's rate
const EXTRA_PER_S := 1.0          # TOTAL minus BASE - what this curse adds per second
const AGITATION_MAX := 100.0      # the Deadline ceiling, the same clamp as the base rise


## Stacks the run holds; >= 1 while the curse is picked (max_stacks 1).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## on_tick: every Claude row's agitation gains the extra third point per second.
static func on_tick(state: Dictionary, api) -> void:
	if held_stacks(state) <= 0:
		return
	var rt = state.get("enemy_runtime")
	if rt == null:
		return
	for row in rt.enemies:
		if str(row.get("id", "")) != CLAUDE_ID:
			continue
		apply_extra(row, dt_ticks_of(state))


## Pure helper (test target): one tick's extra rise, applied to a Claude row with
## the same clamp the base rise uses.
static func apply_extra(row: Dictionary, dt_ticks: int) -> void:
	var agi: float = float(row.get("agitation", 0.0))
	agi = minf(agi + EXTRA_PER_S / 60.0 * float(maxi(dt_ticks, 0)), AGITATION_MAX)
	row["agitation"] = agi


## The tick delta the caller's clock implies (1 tick = 1/60 s at the fixed 60 Hz sim
## rate). Kept pure so tests can drive several ticks at once.
static func dt_ticks_of(state: Dictionary) -> int:
	return 1


## The one-second bookkeeping the rule sentence pins: after 60 ticks the extra rise
## is exactly 1.0 agitation point, so base 2/s + curse = 3/s.
static func extra_after_ticks(ticks: int) -> float:
	return EXTRA_PER_S / 60.0 * float(ticks)
