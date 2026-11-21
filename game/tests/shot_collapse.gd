extends SceneTree
#
# Collapse screenshot tool (B10): boots the REAL world (app/world.gd) on a level, opens the
# beacon, and captures the sequential outside-in collapse as a player sees it. Windowed run -
# rendering needs a GPU context, never --headless:
#
#   <godot> --path game --script res://tests/shot_collapse.gd -- <out_dir> [seed] [level]
#
# Writes <out_dir>/lvl<N>_00_eye.png, _01_zone0.png, _01b_crackclose.png, _02_zone1.png:
#   00  eye level on a platform of the farthest zone, looking inward at the dais
#   01  a close oblique on that zone, half-way through its crack
#   01b straight down on one of its tiles, close enough to read a crack line
#   02  the whole level once that zone is gone and the next zone inward is cracking
# Prints a DIAG line with the zone count, the cracking zone's tile count and whether its
# overlay is actually visible, so a blank shot is not mistaken for a subtle one.
#
# Named shot_collapse.gd, not test_*, so tests/run_all.gd does not discover it (it needs a
# window; the headless gate has none). Prints "SHOT <path>" per PNG and "SHOTCOLLAPSE OK" /
# "SHOTCOLLAPSE FAIL <why>"; exit 1 on failure. A verification tool, not a gate step.

const WorldScript := preload("res://app/world.gd")
const CollapseScript := preload("res://sim/collapse.gd")

const SHOT_SIZE := Vector2i(1280, 720)
const DT := 1.0 / 60.0
const SETTLE_TICKS := 20

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
		_out_dir = ProjectSettings.globalize_path("res://shots_collapse")
	var mk := DirAccess.make_dir_recursive_absolute(_out_dir)
	if mk != OK:
		_fail = "cannot create %s (DirAccess error %d)" % [_out_dir, mk]
		_finish()
		return

	_world = WorldScript.new()
	root.add_child(_world)
	# votes:{} suppresses the lobby vote, so no enemy spawns and nothing kills the player
	# mid-shot; the level geometry, gifts, mines and the collapse are all real.
	if not _world.build(_seed, _level, {"votes": {}}):
		_fail = "world.build(%d, %d) returned false" % [_seed, _level]
		_finish()
		return
	for _i in SETTLE_TICKS:
		_world.step(DT)

	var st: Dictionary = _world._collapse
	if CollapseScript.zone_count(st) < 2:
		_fail = "level %d seed %d has %d zones; need >= 2 to show the sequence" % [
			_level, _seed, CollapseScript.zone_count(st)]
		_finish()
		return

	# Open the beacon through its own API and take the open edge: zone 0 cracks now.
	_world.lstate.beacon.open(int(_world.lstate.tick))
	_world.step(DT)
	var t0 := int(_world.lstate.tick)
	var crack := int(st["crack_ticks"])
	var gap := int(st["gap_ticks"])

	# 00: eye level on a platform of the farthest zone, looking inward at the dais - what a
	# human standing on the ring that is about to go actually sees.
	_steps_until(t0 + crack / 2)
	_frame_eye(st, 0)
	await _shot("lvl%d_00_eye" % _level)

	# 01: a close oblique on the zone that is cracking, so the crack network fills the frame.
	_frame_zone(st, 0)
	await _shot("lvl%d_01_zone0" % _level)
	_diag(st, 0)

	# 01b: right down on one zone-0 tile, to prove the crack decal is actually drawn.
	_frame_tile(st, 0)
	await _shot("lvl%d_01b_crackclose" % _level)

	# 02: zone 0 gone, zone 1 cracking, framed on the whole level so the hole reads.
	_steps_until(t0 + crack + gap + crack / 2)
	_frame_level(st)
	await _shot("lvl%d_02_zone1" % _level)
	_finish()


func _steps_until(target: int) -> void:
	while int(_world.lstate.tick) < target:
		_world.step(DT)


## Eye level on the first tile of zone zi, looking at the dais: the player's own view of the
## ring that is cracking under them.
func _frame_eye(st: Dictionary, zi: int) -> void:
	var cam: Camera3D = _world.camera
	if cam == null:
		return
	var keys: Array = CollapseScript.zone_keys(st, zi)
	if keys.is_empty():
		return
	var p: PackedStringArray = str(keys[0]).split(",")
	var x := float(p[0]) + 0.5
	var z := float(p[1]) + 0.5
	var b: Array = _world.lv["beacon"]
	var dx := float(b[0]) + 0.5
	var dz := float(b[1]) + 0.5
	cam.global_position = Vector3(x, 1.7, z)
	cam.look_at(Vector3(dx, 1.0, dz), Vector3.UP)


## Frame one zone: centroid of its tiles, camera above and to the south of it.
func _frame_zone(st: Dictionary, zi: int) -> void:
	var cam: Camera3D = _world.camera
	if cam == null:
		return
	var keys: Array = CollapseScript.zone_keys(st, zi)
	if keys.is_empty():
		return
	var sx := 0.0
	var sz := 0.0
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for k in keys:
		var p: PackedStringArray = str(k).split(",")
		var x := float(p[0]) + 0.5
		var z := float(p[1]) + 0.5
		sx += x
		sz += z
		lo = Vector2(minf(lo.x, x), minf(lo.y, z))
		hi = Vector2(maxf(hi.x, x), maxf(hi.y, z))
	var n := float(keys.size())
	var cx := sx / n
	var cz := sz / n
	var ext: float = maxf(maxf(hi.x - lo.x, hi.y - lo.y), 8.0)
	cam.global_position = Vector3(cx, ext * 0.45 + 4.0, cz + ext * 0.55 + 5.0)
	cam.look_at(Vector3(cx, 0.0, cz), Vector3.UP)


## Frame the whole level from over the dais, so a missing ring reads as a hole.
func _frame_level(st: Dictionary) -> void:
	var cam: Camera3D = _world.camera
	if cam == null:
		return
	var b: Array = _world.lv["beacon"]
	var dx := float(b[0]) + 0.5
	var dz := float(b[1]) + 0.5
	var r: float = maxf(float(st["radius"]), 10.0)
	cam.global_position = Vector3(dx, r * 0.55 + 5.0, dz + r * 0.75 + 6.0)
	cam.look_at(Vector3(dx, 0.0, dz), Vector3.UP)


## Print what the view thinks it is drawing, so a blank shot is not mistaken for a subtle one.
func _diag(st: Dictionary, zi: int) -> void:
	var cv = _world.collapse_view
	if cv == null:
		print("DIAG no collapse_view")
		return
	var ov: MeshInstance3D = cv.overlays[zi]
	var surf := -1
	if ov.mesh != null:
		surf = (ov.mesh as ArrayMesh).get_surface_count()
	print("DIAG zones=%d zone%d_keys=%d overlay_visible=%s overlay_mesh=%s surfaces=%d progress=%.2f any_visible=%s" % [
		CollapseScript.zone_count(st), zi, CollapseScript.zone_keys(st, zi).size(),
		str(ov.visible), str(ov.mesh != null), surf,
		CollapseScript.crack_progress(st, int(_world.lstate.tick), zi),
		str(cv.any_overlay_visible())])


## Straight down on the first tile of zone zi, close enough to read a crack line.
func _frame_tile(st: Dictionary, zi: int) -> void:
	var cam: Camera3D = _world.camera
	if cam == null:
		return
	var keys: Array = CollapseScript.zone_keys(st, zi)
	if keys.is_empty():
		return
	var p: PackedStringArray = str(keys[0]).split(",")
	var x := float(p[0]) + 0.5
	var z := float(p[1]) + 0.5
	cam.global_position = Vector3(x, 6.0, z + 7.0)
	cam.look_at(Vector3(x, 0.0, z), Vector3.UP)


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
		print("SHOTCOLLAPSE FAIL %s" % _fail)
		quit(1)
		return
	print("SHOTCOLLAPSE OK")
	quit(0)
