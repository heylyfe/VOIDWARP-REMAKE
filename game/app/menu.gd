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
# LOOK (D-FRONT-1, view/ui_style.gd; supersedes D-MENU-9's gold): the house teal over the
# house-teal island (D-FRONT-2). One focal column - the wordmark (VOIDWRAP in white, RUN in
# the accent), a 1 px rule, the entries as quiet rows; the selected entry wears the shared
# focus ring. The build pill sits in the bottom-left corner, the disclaimer bottom-right.
#
# INPUT is the game's own mapping (data/bindings.json through app/input_capture.gd, the file the
# play capture reads): move_forward / move_back select (wrapping), jump or interact confirm, pause
# backs out of the HOW TO PLAY panel; Tab / Shift+Tab and Up / Down also walk the entries
# (the shared focus keys, D-FRONT-1). Gamepad: the bound jump / interact buttons confirm, the left
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
const VERSION_TAG := "v0.1.14-alpha.3 pre-release"

## One line under the entries, per entry (what confirming it does).
const ENTRY_HINTS := [
	"Into the void. Level 1.",
	"Void charges, contact kills, the beacon.",
	"Back to the desktop.",
]

const StageScript := preload("res://app/menu_stage.gd")
const HowToScript := preload("res://app/menu_howto.gd")
const InputCaptureScript := preload("res://app/input_capture.gd")
const RecordsScript := preload("res://core/records.gd")
# The menu's own cues (the "too quiet" pass): the hover tick, the click and the music bed.
# Every file is synthesized by game/tools/audio/synth_cues.gd; a missing file is silent,
# never an error (view/audio/cue_audio.gd's house shape).
const UiAudioScript := preload("res://view/audio/ui_audio.gd")
const AmbienceAudioScript := preload("res://view/audio/ambience_audio.gd")

const UiStyle := preload("res://view/ui_style.gd")
const UiFocus := preload("res://view/ui_focus.gd")

## Palette (D-FRONT-1, view/ui_style.gd - supersedes D-MENU-9's gold/indigo). The names are
## the old roles, kept because tests/test_menu.gd reads C_GOLD / C_MUTED: C_GOLD is the
## SELECTED entry's text, C_MUTED an unselected entry's.
const C_VOID := UiStyle.BLACK
const C_WHITE := UiStyle.TEXT_STRONG
const C_GOLD := UiStyle.TEXT_STRONG
const C_MUTED := UiStyle.TEXT_MUTED
const C_DIM := UiStyle.TEXT_DIM

## Layout at the 1280x720 reference (scaled by ui_scale).
const ENTRY_W := 320.0
const ENTRY_H := 48.0
const DISCLAIMER_W := 560.0

const STICK_THRESHOLD := 0.6
const SCROLL_STEP := 48.0

signal play_requested
signal quit_requested

var selected := ENTRY_PLAY
var bindings: Dictionary = {}
var stage: Node3D = null
var ui_scale := 1.0
## Tests point this at a scratch file (app.gd's records_path pattern); "" = the player's real file.
var records_path := ""
var _records: RefCounted = null
var _music: AudioStreamPlayer = null    # the music bed loop; started in _ready, stopped on exit

var _entries: Array[Button] = []
var _entry_anim: Array[float] = []      # 0 = unselected look, 1 = selected look (eased)
var _howto_open := false
var _panel_t := 0.0                     # 0 closed .. 1 open (eased in _process)
var _panel_left := 0.0                  # the panel's resting offsets (set by _apply_scale)
var _panel_right := 0.0
var _stick_latched := false
var _scaled: Array = []                 # [Control, theme font-size key, base px]
var _title_face: FontVariation = UiStyle.scaled_face(0.85)   # the wordmark (tracking scales)
var _focus: UiFocus = UiFocus.new()     # the entries; the ring follows `selected` (D-FRONT-1)

var _viewport_box: SubViewportContainer
var _scrim: ColorRect
var _column: VBoxContainer
var _title_top: Label
var _title_run: Label
var _rule: ColorRect
var _tagline: Label
var _entry_box: VBoxContainer
var _entry_hint: Label
var _keys_hint: RichTextLabel
var _bests: Label
var _version_pill: PanelContainer
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
	# the music bed: a loop that lives as long as the menu does (null when the cue is
	# missing - the menu is never silent-blocked by audio)
	_music = AmbienceAudioScript.start_music(self)


func _exit_tree() -> void:
	# The bed is our own child, so it has already left the tree - and may already be freed -
	# by the time this runs. stop() takes a typed AudioStreamPlayer, so a freed node throws
	# at the call boundary before any guard inside it could run: check here.
	if is_instance_valid(_music):
		AmbienceAudioScript.stop(_music)
	_music = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_scale()


# ---- build ---------------------------------------------------------------------------------------

## One label in a UiStyle role whose size scales with ui_scale (base = the role's px).
func _label(text: String, role: String, color: Color = Color(0, 0, 0, -1), base_px: int = -1) -> Label:
	var l := UiStyle.label(text, role, color)
	_scaled.append([l, "font_size", base_px if base_px > 0 else UiStyle.role_size(role)])
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

	# one flat scrim over the whole stage (no gradient): the island stays the picture, the
	# text reads over it without a box around the column
	_scrim = ColorRect.new()
	_scrim.name = "Scrim"
	_scrim.color = Color(0, 0, 0, 0.30)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_scrim)

	# the menu column: the one focal element (wordmark, entries)
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
	_title_top = _label("VOIDWRAP", "display", C_WHITE)
	_title_top.name = "TitleVoidwrap"
	_title_top.add_theme_font_override("font", _title_face)
	title.add_child(_title_top)
	_title_run = _label("RUN", "display", UiStyle.ACCENT)
	_title_run.name = "TitleRun"
	_title_run.add_theme_font_override("font", _title_face)
	title.add_child(_title_run)
	_rule = UiStyle.rule()
	_column.add_child(_rule)
	_tagline = _label("collect every black gift. mind the void.", "body", C_MUTED)
	_tagline.name = "Tagline"
	_column.add_child(_tagline)
	var gap := Control.new()
	gap.name = "Gap"
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scaled.append([gap, "min_h", 40])
	_column.add_child(gap)

	_entry_box = VBoxContainer.new()
	_entry_box.name = "Entries"
	_entry_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(_entry_box)
	_focus.hover_focus = false          # the entries' own hover handler moves the selection
	for i in MENU_ENTRIES.size():
		var b := Button.new()
		b.name = "Entry%d" % i
		b.text = str(MENU_ENTRIES[i])
		UiStyle.style_button(b, UiStyle.GHOST)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.mouse_entered.connect(_on_entry_hover.bind(i))
		b.pressed.connect(_on_entry_pressed.bind(i))
		_scaled.append([b, "font_size", UiStyle.FS_ENTRY])
		_entry_box.add_child(b)
		_entries.append(b)
		_entry_anim.append(0.0)
		_focus.add(b, UiStyle.GHOST, activate.bind(i), Callable(), _paint_none)
	_entry_hint = _label("", "small", C_DIM)
	_entry_hint.name = "EntryHint"
	_column.add_child(_entry_hint)
	var gap2 := Control.new()
	gap2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scaled.append([gap2, "min_h", 24])
	_column.add_child(gap2)
	_keys_hint = RichTextLabel.new()
	_keys_hint.name = "KeysHint"
	_keys_hint.bbcode_enabled = true
	_keys_hint.fit_content = true
	_keys_hint.scroll_active = false
	_keys_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	_keys_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keys_hint.add_theme_font_override("normal_font", UiStyle.font("label"))
	_keys_hint.add_theme_font_override("bold_font", UiStyle.font("mono"))
	_keys_hint.add_theme_stylebox_override("normal", UiStyle.pad_box())
	_scaled.append([_keys_hint, "normal_font_size", UiStyle.FS_LABEL])
	_scaled.append([_keys_hint, "bold_font_size", UiStyle.FS_LABEL + 1])
	_keys_hint.text = keys_hint_bbcode()
	_column.add_child(_keys_hint)
	# the locally recorded bests (DESIGN.md section 9): one quiet mono line under the key
	# hint - numbers in the mono face, so a 6-digit purse never shifts the line
	_bests = _label("", "num", C_MUTED, UiStyle.FS_SMALL)
	_bests.name = "Bests"
	_column.add_child(_bests)
	refresh_records()

	# corners: the build pill bottom-left, the disclaimer bottom-right (always on screen -
	# the About entry is gone)
	_version_pill = UiStyle.pill("BUILD", VERSION_TAG)
	_version_pill.name = "VersionPill"
	add_child(_version_pill)
	_version = _version_pill.get_node("Row/Value")
	_version.name = "VersionTag"
	_scaled.append([_version, "font_size", UiStyle.FS_LABEL + 1])
	_scaled.append([_version_pill.get_node("Row/Key"), "font_size", UiStyle.FS_LABEL])
	_disclaimer = _label("VOIDWRAP RUN: " + ABOUT_DISCLAIMER, "small", C_DIM, UiStyle.FS_LABEL + 1)
	_disclaimer.name = "Disclaimer"
	_disclaimer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_disclaimer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_disclaimer.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	add_child(_disclaimer)

	_build_howto_panel()


func _paint_none(_c: Control, _on: bool) -> void:
	pass             # the entries are painted by _style_entry (eased), not by the cycle


func _build_howto_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "HowToPanel"
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", UiStyle.panel_box())
	add_child(_panel)
	var vb := VBoxContainer.new()
	vb.name = "Body"
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(vb)
	var head := _label("HOW TO PLAY", "title")
	head.name = "HowToTitle"
	vb.add_child(head)
	vb.add_child(UiStyle.rule())
	_panel_text = RichTextLabel.new()
	_panel_text.name = "HowToText"
	_panel_text.bbcode_enabled = true
	_panel_text.scroll_active = true
	_panel_text.fit_content = false
	_panel_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel_text.add_theme_font_override("normal_font", UiStyle.font("body"))
	_panel_text.add_theme_font_override("bold_font", UiStyle.font("strong"))
	_panel_text.add_theme_color_override("default_color", UiStyle.TEXT)
	_panel_text.add_theme_constant_override("line_separation", 4)
	_panel_text.add_theme_stylebox_override("normal", UiStyle.pad_box())
	_scaled.append([_panel_text, "normal_font_size", UiStyle.FS_BODY])
	_scaled.append([_panel_text, "bold_font_size", UiStyle.FS_BODY])
	vb.add_child(_panel_text)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(row)
	_back_button = Button.new()
	_back_button.name = "BackButton"
	_back_button.text = "BACK"
	_back_button.pressed.connect(close_howto)
	row.add_child(_back_button)
	_panel_hint = _label("", "label", C_DIM)
	_panel_hint.name = "HowToHint"
	_panel_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_panel_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_panel_hint)
	_panel_hint.text = ("%s scroll     %s / %s back" % [
		_keys(["move_forward", "move_back"]), _keys(["jump", "interact"]), _keys(["pause"])]).to_upper()


## "W / S select     SPACE / F confirm" - read from the bindings, never hardcoded. The keys
## in white mono, the verbs in the tracked label face (D-FRONT-1).
func keys_hint_bbcode() -> String:
	return "[color=#FFFFFF][b]%s[/b][/color] [color=#8FE8E0]SELECT[/color]      [color=#FFFFFF][b]%s[/b][/color] [color=#8FE8E0]CONFIRM[/color]" % [
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
		var px: int = maxi(int(roundf(float(item[2]) * ui_scale)), 1)
		if key == "min_h":
			node.custom_minimum_size = Vector2(0, px)
		else:
			node.add_theme_font_size_override(key, px)
	_title_face.spacing_glyph = int(roundf(UiStyle.TRACK_DISPLAY * ui_scale))
	var margin: float = roundf(w * 0.065)
	var edge: float = roundf(UiStyle.EDGE * ui_scale)
	_column.anchor_left = 0.0
	_column.anchor_right = 0.0
	_column.anchor_top = 0.0
	_column.anchor_bottom = 1.0
	_column.offset_left = margin
	_column.offset_right = margin + roundf(520.0 * ui_scale)
	_column.offset_top = roundf(40.0 * ui_scale)
	_column.offset_bottom = -roundf(90.0 * ui_scale)
	_column.add_theme_constant_override("separation", int(roundf(UiStyle.SP_2 * ui_scale)))
	_entry_box.add_theme_constant_override("separation", int(roundf(UiStyle.SP_1 * ui_scale)))
	_rule.custom_minimum_size = Vector2(roundf(32.0 * ui_scale), 1)
	for b in _entries:
		b.custom_minimum_size = Vector2(roundf(ENTRY_W * ui_scale), roundf(ENTRY_H * ui_scale))
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# the build pill: bottom-left corner, growing up from the edge
	_version_pill.anchor_left = 0.0
	_version_pill.anchor_right = 0.0
	_version_pill.anchor_top = 1.0
	_version_pill.anchor_bottom = 1.0
	_version_pill.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_version_pill.offset_left = margin
	_version_pill.offset_right = margin
	_version_pill.offset_top = -edge
	_version_pill.offset_bottom = -edge
	_version_pill.custom_minimum_size.y = roundf(UiStyle.PILL_H * ui_scale)
	# the disclaimer: bottom-right corner, wrapped to a quiet block, growing up
	_disclaimer.anchor_left = 1.0
	_disclaimer.anchor_right = 1.0
	_disclaimer.anchor_top = 1.0
	_disclaimer.anchor_bottom = 1.0
	_disclaimer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var dw: float = roundf(DISCLAIMER_W * ui_scale)
	var dh: float = ceilf(UiStyle.text_height(_disclaimer.text, "small", dw,
			_disclaimer.get_theme_font_size("font_size")))
	_disclaimer.offset_right = -edge
	_disclaimer.offset_left = -edge - dw
	_disclaimer.offset_bottom = -edge
	_disclaimer.offset_top = -edge - dh
	_version_pill.reset_size()
	# the panel: right side, clear of the menu column
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	# the panel starts right of the title (it never clips the wordmark)
	var title_w: float = maxf(_title_top.get_combined_minimum_size().x, 440.0 * ui_scale)
	_panel_left = margin + title_w + roundf(36.0 * ui_scale)
	_panel_right = -roundf(48.0 * ui_scale)
	_panel.offset_top = roundf(52.0 * ui_scale)
	_panel.offset_bottom = -roundf(96.0 * ui_scale)
	var pad: float = roundf(UiStyle.PANEL_PAD * ui_scale)
	_panel.add_theme_stylebox_override("panel", UiStyle.panel_box(pad))
	(_panel.get_node("Body") as VBoxContainer).add_theme_constant_override("separation",
			int(roundf(UiStyle.SP_3 * ui_scale)))
	_panel_text.text = HowToScript.bbcode(bindings).replace("{h}", str(int(roundf(UiStyle.FS_TITLE * 0.7 * ui_scale))))
	_back_button.custom_minimum_size = Vector2(roundf(160.0 * ui_scale), 0)
	UiStyle.style_button(_back_button, UiStyle.SECONDARY, ui_scale)
	UiStyle.paint(_back_button, UiStyle.SECONDARY, true, ui_scale)   # the panel's only control
	for i in _entries.size():
		_style_entry(i)
	_place_panel()


## The entry look, eased by _entry_anim (0 = resting ghost row, 1 = the shared focus ring):
## the ring's edge fades in, the left bar grows to UiStyle.FOCUS_BAR, the faint accent fill
## comes up and the text goes from C_MUTED to C_GOLD (white).
func _style_entry(i: int) -> void:
	var b: Button = _entries[i]
	var t: float = _entry_anim[i]
	var px: float = roundf(UiStyle.PAD_X * ui_scale)
	var py: float = roundf(UiStyle.PAD_Y * ui_scale)
	var sb: StyleBoxFlat
	if t >= 0.999:
		sb = UiStyle.focus_box(px, py)
	else:
		var a := UiStyle.ACCENT
		sb = UiStyle.box(Color(a.r, a.g, a.b, 0.14 * t), Color(UiStyle.FOCUS.r, UiStyle.FOCUS.g,
				UiStyle.FOCUS.b, t), UiStyle.BORDER if t > 0.01 else 0,
				int(roundf(UiStyle.FOCUS_BAR * t)), px, py)
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, sb)
	var col: Color = C_MUTED.lerp(C_GOLD, t)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, col)


# ---- selection + activation ----------------------------------------------------------------------

func _set_selected(i: int, snap: bool = false) -> void:
	selected = posmod(i, MENU_ENTRIES.size())
	_focus.index = selected          # the shared ring follows the selection (D-FRONT-1)
	_entry_hint.text = str(ENTRY_HINTS[selected])
	if snap:
		for k in _entry_anim.size():
			_entry_anim[k] = 1.0 if k == selected else 0.0
			_style_entry(k)


func move_selection(step: int) -> void:
	_set_selected(selected + step)
	UiAudioScript.play_hover(self)


func activate(i: int) -> void:
	_set_selected(i)
	UiAudioScript.play_click(self)
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


## The keyboard focus registry (tests/test_ui_style.gd reads it); its index is `selected`.
func focus_cycle() -> UiFocus:
	return _focus


func version_label() -> Label:
	return _version


## Re-read the records file (records_path, or the default user://records.json) and refresh the
## bests line. Called once from _build; tests call it after pointing records_path at a scratch
## file. A missing/corrupt file reads as 0/0 (records.gd's contract) - never an error here.
func refresh_records() -> void:
	_records = RecordsScript.new()
	_records.load_from(records_path if records_path != "" else RecordsScript.DEFAULT_PATH)
	if _bests != null:
		_bests.text = "BEST LEVEL %d     BEST PURSE %d" % [_records.get_best_level(), _records.get_best_purse()]


func bests_label() -> Label:
	return _bests


func disclaimer_label() -> Label:
	return _disclaimer


func howto_text() -> String:
	return HowToScript.plain_text(bindings)


func _on_entry_hover(i: int) -> void:
	if not _howto_open:
		if i != selected:
			UiAudioScript.play_hover(self)
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
		# D-FRONT-1: Tab / Shift+Tab and the arrow keys walk the entries on every screen. Enter
		# stays inert here (D-MENU-9: confirm is the game's jump / interact binding).
		if action == "" and code == KEY_TAB:
			action = "up" if k.shift_pressed else "down"
		elif action == "" and code == KEY_UP:
			action = "up"
		elif action == "" and code == KEY_DOWN:
			action = "down"
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
