extends Node3D
#
# Reusable playable level (ticket APP-FLOW): the assembled sim + view of one level as a
# Node3D the app orchestrator can add to the tree. Adapted from game/tools/perf_probe.gd's
# working _build_scene() assembly: voidgen.generate -> collision.make_world ->
# level_mesher.build (one MeshInstance3D per mesh) -> fog_env WorldEnvironment configured
# for the level's biome -> controller -> camera_rig -> enemy_runtime -> one billboard per
# enemy, PLUS view/hud/hud.gd (the probe has no HUD; this is the real game scene).
#
# Differences from the probe, by ticket:
#   - the enemy plan is the run's OWN seeded plan, not the probe's hardcoded VOTE_LIST:
#     the pre-run/intermission votes for this level are resolved by replaying the
#     intermissions the run would have seen (level_completed 0..level-1) with the sim's
#     own Intermission/Offers systems, seeded from the run seed, and the resulting votes
#     dict IS the plan (bot_run.gd's resolving idiom; "votes ARE inputs", DESIGN.md
#     section 13 rule 2). U / REST bays are never touched (no purchase policy is
#     invented); an empty mandatory C draw is tithe-passed when affordable, exactly the
#     bot's rule. For level 1 this replays the pre-run lobby (CLASS + the one starter
#     E bay). Class comes from the CLASS bay the same way; "dasher" when unset.
#   - the HUD is a CanvasLayer child (a Control cannot render under a Node3D).
#
# The run seed reaches the controller and the camera unchanged; the ENEMY runtime gets the
# same run seed (spawn stream), the intermissions are seeded mix(seed, 5000 + lobby) /
# mix(mix(seed, 0xB07), lobby + 1) exactly as the bot seeds them, so the whole level is a
# pure function of (seed, level).
#
# public API:
#   func build(seed_value: int, level: int) -> bool  # false on generator/content failure, never crash
#   func step(dt: float) -> void                     # one sim tick + view pass
#   func teardown() -> void
#   func level_number() -> int
#
# Known gaps, on purpose (logged in DECISIONS.md D-APPFLOW-4, D-APPFLOW-5):
#   - step() ticks exactly controller + enemy_runtime + billboards + camera rig (the
#     ticket's step spec). gifts / mines / beacon are NOT ticked: that needs a LevelState
#     owner decision (gift collection drives the beacon-open path); the HUD gift counter
#     therefore shows 0/0 until then.
#   - curse sim knobs (rush_hour / long_night / early_bird / ...) are NOT applied to the
#     controller or the runtime; only class + enemy votes ride the resolved lobbies.

const VoidGenScript := preload("res://terrain/voidgen.gd")
const CollisionScript := preload("res://sim/collision.gd")
const MesherScript := preload("res://view/level_mesher.gd")
const ControllerScript := preload("res://sim/controller.gd")
const CameraRigScript := preload("res://app/camera_rig.gd")
const EnemyRuntimeScript := preload("res://sim/enemy_runtime.gd")
const BillboardScript := preload("res://view/billboard.gd")
const FogEnvScript := preload("res://view/fog_env.gd")
const HudScript := preload("res://view/hud/hud.gd")
const ContentApiScript := preload("res://core/content_api.gd")
const IntermissionScript := preload("res://sim/intermission.gd")
const VoidRngScript := preload("res://terrain/void_rng.gd")
const InputCaptureScript := preload("res://app/input_capture.gd")

const DT := 1.0 / 60.0
const FALLBACK_CLASS := "dasher"   # D-APPFLOW-6 when the CLASS bay somehow resolved to ""

var lv: Dictionary = {}
var w: Dictionary = {}
var ctl = null
var rt = null
var rig: Node3D = null
var camera: Camera3D = null
var fog: WorldEnvironment = null
var hud: Control = null
var boards: Array = []          # EnemyRuntime enemies index -> billboard node (or null)

var _hud_layer: CanvasLayer = null
var _mesh_instances: Array = []
var _level_number: int = 0
var _roster: Array = []          # [{id, name, count}] built from the resolved votes
var _bindings: Dictionary = {}
var _api: RefCounted = null


func _ready() -> void:
	if _bindings.is_empty():
		_load_bindings()


func _load_bindings() -> void:
	_bindings = InputCaptureScript.load_bindings()
	if not (_bindings.get("errors", []) as Array).is_empty():
		push_warning("world: bindings unreadable, keyboard input disabled: %s"
				% str(_bindings["errors"]))


## Build the level. Returns false on generator/content failure; never crashes.
func build(seed_value: int, level: int) -> bool:
	teardown()
	if _bindings.is_empty():
		_load_bindings()
	lv = VoidGenScript.generate(seed_value, level, 1, 0)
	if lv.is_empty():
		push_warning("world: voidgen.generate(%d, %d) returned {}" % [seed_value, level])
		return false
	w = CollisionScript.make_world(lv["tiles"], lv["props"], lv["pads"], {"dais": lv["beacon"]})

	# The run's own seeded plan for this level: replay the lobbies before it.
	_api = ContentApiScript.load()
	if _api == null or not _api.is_ok():
		push_warning("world: content registry failed to boot; cannot vote the level plan")
		teardown()
		return false
	var plan := _resolve_run(seed_value, level)
	if plan.is_empty():
		teardown()
		return false

	var kit := str(plan.get("class", ""))
	if kit == "":
		kit = FALLBACK_CLASS   # D-APPFLOW-6
	ctl = ControllerScript.new()
	ctl.setup(kit, ControllerScript.load_constants())
	ctl.place(w)

	rt = EnemyRuntimeScript.new()
	rt.setup(lv, w, [ctl], seed_value, {})
	for id in (plan["votes"] as Dictionary).keys():
		var n := int(plan["votes"][id])
		if n <= 0:
			continue
		var eid := str(id)
		var entry: Dictionary = _api.enemy(eid)
		var beh = _behavior_for(eid)
		var cfg := _cfg_for(entry, eid, level, n)
		if beh == null or cfg.is_empty():
			push_warning("world: enemy plan row unreadable: %s" % eid)
			teardown()
			return false
		rt.plan(eid, str(cfg.get("name", eid)), beh, cfg, n)
		_roster.append({"id": eid, "name": str(cfg.get("name", eid)), "count": n})

	# Level geometry. Built always (not only windowed, unlike the probe): this IS the
	# playable scene; the headless gate builds it too (test_mesh.gd meshes headless).
	var mesher: Dictionary = MesherScript.build(lv)
	for mn in mesher["meshes"]:
		var mi := MeshInstance3D.new()
		mi.mesh = mesher["meshes"][mn]
		add_child(mi)
		_mesh_instances.append(mi)

	# Fog / environment for the level's biome (act table; 31+ cycles, D-T014c-1).
	fog = FogEnvScript.new()
	fog.configure(FogEnvScript.biome_id_for_level(level), level)
	add_child(fog)

	# Third-person camera rig (app/camera_rig.gd defaults - the "normal third-person" view).
	rig = CameraRigScript.new()   # the rig's defaults are its D-T082-1 values
	rig.yaw_deg = 0.0
	var cam := Camera3D.new()
	rig.add_child(cam)
	add_child(rig)
	# dt=1.0 snaps the height spring onto the feet (a dt=0 call is a documented no-op).
	rig.update_rig(Vector3(float(ctl.x), float(ctl.y), float(ctl.z)), 1.0)
	cam.fov = CameraRigScript.FOV_DEFAULT
	cam.current = true
	camera = cam

	# HUD (CanvasLayer: a Control child of a Node3D never reaches the canvas).
	_hud_layer = CanvasLayer.new()
	add_child(_hud_layer)
	hud = HudScript.new()
	_hud_layer.add_child(hud)
	_sync_hud()

	_level_number = level
	return true


## One sim tick (controller + enemy runtime) plus the view pass (billboards, camera rig,
## HUD sync). dt is the fixed 60 Hz step; headless callers drive it directly.
func step(dt: float) -> void:
	if ctl == null or rt == null:
		return
	ctl.step(dt, _capture_input(), w)
	rt.step(dt)
	if rig != null:
		rig.update_rig(Vector3(float(ctl.x), float(ctl.y), float(ctl.z)), dt)
	_billboard_pass(dt)
	_sync_hud()


## Free everything build() created and reset the sim references. Safe to call twice; the
## app calls it before queue_free-ing the node.
func teardown() -> void:
	for child in get_children():
		child.free()
	_mesh_instances.clear()
	boards.clear()
	_roster.clear()
	ctl = null
	rt = null
	rig = null
	camera = null
	fog = null
	hud = null
	_hud_layer = null
	lv = {}
	w = {}
	_level_number = 0


func level_number() -> int:
	return _level_number


# ---- the run's own seeded plan (replay the lobbies before this level) -----------------------

## Resolve the intermissions the run would have seen (level_completed 0..level-1) with the
## sim's own Intermission state machine, seeded exactly the way tools/bot_run.gd seeds its
## bot: lobby n from mix(seed, 5000 + n), pick stream mix(mix(seed, 0xB07), n + 1), uniform
## random among the unresolved mandatory bays (CLASS / E / C), U and REST untouched, an
## empty mandatory C draw tithe-passed when affordable. Returns
## {"class": String, "votes": Dictionary, "curses": Dictionary} or {} on failure.
func _resolve_run(seed_value: int, level: int) -> Dictionary:
	var votes := {}
	var curses := {}
	var stacks := {}
	var purse := 0
	var tithes := 0
	var hunger := 0
	var last_vote := ""
	var class_chosen := ""
	for completed in range(0, level):
		var lb: RefCounted = IntermissionScript.create(_api, completed, purse,
				VoidRngScript.mix(seed_value, 5000 + completed), votes, curses, stacks,
				class_chosen, tithes, hunger, last_vote)
		var rng: RefCounted = VoidRngScript.new(VoidRngScript.mix(
				VoidRngScript.mix(seed_value, 0xB07), completed + 1))
		for _i in range(80):
			if bool(lb.gate_open()):
				break
			var table: Array = lb.altar_table()
			var picks: Array[int] = []
			var tithe_picks: Array[int] = []
			for i in table.size():
				var entry: Dictionary = table[i]
				var bay: Dictionary = lb.bays[int(entry["bay_index"])]
				if bool(bay.get("resolved", false)):
					continue
				var kind := str(entry["kind"])
				var bay_kind := str(bay["kind"])
				if kind == "offer" and (bay_kind == "CLASS" or bay_kind == "E" or bay_kind == "C"):
					picks.append(i)
				elif kind == "tithe" and bay_kind == "C":
					tithe_picks.append(i)
			var ev: Array = []
			if not picks.is_empty():
				lb.apply_select(0, picks[rng.urange(picks.size())], ev)
			elif not tithe_picks.is_empty():
				if not bool(lb.apply_select(0, tithe_picks[0], ev)):
					break
			else:
				break
		if not bool(lb.gate_open()):
			push_warning("world: lobby %d did not resolve its mandatory bays" % completed)
			return {}
		votes = lb.votes
		curses = lb.curses_held
		stacks = lb.upgrade_stacks
		purse = int(lb.purse)
		tithes = int(lb.tithes)
		hunger = int(lb.hunger)
		last_vote = str(lb.last_vote)
		class_chosen = str(lb.class_chosen)
	return {"class": class_chosen, "votes": votes, "curses": curses}


# Per-id behavior construction: the content module's factory shape differs per enemy
# (bot_run.gd's table, duplicated here the same way the probe duplicated it).
func _behavior_for(id: String):
	var K = load("res://content/enemies/%s/enemy.gd" % id)
	if K == null:
		return null
	match id:
		"kiwi_cat": return K.KiwiCatBehavior.new()
		"seal": return K.SealBehavior.new()
		"gift_larper": return K.GiftLarperBehavior.new()
		"isagi": return K.Behavior.new()
		"coil": return K.behavior()
		"toucher": return K.behavior()
		"thicc_ben": return K.new_behavior()
		_: return K.new()   # the file-as-behavior module (you, nuke, address_me, claude, gin)


## The runtime cfg for one planned enemy: the enemy.json stats block with the top-level
## contact_kill / preferred_kind / arbiter keys the runtime reads, stamped with name /
## votes / level_number (bot_run.gd's shape; isagi additionally wants the nested stats).
func _cfg_for(entry: Dictionary, id: String, level: int, votes: int) -> Dictionary:
	if entry.is_empty():
		return {}
	var stats: Dictionary = (entry.get("stats", {}) as Dictionary).duplicate(true)
	for key in ["contact_kill", "preferred_kind", "arbiter"]:
		if entry.has(key) and not stats.has(key):
			stats[key] = entry[key]
	stats["id"] = id
	stats["name"] = str(entry.get("name", id))
	stats["votes"] = votes
	stats["level_number"] = level
	if id == "isagi":
		stats["stats"] = (entry.get("stats", {}) as Dictionary).duplicate(true)
	return stats


# ---- per-frame view passes ------------------------------------------------------------------

## Keyboard/gamepad -> PlayerInput, pre-rotated by the camera yaw and quantized to int8
## (D-T010-2), through the real app/input_capture.gd path against data/bindings.json.
func _capture_input():
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
	if rig != null:
		yaw = float(rig.yaw_deg)
	var res: Dictionary = InputCaptureScript.capture(keys, joy, stick_x, stick_y, yaw, _bindings)
	var pi: RefCounted = res["input"]
	# PlayerInput -> the Dictionary the controller reads (buttons/move_x/move_z/aim_*).
	# Aim follows the move stick/keys (no separate aim device exists yet).
	var mx := int(pi.move_x)
	var mz := int(pi.move_z)
	var aim_x := 0.0
	var aim_z := 1.0
	if mx != 0 or mz != 0:
		var l := sqrt(float(mx * mx + mz * mz))
		aim_x = float(mx) / l
		aim_z = float(mz) / l
	return {"move_x": mx, "move_z": mz, "buttons": int(pi.buttons),
			"aim_x": aim_x, "aim_z": aim_z}


func _billboard_pass(dt: float) -> void:
	# outside the tree, global transforms error: the rig is a direct child of this node and
	# this node is its own world, so the local position carries the same information
	var cam_pos: Vector3 = rig.global_position if (rig != null and rig.is_inside_tree()) \
			else (rig.position if rig != null else Vector3.ZERO)
	while boards.size() < rt.enemies.size():
		boards.append(_make_board(rt.enemies[boards.size()]))
	for i in rt.enemies.size():
		var e: Dictionary = rt.enemies[i]
		var bd = boards[i]
		if bd == null:
			continue
		bd.position = Vector3(float(e["x"]), float(e["y"]), float(e["z"]))
		bd.set_animation(str(e.get("anim_state", "")))
		bd.advance_animation(dt)
		bd.face_camera(cam_pos)


func _make_board(e: Dictionary):
	var folder := "res://content/enemies/%s" % str(e["id"])
	var doc: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(folder + "/sprites.json"))
	if not (doc is Dictionary):
		push_warning("world: sprites.json unreadable for %s; billboard skipped" % str(e["id"]))
		return null
	var bd = BillboardScript.new()
	bd.setup_from_sheet(doc, folder)
	add_child(bd)
	return bd


## HUD snapshot. gifts are 0/0 until a LevelState owner ticks sim/gifts.gd (D-APPFLOW-5);
## the roster is the resolved vote plan (static for the level).
func _sync_hud() -> void:
	if hud == null or ctl == null or rt == null:
		return
	hud.sync({
		"gifts_collected": 0,
		"gifts_total": 0,
		"purse_centi": 0,
		"chain": 1.0,
		"charges": int(ctl.charges),
		"charge_cap": int(ctl.charge_cap),
		"last_light": str(ctl.hud_last_light()),
		"kit": str(ctl.kit),
		"roster": _roster,
	})