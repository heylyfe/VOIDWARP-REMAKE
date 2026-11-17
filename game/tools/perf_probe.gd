extends SceneTree
#
# Perf probe A13 (FLEET_PACK.md section 4; ticket T-061; the pinned scene is
# research/fable-tickets.md's addendum row for T-061, verbatim):
#
#   "Perf probe: level 30, seed 7, 22 enemies placed by a fixed vote list (kiwi 3, coil 2,
#    ben 2, seal 2, YOU?! 1, nuke 2, Larper 2, toucher 1, address me 2, Isagi 1, Claude 1,
#    gin 3), the bot playing with --dodge, camera in normal third-person; measure 600
#    frames after 120 warm-up frames, windowed 1920x1080, v-sync off. Report the machine's
#    CPU and GPU names in the output."
#
#   <godot> --headless --path game --script res://tools/perf_probe.gd   (headless, caveat)
#   <godot> --path game --script res://tools/perf_probe.gd              (a real window is used)
#
# Prints the machine's OS / CPU / GPU / renderer lines FIRST, then one PASS/FAIL row per
# A13 bound with its number, then "T-061 RESULT: OK" / "T-061 RESULT: FAIL n rows"
# (exit 1 on any FAIL).
#
#   PASS p99_frame_time  3.21 ms  <= 16.6 ms ...
#   PASS mean_sim_tick   0.94 ms  <= 2.0 ms (22 enemies live)
#   T-061 RESULT: OK
#
# A frame = one main-loop pass: the dodge bot's input, controller.step + enemy
# runtime.step (timed as the sim tick), the third-person camera rig update, and the
# per-enemy billboard view update (frame advance + y-billboard face + position read).
# When a real DisplayServer exists the probe also sets the window to exactly 1920x1080,
# disables v-sync, builds the level meshes into the scene and renders through a real
# Camera3D - so windowed frame times include the renderer. HEADLESS CAVEAT (D-T061-5):
# the dummy renderer submits nothing to a GPU, so in a headless run the frame row is a
# CPU-side frame cost only - the sim row stays a valid measurement. The probe marks the
# frame row with the renderer actually used.

const VoidGenScript := preload("res://terrain/voidgen.gd")
const CollisionScript := preload("res://sim/collision.gd")
const MesherScript := preload("res://view/level_mesher.gd")
const ControllerScript := preload("res://sim/controller.gd")
const CameraRigScript := preload("res://app/camera_rig.gd")
const EnemyRuntimeScript := preload("res://sim/enemy_runtime.gd")
const BillboardScript := preload("res://view/billboard.gd")
const Util := preload("res://tests/sim_testutil.gd")

const DT := 1.0 / 60.0
const SEED := 7
const LEVEL := 30
const WARMUP_FRAMES := 120
const MEASURED_FRAMES := 600
const MAX_FRAMES := 3600            # hard stop: never hang if process_frame stalls
const KIT := "dasher"               # D-T061-4: the probe's bot class [CONTESTABLE]

# The FIXED vote list, verbatim, in vote order (FLEET_PACK/research pin; D-T061-3).
const VOTE_LIST: Array = [
	["kiwi_cat", 3], ["coil", 2], ["thicc_ben", 2], ["seal", 2], ["you", 1],
	["nuke", 2], ["gift_larper", 2], ["toucher", 1], ["address_me", 2],
	["isagi", 1], ["claude", 1], ["gin", 3],
]

const BTN_JUMP := 1

var lv: Dictionary = {}
var w: Dictionary = {}
var ctl = null
var rt = null
var rig = null
var cam: Camera3D = null
var windowed := false
var frame := 0                     # warm-up + measured, 0-based
var frame_us: Array = []           # measured frames: full-frame wall microseconds
var sim_us: Array = []             # measured frames: sim step (ctl+runtime) microseconds
var boards: Array = []   # EnemyRuntime enemies index -> billboard node (or null)
var failures: Array = []   # hard failures (scene assembly); collected before the rows


func _init() -> void:
	var renderer := String(DisplayServer.get_name())
	windowed = renderer != "headless" and renderer != "dummy"
	# Hardware first (A13: "Report the machine's CPU and GPU names in the output").
	print("MACHINE[GODOT] %s" % Engine.get_version_info()["string"])
	print("MACHINE[OS] %s" % OS.get_name())
	print("MACHINE[CPU] %s" % _first_real([OS.get_processor_name(),
			_hw_query("Win32_Processor", "Name")]))
	print("MACHINE[GPU] %s (vendor %s)" % [
		_first_real([RenderingServer.get_video_adapter_name(),
				_hw_query("Win32_VideoController", "Name")]),
		_first_real([RenderingServer.get_video_adapter_vendor()])])
	print("MACHINE[RENDERER] %s" % renderer)
	if windowed:
		DisplayServer.window_set_size(Vector2i(1920, 1080))
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_build_scene()
	process_frame.connect(_frame)


# ---- scene assembly: level 30 seed 7 + 22 planned enemies + third-person camera ---------------

func _build_scene() -> void:
	lv = VoidGenScript.generate(SEED, LEVEL, 1, 0)
	if lv.is_empty():
		failures.append("voidgen.generate(%d, %d) returned {}" % [SEED, LEVEL])
		_finish()
		return
	w = CollisionScript.make_world(lv["tiles"], lv["props"], lv["pads"])
	ctl = Util.ControllerScript.new()
	ctl.setup(KIT, Util.consts())
	ctl.place(w)
	rt = EnemyRuntimeScript.new()
	# D-T061-3: spawn_delay_ticks = 1 so all 22 bodies are live for every measured frame.
	rt.setup(lv, w, [ctl], SEED, {"spawn_delay_ticks": 1})
	for entry in VOTE_LIST:
		var id: String = entry[0]
		var votes: int = int(entry[1])
		var cfg := _cfg_for(id, votes)
		if cfg.is_empty():
			failures.append("enemy cfg unreadable: content/enemies/%s/enemy.json" % id)
			_finish()
			return
		rt.plan(id, _display_name(id), _behavior_for(id), cfg, votes)
	# Third-person camera (app/camera_rig.gd defaults - the "normal third-person" view).
	rig = CameraRigScript.new()   # the rig's defaults are its D-T082-1 values
	if windowed:
		var mesher := MesherScript.build(lv)
		for mn in mesher["meshes"]:
			var mi := MeshInstance3D.new()
			mi.mesh = mesher["meshes"][mn]
			root.add_child(mi)
		cam = Camera3D.new()
		rig.add_child(cam)
		root.add_child(rig)
		cam.current = true
		cam.fov = CameraRigScript.FOV_DEFAULT
	_meshes_note()


func _meshes_note() -> void:
	if not windowed:
		print("NOTE headless dummy renderer: the level meshes and the Camera3D are NOT built;")
		print("NOTE the p99 frame row measures CPU-side frame cost only (D-T061-5).")
	else:
		print("NOTE windowed 1920x1080, v-sync off, level meshes + Camera3D in the scene.")


# Per-id EnemyRuntime.plan arguments: the content module's own behavior shape and a cfg
# from enemy.json (stats topped with the top-level contact_kill / preferred_kind /
# arbiter, plus votes and level_number).
func _cfg_for(id: String, votes: int) -> Dictionary:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(
			"res://content/enemies/%s/enemy.json" % id))
	if not (doc is Dictionary):
		return {}
	var d: Dictionary = doc
	var cfg: Dictionary = (d.get("stats", {}) as Dictionary).duplicate(true)
	for k in ["contact_kill", "preferred_kind", "arbiter"]:
		if d.has(k):
			cfg[k] = d[k]
	cfg["votes"] = votes
	cfg["level_number"] = LEVEL
	return cfg


func _display_name(id: String) -> String:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(
			"res://content/enemies/%s/enemy.json" % id))
	if doc is Dictionary:
		return str((doc as Dictionary).get("name", id))
	return id


 ## The first non-empty candidate string (renderer queries answer "" on the dummy device).
func _first_real(cands: Array) -> String:
	for c in cands:
		var s := str(c).strip_edges()
		if s != "":
			return s
	return "(unavailable)"


## WMI fallback, for the headless run where the rendering server cannot name the
## hardware: OS.execute is blocking; the probe needs the name once, before the table.
func _hw_query(wmi_class: String, prop: String) -> String:
	if OS.get_name() != "Windows":
		return ""
	var out: Array = []
	OS.execute("powershell", ["-NoProfile", "-Command",
			"(Get-CimInstance %s).%s" % [wmi_class, prop]], out, true)
	var text := ""
	for line in out:
		text += str(line)
	text = text.strip_edges()
	if text.contains("\n"):
		text = text.get_slice("\n", 0)   # multi-GPU: report the first
	return text.strip_edges()


func _behavior_for(id: String):
	var K = load("res://content/enemies/%s/enemy.gd" % id)
	match id:
		"kiwi_cat": return K.KiwiCatBehavior.new()
		"seal": return K.SealBehavior.new()
		"gift_larper": return K.GiftLarperBehavior.new()
		"isagi": return K.Behavior.new()
		"coil": return K.behavior()
		"toucher": return K.behavior()
		"thicc_ben": return K.new_behavior()
		_: return K.new()   # the file-as-behavior module (you, nuke, address_me, claude, gin)


# ---- the per-frame pass -------------------------------------------------------------------------

func _frame() -> void:
	var t0 := Time.get_ticks_usec()
	var inp := _bot_input()
	var s0 := Time.get_ticks_usec()
	ctl.step(DT, inp, w)
	rt.step(DT)
	var s1 := Time.get_ticks_usec()
	# The third-person camera pass runs in BOTH modes: pure math over the sim's feet
	# (app/camera_rig.gd), a real node transform in a windowed run.
	rig.update_rig(Vector3(float(ctl.x), float(ctl.y), float(ctl.z)), DT)
	if windowed:
		_view_pass()
	var t1 := Time.get_ticks_usec()
	if frame >= WARMUP_FRAMES:
		frame_us.append(t1 - t0)
		sim_us.append(s1 - s0)
	frame += 1
	if frame >= WARMUP_FRAMES + MEASURED_FRAMES or frame >= MAX_FRAMES:
		_finish()


func _view_pass() -> void:
	var cam_pos: Vector3 = rig.global_position if rig.is_inside_tree() else rig.position
	while boards.size() < rt.enemies.size():
		boards.append(_make_board(rt.enemies[boards.size()]))
	for i in rt.enemies.size():
		var e: Dictionary = rt.enemies[i]
		var bd = boards[i]
		if bd == null:
			continue
		bd.position = Vector3(float(e["x"]), float(e["y"]), float(e["z"]))
		bd.set_animation(str(e.get("anim_state", "")))
		bd.advance_animation(DT)
		bd.face_camera(cam_pos)


func _make_board(e: Dictionary):
	var folder := "res://content/enemies/%s" % str(e["id"])
	var doc: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(folder + "/sprites.json"))
	if not (doc is Dictionary):
		return null
	var bd = BillboardScript.new()
	bd.setup_from_sheet(doc, folder)
	root.add_child(bd)
	return bd


# ---- the dodge bot (D-T061-4): pure function of sim state + tick counter ------------------------

func _bot_input() -> Dictionary:
	var feet := Vector3(float(ctl.x), float(ctl.y), float(ctl.z))
	var dais: Array = w["dais"]
	var target := Vector3(float(dais[0]) + 0.5, 0.0, float(dais[1]) + 0.5)
	if Vector2(target.x - feet.x, target.z - feet.z).length() < 8.0:
		# hold at the beacon: slow circle, keyed off the tick counter (deterministic)
		var a := float(frame) * 0.05
		target = Vector3(feet.x + 6.0 * cos(a), 0.0, feet.z + 6.0 * sin(a))
	# dodge: blend away from the nearest live enemy body within 12 u (world mirror)
	var dir := Vector2(target.x - feet.x, target.z - feet.z)
	if dir.length() > 0.001:
		dir = dir.normalized()
	for e in w["enemies"]:
		var bp := Vector3(float(e["x"]), float(e["y"]), float(e["z"]))
		if bp.distance_to(feet) > 12.0:
			continue
		var away := Vector2(feet.x - bp.x, feet.z - bp.z)
		if away.length() < 0.001:
			away = Vector2(1.0, 0.0)
		dir = (dir * 0.45 + away.normalized() * 1.55).normalized()
	var buttons := 0
	if frame % 90 == 0 and bool(ctl.grounded) and not bool(ctl.dead):
		buttons = BTN_JUMP   # a dodge-style hop every 1.5 s
	return {"move_x": int(round(dir.x * 127.0)), "move_z": int(round(dir.y * 127.0)),
			"buttons": buttons, "aim_x": dir.x, "aim_z": dir.y}


# ---- the table ----------------------------------------------------------------------------------

func _p99(us: Array) -> float:
	var a := us.duplicate()
	a.sort()
	return float(a[int(round(0.99 * float(a.size() - 1)))]) / 1000.0


func _mean(us: Array) -> float:
	var s := 0.0
	for v in us:
		s += float(v)
	return s / maxf(1.0, float(us.size())) / 1000.0


func _finish() -> void:
	var fail_n := 0
	for msg in failures:
		print("FAIL scene %s" % msg)
		fail_n += 1
	# The two A13 rows. The frame row names the renderer that ACTUALLY produced it.
	var renderer := String(DisplayServer.get_name())
	var frames_ok := frame_us.size() >= MEASURED_FRAMES
	if frames_ok:
		var p99 := _p99(frame_us)
		var fmark := "windowed 1080p, v-sync off" if windowed \
				else "HEADLESS %s: CPU frame cost only, no GPU submission (D-T061-5)" % renderer
		var p_ok := p99 <= 16.6
		print("%s p99_frame_time %.2f ms <= 16.6 ms (%s; n=%d)"
				% ["PASS" if p_ok else "FAIL", p99, fmark, frame_us.size()])
		if not p_ok:
			fail_n += 1
	else:
		print("FAIL p99_frame_time never n=%d/%d frames"
				% [frame_us.size(), MEASURED_FRAMES])
		fail_n += 1
	if sim_us.size() >= MEASURED_FRAMES:
		var mean := _mean(sim_us)
		var enemies_live: bool = rt != null and rt.enemies.size() == 22
		var s_ok: bool = mean <= 2.0 and enemies_live
		print("%s mean_sim_tick %.3f ms <= 2.0 ms (ctl+enemy runtime step; %d enemy rows)"
				% ["PASS" if s_ok else "FAIL", mean, rt.enemies.size() if rt != null else 0])
		if not s_ok:
			if not enemies_live:
				print("FAIL scene the vote list produced %d enemy rows, want 22"
						% (rt.enemies.size() if rt != null else 0))
			fail_n += 1
	else:
		print("FAIL mean_sim_tick never n=%d/%d frames"
				% [sim_us.size(), MEASURED_FRAMES])
		fail_n += 1
	if fail_n > 0:
		print("T-061 RESULT: FAIL %d rows" % fail_n)
		quit(1)
	else:
		print("T-061 RESULT: OK")
		quit(0)
