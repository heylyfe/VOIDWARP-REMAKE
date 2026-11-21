extends SceneTree
#
# In-run HUD screenshot tool (cycle 4 items 9, 8 and 11): boots the REAL world
# (app/world.gd) with a carried run ledger - several voted enemy types, some curses and
# some upgrades - and captures the HUD as the player sees it mid-level: the enemy counter
# (one cell per type, its sprite and its count) and the curse / upgrade icon rows.
# Windowed run - rendering needs a GPU context, never --headless:
#
#   <godot> --path game --script res://tests/shot_hud.gd -- <out_dir> [seed] [level]
#
# Writes <out_dir>/hud_00_typical.png  (5 enemy types, 4 curses, 4 upgrades)
#        <out_dir>/hud_01_full.png     (all 12 enemy types, 12 curses, 12 upgrades: the
#                                       worst case the corners must still hold)
#        <out_dir>/hud_02_zoom.png     (hud_00's top-left counter, cropped 3x)
# Prints a DIAG line per shot: the counter's cells, which ones carry real sprite art, their
# badges, and the on-screen rects of the counter, the icon rows and the purse, with an
# overlap check. Named shot_*, not test_*, so tests/run_all.gd skips it. Prints
# "SHOT <path>" per PNG and "SHOTX OK" / "SHOTX FAIL <why>"; exit 1 on failure.

const WorldScript := preload("res://app/world.gd")

const SHOT_SIZE := Vector2i(1280, 720)
const DT := 1.0 / 60.0
const SETTLE_TICKS := 90
const MAX_TICKS := 60 * 40

const TYPICAL := {
	"class": "dasher", "purse": 12000, "tithes": 0, "hunger": 0, "last_vote": "",
	"votes": {"kiwi_cat": 3, "coil": 1, "seal": 2, "thicc_ben": 1, "gift_larper": 2},
	"curses": {"brittle": 1, "tarnish": 2, "inflation": 1, "curfew": 1},
	"stacks": {"brace": 2, "more": 1, "paycheck": 1, "yearn_for_speed": 1},
}
const ALL_ENEMIES := ["address_me", "claude", "coil", "gift_larper", "gin", "isagi",
		"kiwi_cat", "nuke", "seal", "thicc_ben", "toucher", "you"]
const MANY_CURSES := ["aftershock", "brittle", "bunker_buster", "cold_start", "crescendo",
		"curfew", "dull_gifts", "egoist", "hasty", "inflation", "tarnish", "wet_floor"]
const MANY_UPGRADES := ["bargain", "brace", "cartographer", "featherfall", "hot_streak",
		"marathon", "more", "paycheck", "spring_heels", "sure_foot", "twin_dash", "updraft"]

var _out_dir := ""
var _seed := 7
var _level := 3
var _fail := ""
var _world = null


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	root.size = SHOT_SIZE
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out_dir = args[0] if args.size() >= 1 else ProjectSettings.globalize_path("res://shots_hud")
	if args.size() >= 2:
		_seed = int(args[1])
	if args.size() >= 3:
		_level = int(args[2])
	if DirAccess.make_dir_recursive_absolute(_out_dir) != OK:
		_fail = "cannot create %s" % _out_dir
		_finish()
		return
	if not await _capture("hud_00_typical", TYPICAL.duplicate(true)):
		_finish()
		return
	var img: Image = root.get_texture().get_image()
	var crop := img.get_region(Rect2i(0, 0, 260, 200))
	crop.resize(780, 600, Image.INTERPOLATE_NEAREST)
	_save(crop, "hud_02_zoom")
	var full: Dictionary = TYPICAL.duplicate(true)
	full["votes"] = {}
	for id in ALL_ENEMIES:
		full["votes"][id] = 1 + (ALL_ENEMIES.find(id) % 3)
	full["curses"] = {}
	for id in MANY_CURSES:
		full["curses"][id] = 1
	full["stacks"] = {}
	for id in MANY_UPGRADES:
		full["stacks"][id] = 1
	await _capture("hud_01_full", full)
	_finish()


func _capture(name: String, ledger: Dictionary) -> bool:
	if _world != null:
		_world.teardown()
		_world.queue_free()
		_world = null
		await process_frame
	_world = WorldScript.new()
	root.add_child(_world)
	if not _world.build(_seed, _level, ledger):
		_fail = "world.build(%d, %d) returned false for %s" % [_seed, _level, name]
		return false
	# Run until several enemies are actually on the field (or MAX_TICKS), so the counter is
	# shot beside live bodies, not only as a plan.
	var t := 0
	while t < SETTLE_TICKS or (_live_enemies() < 3 and t < MAX_TICKS):
		_world.ctl.invuln = 1.0   # keep the body alive for the shot; the HUD is the subject
		_world.step(DT)
		t += 1
	print("DIAG %s ticks=%d" % [name, t])
	await process_frame
	await process_frame
	_diag(name, ledger)
	await _shot(name)
	return _fail == ""


func _diag(tag: String, ledger: Dictionary) -> void:
	var hud = _world.hud
	var er: Control = hud.enemy_roster
	var cells: PackedStringArray = []
	for item in er._items:
		var art: bool = er.icon_for(str(item["id"])) != null
		cells.append("%s x%d art=%s" % [item["id"], int(item["count"]), str(art)])
		if not art:
			_fail = "%s: enemy %s shows the placeholder, not its sprite" % [tag, item["id"]]
	var want := (ledger["votes"] as Dictionary).size()
	if er._items.size() != want:
		_fail = "%s: the counter shows %d types, the ledger has %d" % [tag, er._items.size(), want]
	var r_roster: Rect2 = er._row.get_global_rect()
	var r_icons: Rect2 = hud.icon_rows.get_global_rect()
	var r_purse: Rect2 = hud.purse_chain.get_global_rect()
	print("DIAG %s cells=%d [%s] roster_rect=%s icon_rows_rect=%s curses=%d upgrades=%d purse_rect=%s roster_x_icons=%s icons_x_purse=%s live_enemies=%d" % [
			tag, er._items.size(), "; ".join(cells), str(r_roster), str(r_icons),
			hud.icon_rows.curse_count(), hud.icon_rows.upgrade_count(), str(r_purse),
			str(_cells_overlap(er._row, hud.icon_rows)), str(_cells_overlap(hud.icon_rows, hud.purse_chain)),
			_live_enemies()])


## True when any drawn cell of a overlaps any drawn cell of b (their leaf Controls).
func _cells_overlap(a: Control, b: Control) -> bool:
	for ca in _leaves(a):
		for cb in _leaves(b):
			if ca.intersects(cb):
				return true
	return false


func _leaves(c: Control) -> Array:
	var out: Array = []
	for n in c.find_children("*", "Control", true, false):
		var k := n as Control
		if k.is_visible_in_tree() and k.get_child_count() == 0 and k.size.x > 0.0:
			out.append(k.get_global_rect())
	return out


func _live_enemies() -> int:
	var w: Dictionary = _world.w
	return (w.get("enemies", []) as Array).size()


func _shot(name: String) -> void:
	var img: Image = root.get_texture().get_image()
	if img == null:
		_fail = "viewport texture returned null for %s" % name
		return
	_save(img, name)


func _save(img: Image, name: String) -> void:
	var path := _out_dir.path_join(name + ".png")
	if img.save_png(path) != OK:
		_fail = "save_png(%s) failed" % path
		return
	print("SHOT %s" % path)


func _finish() -> void:
	if _world != null:
		_world.teardown()
		_world.queue_free()
		_world = null
	if _fail != "":
		print("SHOTX FAIL %s" % _fail)
		quit(1)
		return
	print("SHOTX OK")
	quit(0)
