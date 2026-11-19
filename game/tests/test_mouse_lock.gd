extends RefCounted
#
# Mouse-lock tests (J5, Part C): Ctrl toggles the mouse capture; captured, mouse motion
# turns the rig and the cursor is hidden; released, the cursor shows and the camera must
# not turn. The state machine itself is camera_rig.next_mouse_locked (pure) and the flag
# rides input_capture's APP_* mask, so both halves are pin-able headless:
#   1. capture() raises APP_MOUSE_TOGGLE (and never the buttons bitmask), and composes
#      with APP_PAUSE;
#   2. next_mouse_locked: a toggle flips, a release wins over a same-tick toggle, no
#      edge holds the state;
#   3. mouse_mode_for maps to the engine Input modes;
#   4. world.gd's _mouse_lock_pass wiring: build() starts captured (asserted via a real
#      level build), the toggle edge flips the state, the APP_PAUSE edge releases, and a
#      held flag (no edge) never re-toggles.
# The scan-level guarantee (who may touch the mouse mode / motion) lives in
# test_input.gd's _test_no_manual_camera_turn, rewritten for the same job.

const CaptureScript := preload("res://app/input_capture.gd")
const CameraScript := preload("res://app/camera_rig.gd")
const WorldScript := preload("res://app/world.gd")

const DT := 1.0 / 60.0
const SEED := 1
const LEVEL := 1


func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_test_capture_flags())
	failures.append_array(_test_toggle())
	failures.append_array(_test_mouse_mode_map())
	failures.append_array(_test_world_wiring())
	return failures


func _test_capture_flags() -> Array[String]:
	var f: Array[String] = []
	var b := CaptureScript.load_bindings()
	if not (b["errors"] as Array).is_empty():
		f.append("bindings unreadable, cannot test capture flags")
		return f
	var none := CaptureScript.capture([], [], 0.0, 0.0, 0.0, b, false)
	if int(none["app"]) != 0:
		f.append("no keys and no Ctrl: app flags must be 0, got %d" % int(none["app"]))
	if int((none["input"] as RefCounted).buttons) != 0:
		f.append("APP_MOUSE_TOGGLE must never enter the buttons bitmask")
	var lock := CaptureScript.capture([], [], 0.0, 0.0, 0.0, b, true)
	if int(lock["app"]) != CaptureScript.APP_MOUSE_TOGGLE:
		f.append("Ctrl held: expected APP_MOUSE_TOGGLE (%d), got %d"
				% [CaptureScript.APP_MOUSE_TOGGLE, int(lock["app"])])
	# A held movement key beside Ctrl: flags and move stay independent channels.
	var both := CaptureScript.capture([KEY_CTRL], [], 0.0, 0.0, 0.0, b, true)
	if int(both["app"]) != CaptureScript.APP_MOUSE_TOGGLE:
		f.append("Ctrl via pressed_keys + flag: expected APP_MOUSE_TOGGLE, got %d"
				% int(both["app"]))
	return f


func _test_toggle() -> Array[String]:
	var f: Array[String] = []
	var t := [[true, true, true], [true, true, false], [true, false, false],
			[false, true, false], [false, false, false], [false, true, true]]
	#            locked  toggle  release  -> expected
	var want := [false, false, true, true, false, false]
	for i in t.size():
		var got := CameraScript.next_mouse_locked(t[i][0], t[i][1], t[i][2])
		if got != want[i]:
			f.append("next_mouse_locked(locked=%s, toggle=%s, release=%s): expected %s, got %s"
					% [str(t[i][0]), str(t[i][1]), str(t[i][2]), str(want[i]), str(got)])
	# A held toggle (no edge) is state-preserving: the caller edge-detects, but even a
	# held flag must not oscillate through this function.
	if CameraScript.next_mouse_locked(true, true, false) != false:
		f.append("toggle on a locked rig must release")
	return f


func _test_mouse_mode_map() -> Array[String]:
	var f: Array[String] = []
	if CameraScript.mouse_mode_for(true) != Input.MOUSE_MODE_CAPTURED:
		f.append("mouse_mode_for(true) must be MOUSE_MODE_CAPTURED")
	if CameraScript.mouse_mode_for(false) != Input.MOUSE_MODE_VISIBLE:
		f.append("mouse_mode_for(false) must be MOUSE_MODE_VISIBLE")
	return f


func _test_world_wiring() -> Array[String]:
	var f: Array[String] = []
	var world = WorldScript.new()
	if not world.build(SEED, LEVEL):
		f.append("world failed to build level %d seed %d - cannot test the lock wiring"
				% [LEVEL, SEED])
		world.free()
		return f
	# A level begins CAPTURED.
	if not bool(world._mouse_locked):
		f.append("build() must start the level with the mouse captured")
	world.teardown()
	# teardown = the menu: released.
	if bool(world._mouse_locked):
		f.append("teardown() (the menu) must release the mouse")
	world.free()

	# The state machine over _mouse_lock_pass: toggle edge, hold (no edge), pause release,
	# release-wins-over-toggle. Needs a world enough for the pass to run (it touches no
	# sim object), but build() for a level-started capture state.
	var w2 = WorldScript.new()
	w2._mouse_locked = true
	w2._prev_mouse_toggle = false
	w2._prev_app_pause = false
	w2._mouse_lock_pass(CaptureScript.APP_MOUSE_TOGGLE)   # Ctrl edge: release
	if bool(w2._mouse_locked):
		f.append("toggle edge on a captured level must release the mouse")
	w2._mouse_lock_pass(CaptureScript.APP_MOUSE_TOGGLE)   # flag held, no edge: no re-toggle
	if bool(w2._mouse_locked):
		f.append("a held Ctrl (no edge) must not re-toggle the state")
	w2._mouse_lock_pass(0)
	if bool(w2._mouse_locked):
		f.append("no app flags must not change the lock state")
	w2._mouse_lock_pass(CaptureScript.APP_MOUSE_TOGGLE)   # fresh edge: capture again
	if not bool(w2._mouse_locked):
		f.append("a second Ctrl edge must re-capture")
	w2._mouse_lock_pass(CaptureScript.APP_PAUSE)          # the pause edge: forced release
	if bool(w2._mouse_locked):
		f.append("the APP_PAUSE edge must release the mouse")
	w2._mouse_locked = true
	w2._prev_app_pause = false
	w2._mouse_lock_pass(CaptureScript.APP_PAUSE | CaptureScript.APP_MOUSE_TOGGLE)
	if bool(w2._mouse_locked):
		f.append("a release must win over a same-tick toggle")
	w2._mouse_locked = false
	w2.free()
	return f
