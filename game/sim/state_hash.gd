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
#   LEVELHASH <hex>                   canonical hash of the Level object (terrain parity hash)
#   TICK <tick>                       per-level tick counter
#   RNG <name> <s>                    one line per sim sub-stream, names sorted (D-T010-3)
#   PLAYER <i>                        one line per player, index order, followed by:
#   X <hex> Y <hex> Z <hex> VX <hex> VY <hex> VZ <hex>
#   GROUNDED <0|1>
#   PREV_BUTTONS <int>
#   GIFTS <phase> <black hex> <gold hex>   (T-020) phase + the two slot-id bitsets, hex encoded
#   BEACON <opened> <completed>            (T-020) the beacon machine flags
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
		out.append("GIFTS %s %s %s" % [
			str(lv.gifts.phase),
			(lv.gifts.black_taken as PackedByteArray).hex_encode(),
			(lv.gifts.gold_taken as PackedByteArray).hex_encode(),
		])
	if lv.beacon != null:
		out.append("BEACON %d %d" % [
			1 if bool(lv.beacon.opened) else 0,
			1 if bool(lv.beacon.completed) else 0,
		])
	return out


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
