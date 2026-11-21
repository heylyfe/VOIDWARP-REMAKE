extends SceneTree
#
# Death-screen screenshot tool (cycle 4 item 12): boots the REAL app (app/app.gd), starts a
# pinned run, kills the player for real, and captures the run-over screen The Master hosts.
# Each death goes through the game's own paths: an enemy kill and a tripmine kill through
# the controller's try_kill (the call every enemy hit and the mine ladder make), a void
# fall by putting the body past the kill plane over open void. The app's _process steps the
# world, plays the HUD's 18-tick black-out and opens the screen on blackout_finished. Between
# deaths the harness presses RESTART (the screen's own button), so that path is shot too.
# Windowed run - rendering needs a GPU context, never --headless:
#
#   <godot> --path game --script res://tests/shot_death.gd -- <out_dir> [seed]
#
# Writes <out_dir>/death_00_enemy.png, death_01_void.png, death_02_mine.png,
#        death_03_curse.png (a D-CURSE code through the same kill call; no shipped curse
#        kills yet, so this one only proves the screen's curse layout). When the dead
#        world's HUD layer is still drawn over the screen, each also gets a <name>_unmasked
#        twin with that layer hidden for one frame - a diagnostic of the screen's own
#        layout, NOT what the player sees; the plain shot is the verdict.
# Prints a DIAG line per shot (code, killer line, Master texture size and on-screen rect,
# both buttons' rects, the killer sprite) so a blank screen is not mistaken for a fixed one.
# Named shot_*, not test_*, so tests/run_all.gd skips it. Prints "SHOT <path>" per PNG and
# "SHOTX OK" / "SHOTX FAIL <why>"; exit 1 on failure.

const AppScript := preload("res://app/app.gd")

const SHOT_SIZE := Vector2i(1280, 720)
const RECORDS := "user://shot_death_records.json"
const KILLS := [
	["death_00_enemy", "enemy", "D-KIWI", "kiwi_cat"],
	["death_01_void", "void", "", ""],
	["death_02_mine", "enemy", "D-MINE", "gift_larper"],
	["death_03_curse", "enemy", "D-CURSE:hungry_void", "hungry_void"],
]

var _out_dir := ""
var _seed := 7
var _fail := ""
var _app: Node = null
var _covered: PackedStringArray = []   # shots where the player sees black, not the screen


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	root.size = SHOT_SIZE
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out_dir = args[0] if args.size() >= 1 else ProjectSettings.globalize_path("res://shots_death")
	if args.size() >= 2:
		_seed = int(args[1])
	if DirAccess.make_dir_recursive_absolute(_out_dir) != OK:
		_fail = "cannot create %s" % _out_dir
		_finish()
		return
	_app = AppScript.new()
	_app.records_path = RECORDS
	root.add_child(_app)
	for _i in 5:
		await process_frame
	_app.start_run(_seed)   # pinned: no class altar, straight into level 1
	for k in KILLS:
		if not await _until_state("WORLD", 15.0):
			_fail = "%s: the run never went live (state %s)" % [k[0], _app.state()]
			break
		for _i in 30:
			await process_frame   # a few live ticks: the world is really running
		_kill(str(k[1]), str(k[2]), str(k[3]))
		if not await _until_state("RUN_OVER", 5.0):
			_fail = "%s: the kill did not end the run (state %s)" % [k[0], _app.state()]
			break
		if not await _until_screen(5.0):
			_fail = "%s: the run-over screen never opened" % k[0]
			break
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 1500:
			await process_frame   # 1.5 s: long enough for any fade to settle
		_diag(str(k[0]))
		await _shot(str(k[0]))   # what the player actually sees
		# DIAGNOSTIC ONLY, not what ships: hide the dead world's HUD layer for one frame so
		# the run-over screen's own layout can be judged even while something covers it.
		var hl: CanvasLayer = _app._world._hud_layer if _app._world != null else null
		if hl != null and hl.visible:
			hl.visible = false
			await _shot(str(k[0]) + "_unmasked")
			hl.visible = true
		if _fail != "":
			break
		_app._run_over.restart_button().pressed.emit()   # RESTART: same seed, back in
	if _fail == "" and not _covered.is_empty():
		_fail = "the run-over screen is open but covered by black in: %s" % ", ".join(_covered)
	_finish()


func _kill(kind: String, code: String, killer: String) -> void:
	var world = _app._world
	var ctl = world.ctl
	ctl.charges = 0              # nothing left to save it: this death ends the run
	ctl.last_light_spent = true
	ctl.invuln = 0.0
	ctl.respawn_t = -1.0
	if kind == "void":
		ctl.x = -500.0           # over open void, already past the kill plane (-40)
		ctl.y = -41.0
		ctl.z = 0.0
		ctl.vy = -1.0
		ctl.grounded = false
	else:
		ctl.try_kill(code, killer, world.w)


func _until_state(want: String, secs: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while _app.state() != want:
		if Time.get_ticks_msec() - t0 > int(secs * 1000.0):
			return false
		await process_frame
	return true


func _until_screen(secs: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while _app._run_over == null or not _app._run_over.visible:
		if Time.get_ticks_msec() - t0 > int(secs * 1000.0):
			return false
		await process_frame
	return true


func _diag(tag: String) -> void:
	var ro: Control = _app._run_over
	var m: Texture2D = ro.master_texture()
	var master_rect := "none"
	for n in ro.find_children("*", "TextureRect", true, false):
		if (n as TextureRect).texture == m and m != null:
			master_rect = str((n as TextureRect).get_global_rect())
	var kt: Texture2D = ro.killer_texture()
	print("DIAG %s code=%s killer='%s' line='%s' master=%s master_rect=%s killer_tex=%s restart=%s/%s lobby=%s/%s" % [
			tag, ro.code, ro.killer_text, ro.voice_text,
			str(m.get_size()) if m != null else "null", master_rect,
			str(kt.get_size()) if kt != null and ro._sprite.visible else "hidden",
			str(ro.restart_button().get_global_rect()), str(ro.restart_button().is_visible_in_tree()),
			str(ro.lobby_button().get_global_rect()), str(ro.lobby_button().is_visible_in_tree())])
	# What sits ABOVE the screen: the dead world's HUD CanvasLayer and its black-out.
	var w = _app._world
	var over := "no world"
	if w != null and is_instance_valid(w):
		var hl: CanvasLayer = w._hud_layer
		over = "world_in_tree=%s hud_layer=%s blackout_active=%s screen_fx_visible=%s" % [
				str(w.is_inside_tree()), str(hl.layer) if hl != null else "null",
				str(w.hud.screen_fx.blackout_active()), str(w.hud.screen_fx.is_visible_in_tree())]
	var img: Image = root.get_texture().get_image()
	var lit := 0
	var n := 0
	if img != null:
		for y in range(0, img.get_height(), 8):
			for x in range(0, img.get_width(), 8):
				var p := img.get_pixel(x, y)
				n += 1
				if p.r + p.g + p.b > 0.15:
					lit += 1
	var lit_pct := 100.0 * float(lit) / float(maxi(n, 1))
	print("DIAG %s above: %s run_over_canvas_layer=0 lit_pixels=%.1f%%" % [tag, over, lit_pct])
	if lit_pct < 1.0:
		_covered.append(tag)   # the screen is open but the player is looking at black
	if m == null:
		_fail = "%s: no Master texture" % tag
	if not ro.restart_button().is_visible_in_tree() or not ro.lobby_button().is_visible_in_tree():
		_fail = "%s: a button is hidden" % tag


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	if img == null:
		_fail = "viewport texture returned null for %s" % name
		return
	var path := _out_dir.path_join(name + ".png")
	if img.save_png(path) != OK:
		_fail = "save_png(%s) failed" % path
		return
	print("SHOT %s" % path)


func _finish() -> void:
	if _app != null:
		_app.queue_free()
		_app = null
	if FileAccess.file_exists(RECORDS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RECORDS))
	if _fail != "":
		print("SHOTX FAIL %s" % _fail)
		quit(1)
		return
	print("SHOTX OK")
	quit(0)
