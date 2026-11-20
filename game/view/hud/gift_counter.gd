extends Control
#
# Gift counter, bottom-centre (ticket T-025; DESIGN.md section 14, section 3).
#
# "gifts collected / REAL total" - the only denominator that counts is the REAL
# black gift total (sim/gifts.gd total_real: every occ == 0 slot; tripmines
# occ == 1 are never a gift, never counted, DESIGN.md section 3.3). Mines are
# excluded by construction: the caller counts collected slots by walking
# is_real() && collected(), so an occ == 1 slot can never be counted.
#
# The caller (hud.gd sync) passes collected/total straight from the gift sim.
# It does NOT compute collected as total_real - remaining(): since the platform
# collapse (sim/gifts.gd lose()) a gift can leave the level without being
# collected, and that subtraction would count it as taken.

const EDGE := 24.0
const WIDTH := 220.0
const HEIGHT := 40.0
const TEXT_COLOR := Color(1.0, 1.0, 1.0, 1.0)

var _collected := 0
var _total := 0
var _label: Label


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -WIDTH * 0.5
	offset_right = WIDTH * 0.5
	offset_top = -EDGE - HEIGHT
	offset_bottom = -EDGE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_color", TEXT_COLOR)
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)
	_refresh()


func sync(p_collected: int, p_total: int) -> void:
	_collected = maxi(0, p_collected)
	_total = maxi(0, p_total)
	_refresh()


## The exact HUD string: "collected / REAL total".
func counter_text() -> String:
	return "%d / %d" % [_collected, _total]


func _refresh() -> void:
	if _label != null:
		_label.text = counter_text()
