extends RefCounted
#
# FULL_GAME_PLAN.md gap 9, redone on the correct architecture. The vote ledger
# is sim state only (sim/gifts.gd's run_votes / run_votes_for: counts keyed by
# whatever roster entry a lobby voted for - sim names no roster entry and
# loads no content data, which is test_boundaries.gd's rule). The count ->
# weight arithmetic (per-vote constant, vote cap) is the roster module's own
# static: content/enemies/gift_larper/enemy.gd's extra_mines(votes), i.e.
# DESIGN.md section 5.7's "each vote adds +3 flat extra mines, under the 20%
# cap". app/world.gd reads the ledger, consults each row's module, and passes
# the sum into terrain's generate() as its extra_mines argument (TERRAIN_SPEC
# section 6.8 clamps the applied count; the base roll is untouched).
#
# Proves, on a REAL generated level (seed 1004, level 12, players 1 - 84 gift
# slots, so the 20% cap is 84 // 5 = 16 and the base roll is 3 mines):
#   - the ledger accessors: a ledger's votes dict, absent key, empty key,
#     negative and zero counts all read correctly;
#   - the roster module's weight: 1/2/3 votes -> 3/6/9, the vote cap clamps
#     99 -> 15 (5 x 3), and zero/negative votes weigh nothing;
#   - N collected votes -> exactly N x 3 extra tripmines placed on the next
#     generated level, on top of the base roll;
#   - the base mines are a subset of every extra-mine level (the extra draws
#     come after the base rolls in the same RNG stream);
#   - zero votes -> zero extra, and the generated level is byte-identical to
#     the base (negative control); a ledger that votes only for a row with no
#     weight declared weighs nothing, so the base count and mine slots are
#     unchanged when the gift row is not owned.

# Tests may name content ids (the boundary scan does not cover the tests
# directory); anything under sim/ terrain/ core/ app/ is scanned instead.
const VoidGenScript := preload("res://terrain/voidgen.gd")
const GiftsScript := preload("res://sim/gifts.gd")
const LarperScript := preload("res://content/enemies/gift_larper/enemy.gd")
const LarperId := "gift_larper"

const SEED := 1004
const LEVEL := 12
const PLAYERS := 1


# The mine slot ids of a generated level (occ == 1 gift slots), sorted.
static func _mine_ids(L: Dictionary) -> Array:
	var out: Array = []
	for s in L["gifts"]:
		if int(s["occ"]) == 1:
			out.append(int(s["id"]))
	out.sort()
	return out


static func _gen(extra: int) -> Dictionary:
	return VoidGenScript.generate(SEED, LEVEL, PLAYERS, extra)


func run() -> Array[String]:
	var f: Array[String] = []
	_test_ledger_accessors(f)
	_test_roster_weight(f)
	_test_votes_become_mines(f)
	_test_negative_control(f)
	return f


# ---- sim's vote ledger (app reads it the same way) ------------------------------

func _test_ledger_accessors(f: Array[String]) -> void:
	var ledger := {"class": "dash", "votes": {LarperId: 4, "understudies": 2}}
	if GiftsScript.run_votes(ledger).size() != 2:
		f.append("ledger: run_votes lost rows from the votes dict")
	if GiftsScript.run_votes_for(ledger, LarperId) != 4:
		f.append("ledger: the gift row's vote count reads as %d, want 4"
				% [GiftsScript.run_votes_for(ledger, LarperId)])
	if GiftsScript.run_votes_for(ledger, "understudies") != 2:
		f.append("ledger: the understudy row's vote count reads as %d, want 2"
				% [GiftsScript.run_votes_for(ledger, "understudies")])
	if GiftsScript.run_votes_for(ledger, "not_a_row_id") != 0:
		f.append("ledger: absent row id reads non-zero")
	# empty / malformed ledgers, empty ids, negative and zero counts: no votes.
	if not GiftsScript.run_votes({}).is_empty():
		f.append("ledger: empty ledger reads non-empty votes")
	if GiftsScript.run_votes({"votes": 7}).size() != 0:
		f.append("ledger: a non-dict votes field reads as rows")
	if GiftsScript.run_votes_for(ledger, "") != 0:
		f.append("ledger: empty row id reads non-zero")
	if GiftsScript.run_votes_for(ledger, LarperId) != 4:
		f.append("ledger: the gift row's vote count re-reads as %d, want 4"
				% [GiftsScript.run_votes_for(ledger, LarperId)])
	var neg := {"votes": {LarperId: -2, "understudies": 0}}
	if GiftsScript.run_votes_for(neg, LarperId) != 0:
		f.append("ledger: negative count reads as votes")
	if GiftsScript.run_votes_for(neg, "understudies") != 0:
		f.append("ledger: zero count reads as votes")
	if GiftsScript.run_votes_for({"votes": {LarperId: 2}}, LarperId) != 2:
		f.append("ledger: a second ledger read counts 2 votes, want 2")


# ---- the roster module's weight (count -> mines is content's number) ------------

func _test_roster_weight(f: Array[String]) -> void:
	# The weight constants the design fixes (DESIGN.md section 5.7): +3 per
	# vote, at most 5 votes counted.
	if int(LarperScript.MINES_PER_VOTE) != 3:
		f.append("roster: per-vote weight is %d, want 3" % [int(LarperScript.MINES_PER_VOTE)])
	if int(LarperScript.MAX_VOTES) != 5:
		f.append("roster: vote cap is %d, want 5" % [int(LarperScript.MAX_VOTES)])
	var cases := {0: 0, 1: 3, 2: 6, 3: 9, 4: 12, 5: 15, 99: 15}
	for votes in cases.keys():
		var got: int = int(LarperScript.extra_mines(int(votes)))
		if got != int(cases[votes]):
			f.append("roster: %d votes -> %d weight, want %d" % [int(votes), got, int(cases[votes])])


# ---- N collected votes -> N x 3 extra mines on the NEXT generated level ---------

func _test_votes_become_mines(f: Array[String]) -> void:
	var base := _gen(0)
	if base.is_empty():
		f.append("generator: empty level for seed %d level %d" % [SEED, LEVEL])
		return
	var b_ids := _mine_ids(base)
	if b_ids.is_empty():
		f.append("generator: base level has 0 mines; the proof level exercises no mines")
		return
	for votes in [1, 2, 3]:
		var weight: int = int(LarperScript.extra_mines(votes))
		var want_extra: int = votes * 3
		if weight != want_extra:
			f.append("votes %d: module weight %d, want %d" % [votes, weight, want_extra])
			continue
		var L := _gen(weight)
		if L.is_empty():
			f.append("votes %d: generator returned an empty level at extra_mines=%d"
					% [votes, weight])
			continue
		var m_ids := _mine_ids(L)
		if m_ids.size() - b_ids.size() != want_extra:
			f.append("votes %d: %d mines placed, base %d, want exactly +%d"
					% [votes, m_ids.size(), b_ids.size(), want_extra])
			continue
		for id in b_ids:
			if not m_ids.has(id):
				f.append("votes %d: base mine slot %d lost when the extra mines were placed"
						% [votes, id])
				break


# ---- negative controls: no vote for the row, no mine -----------------------------

func _test_negative_control(f: Array[String]) -> void:
	var base := _gen(0)
	var b_ids := _mine_ids(base)
	# The app's sum, with the same reads: ledger rows whose module declares no
	# extra_mines() weigh nothing, so only this row's votes move the count.
	var not_owned := {"votes": {"understudies": 3, "gin": 2, "coil": 1}}
	var weight := 0
	for id in GiftsScript.run_votes(not_owned).keys():
		var K = load("res://content/enemies/%s/enemy.gd" % str(id))
		if K == null or not K.has_method("extra_mines"):
			continue
		weight += maxi(0, int(K.call("extra_mines", int(not_owned["votes"].get(id, 0)))))
	if weight != 0:
		f.append("app sum: rows without a weight declaration contributed %d" % [weight])
	# With the row owned but zero votes collected: still zero extra.
	var weight_zero := int(LarperScript.extra_mines(0))
	if weight_zero != 0:
		f.append("app sum: zero votes contribute %d, want 0" % [weight_zero])
	# Zero extra -> the level is byte-identical to the base level.
	var L0 := _gen(weight)
	if L0 != base:
		f.append("negative control: extra 0 level differs from the base level")
	var L1 := _gen(weight_zero)
	if L1 != base:
		f.append("zero votes: extra 0 level differs from the base level")
	if _mine_ids(_gen(weight)) != b_ids:
		f.append("not owned: mine slots changed against the base level")
	if _mine_ids(_gen(weight_zero)) != b_ids:
		f.append("zero votes: mine slots changed against the base level")
