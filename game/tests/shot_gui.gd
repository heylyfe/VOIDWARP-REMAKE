extends SceneTree
#
# Front-end screenshot tool (D-FRONT-1): boots the REAL app (app/app.gd) and captures every
# front-end screen the way a player meets them. Windowed run - rendering needs a GPU,
# never --headless; the out dir must be ABSOLUTE:
#
#   <godot> --path game --script res://tests/shot_gui.gd -- <abs_out_dir>
#
# Writes <out_dir>/gui_00_menu.png      the main menu over the island (PLAY selected)
#        <out_dir>/gui_01_menu_quit.png the selection moved twice with Tab (the ring on QUIT)
#        <out_dir>/gui_02_howto.png     HOW TO PLAY open
#        <out_dir>/gui_03_pause.png     ESC mid-run: the pause overlay over the frozen level
#        <out_dir>/gui_04_settings.png  SETTINGS opened from the pause overlay
#        <out_dir>/gui_05_loading.png   a loading screen (restart register, real tip)
# The run is started with a pinned seed (start_run) so no class altar opens - the altar has
# its own tool (shot_class_altar.gd). Named shot_*, not test_*, so run_all.gd skips it.
# Prints "SHOT <path>" per PNG and "SHOTGUI OK" / "SHOTGUI FAIL <why>"; exit 1 on failure.
# The settings screen is pointed at a scratch file (defaults), so the player's own settings
# (fullscreen, volume) are neither applied to the shot nor written. Waits are in seconds,
# not frames: the menu eases by delta, and an uncapped frame rate makes 20 frames ~0.04 s.

const AppScript := preload("res://app/app.gd")
const LoadingScript := preload("res://app/loading_screen.gd")
const SettingsMenuScript := preload("res://view/settings_menu.gd")

const SHOT_SIZE := Vector2i(1280, 720)
const RECORDS := "user://shot_gui_records.json"
const SETTINGS := "user://shot_gui_settings.json"   # defaults: the player's file is never read

var _out_dir := ""
var _fail := ""
var _app: Node = null


func _init() -> void:
	_run()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _wait(p_s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(p_s * 1000.0):
		await process_frame


func _key(code: int, shift := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.shift_pressed = shift
	return e


func _run() -> void:
	await process_frame
	root.size = SHOT_SIZE
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out_dir = args[0] if args.size() >= 1 else ProjectSettings.globalize_path("res://out/shots_gui")
	if DirAccess.make_dir_recursive_absolute(_out_dir) != OK:
		_fail = "cannot create %s" % _out_dir
		_finish()
		return
	_app = AppScript.new()
	_app.records_path = RECORDS
	root.add_child(_app)
	await _wait(1.0)
	var menu: Control = _app._menu
	if menu == null:
		_fail = "the app showed no menu"
		_finish()
		return
	print("DIAG menu mouse_mode=%d selected=%d" % [Input.mouse_mode, menu.selected_index()])
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		_fail = "the cursor is not free on the menu (mouse_mode %d)" % Input.mouse_mode
	await _shot("gui_00_menu")
	menu.handle_input(_key(KEY_TAB))
	menu.handle_input(_key(KEY_TAB))
	await _wait(0.6)
	await _shot("gui_01_menu_quit")
	menu.handle_input(_key(KEY_TAB))           # back on PLAY (wrap)
	menu.open_howto()
	await _wait(0.6)
	await _shot("gui_02_howto")
	menu.close_howto()
	await _frames(20)
	# a pinned run: no altar, straight through the loading screen into level 1
	_app.start_run(4242)
	var t0 := Time.get_ticks_msec()
	while _app.state() != "WORLD" and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
	if _app.state() != "WORLD":
		_fail = "the pinned run never went live (state %s)" % _app.state()
		_finish()
		return
	await _frames(30)
	_app._unhandled_input(_key(KEY_ESCAPE))
	await _frames(10)
	var pause: Control = _app._pause_overlay
	if pause == null or not pause.is_open():
		_fail = "ESC mid-run did not open the pause overlay"
		_finish()
		return
	print("DIAG pause mouse_mode=%d focused=%s" % [Input.mouse_mode, str(pause.focus_cycle().current().name)])
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		_fail = "the cursor is not free on the pause overlay (mouse_mode %d)" % Input.mouse_mode
	await _shot("gui_03_pause")
	var sm = SettingsMenuScript.new()
	sm.settings_path = SETTINGS
	pause._layer.add_child(sm)
	pause._settings = sm
	sm.show_settings()
	await _wait(0.3)
	await _shot("gui_04_settings")
	_app.queue_free()
	_app = null
	await _frames(5)
	var load := LoadingScript.new()
	load.start(7, 0.5, false)
	root.add_child(load)
	await _frames(50)
	await _shot("gui_05_loading")
	load.queue_free()
	_finish()


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
	for p in [RECORDS, SETTINGS]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	if _fail != "":
		print("SHOTGUI FAIL %s" % _fail)
		quit(1)
		return
	print("SHOTGUI OK")
	quit(0)
