extends RefCounted
#
# test_app_lobby.gd (J7): the beacon leads to the Antechamber, and the Antechamber leads
# to the next level.
#
# Before J7 the beacon tore the world down and dropped the player on the main menu
# (D-APP-LOOP-4). This test pins the replacement flow end to end, through the real app
# node and the real lobby scene:
#
#   leg A (the flow): MENU -> WORLD(level 1) -> walk the level to its beacon -> the app
#     enters STATE_LOBBY with the level just completed and the run's purse -> the hall
#     shows the E bay's description panel only while the player stands at it -> hold F ->
#     the pick lands in the sim's Intermission state (votes_sum 1) and the bay flares ->
#     the gate opens -> walk into the gate -> the app builds WORLD(level 2) carrying the
#     lobby's votes, and the level's enemy roster is exactly those votes.
#   leg B (gating): a C-bay lobby (level_completed 2) starts with the gate SEALED and
#     names the unresolved bay; the F-pick on a curse altar opens it.
#   leg C (determinism): build(seed, level) and build(seed, level, run_ledger()) produce
#     the same enemy roster, so the carried-ledger path is the replay's own answer.
#
# Headless, outside the scene tree, like test_app_flow.gd: the app node is not added to
# the SceneTree (under `--headless --script` there is no usable one), so the test calls
# _ready() itself and drives the lobby's tick() directly.

const AppScript := preload("res://app/app.gd")
const WorldScript := preload("res://app/world.gd")
const LobbySceneScript := preload("res://view/lobby/lobby_scene.gd")
const IntermissionScript := preload("res://sim/intermission.gd")
const ContentApiScript := preload("res://core/content_api.gd")
const VoidRngScript := preload("res://terrain/void_rng.gd")

const SEED := 1
const DT := 1.0 / 60.0
const HOLD_TICKS := 30   # 0.50 s of F: past the 0.35 s hold-to-confirm


func run() -> Array[String]:
	var f: Array[String] = []
	_leg_flow(f)
	_leg_gating(f)
	_leg_determinism(f)
	return f


# ---- leg A: beacon -> lobby -> pick -> gate -> next level ---------------------------------

func _leg_flow(f: Array[String]) -> void:
	var app = AppScript.new()
	# I4: a test must never ratchet the player's real user://records.json. Point the store at a
	# scratch file before _ready loads it.
	app.records_path = "user://test_app_lobby_scratch.json"
	app.start_run(SEED)
	app._ready()
	app._on_play_requested()
	var loading = app._loading
	var guard := 0
	while app.state() == "LOADING" and loading != null and guard < 400:
		loading.advance(0.25)
		guard += 1
	if app.state() != "WORLD":
		f.append("flow: the app is in %s after loading, want WORLD" % app.state())
		app.free()
		return
	var world = app._world
	if world == null:
		f.append("flow: no world after loading")
		app.free()
		return

	# Walk the level to its beacon: every real black gift, then the beacon tile.
	var g = world.lstate.gifts
	for i in g.slots.size():
		if not g.is_real(i):
			continue
		var pos: Vector3 = g.slot_pos(i)
		world.ctl.x = pos.x
		world.ctl.y = pos.y - 1.0
		world.ctl.z = pos.z
		world.ctl.vy = 0.0
		world.step(DT)
	var purse_before := int(world._economy.purse_gold())
	var bp: Array = world.lv["beacon"]
	world.ctl.x = float(int(bp[0])) + 0.5
	world.ctl.y = float(int(bp[2])) * 0.5
	world.ctl.z = float(int(bp[1])) + 0.5
	world.ctl.vy = 0.0
	world.step(DT)   # the beacon entry: level_completed -> the app enters the lobby

	if app.state() != "LOBBY":
		f.append("flow: the app is in %s after the beacon, want LOBBY" % app.state())
		app.free()
		return
	if app._world != null:
		f.append("flow: the world was not torn down on completion")
	if app._lobby == null:
		f.append("flow: no lobby was built on completion")
		app.free()
		return
	var scene = app._lobby
	if int(scene.level_completed) != 1:
		f.append("flow: the lobby is for level_completed %d, want 1" % int(scene.level_completed))
	if scene.lobby == null:
		f.append("flow: the lobby has no Intermission state")
		app.free()
		return
	if int(scene.lobby.purse) < purse_before:
		f.append("flow: the lobby purse %d is below the level's %d"
				% [int(scene.lobby.purse), purse_before])
	if int(scene.lobby.purse) <= 0:
		f.append("flow: the lobby purse is %d, want the beacon stipend" % int(scene.lobby.purse))
	if scene.hall == null or scene.player == null:
		f.append("flow: the lobby has no hall or no player")
		app.free()
		return

	# The E bay is mandatory at level_completed 1; the U bay is optional.
	if scene.gate_open:
		f.append("flow: the gate is open before any pick")
	if not (scene.unresolved as Array).has("E"):
		f.append("flow: unresolved bays are %s, want E" % str(scene.unresolved))

	# Stand at the E bay's first altar and look at it: the panel appears, and only that one.
	var target: Dictionary = {}
	for a in scene.hall._altars:
		if str(a["kind"]) == "offer" and str(a["bay_kind"]) == "E":
			target = a
			break
	if target.is_empty():
		f.append("flow: the lobby has no E-bay altar")
		app.free()
		return
	_stand_at(scene, target)
	var res: Dictionary = scene.tick(DT, 0, 0, false)
	if not str(res["prompt"]).begins_with("[F] Choose"):
		f.append("flow: prompt is '%s', want '[F] Choose - <name>'" % str(res["prompt"]))
	if str(res["prompt"]).contains("TBD"):
		f.append("flow: the prompt names no altar: '%s'" % str(res["prompt"]))
	var panel: Label3D = target.get("panel")
	if panel == null or not panel.visible:
		f.append("flow: the faced altar's description panel is not visible")
	if str(panel.text if panel != null else "").strip_edges() == "":
		f.append("flow: the faced altar's description panel is empty")
	var others_shown := 0
	for a in scene.hall._altars:
		var p: Label3D = a.get("panel")
		if p != null and p.visible and int(a["index"]) != int(target["index"]):
			others_shown += 1
	if others_shown != 0:
		f.append("flow: %d other panels are visible at once, want 0" % others_shown)

	# Walk away: the panel hides again.
	scene.player.z = 8.0
	scene.tick(DT, 0, 0, false)
	if panel != null and panel.visible:
		f.append("flow: the panel stayed visible after walking away")

	# Hold F at the altar: the pick lands in the sim and the bay flares.
	_stand_at(scene, target)
	var votes_before: int = int(scene.lobby.votes_sum())
	var fired: Dictionary = _hold(scene, HOLD_TICKS)
	if fired.is_empty():
		f.append("flow: holding F for %.2f s never confirmed a pick" % (HOLD_TICKS * DT))
		app.free()
		return
	if int(scene.lobby.votes_sum()) != votes_before + 1:
		f.append("flow: votes after one E pick = %d, want %d"
				% [int(scene.lobby.votes_sum()), votes_before + 1])
	if float(scene.hall._flash_t) <= 0.0:
		f.append("flow: the picked bay did not flare")
	var lit := 0
	for a in scene.hall._altars:
		var glow: OmniLight3D = a.get("glow")
		if glow != null and glow.light_energy > 0.0:
			lit += 1
	if lit == 0:
		f.append("flow: no altar glow lit on the pick")
	scene.tick(DT, 0, 0, false)
	if not scene.gate_open:
		f.append("flow: the gate is still sealed after the only mandatory bay resolved")
	if not (scene.unresolved as Array).is_empty():
		f.append("flow: unresolved bays are %s after the pick, want []" % str(scene.unresolved))

	# Walk into the open gate: the app builds the next level with the lobby's votes.
	var votes: Dictionary = (scene.lobby.votes as Dictionary).duplicate()
	var votes_sum: int = int(scene.lobby.votes_sum())
	scene.player.x = 0.0
	scene.player.z = -8.5
	scene.tick(DT, 0, 0, false)
	if app.state() != "WORLD":
		f.append("flow: the app is in %s after the gate, want WORLD" % app.state())
		app.free()
		return
	if app._lobby != null:
		f.append("flow: the lobby was not released on exit")
	if app._world == null:
		f.append("flow: no world was built after the gate")
		app.free()
		return
	if int(app._world.level_number()) != 2:
		f.append("flow: the next level is %d, want 2" % int(app._world.level_number()))
	var roster_sum := 0
	var roster_ids := {}
	for row in app._world._roster:
		roster_sum += int(row["count"])
		roster_ids[str(row["id"])] = int(row["count"])
	if roster_sum != votes_sum:
		f.append("flow: the level's roster holds %d enemies, the lobby voted %d"
				% [roster_sum, votes_sum])
	for id in votes.keys():
		if int(roster_ids.get(str(id), 0)) != int(votes[id]):
			f.append("flow: enemy %s is in play x%d, the lobby voted x%d"
					% [str(id), int(roster_ids.get(str(id), 0)), int(votes[id])])
	app.free()


# ---- leg B: the gate is sealed until every mandatory bay resolves -------------------------

func _leg_gating(f: Array[String]) -> void:
	var scene = LobbySceneScript.new()
	if not scene.build(SEED, 2, {"purse": 500}):
		f.append("gating: the C-bay lobby failed to build")
		scene.free()
		return
	if scene.gate_open:
		f.append("gating: the gate is open with the C bay unresolved")
	if not (scene.unresolved as Array).has("C"):
		f.append("gating: unresolved bays are %s, want C" % str(scene.unresolved))
	var target: Dictionary = {}
	for a in scene.hall._altars:
		if str(a["kind"]) == "offer" and str(a["bay_kind"]) == "C":
			target = a
			break
	if target.is_empty():
		f.append("gating: the C bay has no curse altar")
		scene.free()
		return
	_stand_at(scene, target)
	if _hold(scene, HOLD_TICKS).is_empty():
		f.append("gating: holding F never confirmed the curse pick")
		scene.free()
		return
	scene.tick(DT, 0, 0, false)
	if not scene.gate_open:
		f.append("gating: the gate is still sealed after the curse pick")
	if not (scene.unresolved as Array).is_empty():
		f.append("gating: unresolved bays are %s after the pick, want []" % str(scene.unresolved))
	if (scene.lobby.curses_held as Dictionary).is_empty():
		f.append("gating: the curse pick did not reach the sim's curse ledger")
	scene.free()


# ---- leg C: the carried ledger is the replay's own answer --------------------------------

func _leg_determinism(f: Array[String]) -> void:
	var a = WorldScript.new()
	if not a.build(SEED, 2):
		f.append("determinism: the replay world failed to build")
		a.free()
		return
	var ledger: Dictionary = a.run_ledger()
	var roster_a := _roster_of(a)
	a.teardown()
	a.free()
	if not ledger.has("votes"):
		f.append("determinism: run_ledger() carries no votes")
		return
	var b = WorldScript.new()
	if not b.build(SEED, 2, ledger):
		f.append("determinism: the carried-ledger world failed to build")
		b.free()
		return
	var roster_b := _roster_of(b)
	b.teardown()
	b.free()
	if roster_a != roster_b:
		f.append("determinism: the replay roster %s differs from the carried-ledger roster %s"
				% [str(roster_a), str(roster_b)])
	# The lobby the player walks into is the lobby the replay resolves: same seed stream.
	var api: RefCounted = ContentApiScript.load()
	if api == null or not api.is_ok():
		f.append("determinism: content api boot failed")
		return
	var replay: RefCounted = IntermissionScript.create(api, 1, 0,
			VoidRngScript.mix(SEED, 5000 + 1))
	var scene = LobbySceneScript.new()
	if not scene.build(SEED, 1, {}):
		f.append("determinism: the lobby failed to build")
		scene.free()
		return
	var want := _bay_ids(replay)
	var got := _bay_ids(scene.lobby)
	scene.free()
	if want != got:
		f.append("determinism: the lobby drew %s, the replay draws %s" % [str(got), str(want)])


# ---- helpers -----------------------------------------------------------------------------

## Stands the player 2 u south of p_altar, facing it (the hall's own prompt geometry).
func _stand_at(scene, p_altar: Dictionary) -> void:
	var root: Node3D = p_altar["root"]
	scene.player.x = root.position.x
	scene.player.z = root.position.z + 2.0
	scene.player.vx = 0.0
	scene.player.vz = 0.0
	scene.player.rig.yaw_deg = 0.0


## Holds F for p_ticks; returns the tick result that carried the Select ({} if none).
func _hold(scene, p_ticks: int) -> Dictionary:
	for _i in p_ticks:
		var res: Dictionary = scene.tick(DT, 0, 0, true)
		if int(res["select"]) != -1:
			return res
	return {}


## {enemy_id: count} for a built world's planned roster.
func _roster_of(world) -> Dictionary:
	var out := {}
	for row in world._roster:
		out[str(row["id"])] = int(row["count"])
	return out


## The altar ids each bay drew, in bay order - the lobby's visible draw.
func _bay_ids(p_lobby: RefCounted) -> Array:
	var out: Array = []
	for bay in p_lobby.bays:
		var ids: Array = []
		for a in (bay.get("altars", []) as Array):
			ids.append(str(a.get("id", "")))
		out.append("%s:%s" % [str(bay["kind"]), ",".join(ids)])
	return out
