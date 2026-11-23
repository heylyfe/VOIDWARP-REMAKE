extends RefCounted
#
# test_player_anim_baseline.gd - the jump, fall and stairs-up poses are FROZEN (U1).
#
# The owner asked for the level's idle/walk/run to become the Antechamber's animation and
# said the jump, the fall and the stairs-up pose are good as they are. "Unchanged" is not a
# comment here: the posed transforms of those three poses were captured from the tree
# BEFORE the change (aac250b) and are recorded in BASELINE below. Every run re-stages the
# same three sheet poses through the real controller and the real world.gd animation pass,
# samples the same render frames, and compares a SHA-256 over every posed transform.
#
# What is hashed: the six limb nodes (Torso, Head, ArmL, ArmR, LegL, LegR) and the rig's
# two shins, two boots and two forearms, each node's LOCAL transform (basis rows then
# origin) rounded to 0.0001 u / 0.0001 rad. Local, so the hash is the POSE and not the
# figure's position on the course. A pose that moves by 0.1 mm fails.
#
# The three cases are the contact sheet's own poses (test_player_anim.gd POSES), staged by
# the same stage/warm_up/tick helpers the sheet tool uses, so the baseline and the sheet
# show the same motion:
#   jump       the jump sheet, frames 20/40/60 of its 0.75 s span (the tuck and the apex)
#   fall       the land sheet's last airborne frames 0/2/4 (the braced fall pose)
#   up_stairs  the up-stairs sheet, frames 20/40/60 (the owner's "stairs-up pose is fine")

const AnimTest := preload("res://tests/test_player_anim.gd")
const WorldScript := preload("res://app/world.gd")
const RENDER_DT := 1.0 / 120.0

## pose name, index into AnimTest.POSES, the render frames sampled inside the span
const CASES := [
	["jump", 11, [20, 40, 60]],
	["fall", 12, [0, 2, 4]],
	["up_stairs", 9, [20, 40, 60]],
]

## Captured from aac250b, before the U1 change. An empty string means "print it and do not
## compare" - that is how the baseline was recorded, and it is never how it ships.
const BASELINE := {
	"jump": "e8cf80688f48791e4b41a122409e5a4a268b8f4a360d42d7d7706b543f75f334",
	"fall": "f329e66e15734b6941bf5af638618c5d249a09bd574496f46c8530585b6586d1",
	"up_stairs": "1de2d489bc34703aae0ee673a2978043a5c3b2580e27d2e9dc81595a864f67f4",
}


func run() -> Array[String]:
	var f: Array[String] = []
	for case in CASES:
		var digest := _digest(case)
		var want: String = BASELINE[case[0]]
		if want == "":
			print("BASELINE %s %s" % [case[0], digest])
			continue
		if digest != want:
			f.append("baseline %s: the posed transforms changed (%s, want %s)"
					% [case[0], digest, want])
	return f


## Stages the case's sheet pose, runs it to the last sampled frame, and hashes every posed
## transform at each sampled frame.
func _digest(case: Array) -> String:
	var pose: Array = AnimTest.POSES[int(case[1])]
	var world = WorldScript.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	world.set_process(false)
	AnimTest.stage(world, pose)
	AnimTest.warm_up(world, pose)
	var rig = world._leg_rig
	var parts: Array = world._limbs.duplicate()
	parts.append_array(rig.shins + rig.boots + rig.forearms)
	var frames: Array = case[2]
	var last := 0
	for frame in frames:
		last = maxi(last, int(frame))
	var text := PackedStringArray()
	for frame in last + 1:
		if frame % 2 == 0:
			var held: Array[bool] = AnimTest.buttons_at(pose, frame)
			AnimTest.tick(world, pose, held[0], held[1])
		world._process(RENDER_DT)
		if frames.has(frame):
			for part in parts:
				text.append(_fmt((part as Node3D).transform))
	world.free()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update("\n".join(text).to_utf8_buffer())
	return ctx.finish().hex_encode()


## A transform as 12 rounded numbers: the three basis rows, then the origin.
static func _fmt(t: Transform3D) -> String:
	var out := PackedStringArray()
	for row in [t.basis.x, t.basis.y, t.basis.z, t.origin]:
		for v in [row.x, row.y, row.z]:
			out.append("%.4f" % v)
	return ",".join(out)
