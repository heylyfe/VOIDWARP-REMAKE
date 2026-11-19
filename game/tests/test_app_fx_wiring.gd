extends RefCounted
#
# APP-FX wiring test (headless): the enemy presentation layer is FED by the real run
# loop. Every view below existed and was tested in isolation, and nothing in app/ fed
# it - attacks landed with no ring and no sound, projectiles were invisible, the
# straggler beam / danger text / blur / respawn rim / cooldown bar / icon rows never
# moved. Each leg builds a real level through world.build() and drives world.step();
# nothing here calls a view directly, so an unfed view fails its leg.
#
#   leg 1 telegraphs: a probe enemy (spawned through the runtime's own spawn_at) fires
#         real api.telegraph calls - a circle patch, a ring, a box and a line - and the
#         telegraph view draws one element per live drawable tell, plays a cue for each
#         (a known kind resolves to its file, an unknown kind beeps), grows the fill
#         over the lifetime and removes the element the tick the tell expires.
#   leg 2 projectiles: rt.projectiles (api.spawn_projectile) + a row's "shots" + a
#         row's descending "det" are all drawn, at the sim's positions.
#   leg 3 straggler beam: collecting real gifts until <= 20% remain lights one beam per
#         straggler id the sim reports.
#   leg 4 danger text: the planned enemy's enemy_spawn raises its spawn line.
#   leg 5 screen blur: a sim screen_blur event (the eject's) starts the HUD blur.
#   leg 6 respawn: a void fall + respawn shows the reappear and the invulnerability rim.
#   leg 7 ability cooldown: a dash cooldown reaches the HUD bar (not READY).
#   leg 8 icon rows: the ledger's held curses / owned upgrades reach the rows.

const WorldScript := preload("res://app/world.gd")
const RT := preload("res://sim/enemy_runtime.gd")
const TelegraphViewScript := preload("res://view/vfx/telegraph_view.gd")

const SEED := 1
const LEVEL := 1
const DT := 1.0 / 60.0


# The probe enemy: fires its scripted tells on fixed ticks after spawning. Contact
# never kills (it is parked 40 u above the player), so the run cannot end mid-test.
class ProbeBehavior:
	extends RT.EnemyBehavior

	var script_rows: Array = []   # [{"at": age, "do": Callable(row, api)}]
	var age := 0

	func tick(row: Dictionary, api, _dt_ticks: int) -> void:
		for s in script_rows:
			if int(s["at"]) == age:
				(s["do"] as Callable).call(row, api)
		age += 1


func run() -> Array[String]:
	var f: Array[String] = []
	_leg_telegraphs_and_projectiles(f)
	_leg_straggler(f)
	_leg_danger_text(f)
	_leg_blur_respawn_hud(f)
	return f


func _ledger(votes: Dictionary) -> Dictionary:
	return {"class": "dasher", "votes": votes, "curses": {"aftershock": 1},
			"stacks": {"bargain": 2}, "purse": 0}


func _build(f: Array[String], tag: String, votes: Dictionary = {}):
	var world = WorldScript.new()
	if not world.build(SEED, LEVEL, _ledger(votes)):
		f.append("%s: world failed to build level %d seed %d" % [tag, LEVEL, SEED])
		world.free()
		return null
	return world


func _drop(world) -> void:
	world.teardown()
	world.free()


func _probe(world, rows: Array) -> Dictionary:
	var beh := ProbeBehavior.new()
	beh.script_rows = rows
	var c = world.ctl
	# a shipped id, so the billboard pass finds a real sprite sheet (the behavior is ours)
	var cfg := {"contact_kill": false, "id": "kiwi_cat", "name": "FX PROBE"}
	return world.rt.spawn_at("kiwi_cat", "FX PROBE", beh, cfg,
			Vector3(float(c.x) + 3.0, float(c.y) + 40.0, float(c.z)))


# ---- legs 1 + 2: telegraphs (+ cues) and projectiles ----------------------------------------

func _leg_telegraphs_and_projectiles(f: Array[String]) -> void:
	var world = _build(f, "leg 1")
	if world == null:
		return
	var c = world.ctl
	var px := float(c.x)
	var py := float(c.y)
	var pz := float(c.z)
	var fire := func(row: Dictionary, api) -> void:
		api.telegraph("teleport", {"shape": "circle", "cx": px + 5.0, "cz": pz + 5.0,
				"r": 2.0, "y0": py, "y1": py}, 30)
		api.telegraph("zz_unknown_ring", {"shape": "ring", "cx": px - 5.0, "cz": pz,
				"r0": 1.0, "r1": 2.0, "y0": py}, 30)
		api.telegraph("zz_unknown_box", {"shape": "box", "x0": px, "z0": pz + 8.0,
				"x1": px + 2.0, "z1": pz + 10.0, "y0": py}, 20)
		api.telegraph("strings_line", {"shape": "circle", "cx": px, "cz": pz, "r": 0.0,
				"line": [px, py + 1.0, pz, px + 10.0, py + 1.0, pz]}, 40)
		api.telegraph("meow", {"shape": "circle", "cx": px, "cz": pz, "r": 0.0}, 30)
		api.telegraph("coil_ring", {"shape": "circle", "cx": px + 9.0, "cz": pz - 9.0,
				"r": 3.0, "y0": py, "y1": py}, 30)
		api.spawn_projectile({"name": "FX PROBE", "x": px + 6.0, "y": py + 30.0, "z": pz,
				"vx": 0.0, "vy": 0.0, "vz": 0.0, "r": 0.3, "life_ticks": 300})
		row["shots"] = [{"x": px - 6.0, "y": py + 30.0, "z": pz}]
		row["phase"] = "lock"
		row["det"] = {"x": px, "y": py + 25.0, "z": pz - 6.0}
	_probe(world, [{"at": 0, "do": fire}])
	world.step(DT)
	var tv = world.telegraph_view
	if tv == null:
		f.append("leg 1: build() added no telegraph view")
		_drop(world)
		return
	# circle + ring + box + line drawn; the r = 0 meow is sound-only; coil_ring is coil's
	if int(tv.shown_count()) != 4:
		f.append("leg 1: telegraph view shows %d elements after the tells fired, want 4 "
				% int(tv.shown_count()) + "(circle, ring, box, line)")
	if world.coil_view == null or int(world.coil_view.ring_count()) != 1:
		f.append("leg 1: coil's landing ring not fed (coil view %s)" % str(world.coil_view))
	var cues: Array = []
	for e in tv.cue_log:
		cues.append(str(e["cue"]))
	for want in ["thicc_ben_chime", "keystroke_tick", "meow", "isagi_gunshot", "string_sweep"]:
		if not cues.has(want):
			f.append("leg 1: cue '%s' never played (log %s)" % [want, str(cues)])
	if cues.count("beep") != 2:
		f.append("leg 1: the two unknown kinds should each beep, log %s" % str(cues))
	# 7: the four above, the two unknown-kind beeps, and Claude's strings cue (the audio
	# layer announces the strings_line telegraph - PARKED row 14). coil_ring rides its own
	# event, so it is not in this log.
	if cues.has("") or cues.size() != 7:
		f.append("leg 1: want exactly 7 cues (coil_ring rides its own event), got %s" % str(cues))
	var fill0 := _circle_fill(tv)
	# leg 2: the projectile, the row's shot and the row's descending missile
	var pv = world.projectile_view
	if pv == null or int(pv.shown_count()) != 3:
		f.append("leg 2: projectile view shows %s, want 3 (ball + shot + missile)"
				% (str(pv.shown_count()) if pv != null else "no view"))
	elif pv._pool[0].position.distance_to(Vector3(px + 6.0, py + 30.0, pz)) > 0.01:
		f.append("leg 2: the ball is drawn at %s, sim at %s" % [str(pv._pool[0].position),
				str(Vector3(px + 6.0, py + 30.0, pz))])
	for _i in range(15):
		world.step(DT)
	var fill1 := _circle_fill(tv)
	if not (fill1 > fill0 + 0.3):
		f.append("leg 1: the circle fill did not grow with the telegraph (%.3f -> %.3f)"
				% [fill0, fill1])
	for _i in range(5):
		world.step(DT)
	if int(tv.shown_count()) != 3:
		f.append("leg 1: the 20-tick box should be gone at tick 21, shown %d"
				% int(tv.shown_count()))
	for _i in range(25):
		world.step(DT)
	if int(tv.shown_count()) != 0:
		f.append("leg 1: every tell expired, the view still shows %d" % int(tv.shown_count()))
	if int(world.coil_view.ring_count()) != 0:
		f.append("leg 1: coil ring outlived its telegraph")
	_drop(world)


func _circle_fill(tv) -> float:
	for k in tv._nodes.keys():
		var fill = tv._nodes[k].get("fill", null)
		if fill != null:
			return float((fill as MeshInstance3D).scale.x)
	return -1.0


# ---- leg 3: the straggler beam ---------------------------------------------------------------

func _leg_straggler(f: Array[String]) -> void:
	var world = _build(f, "leg 3")
	if world == null:
		return
	var g: RefCounted = world.lstate.gifts
	world.step(DT)
	if world.straggler_beam == null:
		f.append("leg 3: build() added no straggler beam")
		_drop(world)
		return
	if int(world.straggler_beam._beams.size()) != 0:
		f.append("leg 3: beams lit before the last 20%% (%d)" % world.straggler_beam._beams.size())
	# collect real gifts through the sim until the straggler set opens (one left at least)
	var ev: Array = []
	for i in g.slots.size():
		if not g.straggler_ids().is_empty() or int(g.remaining()) <= 1:
			break
		if bool(g.is_real(i)) and not bool(g.collected(i)):
			g.collect(i, int(world.lstate.tick), 0, ev)
	var want: Array = g.straggler_ids()
	if want.is_empty():
		f.append("leg 3: could not open the straggler set (remaining %d of %d)"
				% [int(g.remaining()), int(g.total_real)])
		_drop(world)
		return
	world.step(DT)
	want = g.straggler_ids()
	var beams: Dictionary = world.straggler_beam._beams
	if beams.size() != want.size():
		f.append("leg 3: %d beams for %d straggler ids" % [beams.size(), want.size()])
	for id in want:
		if not beams.has(id):
			f.append("leg 3: straggler slot %s has no beam" % str(id))
	_drop(world)


# ---- leg 4: diegetic danger text -------------------------------------------------------------

func _leg_danger_text(f: Array[String]) -> void:
	var world = _build(f, "leg 4", {"kiwi_cat": 1})
	if world == null:
		return
	var dt_node = world.danger_text
	if dt_node == null:
		f.append("leg 4: build() added no danger text")
		_drop(world)
		return
	var seen := false
	for _i in range(480):
		world.step(DT)
		if int(dt_node.line_count()) > 0:
			seen = true
			break
		if bool(world.ctl.dead):
			break
	if not seen:
		f.append("leg 4: the kiwi cat spawned (%d enemies) but no danger line rose"
				% world.rt.enemies.size())
	else:
		var want := str(dt_node.spawn_line("kiwi_cat"))
		if not dt_node.line_texts().has(want):
			f.append("leg 4: danger lines %s, want '%s'" % [str(dt_node.line_texts()), want])
		# the 4.0 s life runs on the sim clock
		for _i in range(245):
			if bool(world.ctl.dead):
				break
			world.step(DT)
		if not bool(world.ctl.dead) and int(dt_node.line_count()) != 0:
			f.append("leg 4: the danger line outlived its 4.0 s (%d left)" % dt_node.line_count())
	_drop(world)


# ---- legs 5-8: blur, respawn, ability cooldown, icon rows -------------------------------------

func _leg_blur_respawn_hud(f: Array[String]) -> void:
	var world = _build(f, "leg 5")
	if world == null:
		return
	var blur := func(_row: Dictionary, api) -> void:
		api.rt.events.append({"e": "screen_blur", "ticks": 180, "tick": int(api.rt.tick),
				"player": 0, "source": "fx_probe"})
	_probe(world, [{"at": 0, "do": blur}])
	world.ctl.dash_cd = 2.0
	world.step(DT)
	# leg 5
	var sb = world.screen_blur
	if sb == null or not bool(sb.active()) or float(sb.strength()) < 0.99:
		f.append("leg 5: the screen_blur event did not start the blur (%s)"
				% (("active %s strength %.2f" % [str(sb.active()), sb.strength()]) if sb != null
				else "no blur node"))
	# leg 7
	var ac = world.hud.ability_cooldown
	if bool(ac.is_ready()) or float(ac.remaining) < 1.9 or float(ac.remaining) > 2.0:
		f.append("leg 7: the dash cooldown never reached the HUD (remaining %.3f, ready %s)"
				% [float(ac.remaining), str(ac.is_ready())])
	if absf(float(ac.total) - float(world.ctl.C["dash_regen"])) > 1e-6:
		f.append("leg 7: cooldown total %.3f, controller dash_regen %.3f"
				% [float(ac.total), float(world.ctl.C["dash_regen"])])
	# leg 8
	var ir = world.hud.icon_rows
	if int(ir.curse_count()) != 1 or int(ir.upgrade_count()) != 1:
		f.append("leg 8: icon rows hold %d curses / %d upgrades, want 1 / 1 from the ledger"
				% [int(ir.curse_count()), int(ir.upgrade_count())])
	elif str(ir._upgrade_items[0]["id"]) != "bargain" or int(ir._upgrade_items[0]["stacks"]) != 2:
		f.append("leg 8: upgrade row %s, want bargain x2" % str(ir._upgrade_items))
	for _i in range(200):
		world.step(DT)
	if bool(sb.active()):
		f.append("leg 5: the 180-tick blur still active after 201 ticks")
	# leg 6: a void fall -> respawn on the sim's own clock
	var rv = world.respawn_view
	if rv == null:
		f.append("leg 6: build() added no respawn view")
		_drop(world)
		return
	world.ctl.x = 10000.5
	world.ctl.y = 0.0
	world.ctl.z = 10000.5
	world.ctl.vx = 0.0
	world.ctl.vy = 0.0
	world.ctl.vz = 0.0
	world.ctl.grounded = false
	var respawned := false
	for _i in range(400):
		world.step(DT)
		if int(rv.respawn_tick()) >= 0:
			respawned = true
			break
		if bool(world.ctl.dead):
			break
	if not respawned:
		f.append("leg 6: no respawn reached the respawn view (dead %s)" % str(world.ctl.dead))
		_drop(world)
		return
	if not bool(rv.streak_visible()) or float(rv.rim_alpha()) <= 0.0:
		f.append("leg 6: respawn tick shows streak %s rim alpha %.2f"
				% [str(rv.streak_visible()), float(rv.rim_alpha())])
	var ctl_pos := Vector3(float(world.ctl.x), float(world.ctl.y), float(world.ctl.z))
	if rv.position.distance_to(ctl_pos) > 0.01:
		f.append("leg 6: reappear drawn at %s, player at %s" % [str(rv.position), str(ctl_pos)])
	var blinked_off := false
	for _i in range(40):
		world.step(DT)
		if world.player_model != null and not world.player_model.visible:
			blinked_off = true
	if world.player_model != null and not blinked_off:
		f.append("leg 6: the player model never blinked during invulnerability")
	for _i in range(40):
		world.step(DT)
	if float(rv.rim_alpha()) > 0.0 or bool(rv.rim_visible()):
		f.append("leg 6: the invulnerability rim outlived the invulnerability")
	if world.player_model != null and not world.player_model.visible:
		f.append("leg 6: the player model stayed hidden after invulnerability")
	_drop(world)
