extends RefCounted
#
# direct_shot.gd - script curse (ticket T-051; DESIGN.md section 7.1 "direct_shot").
# Rule sentence (spec, verbatim): "balls ricochet once off tiles/props".
# Counter-play: "break sightline entirely - a ricochet kills too, so don't hug cover".
#
# Reading (recorded in DECISIONS.md, D-T051-3 [CONTESTABLE]): an Isagi ball dies the
# step it enters a tile slab or prop (sim projectiles carry no bounce). The curse
# keeps each ball alive for exactly ONE extra bounce: when the projectile's next
# step would enter a solid, the offending axis of the velocity is mirrored and the
# step retries - once per ball, tracked by the row's "bounced" flag. The ball keeps
# killing (it stays the enemy's own projectile; DEATH code unchanged). Which axis
# mirrors is the contestable part: the offending axis is the one whose entry the
# step rejected (x or z; a floor hit reflects nothing - there is no ceiling game).

const CURSE_ID := "direct_shot"

const ISAGI_ID := "isagi"         # the enemy the curse attaches to (content names content)
const BOUNCES := 1                # "ricochet once"


## Stacks the run holds; >= 1 while the curse is picked (max_stacks 1).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## on_tick: scan the runtime's projectiles and bounce each Isagi ball once.
static func on_tick(state: Dictionary, api) -> void:
	if held_stacks(state) <= 0:
		return
	var rt = state.get("enemy_runtime")
	if rt == null:
		return
	for p in rt.projectiles:
		if not _is_isagi_ball(p):
			continue
		try_bounce(p, state, api)


## An Isagi ball: the projectile rows the runtime spawns keep the source's name
## (spawn_projectile defaults def.name to the source row's name).
static func _is_isagi_ball(p: Dictionary) -> bool:
	return str(p.get("name", "")).to_lower().contains("isagi")


## Pure helper (test target): mirrors the offending horizontal axis of the ball's
## velocity - the axis whose step entry the world rejected. ONCE per ball, then
## the flag stops every further call: "ricochet once".
static func try_bounce(p: Dictionary, state: Dictionary, api) -> bool:
	if int(p.get("bounces_left", BOUNCES)) <= 0:
		return false
	var axis := offending_axis(p, state)
	if axis == "":
		return false
	var vx := float(p.get("vx", 0.0))
	var vz := float(p.get("vz", 0.0))
	if axis == "x":
		p["vx"] = -vx
	else:
		p["vz"] = -vz
	p["bounces_left"] = int(p.get("bounces_left", BOUNCES)) - 1
	if api.has_method("rng"):
		pass   # deterministic reflection - no rng draw exists in this curse
	return true


## The axis whose NEXT step enters a solid tile of the collision world.
## Empty when the path is clear (no bounce this tick).
static func offending_axis(p: Dictionary, state: Dictionary) -> String:
	var rt = state.get("enemy_runtime")
	if rt == null:
		return ""
	var w: Dictionary = rt.world
	var x := float(p.get("x", 0.0))
	var z := float(p.get("z", 0.0))
	var vx := float(p.get("vx", 0.0))
	var vz := float(p.get("vz", 0.0))
	if vx != 0.0 and solid_next(w, x + vx / 60.0, z):
		return "x"
	if vz != 0.0 and solid_next(w, x, z + vz / 60.0):
		return "z"
	return ""


## True when the point (x, z) sits inside a live tile column: the same "column +
## height" shape the collision world stores, asked at any height (balls travel
## level flight, and DESIGN.md's tiles block whole columns for projectiles).
static func solid_next(w: Dictionary, x: float, z: float) -> bool:
	var key := "%d,%d" % [int(floorf(x)), int(floorf(z))]
	var col: Variant = w.get("cols", {}).get(key, null)
	if not (col is Array):
		return false
	return not (col as Array).is_empty()
