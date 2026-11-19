extends RefCounted
#
# test_app_review_fixes.gd - the three fixes from out/review_cycle2.md, one leg each:
#
#   BUG-1: a mid-run build failure ends the run through _end_run() - the records ratchet
#     and the run telemetry log is written. Two paths: the Antechamber build after a
#     level is completed, and the next-level build after the Descent Gate. Before the
#     fix both showed the menu and silently dropped the run.
#   BUG-2: _on_retry_requested is re-entrant-safe - a double activation (the RETRY
#     button grabs focus; a fast double-click or key repeat) must not tear the new
#     loading world down twice. Now the second activation early-returns; the loading
#     screen is queue_free'd, never free()'d inside the handler.
#   BUG-3: the altar's SKIP used to emit skipped that nothing connected to - a dead
#     button. SKIP now closes the altar, the same outcome as letting the pick window
#     expire: the seeded replay decides the class.
#
# Headless, outside the scene tree, like test_app_lobby.gd / test_app_death.gd: the app
# node is not added to the tree; the test calls _ready() itself and drives the world
# through app._process.

const AppScript := preload("res://app/app.gd")
const LoadingScreenScript := preload("res://app/loading_screen.gd")
const ControllerScript := preload("res://sim/controller.gd")
const RecordsScript := preload("res://core/records.gd")
const ScreenFxScript := preload("res://view/hud/screen_fx.gd")

const SEED := 2024   # distinctive: the run telemetry log is user://runs/<SEED>_0.jsonl
const DT := 1.0 / 60.0
const HOLD_TICKS := 30


func run() -> Array[String]:
	var f: Array[String] = []
	_leg_bug1_lobby_build_failure(f)
	_leg_bug1_next_level_build_failure(f)
	_leg_bug1_pre_live_failure_writes_nothing(f)
	_leg_bug2_double_activation(f)
	_leg_bug2_retry_outside_run_over_is_noop(f)
	_leg_bug2_single_retry(f)
	_leg_bug3_skip_matches_expiry(f)
	return f


# ---- helpers -------------------------------------------------------------------------------

func _drive_to_world(f: Array[String], app) -> void:
	var loading = app._loading
	var guard := 0
	while app.state() == "LOADING" and loading != null and guard < 400:
		loading.advance(0.25)
		guard += 1
	if app.state() != "WORLD":
		f.append("boot: the app never reached WORLD (state=%s after %d advances)"
				% [app.state(), guard])


func _rm(path: String) -> void:
	var dir := DirAccess.open(path.get_base_dir())
	if dir != null and dir.file_exists(path.get_file()):
		dir.remove(path.get_file())


func _walk_gifts(app) -> void:
	var world = app._world
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


func _beacon_step(app) -> void:
	var world = app._world
	if world == null:
		return
	var bp: Array = world.lv["beacon"]
	world.ctl.x = float(int(bp[0])) + 0.5
	world.ctl.y = float(int(bp[2])) * 0.5
	world.ctl.z = float(int(bp[1])) + 0.5
	world.ctl.vy = 0.0
	world.step(DT)


func _stand_at(scene, p_altar: Dictionary) -> void:
	var root: Node3D = p_altar["root"]
	scene.player.x = root.position.x
	scene.player.z = root.position.z + 2.0
	scene.player.vx = 0.0
	scene.player.vz = 0.0
	scene.player.rig.yaw_deg = 0.0


func _hold(scene, p_ticks: int) -> Dictionary:
	for _i in p_ticks:
		var res: Dictionary = scene.tick(DT, 0, 0, true)
		if int(res["select"]) != -1:
			return res
	return {}

## Walk the run through its first level into the Antechamber. Returns in LOBBY (or not).
func _play_to_lobby(f: Array[String], app) -> bool:
	app._menu.play_requested.emit()
	_drive_to_world(f, app)
	if app.state() != "WORLD":
		return false
	_walk_gifts(app)
	_beacon_step(app)
	if app.state() != "LOBBY":
		f.append("lobby: the app is in %s after the beacon, want LOBBY" % app.state())
		return false
	return true


## Hold F at the E bay's first altar until the pick lands (the gate's last seal).
func _resolve_e_bay(f: Array[String], app) -> void:
	var scene = app._lobby
	var target: Dictionary = {}
	for a in scene.hall._altars:
		if str(a["kind"]) == "offer" and str(a["bay_kind"]) == "E":
			target = a
			break
	if target.is_empty():
		f.append("lobby: no E-bay altar")
		return
	_stand_at(scene, target)
	_hold(scene, HOLD_TICKS)


## After a run ends: the records ratchet at scratch, and the run telemetry log exists.
func _expect_run_recorded(f: Array[String], scratch: String, tag: String) -> void:
	if not FileAccess.file_exists(scratch):
		f.append("%s: the scratch records file %s was never written" % [tag, scratch])
	else:
		var rec := RecordsScript.new()
		rec.load_from(scratch)
		if rec.get_best_level() < 1:
			f.append("%s: the failed run did not ratchet the records (best_level=%d)"
					% [tag, rec.get_best_level()])
	var log_path := "user://runs/%d_0.jsonl" % SEED
	if not FileAccess.file_exists(log_path):
		f.append("%s: the run telemetry log %s was not written" % [tag, log_path])


## Boot the app, drive to WORLD, kill the player with no charge left. Returns the app
## in RUN_OVER with the run-over screen open on the black-out's landing, or null.
func _boot_to_run_over(f: Array[String], scratch: String):
	var app = AppScript.new()
	app.records_path = scratch
	app.start_run(SEED)
	app._ready()
	app._menu.play_requested.emit()
	_drive_to_world(f, app)
	if app.state() != "WORLD":
		f.append("death boot: the app never reached WORLD (state=%s)" % app.state())
		app.free()
		return null
	var world = app._world
	world.ctl.charges = 0
	world.ctl.respawn_t = -1.0
	world.ctl.invuln = 0.0
	world.ctl.x = -500.0
	world.ctl.y = -41.0
	world.ctl.z = 0.0
	world.ctl.vy = -1.0
	world.ctl.grounded = false
	world.step(DT)
	if app.state() != "RUN_OVER":
		f.append("death boot: state %s after the lethal fall, want RUN_OVER" % app.state())
		app.free()
		return null
	world.hud.screen_fx.advance(ScreenFxScript.BLACKOUT_TICKS)
	if app._run_over == null:
		f.append("death boot: no run-over screen after the black-out")
		app.free()
		return null
	return app


func _rm_scratch_and_log(scratch: String) -> void:
	_rm(scratch)
	_rm("user://runs/%d_0.jsonl" % SEED)

# ---- BUG-1: a build failure mid-run ends the run through _end_run() ------------------------

## Path 1: the Antechamber fails to build right after the level is completed.
func _leg_bug1_lobby_build_failure(f: Array[String]) -> void:
	var scratch := "user://test_review_fixes_b1l_scratch.json"
	_rm_scratch_and_log(scratch)
	var app = AppScript.new()
	app.records_path = scratch
	app.start_run(SEED)
	app._ready()
	app._menu.play_requested.emit()
	_drive_to_world(f, app)
	if app.state() != "WORLD":
		f.append("bug1 lobby: never reached WORLD (state=%s)" % app.state())
		app.free()
		return
	_walk_gifts(app)
	# the Antechamber build fails at the beacon step: level_completed -> _enter_lobby
	app.force_build_failure = true
	_beacon_step(app)
	if app.state() != "MENU":
		f.append("bug1 lobby: state %s after the failed build, want MENU" % app.state())
	if app._lobby != null:
		f.append("bug1 lobby: the failed lobby was not released")
	if app._world != null:
		f.append("bug1 lobby: the world survived the level completion")
	_expect_run_recorded(f, scratch, "bug1 lobby")
	app.free()
	_rm_scratch_and_log(scratch)


## Path 2: the next level fails to build after the player walks into the Descent Gate.
func _leg_bug1_next_level_build_failure(f: Array[String]) -> void:
	var scratch := "user://test_review_fixes_b1n_scratch.json"
	_rm_scratch_and_log(scratch)
	var app = AppScript.new()
	app.records_path = scratch
	app.start_run(SEED)
	app._ready()
	if not _play_to_lobby(f, app):
		app.free()
		_rm_scratch_and_log(scratch)
		return
	_resolve_e_bay(f, app)
	var scene = app._lobby
	if scene == null or not scene.gate_open:
		f.append("bug1 next: the gate is still sealed after the E-bay pick")
		app.free()
		_rm_scratch_and_log(scratch)
		return
	# the next-level build fails at the gate: exited -> _on_lobby_exited -> _build_world
	app.force_build_failure = true
	scene.player.x = 0.0
	scene.player.z = -8.5
	scene.tick(DT, 0, 0, false)
	if app.state() != "MENU":
		f.append("bug1 next: state %s after the failed build, want MENU" % app.state())
	if app._lobby != null:
		f.append("bug1 next: the exited lobby was not released")
	if app._world != null:
		f.append("bug1 next: a world survived the failed build")
	_expect_run_recorded(f, scratch, "bug1 next")
	app.free()
	_rm_scratch_and_log(scratch)


## Negative control: a build failure before the run went live writes nothing.
func _leg_bug1_pre_live_failure_writes_nothing(f: Array[String]) -> void:
	var scratch := "user://test_review_fixes_b1p_scratch.json"
	_rm_scratch_and_log(scratch)
	var app = AppScript.new()
	app.records_path = scratch
	app.force_build_failure = true   # armed before the first build: the run never lives
	app.start_run(SEED)
	app._ready()
	app._menu.play_requested.emit()
	if app.state() != "MENU":
		f.append("bug1 n/c: state %s after a pre-live build failure, want MENU" % app.state())
	if FileAccess.file_exists(scratch):
		var rec := RecordsScript.new()
		rec.load_from(scratch)
		if rec.get_best_level() > 0 or rec.get_best_purse() > 0:
			f.append("bug1 n/c: a pre-live failure ratcheted the records (level=%d purse=%d)"
					% [rec.get_best_level(), rec.get_best_purse()])
	if FileAccess.file_exists("user://runs/%d_0.jsonl" % SEED):
		f.append("bug1 n/c: a pre-live failure wrote a run telemetry log")
	app.free()
	_rm_scratch_and_log(scratch)

# ---- BUG-2: RETRY is re-entrant-safe -------------------------------------------------------

## The double activation: two _on_retry_requested calls in a row.
func _leg_bug2_double_activation(f: Array[String]) -> void:
	var scratch := "user://test_review_fixes_b2d_scratch.json"
	_rm_scratch_and_log(scratch)
	var app = _boot_to_run_over(f, scratch)
	if app == null:
		_rm_scratch_and_log(scratch)
		return
	app._on_retry_requested()
	var world_after_first = app._world
	app._on_retry_requested()   # the RETRY button holds focus; this must be a no-op
	if app._world != world_after_first:
		f.append("bug2: the second activation tore down and rebuilt the world")
	if app.state() == "WORLD" and app._world == null:
		f.append("bug2: the double activation left STATE_WORLD with no world")
	var screens := 0
	for c in app.get_children():
		# queue_free is deferred and nothing flushes deletions outside the tree, so a
		# screen freed earlier in the test still sits in children(): count only the
		# ones not queued for deletion (the live ones, the leak).
		if c.get_script() == LoadingScreenScript and not c.is_queued_for_deletion():
			screens += 1
	if screens != 1:
		f.append("bug2: %d live loading screens under the app after a double activation, want 1"
				% screens)
	if app._loading == null:
		f.append("bug2: _loading is null after the double activation")
	if app.state() != "LOADING" and app.state() != "WORLD":
		f.append("bug2: the double activation left state=%s, want LOADING or WORLD"
				% app.state())
	if app._run_over != null:
		f.append("bug2: the run-over screen survived the retry")
	_drive_to_world(f, app)
	if app.state() != "WORLD" or app._world == null:
		f.append("bug2: the surviving loading screen never reached WORLD (state=%s)"
				% app.state())
	elif app.run_seed() != SEED:
		f.append("bug2: the retry used seed %d, want the same seed %d"
				% [app.run_seed(), SEED])
	app.free()
	_rm_scratch_and_log(scratch)


## Negative control: RETRY outside RUN_OVER (a focused button, a key repeat) is a no-op.
func _leg_bug2_retry_outside_run_over_is_noop(f: Array[String]) -> void:
	var scratch := "user://test_review_fixes_b2n_scratch.json"
	_rm_scratch_and_log(scratch)
	var app = AppScript.new()
	app.records_path = scratch
	app.start_run(SEED)
	app._ready()
	app._on_retry_requested()   # MENU: must do nothing at all
	if app.state() != "MENU":
		f.append("bug2 n/c: retry in MENU left state=%s, want MENU" % app.state())
	if app._loading != null:
		f.append("bug2 n/c: retry in MENU spun up a loading screen")
	if app._world != null:
		f.append("bug2 n/c: retry in MENU built a world")
	if app.run_seed() != SEED:
		f.append("bug2 n/c: retry in MENU re-pinned the seed to %d, want %d"
				% [app.run_seed(), SEED])
	app.free()
	_rm(scratch)


## The single-call path still works: Retry lands straight in the retried run.
func _leg_bug2_single_retry(f: Array[String]) -> void:
	var scratch := "user://test_review_fixes_b2s_scratch.json"
	_rm_scratch_and_log(scratch)
	var app = _boot_to_run_over(f, scratch)
	if app == null:
		_rm_scratch_and_log(scratch)
		return
	app._on_retry_requested()
	if app.state() != "LOADING":
		f.append("bug2 retry: state %s right after retry, want LOADING" % app.state())
	if app._world == null:
		f.append("bug2 retry: retry built no world")
	if app.run_seed() != SEED:
		f.append("bug2 retry: retry used seed %d, want the same seed %d"
				% [app.run_seed(), SEED])
	_drive_to_world(f, app)
	if app.state() != "WORLD" or app._world == null:
		f.append("bug2 retry: the retried run never reached WORLD (state=%s)" % app.state())
	if app._menu != null and app._menu.visible:
		f.append("bug2 retry: retry showed the menu; it must go straight into the run")
	app.free()
	_rm_scratch_and_log(scratch)

# ---- BUG-3: SKIP is not a dead button ------------------------------------------------------

## Drive one PLAY to WORLD, optionally pressing SKIP first. Returns the kit / ledger class.
func _altar_run(f: Array[String], scratch: String, use_skip: bool) -> Dictionary:
	_rm(scratch)
	var app = AppScript.new()
	app.records_path = scratch
	app.start_run(SEED)
	app._ready()
	app._menu.play_requested.emit()
	if app._class_altar == null:
		f.append("skip leg: PLAY did not open the class altar")
		app.free()
		return {}
	var skipped := [false]
	var chose := [""]
	app._class_altar.skipped.connect(func() -> void: skipped[0] = true)
	app._class_altar.class_chosen.connect(func(id: String) -> void: chose[0] = id)
	if use_skip:
		app._class_altar.skip()
		if not skipped[0]:
			f.append("skip leg: skip() emitted no skipped (the button is dead)")
		if app._class_altar.is_open():
			f.append("skip leg: the altar is still open after SKIP - the label promises it closes")
		if chose[0] != "":
			f.append("skip leg: skip() reported a pick '%s', want none" % chose[0])
	_drive_to_world(f, app)
	var out := {}
	if app._world == null:
		f.append("skip leg: the run never went live")
	else:
		out["kit"] = str(app._world.ctl.kit)
		out["ledger"] = str(app._world.run_ledger().get("class", ""))
	out["skipped"] = skipped[0]
	out["chosen"] = chose[0]
	app.free()
	_rm(scratch)
	return out


## Drive one PLAY to WORLD after an explicit pick. Returns the kit / ledger class.
func _altar_pick_run(f: Array[String], scratch: String, pick: String) -> Dictionary:
	_rm(scratch)
	var app = AppScript.new()
	app.records_path = scratch
	app.start_run(SEED)
	app._ready()
	app._menu.play_requested.emit()
	if app._class_altar == null:
		f.append("pick leg: PLAY did not open the class altar")
		app.free()
		return {}
	var chose := [""]
	app._class_altar.class_chosen.connect(func(id: String) -> void: chose[0] = id)
	app._class_altar.choose(pick)
	_drive_to_world(f, app)
	var out := {}
	if app._world == null:
		f.append("pick leg: the run never went live")
	else:
		out["kit"] = str(app._world.ctl.kit)
		out["ledger"] = str(app._world.run_ledger().get("class", ""))
	out["chosen"] = chose[0]
	app.free()
	_rm(scratch)
	return out


func _leg_bug3_skip_matches_expiry(f: Array[String]) -> void:
	var via_skip := _altar_run(f, "user://test_review_fixes_b3skip_scratch.json", true)
	var via_expiry := _altar_run(f, "user://test_review_fixes_b3exp_scratch.json", false)
	if via_skip.is_empty() or via_expiry.is_empty():
		return
	if str(via_skip["kit"]) != str(via_expiry["kit"]):
		f.append("skip leg: SKIP kit '%s' != the expired window's kit '%s'"
				% [via_skip["kit"], via_expiry["kit"]])
	if str(via_skip["ledger"]) != str(via_expiry["ledger"]):
		f.append("skip leg: SKIP ledger class '%s' != the expired window's '%s'"
				% [via_skip["ledger"], via_expiry["ledger"]])
	if str(via_skip["ledger"]) != str(via_skip["kit"]):
		f.append("skip leg: the SKIP run's kit '%s' does not match its ledger class '%s'"
				% [via_skip["kit"], via_skip["ledger"]])
	if not ControllerScript.KITS.has(str(via_skip["kit"])):
		f.append("skip leg: the SKIP run's kit '%s' is not a kit" % str(via_skip["kit"]))
	# negative control: an explicit pick yields a different outcome than SKIP
	var seeded_kit := str(via_skip["kit"])
	var other := ""
	for id in ControllerScript.KITS:
		if str(id) != seeded_kit:
			other = str(id)
			break
	if other == "":
		f.append("skip leg: no second class to pick as the negative control")
		return
	var picked := _altar_pick_run(f, "user://test_review_fixes_b3pick_scratch.json", other)
	if picked.is_empty():
		return
	if str(picked["kit"]) != other:
		f.append("skip leg n/c: picking '%s' yielded kit '%s'" % [other, picked["kit"]])
	if str(picked["kit"]) == seeded_kit:
		f.append("skip leg n/c: the explicit pick did not change the run's kit")
	if str(picked["chosen"]) != other:
		f.append("skip leg n/c: choose('%s') emitted class_chosen '%s'" % [other, picked["chosen"]])
