extends Node3D
#
# view/lobby/antechamber.gd - THE ANTECHAMBER (ticket T-023; DESIGN.md section 11,
# owner spec "INTERMISSION (canon)"). One fixed scene, built by a deterministic script:
# no hand-placed nodes anywhere in this file.
#
# Hall 28 u (x) x 20 u (z), ceiling 8 u. Checker floor in the CURRENT biome's platform
# colours, walls in the slab-side colour with the trim band, a 9 u star sigil
# (walkway-light colour) centred on the floor, procedural props along the walls, the same
# fog (view/fog_env.gd) and a player fill light. Player spawns at (0, +8) facing -z; the
# Descent Gate stands at (0, -9.5): dull until lobby.gate_open(), then white (the beacon's
# visual language). Bays at x = -9 / 0 / +9, altars 3 per bay at x offsets -3/0/+3,
# z = -4, exhibits hovering 1.8 u over 1.2 x 1.0 x 1.2 plinths, bobbing +-0.1 u at 0.5 Hz.
#
# View only: it READS the sim intermission state (sim/intermission.gd) and returns SIM
# INPUTS. tick() advances the F-hold (0.35 s) on the prompted altar and, on confirm,
# returns {"select": <altar_table index>} for the caller to feed into
# IntermissionScript.step() - never a UI callback (DESIGN.md section 13 rule 2).
#
# J7 made the hall a place rather than a diorama: the description panel is HIDDEN until
# the player stands at an altar and looks at it (one panel at a time, as the reference art
# shows), a pick flares the bay's plinths and banner for FLASH_S, the banners are the
# reference's two-line lockup (huge emissive title + italic subtitle), the gate carries a
# sealed readout naming the bays still open, and the room carries the art's green back
# arrow plus a cyan reroll ring over every reroll plinth. The props, the plinths and the
# gate are the shipped T-015 .glb models when they are present (box fallbacks otherwise).
# view/lobby/lobby_scene.gd is the node that walks a player through all of it.
#
# Headless-testable: build_all() does the whole build without the scene tree; the bob /
# hold / sink animation runs only inside tick(dt, ...). When parented into a real scene,
# _process() forwards to tick() (the caller sets player_pos / look each frame or pins
# them once) - a caller that drives tick() itself must set_process(false) first, or the
# hold would accrue twice per frame.

const FogEnvScript := preload("res://view/fog_env.gd")
const BillboardScript := preload("res://view/billboard.gd")
const OffersSim := preload("res://sim/offers.gd")
const NoRefundsScript := preload("res://content/curses/no_refunds.gd")

# ---- DESIGN.md section 11 facts ----
const HALL_X := 28.0
const HALL_Z := 20.0
const CEIL := 8.0
const SPAWN := Vector3(0.0, 0.0, 8.0)      # arrives at (0, +8) facing -z
const GATE_POS := Vector3(0.0, 0.0, -9.5)
const BAY_X := [-9.0, 0.0, 9.0]            # left, centre, right
const BAY_Z := -4.0
const ALTAR_DX := [-3.0, 0.0, 3.0]         # 3 altars per bay
const BANNER_Y := 5.0                      # floating banner height
const PLINTH_SIZE := Vector3(1.2, 1.0, 1.2)
const EXHIBIT_LIFT := 1.8                  # exhibit hover above the plinth top
const BOB_AMP := 0.1                       # exhibit bobs +-0.1 u
const BOB_HZ := 0.5                        # at 0.5 Hz
const ENEMY_BODY_H := 1.6                  # enemy exhibit: 1.6 u body height
const ICON_H := 1.2                        # curse / upgrade icon billboard
const PANEL_W := 2.4                       # world-space panel width
const SIGIL_R := 4.5                       # the 9 u star sigil (diameter)
const HOLD_S := 0.35                       # hold F to confirm (radial fill)
const PROMPT_R := 2.5                      # altar proximity for the prompt
const LOOK_COS := 0.5                      # looking within 60 degrees of the altar
const SINK_S := 0.6                        # losing altars sink into the floor over 0.6 s
const PLINTH_DX := 5.5                     # tithe (right) / reroll (left) plinth offset

## Floating bay banners (DESIGN.md section 11: display serif capitals, subtitle in italic
## below). [title, subtitle] - the reference art's two-line lockup, not one dashed line.
const BANNER_TEXT: Dictionary = {
	"E": ["ENEMIES", "Choose an adversary."],
	"C": ["CURSES", "Become accursed."],
	"U": ["UPGRADES", "Arm yourself."],
	"REST": ["RESPITE", "Catch your breath."],
	"CLASS": ["CLASSES", "Choose who falls."],
}

## Banner lockup: a huge emissive title with the italic subtitle one line under it.
const TITLE_FONT := 96
const TITLE_PIXEL := 0.012
const SUBTITLE_FONT := 40
const SUBTITLE_PIXEL := 0.008
const SUBTITLE_DY := -1.15

## The pick flare: the picked bay's plinths and banner glow for FLASH_S, then fade.
const GLOW_ENERGY := 3.2
const FLASH_S := 0.45

## The two room icons from the reference art: the green back arrow (left) and the cyan
## reroll ring (right). The arrow's green has no palette role - it is the art's own colour.
const BACK_ARROW_POS := Vector3(-11.5, 1.7, 6.0)
const BACK_ARROW_HEX := "#7CFF3A"
const REROLL_ICON_H := 0.9

## The gate's unresolved-bay readout, floating over the lintel while the gate is sealed.
const GATE_LABEL_Y := 5.4

## VERBATIM (FLEET_PACK.md T-001 spec, DESIGN.md section 14): the About plaque text.
## Byte-identical to the disclaimer sentence in README.md, em dash included. The label
## wraps at render time (Label3D width + autowrap); the text itself carries no newlines.
const DISCLAIMER := "VOIDWRAP RUN is a personal, non-commercial project — no money is involved, and it is not affiliated with, endorsed by, or connected to any person, brand, character, or IP referenced or depicted in the game."
const ABOUT_PLAQUE_TEXT := "ABOUT\n\n" + DISCLAIMER

const IntermissionScript := preload("res://sim/intermission.gd")
const NO_SELECT := -1

# ---- view state ----
var lobby: RefCounted = null
var fill_light: OmniLight3D = null
var prompt_text := ""
var gate_vfx: Node3D = null          # the gate's fill plane; colour flips with the state
var _altars: Array = []              # live altar wrappers, one per altar_table() entry
var _holds: Dictionary = {}          # table index -> hold seconds this visit
var _last_stamp: int = -1
var _t: float = 0.0                  # seconds, for the bob
var _colours: Dictionary = {}        # resolved role name -> Color
var _pal: Dictionary = {}            # the resolved palette dict (emission factors)
var _biome_id: String = "" # the biome p_biome_id named at build_all time; "" = act-I biome from content
var _level: int = 0                  # the level p_level named at build_all time
var _sink: Array = []                # [{node: Node3D, t: float}] losing-altar sink runs
var _sinking: Dictionary = {}        # instance_id -> true while the sink owns that node
var _banners: Array = []             # [{bay_index, title, subtitle}] live banner labels
var _flash_t: float = 0.0            # the pick flare's remaining time
var _flash_bay: int = -1             # the bay the flare belongs to
var _gate_label: Label3D = null      # the sealed-gate readout (unresolved bays)
## Sealed Deals (T-051, view side): the run's curse ledger shape ({"curses_held":
## {curse id: stacks}} - the ledger's "curses" dict is exactly the held shape). While
## no_refunds is held the reroll plinths never draw; an unset state answers neutral,
## the canon plinth.
var _curses_state: Dictionary = {}


## Feeds the run's curse state (view/lobby/lobby_scene.gd build()'s ledger). Rebuilds
## the selectables on the spot so a mid-visit change is visible at once.
func set_curses_state(p_state: Dictionary) -> void:
	_curses_state = p_state
	if lobby != null:
		refresh(lobby)


func _ready() -> void:
	# A real scene parent may call build_all() itself (its own biome choice). Nothing to
	# do before that: headless runs have no _ready at all.
	pass


## The whole build without any hand-placed node. p_api = ContentApi instance,
## p_lobby = an IntermissionScript state, p_biome_id / p_level pick the palette AND the fog
## (DESIGN.md section 11: the hall carries the current biome's fog).
func build_all(p_api: RefCounted, p_lobby: RefCounted, p_biome_id: String = "",
		p_level: int = 0) -> void:
	lobby = p_lobby
	_resolve_colours(p_api, p_biome_id, p_level)
	_hall()
	_props()
	_plaque()
	_icons()
	_gate_build()
	refresh(p_lobby)


## Rebuilds the bay area from the lobby state. Called by build_all() and by tick()
## whenever the state's stamp moved (re-draws, resolved bays, sold offers).
func refresh(p_lobby: RefCounted) -> void:
	lobby = p_lobby
	for w in _altars:
		if is_instance_valid(w["root"]) and not _is_sinking(w["root"]):
			w["root"].free()
	_altars = []
	_holds = {}
	if lobby != null:
		var table: Array = lobby.altar_table()
		var slots := _bay_slots(lobby)
		for i in table.size():
			_altars.append(_build_selectable(lobby, i, int(table[i]["bay_index"]),
					int(table[i]["altar"]), str(table[i]["kind"]), slots))
	_last_stamp = lobby.stamp if lobby != null else _last_stamp
	_banner_refresh(lobby)
	_gate_refresh()


## Scheduled bay -> bay-x slot index. One bay takes the centre, two take left and
## right (DESIGN.md section 11); three take the hall in order.
static func _bay_slots(p_lobby: RefCounted) -> Array:
	var n := (p_lobby.bays as Array).size()
	if n == 1:
		return [1]
	if n == 2:
		return [0, 2]
	var out: Array = []
	for i in n:
		out.append(mini(i, 2))
	return out


# ---- palette -------------------------------------------------------------------

func _resolve_colours(p_api: RefCounted, p_biome_id: String, p_level: int) -> void:
	_biome_id = p_biome_id
	_level = p_level
	_pal = FogEnvScript.resolve_palette(p_biome_id, p_level)
	var roles: Dictionary = _pal.get("roles", {})
	if roles.is_empty():
		roles = FogEnvScript.load_palette().get("roles", {})
	_colours = {}
	for r in roles.keys():
		var row: Dictionary = roles[r]
		_colours[str(r)] = Color(str(row.get("hex", "#808080")))


# ---- the hall ------------------------------------------------------------------

func _c(p_role: String, p_fallback: Color = Color(0.3, 0.3, 0.3)) -> Color:
	return _colours.get(p_role, p_fallback)


func _mat(p_role: String, p_emission_scale: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var c := _c(p_role)
	m.albedo_color = c
	var em: float = float(_pal.get("roles", {}).get(p_role, {}).get("emission", 0.0))
	m.emission_enabled = em > 0.0 or p_emission_scale > 0.0
	m.emission = c * maxf(em, p_emission_scale)
	m.emission_energy_multiplier = 1.0
	return m


func _box(p_size: Vector3, p_pos: Vector3, p_role: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = p_size
	mi.mesh = mesh
	mi.material_override = _mat(p_role)
	mi.position = p_pos
	add_child(mi)
	return mi


## The fixed hall: floor + checker, ceiling, four walls with the trim band, the star
## sigil, the fog environment, ambient + player fill light.
func _hall() -> void:
	var base := Vector3(2.0, 2.0, 2.0)   # checker cell (TERRAIN_SPEC checker rule carried over)
	# floor: slab-side base plane, alternating platform_light 2x2 checker tiles on top
	_box(Vector3(HALL_X, 0.5, HALL_Z), Vector3(0.0, -0.25, 0.0), "platform_dark")
	var cells_x := int(HALL_X / base.x)
	var cells_z := int(HALL_Z / base.z)
	for i in cells_x:
		for j in cells_z:
			if (i + j) % 2 == 0:
				continue
			_box(Vector3(base.x, 0.04, base.z),
					Vector3(-HALL_X * 0.5 + (i + 0.5) * base.x, 0.02,
					-HALL_Z * 0.5 + (j + 0.5) * base.z), "platform_light")
	# ceiling
	_box(Vector3(HALL_X, 0.5, HALL_Z), Vector3(0.0, CEIL + 0.25, 0.0), "platform_dark")
	# walls: platform colour slabs, side in slab_side, trim band slab_trim
	var wall_t := 0.5
	_box(Vector3(HALL_X, CEIL, wall_t), Vector3(0.0, CEIL * 0.5, -HALL_Z * 0.5 - wall_t * 0.5), "slab_side")
	_box(Vector3(HALL_X, CEIL, wall_t), Vector3(0.0, CEIL * 0.5, HALL_Z * 0.5 + wall_t * 0.5), "slab_side")
	_box(Vector3(wall_t, CEIL, HALL_Z), Vector3(-HALL_X * 0.5 - wall_t * 0.5, CEIL * 0.5, 0.0), "slab_side")
	_box(Vector3(wall_t, CEIL, HALL_Z), Vector3(HALL_X * 0.5 + wall_t * 0.5, CEIL * 0.5, 0.0), "slab_side")
	# the trim band (top 0.125 u of the slab side)
	_box(Vector3(HALL_X + wall_t * 2.0, 0.125, wall_t + 0.02),
			Vector3(0.0, 2.2, HALL_Z * 0.5 + wall_t * 0.5), "slab_trim")
	_box(Vector3(HALL_X + wall_t * 2.0, 0.125, wall_t + 0.02),
			Vector3(0.0, 2.2, -HALL_Z * 0.5 - wall_t * 0.5), "slab_trim")
	_box(Vector3(wall_t + 0.02, 0.125, HALL_Z),
			Vector3(-HALL_X * 0.5 - wall_t * 0.5, 2.2, 0.0), "slab_trim")
	_box(Vector3(wall_t + 0.02, 0.125, HALL_Z),
			Vector3(HALL_X * 0.5 + wall_t * 0.5, 2.2, 0.0), "slab_trim")
	_sigil()
	_lights()


## The 9 u star sigil (walkway-light colour) on the floor centre: a 5-point star
## built as one flat ArrayMesh fan (deterministic, no imported asset).
func _sigil() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outer := SIGIL_R
	var inner := SIGIL_R * 0.4
	var centre := Vector3(0.0, 0.03, 0.0)
	for i in 10:
		var r := outer if i % 2 == 0 else inner
		var a0: float = -PI / 2.0 + float(i) * PI / 5.0
		var a2: float = -PI / 2.0 + float(i + 1) * PI / 5.0
		var r2 := outer if (i + 1) % 2 == 0 else inner
		st.set_color(_c("walkway_light"))
		st.add_vertex(centre)
		st.set_color(_c("walkway_light"))
		st.add_vertex(centre + Vector3(cos(a0) * r, 0.0, sin(a0) * r))
		st.set_color(_c("walkway_light"))
		st.add_vertex(centre + Vector3(cos(a2) * r2, 0.0, sin(a2) * r2))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	add_child(mi)


func _lights() -> void:
	var fog := FogEnvScript.new()
	fog.biome_id = _biome_id
	fog.configure(_biome_id, _level)
	add_child(fog)
	var amb := OmniLight3D.new()
	amb.light_color = _c("ambient", Color(0.04, 0.23, 0.24))
	amb.light_energy = float(_pal.get("ambient_energy", 1.0)) * 2.0
	amb.omni_range = HALL_X
	amb.position = Vector3(0.0, CEIL - 1.0, 0.0)
	add_child(amb)
	fill_light = OmniLight3D.new()
	fill_light.light_color = _c("player_fill_light", Color(0.75, 1.0, 0.97))
	fill_light.light_energy = 1.2
	fill_light.omni_range = 18.0
	fill_light.position = SPAWN + Vector3(0.0, 1.5, 0.0)
	add_child(fill_light)


## Curse consumer (gap 27): lights_out shrinks the player fill light range to the modified
## stat (op=set, absolute). The lobby spawns no curses, but the setter keeps the hall's fill
## light honest to the same stat the run uses. No-op before _lights() built the light.
func apply_stats(stats: Dictionary) -> void:
	if fill_light == null or not stats.has("fill_light_range"):
		return
	fill_light.omni_range = maxf(0.0, float(stats["fill_light_range"]))


## Procedural props (DESIGN.md section 11: urns, barrels and tall jars along the walls, at
## fixed offsets - a deterministic script build). The shipped T-015 models are used when
## they are present; the box fallback keeps a checkout without the imported assets working.
func _props() -> void:
	var Along: Array = [
		[-12.0, 8.5], [-6.0, 9.0], [-1.5, 9.3], [3.0, 8.9], [12.0, 8.5], [6.0, 9.0],
		[13.0, 5.0], [13.0, -1.0], [-13.0, 5.0], [-13.0, -1.0],
	]
	var kinds: Array = ["urn", "barrel", "jar"]
	for i in Along.size():
		var kind: String = kinds[i % kinds.size()]
		var model := "tall_jar" if kind == "jar" else kind
		var size := Vector3(0.6, 1.0, 0.6) if kind == "urn" else (
				Vector3(0.9, 0.9, 0.9) if kind == "barrel" else Vector3(0.7, 1.2, 0.7))
		var prop := _model("res://assets/models/%s.glb" % model, size,
				"prop_block" if kind != "barrel" else "prop_crate")
		prop.position = Vector3(Along[i][0], 0.0, Along[i][1])
		add_child(prop)


## One shipped .glb prop, or a box of p_fallback_size when the model is not there. The
## returned node's origin is the FLOOR under the prop, so callers place it at y = 0.
func _model(p_path: String, p_fallback_size: Vector3, p_role: String) -> Node3D:
	var holder := Node3D.new()
	var ps: PackedScene = load(p_path) if ResourceLoader.exists(p_path) else null
	if ps == null:
		var mi := MeshInstance3D.new()
		mi.mesh = _box_mesh(p_fallback_size)
		mi.material_override = _mat(p_role)
		mi.position = Vector3(0.0, p_fallback_size.y * 0.5, 0.0)
		holder.add_child(mi)
		return holder
	var inst: Node3D = ps.instantiate()
	_vertex_colour_pass(inst)
	holder.add_child(inst)
	return holder


## The T-015 .glb models carry no material (export_materials="NONE", palette colours ride
## the vertex colours): every surface needs the vertex-colour base pass or it renders
## Godot's default white. Same pass view/gifts_view.gd applies to the gift models.
static func _vertex_colour_pass(p_root: Node3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	var stack: Array = [p_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				mi.set_surface_override_material(s, mat)


## The room icons from the reference art. The green back arrow stands on the left of the
## hall (the pause binding leaves the hall the same way); the cyan reroll ring is built
## over each reroll plinth by _build_selectable, because the sim has one per bay.
func _icons() -> void:
	var arrow := Node3D.new()
	arrow.name = "BackArrow"
	arrow.position = BACK_ARROW_POS
	add_child(arrow)
	var green := Color(BACK_ARROW_HEX)
	var shaft := MeshInstance3D.new()
	shaft.mesh = _box_mesh(Vector3(0.9, 0.22, 0.08))
	shaft.material_override = _flat(green)
	shaft.position = Vector3(0.2, 0.0, 0.0)
	arrow.add_child(shaft)
	var head := MeshInstance3D.new()
	head.mesh = _tri_mesh([Vector3(-0.55, 0.0, 0.0), Vector3(0.05, 0.42, 0.0),
			Vector3(0.05, -0.42, 0.0)])
	head.material_override = _flat(green)
	arrow.add_child(head)


## The reroll ring: a torus in the XY plane (facing the arriving player) with a small
## arrowhead, in the reference art's cyan.
func _reroll_icon(p_parent: Node3D) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = REROLL_ICON_H * 0.30
	torus.outer_radius = REROLL_ICON_H * 0.46
	torus.rings = 24
	torus.ring_segments = 8
	ring.mesh = torus
	ring.material_override = _flat(_c("dead_end_light", Color(0.56, 0.91, 0.88)))
	ring.rotation.x = PI / 2.0
	p_parent.add_child(ring)
	var tip := MeshInstance3D.new()
	var r := REROLL_ICON_H * 0.46
	tip.mesh = _tri_mesh([Vector3(r * 0.55, r * 0.95, 0.0), Vector3(r * 1.15, r * 0.35, 0.0),
			Vector3(r * 0.15, r * 0.35, 0.0)])
	tip.material_override = _flat(_c("dead_end_light", Color(0.56, 0.91, 0.88)))
	p_parent.add_child(tip)


## A flat triangle fan from p_pts (already in the XY plane, facing +z).
func _tri_mesh(p_pts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in p_pts:
		st.add_vertex(p)
	return st.commit()


## An unshaded emissive material in one colour (the icons and the pick flare).
func _flat(p_colour: Color, p_emission: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = p_colour
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = p_emission > 0.0
	m.emission = p_colour * p_emission
	return m


## The About plaque on the south wall, readable up close, disclaimer VERBATIM (section 14).
func _plaque() -> void:
	var board := _box(Vector3(4.2, 2.4, 0.1), Vector3(0.0, 3.2, HALL_Z * 0.5 - 0.06), "prop_block")
	board.set_meta("about", true)
	var label := Label3D.new()
	label.text = ABOUT_PLAQUE_TEXT
	label.font_size = 30
	label.pixel_size = 0.004
	label.width = 1000
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.position = Vector3(0.0, 3.2, HALL_Z * 0.5 - 0.12)
	label.rotation.y = PI
	label.modulate = Color(0.9, 1.0, 1.0)
	add_child(label)


## The Descent Gate at (0, -9.5) in the north wall: the shipped descent_gate.glb (frame +
## door slab as two named nodes) when it is there, else two posts + a lintel + a fill
## plane. The DOOR is the state indicator: dull (beacon_closed) until lobby.gate_open(),
## then white (beacon_open - the beacon's visual language). No timers, no menus. Walk in ->
## next level.
func _gate_build() -> void:
	var g := Node3D.new()
	g.name = "DescentGate"
	g.position = GATE_POS + Vector3(0.0, 0.0, -0.6)
	add_child(g)
	var path := "res://assets/models/descent_gate.glb"
	var ps: PackedScene = load(path) if ResourceLoader.exists(path) else null
	if ps != null:
		var inst: Node3D = ps.instantiate()
		g.add_child(inst)
		_vertex_colour_pass(inst)
		var door := inst.find_child("descent_gate_door", true, false)
		if door is MeshInstance3D:
			gate_vfx = door
			return
	var lp := MeshInstance3D.new()
	lp.mesh = _box_mesh(Vector3(0.6, 4.0, 0.6))
	lp.material_override = _mat("prop_block")
	lp.position = Vector3(-2.3, 2.0, 0.0)
	g.add_child(lp)
	var rp := MeshInstance3D.new()
	rp.mesh = _box_mesh(Vector3(0.6, 4.0, 0.6))
	rp.material_override = _mat("prop_block")
	rp.position = Vector3(2.3, 2.0, 0.0)
	g.add_child(rp)
	var lin := MeshInstance3D.new()
	lin.mesh = _box_mesh(Vector3(5.2, 0.6, 0.6))
	lin.material_override = _mat("prop_block")
	lin.position = Vector3(0.0, 4.3, 0.0)
	g.add_child(lin)
	var fill := MeshInstance3D.new()
	fill.mesh = _box_mesh(Vector3(4.0, 3.6, 0.25))
	fill.material_override = _mat("beacon_closed")
	fill.position = Vector3(0.0, 1.8, 0.0)
	fill.name = "GateFill"
	g.add_child(fill)
	gate_vfx = fill


## Swap the gate between the dull and the open (white, beacon_open) material, and show the
## bays still sealing it (DESIGN.md section 11: the gate opens only when every mandatory
## bay is resolved - the hall says which ones are not).
func _gate_refresh() -> void:
	if lobby == null:
		return
	var open := bool(lobby.gate_open())
	if gate_vfx != null:
		gate_vfx.material_override = _mat("beacon_open" if open else "beacon_closed")
	_gate_label_refresh(open)


## The banner title for a bay kind ("ENEMIES", "CURSES", ...); the kind itself when the
## schedule ever grows a bay this file does not name.
static func _banner_title(p_kind: String) -> String:
	var row: Array = BANNER_TEXT.get(p_kind, [])
	return str(row[0]) if not row.is_empty() else p_kind


## The sealed-gate readout over the lintel: the mandatory bays still open, or nothing once
## the gate is open.
func _gate_label_refresh(p_open: bool) -> void:
	var open_kinds: Array = []
	var has_class_bay := false
	for bay in lobby.bays:
		var kind := str(bay["kind"])
		if kind == "CLASS":
			has_class_bay = true
		if (kind == "E" or kind == "C") and not bool(bay.get("resolved", false)):
			open_kinds.append(_banner_title(kind))
	# The CLASS bay gates only the pre-run lobby (sim/intermission.gd gate_open()).
	if has_class_bay and str(lobby.class_chosen) == "":
		open_kinds.append(_banner_title("CLASS"))
	if p_open or open_kinds.is_empty():
		if _gate_label != null and is_instance_valid(_gate_label):
			_gate_label.visible = false
		return
	if _gate_label == null or not is_instance_valid(_gate_label):
		_gate_label = Label3D.new()
		_gate_label.set_meta("gate_label", true)
		_gate_label.font_size = 34
		_gate_label.pixel_size = 0.008
		_gate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_gate_label.position = Vector3(0.0, GATE_LABEL_Y, GATE_POS.z + 0.6)
		_gate_label.modulate = _c("danger", Color(1.0, 0.16, 0.16))
		add_child(_gate_label)
	_gate_label.text = "THE GATE IS SEALED\n" + " · ".join(open_kinds)
	_gate_label.visible = true


func _box_mesh(p_size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = p_size
	return mesh


## Bay banners: the reference art's lockup - a huge emissive serif title with the italic
## subtitle one line under it - for scheduled bays, nothing for the dark empty slots.
func _banner_refresh(p_lobby: RefCounted) -> void:
	# free previous banner labels (children tagged "bay_banner" / "bay_subtitle")
	for child in get_children():
		if child is Label3D and (child.has_meta("bay_banner") or child.has_meta("bay_subtitle")):
			child.free()
	_banners = []
	if p_lobby == null:
		return
	var slots := _bay_slots(p_lobby)
	for bi in (p_lobby.bays as Array).size():
		var bay: Dictionary = p_lobby.bays[bi]
		var kind := str(bay["kind"])
		var text: Array = BANNER_TEXT.get(kind, [])
		if text.is_empty():
			continue
		var x := float(BAY_X[int(slots[bi])])
		var title := Label3D.new()
		title.set_meta("bay_banner", true)
		title.text = str(text[0])
		title.font_size = TITLE_FONT
		title.pixel_size = TITLE_PIXEL
		title.position = Vector3(x, BANNER_Y, BAY_Z - 2.2)
		title.modulate = _c("dead_end_light", Color(0.56, 0.91, 0.88))
		title.outline_size = 12
		title.outline_modulate = _c("walkway_light", Color(0.23, 0.45, 1.0))
		add_child(title)
		var subtitle := Label3D.new()
		subtitle.set_meta("bay_subtitle", true)
		subtitle.text = str(text[1])
		subtitle.font_size = SUBTITLE_FONT
		subtitle.pixel_size = SUBTITLE_PIXEL
		subtitle.position = Vector3(x, BANNER_Y + SUBTITLE_DY, BAY_Z - 2.2)
		subtitle.modulate = _c("dead_end_light", Color(0.56, 0.91, 0.88))
		add_child(subtitle)
		_banners.append({"bay_index": bi, "title": title, "subtitle": subtitle})


# ---- altars --------------------------------------------------------------------

## One selectable altar (or extra plinth) for altar_table() index i. Returns the
## wrapper {"root", "kind", "bay_kind", "bay_index", "altar", "name", "index", "exhibit",
## "plinth", "glow", "panel"}.
##
## "kind" is the altar_table() row kind ("offer" / "tithe" / "reroll"); "bay_kind" is the
## BAY's kind ("E" / "C" / "U" / "REST" / "CLASS"). The exhibit and the panel both switch
## on the BAY kind - passing the row kind there made every exhibit and every panel read
## "TBD", which is what J7 found and fixed.
func _build_selectable(p_lobby: RefCounted, p_index: int, p_bay_index: int, p_altar: int,
		p_kind: String, p_slots: Array) -> Dictionary:
	var kind := str(p_kind)
	var root := Node3D.new()
	add_child(root)
	# offers sit at the bay's altar row; the extra plinths sit beside the bay
	var bay: Dictionary = p_lobby.bays[p_bay_index]
	var bay_kind := str(bay["kind"])
	var slots := p_slots
	var bx: float = float(BAY_X[int(slots[p_bay_index])])
	var x: float = bx + float(ALTAR_DX[clampi(p_altar, 0, 2)])
	if kind == "tithe":
		x = clampf(bx + PLINTH_DX, -HALL_X * 0.5 + 1.5, HALL_X * 0.5 - 1.5)
	elif kind == "reroll":
		x = clampf(bx - PLINTH_DX, -HALL_X * 0.5 + 1.5, HALL_X * 0.5 - 1.5)
	root.position = Vector3(x, 0.0, BAY_Z)

	var plinth: Node3D = _model("res://assets/models/altar_plinth.glb", PLINTH_SIZE, "prop_block")
	root.add_child(plinth)

	var anchor := Node3D.new()   # the bobbing exhibit anchor
	anchor.position = Vector3(0.0, PLINTH_SIZE.y + EXHIBIT_LIFT, 0.0)
	root.add_child(anchor)

	# The pick flare: an omni that only lights while this bay is the one just picked, so
	# the altar visibly answers the F press even after the state rebuilds the plinths.
	var glow := OmniLight3D.new()
	glow.light_color = _c("dead_end_light", Color(0.56, 0.91, 0.88))
	glow.light_energy = 0.0
	glow.omni_range = 4.0
	glow.position = Vector3(0.0, PLINTH_SIZE.y + 0.6, 0.0)
	root.add_child(glow)

	var wrap := {"root": root, "kind": kind, "bay_kind": bay_kind,
			"bay_index": p_bay_index, "altar": p_altar,
			"name": "", "index": p_index, "exhibit": anchor, "flash": 0.0,
			"plinth": plinth, "glow": glow, "panel": null}
	if kind != "tithe" and kind != "reroll":
		var altar: Dictionary = {}
		if p_altar >= 0 and p_altar < (bay["altars"] as Array).size():
			altar = (bay["altars"] as Array)[p_altar]
		wrap["name"] = _exhibit(wrap, anchor, altar)
	elif kind == "reroll":
		_reroll_icon(anchor)
	wrap["panel"] = _panel(wrap, altar_details(p_lobby, p_bay_index, p_altar, bay_kind),
			root.position)
	# Sealed Deals (T-051): while the run holds the curse the reroll plinth never
	# draws (reroll_plinth_visible() false, held_stacks 0 = neutral true). The panel is
	# root's child, so one visible flag covers the whole plinth. The wrapper STAYS in
	# _altars: altar_table()'s indices must keep their Select addresses.
	if kind == "reroll" and not NoRefundsScript.reroll_plinth_visible(_curses_state):
		(wrap["root"] as Node3D).visible = false
	return wrap


## Builds the exhibit for one offer; returns the display name ("TBD" fallback included).
## Switches on the BAY kind (see _build_selectable's note).
func _exhibit(p_wrap: Dictionary, p_anchor: Node3D, p_altar: Dictionary) -> String:
	var kind := str(p_wrap.get("bay_kind", ""))
	if kind == "E":
		return _exhibit_enemy(p_anchor, p_altar)
	if kind == "C":
		return _exhibit_icon(p_anchor, _c("danger", Color(1, 0.16, 0.16)), str(p_altar.get("name", "")))
	if kind == "U" or kind == "REST":
		return _exhibit_icon(p_anchor, Color(0.1, 0.9, 0.85), str(p_altar.get("id", "")))
	if kind == "CLASS":
		return _exhibit_class(p_anchor, str(p_altar.get("id", "")))
	return "TBD"


## Enemy exhibit: the enemy's ACTUAL billboarded PNG sprite (view/billboard.gd), real
## frames from its sprites.json, body scaled to 1.6 u.
func _exhibit_enemy(p_anchor: Node3D, p_altar: Dictionary) -> String:
	var eid := str(p_altar.get("id", ""))
	var name := eid
	var sheet_path := "res://content/enemies/%s/sprites.json" % eid
	var bb = BillboardScript.new()
	p_anchor.add_child(bb)
	var parsed: Variant = null
	if FileAccess.file_exists(sheet_path):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(sheet_path))
	if parsed is Dictionary and not (parsed as Dictionary).is_empty():
		bb.setup_from_sheet(parsed, "res://content/enemies/" + eid)
		# scale the sheet's own world_height up to the exhibit body height.
		# A sheet may declare the key with a JSON null (nuke does), and .get() only
		# falls back to its default when the key is ABSENT - so float(null) would
		# throw "Nonexistent 'float' constructor" and abort this function on every
		# lobby build. Type-check the value instead of trusting the default.
		var raw_h: Variant = (parsed as Dictionary).get("world_height", 1.0)
		var doc_h: float = float(raw_h) if typeof(raw_h) in [TYPE_INT, TYPE_FLOAT] else 1.0
		var k: float = ENEMY_BODY_H / maxf(doc_h, 0.01)
		bb.scale = bb.scale * k
		bb.world_height = ENEMY_BODY_H
		name = str((parsed as Dictionary).get("name", eid))
	else:
		bb.world_height = ENEMY_BODY_H
		name = "TBD"
	return name


## Curse / upgrade exhibit: an icon billboard (1.2 u) with the pink / aqua border frame.
func _exhibit_icon(p_anchor: Node3D, p_border: Color, p_name: String) -> String:
	var border := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2(ICON_H, ICON_H)
	border.mesh = quad
	var m := StandardMaterial3D.new()
	m.albedo_color = p_border
	border.material_override = m
	p_anchor.add_child(border)
	var face := MeshInstance3D.new()
	var face_q := PlaneMesh.new()
	face_q.size = Vector2(ICON_H * 0.72, ICON_H * 0.72)
	face.mesh = face_q
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.02, 0.06, 0.07)
	face.material_override = fm
	face.position = Vector3(0.0, 0.0, 0.01)
	p_anchor.add_child(face)
	return p_name


## Class exhibit: the player model in that class's colours (a capsule stand-in:
## the player model itself arrives with the app scene ticket; colour = palette role).
func _exhibit_class(p_anchor: Node3D, p_class: String) -> String:
	var roles: Array = ["walkway_light", "dead_end_light", "platform_light"]
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.height = 1.7
	cap.radius = 0.35
	mi.mesh = cap
	mi.material_override = _mat(roles[abs(hash(p_class)) % roles.size()], 0.2)
	p_anchor.add_child(mi)
	return p_class


## The panel text lines for one selectable (world-space, 2.4 u wide, above the exhibit).
func altar_details(p_lobby: RefCounted, p_bay_index: int, p_altar: int,
		p_kind: String) -> Array:
	var bay: Dictionary = p_lobby.bays[p_bay_index]
	if p_altar < 0:
		if p_kind == "tithe":
			var cost: int = OffersSim.tithe_cost(int(p_lobby.tithes), p_lobby.content)
			return ["PAY THE TITHE", "Walk past - no curse taken.", "Cost: %d g" % cost]
		var rc: int = OffersSim.reroll_cost(int(bay.get("rerolls_used", 0)), p_lobby.content)
		return ["REROLL", "Re-draw this bay.",
				"Free once" if str(bay["kind"]) == "C" else "Cost: %d g" % rc]
	var altar: Dictionary = (bay["altars"] as Array)[p_altar]
	match str(p_kind):
		"E":
			var lines: Array = [str(altar.get("name", "TBD"))]
			var sheet: Dictionary = _enemy_doc(str(altar.get("id", "")))
			lines.append(str(sheet.get("behavior", "Behavior: TBD (enemy wave pending)")))
			if str(sheet.get("tell", "")) != "":
				lines.append(str(sheet.get("tell")))
			lines.append(str(sheet.get("counter_play", "")))
			lines.append("In play: x%d" % int(altar.get("votes", 0)))
			return lines
		"C":
			var c: Dictionary = p_lobby.content.curse(str(altar.get("id", "")))
			return [
				str(altar.get("name", "")),
				str(c.get("rule", "")),
				str(c.get("counter_play", "")),
				"Bounty: %d g (%s, stacks %d)" % [int(altar.get("bounty", 0)),
						str(altar.get("severity", "")).to_upper(), int(altar.get("stacks", 0))],
			]
		"U", "REST":
			var u: Dictionary = p_lobby.content.upgrade(str(altar.get("id", "")))
			return [
				str(u.get("name", str(altar.get("id", "")))),
				str(u.get("effect", "")),
				"Price: %d g   Owned: %d/max %d" % [int(altar.get("price", 0)),
						int(altar.get("stacks", 0)), int(u.get("max_stacks", 1))],
			]
		"CLASS":
			return [str(altar.get("name", "")), "Choose who falls."]
	return ["TBD"]


func _enemy_doc(p_id: String) -> Dictionary:
	if lobby == null or lobby.content == null:
		return {}
	return lobby.content.enemy(p_id)


## The description panel for one selectable (world-space, 2.4 u wide, above the exhibit).
## It starts HIDDEN: the hall shows the panel of the altar the player is standing at and
## looking at, and hides it again when they walk away (DESIGN.md section 11's interaction
## rule - the reference art shows exactly one name at a time).
func _panel(p_wrap: Dictionary, p_lines: Array, _p_world: Vector3) -> Label3D:
	var label := Label3D.new()
	var text := ""
	for line in p_lines:
		if str(line) != "":
			text += ("" if text == "" else "\n") + str(line)
	label.text = text
	label.font_size = 26
	label.pixel_size = 0.006
	label.width = int(PANEL_W / 0.006)  # 2.4 u wide at this pixel_size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector3(0.0, PLINTH_SIZE.y + EXHIBIT_LIFT + 1.1, 0.0)
	label.set_meta("panel", true)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.visible = false
	(p_wrap["root"] as Node3D).add_child(label)
	return label


# ---- interaction: prompt, F-hold, tick -----------------------------------------

## One frame. p_player_pos / p_look_dir are the walk player's; p_interact_held gates
## the F-hold. The bob, the sink of losing altars and the gate colour run here.
## Returns {"select": altar_table index or NO_SELECT (one confirm, then it resets
## until the next hold), "prompt": ">name" when an altar is in range+focus}.
## The Select goes to the caller, who feeds it into IntermissionScript.step() - the
## antechamber NEVER writes the sim state directly.
func tick(p_dt: float, p_player_pos: Vector3, p_look_dir: Vector3,
		p_interact_held: bool) -> Dictionary:
	_t += p_dt
	var out := {"select": NO_SELECT, "prompt": ""}
	if lobby != null:
		if int(lobby.stamp) != _last_stamp:
			refresh(lobby)
		out = _interaction(p_dt, p_player_pos, p_look_dir, p_interact_held)
	for a in _altars:
		var anchor: Node3D = a["exhibit"]
		if is_instance_valid(anchor):
			anchor.position.y = PLINTH_SIZE.y + EXHIBIT_LIFT \
					+ BOB_AMP * sin(TAU * BOB_HZ * _t)
	_glow_pass(p_dt)
	_sink_advance(p_dt)
	_gate_refresh()
	return out


## The pick flare: the picked bay's plinths and banner glow for FLASH_S, then fade. Keyed
## by BAY INDEX rather than by node, so it survives the state rebuild a pick triggers.
func _glow_pass(p_dt: float) -> void:
	if _flash_t > 0.0:
		_flash_t = maxf(_flash_t - p_dt, 0.0)
	var k: float = _flash_t / FLASH_S
	for a in _altars:
		var glow: OmniLight3D = a.get("glow")
		if glow != null and is_instance_valid(glow):
			glow.light_energy = GLOW_ENERGY * k if int(a["bay_index"]) == _flash_bay else 0.0
	for b in _banners:
		var title: Label3D = b["title"]
		if title != null and is_instance_valid(title):
			var lit: bool = int(b["bay_index"]) == _flash_bay and k > 0.0
			title.modulate = Color(1.0, 1.0, 1.0) if lit \
					else _c("dead_end_light", Color(0.56, 0.91, 0.88))


## Only the prompted altar shows its description panel; every other one hides it.
func _panel_pass(p_best: int) -> void:
	for a in _altars:
		var panel: Label3D = a.get("panel")
		if panel != null and is_instance_valid(panel):
			panel.visible = int(a["index"]) == p_best


func _interaction(p_dt: float, p_player_pos: Vector3, p_look_dir: Vector3,
		p_interact_held: bool) -> Dictionary:
	var out := {"select": NO_SELECT, "prompt": ""}
	var best := -1
	var best_d: float = PROMPT_R
	var look := p_look_dir.normalized()
	for a in _altars:
		var root: Node3D = a["root"]
		var to_a: Vector3 = root.position - p_player_pos
		to_a.y = 0.0
		var d := to_a.length()
		if d > PROMPT_R or d < 1e-6:
			_holds[int(a["index"])] = 0.0
			continue
		if to_a.normalized().dot(look) < LOOK_COS:
			_holds[int(a["index"])] = 0.0
			continue
		if d < best_d:
			best_d = d
			best = int(a["index"])
	_panel_pass(best)
	if best < 0:
		return out
	for a in _altars:
		if int(a["index"]) == best:
			out["prompt"] = "[F] Choose - %s" % str(a.get("name", ""))
			# the radial fill is the hold progress itself; the flare is the confirm
			var h: float = float(_holds.get(best, 0.0))
			if p_interact_held:
				h += p_dt
				if h >= HOLD_S and out["select"] == NO_SELECT and int(a.get("fired", 0)) == 0:
					h = 0.0
					a["fired"] = 1
					out["select"] = best
					_fire(a)
			else:
				h = 0.0
				a["fired"] = 0
			_holds[best] = h
	return out


## On confirm: the altar flares (the bay's plinths and banner glow for FLASH_S); in a
## mandatory bay the other altars sink into the floor over 0.6 s (an E x2 bay's state
## re-draws at once, so the new draw rises on the next stamp refresh).
func _fire(p_wrap: Dictionary) -> void:
	p_wrap["flash"] = 0.25
	_flash_t = FLASH_S
	_flash_bay = int(p_wrap["bay_index"])
	var bay: Dictionary = lobby.bays[int(p_wrap["bay_index"])]
	var kind := str(bay["kind"])
	if kind == "E" or kind == "C" or kind == "CLASS":
		for a in _altars:
			if a != p_wrap and int(a["bay_index"]) == int(p_wrap["bay_index"]) \
					and str(a["kind"]) == "offer":
				_sink.append({"node": a["root"], "t": 0.0})
				# The sink owns the node until it lands: refresh() must not free it out
				# from under the animation (the pick bumps the stamp, so refresh() runs on
				# the very next tick).
				_sinking[(a["root"] as Node3D).get_instance_id()] = true


## True while the sink animation owns p_node (refresh() leaves it alone).
func _is_sinking(p_node: Node3D) -> bool:
	return _sinking.has(p_node.get_instance_id())


func _sink_advance(p_dt: float) -> void:
	var keep: Array = []
	for s in _sink:
		var node_v: Variant = s["node"]
		s["t"] = float(s["t"]) + p_dt
		if node_v == null or not is_instance_valid(node_v):
			continue   # already gone: drop the run rather than touch a freed instance
		var node: Node3D = node_v
		var k: float = clampf(float(s["t"]) / SINK_S, 0.0, 1.0)
		node.position.y = -k * (PLINTH_SIZE.y + 0.6)
		if float(s["t"]) >= SINK_S:
			_sinking.erase(node.get_instance_id())
			node.free()
			continue
		keep.append(s)
	_sink = keep


func _process(p_dt: float) -> void:
	# In-tree convenience: callers that never call tick() directly still get the idle
	# animation; the prompt/hold path stays caller-driven (tick() is the tested path).
	tick(p_dt, SPAWN, Vector3(0.0, 0.0, -1.0), false)
