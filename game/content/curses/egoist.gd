extends RefCounted
#
# egoist.gd - script curse (ticket T-051; DESIGN.md section 7.1 row "egoist").
# Rule sentence (spec, verbatim): "+1 ball per burst per stack".

# Counter-play: "the volley gap (D-064): a burst arrives as volleys of <= 3 balls,
# 0.75 s (45 ticks - one full jump) apart, so each volley is cleared by its own
# jump (5.4)".
#
# Reading (recorded in DECISIONS.md): Isagi's burst assembly reads
# stats["volley_balls"] + stats["balls_per_stack"] * stats["egoist_stacks"], so the
# curse supplies the stacks: every tick each Isagi row's stats block gets
# "egoist_stacks" = the stacks this run holds. The ball count then rises by exactly
# +1 per stack, and the runtime's VolleyClock splits the larger burst through the
# SAME D-064 volley discipline (at most 3 per volley) - no behavior edit, the
# volley gap stays FINAL.

const CURSE_ID := "egoist"

const ISAGI_ID := "isagi"         # the enemy the curse attaches to (content names content)
const VOLLEY_BALLS_FALLBACK := 3  # Isagi's base burst (stats block fallback, same
                                  # default the behavior's _begin_burst reads)
const BALLS_PER_STACK := 1        # the rule sentence: +1 ball per burst per stack


## Stacks the run holds; >= 1 while the curse is picked (max_stacks 2).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## The row's stats block: the same dictionary Isagi's _stats(row) reads, found by
## the same shape rule the behaviors use (cfg["stats"] when the cfg nests it).
static func row_stats(row: Dictionary) -> Dictionary:
	var cfg: Dictionary = row.get("cfg", {})
	var st: Variant = cfg.get("stats", null)
	if st is Dictionary:
		return st
	return cfg


## Pure helper (test target): the burst size the row's Stats produce under s stacks.
static func burst_balls(st: Dictionary, s: int) -> int:
	return int(st.get("volley_balls", VOLLEY_BALLS_FALLBACK)) + BALLS_PER_STACK * maxi(s, 0)


## on_tick: keep every Isagi row's egoist_stacks equal to the run's held stacks.
## Writing only on change keeps the row dictionaries stable for the state hash.
static func on_tick(state: Dictionary, api) -> void:
	var s := held_stacks(state)
	if s <= 0:
		return
	var rt = state.get("enemy_runtime")
	if rt == null:
		return
	for row in rt.enemies:
		if str(row.get("id", "")) != ISAGI_ID:
			continue
		var st := row_stats(row)
		if int(st.get("egoist_stacks", 0)) != s:
			st["egoist_stacks"] = s
