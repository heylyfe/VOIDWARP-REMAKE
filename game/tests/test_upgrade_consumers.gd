extends RefCounted
#
# UPGRADE CONSUMERS test (headless) - W13-B: the nine stack consumers this wave
# landed in the sim. One leg per upgrade, each driven through world.build() and
# world.step() where the effect is observable there, or through the real sim
# object the world drives where it is not (the hand-made input a headless
# world.step() cannot receive, or the one-line world.gd call that ARM these
# consumers - world.gd is outside this worker's scope, so the line is REPORTED,
# not applied; until the lead lands it, an owned world builds exactly like the
# un-owned one and this file performs the reported call itself, on the built
# world, which is what the negative control then contrasts against).
#
# Every leg carries a NEGATIVE CONTROL: the same assertion fails when the
# upgrade is not owned (the un-owned twin of the same fixture). A leg that
# cannot tell owned from not-owned is a failure here, not an inert note - the
# module-without-a-caller defect this wave exists to close.
#
# Reported world.gd lines (one per upgrade, for the lead - see W13-B report):
#   brace            ctl.apply_push_dampening(<brace stacks>)          (at build)
#   featherfall      ctl.apply_fall_cap(<featherfall stacks>)         (at build)
#   last_call        collect_gold_gift(LastCallScript.is_final_band(
#                        int(_economy.gold_gifts_collected), int(lstate.gifts.total_real)))
#   ledge_grace      ctl.apply_coyote_bonus(<ledge_grace stacks>)      (at build)
#   marathon         intermission create gains p_max_stacks_bonus from the
#                    caller's aggregator (the athletic + owned pairing)
#   more             _economy.apply_gift_yield(<more stacks>)           (at build)
#   quick_recovery   ctl.apply_cooldown_reduction(<quick_recovery>) for
#                    dasher/glider; apply_speed_upgrade(0.05 * n) for athletic
#   spring_heels     ctl.apply_double_jump_stacks(<spring_heels stacks>) (at build)
#   straggler_scope  lstate.gifts.apply_straggler_band(<straggler_scope stacks>) (at build)
#
# Determinism: SEED-pinned builds only; assertions measure exact or
# is_equal_approx floats, never frame counts beyond the fixed DT.

const WorldScript := preload("res://app/world.gd")
const IntermissionScript := preload("res://sim/intermission.gd")
const ContentApiScript := preload("res://core/content_api.gd")
const LastCallScript := preload("res://content/upgrades/last_call.gd")
const MarathonScript := preload("res://content/upgrades/marathon.gd")

const SEED := 1
const LEVEL := 1
const DT := 1.0 / 60.0
const BTN_JUMP := 1
const BTN_ABILITY := 2
const JUMP_HELD := {"move_x": 0, "move_z": 0, "buttons": BTN_JUMP, "aim_x": 0, "aim_z": 1}
const JUMP_RELEASED := {"move_x": 0, "move_z": 0, "buttons": 0, "aim_x": 0, "aim_z": 1}
const ABILITY_TAP := {"move_x": 0, "move_z": 0, "buttons": BTN_ABILITY, "aim_x": 0, "aim_z": 1}
const IDLE := {"move_x": 0, "move_z": 0, "buttons": 0, "aim_x": 0, "aim_z": 1}


func run() -> Array[String]:
	var f: Array[String] = []
	_leg_brace(f)
	_leg_featherfall(f)
	_leg_last_call(f)
	_leg_ledge_grace(f)
	_leg_marathon(f)
	_leg_more(f)
	_leg_quick_recovery(f)
	_leg_spring_heels(f)
	_leg_straggler_scope(f)
	print("UPGRADE CONSUMERS legs complete, failures=%d" % f.size())
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


## Collect gifts until at most rem_target real gifts remain in the current phase
## (same shape as the audit fixture; the phase flip only happens at the last one).
func _collect_until(gifts, rem_target: int) -> void:
	for i in gifts.slots.size():
		if int(gifts.remaining()) <= rem_target:
			return
		if bool(gifts.is_real(i)) and not bool(gifts.collected(i)):
			gifts.collect(i, 0, 0, [])


# ---- brace: external push velocity -30% per stack (compounding) ------------------------

func _leg_brace(f: Array[String]) -> void:
	var owned = _build({"brace": 1})
	var two = _build({"brace": 2})
	var three = _build({"brace": 3})
	var base = _build({})
	if owned == null or two == null or three == null or base == null:
		_check(f, false, "brace: a world failed to build")
		_drop(owned)
		_drop(two)
		_drop(three)
		_drop(base)
		return
	# The reported world line, run on each built world:
	owned.ctl.apply_push_dampening(1)
	two.ctl.apply_push_dampening(2)
	three.ctl.apply_push_dampening(3)
	# The application site is the push itself, driven through the real runtime
	# the world runs (a coil shockwave and the eject both land here).
	var dir := Vector3(0.0, 1.0, 0.0)
	base.rt.push(base.ctl, dir, 18.0, {})
	owned.rt.push(owned.ctl, dir, 18.0, {})
	two.rt.push(two.ctl, dir, 18.0, {})
	three.rt.push(three.ctl, dir, 18.0, {})
	_check(f, is_equal_approx(float(base.ctl.vy), 18.0),
		"brace: the un-owned body took the full push (vy %.3f, want 18.0)" % float(base.ctl.vy))
	_check(f, is_equal_approx(float(owned.ctl.vy), 12.6),
		"brace: one stack did not pay the x0.7 push (vy %.3f, want 12.6)" % float(owned.ctl.vy))
	_check(f, is_equal_approx(float(two.ctl.vy), 8.82),
		"brace: two stacks did not pay the x0.49 push (vy %.3f, want 8.82)" % float(two.ctl.vy))
	_check(f, is_equal_approx(float(three.ctl.vy), 6.174),
		"brace: three stacks did not pay the x0.343 push (vy %.3f, want 6.174)" % float(three.ctl.vy))
	# horizontal push, the shockwave direction: same damping on x/z
	var side := Vector3(1.0, 0.0, 0.0)
	base.rt.push(base.ctl, side, 8.0, {})
	owned.rt.push(owned.ctl, side, 8.0, {})
	_check(f, is_equal_approx(float(base.ctl.vx), 8.0),
		"brace: the un-owned body took the full shockwave (vx %.3f, want 8.0)" % float(base.ctl.vx))
	_check(f, is_equal_approx(float(owned.ctl.vx), 5.6),
		"brace: one stack did not pay the x0.7 shockwave (vx %.3f, want 5.6)" % float(owned.ctl.vx))
	_drop(owned)
	_drop(two)
	_drop(three)
	_drop(base)


# ---- last_call: the final 20% of gold gifts pay double ---------------------------------

## The payout the canon chain math gives for the i-th (1-based) gold gift, chain 1.00
## start, +0.05 per in-window gift, cap x2.00, floor once.
func _gold_at(p_i: int) -> int:
	var chain := mini(100 + 5 * (p_i - 1), 200)
	return int(floor(200.0 * float(chain) / 100.0))


func _leg_last_call(f: Array[String]) -> void:
	var owned = _build({"last_call": 1})
	var base = _build({})
	if owned == null or base == null:
		_check(f, false, "last_call: a world failed to build")
		_drop(owned)
		_drop(base)
		return
	var eo: RefCounted = owned._economy
	var eb: RefCounted = base._economy
	var total := int(owned.lstate.gifts.total_real)
	_check(f, total >= 10,
		"last_call: the fixture level carries %d real gifts; need >= 10" % total)
	# The reported world line, replayed on both economies exactly as the app will:
	#   var band := LastCallScript.is_final_band(int(_economy.gold_gifts_collected),
	#       int(lstate.gifts.total_real))
	#   _economy.collect_gold_gift(band)
	# The owned side may double whatever the content band marks; the un-owned
	# side is the same sequence with no band (canon: final_band defaults false).
	# Zero the carried purse so the payout is what this leg measured (the world
	# seeds the economy from the ledger's 500 g otherwise).
	eo.purse_centi = 0
	eb.purse_centi = 0
	eo.begin_gold_phase()
	eb.begin_gold_phase()
	var band_gifts := 0
	for i in range(1, total + 1):
		var band := LastCallScript.is_final_band(i - 1, total)
		if band:
			band_gifts += 1
		eo.collect_gold_gift(band)
		eb.collect_gold_gift()
	# Expected sums, recomputed here from the canon chain math.
	var want_base := 0
	var want_owned := 0
	for i in range(1, total + 1):
		want_base += _gold_at(i)
		if LastCallScript.is_final_band(i - 1, total):
			want_owned += 2 * _gold_at(i)
		else:
			want_owned += _gold_at(i)
	_check(f, int(eo.purse_centi) == want_owned,
		"last_call: the owned run paid %d centi, want %d (the final %d gifts doubled)"
			% [int(eo.purse_centi), want_owned, band_gifts])
	_check(f, int(eb.purse_centi) == want_base,
		"last_call: the un-owned run paid %d centi, want the canon %d - control fixture broken"
			% [int(eb.purse_centi), want_base])
	_check(f, int(eo.purse_centi) > int(eb.purse_centi),
		"last_call: the band never paid anything (owned %d vs control %d)"
			% [int(eo.purse_centi), int(eb.purse_centi)])
	_check(f, int(eo.gold_gifts_collected) == total,
		"last_call: the economy counted %d gold gifts, want %d - the caller cannot place the band"
			% [int(eo.gold_gifts_collected), total])
	_check(f, int(eb.gold_gifts_collected) == total,
		"last_call: the control counted %d gold gifts, want %d"
			% [int(eb.gold_gifts_collected), total])
	_drop(owned)
	_drop(base)


# ---- marathon: the athletic max-stacks bonus reaches the shop draw ----------------------

func _leg_marathon(f: Array[String]) -> void:
	var api = ContentApiScript.load()
	if api == null or not api.is_ok():
		_check(f, false, "marathon: the content registry failed to boot")
		return
	var held := {"yearn_for_speed": 4, "marathon": 1}
	# The bonus the caller's aggregator computes (the content script's own rule).
	var bonus := MarathonScript.max_bonus("athletic", held)
	_check(f, not bonus.is_empty(),
		"marathon: the aggregator refused the athletic pairing - fixture broken")
	# Level 1 lights a U bay; its bracket is exactly paycheck / more / yearn_for_speed.
	# At 4 owned stacks the base cap (4) excludes the third slot entirely, so the
	# bonus is observable on the altar list alone, no seed dependence.
	var lb_owned = IntermissionScript.create(api, 1, 10000, SEED, {}, {}, held,
		"athletic", 0, 0, "", {}, bonus)
	var lb_base = IntermissionScript.create(api, 1, 10000, SEED, {}, {}, held,
		"athletic", 0, 0, "", {}, {})
	if lb_owned == null or lb_base == null:
		_check(f, false, "marathon: an intermission failed to build")
		return
	var owned_ids := _u_altar_ids(lb_owned)
	var base_ids := _u_altar_ids(lb_base)
	_check(f, owned_ids.has("yearn_for_speed"),
		"marathon: the bonus never reached the draw - the +2 cap was not applied (altars %s)"
			% str(owned_ids))
	_check(f, not base_ids.has("yearn_for_speed"),
		"marathon: the un-bonus lobby offered the maxed upgrade - the canon cap was not applied (altars %s)"
			% str(base_ids))
	# The pre-existing callers' shape: no bonus argument at all -> canon caps.
	var lb_plain = IntermissionScript.create(api, 1, 10000, SEED, {}, {}, held, "athletic")
	if lb_plain == null:
		_check(f, false, "marathon: an intermission without the bonus argument failed to build")
		return
	_check(f, not _u_altar_ids(lb_plain).has("yearn_for_speed"),
		"marathon: a caller that passes no bonus saw the maxed upgrade - the default is not the canon cap")


func _u_altar_ids(lb) -> Array:
	for bay in lb.bays:
		if str(bay.get("kind", "")) != "U":
			continue
		var out: Array = []
		for altar in (bay.get("altars", []) as Array):
			out.append(str(altar.get("id", "")))
		return out
	return []


# ---- more: +10% gift yield per stack -----------------------------------------------------

func _leg_more(f: Array[String]) -> void:
	var owned = _build({"more": 1})
	var three = _build({"more": 3})
	var base = _build({})
	if owned == null or three == null or base == null:
		_check(f, false, "more: a world failed to build")
		_drop(owned)
		_drop(three)
		_drop(base)
		return
	# The reported world line, run on each built world's economy:
	owned._economy.apply_gift_yield(1)
	three._economy.apply_gift_yield(3)
	owned._economy.begin_gold_phase()
	three._economy.begin_gold_phase()
	base._economy.begin_gold_phase()
	var v_o := int(owned._economy.collect_gold_gift())
	var v_3 := int(three._economy.collect_gold_gift())
	var v_b := int(base._economy.collect_gold_gift())
	_check(f, v_b == 200,
		"more: the un-owned gold gift paid %d centi, want the canon 200 (chain x1.00)" % v_b)
	_check(f, v_o == 220,
		"more: one stack did not pay +10%% (got %d centi, want 220)" % v_o)
	_check(f, v_3 == 260,
		"more: three stacks did not pay +30%% (got %d centi, want 260)" % v_3)
	_drop(owned)
	_drop(three)
	_drop(base)

# ---- ledge_grace: coyote time +0.08 s per stack ------------------------------------------

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
	# The reported world line, run on each built world (a grounded tick sets the window):
	owned.ctl.apply_coyote_bonus(1)
	two.ctl.apply_coyote_bonus(2)
	base.step(DT)
	owned.step(DT)
	two.step(DT)
	_check(f, is_equal_approx(float(base.ctl.coyote), 0.10),
		"ledge_grace: the un-owned coyote reads %.3f s, want the data 0.10 s" % float(base.ctl.coyote))
	_check(f, is_equal_approx(float(owned.ctl.coyote), 0.18),
		"ledge_grace: one stack did not pay +0.08 s (coyote %.3f, want 0.18)" % float(owned.ctl.coyote))
	_check(f, is_equal_approx(float(two.ctl.coyote), 0.26),
		"ledge_grace: two stacks did not pay +0.16 s (coyote %.3f, want 0.26)" % float(two.ctl.coyote))
	# Functional, through world.step(): from the same height, with the base 0.10 s
	# window already spent, only the widened windows still allow the jump.
	for w in [base, owned, two]:
		w.ctl.y = float(w.ctl.y) + 5.0
		w.ctl.vy = 0.0
		w.ctl.grounded = false
	for _i in range(8):   # ~0.133 s of air, beyond the canon window
		base.ctl.step(DT, IDLE, base.w)
		owned.ctl.step(DT, IDLE, owned.w)
		two.ctl.step(DT, IDLE, two.w)
	for w in [base, owned, two]:
		w.ctl.step(DT, JUMP_HELD, w.w)
	_check(f, float(base.ctl.vy) <= 0.0,
		"ledge_grace: the un-owned body jumped after the window closed (vy %.2f)" % float(base.ctl.vy))
	_check(f, float(owned.ctl.vy) > 0.0,
		"ledge_grace: one stack did not jump inside the widened window (vy %.2f)" % float(owned.ctl.vy))
	_check(f, float(two.ctl.vy) > 0.0,
		"ledge_grace: two stacks did not jump inside the widened window (vy %.2f)" % float(two.ctl.vy))
	_drop(owned)
	_drop(two)
	_drop(base)

# ---- featherfall: hold jump, the fall speed cap becomes 6 u/s ---------------------------

func _leg_featherfall(f: Array[String]) -> void:
	var owned = _build({"featherfall": 1})
	var base = _build({})
	if owned == null or base == null:
		_check(f, false, "featherfall: a world failed to build")
		_drop(owned)
		_drop(base)
		return
	# The reported world line, run on the built world:
	owned.ctl.apply_fall_cap(1)
	# Both bodies drop from the same height with jump HELD in the input; the
	# owned body may never break the 6 u/s band, the control blows through it.
	var min_o := 0.0
	var min_b := 0.0
	for w in [owned, base]:
		w.ctl.y = float(w.ctl.y) + 24.0
		w.ctl.vy = 0.0
		w.ctl.grounded = false
	for _i in range(120):
		owned.ctl.step(DT, JUMP_HELD, owned.w)
		base.ctl.step(DT, JUMP_HELD, base.w)
		min_o = minf(min_o, float(owned.ctl.vy))
		min_b = minf(min_b, float(base.ctl.vy))
	_check(f, min_b < -6.0,
		"featherfall: the un-owned body's fall only reached %.2f u/s - it must fall freely past the 6 u/s band" % min_b)
	_check(f, min_o >= -6.0 - 1e-3,
		"featherfall: the held body broke the 6 u/s cap (peak %.2f u/s)" % min_o)
	# The glider branch: energy, not the cap.
	var g_owned = _build({"featherfall": 1}, "glider")
	var g_base = _build({}, "glider")
	if g_owned == null or g_base == null:
		_check(f, false, "featherfall: the glider world failed to build")
		_drop(g_owned)
		_drop(g_base)
		_drop(owned)
		_drop(base)
		return
	g_owned.ctl.apply_fall_cap(1)
	_check(f, is_equal_approx(float(g_owned.ctl.glide_energy), 4.5),
		"featherfall: the glider branch granted %.2f s of glide energy, want 4.5" % float(g_owned.ctl.glide_energy))
	_check(f, is_equal_approx(float(g_base.ctl.glide_energy), 3.0),
		"featherfall: the un-owned glider reads %.2f s of glide energy, want 3.0" % float(g_base.ctl.glide_energy))
	_check(f, not bool(g_owned.ctl.feather_fall),
		"featherfall: the glider branch armed the fall cap - the bonus must replace it")
	_drop(g_owned)
	_drop(g_base)
	_drop(owned)
	_drop(base)


# ---- quick_recovery: class ability cooldown -20% per stack --------------------------------

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
	# The reported world line (dasher / glider branch), run on each built world:
	owned.ctl.apply_cooldown_reduction(1)
	two.ctl.apply_cooldown_reduction(2)
	# The dasher's dash regen is the class cooldown: fire the ability on each.
	for w in [base, owned, two]:
		w.ctl.step(DT, ABILITY_TAP, w.w)
	_check(f, is_equal_approx(float(base.ctl.dash_cd), 3.0),
		"quick_recovery: the un-owned dash regen reads %.2f s, want the data 3.0 s" % float(base.ctl.dash_cd))
	_check(f, is_equal_approx(float(owned.ctl.dash_cd), 2.4),
		"quick_recovery: one stack did not pay -20%% (dash regen %.2f s, want 2.4)" % float(owned.ctl.dash_cd))
	_check(f, is_equal_approx(float(two.ctl.dash_cd), 1.8),
		"quick_recovery: two stacks did not pay -40%% (dash regen %.2f s, want 1.8)" % float(two.ctl.dash_cd))
	# The glider branch: the rise is the glider's class cooldown.
	var g_owned = _build({"quick_recovery": 1}, "glider")
	var g_base = _build({}, "glider")
	if g_owned == null or g_base == null:
		_check(f, false, "quick_recovery: the glider world failed to build")
		_drop(g_owned)
		_drop(g_base)
		_drop(owned)
		_drop(two)
		_drop(base)
		return
	g_owned.ctl.apply_cooldown_reduction(1)
	for w in [g_base, g_owned]:
		w.ctl.apply_updraft()
		w.ctl.y = float(w.ctl.y) + 5.0
		w.ctl.vy = -1.0
		w.ctl.grounded = false
		# One jump-held step: the glide engages and the re-press edge fires the rise.
		w.ctl.step(DT, JUMP_HELD, w.w)
	_check(f, is_equal_approx(float(g_base.ctl.updraft_cd), 6.0),
		"quick_recovery: the un-owned rise cooldown reads %.2f s, want 6.0" % float(g_base.ctl.updraft_cd))
	_check(f, is_equal_approx(float(g_owned.ctl.updraft_cd), 4.8),
		"quick_recovery: one stack did not pay -20%% on the rise cooldown (%.2f s, want 4.8)" % float(g_owned.ctl.updraft_cd))
	_drop(g_owned)
	_drop(g_base)
	_drop(owned)
	_drop(two)
	_drop(base)


# ---- spring_heels: +1 air jump per stack at 80% jump velocity ----------------------------

func _leg_spring_heels(f: Array[String]) -> void:
	var owned = _build({"spring_heels": 1})
	var two = _build({"spring_heels": 2})
	var athl = _build({"spring_heels": 1}, "athletic")
	var base = _build({})
	if owned == null or two == null or athl == null or base == null:
		_check(f, false, "spring_heels: a world failed to build")
		_drop(owned)
		_drop(two)
		_drop(athl)
		_drop(base)
		return
	# The reported world line, run on each built world (one purchase per stack):
	owned.ctl.apply_double_jump_stacks(1)
	two.ctl.apply_double_jump_stacks(2)
	athl.ctl.apply_double_jump_stacks(1)
	_check(f, int(base.ctl.air_jumps_max) == 0,
		"spring_heels: the un-owned body holds %d air jumps, want 0" % int(base.ctl.air_jumps_max))
	_check(f, int(owned.ctl.air_jumps_max) == 1,
		"spring_heels: one stack granted %d air jumps, want 1" % int(owned.ctl.air_jumps_max))
	_check(f, int(two.ctl.air_jumps_max) == 2,
		"spring_heels: two stacks granted %d air jumps, want 2" % int(two.ctl.air_jumps_max))
	# Functional, through the controller: the air jump pays 0.8 x jump velocity
	# (x1.3 again on the Athletic class multiplier - the 104% the card promises).
	for w in [base, owned, two, athl]:
		w.ctl.y = float(w.ctl.y) + 5.0
		w.ctl.vy = 0.0
		w.ctl.grounded = false
		w.ctl.step(DT, JUMP_HELD, w.w)
	_check(f, float(base.ctl.vy) <= 0.0,
		"spring_heels: the un-owned body air-jumped (vy %.2f)" % float(base.ctl.vy))
	_check(f, absf(float(owned.ctl.vy) - (12.0 * 0.8 - 32.0 * DT)) < 1e-3,
		"spring_heels: the 80%% air jump paid vy %.3f, want %.3f" % [float(owned.ctl.vy), 12.0 * 0.8 - 32.0 * DT])
	_check(f, is_equal_approx(float(two.ctl.vy), float(owned.ctl.vy)),
		"spring_heels: two stacks paid vy %.3f, want %.3f (same card, one jump each)" % [float(two.ctl.vy), float(owned.ctl.vy)])
	_check(f, absf(float(athl.ctl.vy) - (12.0 * 0.8 * 1.3 - 32.0 * DT)) < 1e-3,
		"spring_heels: the Athletic air jump paid vy %.3f, want %.3f (104%%)" % [float(athl.ctl.vy), 12.0 * 0.8 * 1.3 - 32.0 * DT])
	_drop(owned)
	_drop(two)
	_drop(athl)
	_drop(base)


# ---- straggler_scope: the residual band opens at the last 35% ----------------------------

func _leg_straggler_scope(f: Array[String]) -> void:
	var owned = _build({"straggler_scope": 1})
	var base = _build({})
	if owned == null or base == null:
		_check(f, false, "straggler_scope: a world failed to build")
		_drop(owned)
		_drop(base)
		return
	var g_o = owned.lstate.gifts
	var g_b = base.lstate.gifts
	var total := int(g_b.total_real)
	if total < 10:
		_check(f, false,
			"straggler_scope: the level carries only %d real gifts; need >= 10" % total)
		_drop(owned)
		_drop(base)
		return
	# The reported world line, run on the built world's gifts:
	g_o.apply_straggler_band(1)
	var rem30 := int(floor(float(total) * 0.30))
	# Precondition that makes the contrast non-trivial: 30% sits outside the
	# canon band but inside the widened one.
	_check(f, rem30 * 100 > total * 20 and rem30 * 100 <= total * 35,
		"straggler_scope: fixture math broken (rem30 %d at total %d)" % [rem30, total])
	_collect_until(g_b, rem30)
	_collect_until(g_o, rem30)
	_check(f, g_b.straggler_ids().is_empty(),
		"straggler_scope: the canon 20%% band already fired at %d/%d remaining - gift fixture broken"
			% [int(g_b.remaining()), total])
	_check(f, not g_o.straggler_ids().is_empty(),
		"straggler_scope: at %d/%d remaining the widened band did not fire (0 stragglers)"
			% [int(g_o.remaining()), total])
	# The canon band still fires for both at 20%.
	var rem20 := maxi(1, int(floor(float(total) * 0.20)))
	_collect_until(g_b, rem20)
	_collect_until(g_o, rem20)
	_check(f, not g_b.straggler_ids().is_empty(),
		"straggler_scope: the canon 20%% band produced no stragglers at %d/%d - fixture broken"
			% [rem20, total])
	_check(f, not g_o.straggler_ids().is_empty(),
		"straggler_scope: the widened band produced no stragglers inside the canon 20%% band - fixture broken")
	_drop(owned)
	_drop(base)
