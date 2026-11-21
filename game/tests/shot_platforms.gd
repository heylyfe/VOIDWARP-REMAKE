extends SceneTree
#
# Platform-solidity screenshot tool (owner report "platforms look hollow"): boots the REAL world
# (app/world.gd) on a level and frames one platform edge so its slab SIDE and UNDERSIDE fill
# the shot. Before the level_mesher winding fix the sides were culled and the slab read as a
# see-through dark box; after it they must read as a solid block with the trim band on top.
# Windowed run - rendering needs a GPU context, never --headless:
#
#   <godot> --path game --script res://tests/shot_platforms.gd -- <out_dir> [seed] [level]
#
# Writes <out_dir>/lvl<N>_00_side_below.png  (from below and outside: side + underside)
#        <out_dir>/lvl<N>_01_side_level.png  (level with the slab: the side face square-on)
#        <out_dir>/lvl<N>_02_oblique.png     (above a corner, the owner's screenshot angle)
# Prints a DIAG line (picked tile, its exposed sides, slab_side triangle count, the centre
# pixel of the side shot) so a blank shot is not mistaken for a fixed one.
#
# Named shot_platforms.gd, not test_*, so tests/run_all.gd does not discover it (it needs a
# window; the headless gate has none). Prints "SHOT <path>" per PNG and "SHOTPLATFORMS OK" /
# "SHOTPLATFORMS FAIL <why>"; exit 1 on failure. A verification tool, not a gate step.

const WorldScript := preload("res://app/world.gd")
const MesherScript := preload("res://view/level_mesher.gd")

const SHOT_SIZE := Vector2i(1280, 720)
const DT := 1.0 / 60.0
const SETTLE_TICKS := 20
const HU := 0.5
const ROLES_HUB := 0

var _out_dir := ""
var _seed := 7
var _level := 1
var _fail := ""
var _world = null


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	root.size = SHOT_SIZE
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() >= 1:
		_out_dir = args[0]
	if args.size() >= 2:
		_seed = int(args[1])
	if args.size() >= 3:
		_level = int(args[2])
	if _out_dir == "":
		_out_dir = ProjectSettings.globalize_path("res://shots_platforms")
	var mk := DirAccess.make_dir_recursive_absolute(_out_dir)
	if mk != OK:
		_fail = "cannot create %s (DirAccess error %d)" % [_out_dir, mk]
		_finish()
		return

	_world = WorldScript.new()
	root.add_child(_world)
	# votes:{} suppresses the lobby vote, so no enemy spawns; the level geometry is real.
	if not _world.build(_seed, _level, {"votes": {}}):
		_fail = "world.build(%d, %d) returned false" % [_seed, _level]
		_finish()
		return
	for _i in SETTLE_TICKS:
		_world.step(DT)
	if _world.camera == null:
		_fail = "world has no camera"
		_finish()
		return

	var pick := _pick_edge_tile(_world.lv)
	if pick.is_empty():
		_fail = "no non-hub flat tile with an exposed +z side and open air below it"
		_finish()
		return
	var x := float(pick[0])
	var z := float(pick[1])
	var top := float(pick[2]) * HU
	var cx := x + 0.5
	var face_z := z + 1.0    # the exposed +z side plane
	var cam: Camera3D = _world.camera

	# 00: below and outside the +z side, looking up at the side and the underside.
	cam.global_position = Vector3(cx + 1.5, top - 3.0, face_z + 3.5)
	cam.look_at(Vector3(cx, top - 1.0, face_z - 0.5), Vector3.UP)
	await _shot("lvl%d_00_side_below" % _level)
	var centre := _centre_pixel()

	# 01: level with the slab, the side face square-on.
	cam.global_position = Vector3(cx, top - 0.5, face_z + 3.0)
	cam.look_at(Vector3(cx, top - 0.5, face_z), Vector3.UP)
	await _shot("lvl%d_01_side_level" % _level)

	# 02: above a corner, the angle of the owner's screenshot.
	cam.global_position = Vector3(cx + 3.0, top + 2.5, face_z + 4.0)
	cam.look_at(Vector3(cx, top - 0.5, face_z - 1.0), Vector3.UP)
	await _shot("lvl%d_02_oblique" % _level)

	var side_tris := -1
	var mr: Dictionary = MesherScript.build(_world.lv)
	if (mr["meshes"] as Dictionary).has("slab_side"):
		@warning_ignore("integer_division")
		side_tris = (mr["meshes"]["slab_side"] as ArrayMesh).surface_get_array_index_len(0) / 3
	print("DIAG seed=%d level=%d tile=(%d,%d,y%d) exposed=%s slab_side_tris=%d side_below_centre=%s" % [
		_seed, _level, int(pick[0]), int(pick[1]), int(pick[2]), str(pick[3]), side_tris, centre])
	_finish()


## A flat tile of a non-hub piece whose +z neighbour column holds no tile within 2 HU of it
## (so the +z side is exposed) and whose column and +z column are empty for 12 HU below (so a
## camera underneath sees open air, not another floor). Prefers the most exposed tile.
## Returns [x, z, y, exposed dirs] or [] when none qualifies.
func _pick_edge_tile(L: Dictionary) -> Array:
	var hub := -1
	for p in L.get("pieces", []):
		if int(p["role"]) == ROLES_HUB:
			hub = int(p["id"])
	var cols := {}
	for t in L.get("tiles", []):
		var k := "%d,%d" % [int(t[0]), int(t[1])]
		if not cols.has(k):
			cols[k] = []
		(cols[k] as Array).append(int(t[2]))
	var best: Array = []
	var best_score := -1
	for t in L.get("tiles", []):
		if int(t[3]) != 0 or int(t[4]) == hub:
			continue
		var x := int(t[0])
		var z := int(t[1])
		var y := int(t[2])
		if not _clear_below(cols, x, z + 1, y + 2, 14) or not _clear_below(cols, x, z, y - 1, 12):
			continue
		var exposed: Array = []
		var dirs := [[1, 0, "+x"], [0, 1, "+z"], [-1, 0, "-x"], [0, -1, "-z"]]
		for d in dirs:
			if _clear_below(cols, x + int(d[0]), z + int(d[1]), y + 2, 4):
				exposed.append(d[2])
		if not exposed.has("+z"):
			continue
		if exposed.size() > best_score:
			best_score = exposed.size()
			best = [x, z, y, exposed]
	return best


## True when column (x, z) has no tile with y in [from_y - span, from_y].
func _clear_below(cols: Dictionary, x: int, z: int, from_y: int, span: int) -> bool:
	for y2 in cols.get("%d,%d" % [x, z], []):
		if int(y2) <= from_y and int(y2) >= from_y - span:
			return false
	return true


func _centre_pixel() -> String:
	var img: Image = root.get_texture().get_image()
	if img == null:
		return "none"
	return img.get_pixel(img.get_width() / 2, img.get_height() / 2).to_html(false)


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	if img == null:
		_fail = "viewport texture returned null for %s" % name
		return
	var path := _out_dir.path_join(name + ".png")
	var err := img.save_png(path)
	if err != OK:
		_fail = "save_png(%s) error %d" % [path, err]
		return
	print("SHOT %s" % path)


func _finish() -> void:
	if _world != null:
		_world.teardown()
		_world.queue_free()
		_world = null
	if _fail != "":
		print("SHOTPLATFORMS FAIL %s" % _fail)
		quit(1)
		return
	print("SHOTPLATFORMS OK")
	quit(0)