extends RefCounted
#
# overwound.gd - script curse (ticket T-051; DESIGN.md section 7.1 row "overwound").
# Rule sentence (spec, verbatim): "coil idle time 3.0 -> 2.0 s (then 1.5 s)".
# Counter-play: "leave the ring and be airborne or > 6 u away at landing (5.2);
# the shove decays over 0.5 s and never kills".
#
# Reading (the one coil's own code anticipated, D-T-031-12): coil's idle length is
# DATA - the behavior reads row cfg "idle_s" (fallback 3.0) when it enters idle, so
# the curse only writes that key. Stack 1 holds it at 2.0 s, stack 2 at 1.5 s (the
# sentence's parenthetical); the SR-3 copy stagger and every other segment stand
# untouched. Writes are idempotent (different value only), so the state hash stays
# stable and un-plotting the curse restores the cfg's own fallback reading.

const CURSE_ID := "overwound"

const COIL_ID := "coil"           # the enemy the curse attaches to (content names content)
const BASE_IDLE_S := 3.0          # coil's own idle (the cfg fallback the behavior reads)
const IDLE_S_STACK1 := 2.0        # stack 1: 3.0 -> 2.0 s (the rule sentence)
const IDLE_S_STACK2 := 1.5        # stack 2: "(then 1.5 s)" (the rule sentence)


## Stacks the run holds; >= 1 while the curse is picked (max_stacks 2).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## Pure helper (test target): the idle length a coil runs under s stacks.
static func idle_s_for(stacks: int) -> float:
	if stacks >= 2:
		return IDLE_S_STACK2
	if stacks == 1:
		return IDLE_S_STACK1
	return BASE_IDLE_S


## on_tick: keep every coil row's cfg idle_s at the stacks' idle length. Idempotent:
## written only when the stored value differs, so the state hash stays stable.
static func on_tick(state: Dictionary, api) -> void:
	var s := held_stacks(state)
	if s <= 0:
		return
	var rt = state.get("enemy_runtime")
	if rt == null:
		return
	var idle := idle_s_for(s)
	for row in rt.enemies:
		if str(row.get("id", "")) != COIL_ID:
			continue
		if not (row.get("cfg", {}) is Dictionary):
			row["cfg"] = {}
		if not float(row["cfg"].get("idle_s", BASE_IDLE_S)) == idle:
			row["cfg"]["idle_s"] = idle
