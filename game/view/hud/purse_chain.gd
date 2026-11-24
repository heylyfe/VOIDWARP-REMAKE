extends Control
#
# Purse + chain multiplier, top-right (ticket T-025; DESIGN.md section 14 and
# section 3.2; ticket T-022's economy).
#
# Format per section 3.2's worked example: `149.00  1.50x` - centi-gold rendered
# as whole.cents (integer math, floor semantics, matching data/economy.json
# gold_arithmetic), then the chain as x with two decimals. The purse comes from
# economy.purse_centi; the chain from economy.chain_display(). Styled as a dark rounded
# pill (D-GUI-1, view/hud/hud_style.gd).

const HudStyle := preload("res://view/hud/hud_style.gd")
const AssetLoadScript := preload("res://view/asset_load.gd")

const EDGE := HudStyle.MARGIN
const WIDTH := 240.0
const HEIGHT := HudStyle.PILL_H
const ICON_SIZE := 22.0
const ICON_GAP := 8.0
# U4: the icon is a guarded load, not a preload - a missing png must not break this
# script's load (a preload of a missing resource fails the whole file at parse time).
# The pill then draws its number alone.
const GOLD_BALANCE_ICON_PATH := "res://assets/icons/gold_balance.png"
# U4 test seam: the icon path, default the real art; a test re-points it and re-runs
# _load_icon() to prove a missing png only hides the icon.
var icon_path := GOLD_BALANCE_ICON_PATH


func _load_icon() -> void:
	_icon.texture = AssetLoadScript.texture(icon_path)
	if _icon.texture == null:
		_icon.visible = false   # no icon art: the purse number still reads

var _purse_centi := 0
var _chain := 1.0
var _label: Label
var _icon: TextureRect


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
	# D-GUI-1: a dark rounded pill (the reference's top-right panels)
	HudStyle.add_background(self)
	# icon glued to the left of the number: an end-aligned row that sizes to its
	# content, so the gap never opens up as the purse value's width changes
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = HudStyle.PAD_X
	row.offset_right = -HudStyle.PAD_X
	row.add_theme_constant_override("separation", int(ICON_GAP))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_icon = TextureRect.new()
	_load_icon()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_icon)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.size_flags_vertical = Control.SIZE_FILL
	HudStyle.style_label(_label, HudStyle.FONT_BODY, HudStyle.GOLD_TEXT)
	row.add_child(_label)
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
