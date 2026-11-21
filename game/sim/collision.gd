extends RefCounted
#
# Pure kinematic collision against the tile grid (D-047). No engine physics; deterministic:
# floats only, fixed 60 Hz tick, iteration over arrays or per-cell lookups, never over the
# column dictionaries. Constants come from data/player.json via sim/controller.gd.
#
# Geometry (TERRAIN_SPEC section 4):
#   tile  [x, z, y, kind, piece]  top surface at y * 0.5 u, solid slab 1.0 u thick below it.
#         kind 0 = flat; kind 1+d = ramp ascending toward direction d (0:+x 1:+z 2:-x 3:-z),
#         y is the LOW edge HU, high edge y+1 HU (0.5 u per 1 u).
#   prop  [x, z, y, h, kind, piece]  solid box from y*0.5 to (y+h)*0.5 u on one cell.
#   pad   [x, z, y, tx, tz, ty]    launch pad; landing on its tile throws the player onto
#                                  tile (tx, tz, ty) (ballistic; see controller).
# A tile under a prop is not walkable (the prop box blocks it); a body that comes down on
# the prop lands on the prop's own top, not inside the box (move_body).
#
# Body: axis-aligned box, half-width hw (0.4), height h (1.8), feet at y. Resolution order
# per move: X, then Z, then Y; auto step-up 0.5 u (1 HU) on horizontal blocks.

const SLAB := 1.0
const SKIN := 0.0001


# Builds a pure collision world from the level dict's arrays (tiles, props, pads).
# opts: { "dais": [x, z, y] } overrides the beacon-dais spawn tile (default spawns[0]).
@warning_ignore("integer_division")
static func make_world(tiles: Array, props: Array, pads: Array, opts: Dictionary = {}) -> Dictionary:
	var cols: Dictionary = {}
	var tile_index: int = 0
	for t in tiles:
		var key: String = "%d,%d" % [t[0], t[1]]
		var lst: Array = cols.get(key, [])
		if lst.is_empty():
			cols[key] = lst
		lst.append({"y": t[2], "kind": t[3], "i": tile_index})
		tile_index += 1
	var prop_cols: Dictionary = {}
	for p in props:
		var key: String = "%d,%d" % [p[0], p[1]]
		var lst: Array = prop_cols.get(key, [])
		if lst.is_empty():
			prop_cols[key] = lst
		lst.append({"y": p[2], "h": p[3]})
	var pad_at: Dictionary = {}
	for p in pads:
		pad_at["%d,%d" % [p[0], p[1]]] = {"tx": p[3], "tz": p[4], "ty": p[5]}
	var dais: Array = opts.get("dais", [1, 1, 1])
	if dais.size() < 3:
		dais = [1, 1, 1]
	return {
		"cols": cols,
		"prop_cols": prop_cols,
		"pads": pad_at,
		"dais": [dais[0], dais[1], dais[2]],
		"glitched": {},        # tile keys "x,z,y" -> true (glitch floor); state writes here
		"slippery": {},        # extra slippery tile keys (e.g. Wet Floor); friction x0.4
		"removed": {},         # tiles-modified set: destroyed tile keys are removed
		"kill_y": -40.0,
		# live state, refreshed by the sim each respawn/safe check:
		"enemies": [],         # [{"x", "y", "z", "r"}] world positions + hit radius
		"projectiles": [],     # same shape
		# hazard footprints at the check moment:
		# {"shape": "circle", "cx", "cz", "r"} | {"shape": "ring", "cx", "cz", "r0", "r1"}
		# | {"shape": "box", "x0", "z0", "x1", "z1"}; all optionally "y0"/"y1" world band.
		"hazards": [],
	}


static func tile_top(y_hu: int) -> float:
	return float(y_hu) * 0.5


static func tile_key(x: int, z: int, y_hu: int) -> String:
	return "%d,%d,%d" % [x, z, y_hu]


# True when the level still contains tile (x, z, y_hu) and it was not removed mid-level.
static func tile_alive(w: Dictionary, x: int, z: int, y_hu: int) -> bool:
	var col: Array = w["cols"].get("%d,%d" % [x, z], [])
	for t in col:
		if t["y"] == y_hu and not w["removed"].has(tile_key(x, z, y_hu)):
			return true
	return false


# Highest standable surface (tile top or ramp height) over the cells the AABB footprint
# covers, among surfaces no higher than feet + limit; -INF when none. When want_tile is
# true, also reports the tile entry + cell of the best surface: {"s", "cx", "cz", "tile"}.
static func support_at(w: Dictionary, px: float, pz: float, feet: float, limit: float,
		want_tile: bool = false) -> Variant:
	var best: float = -INF
	var best_tile: Variant = null
	var best_cx: int = -2147483648
	var best_cz: int = 0
	var hw: float = 0.4
	var x0 := int(floor(px - hw + SKIN))
	var x1 := int(floor(px + hw - SKIN))
	var z0 := int(floor(pz - hw + SKIN))
	var z1 := int(floor(pz + hw - SKIN))
	var cx := x0
	while cx <= x1:
		var cz := z0
		while cz <= z1:
			for t in w["cols"].get("%d,%d" % [cx, cz], []):
				if w["removed"].has(tile_key(cx, cz, t["y"])):
					continue
				var top: float = 0.0
				if t["kind"] == 0:
					top = tile_top(t["y"])
				else:
					top = _ramp_top_over(t, cx, cz, px, pz)
				if top <= feet + limit + SKIN and top > best:
					best = top
					best_tile = t
					best_cx = cx
					best_cz = cz
			cz += 1
		cx += 1
	if want_tile:
		return {"s": best, "cx": best_cx, "cz": best_cz, "tile": best_tile}
	return best


# Ramp height max over the sub-rectangle the AABB footprint covers of the ramp cell.
static func _ramp_top_over(t: Dictionary, cx: int, cz: int, px: float, pz: float) -> float:
	var d: int = t["kind"] - 1
	var lo: float
	var hi: float
	if d == 0 or d == 2:
		var a: float = clamp(px - 0.4 - float(cx), 0.0, 1.0)
		var b: float = clamp(px + 0.4 - float(cx), 0.0, 1.0)
		lo = a
		hi = b
	else:
		var a: float = clamp(pz - 0.4 - float(cz), 0.0, 1.0)
		var b: float = clamp(pz + 0.4 - float(cz), 0.0, 1.0)
		lo = a
		hi = b
	# d >= 2 ascends toward -x / -z (TERRAIN_SPEC section 4), so the surface falls along
	# +x / +z and the top of the footprint is its low end.
	if d >= 2:
		return (float(t["y"]) + 1.0 - lo) * 0.5
	var e_lo: float = (float(t["y"]) + lo) * 0.5
	var e_hi: float = (float(t["y"]) + hi) * 0.5
	return e_hi if e_hi > e_lo else e_lo


# Highest prop top over the cells the AABB footprint covers, among tops no higher than
# feet + limit; -INF when none. A prop is a horizontal blocker whose top nothing stands on,
# so move_body takes it as a landing candidate itself (a body that comes down on a prop cell
# would otherwise land inside the solid box); support_at stays tile-only so the safe-tile
# ring keeps its tile identity.
static func _prop_top_over(w: Dictionary, px: float, pz: float, feet: float,
		limit: float) -> float:
	var best: float = -INF
	var hw: float = 0.4
	var x0 := int(floor(px - hw + SKIN))
	var x1 := int(floor(px + hw - SKIN))
	var z0 := int(floor(pz - hw + SKIN))
	var z1 := int(floor(pz + hw - SKIN))
	var cx := x0
	while cx <= x1:
		var cz := z0
		while cz <= z1:
			for p in w["prop_cols"].get("%d,%d" % [cx, cz], []):
				var top: float = tile_top(p["y"] + p["h"])
				if top <= feet + limit + SKIN and top > best:
					best = top
			cz += 1
		cx += 1
	return best


# Solid boxes in one cell column: tile slabs [top-1, top] (ramps: low-edge lip
# [lowTop-1, lowTop]) and prop boxes [base, base+h] (world u). Appended to `out`.
static func _boxes_in_column(w: Dictionary, cx: int, cz: int, out: Array) -> void:
	for t in w["cols"].get("%d,%d" % [cx, cz], []):
		if w["removed"].has(tile_key(cx, cz, t["y"])):
			continue
		out.append({"lo": tile_top(t["y"]) - SLAB, "hi": tile_top(t["y"])})
	for p in w["prop_cols"].get("%d,%d" % [cx, cz], []):
		out.append({"lo": tile_top(p["y"]), "hi": tile_top(p["y"] + p["h"])})


# Horizontal block probe at body position (nx, nz) with feet fy, height h. Returns
# {hit, step_top} where for each solid box overlapping the y-window (fy, fy + h):
# hit = true when any box overlaps at all; step_top = the highest box top within
# feet + step_up (the step-up candidate; -INF when none); step-blocked = true when a
# box overlaps whose top is above feet + step_up (a real wall).
static func _blocked(w: Dictionary, nx: float, nz: float, fy: float, h: float,
		step_up: float) -> Dictionary:
	var hit := false
	var wall := false
	var step_top: float = -INF
	var lo_y: float = fy + SKIN
	var hi_y: float = fy + h - SKIN
	var boxes: Array = []
	var x0 := int(floor(nx - 0.4 + SKIN))
	var x1 := int(floor(nx + 0.4 - SKIN))
	var z0 := int(floor(nz - 0.4 + SKIN))
	var z1 := int(floor(nz + 0.4 - SKIN))
	var cx := x0
	while cx <= x1:
		var cz := z0
		while cz <= z1:
			boxes.clear()
			_boxes_in_column(w, cx, cz, boxes)
			for b in boxes:
				if b["lo"] < hi_y and b["hi"] > lo_y:
					hit = true
					if b["hi"] > fy + step_up + SKIN:
						wall = true
					elif b["hi"] > step_top:
						step_top = b["hi"]
			cz += 1
		cx += 1
	return {"hit": hit, "wall": wall, "step_top": step_top}


# Bisects the fraction f in [0, 1] of the move from (x0, z0) toward (x1, z1) keeping the
# position unblocked. Returns the largest safe fraction found (>= 0).
static func _free_frac(w: Dictionary, x0: float, z0: float, x1: float, z1: float,
		fy: float, h: float, step_up: float) -> float:
	var lo_f: float = 0.0
	var hi_f: float = 1.0
	var guard: int = 0
	while guard < 20:
		guard += 1
		var mid: float = (lo_f + hi_f) * 0.5
		var r: Dictionary = _blocked(w, x0 + (x1 - x0) * mid, z0 + (z1 - z0) * mid, fy, h, step_up)
		if not r["hit"]:
			lo_f = mid
		else:
			hi_f = mid
	return lo_f


# True when the body box at (nx, nz) with feet fy has no solid box in its full y-range.
static func _free_at(w: Dictionary, nx: float, nz: float, fy: float, h: float,
		step_up: float) -> bool:
	return not _blocked(w, nx, nz, fy, h, step_up)["hit"]


# One kinematic move step for a body of half-width 0.4 and height h, feet at y.
# Resolution order: X, then Z (each with auto step-up, only from a standing start),
# then Y (land / snap / ceiling). was_grounded enables step-up and the snap-down onto
# surfaces within a step below (ramp descent); an airborne body is wall-clamped only.
# Returns {x, y, z, grounded, stepped, hit_ceiling}.
static func move_body(w: Dictionary, x: float, y: float, z: float,
		dx: float, dy: float, dz: float, h: float, step_up: float,
		was_grounded: bool) -> Dictionary:
	var stepped := false
	if dx != 0.0:
		var nx: float = x + dx
		var r: Dictionary = _blocked(w, nx, z, y, h, step_up)
		if not r["hit"]:
			x = nx
		elif was_grounded and not r["wall"] and r["step_top"] > -INF and \
				_free_at(w, nx, z, r["step_top"], h, step_up):
			y = r["step_top"]
			x = nx
			stepped = true
		else:
			var f: float = _free_frac(w, x, z, nx, z, y, h, step_up)
			x = x + (nx - x) * f
	if dz != 0.0:
		var nz: float = z + dz
		var r2: Dictionary = _blocked(w, x, nz, y, h, step_up)
		if not r2["hit"]:
			z = nz
		elif was_grounded and not r2["wall"] and r2["step_top"] > -INF and \
				_free_at(w, x, nz, r2["step_top"], h, step_up):
			y = r2["step_top"]
			z = nz
			stepped = true
		else:
			var f2: float = _free_frac(w, x, z, x, nz, y, h, step_up)
			z = z + (nz - z) * f2
	var ny: float = y + dy
	var grounded := false
	var hit_ceiling := false
	if dy > 0.0:
		# rising: clamp under the lowest box bottom in the swept head band
		var best: float = INF
		var boxes: Array = []
		var x0 := int(floor(x - 0.4 + SKIN))
		var x1 := int(floor(x + 0.4 - SKIN))
		var z0 := int(floor(z - 0.4 + SKIN))
		var z1 := int(floor(z + 0.4 - SKIN))
		var cx := x0
		while cx <= x1:
			var cz := z0
			while cz <= z1:
				boxes.clear()
				_boxes_in_column(w, cx, cz, boxes)
				for b in boxes:
					if b["lo"] >= y + h - SKIN and b["lo"] <= ny + h - SKIN and b["lo"] < best:
						best = b["lo"]
				cz += 1
			cx += 1
		if best != INF:
			ny = best - h - SKIN
			hit_ceiling = true
	elif dy < 0.0:
		# falling: land on the highest surface in the swept band [ny, y + step_up]
		var s: float = maxf(float(support_at(w, x, z, y, step_up)),
				_prop_top_over(w, x, z, y, step_up))
		if s != -INF and s >= ny - SKIN:
			ny = s
			grounded = true
		elif was_grounded and s != -INF and s >= y - step_up - SKIN:
			# Item 13: the snap-down. A standing body always arrives here with
			# dy = -g x dt (0.0089 u at 60 Hz), never dy == 0, so the dy == 0 branch
			# below could not catch a descent: a ramp drops 0.075 u per tick at run
			# speed, and stairs 0.5 u per tread, both below one tick of gravity, so the
			# body went ballistic and hopped down the slope (grounded flickering, the
			# body 0.0-0.28 u over the surface). A body that stood last tick follows a
			# surface up to one step below, the mirror of the step-up.
			ny = s
			grounded = true
	elif was_grounded:
		# dy == 0 and was standing: snap onto whatever surface is within a step
		var s3: Dictionary = support_at(w, x, z, y, step_up, true)
		var s3s: float = maxf(float(s3["s"]), _prop_top_over(w, x, z, y, step_up))
		if s3s != -INF and s3s >= ny - SKIN:
			ny = s3s
			grounded = true
	# standing re-check after y settles (stays grounded across dy == 0 ticks)
	if not grounded and dy <= 0.0:
		var s2: float = maxf(float(support_at(w, x, z, ny, SKIN)),
				_prop_top_over(w, x, z, ny, SKIN))
		if s2 != -INF and s2 >= ny - SKIN:
			ny = s2
			grounded = true
	return {"x": x, "y": ny, "z": z, "grounded": grounded, "stepped": stepped,
			"hit_ceiling": hit_ceiling}
