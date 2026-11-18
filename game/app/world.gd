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
#   - the LevelState owner decision landed (APP-LOOP): step() now builds and owns
#     the sim LevelState (gifts / mines / beacon) exactly the way tools/bot_run.gd
#     ticks it - controller -> player-row sync -> lv.tick++ -> GiftsScript.tick ->
#     MinesScript.tick -> beacon try_enter -> enemy_runtime. The economy (chain /
#     purse) is ticked on the same pass: beacon open begins the gold phase,
#     tick_gold(dt) advances the window, gold gift pickups pay collect_gold_gift,
#     chain_reset events break the chain, beacon entry pays the stipend. A signal
#     (level_completed) reports the completion so app.gd can advance.
#   - curse sim knobs (the time-of-day curse family and friends) are NOT applied to the
#     controller or the runtime; only class + enemy votes ride the resolved lobbies.
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
#   func is_complete() -> bool                       # true once the beacon was entered (APP-LOOP)
#
# signal level_completed()  - emitted exactly once, at the end of the tick in which
# the beacon is entered (the sim's level_complete event fires on the same tick).
# (The APP-LOOP tick order lives in step()'s own doc comment below.)
#
# signal run_over(info)  - emitted exactly once, at the end of the tick in which the
# controller reports dead: a third void fall, an enemy contact or a tripmine - every
# kill path lands on ctl.dead. DESIGN.md section 3: "Death ends the run." info is
# sim/death.gd's screen_data() row (code / killer / level / purse) plus the charges
# held at death, i.e. the keys view/hud/run_over.gd reads. A dead run never ticks
# again: step() returns before the sim once the latch is set, so the app owns the
# frame from there on (death black-out -> run-over screen).

const VoidGenScript := preload("res://terrain/voidgen.gd")
const CollisionScript := preload("res://sim/collision.gd")
const MesherScript := preload("res://view/level_mesher.gd")
const ControllerScript := preload("res://sim/controller.gd")
const CameraRigScript := preload("res://app/camera_rig.gd")
const EnemyRuntimeScript := preload("res://sim/enemy_runtime.gd")
const BillboardScript := preload("res://view/billboard.gd")
const FogEnvScript := preload("res://view/fog_env.gd")
const HudScript := preload("res://view/hud/hud.gd")
# The core-loop views (DESIGN.md section 3): the black/gold gifts, the tripmine tell and
# the beacon with its progress ring + light column. Nothing under app/ drew them.
const GiftsViewScript := preload("res://view/gifts_view.gd")
const TripmineViewScript := preload("res://view/tripmine_view.gd")
const BeaconViewScript := preload("res://view/beacon_view.gd")
# The glitched-floor decal layer. The body is one of the `boards` billboards; the decals are
# a separate world-origin node in floor-only mode, because the sim's glitched entries carry
# absolute tile coordinates and the body node moves.
const ToucherViewScript := preload("res://view/toucher_view.gd")
const ContentApiScript := preload("res://core/content_api.gd")
const IntermissionScript := preload("res://sim/intermission.gd")
const VoidRngScript := preload("res://terrain/void_rng.gd")
const InputCaptureScript := preload("res://app/input_capture.gd")
# The T-015 player figure. Without it the third-person rig frames empty space and the game
# reads first-person: the camera sits 7 u behind a body that was never drawn.
const PLAYER_MODEL := "res://assets/models/player_figure.glb"
# APP-LOOP: the sim LevelState (gifts / mines / beacon), the gift + mine ticks and the
# gold-phase economy - the same pieces tools/bot_run.gd ticks on the reference surface.
const LevelStateScript := preload("res://sim/level_state.gd")
const GiftsScript := preload("res://sim/gifts.gd")
const MinesScript := preload("res://sim/mines.gd")
const EconomyScript := preload("res://sim/economy.gd")
const DeathScript := preload("res://sim/death.gd")

signal level_completed()
signal run_over(info: Dictionary)

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
# The core-loop views: built in build(), driven from step(), freed by teardown().
var gifts_view: Node3D = null
var tripmine_view: Node3D = null
var beacon_view: Node3D = null
var toucher_floor: Node3D = null   # the glitched-floor decals (floor-only mode)
var boards: Array = []          # EnemyRuntime enemies index -> billboard node (or null)
var lstate: RefCounted = null   # the sim LevelState (gifts / mines / beacon); bot_run.gd's lv
var player_model: Node3D = null # the T-015 player figure, feet on the controller's position
var _player_yaw := 0.0          # last facing yaw; kept while standing still
var _player_light: OmniLight3D = null   # palette.json player_fill_light, rides the figure

var _economy: RefCounted = null   # the gold-phase economy (purse / chain); no upgrade stats yet
var _gold_began := false          # beacon open -> begin_gold_phase + rt.on_beacon_open fire once
var _completed_emitted := false   # level_completed fires once
var _run_over_emitted := false    # run_over fires once; a dead run stops ticking

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
	# The spawn is the level's own spawn tile (the collision default, spawns[0] - the same
	# assembly feel_probe.gd and perf_probe.gd use). The bot_run override {"dais": beacon}
	# plants the spawn inside the beacon monument, which encloses the 1.8 u figure and
	# buries the third-person view's subject.
	w = CollisionScript.make_world(lv["tiles"], lv["props"], lv["pads"])
	# The sim LevelState: one level's slice of the state tree (players + gifts + mines +
	# beacon). Built from the same Level dict; the run seed feeds the Defuse Kit roll.
	lstate = LevelStateScript.build(lv, level, 1, seed_value)

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

	# The gold-phase economy: base stats (the app has no upgrade ledger yet, so no
	# chain/stipend modifiers), tuned by data/economy.json through the content api.
	_economy = EconomyScript.create({}, _api)

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
		var cfg := _cfg_for(entry, eid, level, n, beh)
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

	# The void's own glow: one soft overhead light, shadows OFF (palette.json ambient's
	# "no sun, no directional shadows" still holds - this casts nothing). Without it the
	# only light was the near-black ambient plus the player's 18 u fill, so everything past
	# the player's feet rendered black and the slab detail could not be seen at all.
	var key := DirectionalLight3D.new()
	key.name = "VoidGlow"
	key.light_color = Color(str(FogEnvScript.load_palette().get("roles", {})
			.get("void_glow", {}).get("hex", "#8FE8E0")))
	key.light_energy = float(FogEnvScript.load_palette().get("roles", {})
			.get("void_glow", {}).get("energy", 0.55))
	key.shadow_enabled = false
	key.rotation_degrees = Vector3(-62.0, 34.0, 0.0)
	add_child(key)

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

	# The player figure (T-015): feet on the controller's position, yawed to the motion.
	# Without it the third-person rig frames empty space and the game reads first-person.
	var ps: PackedScene = load(PLAYER_MODEL)
	if ps != null:
		player_model = ps.instantiate()
		player_model.position = Vector3(float(ctl.x), float(ctl.y), float(ctl.z))
		player_model.rotation.y = _player_yaw
		add_child(player_model)
	# The player fill light (palette.json roles.player_fill_light: omni #BFFFF8, range 18,
	# energy 1.2). Nothing ever created it, so ALBEDO rendered near-black and only the light
	# squares' emission showed - the reason the slabs read as untextured. Parented to the
	# figure so it follows the player; held 2.0 u behind the shoulder, because an omni parked
	# at the body's centre lights almost nothing (the falloff kills the close-range term).
	_player_light = OmniLight3D.new()
	var fill: Dictionary = FogEnvScript.load_palette().get("roles", {}).get("player_fill_light", {})
	_player_light.light_color = Color(str(fill.get("hex", "#BFFFF8")))
	_player_light.omni_range = float(fill.get("range", 18.0))
	_player_light.light_energy = float(fill.get("energy", 1.2))
	_player_light.position = Vector3(0.0, 1.3, 2.0)
	if player_model != null:
		player_model.add_child(_player_light)
	else:
		_player_light.position = Vector3(float(ctl.x), float(ctl.y) + 1.3, float(ctl.z) + 2.0)
		add_child(_player_light)

	# HUD (CanvasLayer: a Control child of a Node3D never reaches the canvas).
	_hud_layer = CanvasLayer.new()
	add_child(_hud_layer)
	hud = HudScript.new()
	_hud_layer.add_child(hud)
	_sync_hud()

	# The core-loop views, placed from the LevelState step() ticks: a black + a gold
	# model per REAL gift slot (the gold ones hidden until the flip), one mine per mine
	# slot, the beacon on its dais tile. Without them the run is played blind.
	gifts_view = GiftsViewScript.new()
	add_child(gifts_view)
	gifts_view.setup(lv, lstate.gifts)
	tripmine_view = TripmineViewScript.new()
	add_child(tripmine_view)
	tripmine_view.setup(lv, lstate.mines)
	beacon_view = BeaconViewScript.new()
	add_child(beacon_view)
	beacon_view.setup(lv)

	# The glitched floor, at the world origin: the sim's glitched entries carry
	# absolute tile coordinates, so this node must not move. Floor-only mode builds just the
	# decal layer - the body is already one of the boards above.
	toucher_floor = ToucherViewScript.new()
	add_child(toucher_floor)
	toucher_floor.setup(ToucherViewScript.SHEET_REL, ToucherViewScript.FOLDER_REL, true)

	_level_number = level
	return true


## One sim tick plus the view pass. dt is the fixed 60 Hz step; headless callers drive it
## directly. The sim half mirrors tools/bot_run.gd's per-tick order exactly:
##   controller -> player-row sync -> lv.tick++ -> gifts -> mines -> beacon ->
##   (beacon open: rt.on_beacon_open + the gold phase) -> enemy runtime.
## Mines carry defuse stacks [0] (the app has no Defuse Kit ledger yet, exactly the bot's
## hardcoded stack); the last-light/respawn path rides ctl.step itself. The completion
## signal fires at the end of the tick that entered the beacon; the death signal fires at
## the end of the tick the player died on, and every later call is a no-op.
func step(dt: float) -> void:
	if ctl == null or rt == null or lstate == null:
		return
	if _run_over_emitted:
		return   # the run is over: a dead run never ticks again (DESIGN.md section 3)
	var a_in: Dictionary = _capture_input()
	var ev: Array = ctl.step(dt, a_in, w)
	# The LevelState's player row mirrors the controller (gifts/mines read lv.players).
	var p0: Dictionary = lstate.players[0]
	p0["x"] = ctl.x
	p0["y"] = ctl.y
	p0["z"] = ctl.z
	p0["vx"] = ctl.vx
	p0["vy"] = ctl.vy
	p0["vz"] = ctl.vz
	p0["grounded"] = ctl.grounded
	p0["prev_buttons"] = int(a_in.get("buttons", 0))
	lstate.tick += 1
	GiftsScript.tick(lstate, 0, ev)
	var minev: Array = []
	MinesScript.tick(lstate, [ctl], w, [0], lstate.tick, minev)
	for e in minev:
		ev.append(e)
	lstate.beacon.try_enter(ctl, lstate.tick, 0, ev)
	if lstate.beacon.is_open() and not _gold_began:
		_gold_began = true
		rt.on_beacon_open()
		if _economy != null:
			_economy.begin_gold_phase()
	if _economy != null and bool(_economy.gold_phase):
		_economy.tick_gold(dt)
	for e in rt.step(dt):
		ev.append(e)
	_economy_pass(ev)
	if rig != null:
		rig.update_rig(Vector3(float(ctl.x), float(ctl.y), float(ctl.z)), dt)
	_player_pass()
	_billboard_pass(dt)
	_view_pass()
	_sync_hud()
	# Death ends the run (DESIGN.md section 3). The row is sim/death.gd's own screen_data()
	# plus the charges held at death - the controller's death event carries the same pair.
	# Death is checked first: a dead player cannot enter the beacon (try_enter refuses a
	# dead controller), so the two signals never both fire on one tick.
	if not _run_over_emitted and bool(ctl.dead):
		_run_over_emitted = true
		var purse := -1
		if _economy != null:
			purse = int(_economy.purse_centi)   # centi, the same integer the HUD shows
		var info: Dictionary = DeathScript.screen_data(ctl, _level_number, purse)
		info["charges"] = int(ctl.charges)
		run_over.emit(info)
		return
	if not _completed_emitted and lstate.beacon != null and bool(lstate.beacon.completed):
		_completed_emitted = true
		level_completed.emit()


## Read sim -> economy mapping over this tick's event list (both event shapes: sim events
## key on "type", controller/mine/enemy raw dicts on "e"). Data-driven: no upgrade or
## curse id is named here. The chain_reset -> break reason map covers the two mine-ladder
## reasons (economy's whitelist calls that one reason "defused_or_shielded_tripmine");
## whatever else arrives is handed to break_chain verbatim, which refuses strings that are
## not on the canon whitelist (thicc ben's eject rides through unchanged).
func _economy_pass(ev: Array) -> void:
	if _economy == null:
		return
	for e in ev:
		var kind := str(e.get("e", e.get("type", "")))
		if kind == "gift_collected":
			if str(e.get("phase", "")) == "gold":
				_economy.collect_gold_gift()
		elif kind == "chain_reset":
			var why := str(e.get("why", ""))
			if why == "defused_mine" or why == "shielded_mine":
				why = "defused_or_shielded_tripmine"
			_economy.break_chain(why)
		elif kind == "beacon_enter":
			_economy.enter_beacon(_level_number)


## True once the beacon has been entered (the level is complete). Convenience for
## callers that poll; the level_completed signal is the push channel.
func is_complete() -> bool:
	return lstate != null and lstate.beacon != null and bool(lstate.beacon.completed)


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
	gifts_view = null
	tripmine_view = null
	beacon_view = null
	toucher_floor = null
	player_model = null
	_player_light = null
	_player_yaw = 0.0
	lstate = null
	_economy = null
	_gold_began = false
	_completed_emitted = false
	_run_over_emitted = false
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


# Per-id behavior construction, content-derived: the enemy module's factory shape is
# probed in a fixed order (no content id is named here):
#   1. a module-level behavior() / new_behavior() static factory;
#   2. an inner class whose name ends in "Behavior" (each module declares exactly one);
#   3. the module script itself as the behavior.
func _behavior_for(id: String):
	var K = load("res://content/enemies/%s/enemy.gd" % id)
	if K == null:
		return null
	if K.has_method("behavior"):
		return K.behavior()
	if K.has_method("new_behavior"):
		return K.new_behavior()
	var inner := _behavior_inner(K)
	if inner != null:
		return inner.new()
	return K.new()   # the file-as-behavior module


## The module's inner behavior class: a script constant whose value is a Script whose
## name ends in "Behavior". Deterministic (lowest name) when several qualify; null when none.
static func _behavior_inner(K: Script) -> GDScript:
	var cmap: Dictionary = K.get_script_constant_map()
	var names: Array[String] = []
	for cname in cmap:
		var v: Variant = cmap[cname]
		if v is GDScript and str(cname).to_lower().ends_with("behavior"):
			names.append(str(cname))
	names.sort()
	if names.is_empty():
		return null
	return cmap[names[0]] as GDScript


## The runtime cfg for one planned enemy: the enemy.json stats block with the top-level
## contact_kill / preferred_kind / arbiter keys the runtime reads, stamped with name /
## votes / level_number (bot_run.gd's shape). A behavior module that wants its raw stats
## nested under a cfg key declares that key as a `cfg_stats` constant on its script; the
## nesting follows the declaration, never an id match.
func _cfg_for(entry: Dictionary, id: String, level: int, votes: int, beh = null) -> Dictionary:
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
	if beh != null:
		var bscript: Script = beh.get_script()
		if bscript != null:
			var cmap: Dictionary = bscript.get_script_constant_map()
			var key := str(cmap.get("cfg_stats", ""))
			if key != "":
				stats[key] = (entry.get("stats", {}) as Dictionary).duplicate(true)
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


## The player figure pass: stand at the controller's feet, yawed to the horizontal
## velocity (the last yaw is kept while standing still). The figure's forward is Godot's
## -Z, the glTF Y-up conversion of the Blender +Y visor side.
func _player_pass() -> void:
	if player_model == null:
		return
	player_model.position = Vector3(float(ctl.x), float(ctl.y), float(ctl.z))
	var hx := float(ctl.vx)
	var hz := float(ctl.vz)
	if hx * hx + hz * hz > 0.01:
		_player_yaw = atan2(-hx, -hz)
	player_model.rotation.y = _player_yaw


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


## The core-loop view pass: the three views read the same LevelState step() ticks, so
## what the player sees is what the sim holds - the black gifts go out one by one (gold
## models at the same slots once the phase flips), a consumed mine leaves, and the beacon
## column ramps from the tick it opened on.
func _view_pass() -> void:
	if lstate == null:
		return
	if gifts_view != null:
		gifts_view.sync(lstate.gifts)
	if tripmine_view != null and lstate.mines != null:
		# the view owns no clock: sim seconds in, one turn per TURN_PERIOD (4 s)
		tripmine_view.set_time(float(lstate.tick) * DT)
		tripmine_view.sync(_eye_pos())
	if beacon_view != null and lstate.beacon != null:
		beacon_view.sync_from(lstate.beacon, lstate.gifts, lstate.tick)
	if toucher_floor != null and rt != null:
		toucher_floor.sync_floor_rows(rt.enemies)


## The eye the distance-driven view ramps measure from: the rig IS the camera holder, so
## its position is the camera. Local, not global - the mine roots the tripmine view syncs
## are positioned in this node's own space, and the distance must not mix the two spaces.
func _eye_pos() -> Vector3:
	if rig == null:
		return Vector3.ZERO
	return rig.position


## HUD snapshot. gifts / purse / chain come from the LevelState and the economy this
## node owns (gifts_collected = total_real - remaining(), the sim's own definition);
## the roster is the resolved vote plan (static for the level).
func _sync_hud() -> void:
	if hud == null or ctl == null or rt == null:
		return
	var total := 0
	var collected := 0
	if lstate != null and lstate.gifts != null:
		var g: RefCounted = lstate.gifts
		total = int(g.total_real)
		collected = total - int(g.remaining())
	var purse := 0
	var chain := 1.0
	if _economy != null:
		purse = int(_economy.purse_centi)
		chain = float(_economy.chain_display())
	hud.sync({
		"gifts_collected": collected,
		"gifts_total": total,
		"purse_centi": purse,
		"chain": chain,
		"charges": int(ctl.charges),
		"charge_cap": int(ctl.charge_cap),
		"last_light": str(ctl.hud_last_light()),
		"kit": str(ctl.kit),
		"roster": _roster,
	})