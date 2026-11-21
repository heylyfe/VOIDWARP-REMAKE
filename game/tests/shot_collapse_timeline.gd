extends SceneTree
#
# Collapse-retune screenshot tool (cycle 4 item 10, D-B11-1): boots the REAL world
# (app/world.gd), opens the beacon through its own API and captures the collapse timeline.
# Shots 00-02 share ONE camera framed on the outermost ring (zone 0), so they compare frame
# to frame; 03 is framed on the third ring. (A camera over the dais high enough for the
# whole level puts the outer ring 50+ u away, where the fog hides it.)
#   00 quiet   10 s after the open: nothing may crack yet (the 20 s grace)
#   01 crack   0.5 s after the first crack: the outermost ring shows its cracks
#   02 fall    1 s after that ring fell: a hole where the outer ring was, nothing else cracking
#   03 later   the third ring cracking: two rings gone, rings visibly thin (8 u)
# Windowed run - rendering needs a GPU context, never --headless:
#
#   <godot> --path game --script res://tests/shot_collapse_timeline.gd -- <out_dir> [seed] [level]
#
# Prints a DIAG line per shot (seconds since the open, the zone phases, the cracking zone,
# the delay before the first crack in seconds, zone count, the level radius and the ring
# width) so a quiet shot is proven quiet, not merely dark. Named shot_*, not test_*, so
# tests/run_all.gd skips it. Prints "SHOT <path>" per PNG and "SHOTX OK" / "SHOTX FAIL
# <why>"; exit 1 on failure.

const WorldScript := preload("res://app/world.gd")
const CollapseScript := preload("res://sim/collapse.gd")

const SHOT_SIZE := Vector2i(1280, 720)
const DT := 1.0 / 60.0
const HZ := 60

var _out_dir := ""
var _seed := 7
var _level := 1
var _fail := ""
var _world = null
var _open_tick := 0


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	root.size = SHOT_SIZE
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out_dir = args[0] if args.size() >= 1 else ProjectSettings.globalize_path("res://shots_collapse_tl")
	if args.size() >= 2:
		_seed = int(args[1])
	if args.size() >= 3:
		_level = int(args[2])
	if DirAccess.make_dir_recursive_absolute(_out_dir) != OK:
		_fail = "cannot create %s" % _out_dir
		_finish()
		return
	_world = WorldScript.new()
	root.add_child(_world)
	# votes:{} - no enemy spawns, so nothing kills the player mid-timeline
	if not _world.build(_seed, _level, {"votes": {}}):
		_fail = "world.build(%d, %d) returned false" % [_seed, _level]
		_finish()
		return
	for _i in 20:
		_world.step(DT)
	var st: Dictionary = _world._collapse
	if CollapseScript.zone_count(st) < 3:
		_fail = "level %d seed %d has %d zones; need >= 3" % [_level, _seed, CollapseScript.zone_count(st)]
		_finish()
		return
	_open_tick = int(_world.lstate.tick)
	_world.lstate.beacon.open(_open_tick)
	_world.step(DT)
	var t0 := CollapseScript.zone_crack_tick(st, 0)
	var crack := int(st["crack_ticks"])
	var gap := int(st["gap_ticks"])
	var delay_s := float(t0 - _open_tick) / HZ
	print("DIAG timeline open_tick=%d first_crack_tick=%d delay_s=%.2f crack_s=%.1f gap_s=%.1f zones=%d radius=%.1f ring_w=%.2f" % [
			_open_tick, t0, delay_s, crack / float(HZ), gap / float(HZ),
			CollapseScript.zone_count(st), float(st["radius"]),
			float(st["radius"]) / float(CollapseScript.zone_count(st))])
	if absf(delay_s - 20.0) > 0.1:
		_fail = "the first crack is %.2f s after the open, not 20 s" % delay_s

	_steps_until(_open_tick + 10 * HZ)
	await _frame_and_shot(st, 0, "tl_00_quiet_10s")
	if CollapseScript.cracked_keys(st).size() > 0 or _cracking(st) != -1:
		_fail = "something is cracking 10 s after the open"
	_steps_until(t0 + HZ / 2)
	await _frame_and_shot(st, 0, "tl_01_first_crack")
	if _cracking(st) != 0:
		_fail = "zone 0 is not the one cracking at the first crack"
	_steps_until(t0 + crack + HZ)
	await _frame_and_shot(st, 0, "tl_02_first_fall")
	if CollapseScript.zone_phase(st, 0) != CollapseScript.ZONE_FALLEN or _cracking(st) != -1:
		_fail = "zone 0 has not fallen cleanly 1 s after its fall tick"
	_steps_until(t0 + 2 * (crack + gap) + crack / 2)
	await _frame_and_shot(st, 2, "tl_03_third_ring")
	if _cracking(st) != 2:
		_fail = "zone 2 is not cracking at the third-ring shot"
	_finish()


func _cracking(st: Dictionary) -> int:
	for i in CollapseScript.zone_count(st):
		if CollapseScript.zone_phase(st, i) == CollapseScript.ZONE_CRACKING:
			return i
	return -1


func _steps_until(target: int) -> void:
	while int(_world.lstate.tick) < target:
		_world.step(DT)


## Frame one ring: the centroid of its tiles, the camera above and to the south of it.
func _frame_and_shot(st: Dictionary, zi: int, name: String) -> void:
	var cam: Camera3D = _world.camera
	var keys: Array = CollapseScript.zone_keys(st, zi)
	var c := Vector2.ZERO
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for k in keys:
		var p: PackedStringArray = str(k).split(",")
		var v := Vector2(float(p[0]) + 0.5, float(p[1]) + 0.5)
		c += v
		lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.y))
		hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.y))
	c /= float(maxi(keys.size(), 1))
	var ext: float = clampf(maxf(hi.x - lo.x, hi.y - lo.y), 8.0, 30.0)
	cam.global_position = Vector3(c.x, ext * 0.6 + 6.0, c.y + ext * 0.6 + 6.0)
	cam.look_at(Vector3(c.x, 0.0, c.y), Vector3.UP)
	var phases: PackedStringArray = []
	for i in CollapseScript.zone_count(st):
		phases.append(str(CollapseScript.zone_phase(st, i)))
	print("DIAG %s t_since_open=%.1fs zone_phases=[%s] (0 idle,1 cracking,2 fallen) cracking=%d cracked_keys=%d overlay_visible=%s" % [
			name, float(int(_world.lstate.tick) - _open_tick) / HZ, ",".join(phases),
			_cracking(st), CollapseScript.cracked_keys(st).size(),
			str(_world.collapse_view.any_overlay_visible())])
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	if img == null:
		_fail = "viewport texture returned null for %s" % name
		return
	var path := _out_dir.path_join(name + ".png")
	if img.save_png(path) != OK:
		_fail = "save_png(%s) failed" % path
		return
	print("SHOT %s" % path)


func _finish() -> void:
	if _world != null:
		_world.teardown()
		_world.queue_free()
		_world = null
	if _fail != "":
		print("SHOTX FAIL %s" % _fail)
		quit(1)
		return
	print("SHOTX OK")
	quit(0)
