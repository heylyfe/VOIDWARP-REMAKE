extends RefCounted
#
# sim/clawds.gd - the clawd swarm and the anger timer (cycle 7, track T4; D-T4-2..D-T4-6).
#
# The owner's design (CYCLE7_BRIEF.md T4, verbatim): "On level start he spawns mini CLAWDS across the map:
# minimum 5, scaling with level size up to 15 on very big maps (count formula in data, placed by the terrain
# generator seed, on walkable tiles, never on mines/beacon/hub/pads, spread out; NOT gifts: they never count in
# gift totals/straggler/beacon logic)." "Collecting a clawd (pickup radius like gifts, data) CALMS Claude: it
# resets his anger timer to 0." "If no clawd is collected for 60 s, Claude releases a warning sound (a new synth
# cue). At 120 s a second, louder one. At 180 s he INSTA-KILLS the player, death screen cause \"Claude\"."
# "The timer runs in sim ticks, deterministic, in the state hash. It pauses when the beacon opens (gold phase)
# and resets per level."
#
# SHAPE. The same shape as sim/jump_pads.gd, because the problem is the same one:
#   place_clawds(L, cfg) -> Array of [x, z, y]   (tile coords, y in HU = the tile top)
#   attach(L, cfg)       -> stores {"cfg": ..., "spots": ...} as L["clawds"]
#   create(level)        -> the runtime object LevelState.build keeps as lv.clawds (null when absent)
#   tick(lv, ctls, w, tick, events) -> one sim tick, after the player rows are synced
# Placement is a pure function of the Level dict plus the cfg, so the level hash still determines the swarm and
# voidgen.to_text() - which never reads "clawds" - stays byte-identical with or without it (terrain parity).
#
# NO CONTENT ID LIVES HERE. The killer id, the death code, the cue names and every number arrive in cfg from the
# roster module that wants the swarm (content/enemies/<id>/enemy.gd's clawd_cfg()); app/world.gd and
# tools/bot_run.gd probe the voted modules for that method by name, the idiom extra_mines() already uses. The
# boundary scan (tests/test_boundaries.gd) therefore stays clean, and a second enemy could own a swarm by
# declaring the same method.
#
# CLAWDS ARE NOT GIFTS. Nothing here touches sim/gifts.gd, the straggler rule, the beacon quota or the gold
# phase: the clawd set is its own bitset over its own spots, and a clawd is never counted in a gift total.
#
# Pure sim: no engine types beyond Array/Dictionary/Vector3/PackedByteArray, no RNG instance at runtime (the
# placement shuffle draws from the terrain Mulberry32 stream, seeded from the Level), fixed 60 Hz ticks.

const VoidRngScript := preload("res://terrain/void_rng.gd")
const VoidGenScript := preload("res://terrain/voidgen.gd")
const EventsScript := preload("res://sim/events.gd")

## The placement stream's tag: mixed onto the generator's own per-attempt base exactly as its ST_* streams are,
## with a value no ST_* constant uses ("CLAW").
const ST_CLAWDS := 0x434C4157
## voidgen.CLEAR: two layers are distinct at >= 12 HU (the same reading terrain/jump_pads.gd uses).
const CLEAR := 12
const N4 := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
## The spacing ladder (D-T4-4): the configured spacing first, then 4, then 2, then "any candidate left", so a
## small map still reaches its floor of 5 instead of silently shipping 3.
const SPACING_LADDER := [4, 2, 0]
## The clawd's world height above its tile top: the same 1.0 u the gift mapping uses (TERRAIN_SPEC 6.7), so the
## "pickup radius like gifts" reading is a like-for-like comparison of two centres.
const HOVER_U := 1.0

## Mirrors the roster module's data; the cfg wins for every key it carries (D-T4-3).
const DEFAULTS := {
	"count_min": 5,
	"count_max": 15,
	"count_by_tiles": [
		{"tiles": 0, "count": 5}, {"tiles": 800, "count": 7},
		{"tiles": 1100, "count": 10}, {"tiles": 1400, "count": 12},
		{"tiles": 1700, "count": 15},
	],
	"min_spacing_tiles": 8,
	"pickup_radius": 1.6,
	"warning_ticks": [3600, 7200],
	"kill_ticks": 10800,
	"pause_when_beacon_open": true,
	"killer_id": "",
	"death_code": "",
	"cues": [],
}

## The clawd spots, [x, z, y] per clawd in placement (id) order - read-only shared data.
var spots: Array = []
## Collected clawds by spot id: a bitset like the gift bitsets; joins the state hash (D-T4-6).
var taken := PackedByteArray()
## The anger timer, in sim ticks since the last pickup (or level start). 0 = calm.
var anger_ticks: int = 0
## How many warnings have fired (0, 1 or 2). Part of the hash: a run that heard a warning is not a run that did
## not, even at the same anger_ticks.
var warned: int = 0
## True once the kill has fired, so it fires exactly once and the timer stops.
var killed: bool = false
## The data knobs, pinned in the hash (D-T4-6).
var warning_ticks: Array = []
var kill_ticks: int = 10800
var pickup_radius: float = 1.6
var pause_when_beacon_open: bool = true
var killer_id: String = ""
var death_code: String = ""
var cues: Array = []
## The curse hooks (D-T4-7): the anger rate multiplier and the leftover a pickup leaves behind. Both default to
## the canon body (1.0 / 0), so an un-cursed run is byte-identical to the plain design.
var anger_rate_mul: float = 1.0
var calm_leftover_ticks: int = 0
## Fractional carry for anger_rate_mul, so a 1.5x rate is exactly 3 ticks per 2 ticks and never drifts.
var _anger_carry: float = 0.0


# ---- the config ------------------------------------------------------------------------------

## The cfg with every missing key filled from DEFAULTS. The roster module's data wins for every key it carries,
## so the numbers live in content/enemies/<id>/enemy.json and this file only mirrors them (D-T4-3).
static func resolve_cfg(cfg: Dictionary) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	for k in DEFAULTS.keys():
		if cfg.has(k):
			out[k] = cfg[k]
	return out


## Clawds wanted on a level with `tiles` tiles: the count_by_tiles row with the largest tiles <= the count,
## clamped to [count_min, count_max] (D-T4-3).
static func count_for_tiles(cfg: Dictionary, tiles: int) -> int:
	var c := resolve_cfg(cfg)
	var best_from := -1
	var n := int(c["count_min"])
	for row in c.get("count_by_tiles", []):
		var fr := int((row as Dictionary).get("tiles", 0))
		if fr <= tiles and fr > best_from:
			best_from = fr
			n = int((row as Dictionary).get("count", n))
	return clampi(n, int(c["count_min"]), int(c["count_max"]))


## The placement stream's seed: the generator's per-attempt base, mixed with ST_CLAWDS (the jump pads' idiom).
static func stream_seed(L: Dictionary) -> int:
	var M := VoidRngScript.M32
	var base: int = VoidRngScript.mix(VoidRngScript.mix(VoidRngScript.mix(
			int(L["seed"]) & M, int(L["level"])), int(L["gen_version"])), int(L["attempt"]))
	return VoidRngScript.mix(base, ST_CLAWDS)


# ---- geometry helpers over the packed Level dict ---------------------------------------------

static func _index(L: Dictionary) -> Dictionary:
	var col: Dictionary = {}
	var tiles: Array = L["tiles"]
	for i in tiles.size():
		var t: Array = tiles[i]
		var key := Vector2i(int(t[0]), int(t[1]))
		if not col.has(key):
			col[key] = []
		(col[key] as Array).append(i)
	var pcol: Dictionary = {}
	for p in L.get("props", []):
		var key2 := Vector2i(int(p[0]), int(p[1]))
		if not pcol.has(key2):
			pcol[key2] = []
		(pcol[key2] as Array).append(p)
	return {"col": col, "pcol": pcol}


static func _has_prop(ix: Dictionary, x: int, z: int, y: int) -> bool:
	for p in ix["pcol"].get(Vector2i(x, z), []):
		if int(p[2]) == y:
			return true
	return false


## Every cell a clawd must keep clear of, with its 8 XZ neighbours (D-T4-4): gift slots (which are also the
## tripmine slots - the mine set IS the occ == 1 gift slots), the beacon, launch pads and their landings, jump
## pads, and the player spawns.
static func _banned(L: Dictionary) -> Dictionary:
	var banned: Dictionary = {}
	var ban := func(x: int, z: int) -> void:
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				banned[Vector2i(x + dx, z + dz)] = true
	for g in L.get("gifts", []):
		ban.call(int(g["x"]), int(g["z"]))
	for p in L.get("pads", []):
		ban.call(int(p[0]), int(p[1]))
		ban.call(int(p[3]), int(p[4]))
	for jp in L.get("jump_pads", []):
		ban.call(int(jp[0]), int(jp[1]))
	for s in L.get("spawns", []):
		ban.call(int(s[0]), int(s[1]))
	var bx: Array = L.get("beacon", [0, 0, 1])
	ban.call(int(bx[0]), int(bx[1]))
	return banned


## Every tile index a clawd may legally sit on, ascending (before count / spacing). A candidate is a floor or
## walkway tile (kind 0 / 1), not a ramp tile, not on the hub piece, with no prop on it, and clear of every
## banned cell (D-T4-4).
static func candidates(L: Dictionary) -> Array:
	var ix := _index(L)
	var tiles: Array = L["tiles"]
	var pieces: Array = L.get("pieces", [])
	var banned := _banned(L)
	var out: Array = []
	for i in tiles.size():
		var t: Array = tiles[i]
		var x := int(t[0])
		var z := int(t[1])
		var y := int(t[2])
		if int(t[3]) != 0:
			continue                                     # a ramp tile
		var pid := int(t[4])
		if pid < pieces.size() and int((pieces[pid] as Dictionary)["role"]) == VoidGenScript.ROLE_HUB:
			continue                                     # the hub: the beacon dais lives there
		if banned.has(Vector2i(x, z)) or _has_prop(ix, x, z, y):
			continue
		out.append(i)
	return out


## THE placement function (D-T4-4). Returns Array of [x, z, y] in placement order (deterministic).
static func place_clawds(L: Dictionary, cfg: Dictionary) -> Array:
	if L.is_empty():
		return []
	var c := resolve_cfg(cfg)
	var want := count_for_tiles(c, (L.get("tiles", []) as Array).size())
	if want <= 0:
		return []
	var cand := candidates(L)
	if cand.is_empty():
		return []
	var rng = VoidRngScript.new(stream_seed(L))
	rng.shuffle(cand)
	var tiles: Array = L["tiles"]
	var out: Array = []
	# The spacing ladder: the configured spacing, then 4, then 2, then any candidate left. Each rung only adds
	# spots the previous rung refused, so the result is a prefix-stable superset and stays deterministic.
	var rungs: Array = [int(c["min_spacing_tiles"])]
	rungs.append_array(SPACING_LADDER)
	for spacing in rungs:
		if out.size() >= want:
			break
		var sp2 := float(spacing) * float(spacing)
		for i in cand:
			if out.size() >= want:
				break
			var t: Array = tiles[i]
			var ok := true
			for p in out:
				var dx := float(int(t[0]) - int(p[0]))
				var dz := float(int(t[1]) - int(p[1]))
				if dx * dx + dz * dz < sp2:
					ok = false
					break
			if ok:
				out.append([int(t[0]), int(t[1]), int(t[2])])
	return out


## Places the swarm and stores it on the Level dict as L["clawds"]. Returns the spots.
static func attach(L: Dictionary, cfg: Dictionary) -> Array:
	var c := resolve_cfg(cfg)
	var spots_out: Array = place_clawds(L, c) if not L.is_empty() else []
	L["clawds"] = {"cfg": c, "spots": spots_out}
	return spots_out


## The runtime object LevelState.build keeps as lv.clawds; null when the Level carries no swarm, so a level
## without one keeps every pre-existing state dump byte-identical (D-T4-6).
static func create(level: Dictionary) -> RefCounted:
	var data: Variant = level.get("clawds", null)
	if not (data is Dictionary):
		return null
	var spots_in: Array = (data as Dictionary).get("spots", [])
	if spots_in.is_empty():
		return null
	var c := resolve_cfg((data as Dictionary).get("cfg", {}))
	var cl := new()
	for p in spots_in:
		cl.spots.append([int(p[0]), int(p[1]), int(p[2])])
	cl.taken.resize((cl.spots.size() + 7) >> 3)
	cl.warning_ticks = []
	for t in c.get("warning_ticks", []):
		cl.warning_ticks.append(int(t))
	cl.kill_ticks = maxi(1, int(c["kill_ticks"]))
	cl.pickup_radius = maxf(0.0, float(c["pickup_radius"]))
	cl.pause_when_beacon_open = bool(c["pause_when_beacon_open"])
	cl.killer_id = str(c["killer_id"])
	cl.death_code = str(c["death_code"])
	cl.cues = (c.get("cues", []) as Array).duplicate()
	return cl


# ---- the runtime -----------------------------------------------------------------------------

func count() -> int:
	return spots.size()


func is_taken(i: int) -> bool:
	return i >= 0 and i < spots.size() and (taken[i >> 3] & (1 << (i & 7))) != 0


func remaining() -> int:
	var n := 0
	for i in spots.size():
		if not is_taken(i):
			n += 1
	return n


## World position of clawd i: the tile centre, HOVER_U above the tile top - the same mapping the gift slots use
## (TERRAIN_SPEC 6.7), so "pickup radius like gifts" compares two centres of the same kind.
func spot_pos(i: int) -> Vector3:
	var p: Array = spots[i]
	return Vector3(float(int(p[0])) + 0.5, float(int(p[2])) * 0.5 + HOVER_U, float(int(p[1])) + 0.5)


## The collision tile key of clawd i's tile (collision.gd's own format), so a caller can ask whether the
## platform collapse took it.
func tile_key(i: int) -> String:
	var p: Array = spots[i]
	return "%d,%d,%d" % [int(p[0]), int(p[1]), int(p[2])]


## The platform collapse took these tile keys: a clawd on one falls with it, for good. Returns the ids dropped.
func sweep(fallen_keys: Array) -> Array:
	var out: Array = []
	if fallen_keys.is_empty():
		return out
	var gone := {}
	for k in fallen_keys:
		gone[str(k)] = true
	for i in spots.size():
		if not is_taken(i) and gone.has(tile_key(i)):
			taken[i >> 3] |= 1 << (i & 7)
			out.append(i)
	return out


## True while the anger timer is frozen: the beacon is open (the gold phase begins on exactly that tick,
## app/world.gd's _gold_began) and the data says to pause there (D-T4-5).
func paused(lv) -> bool:
	if not pause_when_beacon_open:
		return false
	var b = lv.get("beacon") if lv != null else null
	return b != null and bool(b.is_open())


## One sim tick (D-T4-5). ctls[i] is player i's controller (null rows are skipped); w is the collision world
## (the kill ladder reads w["dais"]). Order inside the tick: pickups first, then the timer - so a clawd collected
## on the tick a warning was due cancels the warning, which is what "collecting a clawd CALMS Claude" means.
static func tick(lv, ctls: Array, w: Dictionary, tick: int, events: Array) -> void:
	var cl: RefCounted = lv.get("clawds") if lv != null else null
	if cl == null:
		return
	var picked := false
	for i in ctls.size():
		var ctl = ctls[i]
		if ctl == null or bool(ctl.dead):
			continue
		if cl.pickup(ctl, i, tick, events):
			picked = true
	if picked:
		return                      # the pickup already reset the timer this tick
	cl.advance(lv, ctls, w, tick, events)


## The pickup pass for one player: every live clawd whose centre is inside the pickup radius of the player's
## centre (feet + 0.9 u, the gift pickup's own test point, D-T020-2). Returns true when anything was collected.
func pickup(ctl, player_index: int, tick: int, events: Array) -> bool:
	if spots.is_empty() or bool(ctl.dead):
		return false
	var px := float(ctl.x)
	var py := float(ctl.y) + 0.9
	var pz := float(ctl.z)
	var r2 := pickup_radius * pickup_radius
	var got := false
	for i in spots.size():
		if is_taken(i):
			continue
		var pos := spot_pos(i)
		var dx := px - pos.x
		var dy := py - pos.y
		var dz := pz - pos.z
		if dx * dx + dy * dy + dz * dz > r2:
			continue
		taken[i >> 3] |= 1 << (i & 7)
		got = true
		# D-T4-7: a curse can leave anger behind instead of calming completely.
		anger_ticks = maxi(0, calm_leftover_ticks)
		_anger_carry = 0.0
		var ev := EventsScript.make(EventsScript.EV_CLAWD_COLLECTED, tick, player_index)
		ev["clawd"] = i
		ev["remaining"] = remaining()
		ev["anger_ticks"] = anger_ticks
		events.append(ev)
	return got


## One tick of the anger timer: advance (unless paused or already spent), then fire the warnings and the kill at
## their exact tick counts (D-T4-5).
func advance(lv, ctls: Array, w: Dictionary, tick: int, events: Array) -> void:
	if killed or paused(lv):
		return
	# The rate multiplier is a curse hook (D-T4-7); the carry keeps a 1.5x rate exact (3 ticks per 2 ticks).
	_anger_carry += anger_rate_mul
	var step := int(floor(_anger_carry))
	_anger_carry -= float(step)
	anger_ticks += maxi(step, 0)
	while warned < warning_ticks.size() and anger_ticks >= int(warning_ticks[warned]):
		warned += 1
		var ev := EventsScript.make(EventsScript.EV_CLAWD_WARNING, tick, -1)
		ev["level"] = warned
		ev["anger_ticks"] = anger_ticks
		ev["cue"] = str(cues[warned - 1]) if warned - 1 < cues.size() else ""
		events.append(ev)
	if anger_ticks >= kill_ticks:
		killed = true
		anger_ticks = kill_ticks
		_kill(ctls, w, tick, events)


## The 180 s kill: every live player runs the controller's own kill ladder (D-T4-5), so Last Light and respawn
## invulnerability answer exactly as they do for a body contact. The event carries the cause for the view.
func _kill(ctls: Array, w: Dictionary, tick: int, events: Array) -> void:
	for i in ctls.size():
		var ctl = ctls[i]
		if ctl == null or bool(ctl.dead):
			continue
		var ev: Array = []
		ctl.try_kill(death_code, killer_id, w, ev)
		for e in ev:
			if e is Dictionary and not e.has("player"):
				e["player"] = i
			events.append(e)
	var ev2 := EventsScript.make(EventsScript.EV_CLAWD_KILL, tick, -1)
	ev2["killer"] = killer_id
	ev2["code"] = death_code
	events.append(ev2)


# ---- the state hash helpers (D-T4-6) ---------------------------------------------------------

## The ordered clawd coordinates, "x:z:y" per clawd in placement (id) order, comma joined. The set is a function
## of the Level AND of the roster module's data (count, spacing), which the level hash does not cover.
func spots_csv() -> String:
	var parts := PackedStringArray()
	for p in spots:
		parts.append("%d:%d:%d" % [int(p[0]), int(p[1]), int(p[2])])
	return ",".join(parts)


## The warning tick counts joined for the hash line ("" for none).
func warnings_csv() -> String:
	var parts := PackedStringArray()
	for t in warning_ticks:
		parts.append(str(int(t)))
	return ",".join(parts)
