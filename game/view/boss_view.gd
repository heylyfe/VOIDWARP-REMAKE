extends Node3D
## Boss presentation driven by the event stream. Positions use world units.
##
## T8b adds the two attacks' visuals (a rolling bowling ball, a basketball and its ground
## marker), Peter's laugh, and the Bankai cinematic. Everything here is view-only: the
## cinematic is wired through its own signals and never touches sim/ or the state hash.

const AssetLoadScript := preload("res://view/asset_load.gd")   # U4: fail-soft loads
const HudStyle := preload("res://view/hud/hud_style.gd")
const BossAudio := preload("res://view/audio/boss_audio.gd")
const BankaiScript := preload("res://view/cinematics/bankai_gift_animation.gd")
const PETER_PATH := "res://assets/owner_third_party/peter/peter_griffin.png"
const GREEN_PATH := "res://assets/owner_third_party/peter/peter_green_fn.png"
const GiftsView := preload("res://view/gifts_view.gd")

## The two attack balls, in the palette's own colours (a dark bowling ball, an orange
## basketball). Radius comes from the sim row, so the visual matches the hit volume.
const BOWLING_COLOR := Color(0.10, 0.11, 0.16)
const BASKETBALL_COLOR := Color(0.86, 0.42, 0.13)
const MARKER_COLOR := Color(1.0, 0.16, 0.16, 0.55)
const CHARGE_COLOR := Color(0.35, 1.0, 0.45, 0.5)
## Peter's tint during the bowling wind-up. No bowling art was provided, so the pose
## cue is a warm flash plus the ball visibly in his hand.
const BOWLING_TINT := Color(1.0, 0.72, 0.55)
## How far the floor marker runs. The arena is 33 tiles across, so this covers a lane
## from Peter to the far wall.
const LANE_LENGTH := 32.0
## The marker's BACKSTOP lifetime in SIM TICKS. on_events runs once per sim tick, so
## this countdown is frame-rate independent; the release event normally clears the
## marker first and this only catches a dropped event.
const MARKER_TICKS := 60

var _sprite: Sprite3D
var _normal: Texture2D
var _green: Texture2D
var _bar: ProgressBar
var _title: Label
var _overlay: Control
var _gift_model: PackedScene
# U4 test seam: the path the thrown gifts load from. GiftsView.GOLD_MODEL in every
# real run; a test points it at a missing path to prove the arena still runs.
var gift_model_path := GiftsView.GOLD_MODEL
var _gifts: Dictionary = {}
var _balls: Dictionary = {}
var _marker: MeshInstance3D = null
var _marker_ticks := 0
var _held_ball: MeshInstance3D = null
var _charge: MeshInstance3D = null
var _bankai: Node3D = null
var _bankai_grace := 0
var _bankai_grace_ticks := 60
var _floor_y := 0.0
var bankai_feet := Vector3.ZERO
var bankai_model: Node3D
var bankai_bounds := Rect2()
var bankai_hit_tick := 1290



# U4 (Terra finding 3): release this view's surface-override materials before the node
# is destroyed, on EVERY free path (the world's teardown or a direct free()). A
# MeshInstance3D's override Refs die before its rendering-server instance is freed, so
# freeing with the overrides still set leaves a dangling material RID and the dummy
# renderer prints `ERROR: Parameter "material" is null`; clearing them here first is
# the ownership fix (see asset_load.gd release_materials).
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		AssetLoadScript.release_materials(self)
func setup(target: Vector3, sprite_height: float, canvas: CanvasLayer,
		floor_y: float = 0.0, grace_ticks: int = 60) -> void:
	_floor_y = floor_y
	_bankai_grace_ticks = grace_ticks
	_normal = _texture(PETER_PATH)
	_green = _texture(GREEN_PATH)
	_sprite = Sprite3D.new()
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.position = target
	_sprite.hide()
	add_child(_sprite)
	if _normal != null:
		_sprite.pixel_size = sprite_height / float(_normal.get_height())
	_set_texture(_normal)
	_gift_model = AssetLoadScript.scene(gift_model_path)

	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", HudStyle.panel())
	_overlay.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -HudStyle.COUNTER_W * 0.5
	panel.offset_right = HudStyle.COUNTER_W * 0.5
	panel.offset_top = HudStyle.COLLAPSE_TOP

	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(stack)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	HudStyle.style_label(_title, HudStyle.FONT_BODY)
	stack.add_child(_title)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size.y = HudStyle.PAD_Y
	_bar.show_percentage = false
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := HudStyle.cell()
	fill.bg_color = HudStyle.GOLD
	_bar.add_theme_stylebox_override("fill", fill)
	stack.add_child(_bar)
	var hint := Label.new()
	hint.text = "Hold left mouse to throw gifts"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	HudStyle.style_label(hint, HudStyle.FONT_SMALL)
	stack.add_child(hint)

	var reticle := Label.new()
	reticle.text = "+"
	reticle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reticle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	HudStyle.style_label(reticle, HudStyle.FONT_BODY)
	_overlay.add_child(reticle)
	reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	_overlay.hide()
	_marker = _build_marker()
	add_child(_marker)
	_held_ball = _build_held_ball()
	add_child(_held_ball)
	_charge = _build_charge()
	add_child(_charge)


## The floor telegraph: a flat bar that runs along a lane. Built once, moved and shown
## per wind-up.
func _build_marker() -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 0.02, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = MARKER_COLOR
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.visible = false
	return node


## The ball in Peter's hand during the bowling wind-up: the pose cue, since no bowling
## art was provided.
func _build_held_ball() -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.45
	mesh.height = 0.9
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BOWLING_COLOR
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.visible = false
	return node


## The green_fn charge disc at Peter's feet. It says "a shot is coming" and deliberately
## claims no line: the shot aims at the player's position at RELEASE, so any line drawn
## during the wind-up would be a lie the moment the player moves.
func _build_charge() -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 0.02
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = CHARGE_COLOR
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.visible = false
	return node


## The marker's lifetime is the SIM's clock, not the render frame rate: on_events runs
## once per sim tick, so this countdown is tick-accurate at any FPS. The release event
## normally clears the marker first; MARKER_TICKS is the backstop.
func _age_marker() -> void:
	if _marker_ticks <= 0:
		return
	_marker_ticks -= 1
	if _marker_ticks == 0:
		_hide_marker()


func _hide_marker() -> void:
	_marker_ticks = 0
	if _marker != null:
		_marker.visible = false


## Lays the marker from `from` along `dir` for `length`, on the arena floor.
func _show_marker(from: Vector3, dir: Vector3, length: float) -> void:
	if _marker == null:
		return
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return
	flat = flat.normalized()
	var mid := from + flat * (length * 0.5)
	_marker.position = Vector3(mid.x, _floor_y + 0.03, mid.z)
	_marker.rotation = Vector3(0.0, atan2(flat.x, flat.z), 0.0)
	_marker.scale = Vector3(0.35, 1.0, length)
	_marker.visible = true
	_marker_ticks = MARKER_TICKS


func on_events(events: Array) -> void:
	# on_events runs once per SIM TICK, so these two countdowns are tick-accurate at
	# any frame rate. They age BEFORE the batch, so a marker raised by this batch gets
	# its full lifetime.
	_age_marker()
	_age_bankai()
	for event in events:
		match event.get("kind", ""):
			"boss_spawned":
				_sprite.show()
				_overlay.show()
				_set_hp(event)
			"boss_hp_changed":
				_set_hp(event)
			"boss_attack_windup":
				_on_windup(event)
			"boss_projectile_spawned":
				_spawn_ball(event)
			"boss_projectile_moved":
				if _balls.has(event["id"]):
					_balls[event["id"]].position = event["position"]
			"boss_projectile_removed":
				_free_ball(event["id"])
			"boss_projectile_hit_player":
				_overlay.hide()
				_clear_balls()
			"boss_laugh":
				BossAudio.play_laugh(self)
			"bankai_started":
				_start_bankai()
			"bankai_hit":
				# The cinematic also hides the sprite on target_hit at this tick.
				if _bankai == null:
					_sprite.hide()
			"bankai_finished":
				_on_bankai_sim_finished()
			"boss_died":
				_sprite.hide()
				_overlay.hide()
				_clear_balls()
				for gift in _gifts.values():
					AssetLoadScript.release_materials(gift)   # U4 dangling-RID fix
					gift.free()
				_gifts.clear()
			"arena_exited":
				_sprite.hide()
				_overlay.hide()
				_clear_balls()
				_release_bankai()
				for gift in _gifts.values():
					AssetLoadScript.release_materials(gift)   # U4 dangling-RID fix
					gift.free()
				_gifts.clear()
			"boss_gift_spawned":
				if _gift_model != null:
					var gift: Node3D = _gift_model.instantiate()
					add_child(gift)
					_add_body(gift, _gift_material())
					gift.position = event["position"]
					_gifts[event["id"]] = gift
			"boss_gift_moved":
				if _gifts.has(event["id"]):
					_gifts[event["id"]].position = event["position"]
			"boss_gift_removed":
				if _gifts.has(event["id"]):
					AssetLoadScript.release_materials(_gifts[event["id"]])   # U4 dangling-RID fix
					_gifts[event["id"]].free()
					_gifts.erase(event["id"])


func _set_hp(event: Dictionary) -> void:
	_bar.max_value = float(event["hp_max"])
	_bar.value = float(event["hp"])
	_title.text = "Peter Griffin  %d / %d" % [event["hp"], event["hp_max"]]


func _set_texture(texture: Texture2D) -> void:
	_sprite.texture = texture
	if texture != null and _normal != null:
		var size_ratio := float(_normal.get_height()) / float(texture.get_height())
		_sprite.scale = Vector3.ONE * size_ratio


static func _texture(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


## A wind-up, and the two attacks telegraph DIFFERENTLY on purpose.
##
## The bowling ball commits its lane at the wind-up (the sim's `aim`), so the marker drawn
## here IS the lane the ball will take. Peter also holds the ball and takes a warm tint -
## the pose cue, since no bowling art was provided.
##
## The green_fn keeps the owner's "aimed at the player's position at release", so it
## commits nothing yet. It shows the transform and a charge disc at Peter's feet and
## deliberately claims NO line: a line drawn now would be a lie the moment the player
## moves. Its real aim line appears on the release.
func _on_windup(event: Dictionary) -> void:
	var attack := str(event.get("attack", ""))
	if attack == "green_fn":
		_set_texture(_green if _green != null else _normal)
		_sprite.modulate = Color(1.0, 1.0, 1.0)
		if _held_ball != null:
			_held_ball.visible = false
		if _charge != null:
			_charge.position = Vector3(_sprite.position.x, _floor_y + 0.04, _sprite.position.z)
			_charge.visible = true
		_hide_marker()
		return
	_set_texture(_normal)
	_sprite.modulate = BOWLING_TINT
	if _charge != null:
		_charge.visible = false
	if _held_ball != null:
		_held_ball.position = _sprite.position + Vector3(0.7, -0.9, 0.0)
		_held_ball.visible = true
	_show_marker(_sprite.position, event.get("aim", Vector3.ZERO), LANE_LENGTH)


## One ball per live sim projectile, sized from the sim row so the visual matches the hit
## volume. The release drops the wind-up cue; the green_fn also lays the line the shot
## will actually take, from the release point along its velocity.
func _spawn_ball(event: Dictionary) -> void:
	var attack := str(event.get("attack", ""))
	if _held_ball != null:
		_held_ball.visible = false
	if _charge != null:
		_charge.visible = false
	_sprite.modulate = Color(1.0, 1.0, 1.0)
	if attack == "green_fn":
		_set_texture(_normal)
		_show_marker(event["position"], event["velocity"], LANE_LENGTH)
	else:
		_hide_marker()
	var radius := float(event.get("radius", 0.4))
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BOWLING_COLOR if attack == "bowling_ball" else BASKETBALL_COLOR
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = event["position"]
	add_child(node)
	_balls[event["id"]] = node


func _free_ball(id: Variant) -> void:
	if _balls.has(id):
		_balls[id].free()
		_balls.erase(id)


func _clear_balls() -> void:
	for node in _balls.values():
		node.free()
	_balls.clear()


## The sim owns the kill and supplies the clock for the cinematic's presentation.
func _start_bankai() -> void:
	if _bankai != null:
		return
	_bankai = BankaiScript.new()
	add_child(_bankai)
	if is_inside_tree():
		_bankai.global_position = bankai_feet
	else:
		_bankai.position = bankai_feet
	_bankai.arena_bounds = bankai_bounds
	_bankai.hit_tick = bankai_hit_tick
	_bankai.externally_clocked = true
	_bankai.player_model = bankai_model
	if is_instance_valid(bankai_model) and bankai_model.is_inside_tree():
		bankai_model.global_position = bankai_feet
		bankai_model.rotation.y = 0.0
	# Headless (tests, the gate) has no viewport and no camera. The cinematic already falls
	# back to its own get_viewport() lookup and guards with is_instance_valid, so null is a
	# supported value here - it just means "no camera to take".
	var vp := get_viewport()
	if vp != null:
		_bankai.fps_camera = vp.get_camera_3d()
	_bankai.animation_started.connect(_on_bankai_started)
	_bankai.target_hit.connect(_on_bankai_target_hit)
	_bankai.animation_finished.connect(_on_bankai_animation_finished)
	_bankai.play(_sprite)


func sync_bankai_tick(tick: int) -> void:
	if _bankai != null:
		_bankai.sync_tick(tick)


## The cinematic has taken the camera: the fight HUD and every telegraph step aside.
func _on_bankai_started() -> void:
	_overlay.hide()
	_hide_marker()
	if _held_ball != null:
		_held_ball.visible = false
	if _charge != null:
		_charge.visible = false


## The gifts reach Peter. This is the ONLY place the sprite dies during the Bankai, and it
## is the cinematic's own hit tick, so the visual death always coincides with the gifts
## landing rather than with the sim's deliberately later kill tick.
func _on_bankai_target_hit(_target: Node3D) -> void:
	_sprite.hide()


## The cinematic reached TOTAL_DURATION. It has already called its own stop() (which
## restores the player's camera), so the node can go.
func _on_bankai_animation_finished() -> void:
	_release_bankai()


## The sim's bankai_finished. The cinematic normally finishes first; if render drift has
## it still playing, wait a bounded number of ticks for animation_finished and then stop()
## it explicitly. stop() is what restores the camera, so the node is never freed without
## it - freeing a playing cinematic would leave the player looking through the anim camera.
func _on_bankai_sim_finished() -> void:
	if _bankai == null:
		return
	_bankai_grace = _bankai_grace_ticks
	if _bankai_grace <= 0:
		_release_bankai()


## The bounded wait, aged once per sim tick by on_events.
func _age_bankai() -> void:
	if _bankai == null or _bankai_grace <= 0:
		return
	_bankai_grace -= 1
	if _bankai_grace == 0:
		_release_bankai()


## Stops the cinematic (restoring the camera) and frees it. Safe to call twice.
func _release_bankai() -> void:
	if _bankai == null:
		return
	_bankai_grace = 0
	if is_instance_valid(_bankai):
		if bool(_bankai.is_playing):
			_bankai.stop()
		_bankai.queue_free()
	_bankai = null


## The thrown gift's base pass: unshaded, using the mesh's vertex colours. The .glb
## carries no material of its own (export_materials="NONE"), so without this the gift
## renders Godot's default WHITE and the gold palette is never seen - the J3 defect
## class test_model_materials.gd guards. Same pattern as gifts_view.gd's gold body.
static func _gift_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1.0, 1.0, 1.0)
	return m


## Adds the base material to every mesh surface under the instance.
static func _add_body(root: Node3D, mat: StandardMaterial3D) -> void:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D and n.mesh != null:
			for s in n.mesh.get_surface_count():
				n.set_surface_override_material(s, mat)
