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
#   D-GUI-1 (the reference-panel rebuild):
#        <out_dir>/hud_03_black_phase.png  (no curses: the gift counter + CTRL hint)
#        <out_dir>/hud_04_gold_phase.png   (every black gift taken, 3 gold: the gold counter)
#        <out_dir>/hud_05_collapse.png     (beacon open, the first ring cracking: the
#                                           collapse warning under the full icon rows)
#        <out_dir>/hud_06_full_1080.png    (hud_01's ledger at 1920x1080)
#        <out_dir>/hud_07_bottom_zoom.png  (hud_04's bottom-centre counter + hint, 2x)
# Every shot also checks the REAL laid-out panel rects (hud.panel_elements(), global
# rects after the engine's own layout pass): inside the window, no two visible overlap.
# Prints a DIAG line per shot: the counter's cells, which ones carry real sprite art, their
# badges, and the on-screen rects of the counter, the icon rows and the purse, with an
# overlap check. Named shot_*, not test_*, so tests/run_all.gd skips it. Prints
# "SHOT <path>" per PNG and "SHOTX OK" / "SHOTX FAIL <why>"; exit 1 on failure.

const WorldScript := preload("res://app/world.gd")
const CollapseScript := preload("res://sim/collapse.gd")

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
	if not await _capture("hud_01_full", full):
		_finish()
		return
	await _d_gui_shots(full)
	_finish()


func _capture(name: String, ledger: Dictionary) -> bool:
	if not await _boot(name, ledger):
		return false
	await process_frame
	await process_frame
	_diag(name, ledger)
	await _shot(name)
	return _fail == ""


## Build the real world on the ledger and run it until enemies are on the field.
func _boot(name: String, ledger: Dictionary) -> bool:
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
	return true


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
	_panel_check(tag)
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


# ---- D-GUI-1 shots ----------------------------------------------------------------

## The real laid-out panels (global rects after the engine's layout pass): inside the
## window, and no two visible ones overlapping. Prints every rect.
func _panel_check(tag: String) -> void:
	var vp := Rect2(Vector2.ZERO, Vector2(root.size))
	var shown: Array = []
	var parts: PackedStringArray = []
	var panels: Dictionary = _world.hud.panel_elements()
	for key in panels:
		var c: Control = panels[key]
		if not c.is_visible_in_tree():
			continue
		var r := c.get_global_rect()
		parts.append("%s=(%d,%d %dx%d)" % [key, r.position.x, r.position.y, r.size.x, r.size.y])
		if not vp.encloses(r):
			_fail = "%s: %s %s leaves the %s window" % [tag, key, str(r), str(vp.size)]
		for other in shown:
			if r.intersects(other[1]):
				_fail = "%s: %s %s overlaps %s %s" % [tag, key, str(r), other[0], str(other[1])]
		shown.append([key, r])
	print("DIAG %s panels %s" % [tag, " ".join(parts)])


func _d_gui_shots(full: Dictionary) -> void:
	var plain := {"class": "dasher", "purse": 500, "tithes": 0, "hunger": 0, "last_vote": "",
			"votes": {"kiwi_cat": 1}, "curses": {}, "stacks": {}}
	if not await _capture("hud_03_black_phase", plain):
		return
	var hud = _world.hud
	print("DIAG hud_03_black_phase gift='%s' gift_vis=%s gold_vis=%s hint='%s'" % [
			hud.gift_counter.counter_text(), str(hud.gift_counter.visible),
			str(hud.gold_counter.visible), hud.mouse_hint.hint_text()])
	if hud.gold_counter.visible or not hud.gift_counter.visible:
		_fail = "hud_03: the black phase shows the gold counter"
		return
	# gold phase: take every black gift through the sim, then three gold ones
	if not await _boot("hud_04_gold_phase", TYPICAL.duplicate(true)):
		return
	var g: RefCounted = _world.lstate.gifts
	for i in g.slots.size():
		if g.is_real(i) and not g.collected(i):
			g.collect(i, int(_world.lstate.tick), 0, [])
	var took := 0
	for i in g.slots.size():
		if took < 3 and g.present(i):
			g.collect(i, int(_world.lstate.tick), 0, [])
			took += 1
	_world.ctl.invuln = 1.0
	_world.step(DT)
	await process_frame
	await process_frame
	hud = _world.hud
	print("DIAG hud_04_gold_phase phase=%s gold='%s' gold_vis=%s gift_vis=%s" % [
			g.phase, hud.gold_counter.counter_text(), str(hud.gold_counter.visible),
			str(hud.gift_counter.visible)])
	if not hud.gold_counter.visible or hud.gift_counter.visible \
			or hud.gold_counter.counter_text() != "3 / %d" % int(g.total_real):
		_fail = "hud_04: the gold counter is not up at 3 / %d" % int(g.total_real)
		return
	_diag("hud_04_gold_phase", TYPICAL)
	await _shot("hud_04_gold_phase")
	var img: Image = root.get_texture().get_image()
	var sz := root.size
	var crop := img.get_region(Rect2i(sz.x / 2 - 200, sz.y - 110, 400, 110))
	crop.resize(800, 220, Image.INTERPOLATE_NEAREST)
	_save(crop, "hud_07_bottom_zoom")
	# collapse: the full icon rows, the beacon open, the first ring cracking
	if not await _boot("hud_05_collapse", full):
		return
	# as in play: the last black gift flips the phase, then the beacon opens
	g = _world.lstate.gifts
	for i in g.slots.size():
		if g.is_real(i) and not g.collected(i):
			g.collect(i, int(_world.lstate.tick), 0, [])
	_world.lstate.beacon.open(int(_world.lstate.tick))
	_world.step(DT)
	var st: Dictionary = _world._collapse
	var target := CollapseScript.zone_crack_tick(st, 0) + int(st["crack_ticks"]) / 2
	while int(_world.lstate.tick) < target:
		_world.ctl.invuln = 1.0
		_world.step(DT)
	await process_frame
	await process_frame
	hud = _world.hud
	print("DIAG hud_05_collapse warning='%s' vis=%s" % [hud.collapse_warning.warning_text(),
			str(hud.collapse_warning.visible)])
	if not hud.collapse_warning.visible:
		_fail = "hud_05: the collapse warning is not up"
		return
	_diag("hud_05_collapse", full)
	await _shot("hud_05_collapse")
	# the same full ledger at 1920x1080
	root.size = Vector2i(1920, 1080)
	await process_frame
	await _capture("hud_06_full_1080", full)
	root.size = SHOT_SIZE
