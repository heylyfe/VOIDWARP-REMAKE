extends RefCounted
#
# The HUD's one panel language (D-GUI-1, the owner's reference build): dark translucent
# rounded panels, light text, one type scale, one padding, one screen margin. Every
# element in this folder reads its numbers from here, so the HUD cannot drift into
# five different looks again.
#
# Layout grid at any viewport (every element is anchored, so 1280x720 and 1920x1080 hold
# the same arrangement; tests/test_hud_gui.gd checks both for bounds and overlap):
#   top-left      enemy roster            (MARGIN, MARGIN)
#   top-centre    curse / upgrade rows    y = MARGIN .. ICON_ROWS_BOTTOM
#                 collapse warning        y = COLLAPSE_TOP .. COLLAPSE_TOP + PILL_H
#   top-right     purse + chain pill, cartographer map under it
#   bottom-left   void pips pill, class ability pill to its right
#   bottom-centre gift counter (black phase) / gold counter (gold phase), same slot,
#                 and the CTRL mouse hint under it

const MARGIN := 16.0          # screen edge to every panel
const GAP := 8.0              # between two neighbouring panels
const PAD_X := 14.0           # inside a panel, left / right
const PAD_Y := 8.0            # inside a panel, top / bottom
const RADIUS := 10            # panel corner radius
const PILL_H := 40.0          # a one-line pill (purse, collapse warning)

# The type scale: three sizes, nothing else.
const FONT_SMALL := 13        # badges, radar distances, the mouse hint, seconds text
const FONT_BODY := 18         # pill text (purse, collapse warning)
const FONT_DISPLAY := 34      # the gift / gold counter

const PANEL_BG := Color(0.055, 0.055, 0.085, 0.74)
const PANEL_BORDER := Color(1.0, 1.0, 1.0, 0.08)
const TEXT := Color(0.94, 0.94, 0.97, 1.0)
const TEXT_DIM := Color(0.86, 0.86, 0.92, 0.55)
const GOLD := Color(1.0, 0.82, 0.30, 1.0)
const GOLD_TEXT := Color(1.0, 0.93, 0.72, 1.0)
const ACCENT := Color(0.486, 1.0, 0.957)   # #7CFFF4, the void cyan

# Shared slot geometry (top-centre stack and bottom-centre stack).
const ICON_CELL := 40.0
const ICON_GAP := 6.0
const ICON_ROWS_TOP := MARGIN
const ICON_ROWS_BOTTOM := ICON_ROWS_TOP + PAD_Y * 2.0 + ICON_CELL * 2.0 + ICON_GAP   # 118
const COLLAPSE_TOP := ICON_ROWS_BOTTOM + GAP                                          # 126
const HINT_H := 18.0
const HINT_BOTTOM := 10.0     # the hint hugs the bottom edge, like the reference
const COUNTER_W := 240.0
const COUNTER_H := 60.0
const COUNTER_BOTTOM := HINT_BOTTOM + HINT_H + 6.0   # counter pill sits just above the hint
const BOTTOM_ROW_H := 64.0    # void pips pill and class ability pill share this height

static var _mono: Font = null


## A fresh StyleBoxFlat in the panel language (fresh: callers may tint their copy).
static func panel() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = PANEL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(RADIUS)
	sb.anti_aliasing = true
	sb.content_margin_left = PAD_X
	sb.content_margin_right = PAD_X
	sb.content_margin_top = PAD_Y
	sb.content_margin_bottom = PAD_Y
	return sb


## A smaller-radius cell backing (icon cells inside a panel).
static func cell() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 1.0, 1.0, 0.06)
	sb.set_corner_radius_all(6)
	sb.anti_aliasing = true
	return sb


## A full-rect background Panel for `host` (added as its first child).
static func add_background(host: Control) -> Panel:
	var bg := Panel.new()
	bg.name = "Background"
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override("panel", panel())
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(bg)
	host.move_child(bg, 0)
	return bg


## The monospace face (the counter and the mouse hint, as in the reference). A system
## font with fallbacks; the engine default stands in when none is installed.
static func mono() -> Font:
	if _mono == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Consolas", "JetBrains Mono", "DejaVu Sans Mono",
				"Liberation Mono", "Courier New", "monospace"])
		f.font_weight = 700
		_mono = f
	return _mono


## Apply the scale to a Label: size, colour, and a soft outline for legibility on the sky.
static func style_label(l: Label, size: int, color: Color = TEXT, mono_face: bool = false) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.7))
	l.add_theme_constant_override("outline_size", 2 if size <= FONT_SMALL else 3)
	if mono_face:
		l.add_theme_font_override("font", mono())
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
