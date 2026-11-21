extends RefCounted
#
# The settings volume control actually drives the audio bus, and persists (the "too quiet"
# pass: the store and the screen existed, but nothing in the game referenced the screen and
# the saved volume was never applied at boot, so the control was unreachable and inert).
#
# Four legs, all headless (widget values are set directly, exactly what a drag emits):
#   1. the screen's VolumeSlider writes through to the MASTER bus: the store value and
#      AudioServer.get_bus_volume_db() both follow the slider;
#   2. the value persists: the JSON on disk holds it, a fresh store loads it, and a fresh
#      screen's show_settings() puts it back on the bus;
#   3. volume 0 is real silence: the bus is MUTED, not merely quiet;
#   4. the control is reachable in-game: the pause overlay opens the settings screen, and
#      that screen's slider is the same one that drives the bus.
#
# The bus is left as it was found (0 dB, unmuted) so this test cannot colour another one.

const SettingsScript := preload("res://app/settings.gd")
const SettingsMenuScript := preload("res://view/settings_menu.gd")
const PauseOverlayScript := preload("res://app/pause_overlay.gd")

const MASTER := 0
const SCRATCH := "user://test_audio_volume.json"


func run() -> Array[String]:
	var f: Array[String] = []
	_rm(SCRATCH)
	_check_slider_drives_bus(f)
	_check_persists(f)
	_check_zero_is_silence(f)
	_check_reachable_in_game(f)
	_rm(SCRATCH)
	AudioServer.set_bus_volume_db(MASTER, 0.0)
	AudioServer.set_bus_mute(MASTER, false)
	return f


func _rm(path: String) -> void:
	for p in [path, path + ".old", path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _screen() -> Control:
	var m := SettingsMenuScript.new()
	m.settings_path = SCRATCH
	return m


# ---- 1. the slider reaches the bus -------------------------------------------------

func _check_slider_drives_bus(f: Array[String]) -> void:
	var m := _screen()
	var vol: HSlider = m.find_child("VolumeSlider", true, false)
	if vol == null:
		f.append("bus: the settings screen has no VolumeSlider")
		return
	vol.value_changed.emit(35.0)
	if int(m.store.volume) != 35:
		f.append("bus: the slider left the store at %d, want 35" % int(m.store.volume))
	var want := linear_to_db(0.35)
	var got := AudioServer.get_bus_volume_db(MASTER)
	if absf(got - want) > 0.01:
		f.append("bus: the slider did not reach the master bus: %.3f db, want %.3f" % [got, want])
	if AudioServer.is_bus_mute(MASTER):
		f.append("bus: the master bus is muted at volume 35, want unmuted")
	m.free()


# ---- 2. it persists ----------------------------------------------------------------

func _check_persists(f: Array[String]) -> void:
	var m := _screen()
	var vol: HSlider = m.find_child("VolumeSlider", true, false)
	vol.value_changed.emit(35.0)
	var raw := FileAccess.get_file_as_string(SCRATCH)
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		f.append("persist: %s is not readable JSON after a slider change" % SCRATCH)
		return
	if int((parsed as Dictionary).get("volume", -1)) != 35:
		f.append("persist: the file holds volume %s, want 35"
				% str((parsed as Dictionary).get("volume", null)))
	var fresh := SettingsScript.new()
	fresh.load_from(SCRATCH)
	if int(fresh.volume) != 35:
		f.append("persist: a fresh store loaded volume %d, want 35" % int(fresh.volume))
	# a fresh screen's show_settings() puts the saved value back on the bus
	AudioServer.set_bus_volume_db(MASTER, 0.0)
	var m2 := _screen()
	m2.show_settings()
	var want := linear_to_db(0.35)
	var got := AudioServer.get_bus_volume_db(MASTER)
	if absf(got - want) > 0.01:
		f.append("persist: show_settings() left the bus at %.3f db, want %.3f" % [got, want])
	m.free()
	m2.free()


# ---- 3. zero is silence ------------------------------------------------------------

func _check_zero_is_silence(f: Array[String]) -> void:
	var m := _screen()
	var vol: HSlider = m.find_child("VolumeSlider", true, false)
	vol.value_changed.emit(0.0)
	if not AudioServer.is_bus_mute(MASTER):
		f.append("zero: the master bus is not muted at volume 0")
	if AudioServer.get_bus_volume_db(MASTER) > -80.0:
		f.append("zero: the master bus is at %.3f db at volume 0, want -80"
				% AudioServer.get_bus_volume_db(MASTER))
	AudioServer.set_bus_mute(MASTER, false)
	AudioServer.set_bus_volume_db(MASTER, 0.0)
	m.free()


# ---- 4. reachable in-game ----------------------------------------------------------

func _check_reachable_in_game(f: Array[String]) -> void:
	var pause := PauseOverlayScript.new()
	if pause.settings_button() == null:
		f.append("reach: the pause overlay has no settings button")
		return
	pause.open_settings()
	var screen = pause.settings_screen()
	if screen == null:
		f.append("reach: the pause overlay's settings button opened no screen")
		return
	if not screen.visible:
		f.append("reach: the settings screen opened hidden")
	# the screen the pause overlay opens is the one whose slider drives the bus
	screen.settings_path = SCRATCH
	screen.show_settings()
	var vol: HSlider = screen.find_child("VolumeSlider", true, false)
	if vol == null:
		f.append("reach: the opened settings screen has no VolumeSlider")
		return
	vol.value_changed.emit(20.0)
	var want := linear_to_db(0.20)
	var got := AudioServer.get_bus_volume_db(MASTER)
	if absf(got - want) > 0.01:
		f.append("reach: the in-game slider left the bus at %.3f db, want %.3f" % [got, want])
	pause.free()

