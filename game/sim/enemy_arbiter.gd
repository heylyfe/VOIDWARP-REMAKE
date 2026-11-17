extends RefCounted
#
# enemy_arbiter.gd - the declarative scheduling gate (ticket T-072; DESIGN.md SR-4, D-067).
# A pure sim object: RefCounted only, floats through + - * / and sqrt, makes no engine call,
# and names no content id (test_boundaries.gd scans sim/ on every gate run).
#
# Each enemy row may declare, in plain data (the cfg `arbiter` block - the T-073 data pass
# supplies the ids; DATA never names anything here in code) - two lists:
#   "appear_requires": [ {"no_enemy_body_within": 12.0}, {"no_targeted_telegraph": true},
#                        {"player_grounded": true}, {"not_on_glitched_floor": true} ]
#       Requirement entries, all ANDed; the appearance may start only on a tick when every
#       entry it carries holds on the live sim state. An empty/absent list is always true.
#   "yields_to": ["<another row's id>", ...]
#       The gates named by that list outrank this one: while any of them holds a live
#       countdown, the caller defers THIS row (its own timer is unaffected - SR-4 defers the
#       call, the countdown keeps ticking, the call lands on the first free tick
#       that follows).
# Requirement vocabulary (fixed here; every value is read against the sim state):
#   "no_enemy_body_within": <u>   - no body within <u> of the player, 3D space
#   "no_targeted_telegraph": true - no live telegraph footprint covers the player
#   "player_grounded": true       - the player's controller is grounded
#   "not_on_glitched_floor": true - the player does not stand on a glitched tile
#
# Distance requirement form: 3D, from the body's row origin to the player's feet point
# (D-T072-1). A y band on a shape applies only when the shape carries one.

const REQ_BODY_WITHIN := "no_enemy_body_within"
const REQ_NO_TELEGRAPH := "no_targeted_telegraph"
const REQ_GROUNDED := "player_grounded"
const REQ_OFF_GLITCHED := "not_on_glitched_floor"


# Sources of live countdowns, held by DATA. `telegraphs` is the runtime's live telegraph
# list (an entry stays live while its ticks > 0; entry lifetime is the caller's - drop it
# when the strike lands); `pending` is any caller-side countdown a behavior keeps on its
# own row and passes through (an id array, data-owned, e.g. a rumble that is not a
# telegraph shape). One entry per source id, first-seen order.
static func busy_sources(telegraphs: Array, pending: Array = []) -> Array:
	var out: Array = []
	for t in telegraphs:
		if int(t.get("ticks", 0)) <= 0:
			continue
		var src := str(t.get("source", ""))
		if src != "" and not out.has(src):
			out.append(src)
	for id in pending:
		var s := str(id)
		if s != "" and not out.has(s):
			out.append(s)
	return out


# True when this row defers: any id of its `yields_to` list (DATA) holds a live countdown.
static func must_defer(cfg: Dictionary, sources: Array) -> bool:
	var y: Variant = cfg.get("yields_to", [])
	if y is Array:
		for id in y:
			if sources.has(str(id)):
				return true
	return false


# Does a telegraph's footprint (the same {"shape": ...} dictionary the caller announces)
# cover the point (x, y = feet, z)? Horizontal distance for circle/ring; the x/z bounds for
# box; a y band applies only when the shape carries one. Pure math, no world access.
static func point_in_shape(shape: Dictionary, px: float, py: float, pz: float) -> bool:
	var kind := str(shape.get("shape", "circle"))
	var ok := false
	if kind == "box":
		var x0 := float(shape.get("x0", px))
		var x1 := float(shape.get("x1", px))
		var z0 := float(shape.get("z0", pz))
		var z1 := float(shape.get("z1", pz))
		ok = px >= x0 - 1e-9 and px <= x1 + 1e-9 and pz >= z0 - 1e-9 and pz <= z1 + 1e-9
	elif kind == "ring":
		var cxr := px - float(shape["cx"])
		var czr := pz - float(shape["cz"])
		var r0 := float(shape.get("r0", 0.0))
		var d2 := cxr * cxr + czr * czr
		var r1 := float(shape["r1"])
		ok = d2 >= r0 * r0 - 1e-9 and d2 <= r1 * r1 + 1e-9
	else:
		var dx2 := px - float(shape.get("cx", px))
		var dz2 := pz - float(shape.get("cz", pz))
		var r: float = float(shape.get("r", 0.0))
		ok = dx2 * dx2 + dz2 * dz2 <= r * r + 1e-9
	if not ok:
		return false
	if shape.has("y0") or shape.has("y1"):
		var y0 := float(shape.get("y0", -1e9))
		var y1 := float(shape.get("y1", 1e9))
		return py >= y0 - 1e-9 and py <= y1 + 1e-9
	return true


# Any live telegraph footprint covering the player's feet point.
static func telegraph_on_player(telegraphs: Array, player) -> bool:
	for t in telegraphs:
		if int(t.get("ticks", 0)) <= 0:
			continue
		if point_in_shape(t.get("shape", {}), float(player.x), float(player.y), float(player.z)):
			return true
	return false


# True while the player stands on a glitched tile (the controller's current tile key
# against the world's glitched map - the live floor state, D-051).
static func on_glitched_floor(player, w: Dictionary) -> bool:
	if player == null or str(player.cur_key) == "":
		return false
	return w.get("glitched", {}).has(str(player.cur_key))


# One requirement entry against the live sim state. Unknown vocabulary is always false -
# a never-met requirement never drifts into an unconditional yes (an absent key would be
# a spelling error, not an allowance).
static func meets_requirement(req: Dictionary, player, w: Dictionary, tgr: Array) -> bool:
	if req.has(REQ_BODY_WITHIN):
		var lim := float(req[REQ_BODY_WITHIN])
		for b in bodies_arg(w):
			var dx3 := float(b[0]) - float(player.x)
			var dy3 := float(b[1]) - float(player.y)
			var dz3 := float(b[2]) - float(player.z)
			if dx3 * dx3 + dy3 * dy3 + dz3 * dz3 < lim * lim:
				return false
	elif req.has(REQ_NO_TELEGRAPH) and bool(req.get(REQ_NO_TELEGRAPH, false)):
		if telegraph_on_player(tgr, player):
			return false
	elif req.has(REQ_GROUNDED) and bool(req.get(REQ_GROUNDED, false)):
		if player == null or not bool(player.grounded):
			return false
	elif req.has(REQ_OFF_GLITCHED) and bool(req.get(REQ_OFF_GLITCHED, false)):
		if on_glitched_floor(player, w):
			return false
	return true


# The world's live body list as the distance requirement reads it ([x, y, z] per row -
# the runtime already mirrors exactly this shape).
static func bodies_arg(w: Dictionary) -> Array:
	var out: Array = []
	for b in w.get("enemies", []):
		out.append([float(b["x"]), float(b["y"]), float(b["z"])])
	return out


## One gate evaluation against the live sim state: the row's `arbiter` block (cfg),
## requirements, deferral. Returns
##   {"may_appear": bool, "deferred": bool}
## where "deferred" is meaningful only when may_appear is true: the row's yields_to ids
## (DATA) hold a live countdown, so the caller defers the call and its own timer keeps
## ticking (SR-4). player: the targeted controller row (the caller's target, not chosen
## here). w: the world dict (live bodies / glitched tiles). tgr: the live telegraphs.
## pending: optional caller-side countdown ids (data-owned).
static func evaluate(cfg: Dictionary, player, w: Dictionary, tgr: Array,
		pending: Array = []) -> Dictionary:
	var defer := must_defer(cfg, busy_sources(tgr, pending))
	if player == null:
		return {"may_appear": false, "deferred": defer}
	for req in cfg.get("appear_requires", []):
		if req is Dictionary and not meets_requirement(req, player, w, tgr):
			return {"may_appear": false, "deferred": defer}
	return {"may_appear": true, "deferred": defer}


## The row's cfg may defer (its yields_to ids hold a live countdown). Kept beside
## evaluate() for callers that only need the deferral answer.
static func defer_answer(cfg: Dictionary, tgr: Array, pending: Array = []) -> bool:
	return must_defer(cfg, busy_sources(tgr, pending))
