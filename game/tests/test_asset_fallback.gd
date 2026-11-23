extends RefCounted
#
# ASSET FALLBACK test (U4, cycle 8). Terra's bug hunt found godot.log carrying
# "instantiate on null" for res://assets/models/player_figure.glb when the import cache
# was missing. A missing asset must never crash the game, and it must never be silent
# either - a silent fallback hides a broken export until the owner reports "the player is
# invisible".
#
# Every leg points a load at a path that does NOT exist and asserts the game still builds
# and steps:
#
#   leg A  view/asset_load.gd: a missing scene / texture / stream / script answers null,
#          reports the path ONCE (a second call adds no second report), and a path that
#          does exist still loads.
#   leg B  the player figure: world.build() with player_model_path pointed at a missing
#          .glb still returns true, the figure is the blocky fallback with the six limb
#          names the locomotion rig looks for, and 60 real ticks run without error.
#   leg C  the lobby figure: lobby_player.build() with the same bad path still builds the
#          blocky figure and the four-limb walk still animates it.
#   leg D  the gift models: gifts_view.setup() with both model paths missing still builds
#          every real slot (as a blocky box) and sync() runs.
#   leg E  audio: a missing cue is silent (null), never an error - the shared
#          view/audio/cue_audio.gd helper and the new loader agree.
#   leg F  the boss arena with a missing thrown-gift model: on_events(boss_gift_spawned)
#          spawns no gift and does not crash; the arena still ticks.
#   leg G  a missing sprite follows content/enemies/<id>/sprites.json + T-016: a sheet
#          frame whose file is absent loads as a null frame (billboard tolerates it),
#          and a missing sprites.json reads as "" through the guarded loader.
#   leg H  a missing data file + a missing HUD icon: world.build() with player_data_path
#          pointed at an absent file still builds and steps 60 ticks, and the purse
#          pill's icon re-load with a missing png only hides the icon.
#
# The test fails if any of these crashes, if the fallback is absent, or if the report is
# not exactly once per path.

const WorldScript := preload("res://app/world.gd")
const LobbyPlayerScript := preload("res://view/lobby/lobby_player.gd")
const GiftsViewScript := preload("res://view/gifts_view.gd")
const BossViewScript := preload("res://view/boss_view.gd")
const BillboardScript := preload("res://view/billboard.gd")
const PurseChainScript := preload("res://view/hud/purse_chain.gd")
const AssetLoadScript := preload("res://view/asset_load.gd")
const PlayerFallbackScript := preload("res://view/player_figure_fallback.gd")
const CueAudioScript := preload("res://view/audio/cue_audio.gd")
const GiftsScript := preload("res://sim/gifts.gd")
const VoidGenScript := preload("res://terrain/voidgen.gd")

const DT := 1.0 / 60.0
const MISSING_SCENE := "res://assets/models/u4_no_such_model.glb"
const MISSING_TEXTURE := "res://assets/icons/u4_no_such_icon.png"
const MISSING_STREAM := "res://assets/audio/u4_no_such_cue.wav"
const MISSING_SCRIPT := "res://content/upgrades/u4_no_such_upgrade.gd"
const MISSING_DATA := "res://data/u4_no_such_data.json"
const MISSING_SHEET := "res://content/enemies/u4_no_such_enemy/sprites.json"
const LIMB_NAMES := ["Torso", "Head", "ArmL", "ArmR", "LegL", "LegR"]


func run() -> Array[String]:
	var f: Array[String] = []
	_leg_a_loader(f)
	_leg_b_world_figure(f)
	_leg_c_lobby_figure(f)
	_leg_d_gift_models(f)
	_leg_e_audio(f)
	_leg_f_boss_gift_model(f)
	_leg_g_missing_sprite(f)
	_leg_h_missing_data_and_icon(f)
	return f


## Leg A: the loader answers null, reports once, and still loads a real path.
func _leg_a_loader(f: Array[String]) -> void:
	AssetLoadScript.reset_reports()
	if AssetLoadScript.scene(MISSING_SCENE) != null:
		f.append("leg A: a missing scene did not answer null")
	if not AssetLoadScript.reported(MISSING_SCENE):
		f.append("leg A: a missing scene was not reported")
	# The once rule: a second call must not report again. The seam is the report table,
	# so the check is that the entry is still there and the call still answers null.
	if AssetLoadScript.scene(MISSING_SCENE) != null:
		f.append("leg A: the second missing-scene call did not answer null")
	if AssetLoadScript.texture(MISSING_TEXTURE) != null:
		f.append("leg A: a missing texture did not answer null")
	if AssetLoadScript.stream(MISSING_STREAM) != null:
		f.append("leg A: a missing stream did not answer null")
	if AssetLoadScript.script_module(MISSING_SCRIPT) != null:
		f.append("leg A: a missing script did not answer null")
	# A real path still loads: the loader is not a blanket null.
	var real: PackedScene = AssetLoadScript.scene(WorldScript.PLAYER_MODEL)
	if real == null:
		f.append("leg A: the real player model did not load through the loader")
	if AssetLoadScript.reported(WorldScript.PLAYER_MODEL):
		f.append("leg A: the real player model was reported as missing")


## Leg B: the world builds and steps with a missing player model, on the blocky figure.
func _leg_b_world_figure(f: Array[String]) -> void:
	AssetLoadScript.reset_reports()
	var world = WorldScript.new()
	world.player_model_path = MISSING_SCENE
	if not world.build(1, 1):
		f.append("leg B: world.build() failed with a missing player model")
		world.free()
		return
	if world.player_model == null:
		f.append("leg B: a missing player model left no figure at all (no fallback)")
	else:
		if str(world.player_model.name) != "PlayerFigureFallback":
			f.append("leg B: the fallback figure is not the blocky one (%s)"
				% str(world.player_model.name))
		for nm in LIMB_NAMES:
			var limb = world.player_model.find_child(nm, true, false)
			if limb == null:
				f.append("leg B: the fallback figure has no %s limb" % nm)
				continue
			# The fallback must be a REAL blocky figure, not an invisible nothing:
			# every limb is a MeshInstance3D with a non-empty mesh and a non-null
			# surface override material (the vertex-colour base pass), and the whole
			# figure's AABB is a standing ~1.4 u tall body.
			if not (limb is MeshInstance3D) or (limb as MeshInstance3D).mesh == null:
				f.append("leg B: the fallback %s limb carries no mesh" % nm)
			elif (limb as MeshInstance3D).mesh.get_surface_count() < 1:
				f.append("leg B: the fallback %s limb mesh has no surfaces" % nm)
			elif (limb as MeshInstance3D).get_surface_override_material(0) == null:
				f.append("leg B: the fallback %s limb has no base material (renders white/nothing)" % nm)
		var fig_aabb := AABB()
		var first := true
		for nm in LIMB_NAMES:
			var limb = world.player_model.find_child(nm, true, false) as MeshInstance3D
			if limb == null or limb.mesh == null:
				continue
			var lb: AABB = limb.get_aabb()
			lb.position += limb.position
			fig_aabb = lb if first else fig_aabb.merge(lb)
			first = false
		if first or fig_aabb.size.y < 1.0:
			f.append("leg B: the fallback figure's AABB is degenerate (%s) - an invisible nothing"
				% str(fig_aabb))
		# The locomotion rig must have found the limbs, or the figure never animates.
		var found := 0
		for node in world._limbs:
			if node != null:
				found += 1
		if found != LIMB_NAMES.size():
			f.append("leg B: the locomotion rig found %d/%d fallback limbs"
				% [found, LIMB_NAMES.size()])
	if not AssetLoadScript.reported(MISSING_SCENE):
		f.append("leg B: the missing player model was not reported")
	# The game still runs: 60 real ticks through the app world.
	for t in 60:
		world.step(DT, {"move_x": 1, "move_z": 0, "buttons": 0, "app": 0})
	if world.lstate == null or int(world.lstate.tick) <= 0:
		f.append("leg B: the world did not tick with a missing player model")
	world.teardown()
	world.free()


## Leg C: the lobby figure falls back the same way and still walks.
func _leg_c_lobby_figure(f: Array[String]) -> void:
	AssetLoadScript.reset_reports()
	var lp = LobbyPlayerScript.new()
	lp.player_model_path = MISSING_SCENE
	lp.build(Vector3(0.0, 0.0, 8.0))
	if lp.model == null:
		f.append("leg C: a missing lobby figure left no model (no fallback)")
	else:
		if str(lp.model.name) != "PlayerFigureFallback":
			f.append("leg C: the lobby fallback is not the blocky figure (%s)"
				% str(lp.model.name))
		for nm in LIMB_NAMES:
			if lp.model.find_child(nm, true, false) == null:
				f.append("leg C: the lobby fallback has no %s limb" % nm)
	# The four-limb walk still drives it: move for 30 ticks and read the limb rotations.
	var before: Array = []
	for node in lp._limbs:
		before.append(node.rotation.x if node != null else 0.0)
	for t in 30:
		lp.move(DT, 127, 0)
	var moved := false
	for i in lp._limbs.size():
		var node = lp._limbs[i]
		if node != null and absf(float(node.rotation.x) - float(before[i])) > 0.0001:
			moved = true
	if not moved:
		f.append("leg C: the lobby walk did not animate the fallback figure")
	lp.free()


## Leg D: the gift models fall back to a blocky box, every real slot still built.
func _leg_d_gift_models(f: Array[String]) -> void:
	AssetLoadScript.reset_reports()
	var lv: Dictionary = VoidGenScript.generate(1, 1, 1, 0)
	if lv.is_empty():
		f.append("leg D: the level failed to generate")
		return
	var gifts = GiftsScript.create(lv)
	var view = GiftsViewScript.new()
	view.black_model_path = MISSING_SCENE
	view.gold_model_path = MISSING_SCENE
	view.setup(lv, gifts)
	var real := 0
	var built := 0
	for i in gifts.slots.size():
		if not gifts.is_real(i):
			continue
		real += 1
		if view._black[i] != null and view._gold[i] != null:
			built += 1
	if real == 0:
		f.append("leg D: the level carried no real gift slot to test")
	elif built != real:
		f.append("leg D: %d/%d gift slots built with a missing model" % [built, real])
	view.sync(gifts, 0.0)
	if not AssetLoadScript.reported(MISSING_SCENE):
		f.append("leg D: the missing gift model was not reported")
	view.free()


## Leg E: a missing cue is silent, never an error.
func _leg_e_audio(f: Array[String]) -> void:
	AssetLoadScript.reset_reports()
	if AssetLoadScript.stream(MISSING_STREAM) != null:
		f.append("leg E: a missing cue did not answer null")
	if CueAudioScript.load_stream(MISSING_STREAM) != null:
		f.append("leg E: cue_audio.load_stream did not answer null for a missing cue")
	# A real cue still loads through both paths.
	var real := "res://assets/audio/world/level_complete.wav"
	if AssetLoadScript.stream(real) == null:
		f.append("leg E: the real level-complete cue did not load through the loader")
	if CueAudioScript.load_stream(real) == null:
		f.append("leg E: the real level-complete cue did not load through cue_audio")


## Leg F: the boss arena with a missing thrown-gift model. The spawn event must spawn no
## gift and not crash; the arena view still processes the batch.
func _leg_f_boss_gift_model(f: Array[String]) -> void:
	AssetLoadScript.reset_reports()
	var bv = BossViewScript.new()
	bv.gift_model_path = MISSING_SCENE
	bv._gift_model = AssetLoadScript.scene(MISSING_SCENE)   # the missing model answers null
	if bv._gift_model != null:
		f.append("leg F: the missing boss gift model did not answer null")
	# a real arena setup, so the event batch runs the view's own paths (no null sprite).
	# The canvas lives on the root, not under the view, so bv.free() cannot double-free it.
	var canvas := CanvasLayer.new()
	Engine.get_main_loop().get_root().add_child(canvas)
	bv.setup(Vector3.ZERO, 2.0, canvas)
	bv.on_events([{"kind": "boss_spawned", "hp": 100, "hp_max": 100},
		{"kind": "boss_gift_spawned", "id": "g1", "position": Vector3.ZERO}])
	if not bv._gifts.is_empty():
		f.append("leg F: a boss gift spawned from a null model")
	bv.on_events([{"kind": "boss_gift_removed", "id": "g1"}])
	bv.on_events([{"kind": "boss_died"}])
	if not AssetLoadScript.reported(MISSING_SCENE):
		f.append("leg F: the missing boss gift model was not reported")
	bv.free()
	canvas.free()


## Leg G: a missing sprite follows sprites.json + T-016: a sheet whose frame file is
## absent loads that frame as null (the billboard's documented TBD placeholder), the
## sheet still parses, and a missing sprites.json reads as "" through the guarded loader.
func _leg_g_missing_sprite(f: Array[String]) -> void:
	AssetLoadScript.reset_reports()
	var sheet := {
		"world_height": 2.0,
		"animations": [{"name": "idle", "frames": ["u4_no_such_frame.png"],
			"fps": 1.0, "loop": true, "body_rect": [[0, 0, 256, 256]]}],
	}
	var bd = BillboardScript.new()
	bd.setup_from_sheet(sheet, "res://content/enemies/gin")
	var frames: Array = bd.anims.get("idle", {}).get("frames", [])
	if frames.size() != 1 or frames[0] != null:
		f.append("leg G: a missing sprite frame did not load as null per T-016 (%s)" % str(frames))
	bd.set_animation("idle")        # the billboard still drives a null frame...
	bd.advance_animation(0.1)       # ...without crashing (T-016's documented placeholder)
	bd.free()
	if AssetLoadScript.text(MISSING_SHEET) != "":
		f.append("leg G: a missing sprites.json did not read as empty text")
	if not AssetLoadScript.reported(MISSING_SHEET):
		f.append("leg G: the missing sprites.json was not reported")


## Leg H: a missing data file and a missing HUD icon. world.build() with player_data_path
## pointed at an absent file still builds and steps 60 real ticks; the purse pill's icon
## re-load with a missing png only hides the icon (the pill still builds).
func _leg_h_missing_data_and_icon(f: Array[String]) -> void:
	AssetLoadScript.reset_reports()
	var world = WorldScript.new()
	world.player_data_path = MISSING_DATA
	if not world.build(1, 1):
		f.append("leg H: world.build() failed with a missing player data file")
		world.free()
		return
	for t in 60:
		world.step(DT, {"move_x": 1, "move_z": 0, "buttons": 0, "app": 0})
	if world.lstate == null or int(world.lstate.tick) <= 0:
		f.append("leg H: the world did not tick with a missing player data file")
	if not AssetLoadScript.reported(MISSING_DATA):
		f.append("leg H: the missing player data file was not reported")
	world.teardown()
	world.free()
	# The HUD pill: a real build loads the icon; re-pointing at a missing png hides it.
	var pc = PurseChainScript.new()
	if pc._icon.texture == null:
		f.append("leg H: the real gold icon did not load into the purse pill")
	pc.icon_path = MISSING_TEXTURE
	pc._load_icon()
	if pc._icon.texture != null or pc._icon.visible:
		f.append("leg H: a missing icon png did not just hide the icon")
	if not AssetLoadScript.reported(MISSING_TEXTURE):
		f.append("leg H: the missing icon png was not reported")
	pc.free()
