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
# SELF-CONTAINED BY CONTRACT this wave (menu files belong to another worker): builds in
# _init, holds no reference to the menu, no dependency beyond app/settings.gd. The whole
# public API is
#   signal closed
#   show_settings()  load + sync + apply + show
#   close_settings() persist + hide + emit closed
# Wave-2 wiring is one line (see the hand-off report); until then nothing in the menu
# references this file.
#
# Headless-safe like menu.gd: no _input paths, plain property setters, tests drive the
# widgets directly (setting HSlider.value fires value_changed without a scene tree).

const SettingsScript := preload("res://app/settings.gd")

## Palette (data/palette.json roles; the same values menu.gd uses).
const C_VOID := Color(0.0078, 0.0118, 0.0588)        # #02030F the void backdrop
const C_WHITE := Color(0.910, 1.0, 1.0)              # #E8FFFF beacon_open
const C_GOLD := Color(1.0, 0.784, 0.239)             # #FFC83D gold_gift
const C_MUTED := Color(0.545, 0.620, 0.718)          # unselected entry text
const C_DIM := Color(0.431, 0.494, 0.584)            # footer text

const PANEL_TITLE := "SETTINGS"
const HINT_TEXT := "changes apply and save immediately."
const SENS_SLIDER_STEP := 0.01

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
var _fonts: Dictionary = {}               # role -> FontVariation
var _scaled: Array = []                   # [Control, theme font-size key, base px]


func _init() -> void:
	store = SettingsScript.new()
	name = "SettingsMenu"
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_sync_controls()
	visible = false


# ---- build ---------------------------------------------------------------------------------------

func _font(role: String, embolden: float) -> FontVariation:
	if not _fonts.has(role):
		var f := FontVariation.new()
		f.base_font = ThemeDB.fallback_font
		f.variation_embolden = embolden
		_fonts[role] = f
	return _fonts[role]


func _label(text: String, role: String, embolden: float, base_px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font(role, embolden))
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scaled.append([l, "font_size", base_px])
	return l


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.name = "Void"
	bg.color = Color(C_VOID.r, C_VOID.g, C_VOID.b, 0.94)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.name = "SettingsPanel"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(C_VOID.r, C_VOID.g, C_VOID.b, 0.96)
	sb.border_color = Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.7)
	sb.border_width_left = 3
	sb.border_width_right = 3
	sb.border_width_top = 3
	sb.border_width_bottom = 3
	sb.content_margin_left = 34.0
	sb.content_margin_right = 34.0
	sb.content_margin_top = 28.0
	sb.content_margin_bottom = 22.0
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.name = "Body"
	vb.add_theme_constant_override("separation", 10)
	vb.custom_minimum_size = Vector2(520, 0)
	panel.add_child(vb)

	var head := _label(PANEL_TITLE, "title", 0.85, 40, C_WHITE)
	head.name = "SettingsTitle"
	vb.add_child(head)
	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.color = Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.85)
	rule.custom_minimum_size = Vector2(56, 3)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vb.add_child(rule)

	# master volume
	var vol_cap := _label("MASTER VOLUME", "body", 0.0, 15, C_MUTED)
	vb.add_child(vol_cap)
	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 14)
	vb.add_child(vol_row)
	_volume_slider = HSlider.new()
	_volume_slider.name = "VolumeSlider"
	_volume_slider.min_value = float(SettingsScript.VOLUME_MIN)
	_volume_slider.max_value = float(SettingsScript.VOLUME_MAX)
	_volume_slider.step = 1.0
	_volume_slider.custom_minimum_size = Vector2(300, 28)
	_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_volume_slider.focus_mode = Control.FOCUS_NONE
	_volume_slider.value_changed.connect(_on_volume_changed)
	vol_row.add_child(_volume_slider)
	_volume_value = _label("", "bold", 0.4, 15, C_WHITE)
	_volume_value.name = "VolumeValue"
	_volume_value.custom_minimum_size = Vector2(56, 0)
	_volume_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vol_row.add_child(_volume_value)

	# mouse sensitivity
	var sens_cap := _label("MOUSE SENSITIVITY", "body", 0.0, 15, C_MUTED)
	vb.add_child(sens_cap)
	var sens_row := HBoxContainer.new()
	sens_row.add_theme_constant_override("separation", 14)
	vb.add_child(sens_row)
	_sens_slider = HSlider.new()
	_sens_slider.name = "SensSlider"
	_sens_slider.min_value = SettingsScript.SENS_MIN
	_sens_slider.max_value = SettingsScript.SENS_MAX
	_sens_slider.step = SENS_SLIDER_STEP
	_sens_slider.custom_minimum_size = Vector2(300, 28)
	_sens_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sens_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sens_slider.focus_mode = Control.FOCUS_NONE
	_sens_slider.value_changed.connect(_on_sens_changed)
	sens_row.add_child(_sens_slider)
	_sens_value = _label("", "bold", 0.4, 15, C_WHITE)
	_sens_value.name = "SensValue"
	_sens_value.custom_minimum_size = Vector2(56, 0)
	_sens_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sens_row.add_child(_sens_value)

	# field of view
	var fov_cap := _label("FIELD OF VIEW", "body", 0.0, 15, C_MUTED)
	vb.add_child(fov_cap)
	var fov_row := HBoxContainer.new()
	fov_row.add_theme_constant_override("separation", 14)
	vb.add_child(fov_row)
	_fov_slider = HSlider.new()
	_fov_slider.name = "FovSlider"
	_fov_slider.min_value = SettingsScript.FOV_MIN
	_fov_slider.max_value = SettingsScript.FOV_MAX
	_fov_slider.step = 1.0
	_fov_slider.custom_minimum_size = Vector2(300, 28)
	_fov_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fov_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_fov_slider.focus_mode = Control.FOCUS_NONE
	_fov_slider.value_changed.connect(_on_fov_changed)
	fov_row.add_child(_fov_slider)
	_fov_value = _label("", "bold", 0.4, 15, C_WHITE)
	_fov_value.name = "FovValue"
	_fov_value.custom_minimum_size = Vector2(56, 0)
	_fov_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fov_row.add_child(_fov_value)

	# fullscreen
	_fullscreen_check = CheckButton.new()
	_fullscreen_check.name = "FullscreenCheck"
	_fullscreen_check.text = "FULLSCREEN"
	_fullscreen_check.focus_mode = Control.FOCUS_NONE
	_fullscreen_check.add_theme_font_override("font", _font("body", 0.4))
	_fullscreen_check.add_theme_color_override("font_color", C_MUTED)
	_fullscreen_check.add_theme_font_size_override("font_size", 18)
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	vb.add_child(_fullscreen_check)

	# footer: hint + back
	var hint := _label(HINT_TEXT, "body", 0.0, 13, C_DIM)
	hint.name = "SettingsHint"
	vb.add_child(hint)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 12)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(gap)
	var back := Button.new()
	back.name = "BackButton"
	back.text = "BACK"
	back.focus_mode = Control.FOCUS_NONE
	back.flat = false
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back.add_theme_font_override("font", _font("entry", 0.35))
	back.add_theme_color_override("font_color", C_GOLD)
	back.add_theme_color_override("font_hover_color", C_WHITE)
	back.pressed.connect(close_settings)
	_scaled.append([back, "font_size", 18])
	back.custom_minimum_size = Vector2(150, 40)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vb.add_child(back)


## Push the current store values into the widgets without re-triggering their handlers.
func _sync_controls() -> void:
	_volume_slider.set_value_no_signal(float(store.volume))
	_sens_slider.set_value_no_signal(store.mouse_sensitivity)
	_fov_slider.set_value_no_signal(store.field_of_view)
	_fullscreen_check.set_pressed_no_signal(store.fullscreen)
	_volume_value.text = str(store.volume)
	_sens_value.text = "%.2f" % store.mouse_sensitivity
	_fov_value.text = str(int(roundf(store.field_of_view)))


# ---- public API ----------------------------------------------------------------------------------

## Load from disk, sync the widgets, apply every consumer and show the screen.
func show_settings() -> void:
	store.load_from(settings_path)
	_sync_controls()
	_apply_consumers()
	show()


## Persist, hide and tell the owner the screen is done (the `closed` signal).
func close_settings() -> void:
	store.save_to(settings_path)
	hide()
	closed.emit()


func is_open() -> bool:
	return visible


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

