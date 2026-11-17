extends RefCounted
#
# BILLBOARDING hard rule (ticket T-027; ENEMIES.md): the PNG always faces the viewer - after
# face_camera() the sprite normal (+Z basis) opposed the camera forward from every angle:
# normal . forward <= -0.999 from 8 camera angles. Also: alpha-scissor 0.5, nearest filter,
# and frame animation driven by a sprites.json sheet.

const Billboard := preload("res://view/billboard.gd")

# 8 camera angles, 45 deg apart (the A-billboard clause in FLEET_PACK T-027).
const CAM_R := 4.0


func run() -> Array[String]:
	var f: Array[String] = []
	var b = Billboard.new()
	b.position = Vector3(0.5, 0.0, 0.5)
	b.setup_from_sheet(_two_frame_sheet(), "res://content/enemies/kiwi_cat")
	_material(f, b)
	_angles(f, b)
	_frames(f, b)
	b.free()
	return f


func _two_frame_sheet() -> Dictionary:
	# two frames of the same real (imported) PNG; body_rect 224 px tall in a 256 px frame
	return {
		"world_height": 1.0,
		"animations": [{
			"name": "cycle", "fps": 1.0, "loop": true,
			"frames": ["sprites/cycle_00.png", "sprites/cycle_00.png"],
			"body_rect": [[16, 16, 224, 224], [16, 16, 224, 224]],
		}],
	}


func _material(f: Array[String], b) -> void:
	if b.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST:
		f.append("billboard: texture filter is not nearest")
	if b.alpha_cut != SpriteBase3D.ALPHA_CUT_DISCARD:
		f.append("billboard: alpha cut is not discard")
	if absf(float(b.alpha_scissor_threshold) - 0.5) > 1e-9:
		f.append("billboard: alpha scissor threshold %s, want 0.5" % str(b.alpha_scissor_threshold))


# normal . camera forward <= -0.999 from every one of the 8 angles. The billboard is not in
# the scene tree here (headless --script, no root - ref run_all.gd's contract), so the node's
# own transform IS its world transform: basis.z read from `transform` is the sprite normal.
func _angles(f: Array[String], b) -> void:
	var centre := Vector3(0.5, 0.0, 0.5)
	for i in range(8):
		var ang := float(i) * PI / 4.0
		var cam_pos := centre + Vector3(sin(ang), 0.0, cos(ang)) * CAM_R
		b.face_camera(cam_pos)
		var normal: Vector3 = b.transform.basis.z.normalized()
		var fwd: Vector3 = (centre - cam_pos).normalized()
		var dot := normal.dot(fwd)
		if dot > -0.999:
			f.append("billboard: angle %d deg normal.fwd = %.6f, want <= -0.999"
					% [int(ang * 180.0 / PI), dot])
	# Y-billboarding: the facing never pitches - the basis stays level for a camera off-axis
	var cam_hi := centre + Vector3(CAM_R, CAM_R, 0.0)
	b.face_camera(cam_hi)
	var bpitch: Vector3 = b.transform.basis.z
	if absf(bpitch.x) < 1e-6 or absf(bpitch.y) > 1e-6 or absf(bpitch.z) > 1e-6:
		f.append("billboard: facing pitched or rolled for an off-axis camera (%s %s %s)" % [
				str(bpitch.x), str(bpitch.y), str(bpitch.z)])


# Frame animation from the sheet: fps 1 loop; a non-looping variant holds its last frame.
func _frames(f: Array[String], b) -> void:
	if b.frame_i != 0:
		f.append("billboard: animation did not start on frame 0")
	b.advance_animation(0.6)
	if b.frame_i != 0:
		f.append("billboard: frame advanced before the frame time (0.6 s, fps 1)")
	b.advance_animation(0.6)
	if b.frame_i != 1:
		f.append("billboard: frame did not advance to 1 after 1.2 s at fps 1")
	b.advance_animation(1.0)
	if b.frame_i != 0:
		f.append("billboard: looping animation did not wrap to frame 0")
	# scale: the body (224 px) stands 1.0 u tall
	var want_s: float = 1.0 / (224.0 * 0.01)
	if absf(float(b.scale.y) - want_s) > 1e-6:
		f.append("billboard: sprite scale %s, want %.6f (body = world_height)"
				% [str(b.scale.y), want_s])
	# switching to a missing animation keeps the current one
	b.set_animation("nope")
	if b.anim_name == "nope":
		f.append("billboard: set_animation accepted an unknown name")
