extends RefCounted
#
# state_hash.gd (ticket T-010, R4 ADDENDUM): the state hash = SHA-256 of a UTF-8 text dump,
# one line per field, fields in THIS fixed order, ints in decimal, floats as the 16 hex digits of
# their IEEE-754 64-bit pattern (via StreamPeerBuffer.put_double, D-T010-1), arrays in index order,
# dictionaries by sorted key. NEVER hash a float's decimal string.
#
# Dump field order (frozen here, the single authoritative list):
#   RUN <run_seed>                    run identity
#   PLAYERS <n>                       player count
#   CONTENT <id> ...                  sorted content ids, space separated, one line
#   LEVELNUM <n>                      current level number (0 = none)
#   VOTES <id>:<n> ...                the run's carried enemy set (rs.run_votes), ids sorted,
#                                       zero counts dropped; only when non-empty
#   HUNGER <n>                        rs.run_hunger; only when VOTES is written or n > 0
#   LEVELHASH <hex>                   canonical hash of the Level object (terrain parity hash)
#   TICK <tick>                       per-level tick counter
#   RNG <name> <s>                    one line per sim sub-stream, names sorted (D-T010-3)
#   PLAYER <i>                        one line per player, index order, followed by:
#   X <hex> Y <hex> Z <hex> VX <hex> VY <hex> VZ <hex>
#   GROUNDED <0|1>
#   PREV_BUTTONS <int>
#   GIFTS <phase> <black hex> <gold hex> <base_r bits> <mult bits> <lost hex> <quota> <straggler>
#                                          (T-020) phase + the two slot-id bitsets, hex encoded;
#                                          (C4 review finding 1) then the base pickup radius
#                                          (economy.json gold_phase.gift_pickup_radius) and the
#                                          pickup_radius stat multiplier as float bits. Both are
#                                          CONFIG, not a function of the Level: without them two
#                                          runs whose economy data differed hashed the same until
#                                          a pickup at a distance between the radii diverged.
#                                          Then the lost bitset (a gift whose tile fell in the
#                                          collapse) and the two quota knobs, which change what
#                                          the gift machine does without touching the taken bits.
#   BEACON <opened> <completed>            (T-020) the beacon machine flags
#   MINES <consumed hex>                   (T-021) the tripmine consumed bitset, hex encoded
#   COLLAPSE <enabled> <phase> <start> <cur> <fallen_n> <removed_n> <crack_ticks> <gap_ticks>
#            <partition> <delay_ticks>   (B10, D-B10-1; delay_ticks D-B11-1) the sequential
#                                          platform-collapse schedule; only when the level carries one
#                                          (lstate.collapse non-empty). enabled and the
#                                          timing/partition fields are hashed because they are
#                                          DATA, not a function of the Level: without them two
#                                          runs whose collapse.json differed would hash the same
#                                          until the first zone fell (B10 review finding 1).
#   JUMPPADS <pads x:z:y csv> <ready ticks csv> <lost hex> <rearm_ticks> <launch_speed bits>
#                                          (D-JUMPPAD-4) the jump pads: their ordered coordinates
#                                          (placement depends on data/jump_pads.json, which the
#                                          level hash does not cover - Terra review finding 2),
#                                          then their live state: per pad the
#                                          first tick it may fire again and the bitset of pads
#                                          whose tile fell in the collapse, then the two data
#                                          knobs (data/jump_pads.json). Only when the level
#                                          carries jump pads (lv.jump_pads non-null), so every
#                                          dump of a level built without them is unchanged.
#   CLAWDS <spots x:z:y csv> <taken hex> <anger_ticks> <warned> <kill_ticks> <warning ticks csv>
#            <pickup radius bits>          (T4, D-T4-6) the clawd swarm and the anger timer: the
#                                          ordered clawd coordinates (placement depends on the
#                                          roster module's data, which the level hash does not
#                                          cover), the collected bitset, the live timer and the
#                                          three data knobs. Only when the level carries a swarm
#                                          (lv.clawds non-null).
# Level content itself is NOT dumped: it is a pure function of the seed and enters the hash once,
# via LEVELHASH.

const RUN_STATE := preload("res://sim/run_state.gd")


## The state hash: lowercase hex SHA-256 of the dump lines below, each LF-terminated.
static func sha256(rs: RefCounted) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for line in dump(rs):
		ctx.update((line + "\n").to_utf8_buffer())
	return ctx.finish().hex_encode()


## One line per field, in the fixed order documented in the header. Returns PackedStringArray.
static func dump(rs: RefCounted) -> PackedStringArray:
	var out := PackedStringArray()
	out.append("RUN %d" % rs.run_seed)
	out.append("PLAYERS %d" % rs.players)
	var content := ""
	for id in rs.content_ids:
		content += " %s" % id
	out.append("CONTENT%s" % content)
	out.append("LEVELNUM %d" % rs.level_number)
	# The carried enemy set is run state (DESIGN.md section 6: a vote stays in play for the
	# rest of the run). Absent when the run has voted nothing, so every pre-existing dump
	# (the bare sim, the random-input replay) is byte-identical.
	var vline := _votes_line(rs.get("run_votes"))
	var hunger := int(rs.get("run_hunger")) if rs.get("run_hunger") != null else 0
	if vline != "":
		out.append(vline)
	if vline != "" or hunger > 0:
		out.append("HUNGER %d" % hunger)
	var lv: RefCounted = rs.level
	if lv == null:
		return out
	out.append("LEVELHASH %s" % str(lv.level_hash))
	out.append("TICK %d" % int(lv.tick))
	var names: Array = rs.rng.keys()
	names.sort()
	for n in names:
		out.append("RNG %s %d" % [str(n), int((rs.rng[n] as RefCounted).s)])
	for i in lv.players.size():
		var p: Dictionary = lv.players[i]
		out.append("PLAYER %d" % i)
		out.append("X %s Y %s Z %s VX %s VY %s VZ %s" % [
			bits(float(p["x"])), bits(float(p["y"])), bits(float(p["z"])),
			bits(float(p["vx"])), bits(float(p["vy"])), bits(float(p["vz"])),
		])
		out.append("GROUNDED %d" % (1 if bool(p["grounded"]) else 0))
		out.append("PREV_BUTTONS %d" % int(p["prev_buttons"]))
	# T-020: the gift bitsets + phase and the beacon flags are live state, so they
	# join the dump (D-T020-7); PackedByteArray.hex_encode() is deterministic.
	if lv.gifts != null:
		out.append("GIFTS %s %s %s %s %s %s %d %d" % [
			str(lv.gifts.phase),
			(lv.gifts.black_taken as PackedByteArray).hex_encode(),
			(lv.gifts.gold_taken as PackedByteArray).hex_encode(),
			# C4 review finding 1: the pickup ring is data (economy.json) times the stat
			# multiplier; both decide which input collects, so both are pinned here.
			bits(float(lv.gifts.base_pickup_radius)),
			bits(float(lv.gifts.pickup_mult)),
			# The collapse drops a gift whose tile fell (world.gd _collapse_sweep -> lose()),
			# which moves remaining(), all_black_collected() and the pickup loop. Without
			# this bitset two runs differing only in a lost gift hashed the same - the same
			# hole the ring had. black_quota and straggler_pct are the other two knobs that
			# change what the gift machine does, so they are pinned with it.
			(lv.gifts.lost as PackedByteArray).hex_encode(),
			int(lv.gifts.black_quota),
			int(lv.gifts.straggler_pct),
		])
	if lv.beacon != null:
		out.append("BEACON %d %d" % [
			1 if bool(lv.beacon.opened) else 0,
			1 if bool(lv.beacon.completed) else 0,
		])
	# T-021: the tripmine consumed bitset is live state (D-T021-3); the mine SET
	# itself is not hashed - it is a pure function of the Level hash (occ fields).
	if lv.mines != null:
		out.append("MINES %s" % (lv.mines.consumed as PackedByteArray).hex_encode())
	# B10: the collapse schedule is live state (D-B10-1). Absent for a level with no
	# collapse, so every pre-B10 dump (the bare sim, the replay goldens) is unchanged.
	# enabled and the timing/partition fields are hashed too: they are data, not a function
	# of the Level, so without them two runs whose collapse.json differed would hash the
	# same until the first zone fell and then diverge (B10 review finding 1).
	var cst: Dictionary = lv.collapse
	if not cst.is_empty():
		out.append("COLLAPSE %d %d %d %d %d %d %d %d %s %d" % [
			(1 if bool(cst.get("enabled", true)) else 0),
			int(cst["phase"]), int(cst["start_tick"]), int(cst["cur"]),
			int(cst["fallen_n"]), int(cst["removed_n"]),
			int(cst["crack_ticks"]), int(cst["gap_ticks"]),
			str(cst.get("partition", "")),
			int(cst.get("delay_ticks", 0)),   # D-B11-1: the start delay is data too
		])
	# D-JUMPPAD-4: the pad SET depends on the Level AND on data/jump_pads.json (count, spacing),
	# which LEVELHASH does not cover, so the ordered coordinates are dumped; the re-arm ticks
	# and the lost bitset are live state, the two knobs are data.
	var jp = lv.get("jump_pads")
	if jp != null:
		out.append("JUMPPADS %s %s %s %d %s" % [str(jp.pads_csv()), str(jp.ready_csv()),
				(jp.lost as PackedByteArray).hex_encode(), int(jp.rearm_ticks),
				bits(float(jp.launch_speed))])
	# .get(): a test StubLevel has no boss key (T8b gate fix, same as sim/gifts.gd).
	var boss_ref = lv.get("boss")
	if boss_ref != null:
		var encounter: Dictionary = boss_ref.snapshot()
		if lv.arena_controller != null:
			encounter["controller"] = _arena_controller_fields(lv.arena_controller)
			encounter["gift_fire"] = lv.boss_gifts.snapshot()
			encounter["purse_centi"] = lv.arena_purse_centi
		out.append("BOSS " + var_to_bytes(_canonical(encounter)).hex_encode())
	var rt = lv.enemy_runtime
	if rt != null:
		var queue: Array = []
		var has_hashed_plan := false
		for entry in rt.planned:
			var state: Array = entry["behavior"].hash_pending(entry)
			has_hashed_plan = has_hashed_plan or not state.is_empty()
			queue.append([entry["id"], entry["copies"], entry.get("spawned_copies", 0),
					entry["spawn_target"], entry["cfg"].get("preferred_kind", ""), state])
		if has_hashed_plan:
			out.append("ENEMY_QUEUE %d %d %s" % [rt.tick, rt.spawn_delay_ticks,
					var_to_bytes(queue).hex_encode()])
		for row in rt.enemies:
			var state: Array = row["behavior"].hash_state(row)
			if not state.is_empty():
				out.append("ENEMY %s %d %s" % [row["id"], rt.tick, var_to_bytes(state).hex_encode()])
	# T4 (D-T4-6): the clawd swarm + the anger timer. The coordinates are dumped because placement depends on
	# the roster module's data (count, spacing), which LEVELHASH does not cover - the same reason the pads are.
	# taken / anger_ticks / warned are live state; the three knobs are data, pinned so two runs whose data
	# differed cannot hash alike before the first pickup. Absent for a level with no swarm.
	var cl = lv.get("clawds")
	if cl != null:
		out.append("CLAWDS %s %s %d %d %d %s %s" % [str(cl.spots_csv()),
				(cl.taken as PackedByteArray).hex_encode(), int(cl.anger_ticks), int(cl.warned),
				int(cl.kill_ticks), str(cl.warnings_csv()), bits(float(cl.pickup_radius))])
	return out


## Canonical binary values preserve the exact float bits in boss and controller state.
static func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var sorted := {}
		for key in keys:
			sorted[key] = _canonical(value[key])
		return sorted
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_canonical(item))
		return result
	return value


static func _arena_controller_fields(controller: RefCounted) -> Dictionary:
	var fields := {}
	for prop in controller.get_property_list():
		if (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 \
				and int(prop["type"]) != TYPE_CALLABLE:
			fields[prop["name"]] = controller.get(prop["name"])
	return fields


## "VOTES id:n id:n" over the positive counts, ids sorted; "" when there are none.
static func _votes_line(v: Variant) -> String:
	if not (v is Dictionary):
		return ""
	var ids: Array = (v as Dictionary).keys()
	ids.sort()
	var parts := PackedStringArray()
	for id in ids:
		var n := int((v as Dictionary)[id])
		if n > 0:
			parts.append("%s:%d" % [str(id), n])
	if parts.is_empty():
		return ""
	return "VOTES " + " ".join(parts)


## The 16 hex digits of the double's IEEE-754 64-bit pattern, most significant byte first (D-T010-1).
## Never a decimal string: 1.0 must hash as 3FF0000000000000, not "1".
static func bits(x: float) -> String:
	var buf := StreamPeerBuffer.new()
	buf.put_double(x)
	var b: PackedByteArray = buf.data_array
	# StreamPeer is little-endian by default, so byte 7 is the most significant; hex digits are
	# written big-endian. test_replay.gd pins this with absolute known answers.
	var out := ""
	for i in range(7, -1, -1):
		out += "%02X" % b[i]
	return out
