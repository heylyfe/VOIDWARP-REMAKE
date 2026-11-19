extends RefCounted
#
# Settings test (T-082): every field actually reaches its consumer - a control that
# writes a value nothing reads is the exact defect this ticket fixes. Per field
# (volume, field of view, fullscreen): set it through the store, assert it reached
# its consumer (master audio bus volume, Camera3D.fov, a real Window's mode), and
# assert it survives a save/load round trip - on a SCRATCH path, like test_records.gd,
# so the player's real user://settings.json is never touched.
#
# Also proves the settings screen (view/settings_menu.gd) exposes a control for each
# field and is write-through: widget -> store -> disk -> consumers.
#
# Headless facts this test relies on (established by probing this environment):
#   - a real Window.new().mode round-trips headless (0 -> 3), but
#     DisplayServer.window_get_mode LIES in headless (always returns 1), so the
#     seam is the Window node, never DisplayServer.
#   - Camera3D.fov is a plain property and works headless.
#   - audio bus volume get/set works headless.
#
# Registered like every other test: extends RefCounted, run() -> Array[String],
# preloads by path (no class_name). The screen is NOT added to the SceneTree
# (headless harness); the widgets are driven directly (setting HSlider.value and
# CheckButton.button_pressed fire their signals without a tree).

const SettingsScript := preload("res://app/settings.gd")
const SettingsMenuScript := preload("res://view/settings_menu.gd")

const SCRATCH := "user://test_settings_scratch.json"
const MENU_SCRATCH := "user://test_settings_menu_scratch.json"
const MASTER := 0


func run() -> Array[String]:
	var failures: Array[String] = []
	_check_volume(failures)
	_check_fov(failures)
	_check_fullscreen(failures)
	_check_menu_controls(failures)
	_check_menu_write_through(failures)

	# leave the master bus as we found it (the menu tests dragged it around)
	var def := SettingsScript.new()
	def.volume = SettingsScript.VOLUME_DEFAULT
	def.apply_volume(MASTER)

	# scratch cleanup: the player's real user://settings.json is never touched
	_rm(SCRATCH)
	_rm(MENU_SCRATCH)
	return failures


func _check_volume(failures: Array[String]) -> void:
	_rm(SCRATCH)
	var s := SettingsScript.new()
	s.volume = 42
	if not s.save_to(SCRATCH):
		failures.append("volume: save_to(%s) returned false" % SCRATCH)
	var loaded := SettingsScript.new()
	loaded.load_from(SCRATCH)
	if loaded.volume != 42:
		failures.append("volume did not survive save/load: %d, want 42" % loaded.volume)
	var db := loaded.apply_volume(MASTER)
	var want := linear_to_db(0.42)
	if absf(db - want) > 0.01:
		failures.append("apply_volume returned %.3f db, want %.3f" % [db, want])
	var bus_db := AudioServer.get_bus_volume_db(MASTER)
	if absf(bus_db - want) > 0.01:
		failures.append("master bus volume %.3f db, want %.3f (never applied)" % [bus_db, want])
	if AudioServer.is_bus_mute(MASTER):
		failures.append("master bus muted at volume 42, want unmuted")
	# volume 0 is real silence: the bus is muted, not just quiet
	loaded.volume = 0
	loaded.apply_volume(MASTER)
	if not AudioServer.is_bus_mute(MASTER):
		failures.append("master bus not muted at volume 0, want muted")
	# a missing file falls back to the default
	var fresh := SettingsScript.new()
	fresh.load_from("user://test_settings_no_such_file.json")
	if fresh.volume != SettingsScript.VOLUME_DEFAULT:
		failures.append("missing file did not fall back to default volume: %d" % fresh.volume)


func _check_fov(failures: Array[String]) -> void:
	_rm(SCRATCH)
	var s := SettingsScript.new()
	s.field_of_view = 88.0
	if not s.save_to(SCRATCH):
		failures.append("fov: save_to(%s) returned false" % SCRATCH)
	var loaded := SettingsScript.new()
	loaded.load_from(SCRATCH)
	if not is_equal_approx(loaded.field_of_view, 88.0):
		failures.append("fov did not survive save/load: %.2f, want 88.0" % loaded.field_of_view)
	var cam := Camera3D.new()
	var got := loaded.apply_camera(cam)
	if not is_equal_approx(got, 88.0) or not is_equal_approx(cam.fov, 88.0):
		failures.append("camera fov %.2f (apply returned %.2f), want 88.0" % [cam.fov, got])
	cam.free()
	# an out-of-range file is clamped on load, never applied raw
	var wild := SettingsScript.new()
	wild.field_of_view = 120.0
	wild.save_to(SCRATCH)
	var clamped := SettingsScript.new()
	clamped.load_from(SCRATCH)
	if clamped.field_of_view != SettingsScript.FOV_MAX:
		failures.append("fov 120.0 loaded as %.2f, want clamped %.2f" % [clamped.field_of_view, SettingsScript.FOV_MAX])


func _check_fullscreen(failures: Array[String]) -> void:
	_rm(SCRATCH)
	var s := SettingsScript.new()
	s.fullscreen = true
	if not s.save_to(SCRATCH):
		failures.append("fullscreen: save_to(%s) returned false" % SCRATCH)
	var loaded := SettingsScript.new()
	loaded.load_from(SCRATCH)
	if not loaded.fullscreen:
		failures.append("fullscreen did not survive save/load: want true")
	# the seam is a real Window node: DisplayServer.window_get_mode lies headless
	var w := Window.new()
	var mode := loaded.apply_window(w)
	if mode != Window.MODE_FULLSCREEN or w.mode != Window.MODE_FULLSCREEN:
		failures.append("window mode %d (apply returned %d), want MODE_FULLSCREEN" % [w.mode, mode])
	w.mode = Window.MODE_WINDOWED
	loaded.fullscreen = false
	var back := loaded.apply_window(w)
	if back != Window.MODE_WINDOWED or w.mode != Window.MODE_WINDOWED:
		failures.append("window mode %d (apply returned %d), want MODE_WINDOWED" % [w.mode, back])
	if SettingsScript.window_mode_for(true) != Window.MODE_FULLSCREEN:
		failures.append("window_mode_for(true) is not MODE_FULLSCREEN")
	w.free()


func _check_menu_controls(failures: Array[String]) -> void:
	var menu := SettingsMenuScript.new()
	for control_name in ["VolumeSlider", "FovSlider", "FullscreenCheck", "SensSlider"]:
		if menu.find_child(control_name, true, false) == null:
			failures.append("settings screen missing its %s control" % control_name)
	# each control is actually wired to its write-through handler, not just present
	var vol: HSlider = menu.find_child("VolumeSlider", true, false)
	var fov: HSlider = menu.find_child("FovSlider", true, false)
	var sens: HSlider = menu.find_child("SensSlider", true, false)
	var check: CheckButton = menu.find_child("FullscreenCheck", true, false)
	if not vol.value_changed.is_connected(menu._on_volume_changed):
		failures.append("VolumeSlider.value_changed is not wired to its handler")
	if not fov.value_changed.is_connected(menu._on_fov_changed):
		failures.append("FovSlider.value_changed is not wired to its handler")
	if not sens.value_changed.is_connected(menu._on_sens_changed):
		failures.append("SensSlider.value_changed is not wired to its handler")
	if not check.toggled.is_connected(menu._on_fullscreen_toggled):
		failures.append("FullscreenCheck.toggled is not wired to its handler")
	menu.free()


# Probed headless fact (this environment): setting HSlider.value programmatically does
# NOT fire value_changed (a bare slider fired=0), so the sliders are driven the house
# way - the signal is emitted directly, exactly what a user drag would emit. The
# CheckButton's button_pressed setter DOES fire toggled, so it is driven as a user would.
func _check_menu_write_through(failures: Array[String]) -> void:
	_rm(MENU_SCRATCH)
	var menu := SettingsMenuScript.new()
	menu.settings_path = MENU_SCRATCH
	var vol: HSlider = menu.find_child("VolumeSlider", true, false)
	var fov: HSlider = menu.find_child("FovSlider", true, false)
	var check: CheckButton = menu.find_child("FullscreenCheck", true, false)

	# dragging the volume slider writes through: store -> disk -> master bus
	vol.value_changed.emit(30.0)
	if menu.store.volume != 30:
		failures.append("volume slider left the store at %d, want 30" % menu.store.volume)
	var want := linear_to_db(0.30)
	if absf(AudioServer.get_bus_volume_db(MASTER) - want) > 0.01:
		failures.append("volume slider did not reach the master bus: %.3f db, want %.3f" % [AudioServer.get_bus_volume_db(MASTER), want])
	# the fov slider writes through to the store ...
	fov.value_changed.emit(65.0)
	if not is_equal_approx(menu.store.field_of_view, 65.0):
		failures.append("fov slider left the store at %.2f, want 65.0" % menu.store.field_of_view)
	# ... and the fullscreen check to the flag
	check.button_pressed = true
	if not menu.store.fullscreen:
		failures.append("fullscreen check left the store at false, want true")
	# every change persisted immediately (a crashed drag must never lose a setting)
	var persisted := SettingsScript.new()
	persisted.load_from(MENU_SCRATCH)
	if persisted.volume != 30 or not is_equal_approx(persisted.field_of_view, 65.0) or not persisted.fullscreen:
		failures.append("slider changes not persisted to disk: volume %d fov %.2f fs %s" % [persisted.volume, persisted.field_of_view, persisted.fullscreen])

	# closing persists + hides + signals; show_settings reloads the saved values
	_closed_flag = false
	menu.closed.connect(_on_menu_closed)
	menu.close_settings()
	if not _closed_flag or menu.is_open():
		failures.append("close_settings did not hide + emit closed")
	var menu2 := SettingsMenuScript.new()
	menu2.settings_path = MENU_SCRATCH
	menu2.show_settings()
	if menu2.store.volume != 30 or not menu2.is_open():
		failures.append("show_settings did not load the saved values (volume %d)" % menu2.store.volume)
	if not is_equal_approx(menu2.store.field_of_view, 65.0) or not menu2.store.fullscreen:
		failures.append("show_settings did not restore fov/fullscreen: %.2f / %s" % [menu2.store.field_of_view, menu2.store.fullscreen])
	menu2.free()
	menu.free()


var _closed_flag := false


func _on_menu_closed() -> void:
	_closed_flag = true


func _rm(p: String) -> void:
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)
