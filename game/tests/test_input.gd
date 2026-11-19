extends RefCounted
#
# Input / camera / settings tests (ticket T-082; done-when from the ticket verbatim):
#   1. each key produces the documented bit;
#   2. the same key sequence at two camera yaws produces move vectors rotated by exactly the
#      yaw difference;
#   3. the camera never changes sim state — replay test green with the camera moved randomly:
#      inputs are captured through input_capture.gd while the camera yaw varies (deterministic
#      LCG, never a sim object), and the replayed state hashes match at every 60th tick.
# Camera rig numbers and settings store are also pinned here (D-T082-1 / D-T082-2 / D-T082-3).
# extends RefCounted, preload-by-path only (D-T001-1); a global class_name does not resolve
# under --headless --script.

const SimInputScript := preload("res://sim/input.gd")
const CaptureScript := preload("res://app/input_capture.gd")
const CameraScript := preload("res://app/camera_rig.gd")
const SettingsScript := preload("res://app/settings.gd")
const VoidGenScript := preload("res://terrain/voidgen.gd")
const RunStateScript := preload("res://sim/run_state.gd")
const SimScript := preload("res://sim/sim.gd")
const HashScript := preload("res://sim/state_hash.gd")

const RUN_SEED := 20260102
const REPLAY_TICKS := 1800
const CHECK_EVERY := 60
const SETTINGS_TEST_PATH := "user://t82_test_settings.json"


func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_test_bindings_load())
	failures.append_array(_test_key_bits())
	failures.append_array(_test_move_keys())
	failures.append_array(_test_yaw_rotation_exact())
	failures.append_array(_test_yaw_rotation_general())
	failures.append_array(_test_diagonal_clamp_and_neutral())
	failures.append_array(_test_gamepad())
	failures.append_array(_test_camera_statics())
	failures.append_array(_test_no_manual_camera_turn())
	failures.append_array(_test_settings())
	failures.append_array(_test_replay_with_random_camera())
	return failures


# --- 1. bindings.json -------------------------------------------------------------

func _test_bindings_load() -> Array[String]:
	var failures: Array[String] = []
	var b := CaptureScript.load_bindings()
	for e in b["errors"]:
		failures.append("load_bindings error: %s" % e)
	if b["errors"].is_empty():
		print("BINDINGS res://data/bindings.json parsed clean")
	var kb: Dictionary = b["key_bindings"]
	if int(kb.get("jump", [])[0] if kb.has("jump") else -1) != KEY_SPACE:
		failures.append("jump should bind KEY_SPACE (%d), got %s" % [KEY_SPACE, str(kb.get("jump"))])
	if kb.get("ability", []).size() != 1 or int(kb["ability"][0]) != KEY_SHIFT:
		failures.append("ability should bind KEY_SHIFT (%d), got %s"
				% [KEY_SHIFT, str(kb.get("ability"))])
	if kb.get("interact", []).size() != 1 or int(kb["interact"][0]) != KEY_F:
		failures.append("interact should bind KEY_F (%d), got %s" % [KEY_F, str(kb.get("interact"))])
	if kb.get("hud_toggle", []).size() != 1 or int(kb["hud_toggle"][0]) != KEY_TAB:
		failures.append("hud_toggle should bind KEY_TAB, got %s" % str(kb.get("hud_toggle")))
	if kb.get("pause", []).size() != 1 or int(kb["pause"][0]) != KEY_ESCAPE:
		failures.append("pause should bind KEY_ESCAPE, got %s" % str(kb.get("pause")))
	var jb: Dictionary = b["joy_bindings"]
	if int(jb.get("jump", -1)) != 0:
		failures.append("gamepad jump should be button 0 (A), got %s" % str(jb.get("jump")))
	if int(jb.get("ability", -1)) != 2:
		failures.append("gamepad ability should be button 2 (X), got %s" % str(jb.get("ability")))
	if int(jb.get("interact", -1)) != 3:
		failures.append("gamepad interact should be button 3 (Y), got %s" % str(jb.get("interact")))

	# A binding naming an unknown key is a load error, never a silent guess.
	var f := FileAccess.open("user://t82_bad_bindings.json", FileAccess.WRITE)
	f.store_string("{\"jump\": [\"KEY_BOGUS\"]}")
	f.flush()
	f = null
	var bad := CaptureScript.load_bindings("user://t82_bad_bindings.json")
	if bad["errors"].is_empty():
		failures.append("load_bindings accepted an unknown key name")
	if not (bad["key_bindings"].has("jump") and (bad["key_bindings"]["jump"] as Array).is_empty()):
		failures.append("unknown key name must resolve to NO key code, got %s"
				% str(bad["key_bindings"].get("jump")))
	return failures


# Helper: capture with the shipped bindings and no gamepad stick.
func _cap(keys: Array, yaw: float = 0.0, joy: Array = [], stick_x: float = 0.0,
		stick_y: float = 0.0) -> Dictionary:
	return CaptureScript.capture(keys, joy, stick_x, stick_y, yaw, CaptureScript.load_bindings())


# --- 2. each key produces the documented bit ---------------------------------------------

func _test_key_bits() -> Array[String]:
	var failures: Array[String] = []
	# W/S/A/D move and produce NO button bits and NO app flags.
	for k in [KEY_W, KEY_A, KEY_S, KEY_D]:
		var r := _cap([k])
		var inp: RefCounted = r["input"]
		if int(inp.buttons) != 0:
			failures.append("key %d (movement key) must produce buttons == 0, got %d"
					% [k, int(inp.buttons)])
		if int(r["app"]) != 0:
			failures.append("key %d (movement key) must produce no app flags, got %d"
					% [k, int(r["app"])])
	# Space -> BUTTON_JUMP and nothing else.
	var rj := _cap([KEY_SPACE])
	if int((rj["input"] as RefCounted).buttons) != SimInputScript.BUTTON_JUMP:
		failures.append("Space must produce BUTTON_JUMP=%d, got %d"
				% [SimInputScript.BUTTON_JUMP, int((rj["input"] as RefCounted).buttons)])
	if int(rj["app"]) != 0:
		failures.append("Space must produce no app flags, got %d" % int(rj["app"]))
	# Left Shift -> BUTTON_ABILITY.
	var ra := _cap([KEY_SHIFT])
	if int((ra["input"] as RefCounted).buttons) != SimInputScript.BUTTON_ABILITY:
		failures.append("Left Shift must produce BUTTON_ABILITY=%d, got %d"
				% [SimInputScript.BUTTON_ABILITY, int((ra["input"] as RefCounted).buttons)])
	# F -> BUTTON_INTERACT (the bit is "held"; the 0.35 s altar tally is altar-view logic).
	var ri := _cap([KEY_F])
	if int((ri["input"] as RefCounted).buttons) != SimInputScript.BUTTON_INTERACT:
		failures.append("F must produce BUTTON_INTERACT=%d, got %d"
				% [SimInputScript.BUTTON_INTERACT, int((ri["input"] as RefCounted).buttons)])
	# Tab toggles HUD rows (app flag), Esc is the pause menu (app flag) — neither reaches the sim.
	var rt := _cap([KEY_TAB])
	if int(rt["app"]) != CaptureScript.APP_HUD_TOGGLE:
		failures.append("Tab must produce APP_HUD_TOGGLE, got %d" % int(rt["app"]))
	if int((rt["input"] as RefCounted).buttons) != 0:
		failures.append("Tab must produce buttons == 0, got %d" % int((rt["input"] as RefCounted).buttons))
	var re := _cap([KEY_ESCAPE])
	if int(re["app"]) != CaptureScript.APP_PAUSE:
		failures.append("Esc must produce APP_PAUSE, got %d" % int(re["app"]))
	if int((re["input"] as RefCounted).buttons) != 0:
		failures.append("Esc must produce buttons == 0, got %d" % int((re["input"] as RefCounted).buttons))
	# All three sim buttons at once.
	var all_bits := SimInputScript.BUTTON_JUMP | SimInputScript.BUTTON_ABILITY \
			| SimInputScript.BUTTON_INTERACT
	var r3 := _cap([KEY_SPACE, KEY_SHIFT, KEY_F])
	if int((r3["input"] as RefCounted).buttons) != all_bits:
		failures.append("Space+Shift+F must produce all three bits, got %d"
				% int((r3["input"] as RefCounted).buttons))
	# Unbound keys produce nothing.
	var ru := _cap([KEY_Q, KEY_Z, KEY_ENTER])
	if int((ru["input"] as RefCounted).buttons) != 0 or int(ru["app"]) != 0 \
			or int((ru["input"] as RefCounted).move_x) != 0 \
			or int((ru["input"] as RefCounted).move_z) != 0:
		failures.append("unbound keys must produce a fully neutral capture, got %s" % str(ru))
	return failures


# --- 3. move keys + camera-yaw rotation ---------------------------------------------------

func _test_move_keys() -> Array[String]:
	var failures: Array[String] = []
	# At camera yaw 0 (Godot -z forward): W=(0,-127) S=(0,127) A=(-127,0) D=(127,0).
	var expect := {KEY_W: [0, -127], KEY_S: [0, 127], KEY_A: [-127, 0], KEY_D: [127, 0]}
	for k in expect:
		var r := _cap([k], 0.0)
		var inp: RefCounted = r["input"]
		if int(inp.move_x) != expect[k][0] or int(inp.move_z) != expect[k][1]:
			failures.append("key %d at yaw 0: expected (%d, %d), got (%d, %d)" % [k,
					expect[k][0], expect[k][1], int(inp.move_x), int(inp.move_z)])
	return failures


func _test_yaw_rotation_exact() -> Array[String]:
	var failures: Array[String] = []
	# The same key sequence at two camera yaws produces move vectors rotated by exactly the
	# yaw difference. Quarter yaws are exact in int8: forward W (local (0,-1)) maps to
	# (-sin(yaw), -cos(yaw)) * 127 rounded, and sin/cos of 0/90/180/270 are exactly 0/±1.
	var expect := {0.0: [0, -127], 90.0: [-127, 0], 180.0: [0, 127], 270.0: [127, 0]}
	for yaw in expect:
		var r := _cap([KEY_W], yaw)
		var inp: RefCounted = r["input"]
		if int(inp.move_x) != expect[yaw][0] or int(inp.move_z) != expect[yaw][1]:
			failures.append("W at yaw %s: expected (%d, %d), got (%d, %d)" % [str(yaw),
					expect[yaw][0], expect[yaw][1], int(inp.move_x), int(inp.move_z)])
	# 45 deg: forward (local (0,-1)) rotates to (-sin45, -cos45) * 127 = (-90, -90) exactly
	# (round(127 * sqrt(2) / 2) = 90).
	var r45 := _cap([KEY_W], 45.0)
	var i45: RefCounted = r45["input"]
	if int(i45.move_x) != -90 or int(i45.move_z) != -90:
		failures.append("W at yaw 45: expected (-90, -90), got (%d, %d)"
				% [int(i45.move_x), int(i45.move_z)])
	return failures


func _test_yaw_rotation_general() -> Array[String]:
	# Arbitrary yaw pairs: the angle between the two captured forward vectors must equal the
	# yaw difference AND the rotation direction must be fixed (cross < 0 for increasing yaw).
	# int8 rounding allows ~0.5 deg of slop; assert within 1.2 deg.
	var failures: Array[String] = []
	var yaws := [0.0, 30.0, 47.0, 133.0, 250.0, 315.0]
	for i in yaws.size():
		for j in range(i + 1, yaws.size()):
			var v1 := _cap([KEY_W], yaws[i])["input"] as RefCounted
			var v2 := _cap([KEY_W], yaws[j])["input"] as RefCounted
			var a1 := Vector2(float(v1.move_x), float(v1.move_z))
			var a2 := Vector2(float(v2.move_x), float(v2.move_z))
			if absf(a1.length() - 127.0) > 1.0 or absf(a2.length() - 127.0) > 1.0:
				failures.append("W at yaw %s/%s lost magnitude: %.2f / %.2f (want 127)"
						% [str(yaws[i]), str(yaws[j]), a1.length(), a2.length()])
			var ang := rad_to_deg(absf(atan2(a1.cross(a2), a1.dot(a2))))
			var dyaw := absf(wrapf(yaws[j] - yaws[i], -180.0, 180.0))
			if absf(ang - dyaw) > 1.2:
				failures.append("W at yaw %s vs %s: angle between vectors %.2f deg, want the"
						+ " %.2f deg yaw difference" % [str(yaws[i]), str(yaws[j]), ang, dyaw])
	# Direction check: for increasing yaw the captured forward vector's signed cross is negative.
	var b1 := _cap([KEY_W], 10.0)["input"] as RefCounted
	var b2 := _cap([KEY_W], 80.0)["input"] as RefCounted
	var c := Vector2(float(b1.move_x), float(b1.move_z)).cross(
			Vector2(float(b2.move_x), float(b2.move_z)))
	if c >= 0.0:
		failures.append("increasing camera yaw must rotate the move vector the same way "
				+ "(cross %.1f, expected negative)" % c)
	return failures


# --- 4. diagonal clamp, neutral, gamepad ---------------------------------------------------

func _test_diagonal_clamp_and_neutral() -> Array[String]:
	var failures: Array[String] = []
	# W+D at yaw 0: normalized to unit magnitude then scaled -> (90, -90); diagonal never
	# exceeds full speed (D-T010-2 axis contract, D-T082-2 normalization).
	var r := _cap([KEY_W, KEY_D])
	var inp: RefCounted = r["input"]
	if int(inp.move_x) != 90 or int(inp.move_z) != -90:
		failures.append("W+D at yaw 0: expected (90, -90), got (%d, %d)"
				% [int(inp.move_x), int(inp.move_z)])
	# No keys = neutral PlayerInput.
	var rn := _cap([])
	var inp_n: RefCounted = rn["input"]
	if int(inp_n.move_x) != 0 or int(inp_n.move_z) != 0 or int(inp_n.buttons) != 0:
		failures.append("no keys must be neutral (0, 0, 0), got (%d, %d, %d)"
				% [int(inp_n.move_x), int(inp_n.move_z), int(inp_n.buttons)])
	# Saturated stick diagonal is clamped to magnitude 1 too: stick (1, 1) -> magnitude
	# sqrt(2) before the clamp; after: (90, 90) (back-right, no keys needed).
	var rs := _cap([], 0.0, [], 1.0, 1.0)
	var inp_s: RefCounted = rs["input"]
	if int(inp_s.move_x) != 90 or int(inp_s.move_z) != 90:
		failures.append("stick (1,1) at yaw 0: expected (90, 90), got (%d, %d)"
				% [int(inp_s.move_x), int(inp_s.move_z)])
	return failures


# --- 5. camera rig statics (D-T082-1) ------------------------------------------------------

func _test_camera_statics() -> Array[String]:
	var failures: Array[String] = []
	if CameraScript.DISTANCE != 7.0 or CameraScript.PIVOT_HEIGHT != 2.5 \
			or CameraScript.PITCH_DEFAULT != -18.0 or CameraScript.PITCH_MIN != -60.0 \
			or CameraScript.PITCH_MAX != 30.0 or CameraScript.FOV_DEFAULT != 75.0 \
			or not is_equal_approx(CameraScript.MOUSE_SENS_DEFAULT, 0.12) \
			or not is_equal_approx(CameraScript.SPRING_TIME, 0.12):
		failures.append("camera rig constants drifted from D-T082-1")
	# The offset always sits exactly on the 7.0 u sphere, for any yaw and pitch.
	for yaw in [0.0, 47.0, 200.0]:
		for pitch in [-60.0, -18.0, 0.0, 30.0]:
			var off := CameraScript.camera_offset(yaw, pitch)
			if absf(off.length() - 7.0) > 1e-6:
				failures.append("camera_offset(%s, %s) left the 7.0 u sphere: %f"
						% [str(yaw), str(pitch), off.length()])
	# At yaw 0, pitch 0: camera straight behind (+z), level with the pivot.
	var base := CameraScript.camera_offset(0.0, 0.0)
	if absf(base.z - 7.0) > 1e-6 or absf(base.y) > 1e-6 or absf(base.x) > 1e-6:
		failures.append("camera_offset(0, 0) expected (0, 0, 7), got %s" % str(base))
	# Default pitch -18 looks DOWN: camera above the pivot (y > 0) and closer in z.
	var defcam := CameraScript.camera_offset(0.0, -18.0)
	if defcam.y <= 0.0 or defcam.z <= 0.0 or defcam.z >= 7.0:
		failures.append("camera_offset(0, -18) expected above-behind (y>0, 0<z<7), got %s"
				% str(defcam))
	# Pitch clamp: -65 -> -60, +40 -> +30, in-range yaw passes through.
	var l1 := CameraScript.apply_mouse(0.0, -65.0, 0.0, 0.0, 0.12)
	if (l1 as Vector2).y != -60.0:
		failures.append("pitch clamp low: expected -60, got %s" % str((l1 as Vector2).y))
	var l2 := CameraScript.apply_mouse(10.0, 40.0, 0.0, 0.0, 0.12)
	if (l2 as Vector2).y != 30.0 or not is_equal_approx((l2 as Vector2).x, 10.0):
		failures.append("pitch clamp high: expected (x=10, y=30), got %s" % str(l2))
	# Mouse: +10 px right at 0.12 deg/px = yaw -1.2 (Godot yaw + = left); +10 px down pitches
	# DOWN (pitch decreases).
	var m1 := CameraScript.apply_mouse(0.0, -18.0, 10.0, 0.0, 0.12)
	if not is_equal_approx((m1 as Vector2).x, -1.2) or not is_equal_approx((m1 as Vector2).y, -18.0):
		failures.append("mouse right 10 px: expected yaw -1.2, pitch held, got %s" % str(m1))
	var m2 := CameraScript.apply_mouse(-4.0, -18.0, 0.0, 10.0, 0.12)
	if not is_equal_approx((m2 as Vector2).x, -4.0) or not is_equal_approx((m2 as Vector2).y, -19.2):
		failures.append("mouse down 10 px: expected pitch -19.2, yaw held, got %s" % str(m2))
	# Spring: no motion at dt 0; exactly (1 - e^-1) of the way after one time constant;
	# settled after 5 time constants.
	if not is_equal_approx(CameraScript.spring_y(1.0, 1.5, 0.0), 1.0):
		failures.append("spring at dt=0 must not move")
	var s := CameraScript.spring_y(0.0, 0.5, 0.12)
	if absf(s - 0.5 * (1.0 - exp(-1.0))) > 1e-9:
		failures.append("spring after 0.12 s: expected 1-e^-1 of the way, got %f" % s)
	var y := CameraScript.spring_y(0.0, 1.0, 0.6)
	if absf(y - (1.0 - exp(-0.6 / 0.12))) > 1e-9:
		failures.append("spring after dt=0.6 must be 1-e^(-0.6/0.12), got %f" % y)
	# camera_position = feet + pivot height + offset.
	var cp := CameraScript.camera_position(Vector3(3.0, 2.0, -5.0), 0.0, 0.0)
	if not (cp as Vector3).is_equal_approx(Vector3(3.0, 4.5, 2.0)):
		failures.append("camera_position at yaw 0 pitch 0 expected (3, 4.5, 2), got %s" % str(cp))
	return failures


# --- 5b. the mouse-lock guarantee (J5; supersedes the D-T082-4 no-turn pin) -----------------

## J5 REVERSED the shipped no-turn decision: with the mouse CAPTURED, world.gd's
## _unhandled_input turns the rig through apply_mouse() at the settings sensitivity; with
## it RELEASED the camera still must not turn; and the Ctrl toggle (input_capture's
## APP_MOUSE_TOGGLE, edge-detected in world.gd's _mouse_lock_pass) is the ONLY capture
## transition - no other file in app/ may touch the mouse mode, the mouse motion, or the
## rig's yaw. The old test pinned the opposite (any handler fails); it is rewritten here,
## not weakened: the new probe fails unless the gating is present and exclusive.
func _test_no_manual_camera_turn() -> Array[String]:
	var failures: Array[String] = []
	var app_files := _app_gd_files()
	if app_files.size() < 5:
		failures.append("app/ scan found only %d .gd files - the mouse-lock check did not run"
				% app_files.size())
	var motion_files: Array[String] = []
	var mode_files: Array[String] = []
	for name in app_files:
		var f := FileAccess.open("res://app/" + name, FileAccess.READ)
		if f == null:
			failures.append("could not read res://app/%s for the mouse-lock check" % name)
			continue
		var text := f.get_as_text()
		f.close()
		for line in (text as String).split("\n"):
			var code := (line as String).strip_edges()
			if code.begins_with("#"):
				continue
			if code.contains("InputEventMouseMotion") and not motion_files.has(name):
				motion_files.append(name)
			if code.contains("Input.mouse_mode") and not mode_files.has(name):
				mode_files.append(name)
	# Exactly one handler file (world.gd), exactly one mouse-mode writer (world.gd).
	if not (motion_files == ["world.gd"]):
		failures.append("InputEventMouseMotion must appear ONLY in world.gd, found in %s"
				% str(motion_files))
	if not (mode_files == ["world.gd"]):
		failures.append("Input.mouse_mode writes must live ONLY in world.gd, found in %s"
				% str(mode_files))
	if app_files.has("world.gd"):
		# The handler must gate on the lock state BEFORE any apply_mouse call, i.e. the
		# released camera has no turn path inside the handler.
		var body := _func_body("res://app/world.gd", "_unhandled_input")
		var gate := -1
		var apply := -1
		for i in body.size():
			if body[i].contains("_mouse_locked") and gate == -1:
				gate = i
			if body[i].contains("apply_mouse") and apply == -1:
				apply = i
		if gate == -1 or apply == -1 or gate > apply:
			failures.append("world.gd _unhandled_input must check _mouse_locked before"
					+ " apply_mouse (gate line %d, apply line %d in body)" % [gate, apply])
		# The toggle: Ctrl polled in the capture path, the state machine in camera_rig.
		var capture_body := _func_body("res://app/world.gd", "_capture_input")
		var has_ctrl := false
		for line in capture_body:
			if line.contains("KEY_MOUSE_LOCK"):
				has_ctrl = true
		if not has_ctrl:
			failures.append("world.gd _capture_input must poll input_capture's"
					+ " KEY_MOUSE_LOCK - the toggle is the only capture path")
		var rig_text := _file_text("res://app/camera_rig.gd")
		if not rig_text.contains("static func next_mouse_locked"):
			failures.append("camera_rig.gd lost next_mouse_locked (the toggle state machine)")
	else:
		failures.append("world.gd missing from the app/ scan")
	return failures


## The non-comment lines of one named function in one file, from its "func" line to the
## next top-level "func". Empty when the function is absent.
func _func_body(path: String, fname: String) -> Array[String]:
	var out: Array[String] = []
	var inside := false
	for line in _file_text(path).split("\n"):
		var code := (line as String).strip_edges()
		if code.begins_with("func ") or (inside and code.begins_with("func ")):
			if inside:
				break
			inside = code.begins_with("func %s(" % fname)
			continue
		if inside and not code.begins_with("#"):
			out.append(code)
	return out


func _file_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t


## Every .gd file name under res://app/. The no-turn guarantee is a property of the source
## (there is no input path to the camera yaw), so it is checked by reading the source.
func _app_gd_files() -> Array[String]:
	var names: Array[String] = []
	var dir := DirAccess.open("res://app")
	if dir == null:
		return names
	for name in dir.get_files():
		if name.ends_with(".gd"):
			names.append(name)
	return names


func _test_gamepad() -> Array[String]:
	var failures: Array[String] = []
	var ra := _cap([], 0.0, [0])
	if int((ra["input"] as RefCounted).buttons) != SimInputScript.BUTTON_JUMP:
		failures.append("gamepad A (button 0) must produce BUTTON_JUMP, got %d"
				% int((ra["input"] as RefCounted).buttons))
	var rx := _cap([], 0.0, [2])
	if int((rx["input"] as RefCounted).buttons) != SimInputScript.BUTTON_ABILITY:
		failures.append("gamepad X (button 2) must produce BUTTON_ABILITY, got %d"
				% int((rx["input"] as RefCounted).buttons))
	var ry := _cap([], 0.0, [3])
	if int((ry["input"] as RefCounted).buttons) != SimInputScript.BUTTON_INTERACT:
		failures.append("gamepad Y (button 3) must produce BUTTON_INTERACT, got %d"
				% int((ry["input"] as RefCounted).buttons))
	# Left stick full forward (stick_y = -1) at yaw 0 = full speed -z, no buttons.
	var rf := _cap([], 0.0, [], 0.0, -1.0)
	var inp: RefCounted = rf["input"]
	if int(inp.move_x) != 0 or int(inp.move_z) != -127 or int(inp.buttons) != 0:
		failures.append("stick forward at yaw 0: expected (0, -127, no buttons), got (%d, %d, %d)"
				% [int(inp.move_x), int(inp.move_z), int(inp.buttons)])
	# Half stick = half speed (analog, not digital).
	var rh := _cap([], 0.0, [], 0.0, -0.5)
	if int((rh["input"] as RefCounted).move_z) != -64:
		failures.append("stick 0.5 forward: expected move_z -64, got %d"
				% int((rh["input"] as RefCounted).move_z))
	return failures


# --- 6. settings (T-024 addendum made concrete; D-T082-3) ----------------------------------

func _test_settings() -> Array[String]:
	var failures: Array[String] = []
	var s := SettingsScript.new()
	if s.volume != 80 or not is_equal_approx(float(s.mouse_sensitivity), 0.12) \
			or not is_equal_approx(float(s.field_of_view), 75.0) or s.fullscreen != false:
		failures.append("settings defaults drifted: %s" % str(s.to_dict()))
	# Out-of-range values clamp into range on load (never reject, never boot-fail).
	var f := FileAccess.open(SETTINGS_TEST_PATH, FileAccess.WRITE)
	f.store_string("{\"volume\": 250, \"mouse_sensitivity\": 5.0, \"field_of_view\": 10, "
			+ "\"fullscreen\": true}")
	f.flush()
	f = null
	s.load_from(SETTINGS_TEST_PATH)
	if s.volume != 100 or not is_equal_approx(float(s.mouse_sensitivity), 0.30) \
			or not is_equal_approx(float(s.field_of_view), 60.0) or s.fullscreen != true:
		failures.append("out-of-range settings must clamp (100 / 0.30 / 60, fullscreen true), got %s"
				% str(s.to_dict()))
	# Roundtrip: save then load preserves every field.
	s.volume = 55
	s.mouse_sensitivity = 0.2
	s.field_of_view = 83.0
	s.fullscreen = false
	if not s.save_to(SETTINGS_TEST_PATH):
		failures.append("save_to failed")
	var s2 := SettingsScript.new()
	s2.load_from(SETTINGS_TEST_PATH)
	if s2.to_dict() != s.to_dict():
		failures.append("settings roundtrip lost data: saved %s, loaded %s"
				% [str(s.to_dict()), str(s2.to_dict())])
	# Corrupt file = defaults (never a boot failure).
	var fc := FileAccess.open(SETTINGS_TEST_PATH, FileAccess.WRITE)
	fc.store_string("not json at all {{{")
	fc.flush()
	fc = null
	var s3 := SettingsScript.new()
	s3.load_from(SETTINGS_TEST_PATH)
	if s3.volume != 80 or not is_equal_approx(float(s3.mouse_sensitivity), 0.12) \
			or not is_equal_approx(float(s3.field_of_view), 75.0) or s3.fullscreen != false:
		failures.append("corrupt settings file must fall back to defaults, got %s"
				% str(s3.to_dict()))
	# Missing file = defaults too.
	var s4 := SettingsScript.new()
	s4.load_from("user://t82_no_such_settings.json")
	if s4.to_dict() != {"volume": 80, "mouse_sensitivity": 0.12, "field_of_view": 75.0,
			"fullscreen": false}:
		failures.append("missing settings file must fall back to defaults, got %s"
				% str(s4.to_dict()))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_TEST_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://t82_bad_bindings.json"))
	return failures


# --- 7. THE CAMERA NEVER CHANGES SIM STATE: replay with a randomly moved camera ------------

func _test_replay_with_random_camera() -> Array[String]:
	var failures: Array[String] = []
	var inputs := _record_inputs_through_capture()
	var h1 := _replay(RUN_SEED, inputs)
	var h2 := _replay(RUN_SEED, inputs)
	if h1.size() != REPLAY_TICKS / CHECK_EVERY or h2.size() != h1.size():
		failures.append("expected %d checkpoints twice, got %d and %d"
				% [REPLAY_TICKS / CHECK_EVERY, h1.size(), h2.size()])
		return failures
	var mism := 0
	for c in h1.size():
		if h1[c] != h2[c]:
			mism += 1
			failures.append("random-camera replay: checkpoint %d (tick %d) hashes differ"
					% [c, (c + 1) * CHECK_EVERY])
	if mism == 0:
		print("REPLAY-CAMERA %d checkpoints identical with the camera yaw randomized per tick"
				% h1.size())
	# The randomized camera must not have produced a vacuous pass: capture must still show a
	# nonzero move vector and at least one button press somewhere in the stream.
	var moved := false
	var pressed_any := false
	for inp in inputs:
		if int((inp as RefCounted).buttons) != 0:
			pressed_any = true
		if int((inp as RefCounted).move_x) != 0 or int((inp as RefCounted).move_z) != 0:
			moved = true
	if not moved or not pressed_any:
		failures.append("random-camera input generator produced no movement (%s) or no button "
				+ "press (%s) - replay pass would be vacuous" % [str(moved), str(pressed_any)])
	return failures


## The camera waveform is NOT an input and never touches the sim: the LCG below chooses a
## different camera yaw every tick, inputs go through input_capture.capture() (whose move
## vectors are re-rotated by that yaw), and ONLY the resulting PlayerInput structs reach
## SimScript.step. If the rig had any path into sim state, this replay could not be green.
func _record_inputs_through_capture() -> Array:
	var cap_binds := CaptureScript.load_bindings()
	var lcg := 987654321
	var keys := [KEY_W, KEY_W, KEY_W, KEY_D, KEY_S, KEY_A, KEY_SPACE, KEY_SHIFT, KEY_F, KEY_TAB]
	var held: Array = []
	var inputs: Array = []
	for t in REPLAY_TICKS:
		# 32-bit LCG, deterministic: s = (s * 1103515245 + 12345) & 0x7FFFFFFF.
		lcg = (lcg * 1103515245 + 12345) & 0x7FFFFFFF
		var yaw := float(lcg % 360) - 180.0
		lcg = (lcg * 1103515245 + 12345) & 0x7FFFFFFF
		if t % 5 == 0:
			held = [keys[(t / 5) % keys.size()]]
		var frame := CaptureScript.capture(held, [], 0.0, 0.0, yaw, cap_binds)
		inputs.append(frame["input"])
	return inputs


## One fresh run over `inputs`; state hash at every CHECK_EVERY ticks.
func _replay(run_seed: int, inputs: Array) -> Array[String]:
	var rs := RunStateScript.new_run(run_seed, 1, ["core"])
	rs.load_level(VoidGenScript.generate(run_seed, 1, 1, 0), 1)
	var hashes: Array[String] = []
	for t in REPLAY_TICKS:
		SimScript.step(rs, [inputs[t]])
		if (t + 1) % CHECK_EVERY == 0:
			hashes.append(HashScript.sha256(rs))
	return hashes
