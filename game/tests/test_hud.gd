extends RefCounted
#
# T-025: the HUD (DESIGN.md section 14 + section 3.1) shows
#   - "collected / REAL total" with tripmine slots (occ == 1) excluded, on a
#     level-25 seed (42: 136 slots, 124 real, 12 mines);
#   - the void charge pip row: one pip per holdable charge (2, or 1 under
#     Hungry Void), filled = held, hollow = spent;
#   - plus the rest of the section 14 element set: purse + chain format, class
#     ability cooldown, icon rows + Tab collapse, enemy roster, Last Light icon
#     states, diegetic danger lines and the run-over screen's killer/code
#     resolution (sim/death.gd from T-021 is absent; the death event is read
#     from the controller instead).
#
# No global class_name; preload() everywhere (the --headless --script rule).

const VoidGenScript := preload("res://terrain/voidgen.gd")
const LevelStateScript := preload("res://sim/level_state.gd")
const RunStateScript := preload("res://sim/run_state.gd")
const SimScript := preload("res://sim/sim.gd")
const InputScript := preload("res://sim/input.gd")
const GiftsScript := preload("res://sim/gifts.gd")
const ControllerScript := preload("res://sim/controller.gd")
const HudScript := preload("res://view/hud/hud.gd")
const GiftCounterScript := preload("res://view/hud/gift_counter.gd")
const PurseChainScript := preload("res://view/hud/purse_chain.gd")
const VoidPipsScript := preload("res://view/hud/void_pips.gd")
const AbilityCooldownScript := preload("res://view/hud/ability_cooldown.gd")
const IconRowsScript := preload("res://view/hud/icon_rows.gd")
const EnemyRosterScript := preload("res://view/hud/enemy_roster.gd")
const RunOverScript := preload("res://view/hud/run_over.gd")
const DangerTextScript := preload("res://view/hud/danger_text.gd")

const SEED := 42
const LEVEL := 25


func run() -> Array[String]:
	var f: Array[String] = []
	_test_counter_level_25_seed(f)
	_test_void_pips(f)
	_test_element_set(f)
	return f


# ---- the counter: "collected / REAL total", mines excluded, level-25 seed ----

func _test_counter_level_25_seed(f: Array[String]) -> void:
	var L := VoidGenScript.generate(SEED, LEVEL)
	if L.is_empty():
		f.append("seed %d level %d: generator returned an empty level" % [SEED, LEVEL])
		return
	var slots: Array = L["gifts"]
	var real := 0
	var mines := 0
	for s in slots:
		if int(s["occ"]) == 0:
			real += 1
		else:
			mines += 1
	if real <= 0:
		f.append("seed %d level %d: no real gifts" % [SEED, LEVEL])
		return
	if mines <= 0:
		f.append("seed %d level %d: no occ == 1 slots; the mine exclusion is untested" % [SEED, LEVEL])
		return
	if real + mines != slots.size():
		f.append("seed %d level %d: real %d + mines %d != slots %d" % [SEED, LEVEL, real, mines, slots.size()])
		return

	# the sim agrees on the denominator (mines excluded by construction)
	var lv: RefCounted = LevelStateScript.build(L, LEVEL, 1)
	var g: RefCounted = lv.gifts
	if g.total_real != real:
		f.append("sim total_real %d != %d real slots (mines leaked into the total)" % [g.total_real, real])
		return

	var counter = GiftCounterScript.new()
	counter.sync(g.total_real - g.remaining(), g.total_real)
	if counter.counter_text() != "0 / %d" % real:
		f.append("counter at start: '%s', want '0 / %d'" % [counter.counter_text(), real])

	# collect one real gift through the real sim (teleport the player onto it)
	var rs: RefCounted = RunStateScript.new_run(SEED, 1, [])
	rs.load_level(L, LEVEL)
	var lv2: RefCounted = rs.level
	var g2: RefCounted = lv2.gifts
	var first_real := -1
	for i in g2.slots.size():
		if g2.is_real(i):
			first_real = i
			break
	var pos: Vector3 = g2.slot_pos(first_real)
	var p: Dictionary = lv2.players[0]
	p["x"] = pos.x
	p["y"] = pos.y - 1.0
	p["z"] = pos.z
	p["vy"] = 0.0
	p["grounded"] = true
	SimScript.step(rs, [InputScript.neutral()])
	counter.sync(g2.total_real - g2.remaining(), g2.total_real)
	if g2.remaining() != real - 1:
		f.append("sim remaining %d after 1 pickup, want %d" % [g2.remaining(), real - 1])
	if counter.counter_text() != "1 / %d" % real:
		f.append("counter after 1 pickup: '%s', want '1 / %d'" % [counter.counter_text(), real])

	# a mine slot can never move the counter
	var mine_id := -1
	for i in g2.slots.size():
		if not g2.is_real(i):
			mine_id = i
			break
	g2.collect(mine_id, 9999, 0, [])
	counter.sync(g2.total_real - g2.remaining(), g2.total_real)
	if counter.counter_text() != "1 / %d" % real:
		f.append("counter moved by a mine pickup: '%s'" % counter.counter_text())

	# collect every remaining black gift: on the last one the beacon opens and the
	# phase flips to gold (sim/gifts.gd), where "collected" tracks gold gifts and
	# the counter reads 0 / REAL again
	for i in g2.slots.size():
		if g2.is_real(i) and not g2.collected(i):
			g2.collect(i, 10000 + i, 0, [])
	if g2.phase != GiftsScript.PHASE_GOLD:
		f.append("phase %s after the last black gift, want gold" % g2.phase)
	counter.sync(g2.total_real - g2.remaining(), g2.total_real)
	if counter.counter_text() != "0 / %d" % real:
		f.append("counter at beacon open: '%s', want '0 / %d' (gold phase starts over)" % [counter.counter_text(), real])
	# collect every gold gift: the counter lands back on "REAL / REAL", never more
	for i in g2.slots.size():
		if g2.is_real(i) and not g2.collected(i):
			g2.collect(i, 20000 + i, 0, [])
	counter.sync(g2.total_real - g2.remaining(), g2.total_real)
	if counter.counter_text() != "%d / %d" % [real, real]:
		f.append("counter at completion: '%s', want '%d / %d'" % [counter.counter_text(), real, real])
	print("HUD counter seed %d level %d: %d real, %d mines; counter '%s'" % [SEED, LEVEL, real, mines, counter.counter_text()])
	counter.free()
	# the same path through the root HUD element
	var hud = HudScript.new()
	hud.sync({"gifts_collected": real, "gifts_total": real})
	if hud.gift_counter.counter_text() != "%d / %d" % [real, real]:
		f.append("root HUD counter: '%s', want '%d / %d'" % [hud.gift_counter.counter_text(), real, real])
	hud.free()


# ---- the void charge pips -----------------------------------------------------

func _test_void_pips(f: Array[String]) -> void:
	var pips = VoidPipsScript.new()
	pips.set_charges(2, 2)
	if pips.pip_count() != 2 or pips.filled_count() != 2 or pips.hollow_count() != 0:
		f.append("pips at 2 charges: %d pips, %d filled, %d hollow; want 2/2/0"
				% [pips.pip_count(), pips.filled_count(), pips.hollow_count()])
	pips.set_charges(1, 2)
	if pips.pip_count() != 2 or pips.filled_count() != 1 or pips.hollow_count() != 1:
		f.append("pips at 1 charge: %d pips, %d filled, %d hollow; want 2/1/1"
				% [pips.pip_count(), pips.filled_count(), pips.hollow_count()])
	pips.set_charges(0, 2)
	if pips.pip_count() != 2 or pips.filled_count() != 0 or pips.hollow_count() != 2:
		f.append("pips at 0 charges: %d pips, %d filled, %d hollow; want 2/0/2"
				% [pips.pip_count(), pips.filled_count(), pips.hollow_count()])
	# Hungry Void: exactly one pip (D-052)
	var ctl = ControllerScript.new()
	ctl.setup("dasher", ControllerScript.load_constants())
	ctl.set_charge_cap(1)
	if ctl.charge_cap != 1 or ctl.charges != 1:
		f.append("Hungry Void: cap %d charges %d, want 1/1" % [ctl.charge_cap, ctl.charges])
	pips.set_charges(ctl.charges, ctl.charge_cap)
	if pips.pip_count() != 1:
		f.append("Hungry Void: %d pips, want exactly 1" % pips.pip_count())
	if pips.filled_count() != 1 or pips.hollow_count() != 0:
		f.append("Hungry Void at 1 charge: %d filled %d hollow, want 1/0" % [pips.filled_count(), pips.hollow_count()])
	ctl.charges = 0
	pips.set_charges(ctl.charges, ctl.charge_cap)
	if pips.pip_count() != 1 or pips.hollow_count() != 1:
		f.append("Hungry Void at 0 charges: %d pips %d hollow, want 1/1" % [pips.pip_count(), pips.hollow_count()])
	# through the root HUD as well
	var hud = HudScript.new()
	hud.sync({"charges": 2, "charge_cap": 2})
	if hud.void_pips.pip_count() != 2:
		f.append("root HUD pips at 2 charges: %d, want 2" % hud.void_pips.pip_count())
	hud.sync({"charges": 1, "charge_cap": 1})
	if hud.void_pips.pip_count() != 1:
		f.append("root HUD pips under Hungry Void: %d, want 1" % hud.void_pips.pip_count())
	hud.free()
	# Last Light icon states (section 3.1): lit armed / dim at 0 / grey spent
	pips.set_last_light("lit")
	if pips.last_light_state() != "lit":
		f.append("Last Light state: %s, want lit" % pips.last_light_state())
	pips.set_last_light("bogus")
	if pips.last_light_state() != "grey":
		f.append("Last Light with a bogus state: %s, want grey (fail-safe)" % pips.last_light_state())
	pips.set_last_light("dim")
	if pips.last_light_state() != "dim":
		f.append("Last Light state: %s, want dim" % pips.last_light_state())
	pips.free()
	# the controller drives lit/dim/grey (hud_last_light)
	var ctl2 = ControllerScript.new()
	ctl2.setup("dasher", ControllerScript.load_constants())
	ctl2.charges = 1
	if ctl2.hud_last_light() != "lit":
		f.append("controller Last Light at 1 charge: %s, want lit" % ctl2.hud_last_light())
	ctl2.charges = 0
	if ctl2.hud_last_light() != "dim":
		f.append("controller Last Light at 0 charges: %s, want dim" % ctl2.hud_last_light())
	ctl2.last_light_spent = true
	if ctl2.hud_last_light() != "grey":
		f.append("controller Last Light once spent: %s, want grey" % ctl2.hud_last_light())


# ---- the rest of the section 14 element set ------------------------------------

func _test_element_set(f: Array[String]) -> void:
	var purse = PurseChainScript.new()
	purse.sync(14900, 1.5)
	if purse.purse_text() != "149.00  1.50x":
		f.append("purse chain format: '%s', want '149.00  1.50x'" % purse.purse_text())
	purse.sync(200, 1.0)
	if purse.purse_text() != "2.00  1.00x":
		f.append("purse chain format at open: '%s', want '2.00  1.00x'" % purse.purse_text())
	purse.free()
	var ab = AbilityCooldownScript.new()
	ab.sync("dasher", 1.5, 3.0)
	if ab.is_ready():
		f.append("dasher ability reported ready mid cooldown")
	ab.sync("dasher", 0.0, 3.0)
	if not ab.is_ready():
		f.append("dasher ability not ready at 0.0 remaining")
	ab.sync("athletic", 0.0, 3.0)
	if ab.visible:
		f.append("athletic ability element visible; the class has no active ability")
	ab.free()
	var rows = IconRowsScript.new()
	rows.set_curses([{"id": "cold_start", "stacks": 2}])
	rows.set_upgrades([{"id": "long_reach", "stacks": 1}])
	if rows.curse_count() != 1 or rows.upgrade_count() != 1:
		f.append("icon rows counts: curses %d upgrades %d, want 1/1" % [rows.curse_count(), rows.upgrade_count()])
	if rows.is_collapsed():
		f.append("icon rows start collapsed; want expanded")
	rows.toggle_collapsed()
	if not rows.is_collapsed():
		f.append("icon rows did not collapse on Tab")
	rows.toggle_collapsed()
	if rows.is_collapsed():
		f.append("icon rows did not re-expand on Tab")
	rows.free()
	var roster = EnemyRosterScript.new()
	roster.set_roster([{"id": "kiwi_cat", "count": 2}, {"id": "coil", "count": 1}, {"id": "seal", "count": 0}])
	if roster.roster_count() != 2:
		f.append("roster shows %d entries, want 2 (count 0 entries hidden)" % roster.roster_count())
	if roster.count_for("kiwi_cat") != 2:
		f.append("roster count for kiwi_cat: %d, want 2" % roster.count_for("kiwi_cat"))
	roster.free()
	# diegetic danger text: the table and the TBD fallback
	if DangerTextScript.spawn_line("kiwi_cat") != "THE KIWI CAT SHALL FOLLOW":
		f.append("danger line kiwi_cat: '%s'" % DangerTextScript.spawn_line("kiwi_cat"))
	if DangerTextScript.spawn_line("YOU?!") != "YOU SHALL ECHO":
		f.append("danger line YOU?: '%s'" % DangerTextScript.spawn_line("YOU?!"))
	if DangerTextScript.spawn_line("gift larper") != "THE GIFT LARPER SHALL PRETEND":
		f.append("danger line with a space: '%s'" % DangerTextScript.spawn_line("gift larper"))
	if DangerTextScript.spawn_line("something_unknown") != "TBD SHALL ARRIVE":
		f.append("unknown danger line: '%s', want 'TBD SHALL ARRIVE'" % DangerTextScript.spawn_line("something_unknown"))
	# run-over screen: killer / code resolution (death.gd absent - event-sourced)
	var ro = RunOverScript.new()
	if ro.killer_name("D-MINE", "gift_larper") != "gift Larper (Tripmine)":
		f.append("run-over raw id killer: '%s'" % ro.killer_name("D-MINE", "gift_larper"))
	if ro.killer_name("D-MINE", "") != "gift Larper (Tripmine)":
		f.append("run-over code fallback: '%s'" % ro.killer_name("D-MINE", ""))
	if ro.killer_name("D-VOID", "") != "The Void":
		f.append("run-over void killer: '%s'" % ro.killer_name("D-VOID", ""))
	if ro.killer_name("D-CURSE:cold_start", "") != "curse: cold_start":
		f.append("run-over curse killer: '%s'" % ro.killer_name("D-CURSE:cold_start", ""))
	if not ro.is_curse_death("D-CURSE:cold_start") or ro.is_curse_death("D-MINE"):
		f.append("run-over curse predicate broken")
	if not ro.is_void_death("D-VOID") or ro.is_void_death("D-MINE"):
		f.append("run-over void predicate broken")
	ro.show_run_over({"code": "D-MINE", "killer": "gift_larper", "level": 25,
			"purse_centi": 14900, "charges": 1})
	if not ro.visible:
		f.append("run-over screen not visible after show_run_over")
	ro.hide_run_over()
	if ro.visible:
		f.append("run-over screen still visible after hide_run_over")
	ro.free()
