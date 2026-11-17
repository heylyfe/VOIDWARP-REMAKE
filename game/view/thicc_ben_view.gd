extends Node3D
#
# thicc ben view (ticket T-032; DESIGN.md section 5.3 / ENEMIES.md "Bell" / T-083 anim block
# section 1.3). Renders ben - and never writes sim state:
#
#   - the BODY: the T-016 TBD frame billboarded (Y-axis facing, view/billboard.gd),
#     body scaled to the sheet's world_height (4.0 u);
#   - the TELEGRAPH: black smoke stands at the LOCKED DESTINATION for 75 ticks
#     (1.25 s): 24 dark puffs #031A1B, 1.2 u wide, rising ~2 u (anim block
#     `telegraph.effect.params`); ben's own sprite fades alpha 1 -> 0 over the
#     first 30 ticks at the OLD position (anim block, same params);
#   - the CHIME: in the last 30 ticks (0.5 s) the smoke pulses red TWICE and the
#     Westminster cue fires once at tick TELEGRAPH - CHIME_TAIL = 45
#     (hook: thicc_ben_audio "teleport_chime");
#   - the ARRIVAL (tick 75): ben reappears at full alpha + a 6-tick white flash
#     (anim block `attack_arrival`, 6 ticks);
#   - the RING (on touch, anim block `attack_ring`): 18 ticks - the sprite rocks
#     +/-8 degrees twice and a flat ring wave expands to 8 u over 18 ticks
#     (the cleanse radius); the "touch_bell" cue fires on the touch;
#   - the spawn fade: 30 ticks, alpha 0 -> 1, scale 0.8 -> 1.0 (anim block `spawn`
#     common fade).
#
# TIMINGS ARE READ FROM THE SHEET'S ANIM BLOCK (sprites.json `anim`) when it loads -
# this file transcribes nothing except as fallback defaults (identical numbers, T-083);
# the anim block is the single source of truth. View-layer only: nothing here
# touches sim state.
#
# Caller contract (the engine/app loop wires it later):
#   var v := ThiccBenView.new(); add_child(v); v.setup()
#   # per sim tick, with rt.step()'s events array:
#   v.on_events(events)      # "telegraph" (kind "teleport") starts the smoke; "screen_blur" the touch
#   v.sync(row)              # the ben row dict (x/y/z) - call after the sim tick so the teleport shows
#   v.advance(dt_ticks)      # 1 at 60 Hz

const BillboardScript := preload("res://view/billboard.gd")
const AudioScript := preload("res://view/audio/thicc_ben_audio.gd")

# Fallbacks only - used when the sheet's anim block cannot be read.
const TELEGRAPH_TICKS_FB := 75
const CHIME_TAIL_TICKS_FB := 30
const ARRIVAL_FLASH_TICKS_FB := 6
const RING_TICKS_FB := 18
const RING_MAX_U_FB := 8.0
const SPAWN_FADE_TICKS_FB := 30
const SMOKE_PUFFS := 24
const SMOKE_COLOR := Color(0.012, 0.102, 0.106)   # #031A1B from the anim block
const SMOKE_WIDTH_U := 1.2
const SMOKE_RISE_U := 2.0
const BEN_ID := "thicc_ben"

var sheet: Dictionary = {}
var billboard = null   # view/billboard.gd instance (untyped: its props are dynamic-typed here)
var _smoke: CPUParticles3D = null
var _smoke_mat: StandardMaterial3D = null
var _ring: MeshInstance3D = null
var _ring_mat: StandardMaterial3D = null
var _flash_ticks := 0           # remaining white-flash ticks
var _ring_t := -1.0             # ring run, ticks elapsed; -1 = inactive
var _phase := "idle"            # idle | telegraph
var _phase_t := 0
var _spawn_t := -1.0            # spawn fade run; -1 = done (fade starts at setup/birth)
var _chime_fired := false
var _base_scale := 1.0
var _flash_ticks_total := ARRIVAL_FLASH_TICKS_FB
var _telegraph_total := TELEGRAPH_TICKS_FB
var _chime_tail := CHIME_TAIL_TICKS_FB
var _ring_ticks := RING_TICKS_FB
var _ring_max_u := RING_MAX_U_FB
var _spawn_fade := SPAWN_FADE_TICKS_FB
var _smoke_on := false


## The smoke emitter flip must be guarded by the tree: CPUParticles3D's emitting
## setter walks the global transform, which errors (and returns identity) when the
## node is outside a scene tree (e.g. headless tests). The flag is authoritative;
## the tree sync happens here, inside the tree.
func _sync_smoke() -> void:
	if _smoke != null and _smoke.is_inside_tree():
		_smoke.emitting = _smoke_on


## Loads the sheet + builds the billboard, the smoke emitter and the ring. folder_dir
## is the res:// path of the enemy folder. Returns false when the sheet cannot be
## parsed (the body still renders, never a crash).
func setup(folder_dir: String = "res://content/enemies/thicc_ben") -> bool:
	var doc: Variant = null
	var f := FileAccess.open(folder_dir.path_join("sprites.json"), FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			doc = parsed
	billboard = BillboardScript.new()
	if doc is Dictionary:
		sheet = doc
		_read_anim_block(doc)
		billboard.setup_from_sheet(sheet, folder_dir)
	else:
		billboard.world_height = 4.0
	add_child(billboard)
	_base_scale = billboard.scale.y
	_smoke = _make_smoke()
	_smoke_on = false
	add_child(_smoke)
	_ring = _make_ring()
	_ring.visible = false
	add_child(_ring)
	_spawn_t = 0.0
	_set_alpha(0.0)
	return not sheet.is_empty()


## Point the billboard at the row's world position (feet at the origin). Call
## after the sim tick so the teleport is visible on arrival.
func sync(row: Dictionary) -> void:
	position = Vector3(float(row.get("x", 0.0)), float(row.get("y", 0.0)), float(row.get("z", 0.0)))


## Consume one tick's events. The sim raises "telegraph" (kind "teleport") at smoke
## start and "screen_blur" on the touch (the bell + the ring). Everything else is
## ignored.
func on_events(events: Array) -> void:
	for e in events:
		var kind := str(e.get("e", ""))
		if kind == "telegraph" and str(e.get("kind", "")) == "teleport" \
				and str(e.get("source", BEN_ID)) == BEN_ID:
			_start_telegraph(e.get("shape", {}))
		elif kind == "screen_blur":
			_start_ring()
		elif kind == "enemy_spawn" and str(e.get("id", "")) == BEN_ID:
			_spawn_t = 0.0
			_set_alpha(0.0)


## One 60 Hz tick: advances the spawn fade, the telegraph (smoke + fade + chime +
## flash), and the ring.
func advance(ticks: int) -> void:
	var dt := float(maxi(ticks, 0))
	_advance_spawn(dt)
	if _phase == "telegraph":
		_phase_t += maxi(ticks, 0)
		_advance_telegraph()
	elif _flash_ticks > 0:
		_flash_ticks = maxi(_flash_ticks - maxi(ticks, 0), 0)
		_set_flash(_flash_ticks > 0)
	_advance_ring(dt)


# ---- telegraph: smoke, fade, chime, arrival --------------------------------

func _start_telegraph(shape: Dictionary) -> void:
	_phase = "telegraph"
	_phase_t = 0
	_chime_fired = false
	var sx := float(shape.get("cx", 0.0))
	var sz := float(shape.get("cz", 0.0))
	var sy := float(shape.get("y0", position.y))
	# ben stays at the old position (fading out); the smoke stands at the destination
	_smoke.position = Vector3(sx - position.x, sy - position.y + 0.2, sz - position.z)
		# child-local: assumes this node's transform is world-aligned (documented contract)
	_smoke_on = true
	_sync_smoke()


func _advance_telegraph() -> void:
	# ben's own sprite fades alpha 1 -> 0 over the first 30 ticks at the old position
	_set_alpha(1.0 - clampf(float(_phase_t) / float(maxi(_chime_tail, 1)), 0.0, 1.0))
	# chime at tick 45 (the last 30 ticks of the cue): smoke pulses red twice
	var chime_at := _telegraph_total - _chime_tail
	if _phase_t >= chime_at and not _chime_fired:
		_chime_fired = true
		AudioScript.play_cue(self, "teleport_chime")
	if _chime_fired and _smoke_mat != null:
		var p := float(_phase_t - chime_at)
		var half := float(_chime_tail) * 0.5
		var on := (p >= 0.0 and p < 6.0) or (p >= half and p < half + 6.0)
		_smoke_mat.albedo_color = Color(0.75, 0.07, 0.07) if on else SMOKE_COLOR
	if _phase_t >= _telegraph_total:
		_arrive()


func _arrive() -> void:
	_phase = "idle"
	_phase_t = 0
	_smoke_on = false
	_sync_smoke()
	_smoke_mat.albedo_color = SMOKE_COLOR
	_flash_ticks = _flash_ticks_total
	_set_flash(true)


func _set_alpha(a: float) -> void:
	if billboard == null:
		return
	var m = billboard.modulate
	m.a = clampf(a, 0.0, 1.0)
	billboard.modulate = m


func _set_flash(on: bool) -> void:
	if billboard == null:
		return
	# white flash: over-bright modulate (Sprite3D modulate multiplies albedo)
	billboard.modulate = Color(4.0, 4.0, 4.0, 1.0) if on else Color(1.0, 1.0, 1.0, 1.0)


# ---- spawn fade --------------------------------------------------------------

func _advance_spawn(dt: float) -> void:
	if _spawn_t < 0.0:
		return
	_spawn_t += dt
	var k := clampf(_spawn_t / float(maxi(_spawn_fade, 1)), 0.0, 1.0)
		# alpha 0 -> 1, scale 0.8 -> 1.0 (anim block spawn, the common fade)
	if _flash_ticks == 0:
		_set_alpha(k)
	if billboard != null:
		var s := _base_scale * lerpf(0.8, 1.0, k)
		billboard.scale = Vector3(s, s, s)
	if k >= 1.0:
		_spawn_t = -1.0


# ---- the ring (on touch) ------------------------------------------------------

func _start_ring() -> void:
	_ring_t = 0.0
	_ring.visible = true
	AudioScript.play_cue(self, "touch_bell")


func _advance_ring(dt: float) -> void:
	if _ring_t < 0.0:
		return
	_ring_t += dt
	var k := clampf(_ring_t / float(maxi(_ring_ticks, 1)), 0.0, 1.0)
	var r := lerpf(0.5, _ring_max_u, k)
	_ring.scale = Vector3(r, 1.0, r)
	_ring.position = Vector3(0.0, 0.15, 0.0)
	_ring_mat.albedo_color = Color(1.0, 0.16, 0.16, 0.5 * (1.0 - k))
	# the rock: +/-8 degrees twice inside the 18 ticks (anim block attack_ring)
	if billboard != null:
		billboard.rotation.z = sin(k * TAU * 2.0) * deg_to_rad(8.0) if k < 1.0 else 0.0
	if k >= 1.0:
		_ring_t = -1.0
		_ring.visible = false
		if billboard != null:
			billboard.rotation.z = 0.0


# ---- builders -----------------------------------------------------------------

func _make_smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = SMOKE_PUFFS
	p.lifetime = float(_telegraph_total) / 60.0
	p.one_shot = false
	p.explosiveness = 0.0
	p.direction = Vector3(0.0, 1.0, 0.0)
	p.initial_velocity_min = SMOKE_RISE_U / p.lifetime
	p.initial_velocity_max = (SMOKE_RISE_U + 0.6) / p.lifetime
	p.spread = 18.0
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.7
	_smoke_mat = StandardMaterial3D.new()
	_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_smoke_mat.albedo_color = SMOKE_COLOR
	_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p.material_override = _smoke_mat
	var mesh := SphereMesh.new()
	mesh.radius = SMOKE_WIDTH_U * 0.5
	mesh.height = SMOKE_WIDTH_U
	p.mesh = mesh
	return p


func _make_ring() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 0.05
	cyl.radial_segments = 48
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.albedo_color = Color(1.0, 0.16, 0.16, 0.5)
	mi.material_override = _ring_mat
	mi.mesh = cyl
	return mi


# ---- the anim block -------------------------------------------------------------

func _read_anim_block(doc: Dictionary) -> void:
	var anim: Variant = doc.get("anim", {})
	if not (anim is Dictionary):
		return
	var states: Variant = (anim as Dictionary).get("states", {})
	if not (states is Dictionary):
		return
	var s: Dictionary = states
	_telegraph_total = _state_int(s, "telegraph", "total_ticks", TELEGRAPH_TICKS_FB)
	_flash_ticks_total = _effect_int(s, "attack_arrival", "ticks", ARRIVAL_FLASH_TICKS_FB)
	_ring_ticks = _state_int(s, "attack_ring", "total_ticks", RING_TICKS_FB)
	_ring_max_u = _effect_num(s, "attack_ring", "ring_max_u", RING_MAX_U_FB)
	_spawn_fade = _state_int(s, "spawn", "total_ticks", SPAWN_FADE_TICKS_FB)


static func _state_int(states: Dictionary, key: String, field: String, fallback: int) -> int:
	var st: Variant = states.get(key, {})
	if st is Dictionary and (st as Dictionary).get(field, null) != null:
		return int((st as Dictionary)[field])
	return fallback


static func _effect_int(states: Dictionary, key: String, field: String, fallback: int) -> int:
	return int(_effect_num(states, key, field, float(fallback)))


static func _effect_num(states: Dictionary, key: String, field: String, fallback: float) -> float:
	var st: Variant = states.get(key, {})
	if st is Dictionary:
		var eff: Variant = (st as Dictionary).get("effect", {})
		if eff is Dictionary:
			var params: Variant = (eff as Dictionary).get("params", {})
			if params is Dictionary and (params as Dictionary).get(field, null) != null:
				return float((params as Dictionary)[field])
	return fallback
