extends Node3D
#
# gift Larper view (ticket T-036; ENEMIES.md hard rules; DESIGN.md section 5.7; the T-083
# anim block in sprites.json). View layer only: reads sim EVENTS (mine_detonated etc.) and
# the sim tick counter the caller passes to step(), never writes sim state, never a wall clock.
#
# Wired to the anim block (sprites.json -> anim, section 1.7):
#   spawn             RENDERED AS NOTHING - "present from level start; no fade, no scaling"
#   idle              5-frame cycle stepped by ticks: 48 ticks per frame, 240 ticks = 1 rev /
#                     4.0 s (the section 3.3 binding turn; D-T021-6 [CONTESTABLE] on fps)
#   telegraph         NO animation - "its tell is the look, within 12 u"; sync(eye) gates the
#                     pink emitter on the 12.0 u tell ramp (inclusive boundary, D-T021-6)
#   attack_detonation 18 TOTAL ticks on the contact tick: white flash + pink->black burst to
#                     3.0 u (the anim block's attack_detonation effect)
#   defused           24 TOTAL ticks: grey out, drop 0.5 u, fade to alpha 0, 'pff' puff; the
#                     sprite hides at the end; NO blast (the anim block's defused effect)
#
# The frame step is tick-driven (step(dt_ticks)); the billboard's own _process is disabled and
# this file re-aims the face every frame itself (BILLBOARDING: the PNG always faces the viewer).
# The frame set is the T-016 TBD placeholder for the real tripine.png (TBD.md rows 7 / 40);
# dropping the real art in changes nothing here.

const BillboardScript := preload("res://view/billboard.gd")
const GiftLarperAudioScript := preload("res://view/audio/gift_larper_audio.gd")

const DEFUSE_GREY := 0.55          # modulate greys to this at the end of the defused window

var billboard: Sprite3D = null
var anim: Dictionary = {}
var world_height := 1.0

var _frame_ticks := 48
var _frames := 5
var _tell_range := 12.0
var _particles_per_second := 12
var _particle_color := Color(1.0, 0.309804, 0.847059)   # #FF4FD8 (section 3.3)
var _detonation_ticks := 18
var _defused_ticks := 24
var _defuse_drop := 0.5
var _burst_radius := 3.0
var _burst_from := Color(1.0, 0.309804, 0.847059)
var _burst_to := Color(0.0, 0.0, 0.0)

var _anim_ticks := 0               # sim ticks since setup (drives the 240-tick revolution)
var _det_left := 0
var _def_left := 0
var _base_y := 0.0
var _burst: MeshInstance3D = null
var _emitter: CPUParticles3D = null
var _puff: CPUParticles3D = null


## Parses sprites.json, builds the billboarded PNG sprite (BILLBOARDING + TRANSPARENCY via
## billboard.gd, unchanged) and caches the anim-block effect parameters (read from the block,
## never hard-coded). folder_dir is the enemy folder's res:// path.
func setup(folder_dir: String = "res://content/enemies/gift_larper") -> void:
	var text := FileAccess.get_file_as_string(folder_dir.path_join("sprites.json"))
	var doc: Variant = JSON.parse_string(text)
	if not (doc is Dictionary):
		push_warning("gift_larper_view: sprites.json unreadable at %s" % folder_dir)
		doc = {}
	anim = (doc as Dictionary).get("anim", {})
	var states: Dictionary = anim.get("states", {})
	world_height = float((doc as Dictionary).get("world_height", 1.0))
	var idle_fx: Dictionary = ((states.get("idle", {})).get("effect", {})).get("params", {})
	var tel_fx: Dictionary = ((states.get("telegraph", {})).get("effect", {})).get("params", {})
	var det_fx: Dictionary = ((states.get("attack_detonation", {})).get("effect", {})).get("params", {})
	var def_fx: Dictionary = ((states.get("defused", {})).get("effect", {})).get("params", {})
	_frame_ticks = int((states.get("idle", {})).get("ticks_per_frame", 48.0))
	_frames = (states.get("idle", {})).get("frames", []).size()
	_tell_range = float(tel_fx.get("tell_range_u", 12.0))
	_particles_per_second = int(idle_fx.get("particles_per_second", 12))
	_particle_color = Color(str(idle_fx.get("particle_color", "#FF4FD8")))
	_detonation_ticks = int((states.get("attack_detonation", {})).get("total_ticks", 18))
	_defused_ticks = int((states.get("defused", {})).get("total_ticks", 24))
	_defuse_drop = float(def_fx.get("drop_u", 0.5))
	_burst_radius = float(det_fx.get("burst_radius_u", 3.0))
	_burst_from = Color(str(det_fx.get("burst_color_from", "#FF4FD8")))
	_burst_to = Color(str(det_fx.get("burst_color_to", "#000000")))
	billboard = BillboardScript.new()
	billboard.set_process(false)   # this file drives frames (ticks) + facing; billboard's own
	add_child(billboard)           #   _process would wall-clock the 5-frame cycle
	billboard.setup_from_sheet(doc, folder_dir)
	billboard.world_height = world_height
	_base_y = billboard.position.y
	_burst = _build_burst()
	_emitter = _build_emitter()
	_puff = _build_puff()
	_burst.visible = false
	_puff.emitting = false
	add_child(_burst)
	add_child(_emitter)
	add_child(_puff)


## The spawn state renders NOTHING (present from level start - no fade, no scaling); the
## call resets the node for a fresh level: visible again, white modulate, no offsets.
func on_spawn() -> void:
	_anim_ticks = 0
	_det_left = 0
	_def_left = 0
	if billboard != null:
		billboard.visible = true
		billboard.modulate = Color(1.0, 1.0, 1.0, 1.0)
		billboard.position.y = _base_y
		billboard.set_animation("cycle")
	if _burst != null:
		_burst.visible = false


## The detonation begins on the contact tick (the mines.gd ladder reached step 4): 18 TOTAL
## ticks of white flash + pink->black burst to 3.0 u, and the explosion hook fires.
func on_detonation() -> void:
	_det_left = _detonation_ticks
	if _burst != null:
		_burst.visible = true
	GiftLarperAudioScript.play(self, GiftLarperAudioScript.CUE_EXPLOSION)


## The defuse begins when the ladder's step 1 passes (a defused or shielded mine): 24 TOTAL
## ticks of grey-out + 0.5 u drop + fade + the 'pff' puff. NO blast. Shows the defused pose
## (sprites/defused_00.png - deflated + desaturated), not the idle frame.
func on_defused() -> void:
	_def_left = _defused_ticks
	if billboard != null:
		billboard.set_animation("defused")
	GiftLarperAudioScript.play(self, GiftLarperAudioScript.CUE_PFF)


## Sim ticks of view state. dt_ticks is the sim tick count (1 at 60 Hz) - never a wall clock.
## Steps the 5-frame cycle, the detonation burst and the defused grey-out/drop/fade.
func step(dt_ticks: int = 1) -> void:
	if billboard == null:
		return
	_anim_ticks += dt_ticks
	# idle: 48 ticks per frame, looping the 5 frames (one revolution per 240 ticks);
	# while defused the defused pose holds (the grey-out plays over it)
	if _def_left == 0:
		var idx := int(float(_anim_ticks) / float(maxi(_frame_ticks, 1))) % maxi(_frames, 1)
		if idx != billboard.frame_i:
			billboard.frame_i = idx
			billboard._apply_frame(idx)
	# attack_detonation: 18 TOTAL ticks - white flash (first ~4), burst sphere 0 -> radius
	if _det_left > 0:
		_det_left = maxi(_det_left - dt_ticks, 0)
		var prog := 1.0 - float(_det_left) / float(maxi(_detonation_ticks, 1))
		var flash := clampf(1.0 - prog / 0.25, 0.0, 1.0)
		billboard.modulate = Color(1.0 + 1.5 * flash, 1.0 + 1.5 * flash, 1.0 + 1.5 * flash, 1.0)
		if _burst != null:
			_burst.scale = Vector3.ONE * maxf(_burst_radius * prog, 0.001)
			var m := _burst.get_surface_override_material(0) as StandardMaterial3D
			if m != null:
				m.albedo_color = _burst_from.lerp(_burst_to, prog)
				m.albedo_color.a = 1.0 - prog
		if _det_left == 0:
			billboard.modulate = Color(1.0, 1.0, 1.0, 1.0)
			if _burst != null:
				_burst.visible = false
	# defused: 24 TOTAL ticks - grey, drop 0.5 u, fade to alpha 0, then hide + puff
	if _def_left > 0:
		_def_left = maxi(_def_left - dt_ticks, 0)
		var prog2 := 1.0 - float(_def_left) / float(maxi(_defused_ticks, 1))
		var grey := lerpf(1.0, DEFUSE_GREY, prog2)
		billboard.modulate = Color(grey, grey, grey, 1.0 - prog2)
		billboard.position.y = _base_y - _defuse_drop * prog2
		if _def_left == 0:
			billboard.visible = false
			if _puff != null:
				_puff.emitting = true


## The tell (section 3.3): inside _tell_range the pink emitter shows; beyond it the mine reads
## as an ordinary black gift (the PNG stays as-is; the rim glow is the glb tripmine path's job).
## eye is the camera position; pass Vector3.ZERO to force the emitter on (debug/tests).
func sync(eye: Vector3 = Vector3.ZERO) -> void:
	if _emitter == null or billboard == null:
		return
	if eye == Vector3.ZERO:
		_set_emitting(true)
		return
	var p := billboard.global_position if billboard.is_inside_tree() else billboard.position
	_set_emitting(p.distance_to(eye) <= _tell_range)


## U4: CPUParticles3D's `emitting` setter reads the node's global transform, which errors
## ("Condition !is_inside_tree() is true") when the view is not in the tree - and a view
## IS synced outside the tree: world.gd pre-builds the enemy hosts detached and the tests
## build a world outside the tree. The tell is a draw state, so it is simply not written
## while detached; the next tick after the view enters the tree sets it.
func _set_emitting(p_on: bool) -> void:
	if not _emitter.is_inside_tree():
		return
	_emitter.emitting = p_on


## Frame locally (BILLBOARDING) - the billboard's own _process is disabled; this file owns it.
func _process(_dt: float) -> void:
	if billboard == null or get_viewport() == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		billboard.face_camera(cam.global_position)


func tell_range() -> float:
	return _tell_range


func _build_burst() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = _burst_from
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.set_surface_override_material(0, m)
	return mi


func _build_emitter() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = clampi(_particles_per_second, 1, 64)
	p.lifetime = 1.5
	p.position = Vector3(0.0, 0.6, 0.0)
	p.emitting = true
	p.direction = Vector3(0.0, 1.0, 0.0)
	p.spread = 20.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.5
	p.gravity = Vector3(0.0, 0.0, 0.0)
	var m := SphereMesh.new()
	m.radius = 0.03
	m.height = 0.06
	m.radial_segments = 6
	m.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _particle_color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = _particle_color
	m.material = mat
	p.mesh = m
	return p


func _build_puff() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 10
	p.lifetime = 0.8
	p.one_shot = true
	p.explosiveness = 1.0
	p.position = Vector3(0.0, 0.3, 0.0)
	p.direction = Vector3(0.0, 1.0, 0.0)
	p.spread = 60.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 1.8
	p.gravity = Vector3(0.0, -2.0, 0.0)
	var m := SphereMesh.new()
	m.radius = 0.08
	m.height = 0.16
	m.radial_segments = 6
	m.rings = 4
	var mat := StandardMaterial3D.new()
	var grey := Color(0.75, 0.75, 0.75, 0.9)
	mat.albedo_color = grey
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material = mat
	p.mesh = m
	return p
