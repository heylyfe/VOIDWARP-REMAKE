extends Control
#
# Collapse warning, top-centre (owner bug report "the platforms dont collapse", D-B12-1).
#
# The platform collapse is a slow, outside-in schedule (sim/collapse.gd): the farthest ring
# cracks, falls 5 s later, the next ring cracks 10 s after that, and so on inward. Nothing in
# the HUD said so, so a player who reached the beacon before the first fall never learned the
# void was closing. This element is that warning.
#
# sync(active, cracking, seconds, zones_left):
#   active      false -> hidden (the beacon is not open yet)
#   cracking    true  -> a ring is cracking; `seconds` is the time to its fall
#   zones_left  0     -> only the hub is left
#
# The HUD never writes sim state; the caller (world.gd _sync_hud) reads sim/collapse.gd.

# Sits below the curse/upgrade icon rows (view/hud/icon_rows.gd: top 8, two 40 px cells and a
# 6 px gap, so it ends at y = 94) and above the play area.
const EDGE := 100.0
const WIDTH := 460.0
const HEIGHT := 34.0
const TEXT_COLOR := Color("#7CFFF4")
const DIM_COLOR := Color("#8FE8E0")

var _active := false
var _cracking := false
var _seconds := 0.0
var _zones_left := 0
var _label: Label


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
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", TEXT_COLOR)
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)
	visible = false
	_refresh()


func sync(p_active: bool, p_cracking: bool, p_seconds: float, p_zones_left: int) -> void:
	_active = p_active
	_cracking = p_cracking
	_seconds = maxf(0.0, p_seconds)
	_zones_left = maxi(0, p_zones_left)
	visible = _active
	_refresh()


## The exact HUD string (tests assert on it).
func warning_text() -> String:
	if not _active:
		return ""
	if _zones_left <= 0:
		return "ONLY THE HUB REMAINS"
	var n := int(ceil(_seconds))
	if _cracking:
		return "THE VOID IS CLOSING  -  RING FALLS IN %ds" % n
	return "NEXT RING IN %ds" % n


func _refresh() -> void:
	if _label == null:
		return
	_label.text = warning_text()
	_label.add_theme_color_override("font_color", TEXT_COLOR if _cracking else DIM_COLOR)
