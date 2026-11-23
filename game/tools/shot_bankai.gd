extends SceneTree
## Windowed audio measurement and screenshot sequence, driven by FORCE BANKAI.
## Run with an absolute output directory after --.

const Smoke := preload("res://tests/test_bankai_cinematic.gd")
const SHOTS := [468, 738, 750, 810, 960, 1080, 1230, 1290, 1500]

var _app: Node
var _world: Node3D
var _anim: Node3D
var _out := ""
var _acc := 0.0
var _shot := 0
var _heard := false
var _voice_ended := false
var _finished := false


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or not args[0].is_absolute_path():
		print("BANKAI PROBE FAIL: supply an absolute output directory")
		quit(1)
		return
	_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_app = Smoke.start(root, true)
	if _app == null:
		quit(1)
		return
	_world = _app.get("_world")
	_anim = _world._boss_view._bankai
	if _anim == null:
		quit(1)
		return
	_anim._voice_player.finished.connect(_voice_finished)
	_anim.animation_finished.connect(_cinematic_finished)


func _process(delta: float) -> bool:
	if _anim == null:
		return false
	_acc += minf(delta, 5.0 * Smoke.DT)
	while _acc >= Smoke.DT and not _finished:
		_acc -= Smoke.DT
		_world.step(Smoke.DT, {"buttons": 0})
		if not _heard and _anim._voice_player.playing:
			_heard = true
			_stamp("VOICE START")
	if not _finished and _shot < SHOTS.size() and _world.lstate.boss.bankai_tick >= SHOTS[_shot]:
		var tick: int = _world.lstate.boss.bankai_tick
		_shot += 1
		_capture.call_deferred(tick)
	return false


func _capture(tick: int) -> void:
	await RenderingServer.frame_post_draw
	var path := _out.path_join("bankai_%04d.png" % tick)
	if root.get_texture().get_image().save_png(path) != OK:
		print("BANKAI PROBE FAIL: could not write ", path)
		quit(1)
	else:
		print("SHOT ", path)


func _stamp(label: String) -> void:
	var tick: int = _world.lstate.boss.bankai_tick
	print("%s tick=%d seconds=%.4f" % [label, tick, tick * Smoke.DT])


func _voice_finished() -> void:
	_stamp("VOICE FINISHED")
	_voice_ended = true


func _cinematic_finished() -> void:
	_stamp("CINEMATIC FINISHED")
	_finished = true
	quit(0 if _heard and _voice_ended else 1)
