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
const ScreenFxScript := preload("res://view/hud/screen_fx.gd")
const CartographerMapScript := preload("res://view/hud/cartographer_map.gd")

const SEED := 42
const LEVEL := 25


func run() -> Array[String]:
	var f: Array[String] = []
	_test_counter_level_25_seed(f)
	_test_void_pips(f)
	_test_element_set(f)
	_test_cartographer_map(f)
	_test_t086_animations(f)
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
	var purse_icon := false
	var stack: Array = purse.get_children()
	while not stack.is_empty():
		var c = stack.pop_back()
		if c is TextureRect and c.texture != null:
			purse_icon = true
		stack.append_array(c.get_children())
	if not purse_icon:
		f.append("purse chain shows no gold balance icon (a TextureRect with a texture) left of the purse text")
	purse.free()
	var ab = AbilityCooldownScript.new()
	ab.sync("dasher", 1.5, 3.0)
	if ab.is_ready():
		f.append("dasher ability reported ready mid cooldown")
	if ab.seconds_text() != "1.5s":
		f.append("dasher cooldown text mid cooldown: '%s', want '1.5s' (the real number, not READY)"
				% ab.seconds_text())
	if absf(ab.fraction() - 0.5) > 1e-6:
		f.append("dasher cooldown bar at 1.5 of 3.0 s: %f, want 0.5 charged" % ab.fraction())
	ab.sync("glider", 1.5, 3.0)   # glider polarity: remaining IS the airtime left
	if ab.is_ready():
		f.append("glider ability reported ready with 1.5 s of 3.0 s of airtime left")
	if absf(ab.fraction() - 0.5) > 1e-6:
		f.append("glider energy bar at half airtime: %f, want 0.5" % ab.fraction())
	ab.sync("glider", 3.0, 3.0)
	if not ab.is_ready():
		f.append("glider ability not ready at full energy")
	ab.sync("dasher", 0.0, 3.0)
	if not ab.is_ready():
		f.append("dasher ability not ready at 0.0 remaining")
	ab.sync("athletic", 0.0, 3.0)
	if ab.visible:
		f.append("athletic ability element visible; the class has no active ability")
	ab.free()
	# the documented defaults (0.0 / 3.0) keep READY when a sync omits the ability keys
	var hud = HudScript.new()
	hud.sync({})
	if not hud.ability_cooldown.is_ready() or hud.ability_cooldown.seconds_text() != "READY":
		f.append("root HUD with no ability keys: '%s', want READY (0.0 / 3.0 defaults)"
				% hud.ability_cooldown.seconds_text())
	hud.free()
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
	# a rebuild must not leave the previous cells in the row (queue_free is end-of-frame)
	rows.set_curses([{"id": "cold_start", "stacks": 2}])
	if rows._curses_row.get_child_count() != 1:
		f.append("icon rows hold %d curse cells for 1 curse" % rows._curses_row.get_child_count())
	rows.free()
	var roster = EnemyRosterScript.new()
	roster.set_roster([{"id": "kiwi_cat", "count": 2}, {"id": "coil", "count": 1}, {"id": "seal", "count": 0}])
	if roster.roster_count() != 2:
		f.append("roster shows %d entries, want 2 (count 0 entries hidden)" % roster.roster_count())
	if roster.count_for("kiwi_cat") != 2:
		f.append("roster count for kiwi_cat: %d, want 2" % roster.count_for("kiwi_cat"))
	# the roster is re-sent every tick: a rebuild must not stack the stale cells
	roster.set_roster([{"id": "kiwi_cat", "count": 2}, {"id": "coil", "count": 1}, {"id": "seal", "count": 0}])
	if roster._row.get_child_count() != 2:
		f.append("roster holds %d cells for 2 entries" % roster._row.get_child_count())
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


# ---- the Cartographer map: sync feeds facing and the sim's own gift/mine state ----

func _test_cartographer_map(f: Array[String]) -> void:
	var level := {
		"tiles": [[0, 0, 0, 0, 0]],
		"pieces": [{"id": 0, "kind": 0}],
		"gifts": [{"id": 0, "x": 0, "z": 0, "y": 0, "piece": 0, "tier": 0, "occ": 0},
			{"id": 1, "x": 1, "z": 0, "y": 0, "piece": 0, "tier": 0, "occ": 1}],
		"beacon": [0, 0, 0],
	}
	var colours := {"platform": Color(0.2, 0.7, 0.7), "walkway": Color(0.2, 0.4, 0.9),
			"gift": Color(0.9, 0.8, 0.2), "mine": Color(1.0, 0.3, 0.8),
			"beacon": Color(0.5, 1.0, 0.5)}
	var foot: Dictionary = {Vector2i(0, 0): true}
	# sync hands the player's heading to the model: due east turns the arrow east
	var up := _StubMapUpgrades.new()
	up.visited = {0: foot}
	var lv := _StubMapLv.new()
	lv.level_dict = level
	lv.players = [{"x": 0.5, "z": 0.5}]
	lv.upgrades = up
	var map = CartographerMapScript.new()
	map.sync(lv, 0, 2.0, colours, 0.0)
	var east := false
	for item in map._model:
		if item.has("triangle"):
			east = float(item["triangle"][0].x) > CartographerMapScript.SIZE * 0.5
	if not east:
		f.append("cartographer map: sync dropped facing - the player arrow does not point east")
	map.sync(lv, 0, 2.0, colours)   # the default: north-up
	var north := false
	for item in map._model:
		if item.has("triangle"):
			north = float(item["triangle"][0].y) < CartographerMapScript.SIZE * 0.5
	if not north:
		f.append("cartographer map: the default facing is not up/north")
	map.free()
	# collected gifts and defused mines come off the map (the sim twin's own filter)
	var plain: int = CartographerMapScript.revealed_rows(level, foot, 0.5, 0.5).size()
	if plain != 3:
		f.append("cartographer map: %d reveal rows with no gift/mine state, want 3 (gift, mine, beacon)" % plain)
	var slots := _StubMapSlots.new()
	slots.collected_ids = [0]
	slots.consumed_ids = [1]
	var after: int = CartographerMapScript.revealed_rows(level, foot, 0.5, 0.5, slots, slots).size()
	if after != 1:
		f.append("cartographer map: %d reveal rows after 1 pickup and 1 defuse, want 1 (the beacon)" % after)


# ---- T-086: the section 2.4 stepped animations (spend/restore/free/bloom/black-out) ---

const SPEND_TICKS := 18.0
const RESTORE_TICKS := 24.0
const FREE_TICKS := 60.0
const PULSE_TICKS := 12.0
const BLOOM_TICKS := 12.0
const BLACKOUT_TICKS := 18.0
const SHATTER_TICKS := 12.0


func _test_t086_animations(f: Array[String]) -> void:
	# spend: the pip that just went hollow cracks and drains downward over 18 ticks
	var pips = VoidPipsScript.new()
	pips.set_charges(2, 2)
	pips.set_charges(1, 2)   # post-spend count: pip index 1 is the draining one
	pips.pip_spend()
	if not pips.spend_active():
		f.append("pip_spend did not start the spend animation")
	if pips.anim_progress() != 0.0:
		f.append("spend animation progress at t=0: %f, want 0.0" % pips.anim_progress())
	pips.advance(SPEND_TICKS * 0.5)
	if not pips.spend_active() or absf(pips.anim_progress() - 0.5) > 0.01:
		f.append("spend animation at mid: active=%s progress=%f, want active 0.5"
				% [pips.spend_active(), pips.anim_progress()])
	pips.advance(SPEND_TICKS * 0.5)
	if pips.spend_active():
		f.append("spend animation still active after %d ticks" % int(SPEND_TICKS))
	pips.advance(1.0)   # drained pip reads as spent (Hollow), no crash, stays spent
	if pips.filled_count() != 1 or pips.hollow_count() != 1:
		f.append("pip counts after spend animation: %d filled %d hollow, want 1/1"
				% [pips.filled_count(), pips.hollow_count()])
	# spend with nothing to spend is a no-op
	pips.set_charges(2, 2)
	pips.pip_spend()
	if pips.spend_active():
		f.append("pip_spend animated with no hollow pip")
	# restore: the first hollow pip fills upward over 24 ticks, glint included
	pips.set_charges(1, 2)
	pips.pip_restore()
	if not pips.restore_active():
		f.append("pip_restore did not start the restore animation")
	if absf(pips.filling_fraction() - 0.0) > 0.01:
		f.append("restore fill at t=0: %f, want 0.0" % pips.filling_fraction())
	pips.advance(RESTORE_TICKS * 0.5)
	if absf(pips.filling_fraction() - 0.5) > 0.01:
		f.append("restore fill at mid: %f, want ~0.5" % pips.filling_fraction())
	pips.advance(RESTORE_TICKS * 0.5)
	if pips.restore_active():
		f.append("restore animation still active after %d ticks" % int(RESTORE_TICKS))
	if not pips.glint_active():
		f.append("restore landed but the white glint tail is missing")
	pips.advance(6.0)   # glint tail is 6 ticks (D-T086-5)
	if pips.glint_active():
		f.append("glint tail still active after 6 ticks")
	# already-full restore: no fill, one pulse (2.4)
	pips.set_charges(2, 2)
	pips.pip_restore()
	if pips.restore_active():
		f.append("restore animation started with no hollow pip")
	if not pips.pulse_active():
		f.append("already-full restore did not pulse the pips")
	pips.advance(PULSE_TICKS + 1.0)
	if pips.pulse_active():
		f.append("pip pulse still active after %d ticks (must pulse ONCE)" % int(PULSE_TICKS))
	pips.pip_already_full()
	if not pips.pulse_active():
		f.append("pip_already_full did not pulse")
	pips.advance(PULSE_TICKS + 1.0)
	# free fall (Field Dressing): pip flashes white, stays filled, FREE tick 60 ticks
	pips.set_charges(2, 2)
	pips.pip_free_fall()
	if not pips.free_tick_active():
		f.append("pip_free_fall did not raise the FREE tick")
	if not pips.free_flash_active():
		f.append("pip_free_fall did not flash the pip white at the window start")
	pips.advance(FREE_TICKS * 0.5)
	if pips.free_flash_active():
		f.append("free fall still flashing white past its 12-tick flash (D-T086-4)")
	pips.advance(FREE_TICKS * 0.5 + 1.0)
	if pips.free_tick_active():
		f.append("FREE tick still active after %d ticks" % int(FREE_TICKS))
	if pips.filled_count() != 2:
		f.append("free fall changed the pip count: %d filled, want 2 (stays filled)" % pips.filled_count())
	# a charge spent inside the window must move the flash to the new last held pip
	pips.set_charges(2, 2)
	pips.pip_free_fall()
	pips.set_charges(1, 2)
	if pips._free_index != 0:
		f.append("FREE flash left on pip %d after a spend inside the window, want 0 (held is 1)"
				% pips._free_index)
	pips.advance(FREE_TICKS + 1.0)
	pips.set_charges(0, 2)
	pips.pip_free_fall()
	if pips.free_tick_active():
		f.append("pip_free_fall raised the FREE tick with no held charge")
	# Last Light trigger: the icon shatters over 12 ticks
	pips.last_light_trigger()
	if not pips.shatter_active():
		f.append("last_light_trigger did not start the icon shatter")
	pips.advance(SHATTER_TICKS * 0.5)
	if absf(pips.shatter_progress() - 0.5) > 0.01:
		f.append("shatter progress at mid: %f, want ~0.5" % pips.shatter_progress())
	pips.advance(SHATTER_TICKS * 0.5)
	if pips.shatter_active():
		f.append("shatter still active after %d ticks" % int(SHATTER_TICKS))
	pips.free()
	# screen_fx: the void edge flash, the 12-tick white bloom, the 18-tick black-out
	var fx = ScreenFxScript.new()
	fx.void_flash()
	if not fx.flash_active():
		f.append("void_flash did not activate the edge flash")
	fx.advance(12.0)
	if fx.flash_active():
		f.append("void edge flash still active after 12 ticks")
	fx.white_bloom()
	if not fx.bloom_active():
		f.append("white_bloom did not activate the bloom")
	fx.advance(BLOOM_TICKS * 0.5)
	if fx.bloom_alpha() <= 0.0:
		f.append("bloom alpha at mid: %f, want > 0" % fx.bloom_alpha())
	fx.advance(BLOOM_TICKS * 0.5)
	if fx.bloom_active():
		f.append("white bloom still active after %d ticks" % int(BLOOM_TICKS))
	var got := [0]
	fx.blackout_finished.connect(func() -> void: got[0] += 1)
	fx.black_out()
	if fx.blackout_alpha() != 0.0:
		f.append("black-out alpha at t=0: %f, want 0.0" % fx.blackout_alpha())
	fx.advance(BLACKOUT_TICKS * 0.5)
	if absf(fx.blackout_alpha() - 0.5) > 0.01:
		f.append("black-out alpha at mid: %f, want ~0.5" % fx.blackout_alpha())
	fx.advance(BLACKOUT_TICKS * 0.5)
	if got[0] != 1:
		f.append("blackout_finished emitted %d times, want exactly 1 (18 ticks, binding)" % got[0])
	if fx.blackout_alpha() != 1.0:
		f.append("black-out alpha at 18 ticks: %f, want 1.0 (fully black)" % fx.blackout_alpha())
	if not fx.blackout_active():
		f.append("black-out cleared itself; it must hold black until hide_blackout()")
	fx.hide_blackout()
	if fx.blackout_active() or fx.blackout_alpha() != 0.0:
		f.append("hide_blackout did not clear the black-out")
	fx.free()
	# through the root HUD: screen_fx is drawn topmost and re-emits blackout_finished
	var hud = HudScript.new()
	if hud.screen_fx == null:
		f.append("root HUD has no screen_fx overlay")
	else:
		var hud_got := [0]
		hud.blackout_finished.connect(func() -> void: hud_got[0] += 1)
		hud.death_blackout()
		hud.screen_fx.advance(BLACKOUT_TICKS)
		if hud_got[0] != 1:
			f.append("root HUD blackout_finished re-emitted %d times, want 1" % hud_got[0])
	hud.free()
	# run-over: curse deaths show the curse icon (D-CURSE:<id>), void/mine do not
	var ro = RunOverScript.new()
	ro.show_run_over({"code": "D-CURSE:cold_start", "killer": "", "level": 12,
			"purse_centi": 7300, "charges": 1})
	if ro.curse_icon_id() != "cold_start":
		f.append("curse-death icon id: '%s', want 'cold_start'" % ro.curse_icon_id())
	ro.show_run_over({"code": "D-VOID", "killer": "", "level": 12,
			"purse_centi": 7300, "charges": 0})
	if ro.curse_icon_id() != "":
		f.append("void death shows a curse icon: '%s', want none" % ro.curse_icon_id())
	ro.show_run_over({"code": "D-MINE", "killer": "gift_larper", "level": 12,
			"purse_centi": 7300, "charges": 1})
	if ro.curse_icon_id() != "":
		f.append("tripmine death shows a curse icon: '%s', want none" % ro.curse_icon_id())
	ro.free()


# ---- stubs for the map's sync path (a LevelState stand-in; no ClassDB involved) ----

class _StubMapUpgrades extends RefCounted:
	var visited: Dictionary = {}

	## Any key: this test pins sync()'s forwarding, not its ownership guard.
	func has(_role: String) -> bool:
		return true


class _StubMapLv extends RefCounted:
	var level_dict: Dictionary = {}
	var players: Array = []
	var upgrades: RefCounted = null
	var gifts: RefCounted = null
	var mines: RefCounted = null


class _StubMapSlots extends RefCounted:
	var collected_ids: Array = []
	var consumed_ids: Array = []

	func collected(i: int) -> bool:
		return collected_ids.has(i)

	func is_consumed(i: int) -> bool:
		return consumed_ids.has(i)
