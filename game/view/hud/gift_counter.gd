extends Control
#
# Gift counter, bottom-centre (ticket T-025; DESIGN.md section 14, section 3; restyled
# to the reference panel language in D-GUI-1).
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
#
# Look (D-GUI-1): a dark rounded pill, a small gift-square icon, then the number pair
# in the large monospace display size - the reference's "1 / 46". During the gold phase
# hud.gd hides this pill and shows gold_counter.gd (a subclass) in the same slot.

const HudStyle := preload("res://view/hud/hud_style.gd")

const WIDTH := HudStyle.COUNTER_W
const HEIGHT := HudStyle.COUNTER_H
const ICON := 18.0

var _collected := 0
var _total := 0
var _label: Label
var _icon: Control


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -WIDTH * 0.5
	offset_right = WIDTH * 0.5
	offset_top = -HudStyle.COUNTER_BOTTOM - HEIGHT
	offset_bottom = -HudStyle.COUNTER_BOTTOM
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	HudStyle.add_background(self)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_icon = _GiftIcon.new()
	_icon.custom_minimum_size = Vector2(ICON, ICON)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(_icon as _GiftIcon).gold = _is_gold()
	row.add_child(_icon)
	_label = Label.new()
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	HudStyle.style_label(_label, HudStyle.FONT_DISPLAY,
			HudStyle.GOLD_TEXT if _is_gold() else HudStyle.TEXT, true)
	row.add_child(_label)
	_refresh()


func sync(p_collected: int, p_total: int) -> void:
	_collected = maxi(0, p_collected)
	_total = maxi(0, p_total)
	_refresh()


## The exact HUD string: "collected / REAL total".
func counter_text() -> String:
	return "%d / %d" % [_collected, _total]


## The gold subclass answers true (gold icon, gold text).
func _is_gold() -> bool:
	return false


func _refresh() -> void:
	if _label != null:
		_label.text = counter_text()


## The small gift square: hollow white for a black-phase gift (the reference's square),
## filled gold with a ribbon cross for a gold gift.
class _GiftIcon extends Control:
	var gold := false

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size).grow(-1.0)
		if gold:
			draw_rect(r.grow(3.0), Color(1.0, 0.82, 0.30, 0.22), true)
			draw_rect(r, Color(1.0, 0.82, 0.30, 1.0), true)
			var c := r.get_center()
			draw_line(Vector2(c.x, r.position.y), Vector2(c.x, r.end.y), Color(1.0, 0.96, 0.8, 1.0), 2.0)
			draw_line(Vector2(r.position.x, c.y), Vector2(r.end.x, c.y), Color(1.0, 0.96, 0.8, 1.0), 2.0)
		else:
			draw_rect(r, Color(0.0, 0.0, 0.0, 0.6), true)
			draw_rect(r, Color(0.94, 0.94, 0.97, 1.0), false, 2.0)
