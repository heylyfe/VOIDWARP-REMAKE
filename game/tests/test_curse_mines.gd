extends RefCounted
#
# CURSE-MINES test (headless, W10-A): the mine-side curse queries change the shipped game.
#
# The two mine curses are pure QUERY modules (no hook does the work): sim/mines.gd must ask
# them. This file never calls a curse module. Every case builds a real level through
# app/world.gd build() with a carried ledger whose only variable is the curses dict, and
# measures through the world's own LevelState mines object - which reaches the curses
# through the dispatcher world.gd hands it (lstate.mines.curses). Each case runs twice:
# curses {} (the negative control, asserted against the un-cursed literal) and held.
#
#   chain   world.step(): the player steps on mine A; a second mine B moved 4.0 u from A
#           detonates when the blast curse is held (inside 4.5 u) and stays live when not
#           (the base blast never reaches mines). A third mine C 6.0 u the other side stays
#           live in both runs (outside 4.5 u of A and of B).
#   radius  MinesScript.tick on the SAME world's lstate (world.step drives player 0 only,
#           and a blast only reaches OTHER players): a second player 4.0 u from the mine
#           dies held and survives un-held; a third 6.0 u away survives both. The
#           detonation event carries blast_radius 4.5 / 3.0.
#   tell    the world's mines object answers tell_distance() 6 / 12 and
#           tell_ramp_near(10) 5 / 10 (the tell is drawn by view/tripmine_view.gd).

const WorldScript := preload("res://app/world.gd")
const MinesScript := preload("res://sim/mines.gd")
const ControllerScript := preload("res://sim/controller.gd")
const GiftsScript := preload("res://sim/gifts.gd")

const LEVEL := 9
const DT := 1.0 / 60.0
const BLAST := "wide_blast"
const TELL := "method_acting"


func run() -> Array[String]:
	var f: Array[String] = []
	var seed := _seed_with_mines(3)
	if seed < 0:
		f.append("no seed in 1..40 builds a level %d with >= 3 mines" % LEVEL)
		return f
	_chain(f, seed)
	_radius(f, seed)
	_tell(f, seed)
	return f


# ---- helpers -------------------------------------------------------------------------------

func _build(seed: int, curses: Dictionary):
	var world = WorldScript.new()
	var ledger := {
		"class": "dasher", "votes": {}, "curses": curses, "stacks": {},
		"purse": 0, "tithes": 0, "hunger": 0, "last_vote": "",
	}
	if not world.build(seed, LEVEL, ledger):
		world.free()
		return null
	return world


func _drop(world) -> void:
	if world != null:
		world.teardown()
		world.free()


func _seed_with_mines(n: int) -> int:
	for s in range(1, 41):
		var world = _build(s, {})
		if world == null:
			continue
		var c: int = world.lstate.mines.count()
		_drop(world)
		if c >= n:
			return s
	return -1


func _check(f: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		f.append(msg)


## Move mine slot `s` dx_tiles tiles along x from slot `like` (same z, same height): its
## point then sits exactly dx_tiles u from `like`'s point.
func _move(m, s: int, like: int, dx_tiles: int) -> void:
	var row: Dictionary = m.slots[s]
	row["x"] = int(m.slots[like]["x"]) + dx_tiles
	row["z"] = int(m.slots[like]["z"])
	row["y"] = int(m.slots[like]["y"])


## Put a controller's centre on (x, z) with its body centre at the mine-point height of
## slot `like`; Last Light spent so a kill assertion cannot be saved (D-057).
func _place(m, ctl, like: int, x: float, z: float) -> void:
	ctl.x = x
	ctl.z = z
	ctl.y = m.point(like).y - GiftsScript.BODY_CENTER
	ctl.vx = 0.0
	ctl.vy = 0.0
	ctl.vz = 0.0
	ctl.invuln = 0.0
	ctl.last_light_spent = true


static func _kind(ev: Array, k: String) -> Array:
	var out: Array = []
	for e in ev:
		if str(e.get("type", e.get("e", ""))) == k:
			out.append(e)
	return out


## Lay the level's mines out for a case: A stays; B 4 tiles +x of A; C 6 tiles -x of A;
## every other mine parked 200+ tiles away, 10 apart (out of every sphere). Returns [A, B, C].
func _layout(m) -> Array:
	var a: int = int(m.ids[0])
	var b: int = int(m.ids[1])
	var c: int = int(m.ids[2])
	_move(m, b, a, 4)
	_move(m, c, a, -6)
	var k := 0
	for s in m.ids:
		if int(s) == a or int(s) == b or int(s) == c:
			continue
		_move(m, int(s), a, 200 + 10 * k)
		k += 1
	return [a, b, c]


## The world handed its curse dispatcher to the mines (world.gd build()); without that the
## held half of every case below cannot pass.
func _wired(f: Array[String], world, tag: String) -> bool:
	if world.lstate.mines.curses == null:
		f.append("%s: world.build() did not hand the curse dispatcher to lstate.mines.curses" % tag)
		return false
	return true


# ---- chain: through world.step() -----------------------------------------------------------

func _chain(f: Array[String], seed: int) -> void:
	for held in [false, true]:
		var tag := "chain(held=%s)" % str(held)
		var world = _build(seed, {BLAST: 1} if held else {})
		if world == null:
			f.append("%s: build failed" % tag)
			continue
		if not _wired(f, world, tag):
			_drop(world)
			continue
		var m = world.lstate.mines
		var abc := _layout(m)
		var pa: Vector3 = m.point(int(abc[0]))
		_place(m, world.ctl, int(abc[0]), pa.x, pa.z)
		var sa: Dictionary = m.slots[int(abc[0])]
		world.ctl.cur_key = "%d,%d,%d" % [int(sa["x"]), int(sa["z"]), int(sa["y"])]
		world.step(DT)
		_check(f, m.is_consumed(int(abc[0])) and bool(world.ctl.dead),
				"%s: the player did not detonate mine A through world.step (consumed=%s dead=%s)"
				% [tag, str(m.is_consumed(int(abc[0]))), str(bool(world.ctl.dead))])
		_check(f, m.is_consumed(int(abc[1])) == held,
				"%s: mine B 4.0 u from A consumed=%s, want %s" % [tag,
				str(m.is_consumed(int(abc[1]))), str(held)])
		_check(f, not m.is_consumed(int(abc[2])),
				"%s: mine C 6.0 u from A was consumed (outside every sphere)" % tag)
		_drop(world)


# ---- radius: the world's own mines object, two players -------------------------------------

func _radius(f: Array[String], seed: int) -> void:
	for held in [false, true]:
		var tag := "radius(held=%s)" % str(held)
		var world = _build(seed, {BLAST: 1} if held else {})
		if world == null:
			f.append("%s: build failed" % tag)
			continue
		if not _wired(f, world, tag):
			_drop(world)
			continue
		var lst = world.lstate
		var m = lst.mines
		# only A is a mine near anything: B and C go to the far park too, so the victims
		# below stand on no mine and no chain can stand in for the radius
		var abc := _layout(m)
		_move(m, int(abc[1]), int(abc[0]), 400)
		_move(m, int(abc[2]), int(abc[0]), 420)
		var a_slot := int(abc[0])
		var pa: Vector3 = m.point(a_slot)
		var p0 = world.ctl
		var p1 = ControllerScript.new()
		p1.setup("dasher", ControllerScript.load_constants())
		var p2 = ControllerScript.new()
		p2.setup("dasher", ControllerScript.load_constants())
		_place(m, p0, a_slot, pa.x, pa.z)
		_place(m, p1, a_slot, pa.x + 4.0, pa.z)
		_place(m, p2, a_slot, pa.x - 6.0, pa.z)
		var ctls: Array = [p0, p1, p2]
		while lst.players.size() < ctls.size():
			lst.players.append({})
		for j in ctls.size():
			var row: Dictionary = lst.players[j]
			row["x"] = float(ctls[j].x)
			row["y"] = float(ctls[j].y)
			row["z"] = float(ctls[j].z)
		var ev: Array = []
		MinesScript.tick(lst, ctls, world.w, [0, 0, 0], int(lst.tick) + 1, ev)
		var det := _kind(ev, MinesScript.EV_MINE_DETONATED)
		var want_r := 4.5 if held else 3.0
		_check(f, det.size() == 1 and is_equal_approx(float(det[0]["blast_radius"]), want_r),
				"%s: want one detonation with blast_radius %.1f, got %s" % [tag, want_r, str(det)])
		_check(f, bool(p0.dead), "%s: the contactor did not die" % tag)
		_check(f, bool(p1.dead) == held,
				"%s: the player 4.0 u from the mine dead=%s, want %s" % [tag, str(bool(p1.dead)),
				str(held)])
		_check(f, held == false or str(p1.dead_code) == "D-MINE",
				"%s: the widened-blast victim died %s, not D-MINE" % [tag, str(p1.dead_code)])
		_check(f, not bool(p2.dead), "%s: the player 6.0 u away died (outside 4.5 u)" % tag)
		_check(f, _kind(ev, MinesScript.EV_MINE_CHAIN).is_empty(),
				"%s: a chain fired with no second mine in range" % tag)
		_drop(world)


# ---- tell: the world's mines object answers the view's numbers -----------------------------

func _tell(f: Array[String], seed: int) -> void:
	for held in [false, true]:
		var tag := "tell(held=%s)" % str(held)
		var world = _build(seed, {TELL: 1} if held else {})
		if world == null:
			f.append("%s: build failed" % tag)
			continue
		if not _wired(f, world, tag):
			_drop(world)
			continue
		var m = world.lstate.mines
		var want_d := 6.0 if held else 12.0
		var want_n := 5.0 if held else 10.0
		_check(f, is_equal_approx(float(m.tell_distance()), want_d),
				"%s: tell_distance %.2f, want %.1f" % [tag, float(m.tell_distance()), want_d])
		_check(f, is_equal_approx(float(m.tell_ramp_near(10.0)), want_n),
				"%s: tell_ramp_near(10) %.2f, want %.1f" % [tag, float(m.tell_ramp_near(10.0)),
				want_n])
		# the blast curse is not this one: the blast numbers stay canon under it
		_check(f, is_equal_approx(float(m.blast_radius()), 3.0) and m.chain_slots(int(m.ids[0])).is_empty(),
				"%s: the tell curse moved the blast numbers" % tag)
		_drop(world)
