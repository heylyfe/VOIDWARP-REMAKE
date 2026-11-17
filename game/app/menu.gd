extends Control
#
# Main menu (ticket T-024; DESIGN.md section 14). Entries: Play / Settings / About / Quit.
# The About text carries the ENEMIES.md DISCLAIMER paragraph VERBATIM (D-T024-4; the DESIGN.md
# section 14 wording is a different, kept-for-compatibility line in README.md - the two documents
# disagree and the ticket names ENEMIES.md).
#
# The About text and the entry list are constants / static functions so the headless test
# (tests/test_disclaimer.gd) asserts the exact byte string without a scene tree. The Settings
# panel is bound to the real settings store (app/settings.gd, T-082): volume, mouse sensitivity,
# field of view, fullscreen; it loads user://settings.json on open and saves on change.
#
# Play emits `play_requested`; Quit quits the tree. No boot scene exists yet (the loading screen
# is wired to one in a later ticket), so this script is the menu component, not the entry point.

const ABOUT_TITLE := "About VOIDWRAP RUN"
## The ENEMIES.md DISCLAIMER paragraph, verbatim (ENEMIES.md, "🔒 Hard rules").
const ABOUT_DISCLAIMER := "this is a personal, non-commercial project with no money involved. It is not affiliated with, endorsed by, or connected to any person, brand, character, or IP referenced or depicted in the game."
const MENU_ENTRIES := ["Play", "Settings", "About", "Quit"]

const SettingsStore := preload("res://app/settings.gd")

signal play_requested
signal quit_requested

var _settings: RefCounted = null
var _panel_host: VBoxContainer
var _play_button: Button
var _settings_button: Button
var _about_button: Button
var _quit_button: Button


## The full About text: title, the verbatim ENEMIES.md disclaimer, and the roster note.
## Kept static so tests can assert it without instancing the scene.
static func about_text() -> String:
	return "%s\n\n%s\n\nThe world is serious. The enemies are not." % [ABOUT_TITLE, ABOUT_DISCLAIMER]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_view()
	_show_menu()




func _build_view() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var vbox := VBoxContainer.new()
	vbox.name = "MenuColumn"
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(vbox)
	var title := Label.new()
	title.text = "VOIDWRAP RUN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	vbox.add_child(title)
	var sub := Label.new()
	sub.text = "collect every black gift. mind the void."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	vbox.add_child(sub)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 56)
	vbox.add_child(spacer)
	_play_button = _make_button("Play")
	_play_button.pressed.connect(_on_play)
	vbox.add_child(_play_button)
	_settings_button = _make_button("Settings")
	_settings_button.pressed.connect(_on_settings)
	vbox.add_child(_settings_button)
	_about_button = _make_button("About")
	_about_button.pressed.connect(_on_about)
	vbox.add_child(_about_button)
	_quit_button = _make_button("Quit")
	_quit_button.pressed.connect(_on_quit)
	vbox.add_child(_quit_button)
	_panel_host = VBoxContainer.new()
	_panel_host.name = "PanelHost"
	_panel_host.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(_panel_host)


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(280, 52)
	b.add_theme_font_size_override("font_size", 26)
	return b


func _clear_panel() -> void:
	for child in _panel_host.get_children():
		child.queue_free()


func _back_button() -> Button:
	var b := _make_button("Back")
	b.pressed.connect(_show_menu)
	return b


func _show_menu() -> void:
	_clear_panel()


func _on_play() -> void:
	play_requested.emit()


func _on_quit() -> void:
	quit_requested.emit()
	get_tree().quit()



func _on_about() -> void:
	_clear_panel()
	var header := Label.new()
	header.text = ABOUT_TITLE
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 30)
	header.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	_panel_host.add_child(header)
	var disclaimer := Label.new()
	disclaimer.name = "AboutDisclaimer"
	disclaimer.text = ABOUT_DISCLAIMER
	disclaimer.custom_minimum_size = Vector2(720, 0)
	disclaimer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	disclaimer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	disclaimer.add_theme_font_size_override("font_size", 18)
	disclaimer.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	_panel_host.add_child(disclaimer)
	var note := Label.new()
	note.text = "VOIDWRAP RUN is a fan remake. Collect every black gift, enter the beacon, and decide how much risk the gold is worth."
	note.custom_minimum_size = Vector2(720, 0)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 15)
	note.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	_panel_host.add_child(note)
	_panel_host.add_child(_back_button())


func _on_settings() -> void:
	_clear_panel()
	if _settings == null:
		_settings = SettingsStore.new()
		_settings.load_from()
	var header := Label.new()
	header.text = "Settings"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 30)
	header.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	_panel_host.add_child(header)
	_panel_host.add_child(_slider_row("Master volume", 0.0, 100.0, float(_settings.volume), 1.0,
		func(v: float) -> void:
			_settings.volume = int(round(v))
			_apply_settings()))
	_panel_host.add_child(_slider_row("Mouse sensitivity", 0.02, 0.30, _settings.mouse_sensitivity, 0.01,
		func(v: float) -> void:
			_settings.mouse_sensitivity = v
			_apply_settings()))
	_panel_host.add_child(_slider_row("Field of view", 60.0, 90.0, _settings.field_of_view, 1.0,
		func(v: float) -> void:
			_settings.field_of_view = v
			_apply_settings()))
	var fs_row := HBoxContainer.new()
	fs_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var fs_label := Label.new()
	fs_label.text = "Fullscreen"
	fs_label.custom_minimum_size = Vector2(240, 0)
	fs_row.add_child(fs_label)
	var fs := CheckBox.new()
	fs.button_pressed = _settings.fullscreen
	fs.toggled.connect(func(on: bool) -> void:
		_settings.fullscreen = on
		_apply_settings())
	fs_row.add_child(fs)
	_panel_host.add_child(fs_row)
	_panel_host.add_child(_back_button())


func _slider_row(label_text: String, min_v: float, max_v: float, value: float,
		step: float, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(240, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(320, 24)
	slider.value_changed.connect(on_change)
	row.add_child(slider)
	return row


func _apply_settings() -> void:
	_settings.save_to()
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if _settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(mode)

