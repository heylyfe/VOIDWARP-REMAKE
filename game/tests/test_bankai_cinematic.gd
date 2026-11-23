extends RefCounted

const World := preload("res://app/world.gd")
const DT := 1.0 / 60.0
const CUE_TICKS := {"hum": 0, "charge": 612, "impact": 750, "volley": 1200, "kill": 1290}


class TesterApp extends Node:
	var _world: Node3D


## Use the actual buttons and the panel's queued arena-entry tick.
static func start(root: Node, atmosphere: bool = false) -> Node:
	var app := TesterApp.new()
	root.add_child(app)
	var world := World.new()
	app._world = world
	app.add_child(world)
	world.atmosphere = atmosphere
	if not world.build(17, 10, {"class": "dasher", "votes": {}, "curses": {},
			"stacks": {}, "purse": 35}):
		app.free()
		return null
	var panel = load("res://view/tester/debug_panel.gd").new()
	app.add_child(panel)
	panel.setup(app)
	panel.on_world_built(world)
	panel._boss_button.pressed.emit()
	world.step(DT, {"buttons": 0})
	panel._bankai_button.pressed.emit()
	return app


func run() -> Array[String]:
	var failures: Array[String] = []
	for fps in [30, 144]:
		_smoke(failures, fps)
	return failures


func _smoke(f: Array[String], fps: int) -> void:
	var app = start((Engine.get_main_loop() as SceneTree).root)
	if app == null:
		f.append("level 10 failed to build")
		return
	var world = app._world
	var boss = world.lstate.boss
	var anim = world._boss_view._bankai
	if anim == null or not boss.bankai_active:
		f.append("FORCE BANKAI did not start the arena cinematic")
		app.free()
		return
	var camera: Camera3D = anim._anim_cam
	var first_person: Camera3D = anim._prev_camera
	var feet := Vector2(world.ctl.x, world.ctl.z)
	var yaw: float = world.rig.yaw_deg
	var opening_gold: int = world._economy.purse_centi
	var previous: Transform3D = camera.transform
	var fired := {}
	_check_audio(f, anim, fired, 0)
	var voice_tick := -1
	var cmd := {"move_x": 127, "move_z": 0, "buttons": 9}
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(80.0, 10.0)
	world._mouse_locked = true
	var tick := 0
	for frame in range(ceili(25.5 * fps)):
		var next_tick := ((frame + 1) * 60) / fps
		while tick < next_tick:
			tick += 1
			world.step(DT, cmd)
			_check_audio(f, anim, fired, tick)
			if voice_tick < 0 and anim._voice_player.playing:
				voice_tick = tick
			if tick in [749, 1290, 1529]:
				world._unhandled_input(motion)
				if Vector2(world.ctl.x, world.ctl.z) != feet or world.rig.yaw_deg != yaw:
					f.append("input changed the player during Bankai at tick %d" % tick)
			if tick == 1290 and (not boss.dead or not world.lstate.beacon.is_open()
					or world._economy.purse_centi != opening_gold + 30000):
				f.append("Peter's death, beacon or 300 gold missing at tick 1290")
		if anim.is_playing:
			anim._process(1.0 / fps)
			_check_camera(f, anim, camera, previous, fps, float(frame + 1) / fps)
			previous = camera.transform
	if fired != CUE_TICKS:
		f.append("at %d FPS cue ticks were %s" % [fps, str(fired)])
	if voice_tick != 468 or anim._voice_player.stream == null \
			or anim._voice_player.stream.resource_path != "res://view/cinematics/custom_voiceline.mp3":
		f.append("owner voice did not start from the imported clip at tick 468")
	if anim.is_playing or boss.bankai_active or world._boss_view._bankai != null \
			or world.player_model.visible or first_person == null or not first_person.current:
		f.append("at %d FPS the cinematic did not restore the first-person view" % fps)
	world._unhandled_input(motion)
	world.step(DT, cmd)
	if Vector2(world.ctl.x, world.ctl.z) == feet or world.rig.yaw_deg == yaw:
		f.append("movement or look failed to resume after Bankai")
	var beacon: Array = world.lv["beacon"]
	world.ctl.x = float(beacon[0]) + 0.5
	world.ctl.y = boss.floor_y()
	world.ctl.z = float(beacon[1]) + 0.5
	world.step(DT, {"buttons": 0})
	if not world.lstate.beacon.completed or not world._completed_emitted:
		f.append("entering the open beacon failed to complete level 10")
	app.free()


func _check_audio(f: Array[String], anim: Node3D, fired: Dictionary, tick: int) -> void:
	for cue in anim._cue_players:
		var player: AudioStreamPlayer = anim._cue_players[cue]
		if fired.has(cue) or not player.playing:
			continue
		fired[cue] = tick
		var wav := player.stream as AudioStreamWAV
		if wav == null or wav.get_length() <= 0.0 or wav.data.count(0) == wav.data.size():
			f.append("%s has no synthesized audio" % cue)
		if player.volume_db >= anim._voice_player.volume_db:
			f.append("%s is mixed at or above the voice" % cue)
		if cue == "hum" and wav.loop_mode != AudioStreamWAV.LOOP_FORWARD:
			f.append("hum does not loop under the cinematic")


func _check_camera(f: Array[String], anim: Node3D, camera: Camera3D, previous: Transform3D,
		fps: int, t: float) -> void:
	var pos := camera.position
	var sword_y: float = anim._world_sword.position.y
	var step := (camera.transform.origin - previous.origin).length()
	var turn := previous.basis.get_rotation_quaternion().angle_to(
			camera.basis.get_rotation_quaternion())
	if step > 0.16 or turn > 0.12:
		f.append("camera snapped at %.3fs (%d FPS): %.3f m / %.3f rad" % [t, fps, step, turn])
	if camera.global_position.y < anim.global_position.y + 1.0 \
			or not anim.arena_bounds.grow(0.001).has_point(Vector2(
					camera.global_position.x, camera.global_position.z)):
		f.append("camera left the arena floor envelope at %.3fs (%d FPS)" % [t, fps])
	if t < 12.5 and not anim._fps_rig.visible:
		f.append("first person ended before sword impact at %.3fs" % t)
	if t >= 12.5 and anim._fps_rig.visible:
		f.append("first person returned after sword impact at %.3fs" % t)
	if t >= 12.5 and t < 12.75 and (not anim._world_sword.visible
			or sword_y < 1.02 or sword_y > 1.16):
		f.append("sword is missing or submerged after impact at %.3fs" % t)
	if t >= 16.0 and (pos.z < 3.5 or not anim.player_model.visible
			or not camera.is_position_in_frustum(anim.player_model.global_position + Vector3.UP)):
		f.append("camera lost the avatar after pulling back at %.3fs" % t)
