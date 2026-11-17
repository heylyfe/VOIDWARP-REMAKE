extends Control
#
# Cartographer's minimap (ticket T-053, addendum R4, D-T053-2, D-T053-8): a 220 px
# square, top-right under the purse, north-up (+z = down on screen), pieces as
# filled shapes in their biome colour, real gifts as 2 px dots, the player as a
# white triangle, every piece within 40 u of anywhere the player has stood.
#
# The reveal set comes from sim/upgrades.gd revealed() (gift slots, unconsumed
# mines, the beacon) plus the piece tiles: this widget walks level_dict["tiles"]
# ([x, z, y, kind, pid]) and level_dict["pieces"] ([id, kind, ...]) and keeps only
# tiles the footprints reach. Piece colour: piece kind 0 (platform) and 1 (walkway)
# read the caller's biome palette (the current biome's platform_light/walkway_light
# - view reads content through core, so the caller passes the two Colors in).

const CartographerContent := preload("res://content/upgrades/cartographer.gd")

const SIZE := 220.0
const EDGE := 24.0
const GAP := 8.0
const GIFT_DOT_R := 1.0
const MINE_DOT_R := 2.0
const PLAYER_COLOR := Color(1.0, 1.0, 1.0, 1.0)
## The reveal radius squared, in u^2 (the content script owns the 40 u figure).
const CARTO_RANGE2 := 1600.0

var _model: Array = []   # draw items; see build_model()
var _range_u := 40.0


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -EDGE - SIZE
	offset_right = -EDGE
	offset_top = EDGE + 36.0 + GAP   # the purse row: EDGE + HEIGHT(36), one gap below
	offset_bottom = EDGE + 36.0 + GAP + SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## One frame's model. lv: the LevelState; p_index: the player; centre/scale: the
## drawn window (scale = px per u, centred on the player's x/z); colours: at least
## {"platform": Color, "walkway": Color, "gift": Color, "mine": Color, "beacon": Color}.
func sync(lv: RefCounted, p_index: int, scale_px: float, colours: Dictionary) -> void:
	if lv == null or lv.upgrades == null or not lv.upgrades.has("cartographer"):
		_model = []
		queue_redraw()
		return
	_range_u = CartographerContent.REVEAL_RANGE_U
	var p: Dictionary = lv.players[p_index]
	var visited: Dictionary = lv.upgrades.visited.get(p_index, {})
	_model = build_model(lv.level_dict, visited, float(p["x"]), float(p["z"]),
			scale_px, colours, SIZE)
	queue_redraw()


## The draw model, pure and testable: piece tiles as filled rects (piece kind 0 =
## colours["platform"], 1 = colours["walkway"]), mines as filled pink dots,
## real gifts as 2 px dots, the beacon as its colour's filled dot, the player as a
## white triangle pointing at facing (radians; -PI/2 = up/north). North-up: world
## +x = screen right, world +z = screen down.
static func build_model(level_dict: Dictionary, visited: Dictionary, px: float,
		pz: float, scale_px: float, colours: Dictionary, size_px: float,
		facing: float = -PI / 2.0) -> Array:
	var out: Array = []
	if level_dict.is_empty():
		return out
	var c := size_px * 0.5
	# Piece tiles the footprints reach (piece kind 0 platform, 1 walkway -> biome).
	var pieces: Array = level_dict["pieces"]
	for t in level_dict["tiles"]:
		var tx := float(t[0]) + 0.5
		var tz := float(t[1]) + 0.5
		if not _near_any(visited, tx, tz, CARTO_RANGE2):
			continue
		var pid := int(t[4])
		if pid < 0 or pid >= pieces.size():
			continue
		var pk: int = int(pieces[pid]["kind"])
		var key := "walkway" if pk == 1 else "platform"
		if not colours.has(key):
			continue
		var col: Color = colours[key]
		var org := Vector2(c + (float(t[0]) - px) * scale_px,
				c + (float(t[1]) - pz) * scale_px)
		out.append({"rect": Rect2(org, Vector2(scale_px + 0.5, scale_px + 0.5)),
				"color": col})
	for row in revealed_rows(level_dict, visited, px, pz):
		var ppos := Vector2(c + (float(row["x"]) - px) * scale_px,
				c + (float(row["z"]) - pz) * scale_px)
		if row["kind"] == "gift":
			out.append({"dot": ppos, "r": GIFT_DOT_R, "color": colours.get("gift", Color())})
		elif row["kind"] == "mine":
			out.append({"dot": ppos, "r": MINE_DOT_R, "color": colours.get("mine", Color())})
		else:
			out.append({"dot": ppos, "r": 3.0, "color": colours.get("beacon", Color())})
	out.append({"triangle": _player_tri(Vector2(c, c), facing),
			"color": PLAYER_COLOR})
	return out


## The sim reveal rows (gift slots / mines / beacon within the footprint range) -
## read straight from the level dict; the pure sim twin lives in sim/upgrades.gd.
static func revealed_rows(level_dict: Dictionary, visited: Dictionary, px: float,
		pz: float) -> Array:
	var out: Array = []
	var slots: Array = level_dict.get("gifts", [])
	for i in slots.size():
		var s: Dictionary = slots[i]
		var sx := float(int(s["x"])) + 0.5
		var sz := float(int(s["z"])) + 0.5
		if not _near_any(visited, sx, sz, CARTO_RANGE2):
			continue
		if int(s["occ"]) == 0:
			out.append({"kind": "gift", "x": sx, "z": sz})
		else:
			out.append({"kind": "mine", "x": sx, "z": sz})
	var b: Array = level_dict.get("beacon", [])
	if b.size() >= 2:
		var bx := float(int(b[0])) + 0.5
		var bz := float(int(b[1])) + 0.5
		if _near_any(visited, bx, bz, CARTO_RANGE2):
			out.append({"kind": "beacon", "x": bx, "z": bz})
	return out


static func _near_any(tiles: Dictionary, x: float, z: float, r2: float) -> bool:
	for tile in tiles:
		var dx: float = x - (float(tile.x) + 0.5)
		var dz: float = z - (float(tile.y) + 0.5)
		if dx * dx + dz * dz <= r2:
			return true
	return false


static func _player_tri(c: Vector2, facing: float) -> PackedVector2Array:
	var dir := Vector2(cos(facing), sin(facing))
	var side := dir.orthogonal()
	return PackedVector2Array([
		c + dir * 6.0,
		c + side * 3.5 - dir * 4.0,
		c - side * 3.5 - dir * 4.0,
	])


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), Color(0.0, 0.0, 0.0, 0.45), true)
	for item in _model:
		if item.has("rect"):
			draw_rect(item["rect"], item["color"] as Color, true)
		elif item.has("dot"):
			draw_circle(item["dot"], float(item["r"]), item["color"] as Color)
		elif item.has("triangle"):
			draw_colored_polygon(item["triangle"], PLAYER_COLOR)
