extends RefCounted
#
# test_curse_bay.gd (audit A5; DESIGN.md section 7 "Draw: 3 distinct curses from the
# eligible pool; at least one Mild if any Mild is eligible"). Proves on the REAL content
# that one C-bay draw (sim/offers.gd draw_curse_bay) never offers the same curse on two
# altars of one bay:
#   - many seeds x every level 1..30 x several vote sets x random held sets (some of
#     them shrink the pool down to exactly 3, 4, 5 entries, where a duplicate draw is
#     most likely): whenever the eligible, not-maxed pool has >= 3 entries the bay has
#     3 altars with 3 distinct ids;
#   - every altar id is in that pool, and a Mild altar is present whenever a Mild curse
#     is in the pool;
#   - a pool of 1 or 2 entries yields exactly that many altars, still distinct.
# The fill pool used to still hold the Mild drawn first, so the same Mild curse could
# sit on two altars of one bay (fixed in a5d68de; this is its regression test).

const ContentApiScript := preload("res://core/content_api.gd")
const OffersScript := preload("res://sim/offers.gd")
const VoidRngScript := preload("res://terrain/void_rng.gd")

const SEEDS := 16


func run() -> Array[String]:
	var f: Array[String] = []
	var api := ContentApiScript.load()
	if not bool(api.is_ok()):
		f.append("content api boot failed: %s" % " / ".join(api.boot_errors()))
		return f
	_test_distinct_over_seeds(f, api)
	_test_small_pools(f, api)
	return f


## The pool draw_curse_bay draws from: eligible and not held at max stacks.
func _pool(api: RefCounted, level: int, votes: Dictionary, held: Dictionary) -> Array:
	var out: Array = []
	for id in api.eligible_curses(level, votes):
		var cid := str(id)
		var c: Dictionary = api.curse(cid)
		if int(held.get(cid, 0)) >= int(c.get("max_stacks", 1)):
			continue
		out.append(cid)
	return out


func _has_mild(api: RefCounted, ids: Array) -> bool:
	for cid in ids:
		if str((api.curse(str(cid)) as Dictionary).get("severity", "")) == "mild":
			return true
	return false


## Held set that leaves exactly `keep` pool entries (or the whole pool when it is smaller):
## every other id is held at its max stacks. Which ids survive is a seeded choice.
func _held_leaving(api: RefCounted, level: int, votes: Dictionary, keep: int,
		rng: RefCounted) -> Dictionary:
	var ids: Array = _pool(api, level, votes, {})
	rng.shuffle(ids)
	var held: Dictionary = {}
	for i in range(keep, ids.size()):
		var cid := str(ids[i])
		held[cid] = int((api.curse(cid) as Dictionary).get("max_stacks", 1))
	return held


## One bay checked against its pool. `tag` names the case in a failure message.
func _check_bay(f: Array[String], api: RefCounted, level: int, votes: Dictionary,
		held: Dictionary, seed_value: int, tag: String) -> void:
	var pool: Array = _pool(api, level, votes, held)
	var rng: RefCounted = VoidRngScript.new(VoidRngScript.mix(seed_value, 0xC0B))
	var bay: Dictionary = OffersScript.draw_curse_bay(api, level, votes, held, rng, 0)
	var ids: Array = []
	for a in bay.get("altars", []):
		ids.append(str((a as Dictionary).get("id", "")))
	var seen: Dictionary = {}
	for cid in ids:
		if seen.has(cid):
			f.append("%s level %d seed %d: curse %s offered twice in one bay %s (pool %d)"
					% [tag, level, seed_value, cid, str(ids), pool.size()])
		seen[cid] = true
		if not pool.has(cid):
			f.append("%s level %d seed %d: altar %s is not in the eligible pool"
					% [tag, level, seed_value, cid])
	var want := mini(3, pool.size())
	if ids.size() != want:
		f.append("%s level %d seed %d: %d altars for a pool of %d, want %d %s"
				% [tag, level, seed_value, ids.size(), pool.size(), want, str(ids)])
	if _has_mild(api, pool) and not _has_mild(api, ids):
		f.append("%s level %d seed %d: a Mild curse is eligible but no Mild altar %s"
				% [tag, level, seed_value, str(ids)])


## Vote sets: none, every enemy voted once (every enemy-linked curse eligible), and one
## enemy per case (a few linked curses in, the rest out).
func _vote_sets(api: RefCounted) -> Array:
	var all: Dictionary = {}
	var out: Array = [{}]
	for eid in api.enemy_ids():
		all[str(eid)] = 1
		out.append({str(eid): 1})
	out.append(all)
	return out


func _test_distinct_over_seeds(f: Array[String], api: RefCounted) -> void:
	var vote_sets: Array = _vote_sets(api)
	var bays := 0
	var full_pools := 0
	for level in range(1, 31):
		for vi in vote_sets.size():
			var votes: Dictionary = vote_sets[vi]
			for s in range(SEEDS):
				var seed_value: int = 50000 + level * 1000 + vi * 100 + s
				var hrng: RefCounted = VoidRngScript.new(seed_value)
				# s % 4: 0 = nothing held, 1..3 = pools trimmed to 3 / 4 / 5 entries
				var held: Dictionary = {}
				if s % 4 != 0:
					held = _held_leaving(api, level, votes, 2 + s % 4, hrng)
				if _pool(api, level, votes, held).size() >= 3:
					full_pools += 1
				_check_bay(f, api, level, votes, held, seed_value, "sweep")
				bays += 1
				if f.size() > 20:
					f.append("(stopped after 20 failures)")
					return
	if full_pools < bays / 2:
		f.append("only %d of %d bays had a pool of >= 3: the sweep does not exercise the 3-altar draw"
				% [full_pools, bays])


func _test_small_pools(f: Array[String], api: RefCounted) -> void:
	for keep in [1, 2]:
		for s in range(SEEDS):
			var seed_value: int = 90000 + keep * 1000 + s
			var held: Dictionary = _held_leaving(api, 20, {}, keep,
					VoidRngScript.new(seed_value))
			_check_bay(f, api, 20, {}, held, seed_value, "pool-%d" % keep)
	# an empty pool draws an empty bay (the tithe is then the only way past)
	var none: Dictionary = _held_leaving(api, 20, {}, 0, VoidRngScript.new(1))
	var empty: Dictionary = OffersScript.draw_curse_bay(api, 20, {}, none,
			VoidRngScript.new(2), 0)
	if not (empty.get("altars", []) as Array).is_empty():
		f.append("an exhausted curse pool still drew altars: %s" % str(empty.get("altars")))
