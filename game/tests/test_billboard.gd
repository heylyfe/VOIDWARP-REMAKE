extends RefCounted
#
# BILLBOARDING hard rule (ticket T-027; ENEMIES.md): the PNG always faces the viewer - after
# face_camera() the sprite normal (+Z basis) opposed the camera forward from every angle:
# normal . forward <= -0.999 from 8 camera angles. Also: alpha-scissor 0.5, nearest filter,
# and frame animation driven by a sprites.json sheet.

const Billboard := preload("res://view/billboard.gd")

# 8 camera angles, 45 deg apart (the A-billboard clause in FLEET_PACK T-027).
const CAM_R := 4.0


# For EVERY enemy in content/enemies, EVERY animation, EVERY frame: the body's bottom edge
# must land on the node origin (world y = 0) within 1e-3 u. Measured two ways that never
# read the offset expression billboard.gd itself uses:
#   1. engine-generated quad geometry (generate_triangle_mesh) - the quad's lowest vertex
#      plus the px distance from the frame's bottom row to the body bottom row;
#   2. the node's own offset property read after _apply_frame, not recomputed.
# Uses the real imported texture dimensions and the real body_rect from sprites.json.
# Tight tolerance on purpose: this is the assertion that was missing when the sign shipped.
func _feet_all_enemies(f: Array[String]) -> void:
	const PX := 0.01
	const TOL := 1e-3
	var dir := DirAccess.open("res://content/enemies")
	if dir == null:
		f.append("billboard feet: cannot open res://content/enemies")
		return
	for enemy_id in dir.get_directories():
		var folder := "res://content/enemies/" + enemy_id
		var jf := FileAccess.open(folder + "/sprites.json", FileAccess.READ)
		if jf == null:
			continue
		var doc: Variant = JSON.parse_string(jf.get_as_text())
		if not (doc is Dictionary):
			f.append("billboard feet: %s/sprites.json did not parse" % enemy_id)
			continue
		for a in doc.get("animations", []):
			var frames: Array = a.get("frames", [])
			var brs: Array = a.get("body_rect", [])
			var anim: String = str(a.get("name", ""))
			if brs.is_empty():
				f.append("billboard feet: %s/%s has no body_rect" % [enemy_id, anim])
				continue
			for i in range(frames.size()):
				# fresh node per frame: generate_triangle_mesh() caches per node
				var b := Billboard.new()
				b.setup_from_sheet(doc, folder)
				b.anim_name = anim
				b._apply_frame(i)
				var tex: Texture2D = b.texture
				if tex == null:
					f.append("billboard feet: %s/%s[%d] texture failed to load" % [enemy_id, anim, i])
					b.free()
					continue
				var frame_h: float = float(tex.get_height())
				var br: Array = brs[mini(i, brs.size() - 1)]
				var body_bottom_row: float = float(br[1]) + float(br[3])
				var mesh: TriangleMesh = b.generate_triangle_mesh()
				var bottom_mesh := NAN
				if mesh != null:
					var verts: PackedVector3Array = mesh.get_faces()
					if verts.size() > 0:
						var mn := verts[0].y
						for v in verts:
							mn = minf(mn, v.y)
						# quad min-y + px distance from frame bottom row to body bottom row,
						# all in local (unscaled) y, then node scale - offset never read
						bottom_mesh = (mn + (frame_h - body_bottom_row) * PX) * b.scale.y
				var bottom_off: float = (b.offset.y + frame_h * 0.5 - body_bottom_row) * PX * b.scale.y
				if is_nan(bottom_mesh) or absf(bottom_mesh) > TOL:
					f.append("billboard feet: %s/%s[%d] body bottom at y=%.6f (mesh), want 0 +/- %.4f" % [enemy_id, anim, i, bottom_mesh, TOL])
				elif absf(bottom_off) > TOL:
					f.append("billboard feet: %s/%s[%d] body bottom at y=%.6f (offset), want 0 +/- %.4f" % [enemy_id, anim, i, bottom_off, TOL])
				b.free()


func run() -> Array[String]:
	var f: Array[String] = []
	var b = Billboard.new()
	b.position = Vector3(0.5, 0.0, 0.5)
	b.setup_from_sheet(_two_frame_sheet(), "res://content/enemies/kiwi_cat")
	_material(f, b)
	_angles(f, b)
	_frames(f, b)
	b.free()
	_feet_all_enemies(f)
	_anim_states(f)
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


# T-083 anim.states merge (owner report: the toucher showed a black/magenta checker instead of
# its own art). The sim drives billboards by anim_state name, and those names live in the
# T-083 `anim.states` block, not in the legacy T-016 `animations[]` list. Before the merge,
# 9 of 12 enemies had sim states with no art animation and froze on their last frame.
# This pins the contract: every state the sim can ask for must resolve to a real animation,
# unless the sheet deliberately gives it no frames (attack_touch / recover on the toucher).
func _anim_states(f: Array[String]) -> void:
	var dir := DirAccess.open("res://content/enemies")
	if dir == null:
		f.append("anim.states: cannot open res://content/enemies")
		return
	var checked := 0
	for enemy_id in dir.get_directories():
		var folder := "res://content/enemies/" + enemy_id
		var jf := FileAccess.open(folder + "/sprites.json", FileAccess.READ)
		if jf == null:
			continue
		var doc: Variant = JSON.parse_string(jf.get_as_text())
		if not (doc is Dictionary):
			f.append("anim.states: %s/sprites.json did not parse" % enemy_id)
			continue
		var block: Variant = (doc as Dictionary).get("anim")
		if not (block is Dictionary):
			continue
		var states: Variant = (block as Dictionary).get("states")
		if not (states is Dictionary):
			continue
		var b := Billboard.new()
		b.setup_from_sheet(doc, folder)
		# a state that the legacy animations[] list already covers keeps that art (the merge
		# only fills gaps), so its frame count is the legacy one, not the anim.states one
		var legacy := {}
		for a in (doc as Dictionary).get("animations", []):
			legacy[str(a.get("name", ""))] = true
		for state_id in (states as Dictionary).keys():
			var key := str(state_id)
			var st: Dictionary = (states as Dictionary)[state_id]
			var frames: Array = st.get("frames", [])
			checked += 1
			if frames.is_empty():
				# a frameless state is legal: it holds the previous texture
				continue
			if not b.anims.has(key):
				f.append("anim.states: %s state '%s' has %d frames but no animation resolved"
					% [enemy_id, key, frames.size()])
				continue
			var a: Dictionary = b.anims[key]
			if not legacy.has(key) and (a["frames"] as Array).size() != frames.size():
				f.append("anim.states: %s state '%s' resolved %d frames, sheet lists %d"
					% [enemy_id, key, (a["frames"] as Array).size(), frames.size()])
			if float(a["fps"]) <= 0.0:
				f.append("anim.states: %s state '%s' has fps %s" % [enemy_id, key, str(a["fps"])])
			b.set_animation(key)
			if b.anim_name != key:
				f.append("anim.states: %s set_animation('%s') did not take" % [enemy_id, key])
		b.free()
	if checked == 0:
		f.append("anim.states: no enemy sheet declares an anim.states block")
