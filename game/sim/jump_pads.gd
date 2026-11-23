extends RefCounted
#
# sim/jump_pads.gd - the JUMP PAD runtime (D-JUMPPAD-2..4; DESIGN.md section 3.4).
#
# NOT the launch pads (controller._try_launch_pad, level "pads"). The pad SET is level data -
# terrain/jump_pads.gd places it as Level["jump_pads"] = [[x, z, y], ...], a pure function of
# the Level dict AND data/jump_pads.json - the config is outside the level hash, so the ordered
# pad coordinates ARE dumped (pads_csv, Terra review finding 2). Also on the JUMPPADS line:
#   ready_tick[i]  the first level tick at which pad i may fire again (0 = armed from the start)
#   lost           bitset: pad i's tile fell in the platform collapse (it falls with the tile)
#   rearm_ticks / launch_speed - data (data/jump_pads.json), pinned so two runs whose data
#                  differ cannot hash the same.
#
# tick(lv, ctls, w, tick, events) runs once per sim tick AFTER the controllers stepped (the
# same slot MinesScript.tick runs in). A pad fires for a player who is grounded with feet on
# the pad tile's top and centre inside its cell, while the pad is armed (tick >= ready_tick),
# not lost and its tile is in collision (not in w["removed"]). Firing calls the controller's
# jump_pad_launch() - the one place the movement refill lives - and sets
# ready_tick = tick + rearm_ticks, so a player standing on it cannot chain-fire. Integer ticks
# only: no float timer, no RNG.

const CollisionScript := preload("res://sim/collision.gd")
const JumpPadPlaceScript := preload("res://terrain/jump_pads.gd")

const TICK_HZ := 60.0
const FEET_EPS := 0.01

var pads: Array = []                       # [x, z, y] per pad (Level["jump_pads"])
var ready_tick := PackedInt32Array()
var lost := PackedByteArray()
var rearm_ticks: int = 30
var launch_speed: float = 20.0
var _at: Dictionary = {}                   # "x,z" -> Array[int] pad ids (lookup only)


## null when the Level carries no jump pads (the key is absent or empty), so a level without
## any keeps every pre-existing state dump byte-identical.
static func create(level: Dictionary, cfg: Dictionary = {}) -> RefCounted:
	var lst: Array = level.get("jump_pads", [])
	if lst.is_empty():
		return null
	var c: Dictionary = cfg if not cfg.is_empty() else JumpPadPlaceScript.load_config()
	var jp := new()
	jp.rearm_ticks = maxi(1, int(round(float(c.get("rearm_s", 0.5)) * TICK_HZ)))
	jp.launch_speed = float(c.get("launch_speed", 20.0))
	for p in lst:
		var id: int = jp.pads.size()
		jp.pads.append([int(p[0]), int(p[1]), int(p[2])])
		var key := "%d,%d" % [int(p[0]), int(p[1])]
		if not jp._at.has(key):
			jp._at[key] = []
		(jp._at[key] as Array).append(id)
	jp.ready_tick.resize(jp.pads.size())
	jp.ready_tick.fill(0)
	jp.lost.resize((jp.pads.size() + 7) >> 3)
	return jp


func count() -> int:
	return pads.size()


func is_lost(i: int) -> bool:
	return (lost[i >> 3] & (1 << (i & 7))) != 0


func is_armed(i: int, tick: int) -> bool:
	return not is_lost(i) and tick >= ready_tick[i]


## The collision tile key of pad i's tile (collision.gd's own format).
func tile_key(i: int) -> String:
	var p: Array = pads[i]
	return CollisionScript.tile_key(int(p[0]), int(p[1]), int(p[2]))


## The pad under a body at (px, py feet, pz), or -1. Height must match the tile top.
func pad_at(px: float, py: float, pz: float) -> int:
	var key := "%d,%d" % [int(floor(px)), int(floor(pz))]
	for i in _at.get(key, []):
		if absf(py - float(int(pads[i][2])) * 0.5) <= FEET_EPS:
			return int(i)
	return -1


## The platform collapse took these tile keys ("x,z,y"): a pad on one falls with it, for good.
## Returns the pad ids this call dropped.
func sweep(fallen_keys: Array) -> Array:
	var out: Array = []
	if fallen_keys.is_empty():
		return out
	var gone := {}
	for k in fallen_keys:
		gone[str(k)] = true
	for i in pads.size():
		if not is_lost(i) and gone.has(tile_key(i)):
			lost[i >> 3] |= 1 << (i & 7)
			out.append(i)
	return out


## One sim tick. ctls[i] is player i's controller (null rows are skipped).
static func tick(lv, ctls: Array, w: Dictionary, tick: int, events: Array) -> void:
	var jp: RefCounted = lv.jump_pads
	if jp == null:
		return
	for i in ctls.size():
		var ctl = ctls[i]
		if ctl == null or bool(ctl.dead) or float(ctl.respawn_t) >= 0.0 or not bool(ctl.grounded):
			continue
		var pid: int = jp.pad_at(float(ctl.x), float(ctl.y), float(ctl.z))
		if pid < 0 or not jp.is_armed(pid, tick):
			continue
		var p: Array = jp.pads[pid]
		if not CollisionScript.tile_alive(w, int(p[0]), int(p[1]), int(p[2])):
			continue
		jp.ready_tick[pid] = tick + jp.rearm_ticks
		var ev: Array = []
		ctl.jump_pad_launch(jp.launch_speed, ev)
		_sync_row(lv, i, ctl)
		for e in ev:
			e["pad"] = pid
			e["player"] = i
			e["x"] = float(int(p[0])) + 0.5
			e["y"] = float(int(p[2])) * 0.5
			e["z"] = float(int(p[1])) + 0.5
			events.append(e)


## Terra review finding 1: the callers (app/world.gd step, tools/bot_run.gd _play_level) copy
## the controller into lv.players[i] BEFORE this tick runs (gifts and mines read that row), so
## a launch would leave the hashed row grounded with its pre-launch velocity until the next
## tick. The pad is what changed the controller, so the pad writes the row back: every path
## that fires a pad gets it, and no caller has to remember. Only the fields jump_pad_launch()
## changes and the row carries (position is untouched by the fling). A holder without player
## rows (the unit tests' bare Holder) is skipped.
static func _sync_row(lv, i: int, ctl) -> void:
	if not ("players" in lv):
		return
	var rows: Array = lv.players
	if i >= rows.size():
		return
	var row: Dictionary = rows[i]
	row["vx"] = ctl.vx
	row["vy"] = ctl.vy
	row["vz"] = ctl.vz
	row["grounded"] = ctl.grounded


## Terra review finding 2: the ordered pad coordinates for state_hash.gd's JUMPPADS line,
## "x:z:y" per pad in placement (id) order, comma joined. The pad set is a function of the
## Level AND of data/jump_pads.json (count, spacing, ...), and that config is not in the
## level hash - so two runs on one level hash with different pad positions must not hash
## alike. Placement order is the pad id order the ready ticks and the lost bitset index.
func pads_csv() -> String:
	var parts := PackedStringArray()
	for p in pads:
		parts.append("%d:%d:%d" % [int(p[0]), int(p[1]), int(p[2])])
	return ",".join(parts)


## The ready ticks joined for state_hash.gd's JUMPPADS line ("" for none).
func ready_csv() -> String:
	var parts := PackedStringArray()
	for t in ready_tick:
		parts.append(str(t))
	return ",".join(parts)
