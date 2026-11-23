extends Node3D
class_name BankaiGiftAnimation
## Bare Godot 4 (3D / GDScript) "Senbonzakura Kageyoshi" Sakura-Gift Bankai Animation.
## Attach as a child of your Player node (at local Vector3.ZERO, player's feet).
## Call `play()` or `play(target_node)` to trigger the 25.5s sequence.

signal animation_started
signal phase_changed(phase_index: int)
## Fires at 21.0s, 21.9s and 22.8s. `target` is NULL when no target was passed or set
## (the swarm then hits the fallback point 12m ahead): handlers must check is_instance_valid().
signal target_hit(target: Node3D)
signal animation_finished

const TOTAL_DURATION: float = 25.5
const TICK_RATE := 60.0
const IMPACT_TICK := 750
const IMPACT_TIME := IMPACT_TICK / TICK_RATE
const WORLD_SWORD_TIP_Y := 1.15
const CueAudio := preload("res://view/audio/cue_audio.gd")
const BankaiAudio := preload("res://view/audio/bankai_audio.gd")
const DROP_POINT: Vector3 = Vector3(0.0, 0.0, -0.78)
## The owner's own voice line, shipped with this file but NOT wired in anywhere. To use it:
##   senbonzakura_voice = load(CUSTOM_VOICE_PATH)   (or assign it in the Inspector)
const CUSTOM_VOICE_PATH: String = "res://view/cinematics/custom_voiceline.mp3"
const GIFT_COUNT: int = 1400
const SCRAP_COUNT: int = 54

## Optional: Your player's first-person camera (restored automatically when finished).
@export var fps_camera: Camera3D
## Optional: Your third-person player mesh (hidden during FP phases, shown in TP phases).
@export var player_model: Node3D
## Optional: Pool of targets to pick from randomly if none is passed to play().
@export var targets: Array[Node3D] = []
## Toggle built-in placeholder FPS hands off if your player already has viewmodel arms.
@export var show_fps_hands: bool = true
## Play automatically on _ready() for quick testing.
@export var auto_play: bool = false
## Optional: Real anime voiceline clips (drag .mp3 / .wav / .ogg in Inspector).
@export var bankai_voice: AudioStream
@export var senbonzakura_voice: AudioStream

var hit_tick := 1290
var arena_bounds := Rect2()
var externally_clocked := false
var is_playing: bool = false
var sim_time: float = 0.0
var _current_phase: int = -1
var _locked_target: Node3D = null
var _fallback_target_local: Vector3 = Vector3(0.0, 0.0, -12.0)
var _prev_camera: Camera3D = null
var _fired_events: Dictionary = {}
var _player_was_visible := false
var _cue_players: Dictionary = {}
var _clock_tick := 0
var _tick_fraction := 0.0

# Internal nodes
var _anim_cam: Camera3D
var _fps_rig: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _gift_group: Node3D
var _gift_left_half: Node3D
var _gift_right_half: Node3D
var _gift_bow: Node3D
var _fps_sword: Node3D
var _world_sword: Node3D
var _water_mesh: MeshInstance3D
var _water_mat: ShaderMaterial
var _scrap_mm: MultiMesh
var _gift_box_mm: MultiMesh
var _gift_ribbon_mm: MultiMesh
var _gift_bow_mm: MultiMesh
var _giant_blades: Array[Dictionary] = []
var _voice_player: AudioStreamPlayer
var _voice_player2: AudioStreamPlayer

# Particle seeds
var _scrap_seeds: Array[Dictionary] = []
var _gift_seeds: Array[Dictionary] = []

const ZERO_XFORM := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)


func _ready() -> void:
	_ensure_built()
	if auto_play:
		play()


## The procedural rig is normally built by _ready(), which does not run when the node is
## not in a tree - headless, or a test that drives the cinematic directly. Build on demand
## so play() works either way; the guard makes a second call a no-op.
func _ensure_built() -> void:
	if _anim_cam != null:
		return
	_build_camera_and_fps_rig()
	_build_water_ripple_mesh()
	_build_giant_blades()
	_build_gift_swarm()
	_build_voice_player()
	_set_all_visuals_visible(false)


## VIEW-ONLY: the clock is elapsed time expressed in cinematic ticks.
## Starts the Bankai animation. Pass a specific target, or leave null to pick randomly from `targets`.
func play(target_override: Node3D = null) -> void:
	_ensure_built()
	_locked_target = target_override
	if _locked_target == null:
		var valid: Array[Node3D] = []
		for t in targets:
			if is_instance_valid(t):
				valid.append(t)
		if valid.size() > 0:
			_locked_target = valid[randi() % valid.size()]

	if is_playing:
		# Replaying: end the running one cleanly so the player's own camera is restored first.
		stop()
	# get_viewport() is null when the node is not in a tree (headless, tests). The cinematic
	# still plays - it just has no camera to restore afterwards.
	var vp := get_viewport()
	_prev_camera = fps_camera if is_instance_valid(fps_camera) else (vp.get_camera_3d() if vp != null else null)
	_anim_cam.current = true

	sim_time = 0.0
	_clock_tick = 0
	_tick_fraction = 0.0
	_current_phase = -1
	_fired_events.clear()
	is_playing = true
	if is_instance_valid(player_model):
		_player_was_visible = player_model.visible
	_voice_player.stream = bankai_voice if bankai_voice != null else CueAudio.load_stream(CUSTOM_VOICE_PATH)
	_voice_player2.stream = senbonzakura_voice
	_check_events(0)
	_set_all_visuals_visible(true)
	_update_animation(0.0)
	animation_started.emit()


func stop() -> void:
	is_playing = false
	_voice_player.stop()
	_voice_player2.stop()
	for cue in _cue_players.values():
		cue.stop()
	_set_all_visuals_visible(false)
	if is_instance_valid(player_model):
		player_model.visible = _player_was_visible
	if is_instance_valid(_prev_camera):
		_prev_camera.current = true
	_anim_cam.current = false


## Arena events run on the fight clock. Render updates interpolate within the tick.
func sync_tick(tick: int) -> void:
	if not is_playing or tick <= _clock_tick:
		return
	_clock_tick = tick
	_tick_fraction = 0.0
	sim_time = tick / TICK_RATE
	_check_events(tick)
	if sim_time >= TOTAL_DURATION:
		_finish()


func _process(delta: float) -> void:
	if not is_playing:
		return
	if externally_clocked:
		_tick_fraction = minf(_tick_fraction + delta * TICK_RATE, 1.0)
		sim_time = (_clock_tick + _tick_fraction) / TICK_RATE
	else:
		sim_time += minf(delta, 5.0 / TICK_RATE)
		_check_events(floori(sim_time * TICK_RATE + 0.000001))
		if sim_time >= TOTAL_DURATION - 0.000001:
			_finish()
			return
	_update_animation(sim_time)


func _finish() -> void:
	sim_time = TOTAL_DURATION
	stop()
	animation_finished.emit()


# ==============================================================================
# PROCEDURAL BARE ASSET BUILDERS
# ==============================================================================

func _build_camera_and_fps_rig() -> void:
	_anim_cam = Camera3D.new()
	_anim_cam.fov = 60.0
	_anim_cam.near = 0.05
	_anim_cam.far = 200.0
	add_child(_anim_cam)

	_fps_rig = Node3D.new()
	_anim_cam.add_child(_fps_rig)

	# Minimal FPS hands (can be disabled via `show_fps_hands = false`)
	_left_arm = _create_fps_arm(-1.0)
	_right_arm = _create_fps_arm(1.0)
	_fps_rig.add_child(_left_arm)
	_fps_rig.add_child(_right_arm)

	# Wrapped sword-gift (0.95 x 0.13 x 0.13)
	_gift_group = Node3D.new()
	_fps_rig.add_child(_gift_group)

	var paper_mat := StandardMaterial3D.new()
	paper_mat.albedo_color = Color(0.095, 0.055, 0.155)
	paper_mat.roughness = 0.42
	paper_mat.metallic = 0.35

	var ribbon_mat := StandardMaterial3D.new()
	ribbon_mat.albedo_color = Color(1.0, 0.475, 0.753)
	ribbon_mat.emission_enabled = true
	ribbon_mat.emission = Color(0.5, 0.1, 0.32)
	ribbon_mat.emission_energy_multiplier = 0.7
	ribbon_mat.roughness = 0.25

	_gift_left_half = Node3D.new()
	_gift_right_half = Node3D.new()
	_gift_group.add_child(_gift_left_half)
	_gift_group.add_child(_gift_right_half)

	_add_box(_gift_left_half, Vector3(0.475, 0.13, 0.13), Vector3(-0.2375, 0, 0), paper_mat)
	_add_box(_gift_left_half, Vector3(0.48, 0.136, 0.028), Vector3(-0.2375, 0, 0), ribbon_mat)
	_add_box(_gift_left_half, Vector3(0.48, 0.028, 0.136), Vector3(-0.2375, 0, 0), ribbon_mat)

	_add_box(_gift_right_half, Vector3(0.475, 0.13, 0.13), Vector3(0.2375, 0, 0), paper_mat)
	_add_box(_gift_right_half, Vector3(0.48, 0.136, 0.028), Vector3(0.2375, 0, 0), ribbon_mat)
	_add_box(_gift_right_half, Vector3(0.48, 0.028, 0.136), Vector3(0.2375, 0, 0), ribbon_mat)

	_gift_bow = Node3D.new()
	_gift_group.add_child(_gift_bow)
	_add_box(_gift_bow, Vector3(0.036, 0.14, 0.14), Vector3.ZERO, ribbon_mat)
	for side in [-1.0, 1.0]:
		var loop := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.024
		torus.outer_radius = 0.044
		loop.mesh = torus
		loop.material_override = ribbon_mat
		loop.position = Vector3(side * 0.032, 0.09, 0.0)
		loop.rotation = Vector3(PI * 0.5, 0.0, -side * 0.45)
		_gift_bow.add_child(loop)

	# FPS & World-space Zanpakuto
	_fps_sword = _create_zanpakuto(0.82)
	_fps_rig.add_child(_fps_sword)

	_world_sword = _create_zanpakuto(1.0)
	add_child(_world_sword)

	# Paper scraps MultiMesh
	var scrap_mmi := MultiMeshInstance3D.new()
	_scrap_mm = MultiMesh.new()
	_scrap_mm.transform_format = MultiMesh.TRANSFORM_3D
	_scrap_mm.instance_count = SCRAP_COUNT
	var quad := QuadMesh.new()
	quad.size = Vector2(0.075, 0.055)
	_scrap_mm.mesh = quad
	var scrap_mat := StandardMaterial3D.new()
	scrap_mat.albedo_color = Color(1.0, 0.53, 0.78)
	scrap_mat.emission_enabled = true
	scrap_mat.emission = Color(0.4, 0.08, 0.25)
	scrap_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	scrap_mmi.multimesh = _scrap_mm
	scrap_mmi.material_override = scrap_mat
	_fps_rig.add_child(scrap_mmi)

	for i in SCRAP_COUNT:
		_scrap_seeds.append({
			"vel": Vector3(randf_range(-1.1, 1.1), randf_range(0.35, 1.8), randf_range(-0.75, 0.75)),
			"rot": Vector3(randf_range(-5.5, 5.5), randf_range(-5.5, 5.5), randf_range(-5.5, 5.5)),
			"scale": randf_range(0.6, 1.5)
		})


func _create_fps_arm(side: float) -> Node3D:
	var arm := Node3D.new()
	var sleeve_mat := StandardMaterial3D.new()
	sleeve_mat.albedo_color = Color(0.086, 0.06, 0.14)
	var cuff_mat := StandardMaterial3D.new()
	cuff_mat.albedo_color = Color(1.0, 0.47, 0.75)
	cuff_mat.emission_enabled = true
	cuff_mat.emission = Color(0.45, 0.08, 0.28)
	var glove_mat := StandardMaterial3D.new()
	glove_mat.albedo_color = Color(0.13, 0.1, 0.2)

	_add_box(arm, Vector3(0.095, 0.095, 0.44), Vector3(0, 0, 0.22), sleeve_mat)
	_add_box(arm, Vector3(0.102, 0.102, 0.035), Vector3(0, 0, 0.02), cuff_mat)
	_add_box(arm, Vector3(0.088, 0.075, 0.115), Vector3(0, 0, -0.055), glove_mat)
	_add_box(arm, Vector3(0.028, 0.032, 0.06), Vector3(-side * 0.048, 0.02, -0.05), glove_mat)
	return arm


func _create_zanpakuto(s: float) -> Node3D:
	var sword := Node3D.new()

	var handle_mat := StandardMaterial3D.new()
	handle_mat.albedo_color = Color(0.16, 0.08, 0.22)

	var wrap_mat := StandardMaterial3D.new()
	wrap_mat.albedo_color = Color(1.0, 0.52, 0.77)
	wrap_mat.emission_enabled = true
	wrap_mat.emission = Color(0.3, 0.05, 0.18)

	var gold_mat := StandardMaterial3D.new()
	gold_mat.albedo_color = Color(0.9, 0.76, 0.48)
	gold_mat.metallic = 0.88
	gold_mat.roughness = 0.28

	var blade_mat := StandardMaterial3D.new()
	blade_mat.albedo_color = Color(0.96, 0.93, 0.97)
	blade_mat.metallic = 0.95
	blade_mat.roughness = 0.12
	blade_mat.emission_enabled = true
	blade_mat.emission = Color(1.0, 0.62, 0.82)
	blade_mat.emission_energy_multiplier = 0.2

	_add_box(sword, Vector3(0.032, 0.32, 0.022) * s, Vector3(0, -0.16 * s, 0), handle_mat)
	for i in 6:
		var band := _add_box(sword, Vector3(0.035, 0.018, 0.026) * s, Vector3(0, (-0.04 - i * 0.046) * s, 0), wrap_mat)
		band.rotation.z = 0.18

	_add_box(sword, Vector3(0.036, 0.025, 0.028) * s, Vector3(0, -0.33 * s, 0), gold_mat)
	_add_box(sword, Vector3(0.095, 0.016, 0.068) * s, Vector3(0, 0.005 * s, 0), gold_mat)
	_add_box(sword, Vector3(0.034, 0.04, 0.024) * s, Vector3(0, 0.032 * s, 0), gold_mat)
	_add_box(sword, Vector3(0.026, 0.96, 0.009) * s, Vector3(0, 0.53 * s, 0), blade_mat)

	var tip := MeshInstance3D.new()
	var prism := CylinderMesh.new()
	prism.top_radius = 0.0
	prism.bottom_radius = 0.017 * s
	prism.height = 0.14 * s
	prism.radial_segments = 4
	tip.mesh = prism
	tip.material_override = blade_mat
	tip.position = Vector3(0, 1.08 * s, 0)
	tip.rotation.y = PI * 0.25
	tip.scale = Vector3(1.0, 1.0, 0.42)
	sword.add_child(tip)

	return sword


func _build_water_ripple_mesh() -> void:
	_water_mesh = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(5.4, 5.4)
	plane.subdivide_width = 72
	plane.subdivide_depth = 72
	_water_mesh.mesh = plane
	_water_mesh.position = Vector3(DROP_POINT.x, 0.015, DROP_POINT.z)

	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

uniform float sim_t = 0.0;
uniform float water_alpha = 0.0;

float single_wave(float r, float t, float t0, float amp, float spd, float freq, float edge_fade) {
	float dt = t - t0;
	if (dt <= 0.0) return 0.0;
	float wf = dt * spd;
	if (r >= wf) return 0.0;
	float behind = wf - r;
	float damp = exp(-r * 0.85) * exp(-dt * 0.52) * exp(-behind * 0.45);
	return sin(r * freq - dt * 11.0) * amp * damp * edge_fade;
}

float wave_height(vec2 p, float t) {
	float r = length(p);
	if (r > 2.65) return 0.0;
	float edge_fade = 1.0 - smoothstep(1.85, 2.65, r);
	float y = 0.0;
	// 3 submergence impulses: blade tip (9.2s), mid-blade (10.3s), tsuba (11.35s)
	y += single_wave(r, t, 9.2,  0.095, 1.55, 11.5, edge_fade);
	y += single_wave(r, t, 10.3, 0.075, 1.45, 10.2, edge_fade);
	y += single_wave(r, t, 11.35, 0.065, 1.35, 9.4, edge_fade);
	return y;
}

void vertex() {
	vec2 p = VERTEX.xz;
	float h = wave_height(p, sim_t);
	VERTEX.y += h;

	float eps = 0.04;
	float hx = wave_height(p + vec2(eps, 0.0), sim_t);
	float hz = wave_height(p + vec2(0.0, eps), sim_t);
	NORMAL = normalize(vec3(h - hx, eps, h - hz));
}

void fragment() {
	vec2 p = (UV - 0.5) * 5.4;
	float r = length(p);
	float edge = 1.0 - smoothstep(1.75, 2.65, r);
	float crest = clamp(abs(wave_height(p, sim_t)) * 18.0, 0.0, 1.0);

	ALBEDO = vec3(0.07, 0.035, 0.12);
	METALLIC = 0.92;
	ROUGHNESS = 0.06;
	EMISSION = mix(vec3(0.22, 0.04, 0.16), vec3(1.0, 0.55, 0.82), crest) * (0.45 + crest * 1.4);
	ALPHA = water_alpha * edge * 0.92;
}
"""
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = shader
	_water_mesh.material_override = _water_mat
	add_child(_water_mesh)


func _build_giant_blades() -> void:
	for i in 10:
		var side: float = -1.0 if i < 5 else 1.0
		var row_idx: int = i % 5
		var z_pos: float = -1.8 - row_idx * 2.15
		var x_pos: float = side * (2.55 + row_idx * 0.16)

		var blade_group := Node3D.new()
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 0.94, 0.98, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.38, 0.71)
		mat.emission_energy_multiplier = 0.8
		mat.metallic = 0.85
		mat.roughness = 0.12

		_add_box(blade_group, Vector3(0.55, 6.2, 0.11), Vector3(0, 3.1, 0), mat)

		var tip := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.38
		cone.height = 1.35
		cone.radial_segments = 4
		tip.mesh = cone
		tip.material_override = mat
		tip.position = Vector3(0, 6.85, 0)
		tip.rotation.y = PI * 0.25
		tip.scale = Vector3(1.0, 1.0, 0.25)
		blade_group.add_child(tip)

		blade_group.position = Vector3(x_pos, -7.8, z_pos)
		blade_group.rotation.y = side * 0.18
		add_child(blade_group)

		_giant_blades.append({
			"node": blade_group,
			"mat": mat,
			"base_x": x_pos,
			"base_z": z_pos,
			"delay": row_idx * 0.16
		})


func _build_gift_swarm() -> void:
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.115, 0.115, 0.115)
	var box_mat := StandardMaterial3D.new()
	box_mat.albedo_color = Color(1.0, 0.56, 0.78)
	box_mat.emission_enabled = true
	box_mat.emission = Color(0.85, 0.17, 0.53)
	box_mat.emission_energy_multiplier = 0.65
	box_mat.roughness = 0.28

	var ribbon_mesh := BoxMesh.new()
	ribbon_mesh.size = Vector3(0.124, 0.026, 0.124)
	var ribbon_mat := StandardMaterial3D.new()
	ribbon_mat.albedo_color = Color(1.0, 0.91, 0.96)
	ribbon_mat.emission_enabled = true
	ribbon_mat.emission = Color(1.0, 0.7, 0.86)
	ribbon_mat.emission_energy_multiplier = 0.7

	var bow_mesh := SphereMesh.new()
	bow_mesh.radius = 0.032
	bow_mesh.height = 0.064
	bow_mesh.radial_segments = 4
	bow_mesh.rings = 2
	var bow_mat := StandardMaterial3D.new()
	bow_mat.albedo_color = Color(1.0, 0.94, 0.97)
	bow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_gift_box_mm = _create_multimesh_child(box_mesh, box_mat, GIFT_COUNT)
	_gift_ribbon_mm = _create_multimesh_child(ribbon_mesh, ribbon_mat, GIFT_COUNT)
	_gift_bow_mm = _create_multimesh_child(bow_mesh, bow_mat, GIFT_COUNT)

	for i in GIFT_COUNT:
		var b: Dictionary = _giant_blades[i % 10]
		_gift_seeds.append({
			"origin": Vector3(
				b["base_x"] + randf_range(-0.32, 0.32),
				randf_range(0.4, 6.8),
				b["base_z"] + randf_range(-0.32, 0.32)
			),
			"orbit_radius": randf_range(2.2, 6.6),
			"orbit_angle": randf_range(0.0, TAU),
			"orbit_speed": (1.0 if randf() > 0.5 else -1.0) * randf_range(1.2, 3.1),
			"orbit_y": randf_range(0.65, 5.45),
			"wave_phase": randf_range(0.0, TAU),
			"attack_delay": randf_range(0.0, 0.45),
			"vortex_radius": randf_range(0.25, 1.85),
			"spin_speed": randf_range(2.0, 7.0),
			"scale": randf_range(0.68, 1.4)
		})


func _build_voice_player() -> void:
	# Two players so the 12.5s line never cuts off the 7.8s line.
	_voice_player = AudioStreamPlayer.new()
	add_child(_voice_player)
	_voice_player2 = AudioStreamPlayer.new()
	add_child(_voice_player2)
	for cue in BankaiAudio.CUES:
		_cue_players[cue] = BankaiAudio.make_player(self, cue)


func _create_multimesh_child(mesh: Mesh, mat: Material, count: int) -> MultiMesh:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = count
	mm.mesh = mesh
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.extra_cull_margin = 50.0
	add_child(mmi)
	return mm


func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _set_all_visuals_visible(vis: bool) -> void:
	_fps_rig.visible = vis
	_world_sword.visible = false
	_water_mesh.visible = vis
	for b in _giant_blades:
		b["node"].visible = false
	if not vis:
		for i in SCRAP_COUNT:
			_scrap_mm.set_instance_transform(i, ZERO_XFORM)
		for i in GIFT_COUNT:
			_gift_box_mm.set_instance_transform(i, ZERO_XFORM)
			_gift_ribbon_mm.set_instance_transform(i, ZERO_XFORM)
			_gift_bow_mm.set_instance_transform(i, ZERO_XFORM)


# ==============================================================================
# TIMELINE EVENTS (VOICELINES & TARGET HIT SIGNALS)
# ==============================================================================

func _check_events(tick: int) -> void:
	var t := tick / TICK_RATE
	var phase := 0
	if t >= 20.0: phase = 5
	elif t >= 16.5: phase = 4
	elif t >= IMPACT_TIME: phase = 3
	elif t >= 7.2: phase = 2
	elif t >= 3.8: phase = 1

	if phase != _current_phase:
		_current_phase = phase
		phase_changed.emit(phase)

	_play_at("hum", tick, 0, _cue_players["hum"])
	_play_at("charge", tick, 612, _cue_players["charge"])
	_play_at("impact", tick, IMPACT_TICK, _cue_players["impact"])
	_play_at("volley", tick, 1200, _cue_players["volley"])
	_play_at("voice1", tick, 468, _voice_player)
	_play_at("voice2", tick, 750, _voice_player2)
	if _play_at("kill", tick, hit_tick, _cue_players["kill"]):
		target_hit.emit(_locked_target)


func _play_at(key: String, tick: int, start_tick: int, player: AudioStreamPlayer) -> bool:
	if tick < start_tick or _fired_events.has(key):
		return false
	_fired_events[key] = true
	if player.stream != null and is_inside_tree():
		player.play()
	return true


# ==============================================================================
# MASTER ANIMATION UPDATE (t in [0.0, 25.5])
# ==============================================================================

func _update_animation(t: float) -> void:
	var is_fp := t < IMPACT_TIME or (externally_clocked and _clock_tick < IMPACT_TICK)
	_fps_rig.visible = is_fp
	_left_arm.visible = show_fps_hands
	_right_arm.visible = show_fps_hands

	var target_local: Vector3 = _fallback_target_local
	if is_instance_valid(_locked_target) and is_inside_tree() and _locked_target.is_inside_tree():
		target_local = to_local(_locked_target.global_position)

	_anim_cam.transform = _camera_pose(t, target_local)
	if is_instance_valid(player_model):
		# Reveal the avatar once its head clears the near plane during the pull-back.
		player_model.visible = not is_fp and _anim_cam.position.length_squared() > 3.6

	# 2. FIRST-PERSON PHASES (1: Inspect, 2: Unwrap & Reveal, 3: Slow Water Drop)
	if is_fp:
		if t < 3.8:
			var p := t / 3.8
			_gift_group.visible = true
			_fps_sword.visible = false
			_world_sword.visible = false

			_gift_left_half.position = Vector3.ZERO
			_gift_left_half.rotation = Vector3.ZERO
			_gift_right_half.position = Vector3.ZERO
			_gift_right_half.rotation = Vector3.ZERO
			_gift_bow.visible = true
			_gift_bow.position = Vector3.ZERO
			_gift_bow.rotation = Vector3.ZERO

			var sway_x := sin(t * 2.2) * 0.02
			var sway_y := cos(t * 3.1) * 0.015
			var yaw := sin(p * TAU) * 0.42
			var roll := sin(p * PI * 3.0) * 0.28
			var pitch := sin(p * PI) * 0.18

			_gift_group.position = Vector3(0.02 + sway_x, -0.29 + sway_y, -1.04)
			_gift_group.rotation = Vector3(pitch, yaw, roll)

			_left_arm.position = Vector3(-0.34 + sway_x, -0.35 + sway_y, -0.96)
			_left_arm.rotation = Vector3(0.18, 0.25 + yaw * 0.3, -0.1)
			_right_arm.position = Vector3(0.36 + sway_x, -0.34 + sway_y, -0.96)
			_right_arm.rotation = Vector3(0.18, -0.25 + yaw * 0.3, 0.1)

		elif t < 7.2:
			var p := (t - 3.8) / 3.4
			_world_sword.visible = false

			var bow_pull := smoothstep(0.0, 0.22, p)
			var split_p := smoothstep(0.16, 0.48, p)
			var sword_rev := smoothstep(0.24, 0.62, p)
			var flourish_p := smoothstep(0.55, 1.0, p)

			_gift_group.visible = split_p < 0.98
			_gift_group.position = Vector3(0.02, -0.29, -1.04)
			_gift_group.rotation = Vector3(0.08, 0.0, 0.0)

			_gift_bow.visible = bow_pull < 0.95
			_gift_bow.position = Vector3(-bow_pull * 0.35, bow_pull * 0.24, bow_pull * 0.12)
			_gift_bow.rotation.z = bow_pull * 1.4

			_gift_left_half.position = Vector3(-split_p * 0.95, -split_p * 0.35, -split_p * 0.2)
			_gift_left_half.rotation = Vector3(split_p * 0.7, -split_p * 0.9, split_p * 1.2)
			_gift_right_half.position = Vector3(split_p * 0.95, -split_p * 0.35, -split_p * 0.2)
			_gift_right_half.rotation = Vector3(-split_p * 0.6, split_p * 0.9, -split_p * 1.2)

			_fps_sword.visible = sword_rev > 0.02
			var s_scale := lerpf(0.5, 1.0, _ease_out_back(sword_rev))
			_fps_sword.scale = Vector3.ONE * s_scale
			_fps_sword.position = Vector3(
				lerpf(0.02, 0.34, flourish_p),
				lerpf(-0.30, -0.32, flourish_p),
				lerpf(-1.04, -0.94, flourish_p)
			)
			_fps_sword.rotation = Vector3(
				lerpf(0.15, -0.22, flourish_p),
				lerpf(0.0, -0.35, flourish_p),
				lerpf(PI * 0.5, 0.26, _ease_out_cubic(sword_rev))
			)

			_left_arm.position = Vector3(
				lerpf(-0.34, -0.52, bow_pull),
				lerpf(-0.35, -0.24 - flourish_p * 0.28, bow_pull),
				lerpf(-0.96, -0.86, bow_pull)
			)
			_right_arm.position = Vector3(
				lerpf(0.36, 0.34, flourish_p),
				lerpf(-0.34, -0.38, flourish_p),
				lerpf(-0.96, -0.88, flourish_p)
			)

		else:
			_gift_group.visible = false
			var p := (t - 7.2) / 5.5
			var extend_p := smoothstep(0.0, 0.22, p)
			var released := t >= 8.75

			_left_arm.position = Vector3(-0.56, -0.58, -0.82)

			if not released:
				_fps_sword.visible = true
				_world_sword.visible = false
				_fps_sword.scale = Vector3.ONE
				_fps_sword.position = Vector3(
					lerpf(0.34, 0.0, extend_p),
					lerpf(-0.32, -0.18, extend_p),
					lerpf(-0.94, -0.78, extend_p)
				)
				_fps_sword.rotation = Vector3(
					lerpf(-0.22, 0.0, extend_p),
					lerpf(-0.35, 0.0, extend_p),
					lerpf(0.26, PI, _ease_in_out_cubic(extend_p))
				)
				_right_arm.position = Vector3(
					lerpf(0.34, 0.12, extend_p),
					lerpf(-0.38, -0.22, extend_p),
					lerpf(-0.88, -0.74, extend_p)
				)
			else:
				_fps_sword.visible = false
				_world_sword.visible = true
				var drop_p := clampf((t - 8.75) / (IMPACT_TIME - 8.75), 0.0, 1.0)
				var sword_y := lerpf(1.48, WORLD_SWORD_TIP_Y, _ease_in_out_cubic(drop_p))
				_world_sword.position = Vector3(DROP_POINT.x, sword_y, DROP_POINT.z)
				_world_sword.rotation = Vector3(0.0, drop_p * 0.22, PI)

				var pull_back := smoothstep(8.75, 9.8, t)
				_right_arm.position = Vector3(
					lerpf(0.12, 0.32, pull_back),
					lerpf(-0.22, -0.34, pull_back),
					lerpf(-0.74, -0.64, pull_back)
				)
	else:
		_world_sword.visible = t < 16.5
		var settle := smoothstep(IMPACT_TIME, IMPACT_TIME + 0.2, t)
		_world_sword.position = Vector3(DROP_POINT.x, WORLD_SWORD_TIP_Y - 0.12 * settle, DROP_POINT.z)
		_world_sword.rotation = Vector3(0.0, 0.22, PI)

	# 3. FLYING PAPER SCRAPS (4.1s -> 6.9s)
	if is_fp and t >= 4.1 and t <= 6.9:
		var dts := t - 4.1
		var fade := clampf(1.0 - dts / 2.6, 0.0, 1.0)
		for i in SCRAP_COUNT:
			var s: Dictionary = _scrap_seeds[i]
			var vel: Vector3 = s["vel"]
			var rot: Vector3 = s["rot"]
			var pos := Vector3(
				vel.x * dts * 0.65,
				-0.28 + vel.y * dts * 0.55 - 0.55 * dts * dts,
				-1.02 + vel.z * dts * 0.5
			)
			var b := Basis.from_euler(rot * dts).scaled(Vector3.ONE * (s["scale"] * fade))
			_scrap_mm.set_instance_transform(i, Transform3D(b, pos))
	else:
		for i in SCRAP_COUNT:
			_scrap_mm.set_instance_transform(i, ZERO_XFORM)

	# 4. WATER RIPPLE SHADER (9.0s -> 15.2s)
	var water_alpha := smoothstep(9.0, 9.6, t) * (1.0 - smoothstep(13.8, 15.2, t))
	_water_mesh.visible = water_alpha > 0.005
	if _water_mesh.visible:
		_water_mat.set_shader_parameter("sim_t", t)
		_water_mat.set_shader_parameter("water_alpha", water_alpha)

	# 5. GIANT BANKAI BLADES (12.8s -> 17.7s)
	var shatter_p := smoothstep(16.5, 17.6, t)
	for b in _giant_blades:
		var node: Node3D = b["node"]
		var mat: StandardMaterial3D = b["mat"]
		if t >= 12.8 and t <= 17.7:
			var rise_p := _ease_out_cubic((t - (12.9 + b["delay"])) / 1.35)
			node.visible = rise_p > 0.005 and shatter_p < 0.99
			node.position.y = lerpf(-7.8, 0.0, rise_p)
			mat.albedo_color.a = 1.0 - shatter_p
			mat.emission_energy_multiplier = 0.8 + shatter_p * 2.2
		else:
			node.visible = false

	# 6. 1,400 TINY SAKURA-PINK WRAPPED GIFTS SWARM (16.5s -> 25.5s)
	if t >= 16.5:
		var dissolve_p := _ease_out_cubic(smoothstep(16.5, 18.0, t))
		var fade_in := smoothstep(16.5, 16.95, t)
		for i in GIFT_COUNT:
			var gp: Dictionary = _gift_seeds[i]
			var orb_ang: float = gp["orbit_angle"] + (t - 16.5) * gp["orbit_speed"]
			var orb_pos := Vector3(
				cos(orb_ang) * gp["orbit_radius"],
				gp["orbit_y"] + sin(t * 2.4 + gp["wave_phase"]) * 0.45,
				-3.0 + sin(orb_ang) * gp["orbit_radius"]
			)
			var gpos: Vector3 = gp["origin"].lerp(orb_pos, dissolve_p)

			if t >= 20.0:
				var local_p := _ease_in_out_cubic(clampf((t - (20.0 + gp["attack_delay"])) / 1.15, 0.0, 1.0))
				var swirl_ang := orb_ang + (t - 20.0) * 6.5
				var tight_r := lerpf(gp["vortex_radius"] * 1.4, 0.35 + float(i % 7) * 0.11, local_p)
				var t_pos := Vector3(
					target_local.x + cos(swirl_ang) * tight_r,
					maxf(0.22, 1.25 + sin(swirl_ang * 1.3 + gp["wave_phase"]) * (0.65 + (1.0 - local_p) * 1.2)),
					target_local.z + sin(swirl_ang) * tight_r
				)
				gpos = gpos.lerp(t_pos, local_p)

			var sc: float = gp["scale"] * fade_in
			var rot := Vector3(t * gp["spin_speed"] + gp["wave_phase"], t * gp["spin_speed"] * 0.8, 0.0)
			var gbasis := Basis.from_euler(rot).scaled(Vector3.ONE * sc)
			var xf := Transform3D(gbasis, gpos)
			_gift_box_mm.set_instance_transform(i, xf)
			_gift_ribbon_mm.set_instance_transform(i, xf)
			_gift_bow_mm.set_instance_transform(i, Transform3D(gbasis, gpos + Vector3(0.0, 0.068 * sc, 0.0)))
	else:
		for i in GIFT_COUNT:
			_gift_box_mm.set_instance_transform(i, ZERO_XFORM)
			_gift_ribbon_mm.set_instance_transform(i, ZERO_XFORM)
			_gift_bow_mm.set_instance_transform(i, ZERO_XFORM)


func _camera_pose(t: float, target_local: Vector3) -> Transform3D:
	var eye := Vector3(cos(t * 1.3) * 0.008, 1.66 + sin(t * 2.1) * 0.012, 0.0)
	var pitch := -0.83 * smoothstep(8.2, 10.6, t)
	var first_person := Transform3D(Basis(Vector3.RIGHT, pitch), eye)
	if t <= IMPACT_TIME:
		return first_person

	var pull := smoothstep(IMPACT_TIME, 17.0, t)
	var orbit := smoothstep(IMPACT_TIME, TOTAL_DURATION, t)
	var angle := lerpf(-0.52, 0.94, orbit)
	var trailing := Vector3(sin(angle) * 7.0, 2.6 + 1.0 * orbit, cos(angle) * 7.0)
	var cam_pos := eye.lerp(trailing, pull)
	if arena_bounds.has_area() and is_inside_tree():
		var world_pos := to_global(cam_pos)
		world_pos.x = clampf(world_pos.x, arena_bounds.position.x, arena_bounds.end.x)
		world_pos.z = clampf(world_pos.z, arena_bounds.position.y, arena_bounds.end.y)
		cam_pos = to_local(world_pos)
	var focus := Vector3(0.0, 1.05, 0.0).lerp(target_local, lerpf(0.12, 0.36, pull))
	var orbit_basis := Basis.looking_at(focus - cam_pos, Vector3.UP)
	return Transform3D(first_person.basis.slerp(orbit_basis, pull), cam_pos)


# ==============================================================================
# EASING HELPERS
# ==============================================================================

func _ease_out_cubic(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - c, 3.0)


func _ease_in_out_cubic(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return 4.0 * c * c * c if c < 0.5 else 1.0 - pow(-2.0 * c + 2.0, 3.0) * 0.5


func _ease_out_back(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(c - 1.0, 3.0) + c1 * pow(c - 1.0, 2.0)
