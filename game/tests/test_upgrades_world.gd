extends RefCounted
#
# UPGRADES WORLD-LEVEL test (headless) - W12-A: the 24 upgrades the coverage audit found
# proven only at module / partition level, each driven through world.build() + world.step()
# with an un-owned twin as the negative control (the twin is the SAME build minus the
# stacks; the file asserts the canon base on it, never the owned side alone).
#
# Method per id: build the owned world (1 stack; 2 where max_stacks allows) and the twin,
# step both through world.step(), measure the upgrade's OWN observable effect in each.
# The upgrade json/gd was read first; nothing here guesses.
#
# Outcome policy, stated up front: an upgrade that produces NO observable difference between
# owned and not-owned in the shipped path (world.build()/world.step(), or the lobby flow the
# world feeds) is reported as an INERT FINDING (printed, counted, listed in the report table)
# instead of getting a test that passes on nothing. The legs allowed to assert a difference
# are the ones whose wiring exists and runs today:
#   bargain             shop_price_mul reaches the lobby prices via world.run_ledger()
#   subspacial_barrier  barrier_shields reaches the live controller at build
#   bounty_hunter       on_curse_draw reaches the curse bays (world.run_ledger() -> dispatcher)
#   nest_egg            on_beacon_enter pays interest through world.step()'s beacon-enter path
#   skeleton_key        the skeleton_quota role reaches gifts.black_quota at LevelState build
#   slipstream          on_gift_collected boosts run_speed_mul for 120 controller steps
#   stand_fast          on_void_fall saves the first live-chain break (economy skips it)
#
# Every other leg measures the SAME thing in both worlds and reports equality as a finding.
# The control-side assertions (canon base) are real checks on the un-owned twin and fail if
# the base drifts; they are not filler. The control-side assertions never depend on the
# upgrade's wiring, so wiring one up later cannot turn this file red.
#
# Reconciliation note (W13-C): this audit was written BEFORE the W13 wiring landed
# (sim/upgrade_runtime.gd's hook dispatcher and the LevelState upgrade roles). The legs for
# bounty_hunter, nest_egg, skeleton_key, slipstream and stand_fast now ASSERT the wired
# effect (owned world shows it, un-owned twin does not); the remaining notes were re-evidenced
# against the CURRENT code - mostly: the sim consumers landed (W13-B) but no shipped call
# site arms them, and the radar / map / channel roles reach lstate.upgrades but nothing in
# the app path reads them.
#
# Measured through behaviour or live world state (economy payouts, gifts remaining, the
# chain after a fall, the built controller's fields), never by reading a modifier list.

const WorldScript := preload("res://app/world.gd")
const LobbySceneScript := preload("res://view/lobby/lobby_scene.gd")
const IntermissionScript := preload("res://sim/intermission.gd")
const UpgradeRuntimeScript := preload("res://sim/upgrade_runtime.gd")
const ContentApiScript := preload("res://core/content_api.gd")
const VoidRngScript := preload("res://terrain/void_rng.gd")

const SEED := 1
const LEVEL := 1
const SHOP_LOBBY := 1   # data/offering_schedule.json: lobby 1 lights a U bay
const C_LOBBY := 2      # data/offering_schedule.json: lobby 2 lights a C bay
const DT := 1.0 / 60.0

var _inert: Array[String] = []


func run() -> Array[String]:
	var f: Array[String] = []
	_leg_bargain(f)
	_leg_bounty_hunter(f)
	_leg_brace(f)
	_leg_cartographer(f)
	_leg_featherfall(f)
	_leg_last_call(f)
	_leg_ledge_grace(f)
	_leg_marathon(f)
	_leg_more(f)
	_leg_nest_egg(f)
	_leg_pocket_beacon(f)
	_leg_quick_recovery(f)
	_leg_radar_beacon(f)
	_leg_radar_gifts(f)
	_leg_radar_mines(f)
	_leg_radar_threats(f)
	_leg_skeleton_key(f)
	_leg_slipstream(f)
	_leg_spring_heels(f)
	_leg_stand_fast(f)
	_leg_straggler_scope(f)
	_leg_subspacial_barrier(f)
	_leg_twin_dash(f)
	_leg_updraft(f)
	_inert.sort()
	print("INERT FINDINGS (%d): %s" % [_inert.size(), ",".join(_inert)])
	return f


# ---- shared helpers ----------------------------------------------------------------------

func _build(stacks: Dictionary, p_class: String = "dasher", p_level: int = LEVEL,
		p_votes: Dictionary = {}):
	var world = WorldScript.new()
	var ledger := {
		"class": p_class, "votes": p_votes.duplicate(), "curses": {},
		"stacks": stacks.duplicate(),
		"purse": 500, "tithes": 0, "hunger": 0, "last_vote": "",
	}
	if not world.build(SEED, p_level, ledger):
		world.free()
		return null
	return world


func _drop(world) -> void:
	if world != null:
		world.teardown()
		world.free()


func _check(f: Array[String], ok: bool, msg: String) -> bool:
	if not ok:
		f.append(msg)
	return ok


func _note_inert(id: String, detail: String) -> void:
	_inert.append(id)
	print("INERT FINDING %s: %s" % [id, detail])


## The ledger the build carried must round-trip through the live run: the stacks dict is
## what the next lobby replays and what this level's build consumed. Asserting 0 on the
## twin side pins the un-owned shape; asserting n on the owned side pins stack repetition
## (an owned@2 build proves the count reaches the world, not just the id).
func _check_plumbing(f: Array[String], world, id: String, want: int) -> void:
	var st: Dictionary = world.run_ledger().get("stacks", {})
	_check(f, int(st.get(id, 0)) == want,
		"%s: the world's carried ledger shows %d stacks, want %d" % [id, int(st.get(id, 0)), want])


## First live mine slot in the level (skipping consumed), or -1. Used by the barrier leg.
func _live_mine_slot(world) -> int:
	var mines = world.lstate.mines
	if mines == null:
		return -1
	for slot in mines.ids:
		if not bool(mines.is_consumed(slot)):
			return int(slot)
	return -1


## A real gift slot id (real, uncollected), or -1.
func _a_gift_slot(world) -> int:
	var gifts = world.lstate.gifts
	if gifts == null:
		return -1
	for i in gifts.slots.size():
		if bool(gifts.is_real(i)) and not bool(gifts.collected(i)):
			return i
	return -1


## Collect real black-phase gift slots through the same public entry the tick path uses,
## until at most `rem_target` real gifts remain. Direct mutation of the world's own gifts
## object - the same standing the economy calls have in test_modifiers_applied.gd.
func _collect_until(gifts, rem_target: int) -> void:
	for i in gifts.slots.size():
		if int(gifts.remaining()) <= rem_target:
			return
		if bool(gifts.is_real(i)) and not bool(gifts.collected(i)):
			gifts.collect(i, 0, 0, [])


## The U + REST altar price total of a lobby built from p_world's run_ledger (the exact
## inflation-wiring pattern test_world_stat_wiring.gd proves). -1 on a build failure.
func _altar_total(p_world) -> int:
	var ledger: Dictionary = p_world.run_ledger()
	var scene = LobbySceneScript.new()
	if not scene.build(SEED, SHOP_LOBBY, ledger):
		scene.free()
		return -1
	var total := 0
	for bay in scene.lobby.bays:
		var kind := str(bay.get("kind", ""))
		if kind != "U" and kind != "REST":
			continue
		for altar in (bay.get("altars", []) as Array):
			total += int(altar.get("price", 0))
	scene.free()
	return total


# ---- bargain (T2, max 2): shop_price_mul 0.9 / stack, through the lobby the world feeds --

func _leg_bargain(f: Array[String]) -> void:
	var base = _build({})
	var one = _build({"bargain": 1})
	var two = _build({"bargain": 2})
	if base == null or one == null or two == null:
		_check(f, false, "bargain: a world failed to build")
		_drop(base)
		_drop(one)
		_drop(two)
		return
	_check_plumbing(f, base, "bargain", 0)
	_check_plumbing(f, one, "bargain", 1)
	_check_plumbing(f, two, "bargain", 2)
	var tb := _altar_total(base)
	var t1 := _altar_total(one)
	var t2 := _altar_total(two)
	if tb <= 0 or t1 <= 0 or t2 <= 0:
		f.append("bargain: no priced U / REST altar to compare (totals base %d owned1 %d owned2 %d)"
				% [tb, t1, t2])
	else:
		_check(f, t1 < tb,
			"bargain x1: the world computed stats priced the U / REST altars at %d, want less than the un-owned %d"
				% [t1, tb])
		_check(f, t2 < t1,
			"bargain x2: the world computed stats priced the U / REST altars at %d, want less than owned x1's %d (0.9 x 0.9 on the base)"
				% [t2, t1])
	_drop(base)
	_drop(one)
	_drop(two)


# ---- bounty_hunter (T2, max 1): curse bounties +50% - hook on_curse_draw -------------------

func _leg_bounty_hunter(f: Array[String]) -> void:
	var owned = _build({"bounty_hunter": 1})
	var base = _build({})
	if owned == null or base == null:
		_check(f, false, "bounty_hunter: a world failed to build")
		_drop(owned)
		_drop(base)
		return
	_check_plumbing(f, base, "bounty_hunter", 0)
	_check_plumbing(f, owned, "bounty_hunter", 1)
	# Control-side canon: a fresh world's economy sits at the carried purse, untouched.
	_check(f, int(base._economy.purse_centi) == 50000,
		"bounty_hunter: the un-owned run's purse moved before any gift (%d centi, want 50000)"
			% int(base._economy.purse_centi))
	# The curse draw is a LOBBY event (sim/intermission.gd), not a level one: the world's
	# part is the ledger it hands the lobby (run_ledger) and the module loader. Build the
	# lobby with the same create() arguments view/lobby/lobby_scene.gd build() passes, at
	# the first schedule level with a C bay, run the dispatcher's on_curse_draw entry with
	# the world's own loader, and compare the drawn bounties. A repeat call must not
	# compound (the lobby asks again after every select).
	var api: RefCounted = ContentApiScript.load()
	for pair in [[owned, "owned"], [base, "control"]]:
		var w = pair[0]
		var tag: String = pair[1]
		var ledger: Dictionary = w.run_ledger()
		var lb: RefCounted = IntermissionScript.create(api, C_LOBBY,
				int(ledger.get("purse", 0)), VoidRngScript.mix(SEED, 0x10B + C_LOBBY),
				ledger.get("votes", {}), ledger.get("curses", {}), ledger.get("stacks", {}),
				str(ledger.get("class", "")), int(ledger.get("tithes", 0)),
				int(ledger.get("hunger", 0)), str(ledger.get("last_vote", "")),
				ledger.get("stats", {}))
		var cbay: Dictionary = {}
		for bay in lb.bays:
			if str(bay.get("kind", "")) == "C":
				cbay = bay
		if cbay.is_empty():
			_check(f, false, "bounty_hunter: lobby %d drew no C bay for the %s world - fixture broken"
					% [C_LOBBY, tag])
			continue
		var raw: Array[int] = []
		for a in cbay["altars"]:
			raw.append(int(a.get("bounty", 0)))
		var any_bounty := false
		for r in raw:
			if r > 0:
				any_bounty = true
		_check(f, any_bounty,
			"bounty_hunter: the C bay drew no bounties (%s world) - the fixture proves nothing" % tag)
		UpgradeRuntimeScript.curse_draw(lb.bays, lb.upgrade_stacks,
				Callable(w, "_upgrade_module"), C_LOBBY)
		UpgradeRuntimeScript.curse_draw(lb.bays, lb.upgrade_stacks,
				Callable(w, "_upgrade_module"), C_LOBBY)
		for i in (cbay["altars"] as Array).size():
			var got := int(cbay["altars"][i].get("bounty", 0))
			if tag == "owned":
				var want := int(floor(float(raw[i]) * 1.5))
				_check(f, got == want,
					"bounty_hunter: altar %d shows bounty %d, want floor(%d x 1.5) = %d"
						% [i, got, raw[i], want])
			else:
				_check(f, got == raw[i],
					"bounty_hunter: the un-owned altar %d shows bounty %d, want the canon %d (no +50%%)"
						% [i, got, raw[i]])
	_drop(owned)
	_drop(base)


# ---- brace (T1, max 3): push / eject cut 30% / stack - no knockback stat exists ------------

func _leg_brace(f: Array[String]) -> void:
	var owned = _build({"brace": 1})
	var two = _build({"brace": 2})
	var base = _build({})
	if owned == null or two == null or base == null:
		_check(f, false, "brace: a world failed to build")
		_drop(owned)
		_drop(two)
		_drop(base)
		return
	_check_plumbing(f, base, "brace", 0)
	_check_plumbing(f, owned, "brace", 1)
	_check_plumbing(f, two, "brace", 2)
	# Control-side canon: no brace stat reaches the controller's base (canon: the push
	# strengths are the enemies' own content constants, 8.0 u/s and 18.0 u/s).
	_check(f, float(base.ctl.C["accel"]) > 0.0,
		"brace: the un-owned controller's data constants did not load (accel %.1f)"
			% float(base.ctl.C["accel"]))
	_note_inert("brace",
		"the knockback consumer (sim/controller.gd apply_push_dampening, the W13-B consumer) is never called by the world, so the landing push and the eject strength stay content constants with no owned-side multiplier (canon 8.0 / 18.0 u/s); stats carry no knockback stat (the closed list has none)")
	_drop(owned)
	_drop(two)
	_drop(base)


# ---- cartographer (T4, max 1): minimap of stood-on footprints + real gifts -------------------

func _leg_cartographer(f: Array[String]) -> void:
	var owned = _build({"cartographer": 1})
	var base = _build({})
	if owned == null or base == null:
		_check(f, false, "cartographer: a world failed to build")
		_drop(owned)
		_drop(base)
		return
	_check_plumbing(f, base, "cartographer", 0)
	_check_plumbing(f, owned, "cartographer", 1)
	# Control-side canon: an un-upgraded run never builds the scripted-upgrade engine.
	_check(f, base.lstate.upgrades == null,
		"cartographer: the un-owned level built a scripted-upgrade engine (want null)")
	# The roles wiring that DID land: the owned level carries the footprint_map role.
	_check(f, owned.lstate.upgrades != null and bool(owned.lstate.upgrades.has("footprint_map")),
		"cartographer: the owned level did not build the footprint_map role (lstate.upgrades is %s)"
			% str(owned.lstate.upgrades))
	for _i in range(30):
		base.step(DT)
		owned.step(DT)
	var visited: Dictionary = owned.lstate.upgrades.visited if owned.lstate.upgrades != null else {}
	var revealed_rows: Array = owned.lstate.upgrades.revealed(owned.lstate, 0) if owned.lstate.upgrades != null else []
	_note_inert("cartographer",
		"the roles wiring landed (lstate.upgrades non-null, has footprint_map) but no shipped call site ticks the engine: world.gd never calls lstate.upgrades.step_player (only sim.gd's replay path does), so the footprint memory stays empty (visited size %d) and revealed() returns %d rows; the HUD cartographer_map is not instantiated by hud.gd; 30 ticks stepped in both" % [visited.size(), revealed_rows.size()])
	_drop(owned)
	_drop(base)


# ---- featherfall (T2, max 1): hold jump to cap fall speed at 6 u/s ----------------------------

func _leg_featherfall(f: Array[String]) -> void:
	var owned = _build({"featherfall": 1})
	var base = _build({})
	if owned == null or base == null:
		_check(f, false, "featherfall: a world failed to build")
		_drop(owned)
		_drop(base)
		return
	_check_plumbing(f, base, "featherfall", 0)
	_check_plumbing(f, owned, "featherfall", 1)
	# Drop both bodies from the same height and track peak fall speed: the un-owned body
	# must blow through the 6 u/s band freely (canon: no cap).
	var min_b := 0.0
	var min_o := 0.0
	base.ctl.y = float(base.ctl.y) + 24.0
	base.ctl.vy = 0.0
	base.ctl.grounded = false
	owned.ctl.y = float(owned.ctl.y) + 24.0
	owned.ctl.vy = 0.0
	owned.ctl.grounded = false
	for _i in range(90):
		base.step(DT)
		owned.step(DT)
		min_b = minf(min_b, float(base.ctl.vy))
		min_o = minf(min_o, float(owned.ctl.vy))
	_check(f, min_b < -6.0,
		"featherfall: the un-owned body's fall speed only reached %.2f u/s - it must fall freely past the 6 u/s band" % min_b)
	_note_inert("featherfall",
		"no fall-speed cap is ever applied: sim/controller.gd apply_fall_cap (the W13-B consumer) is never called by the world, so terminal_fall stays the fixed 40 u/s data constant and nothing reads stacks['featherfall']; owned world peak fall %.2f u/s vs control %.2f u/s over 90 ticks from the same height"
			% [min_o, min_b])
	_drop(owned)
	_drop(base)


# ---- last_call (T3, max 1): the final 20% of gold gifts pay double -----------------------------

func _leg_last_call(f: Array[String]) -> void:
	var owned = _build({"last_call": 1})
	var base = _build({})
	if owned == null or base == null:
		_check(f, false, "last_call: a world failed to build")
		_drop(owned)
		_drop(base)
		return
	_check_plumbing(f, base, "last_call", 0)
	_check_plumbing(f, owned, "last_call", 1)
	var eb: RefCounted = base._economy
	var eo: RefCounted = owned._economy
	eb.begin_gold_phase()
	eo.begin_gold_phase()
	var vb := int(eb.collect_gold_gift())
	var vo := int(eo.collect_gold_gift())
	_check(f, vb == 200,
		"last_call: the un-owned gold gift paid %d centi, want the canon 200 (2.00 g at chain x1.00)" % vb)
	_note_inert("last_call",
		"world.gd's _economy_pass calls collect_gold_gift() with no arguments, so the doubling band never applies: owned world paid %d centi on the same first gift vs control %d centi; content/upgrades/last_call.gd is_final_band and sim/economy.gd's final_band parameter have no shipped caller"
			% [vo, vb])
	_drop(owned)
	_drop(base)


# ---- ledge_grace (T1, max 2): coyote time +0.08 s / stack --------------------------------------

func _leg_ledge_grace(f: Array[String]) -> void:
	var owned = _build({"ledge_grace": 1})
	var two = _build({"ledge_grace": 2})
	var base = _build({})
	if owned == null or two == null or base == null:
		_check(f, false, "ledge_grace: a world failed to build")
		_drop(owned)
		_drop(two)
		_drop(base)
		return
	_check_plumbing(f, base, "ledge_grace", 0)
	_check_plumbing(f, owned, "ledge_grace", 1)
	_check_plumbing(f, two, "ledge_grace", 2)
	# Control-side canon: the data constant, not a per-stack one.
	_check(f, is_equal_approx(float(base.ctl.C["coyote_time"]), 0.10),
		"ledge_grace: the un-owned coyote window reads %.3f s, want the data 0.10 s"
			% float(base.ctl.C["coyote_time"]))
	_note_inert("ledge_grace",
		"coyote_time stays the data 0.10 s in both: sim/controller.gd apply_coyote_bonus (the W13-B consumer) is never called by the world, so no stack offsets the window; owned reads %.3f s, owned x2 reads %.3f s, control %.3f s"
			% [float(owned.ctl.C["coyote_time"]), float(two.ctl.C["coyote_time"]),
				float(base.ctl.C["coyote_time"])])
	_drop(owned)
	_drop(two)
	_drop(base)


# ---- marathon (T3, max 1, athletic): +2 max stacks of yearn_for_speed --------------------------

func _leg_marathon(f: Array[String]) -> void:
	var owned = _build({"marathon": 1}, "athletic")
	var base = _build({}, "athletic")
	if owned == null or base == null:
		_check(f, false, "marathon: a world failed to build")
		_drop(owned)
		_drop(base)
		return
	_check_plumbing(f, base, "marathon", 0)
	_check_plumbing(f, owned, "marathon", 1)
	# Control-side canon: no max-stacks bonus exists in the un-owned athletic run.
	_check(f, not bool(base.run_ledger().get("stacks", {}).has("marathon")),
		"marathon: the un-owned athletic ledger unexpectedly shows marathon owned")
	for _i in range(10):
		base.step(DT)
		owned.step(DT)
	_note_inert("marathon",
		"max_bonus() has no shipped caller: every IntermissionScript.create site (lobby_scene.build, world._resolve_run's replay, app's pre-run lobby) runs without p_max_stacks_bonus, and no app/ or sim/ path reads stacks['marathon']; the shop draw is unaffected in either world")
	_drop(owned)
	_drop(base)


# ---- more (T1, max 5): +10% gift yield / stack -------------------------------------------------

func _leg_more(f: Array[String]) -> void:
	var owned = _build({"more": 1})
	var two = _build({"more": 2})
	var base = _build({})
	if owned == null or two == null or base == null:
		_check(f, false, "more: a world failed to build")
		_drop(owned)
		_drop(two)
		_drop(base)
		return
	_check_plumbing(f, base, "more", 0)
	_check_plumbing(f, owned, "more", 1)
	_check_plumbing(f, two, "more", 2)
	var eb: RefCounted = base._economy
	var eo: RefCounted = owned._economy
	eb.begin_gold_phase()
	eo.begin_gold_phase()
	var vb := int(eb.collect_gold_gift())
	var vo := int(eo.collect_gold_gift())
	_check(f, vb == 200,
		"more: the un-owned gold gift paid %d centi, want the canon 200 (2.00 g at chain x1.00)" % vb)
	_note_inert("more",
		"the gift-yield consumer (sim/economy.gd apply_gift_yield, the W13-B consumer) is never called by the world, so the payout stays floor(base x gold_value x chain) with no stack term: owned paid %d centi on the same first gift vs control %d centi - identical"
			% [vo, vb])
	_drop(owned)
	_drop(two)
	_drop(base)


# ---- nest_egg (T2, max 2): on beacon entry gain 5% of unspent gold (cap 30 g) / stack ---------

func _leg_nest_egg(f: Array[String]) -> void:
	var owned = _build({"nest_egg": 1})
	var two = _build({"nest_egg": 2})
	var base = _build({})
	if owned == null or two == null or base == null:
		_check(f, false, "nest_egg: a world failed to build")
		_drop(owned)
		_drop(two)
		_drop(base)
		return
	_check_plumbing(f, base, "nest_egg", 0)
	_check_plumbing(f, owned, "nest_egg", 1)
	_check_plumbing(f, two, "nest_egg", 2)
	var deltas: Array[int] = []
	for w in [base, owned, two]:
		var e: RefCounted = w._economy
		e.purse_centi = 50000
		var b: RefCounted = w.lstate.beacon
		b.open(int(w.lstate.tick))
		w.ctl.x = float(b.cx)
		w.ctl.y = float(b.base_y)
		w.ctl.z = float(b.cz)
		w.ctl.grounded = true
		w.ctl.vy = 0.0
		w.step(DT)
		deltas.append(int(e.purse_centi) - 50000)
	_check(f, bool(base.lstate.beacon.completed),
		"nest_egg: the un-owned beacon was not entered - the fixture proves nothing")
	_check(f, bool(owned.lstate.beacon.completed),
		"nest_egg: the owned beacon was not entered through world.step()")
	_check(f, bool(two.lstate.beacon.completed),
		"nest_egg: the owned x2 beacon was not entered through world.step()")
	_check(f, deltas[0] == 1200,
		"nest_egg: beacon entry paid %d centi, want the canon 1200 (12 g for level 1; no interest in the un-owned run)"
			% deltas[0])
	var per := mini(50000 * 5 / 100, 3000)
	_check(f, deltas[1] == 1200 + per,
		"nest_egg: beacon entry paid %d centi, want stipend 1200 + interest %d (5%% of 500 g, capped at 30 g, one stack)"
			% [deltas[1], per])
	_check(f, deltas[2] == 1200 + 2 * per,
		"nest_egg: beacon entry paid %d centi, want stipend 1200 + interest %d x2 (5%% of 500 g per stack, capped at 30 g)"
			% [deltas[2], per])
	_drop(owned)
	_drop(two)
	_drop(base)


# ---- pocket_beacon (T5, max 1): 180-tick stand-still channel to the dais, once per level -------

func _leg_pocket_beacon(f: Array[String]) -> void:
	var owned = _build({"pocket_beacon": 1})
	var base = _build({})
	if owned == null or base == null:
		_check(f, false, "pocket_beacon: a world failed to build")
		_drop(owned)
		_drop(base)
		return
	_check_plumbing(f, base, "pocket_beacon", 0)
	_check_plumbing(f, owned, "pocket_beacon", 1)
	# Control-side canon: an un-upgraded run never builds the scripted-upgrade engine.
	_check(f, base.lstate.upgrades == null,
		"pocket_beacon: the un-owned level built a scripted-upgrade engine (want null)")
	# The roles wiring that DID land: the owned level carries the beacon_channel role.
	_check(f, owned.lstate.upgrades != null and bool(owned.lstate.upgrades.has("beacon_channel")),
		"pocket_beacon: the owned level did not build the beacon_channel role (lstate.upgrades is %s)"
			% str(owned.lstate.upgrades))
	var b: RefCounted = base.lstate.beacon
	var sx := float(base.ctl.x)
	var sz := float(base.ctl.z)
	var far := (float(b.cx) - sx) * (float(b.cx) - sx) + (float(b.cz) - sz) * (float(b.cz) - sz) > 4.0
	for _i in range(30):
		base.step(DT)
		owned.step(DT)
	if far:
		_check(f, is_equal_approx(float(base.ctl.x), sx) and is_equal_approx(float(base.ctl.z), sz),
			"pocket_beacon: the un-owned body moved during 30 idle ticks - expected a stand-still spawn (no channel exists un-owned)")
	var channels: Dictionary = owned.lstate.upgrades.channels if owned.lstate.upgrades != null else {}
	_note_inert("pocket_beacon",
		"the roles wiring landed (lstate.upgrades non-null, has beacon_channel) but no shipped call site ticks the channel: world.gd never calls lstate.upgrades.step_player (only sim.gd's replay path does), so the INTERACT edge never starts the 180-tick channel in the app path (channels held %d, used %s); the owned body stayed at (%.2f, %.2f), spawn at (%.2f, %.2f), beacon at (%.1f, %.1f) - no teleport exists"
			% [channels.size(), str(owned.lstate.upgrades.channel_used if owned.lstate.upgrades != null else {}),
				float(owned.ctl.x), float(owned.ctl.z), sx, sz, float(b.cx), float(b.cz)])
	_drop(owned)
	_drop(base)


# ---- quick_recovery (T2, max 2): class ability cooldown -20% / stack --------------------------

func _leg_quick_recovery(f: Array[String]) -> void:
	var owned = _build({"quick_recovery": 1})
	var two = _build({"quick_recovery": 2})
	var base = _build({})
	if owned == null or two == null or base == null:
		_check(f, false, "quick_recovery: a world failed to build")
		_drop(owned)
		_drop(two)
		_drop(base)
		return
	_check_plumbing(f, base, "quick_recovery", 0)
	_check_plumbing(f, owned, "quick_recovery", 1)
	_check_plumbing(f, two, "quick_recovery", 2)
	# Control-side canon: the data constant, untouched by any stack.
	_check(f, is_equal_approx(float(base.ctl.C["dash_regen"]), 3.0),
		"quick_recovery: the un-owned dash regen reads %.2f s, want the data 3.0 s"
			% float(base.ctl.C["dash_regen"]))
	_note_inert("quick_recovery",
		"the cooldown consumer (sim/controller.gd apply_cooldown_reduction / apply_speed_upgrade, the W13-B consumer) is never called by the world, so dash regen stays the fixed data value 3.0 s and nothing reads the stacks: owned reads %.2f s, owned x2 reads %.2f s, control %.2f s"
			% [float(owned.ctl.C["dash_regen"]), float(two.ctl.C["dash_regen"]),
				float(base.ctl.C["dash_regen"])])
	_drop(owned)
	_drop(two)
	_drop(base)


# ---- radar_beacon (T1, max 1): compass heading and distance to the dais ------------------------

func _leg_radar_beacon(f: Array[String]) -> void:
	var owned = _build({"radar_beacon": 1})
	var base = _build({})
	if owned == null or base == null:
		_check(f, false, "radar_beacon: a world failed to build")
		_drop(owned)
		_drop(base)
		return
	_check_plumbing(f, base, "radar_beacon", 0)
	_check_plumbing(f, owned, "radar_beacon", 1)
	_check(f, base.lstate.upgrades == null,
		"radar_beacon: the un-owned level built a scripted-upgrade engine (want null)")
	# The roles wiring that DID land: the owned level carries the beacon_compass role.
	_check(f, owned.lstate.upgrades != null and bool(owned.lstate.upgrades.has("beacon_compass")),
		"radar_beacon: the owned level did not build the beacon_compass role (lstate.upgrades is %s)"
			% str(owned.lstate.upgrades))
	_note_inert("radar_beacon",
		"the roles wiring landed (lstate.upgrades non-null, has beacon_compass) but nothing in the shipped path reads it: sim/upgrades.gd beacon_compass() has no app/ caller, hud.gd builds no compass entry (the radar_arrows widget exists but is never instantiated), so the heading never reaches the screen")
	_drop(owned)
	_drop(base)


# ---- radar_gifts (T1, max 2): arrow to the nearest real gift within 40 u (80 u at 2) -----------

func _leg_radar_gifts(f: Array[String]) -> void:
	var owned = _build({"radar_gifts": 1})
	var two = _build({"radar_gifts": 2})
	var base = _build({})
	if owned == null or two == null or base == null:
		_check(f, false, "radar_gifts: a world failed to build")
		_drop(owned)
		_drop(two)
		_drop(base)
		return
	_check_plumbing(f, base, "radar_gifts", 0)
	_check_plumbing(f, owned, "radar_gifts", 1)
	_check_plumbing(f, two, "radar_gifts", 2)
	_check(f, base.lstate.upgrades == null,
		"radar_gifts: the un-owned level built a scripted-upgrade engine (want null)")
	# The roles wiring that DID land: the owned level carries the gift_radar role.
	_check(f, owned.lstate.upgrades != null and bool(owned.lstate.upgrades.has("gift_radar")),
		"radar_gifts: the owned level did not build the gift_radar role (lstate.upgrades is %s)"
			% str(owned.lstate.upgrades))
	_check(f, two.lstate.upgrades != null and bool(two.lstate.upgrades.has("gift_radar")),
		"radar_gifts: the owned x2 level did not build the gift_radar role (lstate.upgrades is %s)"
			% str(two.lstate.upgrades))
	_note_inert("radar_gifts",
		"the roles wiring landed (lstate.upgrades non-null, has gift_radar) but nothing in the shipped path reads it: sim/upgrades.gd nearest_real_gift() has no app/ caller, hud.gd builds no arrow entry (the radar_arrows widget exists but is never instantiated), so no arrow is ever drawn")
	_drop(owned)
	_drop(two)
	_drop(base)


# ---- radar_mines (T3, max 1): disguised tripmines within 14 u get a pink outline ----------------

func _leg_radar_mines(f: Array[String]) -> void:
	var owned = _build({"radar_mines": 1})
	var base = _build({})
	if owned == null or base == null:
		_check(f, false, "radar_mines: a world failed to build")
		_drop(owned)
		_drop(base)
		return
	_check_plumbing(f, base, "radar_mines", 0)
	_check_plumbing(f, owned, "radar_mines", 1)
	_check(f, base.lstate.upgrades == null,
		"radar_mines: the un-owned level built a scripted-upgrade engine (want null)")
	# The roles wiring that DID land: the owned level carries the mine_radar role.
	_check(f, owned.lstate.upgrades != null and bool(owned.lstate.upgrades.has("mine_radar")),
		"radar_mines: the owned level did not build the mine_radar role (lstate.upgrades is %s)"
			% str(owned.lstate.upgrades))
	# Control-side canon: the outline pass is off on the live mine view in the owned world too
	# (nothing in the shipped path arms it).
	_check(f, owned.tripmine_view != null and not bool(owned.tripmine_view._radar),
		"radar_mines: the owned world's mine view is missing or has the radar outline armed")
	_note_inert("radar_mines",
		"the roles wiring landed (lstate.upgrades non-null, has mine_radar) but no shipped call site reads it: world.gd never calls set_radar on the tripmine view (it stays off), and sim/upgrades.gd mine_outline_ids() has no app/ caller, so no mine outline ever appears")
	_drop(owned)
	_drop(base)


# ---- radar_threats (T2, max 1): screen-edge markers for enemies within 30 u ---------------------

func _leg_radar_threats(f: Array[String]) -> void:
	var owned = _build({"radar_threats": 1})
	var base = _build({})
	if owned == null or base == null:
		_check(f, false, "radar_threats: a world failed to build")
		_drop(owned)
		_drop(base)
		return
	_check_plumbing(f, base, "radar_threats", 0)
	_check_plumbing(f, owned, "radar_threats", 1)
	_check(f, base.lstate.upgrades == null,
		"radar_threats: the un-owned level built a scripted-upgrade engine (want null)")
	# The roles wiring that DID land: the owned level carries the threat_radar role.
	_check(f, owned.lstate.upgrades != null and bool(owned.lstate.upgrades.has("threat_radar")),
		"radar_threats: the owned level did not build the threat_radar role (lstate.upgrades is %s)"
			% str(owned.lstate.upgrades))
	_note_inert("radar_threats",
		"the roles wiring landed (lstate.upgrades non-null, has threat_radar) but nothing in the shipped path reads it: sim/upgrades.gd threat_markers() has no app/ caller, hud.gd builds no edge marker (the radar_arrows widget exists but is never instantiated), so no marker is ever drawn")
	_drop(owned)
	_drop(base)


# ---- skeleton_key (T4, max 1): the beacon opens at 90% of real black gifts ----------------------

func _leg_skeleton_key(f: Array[String]) -> void:
	var owned = _build({"skeleton_key": 1})
	var base = _build({})
	if owned == null or base == null:
		_check(f, false, "skeleton_key: a world failed to build")
		_drop(owned)
		_drop(base)
		return
	_check_plumbing(f, base, "skeleton_key", 0)
	_check_plumbing(f, owned, "skeleton_key", 1)
	var gb: RefCounted = base.lstate.gifts
	var go: RefCounted = owned.lstate.gifts
	_check(f, int(gb.black_quota) == -1,
		"skeleton_key: the un-owned black quota reads %d, want -1 (canon: open at 100%% of real black gifts)"
			% int(gb.black_quota))
	var total := int(gb.total_real)
	if total < 10:
		f.append("skeleton_key: the level carries only %d real gifts; need >= 10 for the quota measurement" % total)
		_drop(owned)
		_drop(base)
		return
	var want := int(ceil(float(total) * 0.9))
	_check(f, int(go.black_quota) == want,
		"skeleton_key: the owned black quota reads %d, want ceil(90%% of %d) = %d"
			% [int(go.black_quota), total, want])
	# Functional through world.step(): collect quota - 1 gifts directly (the same standing the
	# economy calls have), then the quota-th through the real pickup path; the owned beacon
	# opens at ceil(90%), the un-owned one needs every real black gift.
	for w in [base, owned]:
		var g: RefCounted = w.lstate.gifts
		var taken := 0
		for i in g.slots.size():
			if taken >= want - 1:
				break
			if bool(g.is_real(i)) and not bool(g.collected(i)):
				g.collect(i, int(w.lstate.tick), 0, [])
				taken += 1
	for w in [base, owned]:
		var slot := _a_gift_slot(w)
		if slot < 0:
			_check(f, false, "skeleton_key: no collectible gift slot left for the quota-th pickup")
			_drop(owned)
			_drop(base)
			return
		var pos: Vector3 = w.lstate.gifts.position_of(slot)
		w.ctl.x = float(pos.x)
		w.ctl.y = float(pos.y) - 0.9
		w.ctl.z = float(pos.z)
		w.ctl.grounded = true
		w.ctl.vx = 0.0
		w.ctl.vy = 0.0
		w.ctl.vz = 0.0
		for _i in range(3):
			w.step(DT)
	_check(f, not bool(base.lstate.beacon.is_open()),
		"skeleton_key: the un-owned beacon opened at %d of %d real gifts - it must wait for the last one"
			% [want, total])
	_check(f, bool(owned.lstate.beacon.is_open()),
		"skeleton_key: the owned beacon is still shut at %d of %d real gifts - the 90%% quota never reached the gifts"
			% [want, total])
	_drop(owned)
	_drop(base)


# ---- slipstream (T3, max 1): +20% speed for 2.0 s after any gift pickup -------------------------

func _leg_slipstream(f: Array[String]) -> void:
	var owned = _build({"slipstream": 1})
	var base = _build({})
	if owned == null or base == null:
		_check(f, false, "slipstream: a world failed to build")
		_drop(owned)
		_drop(base)
		return
	_check_plumbing(f, base, "slipstream", 0)
	_check_plumbing(f, owned, "slipstream", 1)
	var before_b := -1
	var before_o := -1
	for w in [base, owned]:
		var g: RefCounted = w.lstate.gifts
		var slot := _a_gift_slot(w)
		if slot < 0:
			_check(f, false, "slipstream: no collectible gift slot in the level")
			_drop(owned)
			_drop(base)
			return
		var pos: Vector3 = g.position_of(slot)
		w.ctl.x = float(pos.x)
		w.ctl.y = float(pos.y) - 0.9
		w.ctl.z = float(pos.z)
		w.ctl.grounded = true
		if w == base:
			before_b = int(g.remaining())
		else:
			before_o = int(g.remaining())
		for _i in range(2):
			w.step(DT)
	_check(f, int(base.lstate.gifts.remaining()) == before_b - 1,
		"slipstream: the un-owned gift did not collect through the pickup path (remaining %d -> %d, want %d)"
			% [before_b, int(base.lstate.gifts.remaining()), before_b - 1])
	_check(f, int(owned.lstate.gifts.remaining()) == before_o - 1,
		"slipstream: the owned gift did not collect through the pickup path (remaining %d -> %d, want %d)"
			% [before_o, int(owned.lstate.gifts.remaining()), before_o - 1])
	var base_o := float(owned._stats_black.get("run_speed", 1.0))
	var base_b := float(base._stats_black.get("run_speed", 1.0))
	_check(f, is_equal_approx(float(owned.ctl.run_speed_mul), base_o * 1.2),
		"slipstream: the owned run_speed_mul after the pickup reads %.4f, want %.4f (x1.2)"
			% [float(owned.ctl.run_speed_mul), base_o * 1.2])
	_check(f, is_equal_approx(float(base.ctl.run_speed_mul), base_b),
		"slipstream: the un-owned run_speed_mul moved to %.4f after the pickup, want the base %.4f"
			% [float(base.ctl.run_speed_mul), base_b])
	_drop(owned)
	_drop(base)


# ---- spring_heels (T2, max 2): +1 air jump / stack at 80% jump height ---------------------------

func _leg_spring_heels(f: Array[String]) -> void:
	var owned = _build({"spring_heels": 1})
	var two = _build({"spring_heels": 2})
	var base = _build({})
	if owned == null or two == null or base == null:
		_check(f, false, "spring_heels: a world failed to build")
		_drop(owned)
		_drop(two)
		_drop(base)
		return
	_check_plumbing(f, base, "spring_heels", 0)
	_check_plumbing(f, owned, "spring_heels", 1)
	_check_plumbing(f, two, "spring_heels", 2)
	# Control-side canon: the base body has no air jump at all.
	_check(f, int(base.ctl.air_jumps_max) == 0,
		"spring_heels: the un-owned body's air jump stock reads %d, want the canon 0"
			% int(base.ctl.air_jumps_max))
	_note_inert("spring_heels",
		"apply_double_jump_stacks (the W13-B consumer) is never called by the world, so no air jump is granted: owned reads %d, owned x2 reads %d, control %d extra air jumps - the 80%% air jump and the Athletic boost never exist"
			% [int(owned.ctl.air_jumps_max), int(two.ctl.air_jumps_max), int(base.ctl.air_jumps_max)])
	_drop(owned)
	_drop(two)
	_drop(base)


# ---- stand_fast (T2, max 1): the first chain-breaker per level does not reset the chain ---------

func _leg_stand_fast(f: Array[String]) -> void:
	var owned = _build({"stand_fast": 1})
	var base = _build({})
	if owned == null or base == null:
		_check(f, false, "stand_fast: a world failed to build")
		_drop(owned)
		_drop(base)
		return
	_check_plumbing(f, base, "stand_fast", 0)
	_check_plumbing(f, owned, "stand_fast", 1)
	var chain_b := -1
	var chain_o := -1
	for w in [base, owned]:
		var e: RefCounted = w._economy
		e.begin_gold_phase()
		e.collect_gold_gift()
		e.collect_gold_gift()
		if w == base:
			chain_b = int(e.chain_centi)
		else:
			chain_o = int(e.chain_centi)
		w.ctl.invuln = 0.0
		w.ctl.charges = 2
		w.ctl.y = float(w.ctl.C["kill_plane_y"]) - 5.0
		w.ctl.vy = -10.0
		w.ctl.grounded = false
		w.step(DT)
	_check(f, chain_b == 110 and chain_o == 110,
		"stand_fast: the fixture's chain reads control %d owned %d after two gold gifts, want 110 in both"
			% [chain_b, chain_o])
	_check(f, int(base._economy.chain_centi) == 100,
		"stand_fast: the un-owned chain did not reset on the void fall (chain_centi %d, want 100)"
			% int(base._economy.chain_centi))
	_check(f, int(owned._economy.chain_centi) == chain_o,
		"stand_fast: the owned chain reset on the first void fall (chain_centi %d, want %d kept - the stand-fast save)"
			% [int(owned._economy.chain_centi), chain_o])
	_check(f, int(owned.ctl.charges) == 1,
		"stand_fast: the owned fall did not spend a charge (charges %d, want 1)" % int(owned.ctl.charges))
	_drop(owned)
	_drop(base)


# ---- straggler_scope (T2, max 1): straggler beams open at the last 35% instead of 20% ----------

func _leg_straggler_scope(f: Array[String]) -> void:
	var owned = _build({"straggler_scope": 1})
	var base = _build({})
	if owned == null or base == null:
		_check(f, false, "straggler_scope: a world failed to build")
		_drop(owned)
		_drop(base)
		return
	_check_plumbing(f, base, "straggler_scope", 0)
	_check_plumbing(f, owned, "straggler_scope", 1)
	var total := int(base.lstate.gifts.total_real)
	if total < 10:
		f.append("straggler_scope: the level carries only %d real gifts; need >= 10 for the residual-band measurement" % total)
		_drop(owned)
		_drop(base)
		return
	var rem30 := int(floor(float(total) * 0.30))
	_collect_until(base.lstate.gifts, rem30)
	_collect_until(owned.lstate.gifts, rem30)
	_check(f, base.lstate.gifts.straggler_ids().is_empty(),
		"straggler_scope: the canon 20%% band already fired at %d/%d remaining - gift fixture broken"
			% [int(base.lstate.gifts.remaining()), total])
	var s_o: Array = owned.lstate.gifts.straggler_ids()
	_note_inert("straggler_scope",
		"at 30%% remaining the owned straggler set is empty (%d gifts): sim/gifts.gd gained apply_straggler_band (the W13-B consumer, the 35%% band) but the world never calls it, so both worlds fire only at the STRAGGLER_DEN 20%% band"
			% s_o.size())
	var rem20 := int(floor(float(total) * 0.20))
	if rem20 < 1:
		rem20 = 1
	_collect_until(base.lstate.gifts, rem20)
	_collect_until(owned.lstate.gifts, rem20)
	_check(f, not base.lstate.gifts.straggler_ids().is_empty(),
		"straggler_scope: the canon 20%% band produced no stragglers at %d/%d remaining - gift fixture broken"
			% [rem20, total])
	_check(f, not owned.lstate.gifts.straggler_ids().is_empty(),
		"straggler_scope: the owned straggler set is empty at %d/%d remaining (inside the canon 20%% band, which must always fire)"
			% [rem20, total])
	_drop(owned)
	_drop(base)


# ---- subspacial_barrier (T3, max 1): 1 shield / level, absorbs exactly one tripmine --------------

func _leg_subspacial_barrier(f: Array[String]) -> void:
	# Gift-larper votes add 3 tripmines to the level (min_level 5), so the contact fixture
	# always has a live one; the un-voted level 1 build has none. The votes never appear in
	# the owned build's stats - they are fixture geometry, not the upgrade under test.
	var votes := {"gift_larper": 1}
	var owned = _build({"subspacial_barrier": 1}, "dasher", 5, votes)
	var base = _build({}, "dasher", 5, votes)
	if owned == null or base == null:
		_check(f, false, "subspacial_barrier: a world failed to build")
		_drop(owned)
		_drop(base)
		return
	_check_plumbing(f, base, "subspacial_barrier", 0)
	_check_plumbing(f, owned, "subspacial_barrier", 1)
	# Last Light pre-spent in BOTH (a fixture, not the control): the un-owned run must die.
	owned.ctl.last_light_spent = true
	base.ctl.last_light_spent = true
	_check(f, int(base.ctl.barrier_shields) == 0,
		"subspacial_barrier: the un-owned body starts with %d shields, want 0" % int(base.ctl.barrier_shields))
	_check(f, int(owned.ctl.barrier_shields) == 1,
		"subspacial_barrier: the owned body starts with %d shields, want the level-start grant of 1" % int(owned.ctl.barrier_shields))
	for w in [base, owned]:
		var m := _live_mine_slot(w)
		if m < 0:
			f.append("subspacial_barrier: no live tripmine slot in the level to contact")
			_drop(owned)
			_drop(base)
			return
		var p: Vector3 = w.lstate.mines.point(m)
		w.ctl.x = float(p.x)
		w.ctl.y = float(p.y)
		w.ctl.z = float(p.z)
		w.ctl.invuln = 0.0
		w.ctl.grounded = true
		w.step(DT)
	_check(f, bool(base.ctl.dead) and str(base.ctl.dead_code) == "D-MINE",
		"subspacial_barrier: the un-owned body did not die to the tripmine (dead %s, code %s) - expected D-MINE with Last Light pre-spent"
			% [str(bool(base.ctl.dead)), str(base.ctl.dead_code)])
	_check(f, not bool(owned.ctl.dead),
		"subspacial_barrier: the owned body died to the tripmine - the shield should have absorbed it")
	_check(f, int(owned.ctl.barrier_shields) == 0,
		"subspacial_barrier: the owned body kept %d shields after the absorb, want 0 (consumed)"
			% int(owned.ctl.barrier_shields))
	# The level-start budget restores on beacon entry.
	var b: RefCounted = owned.lstate.beacon
	b.open(int(owned.lstate.tick))
	owned.ctl.x = float(b.cx)
	owned.ctl.y = float(b.base_y)
	owned.ctl.z = float(b.cz)
	owned.ctl.grounded = true
	owned.ctl.vy = 0.0
	owned.step(DT)
	_check(f, int(owned.ctl.barrier_shields) == 1,
		"subspacial_barrier: the shield was not restored on beacon entry (%d held, want 1)"
			% int(owned.ctl.barrier_shields))
	_drop(owned)
	_drop(base)


# ---- twin_dash (T3, max 1, dasher): 2 dash charges from the second stock -------------------------

func _leg_twin_dash(f: Array[String]) -> void:
	var owned = _build({"twin_dash": 1})
	var base = _build({})
	if owned == null or base == null:
		_check(f, false, "twin_dash: a world failed to build")
		_drop(owned)
		_drop(base)
		return
	_check_plumbing(f, base, "twin_dash", 0)
	_check_plumbing(f, owned, "twin_dash", 1)
	# Control-side canon: the base body holds no second dash stock.
	_check(f, int(base.ctl.bonus_dashes_max) == 0,
		"twin_dash: the un-owned body holds %d bonus dash stocks, want the canon 0"
			% int(base.ctl.bonus_dashes_max))
	_note_inert("twin_dash",
		"apply_twin_dash is never called by the world (sim/controller.gd apply_twin_dash exists; world.gd builds and steps without it): bonus_dashes_max owned %d, control %d - the second stock and its 3 s regen never exist"
			% [int(owned.ctl.bonus_dashes_max), int(base.ctl.bonus_dashes_max)])
	_drop(owned)
	_drop(base)


# ---- updraft (T3, max 1, glider): once per glide, press jump to rise 3 u (6 s cd) -----------------

func _leg_updraft(f: Array[String]) -> void:
	var owned = _build({"updraft": 1}, "glider")
	var base = _build({}, "glider")
	if owned == null or base == null:
		_check(f, false, "updraft: a world failed to build")
		_drop(owned)
		_drop(base)
		return
	_check_plumbing(f, base, "updraft", 0)
	_check_plumbing(f, owned, "updraft", 1)
	# Control-side canon: the base glider has no rise granted.
	_check(f, not bool(base.ctl.updraft_owned),
		"updraft: the un-owned glider reports updraft_owned - want false")
	_note_inert("updraft",
		"apply_updraft is never called by the world (sim/controller.gd apply_updraft exists; world.gd builds and steps without it): updraft_owned owned %s, control %s - the 3 u rise and its 6 s cooldown never exist"
			% [str(bool(owned.ctl.updraft_owned)), str(bool(base.ctl.updraft_owned))])
	_drop(owned)
	_drop(base)