extends RefCounted
#
# Input capture (ticket T-082). Turns one frame of DEVICE STATE (which keys / gamepad buttons
# are held, the left-stick axes) into the sim's PlayerInput (game/sim/input.gd, T-010) with the
# move vector PRE-ROTATED by the camera yaw (DESIGN.md section 13 rule 2) and QUANTIZED to int8
# (D-T010-2), plus the two app-level actions the sim never sees (HUD toggle, pause).
#
# Pure RefCounted, no Node, no engine Input singleton: the app main scene feeds it values, so
# the headless test can too (and the same key sequence at two camera yaws is provable).
#
# Bindings come from res://data/bindings.json (D-T082-2): keyboard by KEY_* name, gamepad by
# JOY button index. Semantics: the JUMP bit is "held" — hold = glide (Glider) and release-cut
# of the variable jump are the sim reading the bit over time (T-012 controller); the INTERACT
# bit is also "held" — the 0.35 s hold-to-confirm tally at altars is altar-view logic
# (DESIGN.md section 11), not capture. Hud/pause are level-triggered here; whoever calls
# capture() edge-detects them against the previous frame (a menu is a modal overlay, not sim).

const InputScript := preload("res://sim/input.gd")

## Button bits the SIM receives (must match sim/input.gd exactly).
const BUTTON_JUMP := 1
const BUTTON_ABILITY := 2
const BUTTON_INTERACT := 4

## App-level action flags in the returned dictionary (never enter the buttons bitmask).
const APP_HUD_TOGGLE := 1
const APP_PAUSE := 2
const APP_MOUSE_TOGGLE := 4

## The mouse-lock key (Ctrl). Deliberately NOT a bindings.json action: bindings.json is
## the sim-facing action set (T-082-2) and has no mouse-lock row, so the key is named
## here and the caller polls it like the other device state. Changing all capture()
## call shapes to thread an extra bool is the same cost with less ceremony.
const KEY_MOUSE_LOCK := KEY_CTRL

const AXIS_127 := 127.0

## Every key name bindings.json may use, with its Godot key code. A binding naming anything
## else is a load error (the file is data, not code, and there is no eval in GDScript).
const KEY_NAMES := {
	"KEY_W": KEY_W,
	"KEY_A": KEY_A,
	"KEY_S": KEY_S,
	"KEY_D": KEY_D,
	"KEY_SPACE": KEY_SPACE,
	"KEY_SHIFT": KEY_SHIFT,
	"KEY_F": KEY_F,
	"KEY_TAB": KEY_TAB,
	"KEY_ESCAPE": KEY_ESCAPE,
}

## The actions capture() knows. Movement actions produce the move vector, the rest produce
## bits or app flags. data/bindings.json must define exactly these.
const ACTIONS := [
	"move_forward", "move_back", "move_left", "move_right",
	"jump", "ability", "interact", "hud_toggle", "pause",
]


## Parse + validate the bindings file, resolving KEY_* names to key codes. Returns
## {"key_bindings": {action -> Array[int]}, "joy_bindings": {action -> int}, "errors": [...]}.
## A non-empty errors array means refuse to capture (call with defaults instead of guessing).
static func load_bindings(path: String = "res://data/bindings.json") -> Dictionary:
	var errors: Array[String] = []
	var key_bindings := {}
	var joy_bindings := {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("cannot open %s (FileAccess error %d)" % [path, FileAccess.get_open_error()])
	else:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) != TYPE_DICTIONARY:
			errors.append("%s: not a JSON object" % path)
		else:
			var d: Dictionary = parsed
			for action in ACTIONS:
				key_bindings[action] = _resolve_keys(d, action, errors)
			var gamepad: Variant = d.get("gamepad", {})
			if typeof(gamepad) == TYPE_DICTIONARY:
				for action in ["jump", "ability", "interact"]:
					if gamepad.has(action):
						joy_bindings[action] = int(gamepad[action])
					else:
						errors.append("%s: gamepad binding '%s' missing" % [path, action])
			else:
				errors.append("%s: 'gamepad' is not an object" % path)
	return {"key_bindings": key_bindings, "joy_bindings": joy_bindings, "errors": errors}


static func _resolve_keys(d: Dictionary, action: String, errors: Array[String]) -> Array[int]:
	var codes: Array[int] = []
	var raw: Variant = d.get(action, [])
	if typeof(raw) != TYPE_ARRAY:
		errors.append("binding '%s' is not a list" % action)
		return codes
	for name_v in raw:
		var s := str(name_v)
		if KEY_NAMES.has(s):
			codes.append(int(KEY_NAMES[s]))
		else:
			errors.append("binding '%s' names unknown key %s" % [action, s])
	return codes


## One frame of capture. Arguments:
##   pressed_keys:  Array of Godot key codes held this frame (expression: Input.is_key_pressed
##                  over the state the app already polled — never the Input singleton here);
##   pressed_joy:   Array of joy button indices held this frame;
##   stick_x:       left stick horizontal, -1 (left) .. +1 (right);
##   stick_y:       left stick vertical, -1 (forward) .. +1 (back) — Godot stick convention;
##   camera_yaw_deg: the camera rig's yaw this frame;
##   bindings:      a load_bindings() result.
## Returns {"input": PlayerInput (sim/input.gd), "app": APP_* flags}. The move vector is the
## combined keyboard + stick direction, normalized to magnitude <= 1 so a diagonal never
## exceeds run speed, rotated by the camera yaw (yaw 0 = world forward -z), scaled to the
## int8 axis (127 == full speed, D-T010-2) and rounded.
static func capture(pressed_keys: Array, pressed_joy: Array, stick_x: float, stick_y: float,
		camera_yaw_deg: float, bindings: Dictionary,
		mouse_lock_pressed: bool = false) -> Dictionary:
	var kb: Dictionary = bindings.get("key_bindings", {})
	var jb: Dictionary = bindings.get("joy_bindings", {})

	var lx := stick_x + _axis_stroke(pressed_keys, kb, "move_right", 1.0) \
			+ _axis_stroke(pressed_keys, kb, "move_left", -1.0)
	var lz := stick_y + _axis_stroke(pressed_keys, kb, "move_back", 1.0) \
			+ _axis_stroke(pressed_keys, kb, "move_forward", -1.0)
	var mag := sqrt(lx * lx + lz * lz)
	if mag > 1.0:
		lx /= mag
		lz /= mag
	var rad := deg_to_rad(camera_yaw_deg)
	var move_x := roundi((lx * cos(rad) + lz * sin(rad)) * AXIS_127)
	var move_z := roundi((-lx * sin(rad) + lz * cos(rad)) * AXIS_127)

	var buttons := 0
	if _held(pressed_keys, kb, "jump") or _joy_held(pressed_joy, jb, "jump"):
		buttons |= BUTTON_JUMP
	if _held(pressed_keys, kb, "ability") or _joy_held(pressed_joy, jb, "ability"):
		buttons |= BUTTON_ABILITY
	if _held(pressed_keys, kb, "interact") or _joy_held(pressed_joy, jb, "interact"):
		buttons |= BUTTON_INTERACT

	var app := 0
	if _held(pressed_keys, kb, "hud_toggle"):
		app |= APP_HUD_TOGGLE
	if _held(pressed_keys, kb, "pause"):
		app |= APP_PAUSE
	if mouse_lock_pressed:
		app |= APP_MOUSE_TOGGLE

	return {"input": InputScript.new(move_x, move_z, buttons), "app": app}


# +1.0/-1.0 stroke for a direction action when any of its keys is held.
static func _axis_stroke(pressed_keys: Array, kb: Dictionary, action: String, sign_: float) -> float:
	if _held(pressed_keys, kb, action):
		return sign_
	return 0.0


static func _held(pressed_keys: Array, kb: Dictionary, action: String) -> bool:
	for code in kb.get(action, []):
		if pressed_keys.has(code):
			return true
	return false


static func _joy_held(pressed_joy: Array, jb: Dictionary, action: String) -> bool:
	return jb.has(action) and pressed_joy.has(int(jb[action]))
