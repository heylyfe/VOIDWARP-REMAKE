extends RefCounted
#
# test_micro_levels.gd (ticket T-075, piece 2 of 3): the five answer-lab
# micro-levels build through REAL sim code and have the geometry the ticket
# states. Pieces:
#   - each of the five builds through sim/level_state.gd's build() without error;
#   - flat_lane is 1 tile wide and 24 u long; stepped_lane is 2 wide with at
#     least one 2 HU height step; nook is a dead end on a 1-wide walkway; pad is
#     7x7; hub builds (205 tiles, the TERRAIN_SPEC section 6.1 shape);
#   - one WALK: a real T-012 controller (the way test_gifts.gd drives it) runs
#     the flat lane end to end - that is what makes the lane usable by piece 3's
#     answer bots.
# Module status: fixture module game/tools/bot/micro_levels.gd is additive;
# voidgen / level_state / the sim are not touched by this ticket piece.

const MicroLevels := preload("res://tools/bot/micro_levels.gd")
const LevelStateScript := preload("res://sim/level_state.gd")
const ControllerScript := preload("res://sim/controller.gd")
const CollisionScript := preload("res://sim/collision.gd")

const DT := 1.0 / 60.0
const WALK_TICKS := 1200    # 20 s of sim: the lane takes ~3 s at run speed

const HU := 0.5             # 1 tile y = 0.5 u (LevelState.HU)


func run() -> Array[String]:
	var f: Array[String] = []
	_five_ids(f)
	_builds_through_level_state(f)
	_flat_lane_shape(f)
	_stepped_lane_shape(f)
	_nook_shape(f)
	_pad_shape(f)
	_hub_shape(f)
	_flat_lane_walk(f)
	return f


func _five_ids(f: Array[String]) -> void:
	var want := ["flat_lane", "hub", "nook", "pad", "stepped_lane"]
	var got: Array = MicroLevels.ids()
	if got != want:
		f.append("micro_levels ids %s, want %s" % [str(got), str(want)])


func _builds_through_level_state(f: Array[String]) -> void:
	for id in MicroLevels.ids():
		var L: Dictionary = MicroLevels.build(id)
		if L.is_empty():
			f.append("%s: build() returned an empty dict" % id)
			continue
		for key in ["gen_version", "seed", "level", "players", "extra_mines", "attempt",
				"beacon", "spawns", "arms", "pieces", "tiles", "props", "edges",
				"gifts", "anchors", "pads"]:
			if not L.has(key):
				f.append("%s: level dict lacks key '%s'" % [id, key])
		var st = LevelStateScript.build(L, 1, 1)
		if st == null or st.level_dict.is_empty():
			f.append("%s: LevelState.build() failed" % id)
			continue
		if st.players.size() != 1:
			f.append("%s: LevelState spawned %d players, want 1" % [id, st.players.size()])
		if st.columns.is_empty():
			f.append("%s: LevelState built no ground columns" % id)
		if st.gifts.total_real != 0:
			f.append("%s: fixture carries %d real gift slots, want 0" % [id, st.gifts.total_real])
		var spawn: Dictionary = st.players[0]
		var col = st.ground_at(float(spawn["x"]), float(spawn["z"]))
		if col == null:
			f.append("%s: the spawn tile has no ground column" % id)


# ---------------------------------------------------------------- shapes --

func _tiles_in(L: Dictionary) -> Array:
	return L["tiles"]


func _span(tiles: Array, axis: int) -> int:
	var lo: int = int(tiles[0][axis])
	var hi: int = lo
	for t in tiles:
		if int(t[axis]) < lo:
			lo = int(t[axis])
		if int(t[axis]) > hi:
			hi = int(t[axis])
	return hi - lo + 1


func _flat_lane_shape(f: Array[String]) -> void:
	var L: Dictionary = MicroLevels.build("flat_lane")
	var tiles: Array = _tiles_in(L)
	if tiles.size() != MicroLevels.FLAT_LANE_LEN:
		f.append("flat_lane: %d tiles, want %d (24 u of 1 u tiles)" % [tiles.size(), MicroLevels.FLAT_LANE_LEN])
	if _span(tiles, 1) != 1:
		f.append("flat_lane: not 1 tile wide (z span %d)" % _span(tiles, 1))
	if _span(tiles, 0) != MicroLevels.FLAT_LANE_LEN:
		f.append("flat_lane: x span %d, want %d u" % [_span(tiles, 0), MicroLevels.FLAT_LANE_LEN])
	for t in tiles:
		if int(t[2]) != 0:
			f.append("flat_lane: tile at %s is not flat" % str(t))


func _stepped_lane_shape(f: Array[String]) -> void:
	var L: Dictionary = MicroLevels.build("stepped_lane")
	var tiles: Array = _tiles_in(L)
	if _span(tiles, 1) != 2:
		f.append("stepped_lane: z span %d, want 2 tiles wide" % _span(tiles, 1))
	if _span(tiles, 0) != MicroLevels.STEPPED_LANE_LEN:
		f.append("stepped_lane: x span %d, want %d u" % [_span(tiles, 0), MicroLevels.STEPPED_LANE_LEN])
	var heights: Dictionary = {}
	for t in tiles:
		heights["%d,%d" % [t[0], t[1]]] = int(t[2])
	var low := 0
	var found_step := false
	for t in tiles:
		var e: Array = t
		var x: int = int(e[0])
		var z: int = int(e[1])
		var west = heights.get("%d,%d" % [x - 1, z])
		if west != null and absi(int(west) - int(e[2])) == MicroLevels.STEPPED_RISE_HU:
			found_step = true
		if int(e[2]) == 0:
			low += 1
	if not found_step:
		f.append("stepped_lane: no %d HU rise found along the lane" % MicroLevels.STEPPED_RISE_HU)
	if low == 0 or low == tiles.size():
		f.append("stepped_lane: %d of %d tiles at y0 - both halves missing" % [low, tiles.size()])
	# the rise is 2 HU of world height, not 2 tiles of y
	for t in tiles:
		if int(t[2]) == MicroLevels.STEPPED_RISE_HU + 1:
			f.append("stepped_lane: a rise tile is %d HU up, the ticket says 2" % (int(t[2]) - 0))
			break


func _nook_shape(f: Array[String]) -> void:
	var L: Dictionary = MicroLevels.build("nook")
	var tiles: Array = _tiles_in(L)
	if tiles.size() != 19:
		f.append("nook: %d tiles, want 19 (16 walkway + 3 pocket)" % tiles.size())
	var cells: Dictionary = {}
	for t in tiles:
		cells["%d,%d" % [t[0], t[1]]] = true
	# the walkway is 1 wide: exactly 3 tiles off the z=0 line (the pocket)
	var off_lane := 0
	for t in tiles:
		if int(t[1]) != 0:
			off_lane += 1
	if off_lane != 3:
		f.append("nook: %d tiles off the z=0 walkway, want 3 (the pocket)" % off_lane)
	# the pocket's first tile opens onto the walkway, 1 tile wide
	if not (cells.has("12,0") and cells.has("12,1")):
		f.append("nook: the pocket mouth at (12,0)-(12,1) is missing")
	# the pocket is 1 wide, 3 deep, tip at (12,3) with exactly one neighbour
	var deg := 0
	var neighbours := [[1, 0], [-1, 0], [0, 1], [0, -1]]
	for n in neighbours:
		if cells.has("%d,%d" % [12 + int(n[0]), 3 + int(n[1])]):
			deg += 1
	if deg != 1:
		f.append("nook: pocket tip (12,3) has %d neighbours, want exactly 1 (a dead end)" % deg)


func _pad_shape(f: Array[String]) -> void:
	var L: Dictionary = MicroLevels.build("pad")
	var tiles: Array = _tiles_in(L)
	if tiles.size() != MicroLevels.PAD_SIZE * MicroLevels.PAD_SIZE:
		f.append("pad: %d tiles, want %d" % [tiles.size(), MicroLevels.PAD_SIZE * MicroLevels.PAD_SIZE])
	if _span(tiles, 0) != MicroLevels.PAD_SIZE or _span(tiles, 1) != MicroLevels.PAD_SIZE:
		f.append("pad: span %dx%d, want %dx%d" % [_span(tiles, 0), _span(tiles, 1),
				MicroLevels.PAD_SIZE, MicroLevels.PAD_SIZE])
	for t in tiles:
		if int(t[2]) != 0:
			f.append("pad: tile %s is not flat" % str(t))


func _hub_shape(f: Array[String]) -> void:
	var L: Dictionary = MicroLevels.build("hub")
	var tiles: Array = _tiles_in(L)
	if tiles.size() != 205:
		f.append("hub: %d tiles, want 205 (TERRAIN_SPEC section 6.1)" % tiles.size())
	var dais := 0
	var props: Array = L["props"]
	for t in tiles:
		var in_dais: bool = absi(int(t[0])) <= 2 and absi(int(t[1])) <= 2
		if in_dais:
			dais += 1
			if int(t[2]) != 1:
				f.append("hub: dais tile %s is not one half-unit up" % str(t))
				break
	if dais != 25:
		f.append("hub: %d dais tiles, want 25" % dais)
	if props.size() != 4:
		f.append("hub: %d props, want the 4 plaza pillars" % props.size())


# ----------------------------------------------------------------- walk --

## A real dasher-class controller walks the flat lane end to end. This is the
## gate piece 3's answer bots must clear on every level: bot input dicts in,
## ctl.step out, feet on tiles the whole way.
func _flat_lane_walk(f: Array[String]) -> void:
	var L: Dictionary = MicroLevels.build("flat_lane")
	var w: Dictionary = CollisionScript.make_world(L["tiles"], L["props"], L["pads"],
			{"dais": L["beacon"]})
	var ctl = ControllerScript.new()
	ctl.setup("dasher", ControllerScript.load_constants())
	ctl.place(w)
	var a_in: Dictionary = {"move_x": 127, "move_z": 0, "buttons": 0,
			"aim_x": 0.0, "aim_z": 1.0}
	var reached := false
	for i in WALK_TICKS:
		ctl.step(DT, a_in, w)
		if ctl.dead:
			f.append("flat_lane walk: the controller died at tick %d (%s)" % [i, str(ctl.dead_code)])
			return
		# far end: the lane spans x 0..23; success = feet at/inside tile 23's
		# centre, checked BEFORE the fall test (past the tip there is no column,
		# and that is arrival, not a fall)
		if float(ctl.x) >= float(MicroLevels.FLAT_LANE_LEN - 1) + 0.5:
			reached = true
			break
		var gx := LevelStateScript.floor_i(ctl.x)
		var gz := LevelStateScript.floor_i(ctl.z)
		if ctl.grounded and not _column_has(w, gx, gz):
			f.append("flat_lane walk: the controller fell off the lane at tick %d (x=%.2f)"
					% [i, float(ctl.x)])
			return
	if not reached:
		f.append("flat_lane walk: after %d ticks the controller reached x=%.2f, want >= %.2f"
				% [WALK_TICKS, float(ctl.x), float(MicroLevels.FLAT_LANE_LEN - 1) + 0.5])


func _column_has(w: Dictionary, x: int, z: int) -> bool:
	return w["cols"].has("%d,%d" % [x, z])

