extends RefCounted
#
# spreading_rot.gd - script curse (DESIGN.md section 7.1 row "spreading_rot").
# Rule sentence (spec, verbatim): "each glitched tile infects one adjacent tile after
# 6 s (max 2 generations)".
# Counter-play: "leave early, use ben's ring".
#
# Reading: the glitched map is the toucher's own live state surface (world["glitched"],
# keys collision.gd's tile_key "x,z,y_hu" - the ONE spelling the controller, ben's
# cleanse and the toucher share, D-T037-5). The curse watches that map: a tile it has
# not seen before is generation 0 (the toucher's own infection); 360 ticks (6.0 s)
# later it infects ONE adjacent tile - the first of +x, -x, +z, -z that exists in the
# level and is not already glitched - and that tile is generation 1. A generation-1
# tile spreads once more (generation 2); a generation-2 tile never spreads, so the
# patch grows at most two rings out from the finger's own tiles.
#
# The curse's own grown tiles are aged here at the toucher's own 12 s tile life
# (TILE_LIFE_TICKS, 5.8): the toucher only ages the tiles in its own row list, so a
# tile this curse added would otherwise be permanent. Ben's ring cleanse erases keys
# straight out of world["glitched"] and the curse drops them on the next tick.

const CURSE_ID := "spreading_rot"

const SPREAD_DELAY_TICKS := 360   # 6.0 s (the rule sentence)
const MAX_GENERATIONS := 2        # the rule sentence's "max 2 generations"
const TILE_LIFE_TICKS := 720      # the toucher's own 12 s tile life (5.8)
const NEIGHBOURS := [[1, 0], [-1, 0], [0, 1], [0, -1]]   # +x, -x, +z, -z (deterministic)

## Per-level scratch:
##   "sr_born" {key: tick first seen}   "sr_gen" {key: generation}
##   "sr_done" {key: true}              "sr_own" {key: tick it expires}
const ST_BORN := "sr_born"
const ST_GEN := "sr_gen"
const ST_DONE := "sr_done"
const ST_OWN := "sr_own"


## Stacks the run holds; >= 1 while the curse is picked (max_stacks 1).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## The spread delay in ticks (the rule sentence's 6 s). Pure helper.
static func spread_delay_ticks() -> int:
	return SPREAD_DELAY_TICKS


## The generation cap (the rule sentence's "max 2 generations"). Pure helper.
static func max_generations() -> int:
	return MAX_GENERATIONS


## The level's own tile keys ("x,z,y_hu"), the set an adjacent tile must belong to.
## Pure helper - the test target.
static func tile_keys(level: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for t in level.get("tiles", []):
		if (t as Array).size() < 3:
			continue
		var k := "%d,%d,%d" % [int(t[0]), int(t[1]), int(t[2])]
		out[k] = true
	return out


## The one adjacent tile `key` infects: the first of +x, -x, +z, -z that exists in the
## level and is not already glitched; "" when none qualifies. Pure helper - the test
## target.
static func pick_adjacent(key: String, tiles: Dictionary, glitched: Dictionary) -> String:
	var parts: PackedStringArray = key.split(",")
	if parts.size() < 3:
		return ""
	var x := int(parts[0])
	var z := int(parts[1])
	var y := int(parts[2])
	for d in NEIGHBOURS:
		var k := "%d,%d,%d" % [x + int(d[0]), z + int(d[1]), y]
		if not tiles.has(k):
			continue
		if glitched.has(k):
			continue
		return k
	return ""


## on_tick: age the curse's own tiles, then spread every due source by one tile.
static func on_tick(state: Dictionary, api) -> void:
	if held_stacks(state) <= 0:
		return
	var rt = state.get("enemy_runtime")
	if rt == null:
		return
	var world: Dictionary = rt.world
	if world.is_empty():
		return
	var gl: Dictionary = world.get("glitched", {})
	var st: Dictionary = state.get("curse_st", {})
	var born: Dictionary = st.get(ST_BORN, {})
	var gen: Dictionary = st.get(ST_GEN, {})
	var done: Dictionary = st.get(ST_DONE, {})
	var own: Dictionary = st.get(ST_OWN, {})
	var tick := int(state.get("tick", 0))
	var tiles: Dictionary = tile_keys(rt.level)
	# 1. age the curse's own grown tiles (the toucher only ages its own row list)
	for key in own.keys():
		if not gl.has(key):
			own.erase(key)   # cleansed by ben's ring (or a future hand)
			continue
		if tick >= int(own[key]):
			gl.erase(key)
			own.erase(key)
	# 2. first sight = generation 0 (the toucher's own infection)
	for key in gl.keys():
		if born.has(key):
			continue
		born[key] = tick
		gen[key] = 0
	# 3. spread: one adjacent tile per source, 6 s after the source appeared
	for key in gl.keys():
		if int(gen.get(key, 0)) >= MAX_GENERATIONS:
			continue   # generation 2 never spreads (the rule sentence's cap)
		if done.has(key):
			continue
		if tick < int(born.get(key, tick)) + SPREAD_DELAY_TICKS:
			continue
		done[key] = true
		var target := pick_adjacent(str(key), tiles, gl)
		if target == "":
			continue   # nowhere to grow: the source is spent, never retried
		gl[target] = true
		born[target] = tick
		gen[target] = int(gen.get(key, 0)) + 1
		own[target] = tick + TILE_LIFE_TICKS
	st[ST_BORN] = born
	st[ST_GEN] = gen
	st[ST_DONE] = done
	st[ST_OWN] = own
