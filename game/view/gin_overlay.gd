extends CanvasLayer
## A screen-space tell stays readable when the ground sword starts outside the camera.

const SWORD_PATH := "res://assets/owner_third_party/gin/gin_sword.png"
const VOICE_PATH := "res://assets/owner_third_party/gin/gin_bye_bye.wav"

var sword_texture: Texture2D
var _portrait: Control
var _voice: AudioStreamPlayer


class Portrait extends Control:
	var sword: Texture2D
	var flight := -1.0
	var twin := false

	func _draw() -> void:
		# Ivory hair and haori against a charcoal cutout, with closed eyes and a grin.
		var unit := minf(size.x, size.y) / 720.0
		var anchor := Vector2(size.x * 0.17, size.y * 0.58)
		draw_set_transform(anchor, 0.0, Vector2.ONE * unit)
		var ink := Color("#181526")
		var ivory := Color("#ebe5f1")
		var silver := Color("#b7b0d3")
		var violet := Color("#655b89")
		draw_circle(Vector2.ZERO, 91, Color("#241c3bc9"))
		draw_arc(Vector2.ZERO, 91, -PI * 0.84, PI * 0.34, 48, silver, 2.0, true)
		_poly([Vector2(-80, 76), Vector2(-61, 38), Vector2(-21, 22), Vector2(29, 21),
				Vector2(62, 41), Vector2(80, 76), Vector2(51, 93), Vector2(-50, 93)], ivory)
		_poly([Vector2(-38, 35), Vector2(-6, 65), Vector2(37, 32), Vector2(25, 93),
				Vector2(-24, 93)], ink)
		_poly([Vector2(-40, -46), Vector2(44, -48), Vector2(38, 3), Vector2(23, 28),
				Vector2(0, 40), Vector2(-24, 25), Vector2(-37, 6)], ink.lightened(0.19))
		_poly([Vector2(-51, -26), Vector2(-44, -60), Vector2(-17, -76), Vector2(29, -74),
				Vector2(51, -54), Vector2(44, -14), Vector2(30, -40), Vector2(4, -20),
				Vector2(12, -44), Vector2(-23, -19), Vector2(-18, -40), Vector2(-42, -13)], ivory)
		_poly([Vector2(-44, -60), Vector2(-17, -76), Vector2(29, -74), Vector2(51, -54),
				Vector2(11, -65), Vector2(-31, -50)], silver)
		draw_line(Vector2(-29, -12), Vector2(-9, -9), silver, 2.5, true)
		draw_line(Vector2(9, -9), Vector2(29, -12), silver, 2.5, true)
		_poly([Vector2(-22, 10), Vector2(0, 16), Vector2(21, 7), Vector2(12, 21),
				Vector2(-2, 25), Vector2(-16, 19)], ivory)
		draw_line(Vector2(-61, 73), Vector2(-41, 48), violet, 3.0, true)
		draw_line(Vector2(61, 73), Vector2(41, 48), violet, 3.0, true)
		if flight >= 0.0:
			_draw_flight(Vector2(size.x * 0.5, size.y * 0.76), unit)

	func _poly(points: Array[Vector2], color: Color) -> void:
		draw_colored_polygon(PackedVector2Array(points), color)

	func _draw_flight(end: Vector2, unit: float) -> void:
		draw_set_transform(Vector2.ZERO)
		var from := Vector2(size.x * 0.23, end.y)
		var tip := from.lerp(end, flight)
		var warning := Color("#ff7995")
		draw_line(from, end, Color("#130c21dd"), 7.0 * unit, true)
		draw_line(from, tip, warning, 3.0 * unit, true)
		draw_arc(end, 12.0 * unit, 0.0, TAU, 24, warning, 2.0 * unit, true)
		if sword != null:
			var bounds := sword.get_size() * (80.0 * unit / float(sword.get_width()))
			draw_texture_rect(sword, Rect2(tip - bounds * 0.5, bounds), false)
			if twin:
				var other := end * 2.0 - tip
				draw_texture_rect(sword, Rect2(other - bounds * 0.5, bounds), false,
						Color("#f8add1"))


func _ready() -> void:
	layer = 12
	_portrait = Portrait.new()
	_portrait.sword = sword_texture
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait)
	_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_voice = AudioStreamPlayer.new()
	if ResourceLoader.exists(VOICE_PATH):
		_voice.stream = load(VOICE_PATH)
	add_child(_voice)


func _init() -> void:
	if ResourceLoader.exists(SWORD_PATH):
		sword_texture = load(SWORD_PATH)


func present(phase: String, row: Dictionary) -> void:
	if _portrait == null:
		return
	visible = phase in ["voice", "sword"]
	_portrait.flight = -1.0
	_portrait.twin = row.has("gin_second_pos")
	if phase == "sword":
		_portrait.flight = float(row["gin_flight_elapsed"]) / float(row["cfg"]["sword_attack"]["flight_ticks"])
	_portrait.queue_redraw()


func play_voice() -> void:
	if _voice != null and _voice.stream != null:
		_voice.play()
