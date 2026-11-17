extends Control
#
# Main menu (ticket MENU; supersedes the T-024 layout - DESIGN.md section 14).
# Entries: PLAY / HOW TO PLAY / QUIT, plus a version tag and the disclaimer footer.
#
# The face of the game: the menu column sits over a live 3D backdrop (app/menu_stage.gd) - a
# floating island in the void, the open beacon's light column, gold gifts, and the full enemy
# roster standing as real billboards. The UI never covers the roster: the column is on the left,
# the stage camera shifts the island right (menu_stage.gd CAM_H_OFFSET).
#
# INPUT is the game's own mapping (data/bindings.json through app/input_capture.gd, the file the
# play capture reads): move_forward / move_back select (wrapping), jump or interact confirm, pause
# backs out of the HOW TO PLAY panel. Gamepad: the bound jump / interact buttons confirm, the left
# stick (the game's move axis) and the d-pad select. Enter is NOT a confirm key; the entries never
# take keyboard focus, so Godot's built-in ui_accept / ui_up / ui_down cannot double-fire.
# The mouse also works: hover selects, click activates.
#
# The ENEMIES.md disclaimer (hard rule) stays reachable: ABOUT_DISCLAIMER is rendered verbatim in
# the footer on the main screen at all times, and about_text() still returns it (the About entry is
# gone - the owner's entry list is PLAY / HOW TO PLAY / QUIT; D-MENU-1).
#
# PUBLIC API (the seam the APP-FLOW ticket's app.gd connects to - do not rename):
#   signal play_requested, signal quit_requested, static func about_text() -> String,
#   const ABOUT_TITLE, const ABOUT_DISCLAIMER, const MENU_ENTRIES.
# PLAY emits play_requested and nothing else: the flow into level 1 is the orchestrator's.
# QUIT emits quit_requested; when nobody listens, it quits the tree itself.
#
# Every animation runs from _process with plain timers (no Tween), and the whole menu builds in
# _init, so tests/test_menu.gd drives it headless without a scene tree via handle_input().

const ABOUT_TITLE := "About VOIDWRAP RUN"
## The ENEMIES.md DISCLAIMER paragraph, verbatim (ENEMIES.md, "🔒 Hard rules").
const ABOUT_DISCLAIMER := "this is a personal, non-commercial project with no money involved. It is not affiliated with, endorsed by, or connected to any person, brand, character, or IP referenced or depicted in the game."
const MENU_ENTRIES := ["PLAY", "HOW TO PLAY", "QUIT"]

const ENTRY_PLAY := 0
const ENTRY_HOWTO := 1
const ENTRY_QUIT := 2

## D-MENU-5: the build's version tag (the alpha tag named in AUDIT.md was not created yet).
const VERSION_TAG := "v0.1.0-alpha.1 pre-release"

## One line under the entries, per entry (what confirming it does).
const ENTRY_HINTS := [
	"Into the void. Level 1.",
	"Void charges, contact kills, the beacon.",
	"Back to the desktop.",
]

const StageScript := preload("res://app/menu_stage.gd")
const HowToScript := preload("res://app/menu_howto.gd")
const InputCaptureScript := preload("res://app/input_capture.gd")

## Palette (data/palette.json roles; D-MENU-2).
const C_VOID := Color(0.0078, 0.0118, 0.0588)        # #02030F the void backdrop
const C_WHITE := Color(0.910, 1.0, 1.0)              # #E8FFFF beacon_open
const C_GOLD := Color(1.0, 0.784, 0.239)             # #FFC83D gold_gift
const C_MUTED := Color(0.545, 0.620, 0.718)          # unselected entry text
const C_DIM := Color(0.431, 0.494, 0.584)            # footer text

const STICK_THRESHOLD := 0.6
const SCROLL_STEP := 48.0

signal play_requested
signal quit_requested

var selected := ENTRY_PLAY
var bindings: Dictionary = {}
var stage: Node3D = null
var ui_scale := 1.0

var _entries: Array[Button] = []
var _entry_anim: Array[float] = []      # 0 = unselected look, 1 = selected look (eased)
var _howto_open := false
var _panel_t := 0.0                     # 0 closed .. 1 open (eased in _process)
var _panel_left := 0.0                  # the panel's resting offsets (set by _apply_scale)
var _panel_right := 0.0
var _stick_latched := false
var _scaled: Array = []                 # [Control, theme font-size key, base px]
var _fonts: Dictionary = {}             # role -> FontVariation

var _viewport_box: SubViewportContainer
var _scrim: TextureRect
var _column: VBoxContainer
var _title_top: Label
var _title_run: Label
var _rule: ColorRect
var _tagline: Label
var _entry_box: VBoxContainer
var _entry_hint: Label
var _keys_hint: RichTextLabel
var _version: Label
var _disclaimer: Label
var _panel: PanelContainer
var _panel_text: RichTextLabel
var _panel_hint: Label
var _back_button: Button


## The full About text: title, the verbatim ENEMIES.md disclaimer, and the roster note.
## Kept static so tests can assert it without instancing the scene.
static func about_text() -> String:
	return "%s\n\n%s\n\nThe world is serious. The enemies are not." % [ABOUT_TITLE, ABOUT_DISCLAIMER]


func _init() -> void:
	name = "MainMenu"
	bindings = InputCaptureScript.load_bindings()
	_build()
	_set_selected(ENTRY_PLAY, true)
	_apply_scale()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_apply_scale()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_scale()


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
	mouse_filter = Control.MOUSE_FILTER_PASS
	var bg := ColorRect.new()
	bg.name = "Void"
	bg.color = C_VOID
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# the 3D stage, in its own world so it never meets the game's camera or environment
	_viewport_box = SubViewportContainer.new()
	_viewport_box.name = "StageView"
	_viewport_box.stretch = true
	_viewport_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vp := SubViewport.new()
	vp.name = "StageViewport"
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.handle_input_locally = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage = StageScript.new()
	vp.add_child(stage)
	_viewport_box.add_child(vp)
	add_child(_viewport_box)

	# left scrim: the column reads over the 3D without a box around it
	_scrim = TextureRect.new()
	_scrim.name = "Scrim"
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.stretch_mode = TextureRect.STRETCH_SCALE
	_scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var g := Gradient.new()
	g.set_color(0, Color(C_VOID.r, C_VOID.g, C_VOID.b, 0.92))
	g.set_color(1, Color(C_VOID.r, C_VOID.g, C_VOID.b, 0.0))
	g.add_point(0.30, Color(C_VOID.r, C_VOID.g, C_VOID.b, 0.78))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.0, 0.5)
	gt.fill_to = Vector2(0.62, 0.5)
	gt.width = 256
	gt.height = 4
	_scrim.texture = gt
	add_child(_scrim)
	var foot := TextureRect.new()
	foot.name = "FooterScrim"
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	foot.stretch_mode = TextureRect.STRETCH_SCALE
	foot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var fg := Gradient.new()
	fg.set_color(0, Color(C_VOID.r, C_VOID.g, C_VOID.b, 0.0))
	fg.set_color(1, Color(C_VOID.r, C_VOID.g, C_VOID.b, 0.85))
	var fgt := GradientTexture2D.new()
	fgt.gradient = fg
	fgt.fill_from = Vector2(0.5, 0.82)
	fgt.fill_to = Vector2(0.5, 1.0)
	fgt.width = 4
	fgt.height = 256
	foot.texture = fgt
	add_child(foot)

	# the menu column
	_column = VBoxContainer.new()
	_column.name = "MenuColumn"
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_column)
	var title := VBoxContainer.new()
	title.name = "Title"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_constant_override("separation", 0)
	_column.add_child(title)
	_title_top = _label("VOIDWRAP", "title", 0.85, 84, C_WHITE)
	_title_top.name = "TitleVoidwrap"
	title.add_child(_title_top)
	_title_run = _label("RUN", "title", 0.85, 84, C_GOLD)
	_title_run.name = "TitleRun"
	title.add_child(_title_run)
	_rule = ColorRect.new()
	_rule.name = "Rule"
	_rule.color = Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.85)
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(_rule)
	_tagline = _label("collect every black gift. mind the void.", "body", 0.0, 17, C_MUTED)
	_tagline.name = "Tagline"
	_column.add_child(_tagline)
	var gap := Control.new()
	gap.name = "Gap"
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scaled.append([gap, "min_h", 44])
	_column.add_child(gap)

	_entry_box = VBoxContainer.new()
	_entry_box.name = "Entries"
	_entry_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(_entry_box)
	for i in MENU_ENTRIES.size():
		var b := Button.new()
		b.name = "Entry%d" % i
		b.text = str(MENU_ENTRIES[i])
		b.flat = false
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_override("font", _font("entry", 0.35))
		b.mouse_entered.connect(_on_entry_hover.bind(i))
		b.pressed.connect(_on_entry_pressed.bind(i))
		_scaled.append([b, "font_size", 30])
		_entry_box.add_child(b)
		_entries.append(b)
		_entry_anim.append(0.0)
	_entry_hint = _label("", "body", 0.0, 15, C_MUTED)
	_entry_hint.name = "EntryHint"
	_column.add_child(_entry_hint)
	var gap2 := Control.new()
	gap2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scaled.append([gap2, "min_h", 26])
	_column.add_child(gap2)
	_keys_hint = RichTextLabel.new()
	_keys_hint.name = "KeysHint"
	_keys_hint.bbcode_enabled = true
	_keys_hint.fit_content = true
	_keys_hint.scroll_active = false
	_keys_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	_keys_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keys_hint.add_theme_font_override("normal_font", _font("body", 0.0))
	_keys_hint.add_theme_font_override("bold_font", _font("bold", 0.6))
	_scaled.append([_keys_hint, "normal_font_size", 14])
	_scaled.append([_keys_hint, "bold_font_size", 14])
	_keys_hint.text = keys_hint_bbcode()
	_column.add_child(_keys_hint)

	# footer: version tag + the disclaimer (always on screen - the About entry is gone)
	_version = _label(VERSION_TAG, "body", 0.2, 13, C_DIM)
	_version.name = "VersionTag"
	add_child(_version)
	_disclaimer = _label("VOIDWRAP RUN: " + ABOUT_DISCLAIMER, "body", 0.0, 12, C_DIM)
	_disclaimer.name = "Disclaimer"
	_disclaimer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_disclaimer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_disclaimer)

	_build_howto_panel()


func _build_howto_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "HowToPanel"
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(C_VOID.r, C_VOID.g, C_VOID.b, 0.94)
	sb.border_color = Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.7)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var vb := VBoxContainer.new()
	vb.name = "Body"
	_panel.add_child(vb)
	var head := _label("HOW TO PLAY", "title", 0.85, 40, C_WHITE)
	head.name = "HowToTitle"
	vb.add_child(head)
	var rule := ColorRect.new()
	rule.color = Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.85)
	rule.custom_minimum_size = Vector2(56, 3)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vb.add_child(rule)
	_panel_text = RichTextLabel.new()
	_panel_text.name = "HowToText"
	_panel_text.bbcode_enabled = true
	_panel_text.scroll_active = true
	_panel_text.fit_content = false
	_panel_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel_text.add_theme_font_override("normal_font", _font("body", 0.0))
	_panel_text.add_theme_font_override("bold_font", _font("bold", 0.6))
	_panel_text.add_theme_constant_override("line_separation", 4)
	_scaled.append([_panel_text, "normal_font_size", 17])
	_scaled.append([_panel_text, "bold_font_size", 17])
	vb.add_child(_panel_text)
	var row := HBoxContainer.new()
	vb.add_child(row)
	_back_button = Button.new()
	_back_button.name = "BackButton"
	_back_button.text = "BACK"
	_back_button.focus_mode = Control.FOCUS_NONE
	_back_button.add_theme_font_override("font", _font("entry", 0.35))
	_back_button.add_theme_color_override("font_color", C_GOLD)
	_back_button.add_theme_color_override("font_hover_color", C_WHITE)
	_back_button.pressed.connect(close_howto)
	_scaled.append([_back_button, "font_size", 18])
	row.add_child(_back_button)
	_panel_hint = _label("", "body", 0.0, 14, C_DIM)
	_panel_hint.name = "HowToHint"
	_panel_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_panel_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_panel_hint)
	_panel_hint.text = "%s scroll     %s / %s back" % [
		_keys(["move_forward", "move_back"]), _keys(["jump", "interact"]), _keys(["pause"])]


## "W / S select     SPACE / F confirm" - read from the bindings, never hardcoded.
func keys_hint_bbcode() -> String:
	return "[color=#E8FFFF][b]%s[/b][/color] [color=#8B9EB7]select[/color]      [color=#E8FFFF][b]%s[/b][/color] [color=#8B9EB7]confirm[/color]" % [
		_keys(["move_forward", "move_back"]), _keys(["jump", "interact"])]


func _keys(actions: Array) -> String:
	var parts: Array[String] = []
	for a in actions:
		parts.append(HowToScript.keys_for(bindings, str(a)))
	return " / ".join(parts)


# ---- layout + scale ------------------------------------------------------------------------------

func _apply_scale() -> void:
	if _column == null or _panel == null:
		return                      # a resize notification during _build
	var h: float = size.y if size.y > 0.0 else 720.0
	var w: float = size.x if size.x > 0.0 else 1280.0
	ui_scale = clampf(minf(h / 720.0, w / 1280.0), 0.7, 3.0)
	for item in _scaled:
		var node: Control = item[0]
		var key: String = item[1]
		var px: int = maxi(int(round(float(item[2]) * ui_scale)), 1)
		if key == "min_h":
			node.custom_minimum_size = Vector2(0, px)
		else:
			node.add_theme_font_size_override(key, px)
	(_fonts["title"] as FontVariation).spacing_glyph = int(round(10.0 * ui_scale))
	if _fonts.has("entry"):
		(_fonts["entry"] as FontVariation).spacing_glyph = int(round(3.0 * ui_scale))
	var margin: float = round(w * 0.065)
	_column.anchor_left = 0.0
	_column.anchor_right = 0.0
	_column.anchor_top = 0.0
	_column.anchor_bottom = 1.0
	_column.offset_left = margin
	_column.offset_right = margin + round(520.0 * ui_scale)
	_column.offset_top = round(40.0 * ui_scale)
	_column.offset_bottom = -round(90.0 * ui_scale)
	_column.add_theme_constant_override("separation", int(round(8.0 * ui_scale)))
	_entry_box.add_theme_constant_override("separation", int(round(4.0 * ui_scale)))
	_title_top.add_theme_constant_override("line_spacing", 0)
	_title_run.add_theme_constant_override("line_spacing", 0)
	_rule.custom_minimum_size = Vector2(round(64.0 * ui_scale), maxf(2.0, round(3.0 * ui_scale)))
	_rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for b in _entries:
		b.custom_minimum_size = Vector2(round(360.0 * ui_scale), round(54.0 * ui_scale))
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var pad: float = round(22.0 * ui_scale)
	_version.anchor_left = 0.0
	_version.anchor_right = 0.0
	_version.anchor_top = 1.0
	_version.anchor_bottom = 1.0
	_version.offset_left = margin
	_version.offset_right = margin + round(360.0 * ui_scale)
	_version.offset_top = -pad - round(20.0 * ui_scale)
	_version.offset_bottom = -pad
	_disclaimer.anchor_left = 1.0
	_disclaimer.anchor_right = 1.0
	_disclaimer.anchor_top = 1.0
	_disclaimer.anchor_bottom = 1.0
	_disclaimer.offset_right = -margin * 0.6
	_disclaimer.offset_left = -margin * 0.6 - round(780.0 * ui_scale)
	_disclaimer.offset_top = -pad - round(40.0 * ui_scale)
	_disclaimer.offset_bottom = -pad
	_disclaimer.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	# the panel: right side, clear of the menu column
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	# the panel starts right of the title (it never clips the wordmark)
	var title_w: float = maxf(_title_top.get_combined_minimum_size().x, 440.0 * ui_scale)
	_panel_left = margin + title_w + round(36.0 * ui_scale)
	_panel_right = -round(48.0 * ui_scale)
	_panel.offset_top = round(52.0 * ui_scale)
	_panel.offset_bottom = -round(96.0 * ui_scale)
	var sb: StyleBoxFlat = _panel.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		sb.border_width_left = maxi(2, int(round(3.0 * ui_scale)))
		var cm: float = round(34.0 * ui_scale)
		sb.content_margin_left = cm
		sb.content_margin_right = cm
		sb.content_margin_top = round(28.0 * ui_scale)
		sb.content_margin_bottom = round(22.0 * ui_scale)
	_panel_text.text = HowToScript.bbcode(bindings).replace("{h}", str(int(round(19.0 * ui_scale))))
	for i in _entries.size():
		_style_entry(i)
	_place_panel()


func _style_entry(i: int) -> void:
	var b: Button = _entries[i]
	var t: float = _entry_anim[i]
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.10 * t)
	sb.border_color = Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, t)
	sb.border_width_left = int(round(4.0 * ui_scale * t))
	sb.content_margin_left = round((12.0 + 16.0 * t) * ui_scale)
	sb.content_margin_right = round(12.0 * ui_scale)
	sb.content_margin_top = round(6.0 * ui_scale)
	sb.content_margin_bottom = round(6.0 * ui_scale)
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, sb)
	var col: Color = C_MUTED.lerp(C_GOLD, t)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, col)


# ---- selection + activation ----------------------------------------------------------------------

func _set_selected(i: int, snap: bool = false) -> void:
	selected = posmod(i, MENU_ENTRIES.size())
	_entry_hint.text = str(ENTRY_HINTS[selected])
	if snap:
		for k in _entry_anim.size():
			_entry_anim[k] = 1.0 if k == selected else 0.0
			_style_entry(k)


func move_selection(step: int) -> void:
	_set_selected(selected + step)


func activate(i: int) -> void:
	_set_selected(i)
	match selected:
		ENTRY_PLAY:
			play_requested.emit()
		ENTRY_HOWTO:
			open_howto()
		ENTRY_QUIT:
			quit_requested.emit()
			if quit_requested.get_connections().is_empty() and is_inside_tree():
				get_tree().quit()


func open_howto() -> void:
	_howto_open = true
	_panel.visible = true
	_panel_text.scroll_to_line(0)


func close_howto() -> void:
	_howto_open = false


func is_howto_open() -> bool:
	return _howto_open


func selected_index() -> int:
	return selected


func entry_buttons() -> Array[Button]:
	return _entries


func version_label() -> Label:
	return _version


func disclaimer_label() -> Label:
	return _disclaimer


func howto_text() -> String:
	return HowToScript.plain_text(bindings)


func _on_entry_hover(i: int) -> void:
	if not _howto_open:
		_set_selected(i)


func _on_entry_pressed(i: int) -> void:
	if not _howto_open:
		activate(i)


# ---- input ---------------------------------------------------------------------------------------

## Which menu action a key code maps to under data/bindings.json: "up", "down", "confirm",
## "back" or "" (unbound for the menu).
func action_for_key(code: int) -> String:
	var kb: Dictionary = bindings.get("key_bindings", {})
	if (kb.get("move_forward", []) as Array).has(code):
		return "up"
	if (kb.get("move_back", []) as Array).has(code):
		return "down"
	if (kb.get("jump", []) as Array).has(code) or (kb.get("interact", []) as Array).has(code):
		return "confirm"
	if (kb.get("pause", []) as Array).has(code):
		return "back"
	return ""


func _action_for_joy(button: int) -> String:
	var jb: Dictionary = bindings.get("joy_bindings", {})
	if (jb.has("jump") and int(jb["jump"]) == button) or (jb.has("interact") and int(jb["interact"]) == button):
		return "confirm"
	if button == JOY_BUTTON_DPAD_UP:
		return "up"
	if button == JOY_BUTTON_DPAD_DOWN:
		return "down"
	if button == JOY_BUTTON_START:
		return "back"
	return ""


## The menu's whole input path. Returns true when the event was used.
func handle_input(event: InputEvent) -> bool:
	var action := ""
	if event is InputEventKey:
		var k: InputEventKey = event
		if not k.pressed:
			return false
		var code: int = int(k.keycode) if k.keycode != KEY_NONE else int(k.physical_keycode)
		action = action_for_key(code)
		if k.echo and action != "up" and action != "down":
			return false
	elif event is InputEventJoypadButton:
		var jbe: InputEventJoypadButton = event
		if not jbe.pressed:
			return false
		action = _action_for_joy(int(jbe.button_index))
	elif event is InputEventJoypadMotion:
		var jm: InputEventJoypadMotion = event
		if jm.axis != JOY_AXIS_LEFT_Y:
			return false
		if absf(jm.axis_value) < STICK_THRESHOLD * 0.5:
			_stick_latched = false
			return false
		if _stick_latched or absf(jm.axis_value) < STICK_THRESHOLD:
			return false
		_stick_latched = true
		action = "up" if jm.axis_value < 0.0 else "down"
	if action == "":
		return false
	return _do(action)


func _do(action: String) -> bool:
	if _howto_open:
		match action:
			"up":
				_scroll_panel(-SCROLL_STEP * ui_scale)
			"down":
				_scroll_panel(SCROLL_STEP * ui_scale)
			"confirm", "back":
				close_howto()
		return true
	match action:
		"up":
			move_selection(-1)
		"down":
			move_selection(1)
		"confirm":
			activate(selected)
		"back":
			return false
	return true


func _scroll_panel(dy: float) -> void:
	var bar := _panel_text.get_v_scroll_bar()
	if bar != null:
		bar.value = clampf(bar.value + dy, bar.min_value, bar.max_value)


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if handle_input(event):
		get_viewport().set_input_as_handled()


# ---- per-frame -----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	tick_ui(delta)


## Eases the selection look and the panel slide; pure function of delta (testable headless).
func tick_ui(delta: float) -> void:
	var k: float = clampf(delta * 14.0, 0.0, 1.0)
	for i in _entry_anim.size():
		var target: float = 1.0 if i == selected else 0.0
		var v: float = _entry_anim[i]
		if absf(v - target) > 0.001:
			_entry_anim[i] = lerpf(v, target, k)
			if absf(_entry_anim[i] - target) <= 0.01:
				_entry_anim[i] = target
			_style_entry(i)
	var pt: float = 1.0 if _howto_open else 0.0
	if absf(_panel_t - pt) > 0.001:
		_panel_t = move_toward(_panel_t, pt, delta / 0.18)
	_place_panel()


## Panel visibility, fade and a short slide in from the right (eased by _panel_t).
func _place_panel() -> void:
	_panel.visible = _panel_t > 0.0 or _howto_open
	var e: float = 1.0 - pow(1.0 - _panel_t, 3.0)
	_panel.modulate = Color(1, 1, 1, e)
	var slide: float = (1.0 - e) * 32.0 * ui_scale
	_panel.offset_left = _panel_left + slide
	_panel.offset_right = _panel_right + slide
