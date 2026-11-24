extends Node3D
#
# isagi body (W11-A adapter). view/isagi_view.gd is a RefCounted helper - pure snapshot
# maths, no Node - so it cannot sit in the tree by itself. This node is its body: the
# billboarded PNG enemy (billboard.gd, sheet-driven) plus the two things the helper's
# snapshot() describes and nothing else draws:
#   - the wind-up rim flash (red modulate, the helper's accelerating 24 -> 12 -> 6 period)
#   - the aim line, re-aimed every tick from the muzzle to the player's centre
# The helper stays the single source of every number; this file only renders them.
# View layer only: reads the sim row, never writes it.

const BillboardScript := preload("res://view/billboard.gd")
const AssetLoadScript := preload("res://view/asset_load.gd")   # U4: fail-soft loads (text/scene/texture/stream)
const IsagiViewScript := preload("res://view/isagi_view.gd")

const FLASH_RED := Color(1.0, 0.25, 0.25, 1.0)
const AIM_THICK := 0.05

var helper = null                  # the isagi_view.gd RefCounted helper
var billboard = null               # billboard.gd Sprite3D
var aim_line: MeshInstance3D = null
var last_snapshot: Dictionary = {} # the helper's snapshot from the latest sync (the proof reads it)
var _prev_st := ""
var _burst_tick := 0               # ticks since the row entered "attack" (the helper's burst clock)


func setup(folder: String) -> void:
	for child in get_children():
		child.free()
	var doc: Dictionary = {}
	var path := folder.path_join("sprites.json")
	var parsed: Variant = JSON.parse_string(AssetLoadScript.text(path))
	if parsed is Dictionary:
		doc = parsed
	helper = IsagiViewScript.new()
	helper.setup(doc)
	billboard = BillboardScript.new()
	add_child(billboard)
	if not doc.is_empty():
		billboard.setup_from_sheet(doc, folder)
	aim_line = MeshInstance3D.new()
	aim_line.name = "AimLine"
	var box := BoxMesh.new()
	box.size = Vector3(AIM_THICK, AIM_THICK, 1.0)   # unit length on Z, scaled per tick
	aim_line.mesh = box
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.164706, 0.164706)   # #FF2A2A, the hazard red
	m.disable_fog = true
	aim_line.material_override = m
	aim_line.visible = false
	add_child(aim_line)


## One sim tick. row is the live isagi row (read-only), player the nearest player's
## position row ({} = none), dt seconds, cam the camera position for the facing.
func sync_row(row: Dictionary, player: Dictionary, dt: float, cam: Vector3) -> void:
	if helper == null or billboard == null:
		return
	var st := str(row.get("st", "idle"))
	if st != _prev_st:
		_prev_st = st
		_burst_tick = 0
	else:
		_burst_tick += 1
	last_snapshot = helper.snapshot(row, player, _burst_tick)
	billboard.set_animation(st)
	billboard.advance_animation(dt)
	# the wind-up flash: red for the first half of each period, white for the second
	var period := int(last_snapshot.get("flash_period", 0))
	if period > 0:
		var t := int(IsagiViewScript.WINDUP_TICKS) - int(row.get("st_t", 0))
		var on := (t % period) < maxi(period / 2, 1)
		billboard.modulate = FLASH_RED if on else Color(1.0, 1.0, 1.0, 1.0)
	else:
		billboard.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_sync_aim(last_snapshot.get("aim", null))
	if cam != Vector3.ZERO:
		billboard.face_camera(cam)


func _sync_aim(aim: Variant) -> void:
	if aim_line == null:
		return
	if not (aim is Dictionary):
		aim_line.visible = false
		return
	var a: Vector3 = (aim as Dictionary)["from"] - position
	var b: Vector3 = (aim as Dictionary)["to"] - position
	var d := b - a
	var length := d.length()
	if length < 1e-4:
		aim_line.visible = false
		return
	aim_line.visible = true
	var mid := (a + b) * 0.5
	var up := Vector3.UP if absf(d.normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	aim_line.transform = Transform3D(Basis.looking_at(d, up), mid)
	aim_line.scale = Vector3(1.0, 1.0, length)
