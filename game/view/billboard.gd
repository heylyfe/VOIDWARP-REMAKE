extends Sprite3D
#
# billboard.gd - the PNG enemy sprite (ticket T-027; ENEMIES.md BILLBOARDING hard rule,
# DESIGN.md section 5). View layer only: reads sim state and events, never writes sim state.
#
# - Y-billboarding: the sprite rotates around Y every frame to face the camera (BILLBOARDING:
#   the PNG always faces the viewer; there is no side of a PNG enemy). Done by hand, not with
#   the shader billboard mode, so the facing is testable: after face_camera(), the sprite's
#   normal (+Z basis) opposed the camera's forward direction from every angle.
# - Material: rendered with the texture's alpha (alpha-scissor cut with threshold 0.5 -
#   TRANSPARENCY: transparent padding never renders) and nearest filtering (pixel art).
# - Frame animation: driven by content/enemies/<id>/sprites.json (T-016 schema) - animation
#   name, fps, loop and frame list; textures load from the frame paths. The sprite is scaled
#   so the BODY (the body_rect of the sheet) is the row's world_height u tall, and the body's
#   bottom (its feet) sits on the node origin.
# - Diegetic spawn text: spawn_text() raises an in-world label with the enemy's own name at
#   the spawn point (the enemy_spawn event carries the same text); it fades and frees itself.

const EnemyRuntime := preload("res://sim/enemy_runtime.gd")

const SCISSOR_THRESHOLD := 0.5

var sheet: Dictionary = {}            # parsed sprites.json
var anims: Dictionary = {}            # name -> {"frames": [Texture2D], "fps": float, "loop": bool}
var anim_name := ""                   # current animation (empty = the sheet's first)
var frame_i := 0
var anim_t := 0.0
var world_height := 1.0               # the body's height in world u (DESIGN.md SR-2)
var body_feet_shift := 0.0            # world u the sprite must rise so the body bottom = origin


## Parses a sprites.json document (the T-016 schema). Frames are paths relative to the enemy
## folder; folder_dir is that folder's absolute res:// path (no uid - D-T016 res rule).
func setup_from_sheet(doc: Dictionary, folder_dir: String) -> void:
	sheet = doc
	# The T-016 schema stores world_height null where the design gives the enemy no body
	# row (the launcher, SR-2) - null must read as 0.0, not float-crash.
	var wh: Variant = doc.get("world_height", 1.0)
	world_height = float(wh) if (wh is float or wh is int) else 0.0
	anims.clear()
	for a in doc.get("animations", []):
		var texs: Array = []
		for fpath in a.get("frames", []):
			var full := folder_dir.path_join(str(fpath))
			if ResourceLoader.exists(full):
				texs.append(load(full))
			else:
				texs.append(null)
		var fps: Variant = a.get("fps", 1.0)
		anims[str(a.get("name", ""))] = {"frames": texs,
				"fps": float(fps) if (fps is float or fps is int) else 1.0,
				"loop": bool(a.get("loop", true)),
				"body_rect": a.get("body_rect", [[0, 0, 256, 256]])}
	anim_name = ""
	anim_t = 0.0
	frame_i = 0
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	alpha_scissor_threshold = SCISSOR_THRESHOLD
	_apply_frame(0)


func set_animation(p_name: String) -> void:
	if not anims.has(p_name) or p_name == anim_name:
		return
	anim_name = p_name
	anim_t = 0.0
	frame_i = 0
	_apply_frame(0)


## One animation step: anim_t advances p_dt seconds, the frame follows the fps; a non-looping
## animation holds its last frame.
func advance_animation(p_dt: float) -> void:
	var a: Dictionary = _current_anim()
	if a.is_empty() or a["frames"].is_empty():
		return
	anim_t += p_dt
	var fps: float = maxf(float(a["fps"]), 0.001)
	var idx := int(anim_t * fps)
	if bool(a["loop"]):
		idx = idx % a["frames"].size()
	else:
		idx = mini(idx, a["frames"].size() - 1)
	if idx != frame_i:
		frame_i = idx
		_apply_frame(idx)


## Point the sprite's +Z normal at the camera, Y axis only (no pitch, no roll): the rotation
## happens around the world up, so the sprite never shows its top or bottom edge.
func face_camera(cam_pos: Vector3) -> void:
	# outside the tree, global transforms error (unparented in tests/tools): the node is then
	# its own world, so the local position carries the same information
	var bp := global_position if is_inside_tree() else position
	var dx: float = cam_pos.x - bp.x
	var dz: float = cam_pos.z - bp.z
	if absf(dx) < 1e-9 and absf(dz) < 1e-9:
		return
	rotation.y = atan2(dx, dz)


func _process(p_dt: float) -> void:
	advance_animation(p_dt)
	var vp := get_viewport()
	if vp != null:
		var cam := vp.get_camera_3d()
		if cam != null:
			face_camera(cam.global_position)


func _current_anim() -> Dictionary:
	if anim_name != "" and anims.has(anim_name):
		return anims[anim_name]
	for k in anims.keys():
		return anims[k]
	return {}


## Applies frame i: swaps the texture and re-derives scale + feet offset from the frame's
## body_rect, so the body stands world_height u tall with its bottom on the node origin.
func _apply_frame(i: int) -> void:
	var a := _current_anim()
	if a.is_empty():
		return
	var frames: Array = a["frames"]
	if frames.is_empty():
		return
	texture = frames[i % frames.size()]
	var brs: Array = a["body_rect"]
	var br: Array = brs[mini(i, brs.size() - 1)]
	var brh: float = maxf(float(br[3]), 1.0)
	var frame_h: float = 0.0
	var frame_w: float = 0.0
	if texture != null:
		frame_w = float(texture.get_width())
		frame_h = float(texture.get_height())
	else:
		frame_w = 256.0
		frame_h = 256.0
	# scale: body_rect height (px, at pixel_size 0.01 u/px) must become world_height u
	var px := 0.01
	var body_px_h: float = brh * px
	var s: float = world_height / body_px_h
	scale = Vector3(s, s, s)
	# body bottom row (px, from top): br[1] + br[3]; distance below the frame centre, in u.
	# SpriteBase3D.offset.y is +up in world space (Godot 4 docs; verified against
	# generate_triangle_mesh()), so standing the body bottom on the node origin needs the
	# POSITIVE distance, not its negation.
	body_feet_shift = ((float(br[1]) + brh) - frame_h * 0.5) * px * s
	offset = Vector2(0.0, (float(br[1]) + brh) - frame_h * 0.5)


## Diegetic spawn text (deliverable 4): an in-world label above the spawn point, showing the
## enemy's own name from its enemy_spawn event. Returns the label so the caller can attach it.
func spawn_text(p_text: String) -> Label3D:
	var label := Label3D.new()
	label.text = p_text
	label.font_size = 48
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 10
	label.position = Vector3(0.0, world_height + 0.6, 0.0)
	add_child(label)
	var tw := label.create_tween()
	tw.tween_interval(1.5)
	tw.tween_property(label, "modulate", Color(1.0, 1.0, 1.0, 0.0), 1.0)
	tw.tween_callback(label.queue_free)
	return label
