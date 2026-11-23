extends Node3D
#
# view/lobby/lobby_scene.gd - the app-facing Antechamber scene (J7).
#
# The node app.gd adds to the tree when the beacon is entered. It owns the three pieces the
# hall needs to be a PLACE rather than a diorama:
#   - view/lobby/antechamber.gd  the hall itself (floor, sigil, walls, props, plaque, gate,
#                                banners, altars, exhibits, panels, the F-hold);
#   - view/lobby/lobby_player.gd the walking player + the third-person camera;
#   - sim/intermission.gd        the state machine the picks land in.
#
# The data flow is the one DESIGN.md section 13 rule 2 pins: the view produces SIM INPUTS.
# tick() asks the antechamber which altar the player is facing and holding F on, and feeds
# that index into Intermission.step() as a PlayerInput's `select`. The view never writes
# lobby state directly and the sim re-validates every pick.
#
# The exit is the Descent Gate (DESIGN.md section 11): closed until every mandatory bay is
# resolved, then open; walking into it emits `exited(ledger)`. The ledger is the run's
# carried state (class / votes / curses / stacks / purse / tithes / hunger / last_vote) -
# app.gd hands it to world.build() for the next level, so the run stays a pure function of
# (seed, level) plus the player's own picks.
#
# Headless-testable: build() and tick() do the whole job without the scene tree or the
# Input singleton (the tests drive tick() directly). step() is the app path: it captures
# the real device state through app/input_capture.gd and then calls tick().

const ContentApiScript := preload("res://core/content_api.gd")
const AssetLoadScript := preload("res://view/asset_load.gd")   # U4: fail-soft loads + material release
const IntermissionScript := preload("res://sim/intermission.gd")
const UpgradeRuntimeScript := preload("res://sim/upgrade_runtime.gd")
const WorldScript := preload("res://app/world.gd")
const InputScript := preload("res://sim/input.gd")
const AntechamberScript := preload("res://view/lobby/antechamber.gd")
const LobbyPlayerScript := preload("res://view/lobby/lobby_player.gd")
const InputCaptureScript := preload("res://app/input_capture.gd")
const CameraRigScript := preload("res://app/camera_rig.gd")
const SettingsScript := preload("res://app/settings.gd")
const VoidRngScript := preload("res://terrain/void_rng.gd")
const FogEnvScript := preload("res://view/fog_env.gd")
const LobbyHudScript := preload("res://view/lobby/lobby_hud.gd")
# The Antechamber's ambience bed (the "too quiet" pass): synthesized by
# game/tools/audio/synth_cues.gd, looped for as long as the hall is in the tree. A missing
# file is silent, never an error (view/audio/cue_audio.gd's house shape).
const AmbienceAudioScript := preload("res://view/audio/ambience_audio.gd")

## The gate's walk-in zone: past this z, inside this half-width, the level ends. The door
## slab is 3.0 u wide (assets_src/blender/descent_gate.py), so 1.4 keeps the player inside
## the opening rather than clipping the pillars.
const GATE_ENTER_Z := -8.0
const GATE_ENTER_X := 1.4

## The lobby draw stream's seed offset - the SAME constant world.gd's replay and
## tools/bot_run.gd use (mix(seed, 5000 + level_completed)), so the hall the player walks
## into is the hall the replay would have resolved.
const LOBBY_SEED_OFFSET := 5000

signal exited(ledger: Dictionary)
signal back_requested()

var lobby: RefCounted = null
var hall: Node3D = null
var player: Node3D = null
var hud: Control = null        # view/lobby/lobby_hud.gd: the purse, top-right
var seed_value := 0
var level_completed := 0
var prompt := ""
var gate_open := false
var unresolved: Array = []      # mandatory bay kinds still open, in schedule order

var _api: RefCounted = null
var _ledger: Dictionary = {}
var _bindings: Dictionary = {}
var _exited := false
var _mouse_locked := true
var _mouse_sens := CameraRigScript.MOUSE_SENS_DEFAULT
var _prev_mouse_toggle := false
var _prev_app_pause := false
var _ambience: AudioStreamPlayer = null   # the lobby bed loop; started in _ready



# U4 (Terra finding 3): release this subtree's surface-override materials before the
# node is destroyed, on EVERY free path (the app's transition or a direct free()):
# a MeshInstance3D's override Refs die before its RS instance is freed, so freeing with
# the overrides still set leaves a dangling material RID and the dummy renderer prints
# `ERROR: Parameter "material" is null` (see asset_load.gd release_materials).
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		AssetLoadScript.release_materials(self)
func _ready() -> void:
	if _bindings.is_empty():
		_bindings = InputCaptureScript.load_bindings()
	_ambience = AmbienceAudioScript.start_lobby(self)


func _exit_tree() -> void:
	# The bed is our own child, so it has already left the tree - and may already be freed -
	# by the time this runs. stop() takes a typed AudioStreamPlayer, so a freed node throws
	# at the call boundary before any guard inside it could run: check here.
	if is_instance_valid(_ambience):
		AmbienceAudioScript.stop(_ambience)
	_ambience = null


## Builds the hall for the level just completed. p_ledger is the run's carried state
## (world.run_ledger()); an empty one starts a fresh run's lobby. Returns false when the
## content registry cannot boot - the caller must not trap the player in a dead hall.
func build(p_seed: int, p_completed: int, p_ledger: Dictionary = {}) -> bool:
	seed_value = p_seed
	level_completed = p_completed
	_ledger = p_ledger.duplicate(true)
	_exited = false
	if _bindings.is_empty():
		_bindings = InputCaptureScript.load_bindings()
	_api = ContentApiScript.load()
	if _api == null or not _api.is_ok():
		push_warning("lobby: content registry failed to boot")
		return false
	lobby = IntermissionScript.create(_api, level_completed, int(_ledger.get("purse", 0)),
			VoidRngScript.mix(seed_value, LOBBY_SEED_OFFSET + level_completed),
			_ledger.get("votes", {}), _ledger.get("curses", {}), _ledger.get("stacks", {}),
			str(_ledger.get("class", "")), int(_ledger.get("tithes", 0)),
			int(_ledger.get("hunger", 0)), str(_ledger.get("last_vote", "")),
			_run_stats(),
			WorldScript.max_stacks_bonus_for(_ledger.get("stacks", {}) as Dictionary,
					str(_ledger.get("class", ""))))
	# The bounty an altar shows is the bounty paid on pick: the owned bounty-granting
	# upgrades get first draw on every unresolved curse bay. Called again after every
	# Select in tick() - a reroll redraws a bay with fresh altars.
	_draw_curse_bays()
	# The hall carries the CURRENT biome's palette and fog (DESIGN.md section 11): the
	# biome the player just walked out of, which is the level just completed.
	var biome := FogEnvScript.biome_id_for_level(maxi(level_completed, 1))
	hall = AntechamberScript.new()
	add_child(hall)
	hall.build_all(_api, lobby, biome, maxi(level_completed, 1))
	# This node drives hall.tick() itself every frame; the hall's own _process convenience
	# path would tick the F-hold a second time per frame.
	hall.set_process(false)
	player = LobbyPlayerScript.new()
	add_child(player)
	player.build(AntechamberScript.SPAWN)
	# The purse HUD (owner defect: the lobby showed no gold at all). On its own CanvasLayer
	# so it draws over the 3D hall; synced from the lobby state every tick.
	var hud_layer := CanvasLayer.new()
	hud_layer.name = "LobbyHudLayer"
	add_child(hud_layer)
	hud = LobbyHudScript.new()
	hud_layer.add_child(hud)
	hud.sync(int(lobby.purse))
	# Lights Out reaches the hall too: the world-computed stats drive both fill lights.
	hall.apply_stats(_run_stats())
	player.apply_stats(_run_stats())
	# Sealed Deals reaches the hall too (T-051): the run's carried curses ARE the held
	# shape ({curse id: stacks} - sim/curse_runtime.gd's held_of), so the ledger's
	# "curses" dict is the curse state the antechamber's reroll query reads.
	hall.set_curses_state({"curses_held": _ledger.get("curses", {}) as Dictionary})
	var sett := SettingsScript.new()
	sett.load_from()
	_mouse_sens = sett.mouse_sensitivity
	_prev_mouse_toggle = false
	_prev_app_pause = false
	_mouse_locked = true
	Input.mouse_mode = CameraRigScript.mouse_mode_for(true)
	_refresh_gate()
	return true


## On-curse-draw pass over the bays as they stand: fresh after create() and after every
## Select (a reroll redraws a bay). stacks are the lobby's live upgrade ledger; the
## loader is the world's shared static one (world.gd's upgrade_module), so this never
## names a module of its own. Returns the number of hook calls made.
func _draw_curse_bays() -> int:
	if lobby == null:
		return 0
	return UpgradeRuntimeScript.curse_draw(lobby.bays, lobby.upgrade_stacks,
			Callable(WorldScript, "upgrade_module"), level_completed)


## The run's always-on stats as world.run_ledger() computed them (shop_price_mul prices the
## shop, fill_light_range the hall's fill lights). {} when the ledger carries none (a fresh
## run's lobby, or a caller that predates the key): every consumer then keeps its canon base.
func _run_stats() -> Dictionary:
	var st: Variant = _ledger.get("stats", {})
	return (st as Dictionary).duplicate() if st is Dictionary else {}


## The app path: capture the real device state, then one tick. The app calls this from its
## own _process at the fixed 60 Hz step, exactly as it steps the world.
func step(p_dt: float) -> void:
	if lobby == null:
		return
	var a_in: Dictionary = _capture_input()
	_mouse_lock_pass(int(a_in.get("app", 0)))
	var buttons := int(a_in.get("buttons", 0))
	tick(p_dt, int(a_in.get("move_x", 0)), int(a_in.get("move_z", 0)),
			(buttons & InputCaptureScript.BUTTON_INTERACT) != 0)


## One lobby tick. p_move_x / p_move_z are the captured int8 world axes; p_interact is the
## F key held. Returns {"select", "prompt", "gate_open", "unresolved", "exited"}.
## The Select the antechamber reports is applied through Intermission.step() - the sim's
## own input path - and never written into the lobby state directly.
func tick(p_dt: float, p_move_x: int, p_move_z: int, p_interact: bool) -> Dictionary:
	var out := {"select": IntermissionScript.NO_SELECT, "prompt": "", "gate_open": false,
			"unresolved": [], "exited": false}
	if lobby == null or hall == null or player == null:
		return out
	player.move(p_dt, p_move_x, p_move_z)
	var res: Dictionary = hall.tick(p_dt, player.feet(), player.look_dir(), p_interact)
	prompt = str(res.get("prompt", ""))
	out["prompt"] = prompt
	var sel := int(res.get("select", IntermissionScript.NO_SELECT))
	if sel != IntermissionScript.NO_SELECT:
		# votes ARE inputs (DESIGN.md section 13 rule 2): the pick rides a PlayerInput.
		lobby.step([InputScript.new(0, 0, 0, sel)])
		# on_curse_draw again: the Select above may be a reroll, which redraws a bay
		# with fresh altars that no pass has seen yet. Idempotent per bay.
		_draw_curse_bays()
		out["select"] = sel
	# the purse after this tick's pick (a purchase, a tithe, a reroll or a curse bounty)
	if hud != null:
		hud.sync(int(lobby.purse))
	_refresh_gate()
	out["gate_open"] = gate_open
	out["unresolved"] = unresolved.duplicate()
	if gate_open and not _exited and _in_gate():
		_exited = true
		out["exited"] = true
		# The hall releases its own capture on the way out: the next level's build()
		# captures again, and a failed build lands on the menu with a visible cursor.
		_mouse_locked = false
		Input.mouse_mode = CameraRigScript.mouse_mode_for(false)
		exited.emit(ledger())
	return out


## The run's carried state after this visit: what world.build() needs for the next level.
func ledger() -> Dictionary:
	if lobby == null:
		return _ledger.duplicate(true)
	return {
		"class": str(lobby.class_chosen),
		"votes": (lobby.votes as Dictionary).duplicate(),
		"curses": (lobby.curses_held as Dictionary).duplicate(),
		"stacks": (lobby.upgrade_stacks as Dictionary).duplicate(),
		"purse": int(lobby.purse),
		"tithes": int(lobby.tithes),
		"hunger": int(lobby.hunger),
		"last_vote": str(lobby.last_vote),
	}


## True once the player has walked into the open gate (the level is over).
func has_exited() -> bool:
	return _exited


## The next level this lobby leads to.
func next_level() -> int:
	return level_completed + 1


## Frees the hall and releases the mouse. Safe to call twice; the app calls it before
## queue_free-ing the node (the same teardown contract world.gd has).
func teardown() -> void:
	for child in get_children():
		child.free()
	hall = null
	player = null
	hud = null
	lobby = null
	_api = null
	prompt = ""
	gate_open = false
	unresolved = []
	_mouse_locked = false
	_prev_mouse_toggle = false
	_prev_app_pause = false
	Input.mouse_mode = CameraRigScript.mouse_mode_for(false)


# ---- gate ------------------------------------------------------------------------------

## The gate's state and the bays still blocking it (DESIGN.md section 11: the gate opens
## only when every mandatory bay is resolved; the hall shows which are unresolved).
func _refresh_gate() -> void:
	gate_open = lobby != null and bool(lobby.gate_open())
	unresolved = []
	if lobby == null:
		return
	var has_class_bay := false
	for bay in lobby.bays:
		var kind := str(bay["kind"])
		if kind == "CLASS":
			has_class_bay = true
		if kind != "E" and kind != "C":
			continue
		if not bool(bay.get("resolved", false)):
			unresolved.append(kind)
	# The CLASS bay gates only the pre-run lobby (sim/intermission.gd gate_open() checks
	# class_chosen inside the CLASS branch, so a lobby without one never waits for it).
	if has_class_bay and str(lobby.class_chosen) == "":
		unresolved.append("CLASS")


func _in_gate() -> bool:
	var p: Vector3 = player.feet()
	return p.z <= GATE_ENTER_Z and absf(p.x) <= GATE_ENTER_X


# ---- input -----------------------------------------------------------------------------

## Keyboard/gamepad -> the same dictionary world.gd's _capture_input() builds, through the
## real app/input_capture.gd path against data/bindings.json (no key is named here).
func _capture_input() -> Dictionary:
	var kb: Dictionary = _bindings.get("key_bindings", {})
	var keys: Array = []
	var seen := {}
	for action in kb.keys():
		for code in kb[action]:
			var c := int(code)
			if seen.has(c):
				continue
			seen[c] = true
			if Input.is_key_pressed(c):
				keys.append(c)
	var joy: Array = []
	var jb: Dictionary = _bindings.get("joy_bindings", {})
	var stick_x := 0.0
	var stick_y := 0.0
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		var device: int = int(pads[0])
		for action in jb.keys():
			var idx := int(jb[action])
			if Input.is_joy_button_pressed(device, idx):
				joy.append(idx)
		stick_x = Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
		stick_y = Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)
	var yaw := 0.0
	if player != null and player.rig != null:
		yaw = float(player.rig.yaw_deg)
	var res: Dictionary = InputCaptureScript.capture(keys, joy, stick_x, stick_y, yaw, _bindings,
			Input.is_key_pressed(InputCaptureScript.KEY_MOUSE_LOCK))
	var pi: RefCounted = res["input"]
	return {"move_x": int(pi.move_x), "move_z": int(pi.move_z), "buttons": int(pi.buttons),
			"app": int(res.get("app", 0))}


## Ctrl toggles the mouse capture; the pause edge forces a release (the same state machine
## world.gd runs, app/camera_rig.gd's next_mouse_locked).
func _mouse_lock_pass(p_flags: int) -> void:
	var toggled := (p_flags & InputCaptureScript.APP_MOUSE_TOGGLE) != 0
	var paused := (p_flags & InputCaptureScript.APP_PAUSE) != 0
	_mouse_locked = CameraRigScript.next_mouse_locked(
			_mouse_locked, toggled and not _prev_mouse_toggle, paused and not _prev_app_pause)
	_prev_mouse_toggle = toggled
	_prev_app_pause = paused
	Input.mouse_mode = CameraRigScript.mouse_mode_for(_mouse_locked)


## Apply the current lock state to the engine. The pause overlay releases and restores the
## mouse by setting _mouse_locked and calling this, the same contract world.gd offers - the
## lobby is the other state the overlay can freeze, so it must answer the same call.
func apply_mouse_mode() -> void:
	Input.mouse_mode = CameraRigScript.mouse_mode_for(_mouse_locked)


## Mouse motion -> the camera, only while captured (the level's rule, J5).
func _unhandled_input(event: InputEvent) -> void:
	if not _mouse_locked or player == null:
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		player.apply_mouse(float(mm.relative.x), float(mm.relative.y), _mouse_sens)
