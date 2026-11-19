extends RefCounted
#
# test_app_pause_class.gd - gap 1 (the pause) and gap 2 (the class altar), end to end:
#
#   leg A (the pause, the PROOF): ESC mid-run opens the pause overlay and freezes the run
#     (lstate.tick frozen across app._process frames); Resume (ESC again) steps it again;
#     ESC once more + Abandon ends the run the way ESC used to (MENU, world freed, menu
#     shown) - but only after the player chose it.
#   leg B (the class altar, the PROOF): PLAY shows the altar over the loading screen; a
#     pick rebuilds the not-yet-shown run with the chosen kit (ctl.kit == the pick once
#     WORLD), the pre-run lobby around it resolves with that class and the run carries the
#     pick into its ledger; a re-pick rebuilds again; the pick stream is a pure function of
#     (seed, class) - glider -> dasher -> glider redraws exactly the first glider's votes.
#   leg C (persistence + skip): the pick survives into the NEXT run (world built with it
#     before any pick), an unknown id is refused at the altar, SKIP keeps the seeded
#     replay's pick, and a pinned start_run never shows the altar at all.
#
# Headless, outside the scene tree, like test_app_flow.gd: the app node is not added to
# the SceneTree, the test calls _ready() itself and drives the world through app._process.

const AppScript := preload("res://app/app.gd")
const ControllerScript := preload("res://sim/controller.gd")

const SEED := 1
const DT := 1.0 / 60.0


func run() -> Array[String]:
	var f: Array[String] = []
	_leg_pause(f)
	_leg_class(f)
	_leg_persist(f)
	_leg_lobby_pause(f)
	return f


func _boot(f: Array[String], p_records: String):
	var app = AppScript.new()
	# I4: a test must never ratchet the player's real user://records.json.
	app.records_path = p_records
	app.start_run(SEED)
	app._ready()   # the tree is unavailable under --headless --script (test_app_flow)
	app._menu.play_requested.emit()
	_drive_to_world(f, app)
	return app


func _drive_to_world(f: Array[String], app) -> void:
	var loading = app._loading
	var guard := 0
	while app.state() == "LOADING" and loading != null and guard < 400:
		loading.advance(0.25)
		guard += 1
	if app.state() != "WORLD":
		f.append("boot: the app never reached WORLD (state=%s after %d advances)"
				% [app.state(), guard])


func _esc(app) -> void:
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	app._unhandled_input(esc)


# ---- leg A: pause freezes the world, resume steps it, abandon ends the run -----------------

func _leg_pause(f: Array[String]) -> void:
	var app = _boot(f, "user://test_app_pause_scratch.json")
	for _i in range(6):
		app._process(DT)
	if app._world == null:
		f.append("pause: no world to pause")
		app.free()
		return
	var world = app._world
	var tick_before := int(world.lstate.tick)
	_esc(app)
	if app.state() != "WORLD":
		f.append("pause: ESC mid-run left app in %s, want WORLD (the run is alive)" % app.state())
	if app._pause_overlay == null or not app._pause_overlay.is_open():
		f.append("pause: ESC mid-run did not open the pause overlay")
	if not app._paused:
		f.append("pause: the app is not frozen with the overlay open")
	for _i in range(4):
		app._process(DT)
	if int(world.lstate.tick) != tick_before:
		f.append("pause: the frozen world kept stepping (%d -> %d)"
				% [tick_before, int(world.lstate.tick)])
	# RESUME (ESC again on the open overlay): the world steps from where it stopped.
	_esc(app)
	if app._paused or (app._pause_overlay != null and app._pause_overlay.is_open()):
		f.append("pause: resume did not close the overlay / unfreeze the app")
	var tick_after := int(world.lstate.tick)
	app._process(DT)
	if int(world.lstate.tick) != tick_after + 1:
		f.append("pause: after resume the world tick went %d -> %d, want exactly +1"
				% [tick_after, int(world.lstate.tick)])
	# ABANDON (the old ESC behaviour, now only a player's choice).
	_esc(app)
	if app._pause_overlay == null or not app._pause_overlay.is_open():
		f.append("pause: ESC did not re-open the overlay before the abandon")
	app._pause_overlay.abandon_requested.emit()
	if app.state() != "MENU":
		f.append("pause: abandon left app in %s, want MENU" % app.state())
	if app._world != null:
		f.append("pause: abandon did not free the world")
	if app._menu == null or not app._menu.visible:
		f.append("pause: abandon did not show the menu")
	if app._paused:
		f.append("pause: the frozen latch survived the abandon")
	app.free()


# ---- leg B: the pick at the altar is the class the run uses -------------------------------

func _leg_class(f: Array[String]) -> void:
	var app = AppScript.new()
	app.records_path = "user://test_app_class_scratch.json"
	app.start_run(SEED)
	app._ready()
	app._menu.play_requested.emit()
	# the altar is up over the loading screen, BEFORE the run starts
	if app.state() != "LOADING":
		f.append("class: PLAY left app in %s, want LOADING" % app.state())
		app.free()
		return
	if app._class_altar == null or not app._class_altar.is_open():
		f.append("class: PLAY did not open the class altar over the loading screen")
		app.free()
		return
	var ids: Array = app._class_altar.class_ids()
	if ids.size() != int(ControllerScript.KITS.size()):
		f.append("class: the altar offers %d altars, want the %d classes"
				% [ids.size(), ControllerScript.KITS.size()])
	# pick glider: the world is rebuilt before the player ever sees it
	app._class_altar.choose("glider")
	var world = app._world
	if world == null:
		f.append("class: the pick left no world")
		app.free()
		return
	if str(world.ctl.kit) != "glider":
		f.append("class: after picking glider the run uses '%s'" % str(world.ctl.kit))
	var ledger: Dictionary = world.run_ledger()
	if str(ledger.get("class", "")) != "glider":
		f.append("class: the run's ledger carries class '%s', want glider"
				% str(ledger.get("class", "")))
	if not ledger.has("votes") or (int(ledger["hunger"]) == 0
			and (ledger["votes"] as Dictionary).is_empty()):
		f.append("class: the pre-run lobby the pick resolves does not carry a starter E pick")
	# a re-pick rebuilds again - and the pick stream is a pure function of (seed, class):
	# glider -> dasher -> glider redraws exactly the first glider's votes.
	var glider_votes: Dictionary = (ledger["votes"] as Dictionary).duplicate(true)
	app._class_altar.choose("dasher")
	if app._world == null or app._world == world or str(app._world.ctl.kit) != "dasher":
		f.append("class: re-picking dasher did not rebuild the run as dasher")
	var dasher_votes: Dictionary = (app._world.run_ledger()["votes"] as Dictionary).duplicate(true)
	app._class_altar.choose("glider")
	if app._world == null or str(app._world.ctl.kit) != "glider":
		f.append("class: re-picking glider did not rebuild the run as glider")
	var glider_again: Dictionary = (app._world.run_ledger()["votes"] as Dictionary).duplicate(true)
	if glider_again != glider_votes:
		f.append("class: glider's votes differ between picks: %s then %s"
				% [str(glider_votes), str(glider_again)])
	# the class must never re-roll the level's starter draw: the E pick is the same seeded
	# draw for every class - the choice changes the kit, nothing else about the plan.
	if dasher_votes != glider_votes:
		f.append("class: dasher's votes %s differ from glider's %s - the pick re-rolled the draw"
				% [str(dasher_votes), str(glider_votes)])
	# the run goes live with the pick: WORLD, the HUD's kit, the real controller.
	_drive_to_world(f, app)
	world = app._world
	if world == null:
		f.append("class: no world went live after the loading clock")
		app.free()
		return
	if app.state() != "WORLD" or str(world.ctl.kit) != "glider":
		f.append("class: the live run is state=%s kit='%s', want WORLD + glider"
				% [app.state(), str(world.ctl.kit)])
	if app._class_altar != null and app._class_altar.is_open():
		f.append("class: the altar is still open once the run is live")
	# two steps: the world ticks through the real glider controller, no errors
	var tick := int(world.lstate.tick)
	app._process(DT)
	app._process(DT)
	if int(world.lstate.tick) == tick:
		f.append("class: the live run does not step")
	app.free()


# ---- leg C: the pick persists into the next run; refuse + skip + the pinned contract -------

func _leg_persist(f: Array[String]) -> void:
	var app = _boot(f, "user://test_app_persist_scratch.json")
	_esc(app)   # pause
	app._pause_overlay.abandon_requested.emit()   # abandon: back to the menu
	if app.state() != "MENU":
		f.append("persist: the abandon left app in %s, want MENU" % app.state())
		app.free()
		return
	# next run: the pick (glider, from leg... this app picked nothing yet - pick now)
	app._menu.play_requested.emit()
	if app.state() != "LOADING" or app._class_altar == null:
		f.append("persist: the next PLAY did not show the altar (state=%s altar=%s)"
				% [app.state(), str(app._class_altar)])
		app.free()
		return
	app._class_altar.choose("athletic")
	_drive_to_world(f, app)
	if app._world == null or str(app._world.ctl.kit) != "athletic":
		f.append("persist: the pick did not apply to the run (kit='%s')"
				% str(app._world.ctl.kit if app._world != null else ""))
		app.free()
		return
	_esc(app)
	if app._pause_overlay == null or not app._pause_overlay.is_open():
		f.append("persist: ESC mid-run did not open the pause overlay")
		app.free()
		return
	app._pause_overlay.abandon_requested.emit()
	# the NEXT next run: built with athletic BEFORE any pick - the choice persists
	app._menu.play_requested.emit()
	if app._world == null or str(app._world.ctl.kit) != "athletic":
		f.append("persist: the next run's kit is '%s', want athletic (the pick persists)"
				% str(app._world.ctl.kit if app._world != null else ""))
		app.free()
		return
	if app._class_altar == null or not app._class_altar.is_open():
		f.append("persist: the altar did not offer over the next loading screen")
		app.free()
		return
	if app._class_altar.chosen_id() != "":
		f.append("persist: the reopened altar already carries a visit pick")
	# an unknown id is refused at the altar (only the table's rows are altars)
	app._class_altar.choose("tbd")
	if app._class_altar.chosen_id() != "":
		f.append("persist: the altar accepted an unknown class id")
	app.free()

	# SKIP: a fresh app, skip at the altar -> the seeded replay picks, the run still lives
	var app2 = AppScript.new()
	app2.records_path = "user://test_app_skip_scratch.json"
	app2.start_run(SEED)
	app2._ready()
	app2._menu.play_requested.emit()
	if app2._class_altar == null:
		f.append("skip: no altar over the fresh PLAY")
		app2.free()
		return
	app2._class_altar.choose("bogus")
	if app2._class_altar.chosen_id() != "":
		f.append("skip: the class altar accepted 'bogus'")
	app2._class_altar.skip()
	_drive_to_world(f, app2)
	if app2._world == null:
		f.append("skip: the run did not go live after SKIP")
		app2.free()
		return
	var ledger: Dictionary = app2._world.run_ledger()
	var kit := str(app2._world.ctl.kit)
	if str(ledger.get("class", "")) != kit:
		f.append("skip: the run uses '%s' but its ledger says '%s'"
				% [kit, str(ledger.get("class", ""))])
	if not ControllerScript.KITS.has(kit):
		f.append("skip: the seeded replay's class '%s' is not a kit" % kit)
	# the pinned contract: start_run never shows the altar (the bot / Retry reproduce).
	# Abandon the paused run first: start_run only starts from MENU.
	_esc(app2)
	app2._pause_overlay.abandon_requested.emit()
	app2.start_run(SEED + 1)
	if app2._class_altar != null:
		f.append("skip: a pinned start_run showed the class altar")
	app2._return_to_menu()
	app2.free()


# ---- leg D: the pause works in the lobby too ----------------------------------------------
#
# The overlay freezes whichever state is running, and it releases and restores the mouse by
# calling apply_mouse_mode() on that frozen state. world.gd answers that call; the lobby is
# the OTHER state the overlay can freeze, so it must answer it too. Without the method the
# pause raises a script error in the Antechamber and the mouse stays captured behind the
# RESUME / ABANDON buttons, which makes ABANDON unreachable by click.

func _leg_lobby_pause(f: Array[String]) -> void:
	var app = _boot(f, "user://test_app_pause_lobby_scratch.json")
	_drive_to_world(f, app)
	if app.state() != "WORLD":
		app.free()
		return
	var world = app._world
	# Walk the level to its beacon, the same way test_app_lobby.gd does.
	var g = world.lstate.gifts
	for i in g.slots.size():
		if not g.is_real(i):
			continue
		var pos: Vector3 = g.slot_pos(i)
		world.ctl.x = pos.x
		world.ctl.y = pos.y - 1.0
		world.ctl.z = pos.z
		world.ctl.vy = 0.0
		world.step(DT)
	var bp: Array = world.lv["beacon"]
	world.ctl.x = float(int(bp[0])) + 0.5
	world.ctl.y = float(int(bp[2])) * 0.5
	world.ctl.z = float(int(bp[1])) + 0.5
	world.ctl.vy = 0.0
	world.step(DT)
	if app.state() != "LOBBY":
		f.append("lobby pause: the app is in %s after the beacon, want LOBBY" % app.state())
		app.free()
		return
	var lobby = app._lobby
	if lobby == null:
		f.append("lobby pause: no lobby to pause")
		app.free()
		return
	if not lobby.has_method("apply_mouse_mode"):
		f.append("lobby pause: the lobby has no apply_mouse_mode() - the overlay's release "
				+ "call raises and the mouse stays captured behind the buttons")
		app.free()
		return
	var locked_before := bool(lobby._mouse_locked)
	_esc(app)
	if app._pause_overlay == null or not app._pause_overlay.is_open():
		f.append("lobby pause: ESC in the lobby did not open the pause overlay")
	if not app._paused:
		f.append("lobby pause: the app is not frozen with the overlay open")
	if bool(lobby._mouse_locked):
		f.append("lobby pause: the lobby mouse stayed captured behind the overlay")
	_esc(app)
	if app._paused:
		f.append("lobby pause: resume did not unfreeze the app")
	if bool(lobby._mouse_locked) != locked_before:
		f.append("lobby pause: resume did not restore the lobby's capture state")
	app.free()
