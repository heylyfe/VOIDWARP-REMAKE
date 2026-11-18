extends RefCounted
#
# Ramp surface height, all four kinds (TERRAIN_SPEC section 4; collision.gd _ramp_top_over).
# kind 1+d = ramp ascending toward direction d (0:+x 1:+z 2:-x 3:-z); the tile's y is the LOW
# edge, the high edge is y+1 HU. With f the local fraction along the slope axis (x - cx or
# z - cz), the spec surface is
#   d 0 / 1:  (y + f) * 0.5 u          (low edge at f = 0, high edge at f = 1)
#   d 2 / 3:  (y + 1 - f) * 0.5 u      (low edge at f = 1, high edge at f = 0)
# A body (half-width 0.4) stands on the HIGHEST point of the spec surface its footprint covers.
# Each kind is probed with the body centred on the low edge, 0.2 in from it, the middle, 0.2 in
# from the high edge and on the high edge, at two cross-axis offsets, through both the private
# _ramp_top_over and the public support_at, against (a) a hard-coded value and (b) a brute-force
# max of the spec formula over the clamped footprint. Kinds 1 and 2 must also stay bit-identical
# to the original single formula (max of the two clamped footprint ends, T-012), which was right
# for the +x / +z kinds and mirrored for kinds 3 and 4 (PARKED row 26).

const Collision := preload("res://sim/collision.gd")

const HW := 0.4
# body centre's distance from the LOW edge -> footprint max above the low edge, in HU
# (min(s + 0.4, 1)): the hard-coded half of the expectation.
const PROBES := [[0.0, 0.4], [0.2, 0.6], [0.5, 0.9], [0.8, 1.0], [1.0, 1.0]]
# [cx, cz, y]: one ordinary cell, one at negative coordinates with a negative height.
const CELLS := [[3, -2, 4], [-5, 7, -3]]
const CROSS := [0.5, 0.05]


func run() -> Array[String]:
	var f: Array[String] = []
	_test_four_kinds(f)
	_test_kinds_1_2_unchanged(f)
	return f


# The spec surface at local fractions (fx, fz) of a ramp cell.
static func _spec_surface(kind: int, y: int, fx: float, fz: float) -> float:
	match kind - 1:
		0:
			return (float(y) + fx) * 0.5
		1:
			return (float(y) + fz) * 0.5
		2:
			return (float(y) + 1.0 - fx) * 0.5
		3:
			return (float(y) + 1.0 - fz) * 0.5
	return NAN


# Brute force: the max of the spec surface over a 41 x 41 grid spanning the footprint clamped
# to the cell. The surface is linear, so its max sits on a clamped corner, which the grid
# includes exactly (both endpoints of each axis are samples).
static func _spec_footprint_max(kind: int, y: int, fx_c: float, fz_c: float) -> float:
	var x0: float = clampf(fx_c - HW, 0.0, 1.0)
	var x1: float = clampf(fx_c + HW, 0.0, 1.0)
	var z0: float = clampf(fz_c - HW, 0.0, 1.0)
	var z1: float = clampf(fz_c + HW, 0.0, 1.0)
	var best := -INF
	for i in range(41):
		var fx: float = x1 if i == 40 else x0 + (x1 - x0) * float(i) / 40.0
		for j in range(41):
			var fz: float = z1 if j == 40 else z0 + (z1 - z0) * float(j) / 40.0
			best = maxf(best, _spec_surface(kind, y, fx, fz))
	return best


func _test_four_kinds(f: Array[String]) -> void:
	for kind in range(1, 5):
		var d: int = kind - 1
		var on_x: bool = d % 2 == 0
		var falls: bool = d >= 2   # low edge at local 1, high edge at local 0
		for cell in CELLS:
			var cx: int = cell[0]
			var cz: int = cell[1]
			var y: int = cell[2]
			var t := {"y": y, "kind": kind}
			var w := Collision.make_world([[cx, cz, y, kind, 0]], [], [])
			for probe in PROBES:
				var s: float = probe[0]
				var want: float = (float(y) + float(probe[1])) * 0.5
				var along: float = 1.0 - s if falls else s
				for cross in CROSS:
					var fx: float = along if on_x else cross
					var fz: float = cross if on_x else along
					var px: float = float(cx) + fx
					var pz: float = float(cz) + fz
					var brute: float = _spec_footprint_max(kind, y, fx, fz)
					var got: float = Collision._ramp_top_over(t, cx, cz, px, pz)
					var sup: float = Collision.support_at(w, px, pz, 1000.0, 0.5)
					var where := "kind %d cell (%d,%d) y %d, centre %.1f from the low edge (local %s %.2f, cross %.2f)" % [
						kind, cx, cz, y, s, "x" if on_x else "z", along, cross]
					if absf(want - brute) > 1e-9:
						f.append("ramp surface: the test's own tables disagree at %s: %.6f vs brute %.6f" % [
							where, want, brute])
					if absf(got - want) > 1e-9:
						f.append("ramp surface: _ramp_top_over %.6f at %s, want %.6f" % [got, where, want])
					if absf(sup - want) > 1e-9:
						f.append("ramp surface: support_at %.6f at %s, want %.6f" % [sup, where, want])


# Kinds 1 and 2 (ascending +x / +z) are the original formula, bit for bit: the body's surface is
# the larger of the spec heights at the two clamped footprint ends along the slope axis.
func _test_kinds_1_2_unchanged(f: Array[String]) -> void:
	for kind in [1, 2]:
		var on_x: bool = kind == 1
		for cell in CELLS:
			var cx: int = cell[0]
			var cz: int = cell[1]
			var y: int = cell[2]
			var t := {"y": y, "kind": kind}
			for i in range(0, 61):
				# centres from 0.4 u before the cell to 0.4 u past it, in 0.03 u steps
				var along: float = -0.4 + float(i) * 0.03
				var px: float = float(cx) + (along if on_x else 0.5)
				var pz: float = float(cz) + (0.5 if on_x else along)
				var p: float = px if on_x else pz
				var c: float = float(cx) if on_x else float(cz)
				var lo: float = clamp(p - 0.4 - c, 0.0, 1.0)
				var hi: float = clamp(p + 0.4 - c, 0.0, 1.0)
				var e_lo: float = (float(y) + lo) * 0.5
				var e_hi: float = (float(y) + hi) * 0.5
				var want: float = e_hi if e_hi > e_lo else e_lo
				var got: float = Collision._ramp_top_over(t, cx, cz, px, pz)
				if got != want:
					f.append("ramp surface: kind %d at local %.2f gives %.17f, the original formula %.17f" % [
						kind, along, got, want])
