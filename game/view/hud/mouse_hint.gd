extends Control
#
# The mouse-lock hint, bottom-centre under the gift counter (D-GUI-1; the owner's reference
# build: a dim monospace "CTRL TO LOCK/UNLOCK MOUSE"). The CTRL toggle itself is
# app/camera_rig.gd next_mouse_locked, applied in app/world.gd; this element only says
# what pressing CTRL will do NOW, so the words are always true:
#   mouse locked   -> "CTRL TO UNLOCK MOUSE"
#   mouse free     -> "CTRL TO LOCK MOUSE"
# The state arrives in the HUD snapshot ("mouse_locked", world.gd _sync_hud reads its own
# _mouse_locked, the same flag it hands to camera_rig.mouse_mode_for). No panel: the
# reference draws it as bare dim text hugging the bottom edge.

const HudStyle := preload("res://view/hud/hud_style.gd")

const WIDTH := 320.0
const HEIGHT := HudStyle.HINT_H
const TEXT_LOCKED := "CTRL TO UNLOCK MOUSE"
const TEXT_FREE := "CTRL TO LOCK MOUSE"

var locked := false
var _label: Label


func _init() -> void:
	name = "MouseHint"
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -WIDTH * 0.5
	offset_right = WIDTH * 0.5
	offset_top = -HudStyle.HINT_BOTTOM - HEIGHT
	offset_bottom = -HudStyle.HINT_BOTTOM
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	HudStyle.style_label(_label, HudStyle.FONT_SMALL, HudStyle.TEXT_DIM, true)
	_label.add_theme_constant_override("outline_size", 0)
	add_child(_label)
	_refresh()


func sync(p_locked: bool) -> void:
	if p_locked == locked and _label.text != "":
		return
	locked = p_locked
	_refresh()


## The exact on-screen string (tests assert on it).
func hint_text() -> String:
	return TEXT_LOCKED if locked else TEXT_FREE


func _refresh() -> void:
	_label.text = hint_text()
