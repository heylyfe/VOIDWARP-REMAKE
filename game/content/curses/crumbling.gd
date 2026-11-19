extends RefCounted
#
# crumbling.gd - the Crumbling script curse (DESIGN.md section 7.2, GENERAL family;
# ticket T-051).
#
# Rule: "1-wide walkway tiles fall 1.2 s after being stepped on and return after 5 s".
#
# Module shape (per DECISIONS D-T051-1): hooks only, state in, events out, no engine
# surface. The rule's tile reading (which tiles are 1-wide, when they were stepped on)
# stays with the sim dispatcher; this module owns the SCHEDULE:
#   - step_on(state, key) arms the tile: FALL_DELAY_TICKS (72 = 1.2 s) to the fall,
#     RETURN_DELAY_TICKS (300 = 5.0 s) later the regrow;
#   - on_tick(state) advances the schedule and returns events in key order:
#     {"e": "tile_fell", "key": key} / {"e": "tile_returned", "key": key} - the
#     dispatcher erases (falls) or restores (regrows) the tile in the world's live
#     tile-modified set (w["removed"], D-051's surface).
#
# No engine surface, no RNG: whole 60 Hz ticks against the level's own tick counter
# (state["tick"]), the D-040 always-returns guarantee as the regrow deadline.

const CURSE_ID := "crumbling"
const FALL_DELAY_TICKS := 72     # 1.2 s after being stepped on (the rule sentence)
const RETURN_DELAY_TICKS := 300  # 5.0 s after the fall (the rule sentence)


## Stacks the run holds; >= 1 while the curse is picked (the sim's {curse_id: stacks}).
## The uniform module contract (test_curse_content.gd assertion 6): every script curse
## answers this, so the dispatcher can ask any module whether it is held without
## special-casing the hooks-only shape this module has.
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


# ---- per-curse slot (the D-T051-1 shape: state["curse_st"][CURSE_ID]) ----------------
# {"keys": {tile_key: row}} with a schedule row {"fall_tick": int, "return_tick": int,
# "fell": bool, "returned": bool} in whole 60 Hz ticks. Tile keys are collision.gd's own
# "%d,%d,%d" (x, z, y_hu) — the dispatcher reads them out of collision.gd support_at().

static func _slot(state: Dictionary) -> Dictionary:
	var root_v: Variant = state.get("curse_st", {})
	var root: Dictionary = {}
	if root_v is Dictionary:
		root = root_v
	if not root.has(CURSE_ID):
		root[CURSE_ID] = {"keys": {}}
	state["curse_st"] = root
	return root[CURSE_ID]


## A player stepped onto tile key (collision.gd's own tile key): arm the schedule.
## The FIRST schedule wins — a tile already scheduled (fell or not) is returned as-is,
## so re-stepping never extends or restarts a tile's clock.
static func step_on(state: Dictionary, key: String) -> Dictionary:
	var keys: Dictionary = _slot(state)["keys"]
	if keys.has(key):
		return keys[key]
	var now := int(state.get("tick", 0))
	var e := {
		"fall_tick": now + FALL_DELAY_TICKS,
		"return_tick": now + FALL_DELAY_TICKS + RETURN_DELAY_TICKS,
		"fell": false,
		"returned": false,
	}
	keys[key] = e
	return e


## One 60 Hz tick over the schedule. Returns this tick's events, in key order:
##   {"e": "tile_fell", "key": key}     - fall_tick reached: the dispatcher now erases
##                                        the tile from the world's removed set;
##   {"e": "tile_returned", "key": key} - return_tick reached: the dispatcher now
##                                        restores the tile (the regrow).
## The flags flip exactly once and stay flipped.
static func on_tick(state: Dictionary) -> Array:
	var events: Array = []
	var keys: Dictionary = _slot(state)["keys"]
	var now := int(state.get("tick", 0))
	for key in keys.keys():
		var e: Dictionary = keys[key]
		if not bool(e["fell"]):
			if now >= int(e["fall_tick"]):
				e["fell"] = true
				events.append({"e": "tile_fell", "key": key})
		elif not bool(e["returned"]):
			if now >= int(e["return_tick"]):
				e["returned"] = true
				events.append({"e": "tile_returned", "key": key})
	return events
