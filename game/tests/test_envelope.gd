extends RefCounted
#
# Envelope proof (ticket T-012, TERRAIN_SPEC section 5.1, retro section 4e): for every
# row of 5.1 the scripted jump clears the VALIDATOR gap at that height and fails at
# gap+2. The script models the table's x0.9 safety as a ~10%-early takeoff: the jump is
# pressed when the centre crosses (edge - 0.1 * raw reach), raw reach = 9 * t2 with
# t2 = (12 + sqrt(144 - 64*dy)) / 32 over the real controller and collision code.

const Util := preload("res://tests/sim_testutil.gd")
const CollisionScript := preload("res://sim/collision.gd")

# rows: [dy HU, validator gap cells, fail gap cells, trigger offset u]
const ROWS := [
	[0, 5, 7, 0.675],   # <= 0 HU
	[2, 4, 6, 0.589],   # <= +2 HU (+1.0 u)
	[4, 3, 5, 0.45],    # <= +4 HU (+2.0 u)
]
const UNREACH_DY_HU := 5   # "> +4 HU unreachable (apex 2.25 u)"


func run() -> Array[String]:
	var failures: Array[String] = []
	for row in ROWS:
		var dy_hu: int = row[0]
		var gap: int = row[1]
		var fail_gap: int = row[2]
		var trig: float = -row[3]
		_jumps_row(dy_hu, gap, trig, true, failures)
		_jumps_row(dy_hu, fail_gap, trig, false, failures)
	_unreachable_row(failures)
	_real_level(failures)
	return failures


func _arena(gap: int, dy_hu: int) -> Dictionary:
	var tiles: Array = []
	for cx in range(-14, 0):
		tiles.append([cx, 0, 0])
	for cx in range(gap, gap + 8):
		tiles.append([cx, 0, dy_hu])
	return Util.world_from_tiles(tiles)


func _jumps_row(dy_hu: int, gap: int, trig: float, expect: bool,
		failures: Array[String]) -> void:
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	var w := _arena(gap, dy_hu)
	# stand on the start platform (feet at its top, cell -8); no dais here
	ctl.x = -8.5
	ctl.y = 0.0
	ctl.z = 0.5
	ctl.vx = 0.0
	ctl.vy = 0.0
	ctl.vz = 0.0
	ctl.grounded = true
	ctl.cur_key = "-9,0,0"
	var jumped := false
	var landed := false
	var fell := false
	for i in range(300):
		var btn: int = 0
		if jumped or ctl.x >= trig:
			jumped = true
			btn = Util.ControllerScript.BTN_JUMP
		ctl.step(Util.DT, Util.mk_in(1, 0, btn), w)
		if ctl.y < -39.9:
			fell = true
		if ctl.grounded and absf(ctl.y - dy_hu * 0.5) < 0.03 and int(floor(ctl.x)) >= gap:
			landed = true
			break
	if landed != expect:
		failures.append("dy=+%d HU gap=%d: scripted jump %s, expected %s%s" % [
			dy_hu, gap, "landed" if landed else "did not land",
			"landing" if expect else "no landing",
			"" if landed else " (fell to the void)" if not fell else ""])


 # "> +4 HU unreachable": the base kit may never stand on a tile 5 HU (2.5 u) above,
# whatever the gap (apex 2.25 u, step-up 0.5 u).
func _unreachable_row(failures: Array[String]) -> void:
	var dy_hu := UNREACH_DY_HU
	for gap in [1, 3]:
		var ctl = Util.ControllerScript.new()
		ctl.setup("dasher", Util.consts())
		var w := _arena(gap, dy_hu)
		ctl.x = -8.5
		ctl.y = 0.0
		ctl.z = 0.5
		ctl.grounded = true
		ctl.cur_key = "-9,0,0"
		var jumped := false
		var landed := false
		for i in range(300):
			var btn: int = 0
			if jumped or ctl.x >= -0.3:
				jumped = true
				btn = Util.ControllerScript.BTN_JUMP
			ctl.step(Util.DT, Util.mk_in(1, 0, btn), w)
			if ctl.grounded and absf(ctl.y - dy_hu * 0.5) < 0.03 and int(floor(ctl.x)) >= gap:
				landed = true
				break
		if landed:
			failures.append("dy=+%d HU gap=%d: unreachable tile was landed on" % [dy_hu, gap])


# Real-level integration probe: the controller runs against an actual voidgen level
# (seed 7, level 12) — collision agrees with generator output, and a second identical
# drive reaches the same final state (replay determinism at one checkpoint; T-010 owns
# the full 3,600-tick hash replay).
func _real_level(failures: Array[String]) -> void:
	var VoidGen := preload("res://terrain/voidgen.gd")
	var L: Dictionary = VoidGen.generate(7, 12)
	if L.is_empty():
		failures.append("real level: voidgen.generate(7, 12) returned {}")
		return
	var w := CollisionScript.make_world(L["tiles"], L["props"], L["pads"])
	var ds: Array = []
	for rep in range(2):
		var ctl = Util.ControllerScript.new()
		ctl.setup("athletic", Util.consts())
		ctl.place(w)
		for i in range(600):
			var mx: int = 1 if (i / 40) % 2 == 0 else -1
			var btn: int = Util.ControllerScript.BTN_JUMP if i % 90 == 0 else 0
			ctl.step(Util.DT, Util.mk_in(mx, 0, btn), w)
		ds.append("%d,%d,%d,%d" % [ctl.x * 60.0, ctl.y * 60.0, ctl.z * 60.0, ctl.charges])
		if not is_finite(ctl.x) or not is_finite(ctl.y) or not is_finite(ctl.z):
			failures.append("real level: position left finite range")
			return
	if ds[0] != ds[1]:
		failures.append("real level: two identical drives diverged (%s vs %s)" % [ds[0], ds[1]])
	if float(ds[0].get_slice(",", 1)) <= -39.0 * 60.0:
		failures.append("real level: controller fell through the level (y %.2f)" % (float(ds[0].get_slice(",", 1)) / 60.0))
