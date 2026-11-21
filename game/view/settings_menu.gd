extends Control
#
# Settings screen: the UI the T-082 store (app/settings.gd) never had. Four controls -
# master volume, mouse sensitivity, field of view, fullscreen - each writing through the
# store AND pushed to its real consumer the same tick (a control that writes a value
# nothing reads is the defect being fixed):
#   master volume     -> AudioServer master bus  (store.apply_volume)
#   field of view     -> the active Camera3D     (store.apply_camera)
#   fullscreen        -> the root Window         (store.apply_window)
#   mouse sensitivity -> no view-side action here: its live consumer already exists
#                        (world.gd / lobby_scene.gd read it when a level builds).
# Every change persists immediately to `settings_path` (a slider dragged off-screen must
# never be lost to a crash), and show_settings() re-applies everything, so opening the
# screen loads the saved values into the running game.
#
# Builds in _init, holds no reference to the menu; its dependencies are app/settings.gd
# and the shared view/ui_style.gd + view/ui_focus.gd. Opened from the pause overlay
# (app/pause_overlay.gd SETTINGS). The whole public API is
#   signal closed
#   show_settings()  load + sync + apply + show
#   close_settings() persist + hide + emit closed
#   handle_input(e)  the screen's keys (fed by _unhandled_input)
#   focus_cycle()    the keyboard focus (tests)
#
# Headless-safe like menu.gd: plain property setters, tests drive the widgets directly.
#
# Look and keys (D-FRONT-1, view/ui_style.gd + view/ui_focus.gd): one centred panel - the
# SETTINGS heading, then one row per setting (tracked caption, control, the value in mono),
# the hint, and BACK. Each row is one focus stop wearing the shared focus ring: Tab /
# Shift+Tab / Up / Down move it, Left / Right adjust the focused slider (key repeat
# allowed), Enter / Space toggle FULLSCREEN or press BACK, ESC closes the screen (persist +
# `closed`), wherever it was opened from. The mouse works on every control as before.

const SettingsScript := preload("res://app/settings.gd")
const UiStyle := preload("res://view/ui_style.gd")
const UiFocus := preload("res://view/ui_focus.gd")

const PANEL_TITLE := "SETTINGS"
const HINT_TEXT := "changes apply and save immediately."
const SENS_SLIDER_STEP := 0.01
const PANEL_W := 560.0          # the panel's inner width
const CAPTION_W := 176.0        # the caption column ("MOUSE SENSITIVITY" + padding)
const VALUE_W := 64.0           # the value column ("0.30", "100")

signal closed

var store = null                          # the settings store this screen drives
var settings_path: String = SettingsScript.DEFAULT_PATH

var _volume_slider: HSlider
var _sens_slider: HSlider
var _fov_slider: HSlider
var _fullscreen_check: CheckButton
var _volume_value: Label
var _sens_value: Label
var _fov_value: Label
var _fullscreen_value: Label
var _back: Button
var _focus: UiFocus = UiFocus.new()


func _init() -> void:
	store = SettingsScript.new()
	name = "SettingsMenu"
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_sync_controls()
	visible = false


# ---- build ---------------------------------------------------------------------------------------

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := UiStyle.backdrop(Color(0, 0, 0, 0.96))
	bg.name = "Void"
	add_child(bg)
	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.name = "SettingsPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UiStyle.panel_box())
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.name = "Body"
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", UiStyle.SP_2)
	vb.custom_minimum_size = Vector2(PANEL_W, 0)
	panel.add_child(vb)
	var head := UiStyle.label(PANEL_TITLE, "title")
	head.name = "SettingsTitle"
	vb.add_child(head)
	vb.add_child(UiStyle.rule())
	vb.add_child(_gap(UiStyle.SP_3))
	_volume_slider = _slider("VolumeSlider", float(SettingsScript.VOLUME_MIN),
			float(SettingsScript.VOLUME_MAX), 1.0, _on_volume_changed)
	_volume_value = _row(vb, "VolumeRow", "MASTER VOLUME", _volume_slider, "VolumeValue",
			Callable(), _adjust.bind(_volume_slider, _on_volume_changed))
	_sens_slider = _slider("SensSlider", SettingsScript.SENS_MIN, SettingsScript.SENS_MAX,
			SENS_SLIDER_STEP, _on_sens_changed)
	_sens_value = _row(vb, "SensRow", "MOUSE SENSITIVITY", _sens_slider, "SensValue",
			Callable(), _adjust.bind(_sens_slider, _on_sens_changed))
	_fov_slider = _slider("FovSlider", SettingsScript.FOV_MIN, SettingsScript.FOV_MAX, 1.0,
			_on_fov_changed)
	_fov_value = _row(vb, "FovRow", "FIELD OF VIEW", _fov_slider, "FovValue",
			Callable(), _adjust.bind(_fov_slider, _on_fov_changed))
	_fullscreen_check = CheckButton.new()
	_fullscreen_check.name = "FullscreenCheck"
	_fullscreen_check.text = ""
	_fullscreen_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fullscreen_check.alignment = HORIZONTAL_ALIGNMENT_LEFT
	UiStyle.style_toggle(_fullscreen_check)
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	_fullscreen_value = _row(vb, "FullscreenRow", "FULLSCREEN", _fullscreen_check,
			"FullscreenValue", _toggle_fullscreen, Callable())
	vb.add_child(_gap(UiStyle.SP_2))
	var hint := UiStyle.label(HINT_TEXT, "small", UiStyle.TEXT_DIM)
	hint.name = "SettingsHint"
	vb.add_child(hint)
	vb.add_child(_gap(UiStyle.SP_3))
	var foot := HBoxContainer.new()
	foot.name = "Footer"
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_theme_constant_override("separation", UiStyle.SP_4)
	vb.add_child(foot)
	_back = Button.new()
	_back.name = "BackButton"
	_back.text = "BACK"
	_back.custom_minimum_size = Vector2(160, UiStyle.BUTTON_H)
	UiStyle.style_button(_back, UiStyle.SECONDARY)
	_back.pressed.connect(close_settings)
	foot.add_child(_back)
	_focus.add(_back, UiStyle.SECONDARY, close_settings)
	var hints := UiStyle.key_hints([["TAB", "move"], ["← →", "adjust"], ["ESC", "back"]])
	hints.alignment = BoxContainer.ALIGNMENT_END
	hints.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hints.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(hints)


func _gap(p_h: float) -> Control:
	var g := Control.new()
	g.custom_minimum_size = Vector2(0, p_h)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


func _slider(p_name: String, p_min: float, p_max: float, p_step: float, p_changed: Callable) -> HSlider:
	var s := HSlider.new()
	s.name = p_name
	s.min_value = p_min
	s.max_value = p_max
	s.step = p_step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStyle.style_slider(s)
	s.value_changed.connect(p_changed)
	return s


## One setting row: [CAPTION | control | value], the whole row one focus stop. Returns the
## value label.
func _row(p_parent: Control, p_name: String, p_caption: String, p_control: Control,
		p_value_name: String, p_activate: Callable, p_adjust: Callable) -> Label:
	var row := PanelContainer.new()
	row.name = p_name
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.custom_minimum_size = Vector2(0, UiStyle.BUTTON_H)
	p_parent.add_child(row)
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", UiStyle.SP_4)
	row.add_child(hb)
	var cap := UiStyle.label(p_caption, "label")
	cap.custom_minimum_size = Vector2(CAPTION_W, 0)
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cap.size_flags_vertical = Control.SIZE_FILL
	hb.add_child(cap)
	hb.add_child(p_control)
	var val := UiStyle.label("", "num")
	val.name = p_value_name
	val.custom_minimum_size = Vector2(VALUE_W, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	val.size_flags_vertical = Control.SIZE_FILL
	hb.add_child(val)
	_focus.add(row, UiStyle.ROW, p_activate, p_adjust)
	return val


## Left / Right on a focused slider row: one step, through the slider's own handler (the
## same write-through a drag makes), so it never depends on value_changed firing.
func _adjust(p_dir: int, p_slider: HSlider, p_changed: Callable) -> void:
	var v := clampf(p_slider.value + p_slider.step * float(p_dir), p_slider.min_value, p_slider.max_value)
	p_slider.set_value_no_signal(v)
	p_changed.call(v)


func _toggle_fullscreen() -> void:
	_fullscreen_check.set_pressed_no_signal(not _fullscreen_check.button_pressed)
	_on_fullscreen_toggled(_fullscreen_check.button_pressed)


## Push the current store values into the widgets without re-triggering their handlers.
func _sync_controls() -> void:
	_volume_slider.set_value_no_signal(float(store.volume))
	_sens_slider.set_value_no_signal(store.mouse_sensitivity)
	_fov_slider.set_value_no_signal(store.field_of_view)
	_fullscreen_check.set_pressed_no_signal(store.fullscreen)
	_volume_value.text = str(store.volume)
	_sens_value.text = "%.2f" % store.mouse_sensitivity
	_fov_value.text = str(int(roundf(store.field_of_view)))
	_fullscreen_value.text = "ON" if store.fullscreen else "OFF"


# ---- public API ----------------------------------------------------------------------------------

## Load from disk, sync the widgets, apply every consumer and show the screen.
func show_settings() -> void:
	store.load_from(settings_path)
	_sync_controls()
	_apply_consumers()
	_focus.focus(0)
	show()


## Persist, hide and tell the owner the screen is done (the `closed` signal).
func close_settings() -> void:
	store.save_to(settings_path)
	hide()
	closed.emit()


func is_open() -> bool:
	return visible


## The keyboard focus (tests/test_ui_style.gd drives it).
func focus_cycle() -> UiFocus:
	return _focus


## The screen's keys: ESC closes, everything else is the shared focus map.
func handle_input(event: InputEvent) -> bool:
	if not visible or not (event is InputEventKey):
		return false
	var k := event as InputEventKey
	if k.pressed and not k.echo and (k.keycode == KEY_ESCAPE or k.physical_keycode == KEY_ESCAPE):
		close_settings()
		return true
	return _focus.handle_key(event)


func _unhandled_input(event: InputEvent) -> void:
	if handle_input(event) and is_inside_tree():
		get_viewport().set_input_as_handled()


# ---- change handlers: write-through --------------------------------------------------------------

func _on_volume_changed(v: float) -> void:
	store.volume = clampi(int(roundf(v)), SettingsScript.VOLUME_MIN, SettingsScript.VOLUME_MAX)
	_volume_value.text = str(store.volume)
	_commit()


func _on_sens_changed(v: float) -> void:
	store.mouse_sensitivity = clampf(v, SettingsScript.SENS_MIN, SettingsScript.SENS_MAX)
	_sens_value.text = "%.2f" % store.mouse_sensitivity
	_commit()


func _on_fov_changed(v: float) -> void:
	store.field_of_view = clampf(v, SettingsScript.FOV_MIN, SettingsScript.FOV_MAX)
	_fov_value.text = str(int(roundf(store.field_of_view)))
	_commit()


func _on_fullscreen_toggled(on: bool) -> void:
	store.fullscreen = on
	_fullscreen_value.text = "ON" if on else "OFF"
	_commit()


## Write-through: persist, then push every field to its consumer (see the header table).
func _commit() -> void:
	store.save_to(settings_path)
	_apply_consumers()


## The consumer push half of _commit(): every field to its consumer; camera/window only
## when the screen is inside the scene tree (headless tests drive the store directly).
func _apply_consumers() -> void:
	store.apply_volume()
	if is_inside_tree():
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			store.apply_camera(cam)
		store.apply_window(get_window())
