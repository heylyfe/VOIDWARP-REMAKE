extends Node3D
#
# menu_stage.gd - the main menu's 3D backdrop (ticket MENU).
#
# A small floating island in the void, in the gold phase: the beacon is OPEN (the real
# view/beacon_view.gd, light column to Y +60 u), gold gifts sit on their slots, one tripmine
# sparks pink, and the whole enemy roster stands on stepped terraces facing the camera. The
# camera drifts slowly in a shallow arc; it never orbits behind the roster (D-MENU-3).
#
# Everything the player sees is the game's own material:
#   - fog / background / ambient: view/fog_env.gd configured for one biome (D-MENU-2);
#   - tile, slab, trim, dais, prop colours: fog_env.resolve_palette() roles, checker rule
#     (x + z) & 1 == 0 = light (data/palette.json "checker");
#   - beacon: view/beacon_view.gd (model, column, pulse) opened on the frame path;
#   - gifts / tripmine: the T-015 .glb models with view/gifts_view.gd's emission overlay;
#   - enemies: view/billboard.gd fed each enemy's own sprites.json (the real per-enemy PNGs),
#     an idle-type animation, facing the camera every frame (BILLBOARDING hard rule);
#   - the roster caption: view/hud/danger_text.gd's spawn lines in #FF2A2A, one enemy at a time.
#
# The roster is DISCOVERED from res://content/enemies/*/sprites.json - no content id is named
# in this file, so a dropped-in 13th enemy appears without an edit. Placement is by body height
# (tallest at the back, smallest in front), ties broken by id, so the layout is stable run to
# run. An enemy the design gives no body row (world_height null, SR-2) flies across
# the sky instead of standing. A missing frame PNG becomes the TBD placeholder (ENEMIES.md TBD
# FALLBACK): the scene never waits on an asset.
#
# No Tween, no timer node: every motion is a pure function of the stage clock advanced in
# _process (or by advance() in tests), so it runs identically in and out of the scene tree.

const BillboardScript := preload("res://view/billboard.gd")
const FogEnvScript := preload("res://view/fog_env.gd")
const BeaconViewScript := preload("res://view/beacon_view.gd")
const GiftsViewScript := preload("res://view/gifts_view.gd")
const DangerTextScript := preload("res://view/hud/danger_text.gd")
const MakeTbd := preload("res://tools/make_tbd_png.gd")

const ENEMY_DIR := "res://content/enemies"
const GOLD_MODEL := "res://assets/models/gold_gift.glb"
const MINE_MODEL := "res://assets/models/tripmine_box.glb"

## D-MENU-2: the biome whose fog/palette the menu wears. Picked by a palette field read
## from the content tree at run time (the biome whose void colour equals the menu's
## backdrop colour), never by id; the level is that biome's first level (fog_env reads
## the act density for it). See DECISIONS.md D-FIX-APP-BOUNDARY-1.
const VOID_HEX := "#02030F"   # the menu backdrop's own void colour (menu.gd C_VOID)

## Anim-block states tried in order for a roster pose (the T-083 "anim" block).
const IDLE_STATES: Array[String] = ["idle", "idle_chase", "idle_flap"]
## Fallback: T-016 animation names whose FIRST frame is held when no idle state has frames.
const POSE_ANIMS: Array[String] = ["idle", "idle_chase", "idle_flap", "cycle"]
const POSE_NAME := "menu_pose"

## D-MENU-4: display heights compress the canon body range (0.6 .. 4.0 u) into 1.2 .. 3.4 u
## so the smallest enemy stays readable from the menu camera; the order is preserved.
const CANON_H_MIN := 0.6
const CANON_H_MAX := 4.0
const SHOW_H_MIN := 1.2
const SHOW_H_MAX := 3.4
const FLYER_H := 1.3      # the sky enemy's body height (no canon row exists for it)

## Terraces (D-MENU-3). Rows fill back to front; each row's slots fill centre-out.
const ROWS: Array = [
	{"z": -5.5, "top": 2.0, "xs": [-6.2, 6.2]},
	{"z": -2.0, "top": 1.0, "xs": [0.0, -3.1, 3.1, -6.2, 6.2]},
	{"z": 1.6, "top": 0.0, "xs": [-1.55, 1.55, -4.65, 4.65]},
]
const OVERFLOW_Z := 3.9   # extra enemies beyond the 11 terrace slots stand on the front lip

## Island footprint (tile grid, 1 u tiles, tops in u).
const ISLAND_CX := -0.5
const ISLAND_CZ := -3.0
const ISLAND_RX := 10.5
const ISLAND_RZ := 8.4
const SLAB_BOTTOM := -1.0
const TRIM := 0.125
const DAIS_TOP := 2.5
const DAIS_CENTER := Vector3(0.0, DAIS_TOP, -7.0)

## Camera drift (D-MENU-3).
const CAM_TARGET := Vector3(0.0, 1.6, -2.0)
const CAM_DIST := 19.5
const CAM_PITCH_DEG := 15.0
const CAM_SWAY_DEG := 16.0
const CAM_PERIOD := 48.0
const CAM_FOV := 50.0
const CAM_H_OFFSET := -4.2   # frustum shift: the island sits right of the menu column

## Roster caption timing (D-MENU-6).
const CAPTION_EVERY := 3.2
const CAPTION_FADE := 0.35
const CAPTION_HOLD := 2.3

const DANGER := Color(1.0, 0.1647, 0.1647)   # #FF2A2A
const PINK := Color(1.0, 0.309804, 0.847059) # #FF4FD8 tripmine tell - used once
const BEAM := Color(0.910, 1.0, 1.0)          # #E8FFFF beacon_open

var palette: Dictionary = {}
var camera: Camera3D
var env_node: WorldEnvironment
var beacon: Node3D
var roster: Array = []          # [{id, name, height, show_h, flying, holder, sprite, caption}]
var clock := 0.0

var _sky_holder: Node3D = null
var _motes: Node3D
var _shards: Array = []         # [Node3D, spin Vector3]
var _caption_index := -1
var _tbd_texture: Texture2D = null
var _biome_id := ""             # picked by menu_biome() in build() (D-MENU-2)
var _biome_level := 1


func _init() -> void:
	name = "MenuStage"
	build()


func build() -> void:
	var pick := menu_biome()
	_biome_id = str(pick.get("id", ""))
	_biome_level = int(pick.get("level", 1))
	palette = FogEnvScript.resolve_palette(_biome_id, _biome_level)
	_build_environment()
	_build_island()
	_build_props()
	_build_beacon()
	_build_roster()
	_build_shards()
	_build_motes()
	_build_camera()
	advance(0.0)


# ---- palette helpers ---------------------------------------------------------------------------

## The menu biome, picked from the content tree at run time: the biome whose palette void
## equals VOID_HEX (the deep-indigo act set the island wears). Falls back to the deepest act
## (highest first level) when no void matches - a content drift, not a crash. Returns
## {"id": String, "level": int}; {"id": "", "level": 1} when the content tree is unreadable
## (fog_env resolves "" to the act-I biome from the level). No content id is named here.
static func menu_biome() -> Dictionary:
	var dir := DirAccess.open("res://content/biomes")
	if dir == null:
		return {"id": "", "level": 1}
	var rows: Array = []
	var found: Dictionary = {}
	for fn in dir.get_files():
		if not fn.ends_with(".json") or fn.begins_with("."):
			continue
		var text := FileAccess.get_file_as_string("res://content/biomes/%s" % fn)
		var parsed: Variant = JSON.parse_string(text)
		if not (parsed is Dictionary):
			continue
		var p: Dictionary = parsed
		var pal: Variant = p.get("palette", {})
		var void_hex := ""
		if pal is Dictionary:
			void_hex = str((pal as Dictionary).get("void", "")).to_upper()
		var levels: Variant = p.get("levels", [])
		var first := 999999
		if levels is Array and not (levels as Array).is_empty():
			first = int((levels as Array)[0])
		var row := {"id": str(p.get("id", fn.trim_suffix(".json"))), "level": first,
				"void": void_hex}
		rows.append(row)
		if void_hex == VOID_HEX:
			found = row
	if not found.is_empty():
		return found
	rows.sort_custom(func(a, b): return int(a["level"]) < int(b["level"]))
	return rows[rows.size() - 1] if not rows.is_empty() else {"id": "", "level": 1}

func role(p_name: String, fallback: Color = Color(0.1, 0.1, 0.12)) -> Color:
	var roles: Dictionary = palette.get("roles", {})
	if roles.has(p_name):
		var r: Dictionary = roles[p_name]
		return Color(str(r.get("hex", "#000000")))
	return fallback


# ---- environment -------------------------------------------------------------------------------

func _build_environment() -> void:
	env_node = FogEnvScript.new()
	env_node.name = "FogEnv"
	env_node.configure(_biome_id, _biome_level)
	# D-MENU-2: glow on top of the game's own fog so the open beacon blooms like the reference.
	var env: Environment = env_node.environment
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env_node)


# ---- island ------------------------------------------------------------------------------------

## Integer hash for the deterministic ragged edge and spike lengths (no engine RNG).
static func _hash2(x: int, z: int) -> int:
	var h: int = (x * 73856093) ^ (z * 19349663)
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))


## Top of the tile at grid (x, z), or NAN when the island has no tile there.
static func tile_top(x: int, z: int) -> float:
	var xc: float = float(x) + 0.5
	var zc: float = float(z) + 0.5
	var ex: float = (xc - ISLAND_CX) / ISLAND_RX
	var ez: float = (zc - ISLAND_CZ) / ISLAND_RZ
	var e: float = ex * ex + ez * ez
	if e > 1.0:
		return NAN
	if e > 0.78 and _hash2(x, z) % 3 == 0:
		return NAN
	if absf(xc) <= 2.5 and zc >= DAIS_CENTER.z - 2.5 and zc <= DAIS_CENTER.z + 2.5:
		return DAIS_TOP
	if zc >= 0.0:
		return 0.0
	if zc >= -3.5:
		return 1.0
	return 2.0


static func _is_dais(x: int, z: int) -> bool:
	var xc: float = float(x) + 0.5
	var zc: float = float(z) + 0.5
	return absf(xc) <= 2.5 and zc >= DAIS_CENTER.z - 2.5 and zc <= DAIS_CENTER.z + 2.5


func _material(c: Color, emission: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1)
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.92
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	return m


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	st.set_normal(n)
	st.set_color(col)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var n: Vector3 = (b - a).cross(c - a).normalized()
	st.set_normal(n)
	st.set_color(col)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


## Lightness grain per tile: +/- 4 % (the palette's per-texel grain, coarsened to tiles).
static func _grain(c: Color, x: int, z: int) -> Color:
	var g: float = 1.0 + (float(_hash2(x + 101, z - 37) % 81) - 40.0) / 1000.0
	return Color(c.r * g, c.g * g, c.b * g, 1.0)


func _build_island() -> void:
	var light := role("platform_light")
	var dark := role("platform_dark")
	var dais := role("hub_dais")
	var side := role("slab_side")
	var trim := role("slab_trim")
	var spike := role("support_spike")
	var st_light := SurfaceTool.new()
	var st_dark := SurfaceTool.new()
	var st_side := SurfaceTool.new()
	var st_trim := SurfaceTool.new()
	for st in [st_light, st_dark, st_side, st_trim]:
		(st as SurfaceTool).begin(Mesh.PRIMITIVE_TRIANGLES)
	var dirs: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for z in range(-12, 7):
		for x in range(-12, 12):
			var top: float = tile_top(x, z)
			if is_nan(top):
				continue
			var x0 := float(x)
			var z0 := float(z)
			var is_light: bool = ((x + z) & 1) == 0
			var col: Color = dais if _is_dais(x, z) else (light if is_light else dark)
			var st_top: SurfaceTool = st_light if (is_light and not _is_dais(x, z)) else st_dark
			_quad(st_top, Vector3(x0, top, z0), Vector3(x0 + 1, top, z0), Vector3(x0 + 1, top, z0 + 1),
					Vector3(x0, top, z0 + 1), Vector3.UP, _grain(col, x, z))
			# underside
			_quad(st_side, Vector3(x0, SLAB_BOTTOM, z0), Vector3(x0, SLAB_BOTTOM, z0 + 1),
					Vector3(x0 + 1, SLAB_BOTTOM, z0 + 1), Vector3(x0 + 1, SLAB_BOTTOM, z0), Vector3.DOWN, spike)
			for d in dirs:
				var dv: Vector2i = d
				var nt: float = tile_top(x + dv.x, z + dv.y)
				var lo: float = SLAB_BOTTOM if is_nan(nt) else nt
				if lo >= top:
					continue
				var a := Vector3.ZERO
				var b := Vector3.ZERO
				if dv.x == 1:
					a = Vector3(x0 + 1, 0, z0)
					b = Vector3(x0 + 1, 0, z0 + 1)
				elif dv.x == -1:
					a = Vector3(x0, 0, z0 + 1)
					b = Vector3(x0, 0, z0)
				elif dv.y == 1:
					a = Vector3(x0 + 1, 0, z0 + 1)
					b = Vector3(x0, 0, z0 + 1)
				else:
					a = Vector3(x0, 0, z0)
					b = Vector3(x0 + 1, 0, z0)
				var n := Vector3(float(dv.x), 0.0, float(dv.y))
				var band: float = maxf(top - TRIM, lo)
				_quad(st_trim, Vector3(a.x, top, a.z), Vector3(b.x, top, b.z), Vector3(b.x, band, b.z),
						Vector3(a.x, band, a.z), n, trim)
				if band > lo:
					_quad(st_side, Vector3(a.x, band, a.z), Vector3(b.x, band, b.z), Vector3(b.x, lo, b.z),
							Vector3(a.x, lo, a.z), n, side)
			# support spikes under the island: every edge tile and one interior tile in five
			var edge := false
			for d2 in dirs:
				var dv2: Vector2i = d2
				if is_nan(tile_top(x + dv2.x, z + dv2.y)):
					edge = true
			var hsh: int = _hash2(x * 3 + 7, z * 5 - 11)
			if edge or hsh % 5 == 0:
				var depth: float = 1.2 + float(hsh % 7) * 0.75
				var apex := Vector3(x0 + 0.5, SLAB_BOTTOM - depth, z0 + 0.5)
				var p0 := Vector3(x0, SLAB_BOTTOM, z0)
				var p1 := Vector3(x0 + 1, SLAB_BOTTOM, z0)
				var p2 := Vector3(x0 + 1, SLAB_BOTTOM, z0 + 1)
				var p3 := Vector3(x0, SLAB_BOTTOM, z0 + 1)
				_tri(st_side, p0, p1, apex, spike)
				_tri(st_side, p1, p2, apex, spike)
				_tri(st_side, p2, p3, apex, spike)
				_tri(st_side, p3, p0, apex, spike)
	var mesh := ArrayMesh.new()
	var mats: Array = [
		[st_light, _material(light, 0.35)],    # platform_light emission 0.35 x albedo
		[st_dark, _material(dark)],
		[st_side, _material(side)],
		[st_trim, _material(trim)],
	]
	for pair in mats:
		var st: SurfaceTool = pair[0]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, pair[1])
	var mi := MeshInstance3D.new()
	mi.name = "Island"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ---- props: pillars, gold gifts, one tripmine --------------------------------------------------

func _build_props() -> void:
	var block := role("prop_block")
	var trim := role("slab_trim")
	var pillars: Array = [[-9.0, -4.0, 3.5], [8.5, -1.0, 2.2], [-4.5, -9.0, 4.5], [9.0, -6.5, 5.0]]
	for p in pillars:
		var pa: Array = p
		var top: float = tile_top(int(floor(float(pa[0]))), int(floor(float(pa[1]))))
		if is_nan(top):
			continue
		var h: float = float(pa[2])
		var box := BoxMesh.new()
		box.size = Vector3(0.9, h, 0.9)
		var mi := MeshInstance3D.new()
		mi.mesh = box
		var m := StandardMaterial3D.new()
		m.albedo_color = block
		m.roughness = 0.9
		mi.material_override = m
		mi.position = Vector3(floor(float(pa[0])) + 0.5, top + h * 0.5, floor(float(pa[1])) + 0.5)
		add_child(mi)
		var cap := BoxMesh.new()
		cap.size = Vector3(0.96, TRIM, 0.96)
		var ci := MeshInstance3D.new()
		ci.mesh = cap
		var cm := StandardMaterial3D.new()
		cm.albedo_color = trim
		ci.material_override = cm
		ci.position = Vector3(0.0, h * 0.5 - TRIM * 0.5, 0.0)
		mi.add_child(ci)
	# gold phase: gold gifts on their slots (emission x 2.0 overlay, the in-game look)
	var gold_ps: PackedScene = load(GOLD_MODEL) if ResourceLoader.exists(GOLD_MODEL) else null
	if gold_ps != null:
		var gold_mat := GiftsViewScript.emission_material(GiftsViewScript.GOLD_FACTOR)
		# in the gaps between front-row enemies, never in front of one
		for gxz in [Vector2(0.0, 3.2), Vector2(3.1, 3.0), Vector2(7.6, -0.4),
				Vector2(3.4, -5.2), Vector2(-3.2, -5.4)]:
			var gp := _on_tile(gxz)
			if is_nan(gp.y):
				continue
			var g: Node3D = gold_ps.instantiate()
			g.position = gp
			g.rotation.y = gp.x * 0.7
			_overlay(g, gold_mat)
			add_child(g)
	# one tripmine: the only pink in the scene (its constant #FF4FD8 particle tell)
	var mine_ps: PackedScene = load(MINE_MODEL) if ResourceLoader.exists(MINE_MODEL) else null
	var mine_pos := _on_tile(Vector2(-3.1, 3.0))
	if is_nan(mine_pos.y):
		mine_pos = Vector3(-3.1, 0.0, 1.6)
	if mine_ps != null:
		var mine: Node3D = mine_ps.instantiate()
		mine.name = "Tripmine"
		mine.position = mine_pos
		_overlay(mine, GiftsViewScript.emission_material(1.5))
		add_child(mine)
	var sparks := CPUParticles3D.new()
	sparks.name = "TripmineSparks"
	sparks.position = mine_pos + Vector3(0.0, 0.6, 0.0)
	sparks.amount = 18
	sparks.lifetime = 1.5
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.2
	sparks.direction = Vector3.UP
	sparks.spread = 25.0
	sparks.gravity = Vector3.ZERO
	sparks.initial_velocity_min = 0.3
	sparks.initial_velocity_max = 0.5
	var spark_mesh := QuadMesh.new()
	spark_mesh.size = Vector2(0.06, 0.06)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.albedo_color = PINK
	sm.emission_enabled = true
	sm.emission = PINK
	sm.emission_energy_multiplier = 2.0
	spark_mesh.material = sm
	sparks.mesh = spark_mesh
	add_child(sparks)


## A point on the island surface at (x, z); y is NAN when no tile is there.
static func _on_tile(xz: Vector2) -> Vector3:
	return Vector3(xz.x, tile_top(int(floor(xz.x)), int(floor(xz.y))), xz.y)


static func _overlay(root: Node, mat: Material) -> void:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D:
			(n as MeshInstance3D).material_overlay = mat


# ---- beacon ------------------------------------------------------------------------------------

func _build_beacon() -> void:
	beacon = BeaconViewScript.new()
	beacon.name = "Beacon"
	beacon.position = DAIS_CENTER
	beacon.set_progress(8, 8)
	beacon.set_open(true)
	add_child(beacon)
	# the beacon is the scene's key light (the game has no sun; D-MENU-2)
	var lamp := OmniLight3D.new()
	lamp.name = "BeaconLight"
	lamp.light_color = BEAM
	lamp.light_energy = 2.2
	lamp.omni_range = 24.0
	lamp.omni_attenuation = 1.2
	lamp.shadow_enabled = false
	lamp.position = DAIS_CENTER + Vector3(0.0, 3.5, 1.5)
	add_child(lamp)
	var fill := OmniLight3D.new()
	fill.name = "RosterFill"
	fill.light_color = role("player_fill_light", Color(0.75, 1.0, 0.97))
	fill.light_energy = 0.8
	fill.omni_range = 18.0
	fill.shadow_enabled = false
	fill.position = Vector3(0.0, 5.0, 6.0)
	add_child(fill)


# ---- roster ------------------------------------------------------------------------------------

## Every enemy folder with a sprites.json, as {id, name, doc, height, flying}, sorted by id.
static func discover_roster() -> Array:
	var out: Array = []
	var dir := DirAccess.open(ENEMY_DIR)
	if dir == null:
		return out
	var ids: Array[String] = []
	for d in dir.get_directories():
		if FileAccess.file_exists("%s/%s/sprites.json" % [ENEMY_DIR, d]):
			ids.append(str(d))
	ids.sort()
	for id in ids:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s/sprites.json" % [ENEMY_DIR, id]))
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var doc: Dictionary = parsed
		var wh_v: Variant = doc.get("world_height", null)
		var wh: float = float(wh_v) if (wh_v is float or wh_v is int) else 0.0
		out.append({"id": id, "name": str(doc.get("name", id)), "doc": doc, "height": wh,
				"flying": wh <= 0.0})
	return out


## Grounded enemies sorted tallest first (ties by id) -> one slot each, back row first.
static func layout(entries: Array) -> Array:
	var grounded: Array = []
	for e in entries:
		if not bool(e["flying"]):
			grounded.append(e)
	grounded.sort_custom(func(a, b) -> bool:
		if float(a["height"]) != float(b["height"]):
			return float(a["height"]) > float(b["height"])
		return str(a["id"]) < str(b["id"]))
	var slots: Array = []
	for row in ROWS:
		var r: Dictionary = row
		for xv in r["xs"]:
			slots.append(Vector3(float(xv), float(r["top"]), float(r["z"])))
	var k := 0
	while slots.size() < grounded.size():
		var side: float = -1.0 if k % 2 == 0 else 1.0
		slots.append(Vector3(side * (1.55 + 3.1 * float(k / 2)), 0.0, OVERFLOW_Z))
		k += 1
	var placed: Array = []
	for i in grounded.size():
		placed.append({"entry": grounded[i], "pos": slots[i]})
	return placed


static func show_height(canon_h: float) -> float:
	var t: float = clampf((canon_h - CANON_H_MIN) / (CANON_H_MAX - CANON_H_MIN), 0.0, 1.0)
	return lerpf(SHOW_H_MIN, SHOW_H_MAX, t)


static func pose_anim(doc: Dictionary) -> String:
	var names: Array[String] = []
	for a in doc.get("animations", []):
		if a is Dictionary:
			names.append(str((a as Dictionary).get("name", "")))
	for n in POSE_ANIMS:
		if names.has(n):
			return n
	return names[0] if not names.is_empty() else ""


## The idle loop as the anim block states it (content/enemies/<id>/sprites.json "anim", the
## T-083 block enemy_anim.gd plays): the first of IDLE_STATES that lists frames, at its
## ticks_per_frame (60 Hz ticks) - or its fps - looping. Without such a state (an enemy whose
## resting look is not a loop of its own, e.g. a countdown or a missile), the T-016 pose
## animation's FIRST frame is held still, so no attack/telegraph frame ever plays in the menu.
## Returns {"frames": [paths], "fps": float}.
static func idle_pose(doc: Dictionary) -> Dictionary:
	var anim_v: Variant = doc.get("anim", {})
	var states: Dictionary = {}
	if anim_v is Dictionary:
		var st_v: Variant = (anim_v as Dictionary).get("states", {})
		if st_v is Dictionary:
			states = st_v
	for sname in IDLE_STATES:
		if not states.has(sname) or not (states[sname] is Dictionary):
			continue
		var sp: Dictionary = states[sname]
		var fr_v: Variant = sp.get("frames", [])
		if not (fr_v is Array) or (fr_v as Array).is_empty():
			continue
		var fps := 0.0
		var tpf: Variant = sp.get("ticks_per_frame", null)
		if (tpf is float or tpf is int) and float(tpf) > 0.0:
			fps = 60.0 / float(tpf)
		elif sp.get("fps", null) is float or sp.get("fps", null) is int:
			fps = float(sp.get("fps"))
		return {"frames": (fr_v as Array).duplicate(), "fps": fps}
	var pose := pose_anim(doc)
	for a in doc.get("animations", []):
		if a is Dictionary and str((a as Dictionary).get("name", "")) == pose:
			var fr: Array = (a as Dictionary).get("frames", [])
			if not fr.is_empty():
				return {"frames": [fr[0]], "fps": 0.0}
	return {"frames": [], "fps": 0.0}


## Adds the idle pose as the billboard's "menu_pose" animation: frame textures from the enemy
## folder, each frame's body_rect looked up from the T-016 list by file path.
func _install_pose(sprite: Sprite3D, doc: Dictionary, folder: String) -> void:
	var rect_of := {}
	var first_rect: Variant = null
	for a in doc.get("animations", []):
		if not (a is Dictionary):
			continue
		var fr: Array = (a as Dictionary).get("frames", [])
		var rects: Array = (a as Dictionary).get("body_rect", [])
		for i in fr.size():
			if i < rects.size() and not rect_of.has(str(fr[i])):
				rect_of[str(fr[i])] = rects[i]
				if first_rect == null:
					first_rect = rects[i]
	var pose := idle_pose(doc)
	var texs: Array = []
	var rects_out: Array = []
	for p in pose["frames"]:
		var full := folder.path_join(str(p))
		texs.append(load(full) if ResourceLoader.exists(full) else null)
		rects_out.append(rect_of.get(str(p), first_rect if first_rect != null else [0, 0, 256, 256]))
	if texs.is_empty():
		texs.append(null)
		rects_out.append([16, 16, 224, 224])         # the TBD placeholder's body
	sprite.anims[POSE_NAME] = {"frames": texs, "fps": maxf(float(pose["fps"]), 0.0001),
			"loop": true, "body_rect": rects_out}
	sprite.set_animation(POSE_NAME)


func _tbd() -> Texture2D:
	if _tbd_texture == null:
		_tbd_texture = ImageTexture.create_from_image(MakeTbd.build(256))
	return _tbd_texture


func _make_billboard(entry: Dictionary, show_h: float) -> Sprite3D:
	var doc: Dictionary = (entry["doc"] as Dictionary).duplicate(true)
	doc["world_height"] = show_h
	var sprite: Sprite3D = BillboardScript.new()
	sprite.name = "Billboard"
	var folder := "%s/%s" % [ENEMY_DIR, str(entry["id"])]
	sprite.setup_from_sheet(doc, folder)
	_install_pose(sprite, doc, folder)
	# TBD FALLBACK: any frame that failed to load shows the placeholder, never nothing
	for k in sprite.anims.keys():
		var frames: Array = sprite.anims[k]["frames"]
		for i in frames.size():
			if frames[i] == null:
				frames[i] = _tbd()
	sprite._apply_frame(sprite.frame_i)          # re-derive scale/feet from the real texture
	if sprite.texture == null:
		sprite.texture = _tbd()
	sprite.shaded = false
	# the stage drives the frame and the facing in one place (advance()), so the billboard's
	# own _process is switched off. The feet offset is billboard.gd's job and is correct as of
	# FIX-BILLBOARD (D-FIX-BILLBOARD-1), so the menu no longer compensates for it.
	sprite.process_mode = Node.PROCESS_MODE_DISABLED
	return sprite


## World-space y of the visible body's bottom edge relative to the sprite's holder (tests: ~0).
static func body_bottom(sprite: Sprite3D) -> float:
	var a: Dictionary = sprite._current_anim()
	if a.is_empty() or sprite.texture == null:
		return 0.0
	var brs: Array = a["body_rect"]
	var br: Array = brs[mini(int(sprite.frame_i), brs.size() - 1)]
	var bottom_px_from_center: float = float(br[1]) + float(br[3]) - float(sprite.texture.get_height()) * 0.5
	return sprite.position.y + sprite.scale.y * sprite.pixel_size * (sprite.offset.y - bottom_px_from_center)


func _shadow_blob(radius: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(radius * 2.0, radius * 1.2)
	q.orientation = PlaneMesh.FACE_Y
	var mi := MeshInstance3D.new()
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.55))
	grad.set_color(1, Color(0, 0, 0, 0.0))
	g.gradient = grad
	m.albedo_texture = g
	mi.material_override = m
	mi.position = Vector3(0.0, 0.015, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _make_caption(entry: Dictionary, height_u: float) -> Label3D:
	var label := Label3D.new()
	label.name = "Caption"
	label.text = DangerTextScript.spawn_line(str(entry["id"]))
	label.font_size = 52
	label.pixel_size = 0.0125
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(DANGER.r, DANGER.g, DANGER.b, 0.0)
	label.outline_size = 12
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.0)
	label.position = Vector3(0.0, height_u + 0.55, 0.0)
	label.visible = false
	return label


func _build_roster() -> void:
	var entries := discover_roster()
	for placed in layout(entries):
		var e: Dictionary = placed["entry"]
		var pos: Vector3 = placed["pos"]
		var sh: float = show_height(float(e["height"]))
		_add_enemy(e, sh, pos, false)
	var flyers: Array = []
	for e in entries:
		if bool(e["flying"]):
			flyers.append(e)
	for i in flyers.size():
		var pos := Vector3(0.0, 8.5 + 1.6 * float(i), -9.0 - 2.0 * float(i))
		_add_enemy(flyers[i], FLYER_H, pos, true)


func _add_enemy(e: Dictionary, show_h: float, pos: Vector3, flying: bool) -> void:
	var holder := Node3D.new()
	holder.name = "Enemy_%s" % str(e["id"])
	holder.position = pos
	add_child(holder)
	var sprite := _make_billboard(e, show_h)
	holder.add_child(sprite)
	if not flying:
		var w: float = show_h
		var tex: Texture2D = sprite.texture
		if tex != null and tex.get_height() > 0:
			w = show_h * float(tex.get_width()) / float(tex.get_height())
		holder.add_child(_shadow_blob(clampf(w * 0.42, 0.45, 2.4)))
	var caption := _make_caption(e, show_h)
	holder.add_child(caption)
	roster.append({"id": str(e["id"]), "name": str(e["name"]), "height": float(e["height"]),
			"show_h": show_h, "flying": flying, "holder": holder, "sprite": sprite,
			"caption": caption, "base": pos})


# ---- floating shards + void motes --------------------------------------------------------------

## Deterministic LCG in [0, 1) for scenery scatter (never sim state).
static func _rand(seed_v: int) -> float:
	var s: int = (seed_v * 1103515245 + 12345) & 0x7fffffff
	return float(s % 10000) / 10000.0


func _build_shards() -> void:
	var body := role("black_gift_body", Color(0.02, 0.02, 0.03))
	var rim := role("black_gift_rim", Color(0.49, 1.0, 0.96))
	var count := 13
	for i in count:
		var ang: float = TAU * (float(i) + 0.35 * _rand(i * 7 + 1)) / float(count)
		var rad: float = 14.0 + 9.0 * _rand(i * 13 + 5)
		var y: float = -5.0 + 17.0 * _rand(i * 17 + 3)
		var pos := Vector3(cos(ang) * rad, y, -4.0 + sin(ang) * rad * 0.8)
		if pos.z > 6.0:
			pos.z = -pos.z * 0.6          # keep the camera side clear
		var size: float = 0.8 + 1.8 * _rand(i * 19 + 9)
		if absf(pos.x) < 11.0 and pos.y > 3.0:
			# above the roster: small and pushed back, so no shard sits on the beam or a name
			pos.z = minf(pos.z, -14.0)
			size = minf(size, 1.1)
		var shard := _make_shard(i, size, body, rim)
		shard.position = pos
		shard.rotation = Vector3(_rand(i + 40) * TAU, _rand(i + 50) * TAU, _rand(i + 60) * TAU)
		add_child(shard)
		_shards.append([shard, Vector3(_rand(i + 70) - 0.5, _rand(i + 80) - 0.5, _rand(i + 90) - 0.5) * 0.25])


func _make_shard(i: int, size: float, body: Color, rim: Color) -> Node3D:
	# a jittered octahedron: six points, eight faces, flat shaded, with its edges drawn
	var pts: Array[Vector3] = [
		Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1.3, 0),
		Vector3(0, -1.3, 0), Vector3(0, 0, 1), Vector3(0, 0, -1),
	]
	for k in pts.size():
		var j: float = 0.65 + 0.7 * _rand(i * 31 + k * 7)
		pts[k] = pts[k] * j * size
	var faces: Array = [[0, 2, 4], [4, 2, 1], [1, 2, 5], [5, 2, 0], [0, 4, 3], [4, 1, 3], [1, 5, 3], [5, 0, 3]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		var fa: Array = f
		_tri(st, pts[int(fa[0])], pts[int(fa[1])], pts[int(fa[2])], body)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1)
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.35
	m.metallic_specular = 0.8
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	var edges: Array = [[0, 2], [1, 2], [4, 2], [5, 2], [0, 3], [1, 3], [4, 3], [5, 3], [0, 4], [4, 1], [1, 5], [5, 0]]
	var lines := SurfaceTool.new()
	lines.begin(Mesh.PRIMITIVE_LINES)
	for ed in edges:
		var ea: Array = ed
		lines.set_color(rim)
		lines.add_vertex(pts[int(ea[0])])
		lines.set_color(rim)
		lines.add_vertex(pts[int(ea[1])])
	var li := MeshInstance3D.new()
	li.mesh = lines.commit()
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.vertex_color_use_as_albedo = true
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lm.albedo_color = Color(1, 1, 1, 0.45)
	li.material_override = lm
	mi.add_child(li)
	var root := Node3D.new()
	root.name = "Shard%d" % i
	root.add_child(mi)
	return root


func _build_motes() -> void:
	_motes = Node3D.new()
	_motes.name = "Motes"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(0.75, 0.85, 1.0, 0.55)
	m.disable_fog = true
	q.material = m
	mm.mesh = q
	mm.instance_count = 240
	for i in mm.instance_count:
		var a: float = _rand(i * 3 + 1000) * TAU
		var r: float = 18.0 + 40.0 * _rand(i * 5 + 2000)
		var y: float = -14.0 + 44.0 * _rand(i * 7 + 3000)
		var s: float = 0.5 + 1.6 * _rand(i * 11 + 4000)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s, s)),
				Vector3(cos(a) * r, y, sin(a) * r - 6.0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	_motes.add_child(mmi)
	add_child(_motes)


# ---- camera ------------------------------------------------------------------------------------

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "MenuCamera"
	camera.fov = CAM_FOV
	camera.h_offset = CAM_H_OFFSET
	camera.near = 0.1
	camera.far = 400.0
	camera.current = true
	add_child(camera)


## Camera pose at stage time t: a shallow sway around the roster, never behind it.
static func camera_pose(t: float) -> Transform3D:
	var yaw: float = deg_to_rad(CAM_SWAY_DEG) * sin(TAU * t / CAM_PERIOD)
	var pitch: float = deg_to_rad(CAM_PITCH_DEG + 1.5 * sin(TAU * t / (CAM_PERIOD * 0.73)))
	var dist: float = CAM_DIST + 0.8 * sin(TAU * t / (CAM_PERIOD * 1.31))
	var eye := CAM_TARGET + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	return Transform3D(Basis.looking_at(CAM_TARGET - eye, Vector3.UP), eye)


# ---- per-frame ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	advance(delta)


## Advances the stage clock: camera drift, flyer path, shard spin, mote drift, caption cycle,
## and the billboards' own frame animation + camera facing (billboard.gd).
func advance(delta: float) -> void:
	clock += delta
	if camera != null:
		camera.transform = camera_pose(clock)
	var cam_pos: Vector3 = camera.position if camera != null else Vector3(0, 0, 20)
	for r in roster:
		var holder: Node3D = r["holder"]
		var sprite: Sprite3D = r["sprite"]
		if bool(r["flying"]):
			# the sky enemy crosses the void nose-first (the sprite's nose points -x), wrapping
			var base: Vector3 = r["base"]
			var span := 44.0
			var x: float = fposmod(22.0 - clock * 1.6 + base.x, span) - span * 0.5
			holder.position = Vector3(x, base.y + 0.35 * sin(clock * 0.9), base.z)
		sprite.advance_animation(delta)
		if sprite.is_inside_tree():
			sprite.face_camera(cam_pos)
		else:
			sprite.face_camera(cam_pos - holder.position)
	for s in _shards:
		var node: Node3D = s[0]
		var spin: Vector3 = s[1]
		node.rotation += spin * delta
	if _motes != null:
		_motes.rotation.y = clock * 0.004
	_update_caption()


func _update_caption() -> void:
	if roster.is_empty():
		return
	var idx: int = int(floor(clock / CAPTION_EVERY)) % roster.size()
	var local: float = fmod(clock, CAPTION_EVERY)
	if idx != _caption_index:
		if _caption_index >= 0 and _caption_index < roster.size():
			var old: Label3D = roster[_caption_index]["caption"]
			old.visible = false
		_caption_index = idx
	var label: Label3D = roster[idx]["caption"]
	var a := 0.0
	if local < CAPTION_FADE:
		a = local / CAPTION_FADE
	elif local < CAPTION_FADE + CAPTION_HOLD:
		a = 1.0
	elif local < CAPTION_FADE * 2.0 + CAPTION_HOLD:
		a = 1.0 - (local - CAPTION_FADE - CAPTION_HOLD) / CAPTION_FADE
	label.visible = a > 0.0
	label.modulate = Color(DANGER.r, DANGER.g, DANGER.b, a)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85 * a)


## The enemy whose danger line is showing (-1 when none).
func caption_index() -> int:
	return _caption_index


## Test/inspection surface: the roster billboards (Sprite3D, billboard.gd).
func roster_billboards() -> Array:
	var out: Array = []
	for r in roster:
		out.append(r["sprite"])
	return out


func roster_ids() -> Array:
	var out: Array = []
	for r in roster:
		out.append(r["id"])
	return out
