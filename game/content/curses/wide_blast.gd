extends RefCounted
#
# wide_blast.gd - script curse (DESIGN.md section 7.1 row "wide_blast").
# Rule sentence (spec, verbatim): "mine blast radius 3 → 4.5 u and the blast
# chain-detonates mines inside it".
# Counter-play: "never stand near a second mine".
#
# Reading: sim/mines.gd owns the ladder and the blast (BLAST_RADIUS 3.0, section 3.3);
# this curse widens the sphere the blast measures from and makes the blast reach the
# MINES inside it, not only the players. The module exposes the radius the ladder
# should measure with (blast_radius_u) and the chain itself (chain_targets): every
# other mine whose point sits inside the widened sphere detonates too, so a player who
# steps on one mine can be caught by the second one 4.5 u away. Nothing here kills:
# each chained mine runs the same ladder (defuse -> barrier -> Last Light -> D-MINE),
# which is why the chain is a list of mine indices, never a death.

const CURSE_ID := "wide_blast"

const BLAST_RADIUS_BASE := 3.0   # sim/mines.gd's BLAST_RADIUS (section 3.3)
const BLAST_RADIUS_HELD := 4.5   # the rule sentence's widened sphere


## Stacks the run holds; >= 1 while the curse is picked (max_stacks 1).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## The radius the blast measures with: 4.5 u while held, the base 3.0 u otherwise.
## Pure helper - the test target.
static func blast_radius_u(state: Dictionary) -> float:
	if held_stacks(state) >= 1:
		return BLAST_RADIUS_HELD
	return BLAST_RADIUS_BASE


## True while the blast chain-detonates the mines inside it (the rule sentence's
## second half). Pure helper.
static func chain_detonates(state: Dictionary) -> bool:
	return held_stacks(state) >= 1


## The mines a blast at `origin` chain-detonates: every mine point inside the widened
## sphere, in the order given, minus the mine that detonated (`skip_index`). Empty
## when the curse is not held - the base blast reaches players only.
## `mine_points` is an Array of Vector3 (or of {x,y,z} rows). Pure helper - the test
## target.
static func chain_targets(state: Dictionary, origin: Vector3, mine_points: Array,
		skip_index: int = -1) -> Array:
	var out: Array = []
	if not chain_detonates(state):
		return out
	var r: float = blast_radius_u(state)
	for i in range(mine_points.size()):
		if i == skip_index:
			continue
		var p: Vector3 = _point(mine_points[i])
		if p.distance_to(origin) > r:
			continue
		out.append(i)
	return out


## A mine point as a Vector3: a Vector3 row passes through, a {x,y,z} dict is read.
static func _point(v) -> Vector3:
	if v is Vector3:
		return v
	if v is Dictionary:
		return Vector3(float(v.get("x", 0.0)), float(v.get("y", 0.0)), float(v.get("z", 0.0)))
	return Vector3.ZERO
