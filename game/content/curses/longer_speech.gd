extends RefCounted
#
# longer_speech.gd - script curse (ticket T-051; DESIGN.md section 7.1 "longer_speech").
# Rule sentence (spec, verbatim): "you must hold still 2.5 s instead of 1.5 s".
# Counter-play: "stop sooner".
#
# Reading (recorded in DECISIONS.md): address_me's stillness gate fires inside the
# behavior at row["still_t"] >= 90 (STILL_TICKS, 1.5 s). The curse owns the longer
# requirement through a one-time debit, no behavior edit: when a stillness run
# begins (the row's visible counter climbs off 0) the curse debits the visible
# counter by DEBIT_TICKS = 60 once, so the visible counter stays DEBIT_TICKS behind
# TRUE stillness for the whole run. The behavior's 90-tick gate then passes exactly
# when true stillness has run 150 ticks (2.5 s); the debit re-arms when the run
# breaks (the behavior's own reset zeroes the visible counter). Either dispatch
# order lands the release within one tick of 150 true still ticks.

const CURSE_ID := "longer_speech"

const ADDRESS_ID := "address_me"  # the enemy the curse attaches to (content names content)
const BASE_STILL_TICKS := 90      # 1.5 s, the behavior's own gate (5.10)
const REQUIRED_STILL_TICKS := 150 # 2.5 s, the rule sentence
const DEBIT_TICKS := 60           # REQUIRED - BASE: the one-time debit per still run

## Per-level scratch: "lsp_applied_<row index>" -> 1 once the run's debit is taken;
## cleared when the visible counter reads 0 (run broken / episode over), so the
## next still run gets its own debit.
const ST_PREFIX := "lsp_applied_"


## Stacks the run holds; >= 1 while the curse is picked (max_stacks 1).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## Pure helper (test target): the visible counter that corresponds to a true
## stillness of t ticks under this curse - the behavior's gate reads the visible one.
static func visible_for(t: int) -> int:
	return maxi(t - DEBIT_TICKS, 0)


## on_tick: take the debit at each still run's start on every address_me row.
static func on_tick(state: Dictionary, api) -> void:
	if held_stacks(state) <= 0:
		return
	var rt = state.get("enemy_runtime")
	if rt == null:
		return
	var st: Dictionary = state.get("curse_st", {})
	for i in range(rt.enemies.size()):
		var row = rt.enemies[i]
		if str(row.get("id", "")) != ADDRESS_ID:
			continue
		var key := "%s%d" % [ST_PREFIX, i]
		var visible := int(row.get("still_t", 0))
		if visible <= 0:
			st[key] = 0    # run broken (the behavior's own reset): re-arm the debit
			continue
		if int(st.get(key, 0)) == 0:
			st[key] = 1
			row["still_t"] = maxi(visible - DEBIT_TICKS, 0)
