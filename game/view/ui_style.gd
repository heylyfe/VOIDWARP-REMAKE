extends RefCounted
#
# view/ui_style.gd - the ONE front-end style every menu screen uses (D-GUI-1).
#
# Screens: app/menu.gd, app/class_altar.gd, app/pause_overlay.gd, view/settings_menu.gd,
# view/lobby/lobby_hud.gd, app/loading_screen.gd. The in-game HUD (view/hud/*) is not on
# this list and does not read this file.
#
# Layout language: near-black ground, one teal accent used sparingly, compact pills in the
# corners, one centred focal element per screen, 1 px borders, a 2 px corner radius, no
# shadows, no gradients. Numbers are set in a monospace face; labels in a small tracked
# upper-case face.
#
# The palette is the house teal set (data/palette.json roles platform_dark, slab_trim,
# platform_light, black_gift_rim, dead_end_light) plus pure white and pure black. Every
# colour below is one of those seven at some alpha - tests/test_ui_style.gd checks every
# colour override on every screen against PALETTE (alpha ignored).
#
# Focus: every screen keeps keyboard focus itself (FocusCycle below) instead of Godot's
# built-in focus, so ui_accept can never double-fire a button behind a screen's back
# (D-MENU-9). The focused control wears FOCUS RING: a 1 px BRIGHT border with a 3 px
# BRIGHT bar on the left. That ring is the only thing drawn in BRIGHT on a screen.
#
# Pure static helpers + one inner class; nothing here needs the scene tree.

# ---- palette ------------------------------------------------------------------------------
const DEEP := Color(0.0392, 0.1804, 0.1882)      # #0A2E30
const MID := Color(0.1098, 0.4314, 0.4392)       # #1C6E70
const ACCENT := Color(0.1843, 0.7176, 0.6902)    # #2FB7B0
const BRIGHT := Color(0.4863, 1.0, 0.9569)       # #7CFFF4
const SOFT := Color(0.5608, 0.9098, 0.8784)      # #8FE8E0
const WHITE := Color(1.0, 1.0, 1.0)
const BLACK := Color(0.0, 0.0, 0.0)
const PALETTE := [DEEP, MID, ACCENT, BRIGHT, SOFT, WHITE, BLACK]

## Roles (all palette colours at an alpha).
const GROUND := Color(0.0, 0.0, 0.0, 1.0)            # a modal screen's backdrop
const SCRIM := Color(0.0, 0.0, 0.0, 0.78)            # over a live/frozen scene
const PANEL_FILL := Color(0.0, 0.0, 0.0, 0.88)
const TEXT := Color(0.5608, 0.9098, 0.8784, 1.0)     # SOFT: body text
const TEXT_MUTED := Color(0.5608, 0.9098, 0.8784, 0.62)
const TEXT_DIM := Color(0.5608, 0.9098, 0.8784, 0.42)
const TEXT_STRONG := Color(1.0, 1.0, 1.0, 1.0)       # titles, values
const FOCUS := BRIGHT

# ---- type scale (px at the 1280x720 reference; the menu multiplies by its ui_scale) --------
const FS_DISPLAY := 56     # the one wordmark / screen title
const FS_TITLE := 26       # a panel heading, a card name
const FS_ENTRY := 20       # a button / menu entry
const FS_BODY := 15        # running text
const FS_SMALL := 13       # secondary running text
const FS_LABEL := 11       # tracked upper-case labels (pills, captions, key hints)
const FS_NUM := 15         # monospace numbers
const TRACK_LABEL := 2     # glyph spacing of the label face, px
const TRACK_DISPLAY := 8   # glyph spacing of the display face, px

# ---- spacing scale -----------------------------------------------------------------------
const SP_1 := 4
const SP_2 := 8
const SP_3 := 12
const SP_4 := 16
const SP_5 := 24
const SP_6 := 32
const SP_7 := 48
const EDGE := 24           # screen edge inset for corner pills

# ---- shapes ------------------------------------------------------------------------------
const BORDER := 1
const RADIUS := 2
const FOCUS_BAR := 3
const BUTTON_H := 40
const BUTTON_W := 240
const PILL_H := 28
const PAD_X := 16          # button / panel horizontal content margin
const PAD_Y := 8
const PANEL_PAD := 24
const MIN_PAD := 4         # every label keeps at least this much room inside its own rect

## Button kinds.
const PRIMARY := "primary"       # the one action a screen exists for
const SECONDARY := "secondary"   # everything else
const GHOST := "ghost"           # list rows (the main menu entries)
const ROW := "row"               # a settings row (caption + control + value)

const MONO_NAMES := ["Cascadia Mono", "Consolas", "JetBrains Mono", "DejaVu Sans Mono",
		"Liberation Mono", "Menlo", "Courier New", "monospace"]

static var _cache: Dictionary = {}


# ---- faces -------------------------------------------------------------------------------

## The four faces. "body" is Godot's built-in fallback (ships inside every export, D-MENU-9);
## "label" is the same face emboldened and tracked; "display" heavier and wide-tracked;
## "mono" is the first installed monospace system face, with tabular digits from the fallback
## behind it (the fallback's "tnum" feature) so a number never jitters even on a machine
## without one. Cached: every screen shares one object per face.
static func font(p_role: String) -> Font:
	if _cache.has(p_role):
		return _cache[p_role]
	var f: Font
	match p_role:
		"mono":
			var tab := FontVariation.new()
			tab.base_font = ThemeDB.fallback_font
			tab.opentype_features = {"tnum": 1}
			var sf := SystemFont.new()
			sf.font_names = PackedStringArray(MONO_NAMES)
			sf.fallbacks = [tab]
			f = sf
		"label":
			f = _variation(0.45, TRACK_LABEL)
		"display":
			f = _variation(0.85, TRACK_DISPLAY)
		"strong":
			f = _variation(0.5, 1)
		_:
			f = _variation(0.0, 0)
	_cache[p_role] = f
	return f


static func _variation(p_embolden: float, p_spacing: int) -> FontVariation:
	var v := FontVariation.new()
	v.base_font = ThemeDB.fallback_font
	v.variation_embolden = p_embolden
	v.spacing_glyph = p_spacing
	return v


## A private copy of a face whose tracking the caller scales (the menu's wordmark).
static func scaled_face(p_embolden: float) -> FontVariation:
	return _variation(p_embolden, 0)


# ---- text --------------------------------------------------------------------------------

## The role's face and size. "label" text is upper-cased by label().
static func role_font(p_role: String) -> Font:
	match p_role:
		"display":
			return font("display")
		"title", "entry":
			return font("strong")
		"label":
			return font("label")
		"num":
			return font("mono")
	return font("body")


static func role_size(p_role: String) -> int:
	match p_role:
		"display":
			return FS_DISPLAY
		"title":
			return FS_TITLE
		"entry":
			return FS_ENTRY
		"small":
			return FS_SMALL
		"label":
			return FS_LABEL
		"num":
			return FS_NUM
	return FS_BODY


static func role_color(p_role: String) -> Color:
	match p_role:
		"display", "title", "num":
			return TEXT_STRONG
		"label", "small":
			return TEXT_MUTED
	return TEXT


## One label in a role: "display", "title", "entry", "body", "small", "label", "num".
## p_color.a < 0 = the role's own colour. Never takes the mouse.
static func label(p_text: String, p_role: String = "body", p_color: Color = Color(0, 0, 0, -1)) -> Label:
	var l := Label.new()
	style_label(l, p_role, p_color)
	l.text = p_text.to_upper() if p_role == "label" else p_text
	return l


static func style_label(l: Label, p_role: String, p_color: Color = Color(0, 0, 0, -1)) -> void:
	l.add_theme_stylebox_override("normal", pad_box())
	l.add_theme_font_override("font", role_font(p_role))
	l.add_theme_font_size_override("font_size", role_size(p_role))
	l.add_theme_color_override("font_color", role_color(p_role) if p_color.a < 0.0 else p_color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE


## The empty box every label draws in: MIN_PAD on all four sides, so no text ever touches
## the edge of its own rect (tests/test_ui_style.gd FIT).
static func pad_box() -> StyleBoxEmpty:
	if not _cache.has("_pad"):
		var sb := StyleBoxEmpty.new()
		sb.set_content_margin_all(MIN_PAD)
		_cache["_pad"] = sb
	return _cache["_pad"]


## The height a label of p_role needs for p_text wrapped in a p_width-wide rect, padding
## and line spacing included (the class altar sizes its cards with this).
static func text_height(p_text: String, p_role: String, p_width: float, p_size: int = -1) -> float:
	var f := role_font(p_role)
	var fs := role_size(p_role) if p_size < 0 else p_size
	var ts := f.get_multiline_string_size(p_text, HORIZONTAL_ALIGNMENT_LEFT,
			p_width - 2.0 * MIN_PAD, fs)
	var lines := maxi(1, int(roundf(ts.y / f.get_height(fs))))
	return ts.y + 3.0 * float(lines - 1) + 2.0 * MIN_PAD


## A 1 px accent rule under a heading.
static func rule(p_width: float = 32.0, p_align: int = Control.SIZE_SHRINK_BEGIN) -> ColorRect:
	var r := ColorRect.new()
	r.name = "Rule"
	r.color = ACCENT
	r.custom_minimum_size = Vector2(p_width, 1)
	r.size_flags_horizontal = p_align
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## A full-rect backdrop.
static func backdrop(p_color: Color = GROUND) -> ColorRect:
	var bg := ColorRect.new()
	bg.name = "Backdrop"
	bg.color = p_color
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return bg


# ---- boxes -------------------------------------------------------------------------------

## The one StyleBoxFlat shape: p_fill, a p_border-wide edge in p_edge, optional left bar,
## RADIUS corners, no shadow, no anti-aliased glow. Margins are content margins in px.
static func box(p_fill: Color, p_edge: Color, p_border: int = BORDER, p_bar: int = 0,
		p_pad_x: float = PAD_X, p_pad_y: float = PAD_Y) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = p_fill
	sb.border_color = p_edge
	sb.set_border_width_all(p_border)
	sb.border_width_left = maxi(p_border, p_bar)
	sb.set_corner_radius_all(RADIUS)
	sb.shadow_size = 0
	sb.anti_aliasing = false
	sb.content_margin_left = p_pad_x + float(maxi(p_bar - p_border, 0))
	sb.content_margin_right = p_pad_x
	sb.content_margin_top = p_pad_y
	sb.content_margin_bottom = p_pad_y
	return sb


## A panel: near-black fill, 1 px MID edge, PANEL_PAD inside.
static func panel_box(p_pad: float = PANEL_PAD) -> StyleBoxFlat:
	return box(PANEL_FILL, MID, BORDER, 0, p_pad, p_pad)


## The focus ring (see the header): what the focused control of any screen wears.
static func focus_box(p_pad_x: float = PAD_X, p_pad_y: float = PAD_Y) -> StyleBoxFlat:
	return box(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.14), FOCUS, BORDER, FOCUS_BAR, p_pad_x, p_pad_y)


## The resting look per button kind.
static func rest_box(p_kind: String, p_pad_x: float = PAD_X, p_pad_y: float = PAD_Y) -> StyleBoxFlat:
	match p_kind:
		PRIMARY:
			return box(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.18), ACCENT, BORDER, 0, p_pad_x, p_pad_y)
		GHOST:
			return box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, p_pad_x, p_pad_y)
		ROW:
			return box(Color(0, 0, 0, 0), Color(MID.r, MID.g, MID.b, 0.0), BORDER, 0, p_pad_x, p_pad_y)
	return box(Color(0, 0, 0, 0), MID, BORDER, 0, p_pad_x, p_pad_y)


## Mouse-over on a control that is not focused: the edge lifts to ACCENT, nothing else.
static func hover_box(p_kind: String, p_pad_x: float = PAD_X, p_pad_y: float = PAD_Y) -> StyleBoxFlat:
	var sb := rest_box(p_kind, p_pad_x, p_pad_y)
	sb.border_color = ACCENT
	if p_kind == GHOST:
		sb.set_border_width_all(0)
	return sb


## True when p_c currently wears the focus ring (tests/test_ui_style.gd reads this).
static func has_focus_ring(p_c: Control) -> bool:
	var sb: StyleBox = null
	if p_c is Button:
		sb = (p_c as Button).get_theme_stylebox("normal")
	elif p_c is PanelContainer:
		sb = (p_c as PanelContainer).get_theme_stylebox("panel")
	if not (sb is StyleBoxFlat):
		return false
	var f := sb as StyleBoxFlat
	return f.border_width_left >= FOCUS_BAR and f.border_width_top >= BORDER \
			and is_rgb(f.border_color, FOCUS) and f.border_color.a > 0.9


static func is_rgb(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.004 and absf(a.g - b.g) < 0.004 and absf(a.b - b.b) < 0.004


## True when p_c's colour is one of the seven (alpha ignored).
static func in_palette(p_c: Color) -> bool:
	for c in PALETTE:
		if is_rgb(p_c, c):
			return true
	return false


# ---- buttons -----------------------------------------------------------------------------

## Makes p_b a house button of p_kind: face, size, height, no Godot focus (the screen's
## FocusCycle drives the ring), resting look. p_scale multiplies sizes (the menu's ui_scale).
static func style_button(p_b: Button, p_kind: String = SECONDARY, p_scale: float = 1.0) -> void:
	p_b.focus_mode = Control.FOCUS_NONE
	p_b.flat = false
	p_b.add_theme_font_override("font", font("label") if p_kind != GHOST else font("strong"))
	var fs := FS_BODY if p_kind != GHOST else FS_ENTRY
	p_b.add_theme_font_size_override("font_size", maxi(int(roundf(fs * p_scale)), 1))
	p_b.custom_minimum_size.y = maxf(p_b.custom_minimum_size.y, roundf(BUTTON_H * p_scale))
	p_b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	paint(p_b, p_kind, false, p_scale)


## The look of p_b for its focus state. Every state slot gets the same box, so the look is
## the focus ring or the resting look - never Godot's default theme.
static func paint(p_b: Button, p_kind: String, p_focused: bool, p_scale: float = 1.0) -> void:
	var px := roundf(PAD_X * p_scale)
	var py := roundf(PAD_Y * p_scale)
	var sb := focus_box(px, py) if p_focused else rest_box(p_kind, px, py)
	var hv := focus_box(px, py) if p_focused else hover_box(p_kind, px, py)
	for st in ["normal", "pressed", "focus", "disabled"]:
		p_b.add_theme_stylebox_override(st, sb)
	for st in ["hover", "hover_pressed"]:
		p_b.add_theme_stylebox_override(st, hv)
	var col := text_for(p_kind, p_focused)
	for key in ["font_color", "font_hover_color", "font_pressed_color",
			"font_hover_pressed_color", "font_focus_color"]:
		p_b.add_theme_color_override(key, col)
	p_b.add_theme_color_override("font_disabled_color", TEXT_DIM)


static func text_for(p_kind: String, p_focused: bool) -> Color:
	if p_focused:
		return TEXT_STRONG
	match p_kind:
		PRIMARY:
			return TEXT_STRONG
		GHOST:
			return TEXT_MUTED
	return TEXT


# ---- pills and key hints -----------------------------------------------------------------

## A compact corner pill: "LABEL  value" - the tracked label face, then the value in mono.
## Returns the PanelContainer; its value Label is named "Value" (set .text to update it).
static func pill(p_label: String, p_value: String = "", p_scale: float = 1.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "Pill"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", box(PANEL_FILL, Color(MID.r, MID.g, MID.b, 1.0),
			BORDER, 0, roundf(SP_3 * p_scale), roundf(SP_1 * p_scale)))
	p.custom_minimum_size.y = roundf(PILL_H * p_scale)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", int(roundf(SP_2 * p_scale)))
	p.add_child(row)
	if p_label != "":
		var k := label(p_label, "label")
		k.name = "Key"
		k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		k.add_theme_font_size_override("font_size", maxi(int(roundf(FS_LABEL * p_scale)), 1))
		row.add_child(k)
	var v := label(p_value, "num")
	v.name = "Value"
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.add_theme_font_size_override("font_size", maxi(int(roundf(FS_NUM * p_scale)), 1))
	row.add_child(v)
	return p


## One key-hint row: [["TAB", "move"], ["ENTER", "select"], ...] -> small keycaps (1 px
## edge, mono) each followed by its verb in the label face. Never takes the mouse.
static func key_hints(p_pairs: Array, p_scale: float = 1.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "KeyHints"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", int(roundf(SP_4 * p_scale)))
	for pair in p_pairs:
		var one := HBoxContainer.new()
		one.mouse_filter = Control.MOUSE_FILTER_IGNORE
		one.add_theme_constant_override("separation", int(roundf(SP_2 * p_scale)))
		var cap := PanelContainer.new()
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cap.add_theme_stylebox_override("panel", box(Color(0, 0, 0, 0), MID, BORDER, 0,
				roundf(SP_2 * p_scale), roundf(2.0 * p_scale)))
		var k := label(str(pair[0]), "num", TEXT)
		k.add_theme_font_size_override("font_size", maxi(int(roundf(FS_LABEL * p_scale)), 1))
		cap.add_child(k)
		one.add_child(cap)
		var verb := label(str(pair[1]), "label")
		verb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		verb.add_theme_font_size_override("font_size", maxi(int(roundf(FS_LABEL * p_scale)), 1))
		one.add_child(verb)
		row.add_child(one)
	return row


# ---- sliders and toggles -----------------------------------------------------------------

## A house slider: a 2 px MID track, the filled part in ACCENT, a SOFT square grabber,
## at least 32 px tall (the whole row is the hit target), no Godot focus.
static func style_slider(p_s: HSlider) -> void:
	p_s.focus_mode = Control.FOCUS_NONE
	p_s.custom_minimum_size.y = maxf(p_s.custom_minimum_size.y, 32.0)
	p_s.size_flags_vertical = Control.SIZE_FILL
	var track := box(Color(MID.r, MID.g, MID.b, 1.0), Color(0, 0, 0, 0), 0, 0, 0, 1)
	var fill := box(ACCENT, Color(0, 0, 0, 0), 0, 0, 0, 1)
	p_s.add_theme_stylebox_override("slider", track)
	p_s.add_theme_stylebox_override("grabber_area", fill)
	p_s.add_theme_stylebox_override("grabber_area_highlight", fill)
	p_s.add_theme_icon_override("grabber", _swatch("grab", SOFT, Vector2i(8, 16)))
	p_s.add_theme_icon_override("grabber_highlight", _swatch("grab_hi", WHITE, Vector2i(8, 16)))


## A house toggle (CheckButton): a 1 px edged 36x18 track with a square knob - MID and
## left when off, ACCENT and right when on. Text and icons are the palette's only.
static func style_toggle(p_c: CheckButton) -> void:
	p_c.focus_mode = Control.FOCUS_NONE
	p_c.flat = true
	p_c.add_theme_icon_override("unchecked", _toggle_icon(false))
	p_c.add_theme_icon_override("checked", _toggle_icon(true))
	p_c.add_theme_icon_override("unchecked_disabled", _toggle_icon(false))
	p_c.add_theme_icon_override("checked_disabled", _toggle_icon(true))
	p_c.custom_minimum_size.y = maxf(p_c.custom_minimum_size.y, 32.0)
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		p_c.add_theme_stylebox_override(st, empty)


static func _swatch(p_key: String, p_col: Color, p_size: Vector2i) -> ImageTexture:
	if _cache.has(p_key):
		return _cache[p_key]
	var img := Image.create(p_size.x, p_size.y, false, Image.FORMAT_RGBA8)
	img.fill(p_col)
	var t := ImageTexture.create_from_image(img)
	_cache[p_key] = t
	return t


static func _toggle_icon(p_on: bool) -> ImageTexture:
	var key := "toggle_on" if p_on else "toggle_off"
	if _cache.has(key):
		return _cache[key]
	var w := 36
	var h := 18
	var edge: Color = ACCENT if p_on else MID
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in w:
		img.set_pixel(x, 0, edge)
		img.set_pixel(x, h - 1, edge)
	for y in h:
		img.set_pixel(0, y, edge)
		img.set_pixel(w - 1, y, edge)
	var kx := w - 3 - 12 if p_on else 3
	img.fill_rect(Rect2i(kx, 3, 12, h - 6), ACCENT if p_on else MID)
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t
