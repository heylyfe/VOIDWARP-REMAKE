extends Node3D
#
# clawd view (cycle 7, track T4; D-T4-8). The clawd swarm's sprites, level-wide.
#
# The owner's words (CYCLE7_BRIEF.md T4): "plus clawd sprites (reuse the Claude logo sprite shrunk, or a simple
# procedural clawd icon)". This reuses the Claude logo frame (sprites/idle_00.png, the real art the T-016 pipeline
# produced) shrunk to CLAWD_SCALE, exactly the stand-in the old plushies used - now driven by sim/clawds.gd
# instead of an enemy row.
#
# View layer only: it READS the clawd state (spots / taken / anger_ticks) and never writes sim state. It is a
# level-wide node like gifts_view / jump_pad_view, not a child of the enemy view, because the swarm is not one
# body's property (D-T4-8).
#
# Everything animated is DERIVED from the sim tick - this node owns no clock:
#   bob        +-0.1 u on a 1 Hz sine of the sim tick
#   pop        a 9-tick white sphere at the spot a clawd was collected on
#   collapse   a clawd whose tile fell (taken by sweep) or is in the world's removed set is hidden
#   anger      the whole swarm tints toward the hazard red as the anger timer climbs to the kill

const SHEET_REL := "res://content/enemies/claude/sprites.json"
const FOLDER_REL := "res://content/enemies/claude"
const FRAME_REL := "sprites/idle_00.png"   # the real Claude logo frame (the T-016 art)

const CLAWD_SCALE := 0.6      # u, the sprite's body height (the old plushie stand-in's size)
const BOB_U := 0.1            # u, the idle bob amplitude
const BOB_HZ := 1.0
const POP_TICKS := 9          # the collected pop's length
const RED := Color(1.0, 0.164706, 0.164706)   # #FF2A2A, the game's hazard red

var _tex: Texture2D = null
var _root: Node3D = null
var _removed: Dictionary = {}
var _last_taken := 0
var _pop_at: Array = []       # [{x, y, z, tick}] the pops still drawing
var _anger := 0.0             # 0..1, the tint


func setup(clawds) -> void:
	for child in get_children():
		child.free()
	_root = Node3D.new()
	_root.name = "Clawds"
	add_child(_root)
	var full := FOLDER_REL + "/" + FRAME_REL
	_tex = load(full) if ResourceLoader.exists(full) else null
	_last_taken = 0
	_pop_at = []
	_anger = 0.0
	if clawds != null:
		_last_taken = int(clawds.count()) - int(clawds.remaining())


## The world's removed-tile set (a tile a curse dropped for a while): a clawd on one is hidden.
func set_removed(removed: Dictionary) -> void:
	_removed = removed


## One view frame. clawds is the sim object (read-only) or null; tick is the sim tick.
func sync(clawds, tick: int) -> void:
	if _root == null:
		return
	for c in _root.get_children():
		c.free()
	if clawds == null:
		return
	var taken_now := int(clawds.count()) - int(clawds.remaining())
	if taken_now > _last_taken:
		# a pickup this tick: pop at the spot that just went (the highest newly-taken id)
		for i in range(clawds.spots.size() - 1, -1, -1):
			if clawds.is_taken(i):
				var p: Vector3 = clawds.spot_pos(i)
				_pop_at.append({"x": p.x, "y": p.y, "z": p.z, "tick": tick})
				break
	_last_taken = taken_now
	_anger = clampf(float(clawds.anger_ticks) / maxf(float(clawds.kill_ticks), 1.0), 0.0, 1.0)
	var t := float(tick) / 60.0
	var bob: float = sin(t * TAU * BOB_HZ) * BOB_U
	for i in clawds.spots.size():
		if clawds.is_taken(i):
			continue
		var key: String = clawds.tile_key(i)
		if _removed.has(key):
			continue
		var pos: Vector3 = clawds.spot_pos(i)
		var spr := Sprite3D.new()
		if _tex != null:
			spr.texture = _tex
		spr.pixel_size = 0.01
		spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		spr.alpha_scissor_threshold = 0.5
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		spr.position = Vector3(pos.x, pos.y + bob, pos.z)
		var s: float = CLAWD_SCALE / 2.0   # the 2.0 u logo frame shrinks to the clawd
		spr.scale = Vector3(s, s, s)
		# the anger tint: the swarm reddens as the timer climbs (a warning the player can see)
		spr.modulate = Color(1.0, lerpf(1.0, RED.g, _anger), lerpf(1.0, RED.b, _anger), 1.0)
		_root.add_child(spr)
	_sync_pops(tick)


## The collected pops: a white sphere expanding and fading over POP_TICKS, then dropped.
func _sync_pops(tick: int) -> void:
	var keep: Array = []
	for p in _pop_at:
		var age := tick - int(p["tick"])
		if age < 0 or age > POP_TICKS:
			continue
		keep.append(p)
		var k := float(age) / float(POP_TICKS)
		var mi := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.2 + 0.5 * k
		sphere.height = sphere.radius * 2.0
		mi.mesh = sphere
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1, 1, 1, 1.0 - k)
		m.disable_fog = true
		mi.material_override = m
		mi.position = Vector3(float(p["x"]), float(p["y"]), float(p["z"]))
		_root.add_child(mi)
	_pop_at = keep
