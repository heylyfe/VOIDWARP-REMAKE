extends RefCounted
#
# micro_levels.gd - ticket T-075, piece 2 of 3: the five answer-lab micro-levels,
# hand-written as tile lists, plus the builder that turns each into a Level dict in
# the SAME schema terrain/voidgen.gd's generate() returns, so sim/level_state.gd's
# build() accepts it unchanged. Additive fixture only: voidgen, level_state.gd and
# the sim are NOT touched.
#
# The five (research/fable-enemies.md section 6, ticket T-075):
#   flat_lane    a 1-wide flat lane, 24 u long          (open-ground answers, runaways)
#   stepped_lane a 2-wide stepped lane, height step     ("step behind a 2 HU rise")
#                partway, so the hide answers have something real to hide behind
#   nook         a dead-end nook on a 1-wide walkway    (the F1/F2 corner cases)
#   pad          a 7x7 pad                              (isolation cases, pinning absent)
#   hub          the hub                                (spawn-crowding, the co-arrival cases)
#
# Level schema notes (per field):
#   gen_version 0 - a hand-written fixture is NOT a voidgen product; the same neutral
#                 reading test_gifts.gd / test_curses_scripted_general.gd use.
#   seed / level / players / extra_mines / attempt - neutral values; LevelState.build
#                 reads none of them (the answer lab passes its own seeds to the bots).
#   beacon       the spawn tile - controller.place() spawns the player there
#                 (collision.gd make_world "dais"), like the real hub spawns on its dais.
#   spawns       one row per level: [x, z, y].
#   gifts / mines none - the answer lab spawns ENEMIES, not gifts. Zero slots means
#                 zero mines and a beacon quota of nothing (opens immediately), which
#                 is what the lab wants: the level is a stage, not a puzzle.
#   arms [] / edges [] / pads [] - arms are the procedural trait names, edges the
#                 EDGE_TREE/EDGE_LOOP/EDGE_DROP links between generated pieces and
#                 pads the EDGE_PAD endpoints; a hand-written micro-level honestly
#                 carries none of them. Piece 3's lab pathfinds on tiles directly
#                 (the way bot_run.gd's _build_graph does).
#   props        only the hub carries any - the four plaza pillars, copied from
#                 voidgen.gd build_hub (kind PROP_PILLAR = 3, h = 10).
#
# Tile row format: [x, z, y, kind, pid] - exactly voidgen's World.add_tile row.
# kind 0 (flat top) everywhere; y is in half-units (1 y = 1 HU = 0.5 u, so a
# 2 HU rise is a y-step of 2), read by LevelState._build_columns as y * 0.5.

# widths/lengths the ticket states, exposed so tests and the lab quote the constants
# instead of retyping magic numbers:
const FLAT_LANE_LEN := 24      # u
const STEPPED_LANE_LEN := 24   # u
const STEPPED_RISE_HU := 2     # the "2 HU rise" the hide answers cite
const PAD_SIZE := 7            # 7x7

const ROLES_HUB := 0           # terrain/voidgen.gd's ROLE_HUB / ROLE_LINK
const ROLES_LINK := 3
const PROP_KIND_PILLAR := 3    # voidgen's PROP_PILLAR
const PILLAR_H := 10           # copied from build_hub's props
const ANCHOR_OPEN := 1         # voidgen's AN_OPEN

const IDS := ["flat_lane", "nook", "pad", "hub", "stepped_lane"]


static func ids() -> Array:
	var out: Array = IDS.duplicate()
	out.sort()
	return out


## Build one micro-level by id as a Level dict (voidgen generate() schema).
## Unknown ids assert loudly - no silent default level.
static func build(id: String) -> Dictionary:
	assert(IDS.has(id), "micro_levels: unknown level id '%s'" % id)
	match id:
		"flat_lane":
			return _flat_lane()
		"stepped_lane":
			return _stepped_lane()
		"nook":
			return _nook()
		"pad":
			return _pad()
		"hub":
			return _hub()
	return {}  # unreachable in debug; keeps shippable builds honest


# ---------------------------------------------------------------- levels --

## A 1-wide flat lane, 24 u long. Spawns at the west end; the answers that need
## pure open ground (run away, allow a straight escape) run on this.
##
##	z=0  "########################"   x: 0..23
##
static func _flat_lane() -> Dictionary:
	var rows := ["########################"]
	var tiles := _parse(rows, 0, 0, 0, [])
	return _level(tiles, "flat_lane", ROLES_LINK, [0, 0, 0], [])


## A 2-wide stepped lane, 24 u long: 12 u at y=0, then twelve cells raised 2 HU
## (y step of 2 = 1.0 u - STEPPED_RISE_HU), so "step behind a 2 HU rise" hides
## behind a real rise and the seal/isagi step answers have their step.
##
##	z=1  "############^^^^^^^^^^^^"
##	z=0  "############^^^^^^^^^^^^"   x: 0..23, low half then high half
##
static func _stepped_lane() -> Dictionary:
	var rows := [
		"############^^^^^^^^^^^^",
		"############^^^^^^^^^^^^",
	]
	var tiles := _parse(rows, 0, 0, 0, [])
	return _level(tiles, "stepped_lane", ROLES_LINK, [0, 0, 0], [])


## A dead-end nook on a 1-wide walkway: 16 u of lane, with a 1-wide 3 u pocket
## opening off its south side at the mouth (x=12), dead end at (12,3) - the F1/F2
## corner: a floating chaser entering the pocket has one way out.
##
##	z=3  "            #  "        the dead end
##	z=2  "            #"
##	z=1  "            #"         pocket, 1 wide, mouth where it meets the walkway
##	z=0  "################"      the walkway, x: 0..15
##
static func _nook() -> Dictionary:
	var rows := [
		"################",
		"            #   ",
		"            #   ",
		"            #   ",
	]
	var tiles := _parse(rows, 0, 0, 0, [])
	return _level(tiles, "nook", ROLES_LINK, [0, 0, 0], [])


## A 7x7 pad. No geometry between player and enemy - the isolation case.
##
##	z=0..6  "#######"   x: 0..6
##
static func _pad() -> Dictionary:
	var rows := [
		"#######",
		"#######",
		"#######",
		"#######",
		"#######",
		"#######",
		"#######",
	]
	var tiles := _parse(rows, 0, 0, 0, [])
	return _level(tiles, "pad", ROLES_LINK, [3, 3, 0], [])


## The hub, hand-shaped to terrain/voidgen.gd build_hub (TERRAIN_SPEC section 6.1,
## 205 tiles, bbox 19x19): plaza [-6,6]^2 at y=0, the dais [-2,2]^2 one half-unit
## up (y=1), four 3-wide stubs out at cells 7..9 (mid-rows only), and the four
## plaza pillars.
##
##	z=-9..-7   ".........###......."    north stub
##	z=-6       "...P###########P..."    plaza row with the two north pillars (P)
##	z=-5..-3   "...#############..."    plaza only
##	z=-2       "...####DDDDD####..."    plaza, dais begins
##	z=-1..1    "#######DDDDD#######"    plaza + dais + both side stubs
##	z=2        "...####DDDDD####..."    dais ends
##	z=3..5     "...#############..."
##	z=6        "...P###########P..."    the two south pillars
##	z=7..9     ".........###......."    south stub
##
static func _hub() -> Dictionary:
	var rows := [
		".........###.......",
		".........###.......",
		".........###.......",
		"...P###########P...",
		"...#############...",
		"...#############...",
		"...#############...",
		"...####DDDDD####...",
		"#######DDDDD#######",
		"#######DDDDD#######",
		"#######DDDDD#######",
		"...####DDDDD####...",
		"...#############...",
		"...#############...",
		"...#############...",
		"...P###########P...",
		".........###.......",
		".........###.......",
		".........###.......",
	]
	var props: Array = []
	var tiles := _parse(rows, -9, -9, 0, props)
	return _level(tiles, "hub", ROLES_HUB, [0, 0, 1], props)


# --------------------------------------------------------------- helpers --

## Turn ASCII rows into tile rows + pillar props.
##   '#'  tile at base_y          '^'  tile at base_y + 2 (the 2 HU rise)
##   'D'  tile at base_y + 1      'P'  tile at base_y + a pillar prop on it
##   '.'  void (no tile)
static func _parse(rows: Array, x0: int, z0: int, base_y: int, props: Array) -> Array:
	var tiles: Array = []
	for j in rows.size():
		var row: String = rows[j]
		for i in row.length():
			var c := row[i]
			var x: int = x0 + i
			var z: int = z0 + j
			if c == "#":
				tiles.append([x, z, base_y, 0, 0])
			elif c == "^":
				tiles.append([x, z, base_y + 2, 0, 0])
			elif c == "D":
				tiles.append([x, z, base_y + 1, 0, 0])
			elif c == "P":
				tiles.append([x, z, base_y, 0, 0])
				props.append([x, z, base_y, PILLAR_H, PROP_KIND_PILLAR, 0])
	# '.' and ' ' are void
	return tiles


## The Level dict shell, filled with the empty/neutral values voidgen would
## produce for a one-piece world (see the module header for the per-field notes).
static func _level(tiles: Array, arch: String, role: int, beacon: Array, props: Array) -> Dictionary:
	var xmin: int = int(tiles[0][0])
	var xmax: int = xmin
	var zmin: int = int(tiles[0][1])
	var zmax: int = zmin
	for t in tiles:
		if int(t[0]) < xmin:
			xmin = int(t[0])
		if int(t[0]) > xmax:
			xmax = int(t[0])
		if int(t[1]) < zmin:
			zmin = int(t[1])
		if int(t[1]) > zmax:
			zmax = int(t[1])
	return {
		"gen_version": 0,
		"seed": 0, "level": 1, "players": 1, "extra_mines": 0, "attempt": 0,
		"beacon": beacon,
		"spawns": [[int(beacon[0]), int(beacon[1]), int(beacon[2])]],
		"arms": [],
		"pieces": [{"id": 0, "kind": 0, "arch": arch, "parent": -1, "depth": 0,
			"arm": -1, "role": role, "y": int(beacon[2]),
			"bbox": [xmin, zmin, xmax, zmax], "tiles": tiles.size(),
			"jumps": 0, "w": 0}],
		"tiles": tiles,
		"props": props,
		"edges": [],
		"gifts": [],
		"anchors": [[ANCHOR_OPEN, int(beacon[0]), int(beacon[1]), int(beacon[2]), 0]],
		"pads": [],
	}

