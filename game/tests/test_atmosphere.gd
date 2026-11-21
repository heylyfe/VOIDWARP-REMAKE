extends RefCounted
#
# Atmosphere pass (DECISIONS D-ATMO-1..3): the procedural cloud dome (view/sky_dome.gd), the
# floating contour-outlined rocks (view/debris.gd) and the retuned light numbers.
#   leg 1  both build on a REAL world (world.build) and are found by name; the dome material
#          has fog off, depth write off, inside faces, the minimum render priority
#   leg 2  the rock field is identical for the same seed, different for another seed, and the
#          world placed it from (seed, level)
#   leg 3  count / size / radius / colours come from data (palette.json and an override cfg);
#          every rock sits outside the level radius; each rock hull is convex, 20..40 tris
#   leg 4  NEGATIVE CONTROL: a field drawn from an unseeded RNG fails the leg-2 sameness check
#   leg 5  the sim state hash is byte-identical every tick with the atmosphere on and off
#          (and the off world really has no dome / rocks, so the comparison is not vacuous)
#   leg 6  the fog readability thresholds (tools/fog_check.gd) still pass for every biome,
#          and the retuned ambient / void glow energies reach the live scene from data
#   leg 7  the atmosphere adds no collision: no CollisionObject3D / CollisionShape3D under it

const WorldScript := preload("res://app/world.gd")
const SkyDomeScript := preload("res://view/sky_dome.gd")
const DebrisScript := preload("res://view/debris.gd")
const FogEnvScript := preload("res://view/fog_env.gd")
const FogCheckScript := preload("res://tools/fog_check.gd")
const VoidGenScript := preload("res://terrain/voidgen.gd")
const RunStateScript := preload("res://sim/run_state.gd")
const HashScript := preload("res://sim/state_hash.gd")

const DT := 1.0 / 60.0
const SEED := 7
const LEVEL := 1
const HASH_TICKS := 240


class FixedInputWorld:
	extends WorldScript
	var n := 0
	func _capture_input():
		n += 1
		# walk forward, turn now and then, jump every 50 ticks: enough to move the sim
		return {"move_x": 40 if (n / 60) % 2 == 0 else -30, "move_z": -90,
				"buttons": 1 if n % 50 == 0 else 0, "aim_x": 0.0, "aim_z": -1.0, "app": 0}


func _root() -> Node:
	var ml := Engine.get_main_loop()
	return (ml as SceneTree).root if ml is SceneTree else null


func _drop(world) -> void:
	world.teardown()
	if world.get_parent() != null:
		world.get_parent().remove_child(world)
	world.free()


func _build(atmo: bool) -> Node:
	var world = FixedInputWorld.new()
	world.atmosphere = atmo
	var root := _root()
	if root != null:
		root.add_child(world)
	if not world.build(SEED, LEVEL):
		_drop(world)
		return null
	return world


func run() -> Array[String]:
	var f: Array[String] = []
	_leg_world(f)
	_leg_determinism(f)
	_leg_data(f)
	_leg_negative_control(f)
	_leg_hash(f)
	_leg_fog_and_light(f)
	return f


## Canonical text of a layout (exact float bits via var_to_str), for sameness checks.
static func _sig(rows: Array) -> String:
	var parts: PackedStringArray = []
	for r in rows:
		parts.append(var_to_str([r["pos"], r["size"], r["variant"], r["axes"], r["rot"],
				r["spin"], r["phase"]]))
	return "\n".join(parts)


## The leg-2 determinism check, shared with the negative control.
static func _same(a: Array, b: Array) -> bool:
	return a.size() == b.size() and _sig(a) == _sig(b)


func _leg_world(f: Array[String]) -> void:
	var world := _build(true)
	if world == null:
		f.append("leg 1: world.build(%d, %d) failed" % [SEED, LEVEL])
		return
	var dome = world.get_node_or_null("SkyDome")
	var rocks = world.get_node_or_null("Debris")
	if dome == null or rocks == null:
		f.append("leg 1: the world has no SkyDome (%s) / Debris (%s) child" % [dome, rocks])
		_drop(world)
		return
	if dome.mesh == null or dome.shader_material == null:
		f.append("leg 1: the dome built no mesh / material")
	else:
		var code: String = dome.shader_material.shader.code
		for mode in ["fog_disabled", "depth_draw_never", "cull_front", "unshaded"]:
			if not code.contains(mode):
				f.append("leg 1: the dome shader lacks render_mode %s" % mode)
		if dome.shader_material.render_priority != Material.RENDER_PRIORITY_MIN:
			f.append("leg 1: dome render_priority %d, want %d" % [
					dome.shader_material.render_priority, Material.RENDER_PRIORITY_MIN])
		var sky := SkyDomeScript.load_config()
		var z: Color = dome.shader_material.get_shader_parameter("zenith")
		if not z.is_equal_approx(Color(str(sky["zenith"]))):
			f.append("leg 1: the dome zenith %s is not the data colour %s" % [z, sky["zenith"]])
		if absf(float((dome.mesh as SphereMesh).radius) - float(sky.get("radius", 450.0))) > 1e-3:
			f.append("leg 1: dome radius is not the data radius")
	for code in [DebrisScript.BODY_SHADER, DebrisScript.OUTLINE_SHADER]:
		if not (code as String).contains("fog_disabled"):
			f.append("leg 1: a rock shader is fogged")
	if not (DebrisScript.OUTLINE_SHADER as String).contains("cull_front"):
		f.append("leg 1: the outline is not an inverted (cull_front) hull")
	# leg 2 (world side): the world placed the field from (seed, level)
	var expect := DebrisScript.layout(hash([SEED, LEVEL]), DebrisScript.load_config())
	if not _same(rocks.rocks, expect):
		f.append("leg 2: the world rock field is not layout(hash([seed, level]))")
	# leg 7: no collision anywhere under the atmosphere
	for host in [dome, rocks]:
		for n in (host as Node).find_children("*", "", true, false):
			if n is CollisionObject3D or n is CollisionShape3D:
				f.append("leg 7: %s has a collision node %s" % [host.name, n.name])
	_drop(world)


func _leg_determinism(f: Array[String]) -> void:
	var cfg := DebrisScript.load_config()
	var a := DebrisScript.layout(1234, cfg)
	var b := DebrisScript.layout(1234, cfg)
	var c := DebrisScript.layout(1235, cfg)
	if a.is_empty():
		f.append("leg 2: the shipped debris count is 0")
	if not _same(a, b):
		f.append("leg 2: the same seed gave two different rock fields")
	if _same(a, c):
		f.append("leg 2: seeds 1234 and 1235 gave the same rock field")
	# the rock shapes are seeded too: two configures of one seed mesh the same vertices
	var n1 = DebrisScript.new()
	var n2 = DebrisScript.new()
	n1.configure(1234, cfg)
	n2.configure(1234, cfg)
	var m1: ArrayMesh = (n1.get_child(0) as MultiMeshInstance3D).multimesh.mesh
	var m2: ArrayMesh = (n2.get_child(0) as MultiMeshInstance3D).multimesh.mesh
	if var_to_str(m1.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]) != var_to_str(m2.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]):
		f.append("leg 2: the same seed meshed two different rock shapes")
	n1.free()
	n2.free()


func _leg_data(f: Array[String]) -> void:
	var cfg := DebrisScript.load_config()
	var rows := DebrisScript.layout(99, cfg)
	if rows.size() != int(cfg["count"]):
		f.append("leg 3: %d rocks, data count %d" % [rows.size(), int(cfg["count"])])
	# the widest level the generator makes (t caps at 30)
	var level_r := float(VoidGenScript.tuning(30, 1)["radius"])
	if float(cfg["min_radius"]) <= level_r + 30.0:
		f.append("leg 3: debris min_radius %.1f is not well outside the level radius %.1f"
				% [float(cfg["min_radius"]), level_r])
	for r in rows:
		var s := float(r["size"])
		if s < float(cfg["min_size"]) - 1e-6 or s > float(cfg["max_size"]) + 1e-6:
			f.append("leg 3: rock size %.3f outside data %s..%s" % [s, cfg["min_size"], cfg["max_size"]])
			break
		var p: Vector3 = r["pos"]
		var d := Vector2(p.x, p.z).length()
		if d < float(cfg["min_radius"]) - 1e-3 or d > float(cfg["max_radius"]) + 1e-3:
			f.append("leg 3: rock at %.1f u, data ring %s..%s" % [d, cfg["min_radius"], cfg["max_radius"]])
			break
	# an override cfg drives the node: count, sizes and colours all follow it
	var o := cfg.duplicate()
	o["count"] = 7
	o["min_size"] = 2.0
	o["max_size"] = 2.5
	o["outline_hex"] = "#123456"
	var node = DebrisScript.new()
	node.configure(5, o)
	var total := 0
	var outline_total := 0
	for c in node.get_children():
		if (c.name as String).begins_with("RockBody"):
			total += (c as MultiMeshInstance3D).multimesh.instance_count
		else:
			outline_total += (c as MultiMeshInstance3D).multimesh.instance_count
	if node.rocks.size() != 7 or total != 7 or outline_total != 7:
		f.append("leg 3: override count 7 gave rows=%d bodies=%d outlines=%d"
				% [node.rocks.size(), total, outline_total])
	for r in node.rocks:
		if float(r["size"]) < 2.0 or float(r["size"]) > 2.5:
			f.append("leg 3: override size range ignored (%.3f)" % float(r["size"]))
			break
	var oc: Color = node.outline_material.get_shader_parameter("outline")
	if not oc.is_equal_approx(Color("#123456")):
		f.append("leg 3: the outline colour is not the cfg outline_hex")
	if absf(float(node.outline_material.get_shader_parameter("width_px")) - float(o["outline_width"])) > 1e-6:
		f.append("leg 3: the outline width is not the cfg outline_width")
	# every rock hull is convex and low-poly
	for c in node.get_children():
		if not (c.name as String).begins_with("RockBody"):
			continue
		var verts: PackedVector3Array = (c as MultiMeshInstance3D).multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var tris := verts.size() / 3
		if tris < 20 or tris > 40:
			f.append("leg 3: %s has %d triangles, want 20..40" % [c.name, tris])
		for t in tris:
			var a := verts[t * 3]
			var nrm := (verts[t * 3 + 2] - a).cross(verts[t * 3 + 1] - a).normalized()
			for v in verts:
				if nrm.dot(v - a) > 1e-4:
					f.append("leg 3: %s is not convex (a vertex is in front of face %d)" % [c.name, t])
					break
	node.free()


func _leg_negative_control(f: Array[String]) -> void:
	var cfg := DebrisScript.load_config()
	var r1 := RandomNumberGenerator.new()
	r1.randomize()
	var r2 := RandomNumberGenerator.new()
	r2.randomize()
	var a := DebrisScript.layout(1234, cfg, r1)
	var b := DebrisScript.layout(1234, cfg, r2)
	if _same(a, b):
		f.append("leg 4 (negative control): two unseeded fields passed the sameness check - leg 2 proves nothing")
	else:
		print("ATMO negative control: unseeded RNG fields differ -> the determinism check FAILS them, as it must")


## Per-tick state hashes of a FixedInputWorld, read through sim/state_hash.gd.
func _hash_run(atmo: bool, f: Array[String]) -> PackedStringArray:
	var out := PackedStringArray()
	var world := _build(atmo)
	if world == null:
		f.append("leg 5: build failed (atmosphere=%s)" % atmo)
		return out
	if atmo != (world.get_node_or_null("SkyDome") != null and world.get_node_or_null("Debris") != null):
		f.append("leg 5: atmosphere=%s but the dome/rocks presence does not match" % atmo)
	var rs = RunStateScript.new_run(SEED, 1, [])
	rs.level_number = LEVEL
	for t in HASH_TICKS:
		world.step(DT)
		if world.lstate == null:
			break
		rs.level = world.lstate
		out.append(HashScript.sha256(rs))
	_drop(world)
	return out


func _leg_hash(f: Array[String]) -> void:
	var on := _hash_run(true, f)
	var off := _hash_run(false, f)
	if on.size() != HASH_TICKS or off.size() != HASH_TICKS:
		f.append("leg 5: hashed %d / %d ticks, want %d" % [on.size(), off.size(), HASH_TICKS])
		return
	if on[0] == on[HASH_TICKS - 1]:
		f.append("leg 5: the hash never moved over %d ticks - the comparison is vacuous" % HASH_TICKS)
	for t in HASH_TICKS:
		if on[t] != off[t]:
			f.append("leg 5: the state hash differs at tick %d with the atmosphere on vs off" % t)
			return
	print("ATMO hash on==off over %d ticks, final %s" % [HASH_TICKS, on[HASH_TICKS - 1]])


func _leg_fog_and_light(f: Array[String]) -> void:
	var failures: Array = []
	var checked := 0
	for id in FogCheckScript._biome_ids():
		checked += FogCheckScript._check_biome(str(id), failures)
	if checked == 0:
		f.append("leg 6: the fog check ran no rows")
	for x in failures:
		f.append("leg 6: fog check failed: %s" % x)
	var roles: Dictionary = FogEnvScript.load_palette()["roles"]
	var world := _build(true)
	if world == null:
		f.append("leg 6: build failed")
		return
	var env: Environment = world.fog.environment
	if absf(env.ambient_light_energy - float(roles["ambient"]["energy"])) > 1e-6:
		f.append("leg 6: live ambient energy %.3f is not the data %.3f"
				% [env.ambient_light_energy, float(roles["ambient"]["energy"])])
	var key := world.get_node_or_null("VoidGlow") as DirectionalLight3D
	if key == null or absf(key.light_energy - float(roles["void_glow"]["energy"])) > 1e-6:
		f.append("leg 6: the VoidGlow light is missing or not the data energy")
	elif key.shadow_enabled:
		f.append("leg 6: VoidGlow casts shadows (palette: no directional shadows)")
	_drop(world)
