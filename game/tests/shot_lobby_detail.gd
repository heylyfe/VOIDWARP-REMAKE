extends SceneTree
#
# Lobby detail screenshot tool (cycle 4 items 2, 3, 5, 8, 11): boots the REAL Antechamber
# (view/lobby/lobby_scene.gd) and frames what shot_lobby.gd does not: an upgrade altar's
# price line in both afford states, a curse altar, the About plaque up close, and the curse
# / upgrade icons on their altars. Windowed run - rendering needs a GPU, never --headless:
#
#   <godot> --path game --script res://tests/shot_lobby_detail.gd -- <out_dir> [seed]
#
# Writes <out_dir>/detail_00_upgrade_afford.png  (completed 1, purse 400: PRICE in gold)
#        <out_dir>/detail_01_upgrade_cannot.png  (completed 1, purse 30: CANNOT AFFORD)
#        <out_dir>/detail_02_curse.png           (completed 2: a curse altar and the tithe)
#        <out_dir>/detail_03_about.png           (the About plaque, square-on)
#        <out_dir>/detail_04_icons_eye.png       (the upgrade bay from standing eye height)
#        <out_dir>/detail_05_icons_above.png     (the same bay from above, 45 degrees)
#        <out_dir>/detail_06_purse_max.png       (completed 999, purse 999999: the purse pill and
#                                                 the price line at their widest - D-FRONT-1)
# Prints a DIAG line per shot (the stood-at altar's label, price, afford state and the
# price line's text; the icon quads' facing) so a blank shot is not mistaken for a fixed
# one. Named shot_*, not test_*, so tests/run_all.gd skips it. Prints "SHOT <path>" per PNG
# and "SHOTX OK" / "SHOTX FAIL <why>"; exit 1 on failure.

const LobbySceneScript := preload("res://view/lobby/lobby_scene.gd")

const SHOT_SIZE := Vector2i(1280, 720)
const DT := 1.0 / 60.0

var _out_dir := ""
var _seed := 7
var _fail := ""
var _scene: Node3D = null


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	root.size = SHOT_SIZE
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out_dir = args[0] if args.size() >= 1 else ProjectSettings.globalize_path("res://shots_lobby_detail")
	if args.size() >= 2:
		_seed = int(args[1])
	if DirAccess.make_dir_recursive_absolute(_out_dir) != OK:
		_fail = "cannot create %s" % _out_dir
		_finish()
		return
	if await _build(1, 400):
		await _at_altar("U", "detail_00_upgrade_afford", true)
	if await _build(1, 30):
		await _at_altar("U", "detail_01_upgrade_cannot", false)
	if await _build(2, 400):
		await _at_altar("C", "detail_02_curse", true)
	if await _build(1, 400):
		var hz: float = _scene.hall.HALL_Z
		var cam: Camera3D = _scene.player.camera
		cam.global_position = Vector3(0.0, 3.2, hz * 0.5 - 4.5)
		cam.look_at(Vector3(0.0, 3.2, hz * 0.5), Vector3.UP)
		await _shot("detail_03_about")
		var u: Dictionary = _find("U")
		var p: Vector3 = (u["root"] as Node3D).global_position
		_stand_at(u)
		for _i in 4:
			_scene.tick(DT, 0, 0, false)
		cam.global_position = Vector3(p.x, 1.7, p.z + 5.0)
		cam.look_at(Vector3(p.x, 2.6, p.z), Vector3.UP)
		_diag_icons(u)
		await _shot("detail_04_icons_eye")
		cam.global_position = Vector3(p.x, 6.5, p.z + 4.0)
		cam.look_at(Vector3(p.x, 2.8, p.z), Vector3.UP)
		await _shot("detail_05_icons_above")
	# the widest real numbers: a 6-digit purse in the corner pill (the level is the pause
	# pill's, shot by shot_gui.gd)
	if await _build(1, 999999):
		print("DIAG purse_pill text='%s' rect=%s" % [_scene.hud._label.text,
				str(_scene.hud.get_global_rect())])
		await _at_altar("U", "detail_06_purse_max", true)
	_finish()


func _build(completed: int, purse: int) -> bool:
	if _scene != null:
		_scene.teardown()
		_scene.queue_free()
		_scene = null
		await process_frame
	_scene = LobbySceneScript.new()
	root.add_child(_scene)
	if not _scene.build(_seed, completed, {"purse": purse}):
		_fail = "lobby.build(%d, %d) returned false" % [_seed, completed]
		return false
	for _i in 30:
		_scene.tick(DT, 0, 0, false)
	return true


func _find(bay_kind: String) -> Dictionary:
	for a in _scene.hall._altars:
		if str(a["kind"]) == "offer" and str(a["bay_kind"]) == bay_kind:
			return a
	return {}


func _at_altar(bay_kind: String, name: String, want_afford: bool) -> void:
	var a := _find(bay_kind)
	if a.is_empty():
		_fail = "%s: no %s offer altar in this lobby" % [name, bay_kind]
		return
	_stand_at(a)
	for _i in 4:
		_scene.tick(DT, 0, 0, false)
	var pl: Label3D = a.get("price_label")
	print("DIAG %s label='%s' price=%s affordable=%s price_text='%s' purse=%d" % [name,
			str(a.get("label", "")), str(a.get("price", "-")), str(a.get("affordable", "-")),
			pl.text if pl != null else "", int(_scene.hall.lobby.purse)])
	if bay_kind == "U" and (pl == null or bool(a.get("affordable", false)) != want_afford):
		_fail = "%s: price line missing or afford state wrong" % name
	await _shot(name)


## Which way the icon quads face: a PlaneMesh is FACE_Y (lying flat) unless rotated.
func _diag_icons(a: Dictionary) -> void:
	var anchor: Node3D = a["exhibit"]
	var parts: PackedStringArray = []
	for n in anchor.get_children():
		if n is MeshInstance3D and (n as MeshInstance3D).mesh is PlaneMesh:
			var mi := n as MeshInstance3D
			var normal: Vector3 = mi.global_transform.basis.y.normalized()
			if (mi.mesh as PlaneMesh).orientation == PlaneMesh.FACE_Z:
				normal = mi.global_transform.basis.z.normalized()
			parts.append("%s orient=%d normal=%s" % [mi.get_meta("icon_kind", "frame"),
					int((mi.mesh as PlaneMesh).orientation), str(normal)])
	print("DIAG icons label='%s' quads=[%s]" % [str(a.get("label", "")), "; ".join(parts)])


func _stand_at(p_altar: Dictionary) -> void:
	var root3: Node3D = p_altar["root"]
	_scene.player.x = root3.position.x
	_scene.player.z = root3.position.z + 2.0
	_scene.player.vx = 0.0
	_scene.player.vz = 0.0
	_scene.player.rig.yaw_deg = 0.0


func _shot(name: String) -> void:
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
	if _scene != null:
		_scene.teardown()
		_scene.queue_free()
		_scene = null
	if _fail != "":
		print("SHOTX FAIL %s" % _fail)
		quit(1)
		return
	print("SHOTX OK")
	quit(0)
