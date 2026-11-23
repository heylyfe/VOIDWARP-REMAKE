extends Node3D
## Boss presentation driven by the event stream. Positions use world units.
##
## T8b adds the two attacks' visuals (a rolling bowling ball, a basketball and its ground
## marker), Peter's laugh, and the Bankai cinematic. Everything here is view-only: the
## cinematic is wired through its own signals and never touches sim/ or the state hash.

const HudStyle := preload("res://view/hud/hud_style.gd")
const BossAudio := preload("res://view/audio/boss_audio.gd")
const BankaiScript := preload("res://view/cinematics/bankai_gift_animation.gd")
const PETER_PATH := "res://assets/owner_third_party/peter/peter_griffin.png"
const GREEN_PATH := "res://assets/owner_third_party/peter/peter_green_fn.png"
const GIFT_MODEL := "res://assets/models/gold_gift.glb"

## The two attack balls, in the palette's own colours (a dark bowling ball, an orange
## basketball). Radius comes from the sim row, so the visual matches the hit volume.
const BOWLING_COLOR := Color(0.10, 0.11, 0.16)
const BASKETBALL_COLOR := Color(0.86, 0.42, 0.13)
const MARKER_COLOR := Color(1.0, 0.16, 0.16, 0.55)
## The green_fn marker lives for its windup; the sim owns the real timing, this is the
## view's own fade so a dropped event cannot leave a line on the floor forever.
const MARKER_TICKS := 40

var _sprite: Sprite3D
var _normal: Texture2D
var _green: Texture2D
var _bar: ProgressBar
var _title: Label
var _overlay: Control
var _gift_model: PackedScene
var _gifts: Dictionary = {}
var _balls: Dictionary = {}
var _marker: MeshInstance3D = null
var _marker_ticks := 0
var _bankai: Node3D = null
var _floor_y := 0.0


func setup(target: Vector3, sprite_height: float, canvas: CanvasLayer,
		floor_y: float = 0.0) -> void:
	_floor_y = floor_y
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
	_gift_model = load(GIFT_MODEL)

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


## The green_fn telegraph: a flat red bar on the arena floor from Peter to the spot the
## shot is aimed at. Built once, moved and shown per windup.
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


## The marker is the view's own clock: it fades out MARKER_TICKS after the windup that
## raised it, so a missed release event cannot leave a line on the floor.
func _process(_delta: float) -> void:
	if _marker_ticks <= 0:
		return
	_marker_ticks -= 1
	if _marker_ticks == 0 and _marker != null:
		_marker.visible = false


## Lays the marker from `from` to `to` on the floor at `floor_y`, one bar wide.
func _show_marker(from: Vector3, to: Vector3, floor_y: float) -> void:
	if _marker == null:
		return
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var length := flat.length()
	if length < 0.01:
		return
	_marker.position = Vector3((from.x + to.x) * 0.5, floor_y + 0.03, (from.z + to.z) * 0.5)
	_marker.rotation = Vector3(0.0, atan2(flat.x, flat.z), 0.0)
	_marker.scale = Vector3(0.35, 1.0, length)
	_marker.visible = true
	_marker_ticks = MARKER_TICKS


func on_events(events: Array) -> void:
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
				_sprite.hide()
			"bankai_finished":
				_stop_bankai()
			"boss_died":
				_sprite.hide()
				_overlay.hide()
				_clear_balls()
				for gift in _gifts.values():
					gift.free()
				_gifts.clear()
			"arena_exited":
				_sprite.hide()
				_overlay.hide()
				_clear_balls()
				_stop_bankai()
				for gift in _gifts.values():
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


## A windup: the green_fn transform is a VIEW state driven by this event, never a sim
## field, so the sprite swaps here and swaps back on the release. The green_fn also lays
## its ground marker from Peter to the spot the shot is aimed at.
func _on_windup(event: Dictionary) -> void:
	var attack := str(event.get("attack", ""))
	_set_texture(_green if attack == "green_fn" and _green != null else _normal)
	if attack == "green_fn" and event.has("player_position"):
		_show_marker(_sprite.position, event["player_position"], _floor_y)


## One ball per live sim projectile, sized from the sim row so the visual matches the hit
## volume. The green_fn release also drops the transform and the marker.
func _spawn_ball(event: Dictionary) -> void:
	var attack := str(event.get("attack", ""))
	if attack == "green_fn":
		_set_texture(_normal)
		if _marker != null:
			_marker.visible = false
			_marker_ticks = 0
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


## The Bankai easter egg. The sim rolled it and owns the kill; this plays the owner's
## dormant cinematic and follows its own signals. View-only: nothing here writes sim state.
func _start_bankai() -> void:
	if _bankai != null:
		return
	_bankai = BankaiScript.new()
	add_child(_bankai)
	_bankai.fps_camera = get_viewport().get_camera_3d()
	_bankai.animation_started.connect(_on_bankai_started)
	_bankai.target_hit.connect(_on_bankai_target_hit)
	_bankai.animation_finished.connect(_on_bankai_finished)
	if ResourceLoader.exists(BankaiScript.CUSTOM_VOICE_PATH):
		_bankai.senbonzakura_voice = load(BankaiScript.CUSTOM_VOICE_PATH)
	_bankai.play(_sprite)


## The cinematic has taken the camera: the fight HUD and the marker step aside.
func _on_bankai_started() -> void:
	_overlay.hide()
	if _marker != null:
		_marker.visible = false
		_marker_ticks = 0


## The gifts reach Peter. The sim's bankai_hit does the same; this keeps the sprite gone
## even if the two clocks drift apart by a frame.
func _on_bankai_target_hit(_target: Node3D) -> void:
	_sprite.hide()


func _on_bankai_finished() -> void:
	if _bankai != null and is_instance_valid(_bankai):
		_bankai.queue_free()
	_bankai = null


func _stop_bankai() -> void:
	if _bankai == null:
		return
	if is_instance_valid(_bankai):
		_bankai.free()
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
