extends RefCounted
#
# sim/economy.gd - the gold-phase economy: purse, chain multiplier, overtime, stipend
# (DESIGN.md section 3.2; ticket T-022).
#
# Money is integer centi-gold (data/economy.json gold_arithmetic: unit centi_gold, rounding
# floor); every derived amount below floors once, so no amount drifts. The tunable numbers
# are read from data/economy.json through core/content_api.gd; the literals here are only
# same-value fallbacks used when no api is passed (a broken data file fails the boot check,
# it does not change prices at runtime silently).
#
# Economy upgrades reach this script as a stats Dictionary - the core/content_api.gd
# apply_modifiers() output over the owned upgrade stacks (ticket T-013): gold_value,
# chain_window, chain_cap, overtime_period, stipend_flat. A stat the caller leaves out
# keeps its StatsScript.DEFAULTS value, so zero owned upgrades is exactly the canon base.
#
# The chain multiplies what a gold gift pays: x1.00 at beacon open, +0.05 per gold gift
# collected within the chain window of the previous one, cap x2.00. It resets to x1.00 on
# exactly four events: the window missed (the automatic reset), a void fall, a defused or
# shielded tripmine, thicc ben's eject. break_chain(reason) refuses every other reason
# string - nothing outside the whitelist can reset the chain (test_economy.gd proves it).
#
# Pure sim layer (test_boundaries.gd): Array/Dictionary surface only, no clock - dt comes
# in through tick_gold(), and no content id is named anywhere; the stats dict carries the
# upgrade effects. The caller (T-023 wiring / T-026 bot) owns the call order:
#   beacon opens  -> begin_gold_phase()
#   every tick    -> tick_gold(dt); on gold pickups -> collect_gold_gift()
#   break events  -> break_chain(reason) with the reason string from the hazard code
#   beacon entry  -> enter_beacon(level) pays the stipend and ends the gold phase.

const StatsScript := preload("res://core/stats.gd")

const CENTI := 100                 # centi-gold per whole gold
const CHAIN_START_CENTI := 100     # x1.00
const CHAIN_INCREMENT_CENTI := 5   # +0.05 per in-window gold gift

## Canon chain-break reasons (data/economy.json gold_phase.chain.break_events is the
## data source; the missed window is the fourth, automatic reset).
const BREAK_MISSED_WINDOW := "missed_window"
const BREAK_VOID_FALL := "void_fall"
const BREAK_MINE_DEFUSED_OR_SHIELDED := "defused_or_shielded_tripmine"
const BREAK_THICC_BEN_EJECT := "thicc_ben_eject"


# --- tunables (data/economy.json values; canon same-value fallbacks) ---------------------

var base_gift_centi := 200        # gold gift base value 2.00 g
var window_s := 4.0               # chain window
var increment_centi := 5          # +0.05 per in-window gift
var cap_centi := 200              # chain cap x2.00
var overtime_period_s := 20.0     # one tier per 20 s of gold phase
var overtime_max_tier := 8
var overtime_speed_per_tier := 0.06
var overtime_cooldown_per_tier := 0.05
var stipend_base := 10
var stipend_per_level := 2

# --- stats-sourced upgrade effects (StatScript.DEFAULTS unless the caller overrides) ----

var gold_value_mul := 1.0
var stipend_flat_gold := 0

# --- live state ---------------------------------------------------------------------------

var purse_centi := 0
var chain_centi := CHAIN_START_CENTI
var since_gold := 0.0             # s since the last gold gift (or beacon open)
var gold_clock := 0.0             # s since beacon open
var overtime_clock := 0.0         # s accrued toward the next overtime tier
var overtime_tier := 0
var gold_phase := false
var chain_resets := 0             # every reset, with its reason
var last_reset := ""
var break_reasons: Array[String] = [
	BREAK_MISSED_WINDOW,
	BREAK_VOID_FALL,
	BREAK_MINE_DEFUSED_OR_SHIELDED,
	BREAK_THICC_BEN_EJECT,
]


## Factory. p_stats: apply_modifiers() output over the owned upgrade stacks (may be {}).
## p_api: the booted content api; its data/economy.json fills the tunables when given.
static func create(p_stats: Dictionary = {}, p_api: RefCounted = null) -> RefCounted:
	var e := new()
	e._load_data(p_api)
	e.window_s = float(p_stats.get("chain_window", e.window_s))
	e.cap_centi = to_centi(float(p_stats.get("chain_cap", float(e.cap_centi) / CENTI)))
	e.overtime_period_s = float(p_stats.get("overtime_period", e.overtime_period_s))
	e.stipend_flat_gold = int(p_stats.get("stipend_flat", e.stipend_flat_gold))
	e.gold_value_mul = float(p_stats.get("gold_value", e.gold_value_mul))
	return e


static func to_centi(p_gold: float) -> int:
	return int(floor(p_gold * CENTI))


func _load_data(p_api: RefCounted) -> void:
	if p_api == null:
		return
	var econ: Dictionary = p_api.data("economy")
	if econ.is_empty():
		return
	var gp: Dictionary = econ.get("gold_phase", {})
	base_gift_centi = to_centi(float(gp.get("gold_gift_base_value", 2.0)))
	var ch: Dictionary = gp.get("chain", {})
	window_s = float(ch.get("window_s", window_s))
	increment_centi = to_centi(float(ch.get("per_gift_increment", 0.05)))
	cap_centi = to_centi(float(ch.get("cap", 2.0)))
	break_reasons = [BREAK_MISSED_WINDOW]
	for raw in ch.get("break_events", []):
		var reason := str(raw)
		if not break_reasons.has(reason):
			break_reasons.append(reason)
	var ov: Dictionary = gp.get("overtime", {})
	overtime_period_s = float(ov.get("period_s", overtime_period_s))
	overtime_max_tier = int(ov.get("max_tier", overtime_max_tier))
	overtime_speed_per_tier = float(ov.get("enemy_speed_per_tier", overtime_speed_per_tier))
	overtime_cooldown_per_tier = float(ov.get("enemy_cooldown_per_tier", overtime_cooldown_per_tier))
	var st: Dictionary = gp.get("clear_stipend", {})
	stipend_base = int(st.get("base", stipend_base))
	stipend_per_level = int(st.get("per_level", stipend_per_level))


# --- gold phase ---------------------------------------------------------------------------

## Beacon opens: the gold phase starts, the chain is x1.00, overtime tier 0.
func begin_gold_phase() -> void:
	gold_phase = true
	gold_clock = 0.0
	since_gold = 0.0
	overtime_clock = 0.0
	overtime_tier = 0
	chain_centi = CHAIN_START_CENTI


## One fixed-dt tick of the gold phase. Returns the overtime tiers gained this tick.
## The chain window is checked here: past the window the chain resets (missed_window).
func tick_gold(dt: float) -> int:
	if not gold_phase:
		return 0
	gold_clock += dt
	since_gold += dt
	overtime_clock += dt
	if since_gold > window_s:
		_reset(BREAK_MISSED_WINDOW)
	var gained := 0
	while overtime_clock >= overtime_period_s and overtime_tier < overtime_max_tier:
		overtime_clock -= overtime_period_s
		overtime_tier += 1
		gained += 1
	if overtime_tier >= overtime_max_tier:
		overtime_clock = 0.0
	return gained


## A gold gift is collected. Pays floor(base x gold_value x chain) centi-gold (doubled on
## the final band while Last Call is held), then advances the chain by +0.05 capped at
## the cap - or repairs a window the ticks missed before this pickup. Returns the gain.
func collect_gold_gift(final_band: bool = false) -> int:
	if not gold_phase:
		return 0
	if since_gold > window_s:
		_reset(BREAK_MISSED_WINDOW)
	var value := int(floor(float(base_gift_centi) * gold_value_mul * float(chain_centi) / float(CHAIN_START_CENTI)))
	if final_band:
		value *= 2
	purse_centi += value
	chain_centi = mini(chain_centi + increment_centi, cap_centi)
	since_gold = 0.0
	return value


## A chain-break event is reported. ONLY the whitelisted canon reasons reset; any other
## string is refused (returns false), so a new hazard cannot silently weaken the economy.
func break_chain(reason: String) -> bool:
	if not break_reasons.has(reason):
		return false
	_reset(reason)
	return true


func _reset(reason: String) -> void:
	chain_centi = CHAIN_START_CENTI
	since_gold = 0.0
	chain_resets += 1
	last_reset = reason


## Beacon entered: pays the clear stipend 10 + 2 x level (+ stipend_flat) in whole gold,
## ends the gold phase (overtime resets next level when begin_gold_phase runs again).
func enter_beacon(p_level: int) -> int:
	gold_phase = false
	return add_gold(stipend_for(p_level) + stipend_flat_gold)


## Canon stipend formula; the instance method above adds the upgrade stat.
static func stipend_for(p_level: int) -> int:
	return 10 + 2 * p_level


# --- money --------------------------------------------------------------------------------

func purse_gold() -> int:
	return purse_centi / CENTI


## Adds p_gold whole gold (stipend, bounties); returns the purse after, in whole gold.
func add_gold(p_gold: int) -> int:
	purse_centi += p_gold * CENTI
	return purse_gold()


func can_afford_gold(p_gold: int) -> bool:
	return purse_centi >= p_gold * CENTI


## Spends p_gold whole gold when affordable; false (and no change) when not.
func spend_gold(p_gold: int) -> bool:
	if not can_afford_gold(p_gold):
		return false
	purse_centi -= p_gold * CENTI
	return true


# --- overtime (read by the enemy layer) ---------------------------------------------------

func enemy_speed_mul() -> float:
	return 1.0 + overtime_speed_per_tier * float(overtime_tier)


func enemy_cooldown_mul() -> float:
	return 1.0 - overtime_cooldown_per_tier * float(overtime_tier)


## HUD form: the chain as a plain multiplier, x1.00 .. x2.00.
func chain_display() -> float:
	return float(chain_centi) / float(CHAIN_START_CENTI)
