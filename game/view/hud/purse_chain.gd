extends Control
#
# Purse + chain multiplier, top-right (ticket T-025; DESIGN.md section 14 and
# section 3.2; ticket T-022's economy).
#
# Format per section 3.2's worked example: `149.00  1.50x` - centi-gold rendered
# as whole.cents (integer math, floor semantics, matching data/economy.json
# gold_arithmetic), then the chain as x with two decimals. The purse comes from
# economy.purse_centi; the chain from economy.chain_display().

const EDGE := 24.0
const WIDTH := 260.0
const HEIGHT := 36.0

var _purse_centi := 0
var _chain := 1.0
var _label: Label


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -EDGE - WIDTH
	offset_right = -EDGE
	offset_top = EDGE
	offset_bottom = EDGE + HEIGHT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(1.0, 0.956, 0.8, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)
	_refresh()


func sync(p_purse_centi: int, p_chain: float) -> void:
	_purse_centi = maxi(0, p_purse_centi)
	_chain = maxf(1.0, p_chain)
	_refresh()


## e.g. "149.00  1.50x" (cents floored, never rounded up).
func purse_text() -> String:
	return "%d.%02d  %.2fx" % [_purse_centi / 100, _purse_centi % 100, _chain]


func _refresh() -> void:
	if _label != null:
		_label.text = purse_text()
