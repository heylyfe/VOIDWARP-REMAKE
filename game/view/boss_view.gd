extends Node3D
## Boss presentation driven by the event stream. Positions use world units.

const PETER_PATH := "res://assets/owner_third_party/peter/peter_griffin.png"
const GREEN_PATH := "res://assets/owner_third_party/peter/peter_green_fn.png"
const GIFT_MODEL := "res://assets/models/gold_gift.glb"

var _sprite: Sprite3D
var _normal: Texture2D
var _green: Texture2D
var _bar: ProgressBar
var _overlay: Control
var _gift_model: PackedScene
var _gifts: Dictionary = {}


func setup(target: Vector3, sprite_height: float, canvas: CanvasLayer) -> void:
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

	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(stack)
	stack.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	stack.offset_left = -156.0
	stack.offset_right = 156.0
	stack.offset_top = 20.0
	var title := Label.new()
	title.text = "Peter Griffin"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size.y = 18.0
	_bar.show_percentage = false
	stack.add_child(_bar)

	var reticle := Label.new()
	reticle.text = "+"
	reticle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reticle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(reticle)
	reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	_overlay.hide()


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
				_set_texture(_green if event["attack"] == "green_fn" and _green != null else _normal)
			"boss_died", "arena_exited":
				_sprite.hide()
				_overlay.hide()
				for gift in _gifts.values():
					gift.free()
				_gifts.clear()
			"boss_gift_spawned":
				if _gift_model != null:
					var gift: Node3D = _gift_model.instantiate()
					add_child(gift)
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


func _set_texture(texture: Texture2D) -> void:
	_sprite.texture = texture
	if texture != null and _normal != null:
		var size_ratio := float(_normal.get_height()) / float(texture.get_height())
		_sprite.scale = Vector3.ONE * size_ratio


static func _texture(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null
