extends Node3D
## Boss presentation driven by the event stream. Positions use world units.

const HudStyle := preload("res://view/hud/hud_style.gd")
const PETER_PATH := "res://assets/owner_third_party/peter/peter_griffin.png"
const GREEN_PATH := "res://assets/owner_third_party/peter/peter_green_fn.png"
const GIFT_MODEL := "res://assets/models/gold_gift.glb"

var _sprite: Sprite3D
var _normal: Texture2D
var _green: Texture2D
var _bar: ProgressBar
var _title: Label
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
			"boss_projectile_hit_player":
				_overlay.hide()
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
	_title.text = "Peter Griffin  %d / %d" % [event["hp"], event["hp_max"]]


func _set_texture(texture: Texture2D) -> void:
	_sprite.texture = texture
	if texture != null and _normal != null:
		var size_ratio := float(_normal.get_height()) / float(texture.get_height())
		_sprite.scale = Vector3.ONE * size_ratio


static func _texture(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null
