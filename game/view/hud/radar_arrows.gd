extends Control
#
# Radar arrows (ticket T-053, addendum R4, D-T053-8): a 24 px chevron at the screen
# edge pointing at the target, with the distance in u under it. One overlay per
# target source the player owns a radar for; the caller (hud.gd wiring) builds the
# entry list from the pure sim queries:
#   RadarMines  -> sim/upgrades.gd mine_outline_ids()   (mine radar, 14 u)
#   RadarGifts  -> sim/upgrades.gd nearest_real_gift()  (gift radar, 40/80 u)
#   RadarThreats-> sim/upgrades.gd threat_markers()     (threat radar, 30 u)
#   RadarBeacon -> sim/upgrades.gd beacon_compass()     (a compass, always on-screen)
# Angles are world-space atan2(dz, dx) read straight onto the screen (the world is
# top-down-on-screen: +x right, +z down), no camera yaw folding - the same contract
# the T-025 HUD elements use.

const HudStyle := preload("res://view/hud/hud_style.gd")

const CHEVRON := 24.0
const EDGE_MARGIN := 4.0
const FONT_SIZE := HudStyle.FONT_SMALL   # D-GUI-1: the HUD type scale
const LABEL_COLOR := Color(1.0, 1.0, 1.0, 0.9)
const CHEVRON_COLOR := Color(1.0, 1.0, 1.0, 1.0)

var _items: Array = []   # [{pos: Vector2, angle: float, dist: float, label: Label}]


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## entries: [{angle: float radians (screen-space atan2(dz, dx)), dist: float u}].
func sync(p_entries: Array) -> void:
	for it in _items:
		it["label"].queue_free()
	_items.clear()
	var vp := size
	if vp.x < 1.0 or vp.y < 1.0:
		return
	for entry in p_entries:
		var pos := _chevron_pos(float(entry["angle"]), vp)
		var label := Label.new()
		label.text = "%d u" % int(round(float(entry["dist"])))
		HudStyle.style_label(label, FONT_SIZE, LABEL_COLOR)
		label.position = pos + Vector2(-14.0, CHEVRON * 0.5 + 2.0)
		add_child(label)
		_items.append({"pos": pos, "angle": float(entry["angle"]),
				"dist": float(entry["dist"]), "label": label})
	queue_redraw()


## The chevron centre: from the viewport centre along the angle, clamped so the
## 24 px chevron sits fully at the screen edge (EDGE_MARGIN in from the border).
static func _chevron_pos(angle: float, vp: Vector2) -> Vector2:
	var c := vp * 0.5
	var dir := Vector2(cos(angle), sin(angle))
	var half := (vp * 0.5) - Vector2(CHEVRON * 0.5 + EDGE_MARGIN, CHEVRON * 0.5 + EDGE_MARGIN)
	# Walk to the edge: the largest t keeping the chevron inside is the smaller of
	# the |half.x / dir.x| and |half.y / dir.y| hits.
	var tx := INF if absf(dir.x) < 1e-9 else absf(half.x / dir.x)
	var ty := INF if absf(dir.y) < 1e-9 else absf(half.y / dir.y)
	return c + dir * minf(tx, ty)


func _draw() -> void:
	for it in _items:
		_draw_chevron(it["pos"], it["angle"])


func _draw_chevron(c: Vector2, angle: float) -> void:
	var dir := Vector2(cos(angle), sin(angle))
	var side := dir.orthogonal() * (CHEVRON * 0.5)
	var back := -dir * (CHEVRON * 0.5)
	var pts := PackedVector2Array([
		c + side * 0.7 + back,
		c + dir * (CHEVRON * 0.5),
		c - side * 0.7 + back,
	])
	draw_polyline(pts, CHEVRON_COLOR, 3.0, true)
