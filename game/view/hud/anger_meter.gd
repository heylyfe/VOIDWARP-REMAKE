extends Control
#
# The clawd counter + anger meter, top-centre (cycle 7, track T4; D-T4-8).
#
# The owner's words (CYCLE7_BRIEF.md T4): "HUD: a small anger/timer indicator and a clawd counter (view side)".
# One pill carries both, because they are one mechanic: the clawds left are the clock.
#
#   "CLAWD 3 / 8   CALM 42s"      calm: the seconds until the next warning (or the kill)
#   "CLAWD 3 / 8   ANGRY 1:12"    after warning 1: the border lights up
#   "CLAWD 3 / 8   CLAUDE 0:48"   after warning 2: the border pulses red
#   "CLAWD 3 / 8   PAUSED"        the beacon is open: the timer is frozen (D-T4-5)
#
# sync(feed): feed is world.gd's _clawd_feed() dict - {active, taken, total, anger_ticks, warned,
# kill_ticks, next_at, paused}. An absent dict or active == false hides the pill (the level carries no swarm).
# The HUD never writes sim state; the caller reads sim/clawds.gd.
#
# Sits below the collapse warning (hud_style.gd COLLAPSE_TOP + PILL_H + GAP = 174) in the same top-centre
# column, so it never shares pixels with the icon rows or the collapse pill (tests/test_hud_gui.gd leg 4).

const HudStyle := preload("res://view/hud/hud_style.gd")

const EDGE := HudStyle.COLLAPSE_TOP + HudStyle.PILL_H + HudStyle.GAP   # 174
const WIDTH := 460.0
const HEIGHT := HudStyle.PILL_H
const TEXT_COLOR := Color("#7CFFF4")
const WARN_COLOR := Color("#FFD24A")     # warning 1: amber
const KILL_COLOR := Color("#FF2A2A")    # warning 2: the hazard red
const PAUSE_COLOR := Color("#8FE8E0")

var _active := false
var _taken := 0
var _total := 0
var _anger := 0
var _warned := 0
var _kill := 10800
var _next_at := 10800
var _paused := false
var _label: Label
var _bg: Panel


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -WIDTH * 0.5
	offset_right = WIDTH * 0.5
	offset_top = EDGE
	offset_bottom = EDGE + HEIGHT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg = HudStyle.add_background(self)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	HudStyle.style_label(_label, HudStyle.FONT_BODY, TEXT_COLOR)
	add_child(_label)
	visible = false
	_refresh()


func sync(feed: Dictionary) -> void:
	_active = bool(feed.get("active", false))
	_taken = maxi(0, int(feed.get("taken", 0)))
	_total = maxi(0, int(feed.get("total", 0)))
	_anger = maxi(0, int(feed.get("anger_ticks", 0)))
	_warned = clampi(int(feed.get("warned", 0)), 0, 2)
	_kill = maxi(1, int(feed.get("kill_ticks", 10800)))
	_next_at = maxi(_anger, int(feed.get("next_at", _kill)))
	_paused = bool(feed.get("paused", false))
	visible = _active
	_refresh()


## The exact HUD string (tests assert on it).
func meter_text() -> String:
	if not _active:
		return ""
	var head := "CLAWD %d / %d" % [_taken, _total]
	if _paused:
		return "%s   PAUSED" % head
	var left := maxi(_next_at - _anger, 0)
	var secs := int(ceil(float(left) / 60.0))
	if _warned >= 2:
		return "%s   CLAUDE %d:%02d" % [head, secs / 60, secs % 60]
	if _warned == 1:
		return "%s   ANGRY %d:%02d" % [head, secs / 60, secs % 60]
	return "%s   CALM %ds" % [head, secs]


## The border colour the current warning level asks for (the test target).
func border_color() -> Color:
	if _paused:
		return PAUSE_COLOR
	if _warned >= 2:
		return KILL_COLOR
	if _warned == 1:
		return WARN_COLOR
	return HudStyle.PANEL_BORDER


func _refresh() -> void:
	if _label == null:
		return
	_label.text = meter_text()
	_label.add_theme_color_override("font_color", border_color() if _warned > 0 else TEXT_COLOR)
	var sb := _bg.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		sb.border_color = border_color()
		sb.set_border_width_all(2 if _warned > 0 else 1)
