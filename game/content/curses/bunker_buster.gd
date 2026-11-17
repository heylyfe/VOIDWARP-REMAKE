extends RefCounted
#
# bunker_buster.gd - script curse (ticket T-051; DESIGN.md section 7.1 "bunker_buster").
# Rule sentence (spec, verbatim): "explosions delete props within the blast for the
# rest of the level".
# Counter-play: "fight in the open on purpose, save cover".
#
# Reading (recorded in DECISIONS.md): a nuke blast is observable on the launcher row
# (the blast tick enters the 300-tick pause with row["explosion_left"] == 24 and the
# detonation point in row["det"] = {"x", "y", "z"}). Props live in the collision
# world as live state (world["prop_cols"], key "x,z" -> entries [{"y", "h"}]); the
# barrier scan keeps sim/ content-id-free, so this content script does the deleting
# itself: each prop column entry within the blast's radius of the detonation point
# is removed from the world for the rest of the level. Tiles are never touched.

const CURSE_ID := "buster"

const NUKE_ID := "nuke"           # the enemy the curse attaches to (content names content)
const BLAST_RADIUS_FALLBACK := 5.0  # u, the enemy.json blast_radius (nuke's sphere)
const ST_KEY := "buster_done"     # per-level scratch: keys "nuke row index/blast no"


## Stacks the run holds; >= 1 while the curse is picked (max_stacks 1).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## on_tick: on each nuke blast tick, delete the props inside the blast sphere.
static func on_tick(state: Dictionary, api) -> void:
	if held_stacks(state) <= 0:
		return
	var rt = state.get("enemy_runtime")
	if rt == null:
		return
	var st: Dictionary = state.get("curse_st", {})
	for i in range(rt.enemies.size()):
		var row = rt.enemies[i]
		if str(row.get("id", "")) != NUKE_ID:
			continue
		if int(row.get("explosion_left", 0)) != 24:
			continue   # not a blast tick (attack_explosion draws over the first 24)
		var det: Variant = row.get("det", null)
		if not (det is Dictionary):
			continue
		var r := float(row.get("cfg", {}).get("blast_radius", BLAST_RADIUS_FALLBACK))
		var w: Dictionary = rt.world
		_blast_props(w, Vector3(float(det["x"]), float(det["y"]), float(det["z"])), r, api)
		st[ST_KEY] = int(st.get(ST_KEY, 0)) + 1


## Pure helper (test target): returns the "x,z" keys of the prop entries inside the
## sphere, WITHOUT deleting; the caller removes them from world["prop_cols"].
static func props_within(prop_cols: Dictionary, det: Vector3, r: float) -> Array:
	var out: Array = []
	for key in prop_cols.keys():
		var parts := str(key).split(",")
		if parts.size() != 2:
			continue   # prop_cols keys are "x,z" (collision.gd make_world)
		var px := float(parts[0]) + 0.5    # column -> tile-centre convention
		var pz := float(parts[1]) + 0.5
		var col: Array = prop_cols[key]
		for e in col:
			var ey := float(e.get("y", 0)) * 0.5   # entry y is in height units like tiles
			var dx := px - det.x
			var dz := pz - det.z
			var dy := ey - det.y
			if dx * dx + dz * dz + dy * dy <= r * r:
				out.append(key)
				break
	return out


## The world change itself: remove the sphere's prop entries from the T-012 collision
## world. "For the rest of the level": prop_cols is the level's live prop state, so
## deleting here lasts exactly that long.
static func _blast_props(w: Dictionary, det: Vector3, r: float, _api) -> void:
	if not w.has("prop_cols"):
		return
	var doomed := props_within(w["prop_cols"], det, r)
	for key in doomed:
		w["prop_cols"].erase(key)
