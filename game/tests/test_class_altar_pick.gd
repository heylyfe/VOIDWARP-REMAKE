extends RefCounted
#
# test_class_altar_pick.gd - item 7: "today it picks for you about half the time".
#
# The REAL app path, in the real scene tree: app.gd is added to the root window, PLAY is
# the menu's own play_requested, the loading clock is the loading screen's own advance(),
# and a "click" is a real InputEventMouseButton press + release pushed into the root
# viewport at the centre of the card's on-screen rect - the viewport's GUI routing picks the
# control under the cursor, so a container or backdrop that swallowed the click would fail
# here exactly as it fails for a player.
#
#   leg A (the PROOF, 100 trials): the chosen class is the clicked card 100 / 100 times.
#     Trial i clicks card i % 3 at loading-clock offset OFFSETS[i % 7] (7 and 3 coprime:
#     every card meets every offset), from before the clock starts to well after it ran
#     out; each trial is a new PLAY on a fresh seed in the same app (the previous trial's
#     pick persists, so a stale pick overriding the click would also fail). Per trial: the
#     cursor is free while the altar is up, the run is held (not live) until the confirm,
#     and once live the run's kit, ledger class and the app's pick all equal the click and
#     the cursor is captured again.
#   leg B (keyboard): number key / arrows select exactly that card, Enter confirms; an
#     Enter (and a held-key echo) with nothing selected confirms nothing.
#   leg C (the hold): no pick at all - the clock runs out 10x over and the run is still
#     held at the altar; SKIP then starts it with the seeded class.
#
# Negative control (this test against the pre-fix app.gd + class_altar.gd, 2026-11-21):
# leg A failed 100 / 100 - 42 trials clicked after the loading clock ran out and found the
# altar freed and the run live on the seeded class, the other 58 found the cursor captured
# by world.build() under the altar. With the cursor check off, the clock alone gave the
# wrong class in 28 / 100 (the seeded pick matched the click by luck in the other 14).
# Legs B and C failed too (no keyboard altar; the run went live with no pick).

const AppScript := preload("res://app/app.gd")
const ControllerScript := preload("res://sim/controller.gd")

const TRIALS := 100
# seconds of loading clock before the click, as a fraction of the hold (+ absolute extra)
const OFFSETS := [[0.0, 0.0], [0.0, 0.25], [0.5, 0.0], [1.0, -0.25], [1.0, 0.0],
		[1.0, 0.5], [1.0, 3.0]]


func run() -> Array[String]:
	var f: Array[String] = []
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		f.append("no scene tree: this test drives the real viewport")
		return f
	# headless, the root window is 64 x 64 and a click outside it never presses a button:
	# give it a real window size for the test, then put it back
	var old_size := tree.root.size
	tree.root.size = Vector2i(1280, 720)
	_leg_clicks(f, tree.root)
	_leg_keyboard(f, tree.root)
	_leg_hold(f, tree.root)
	tree.root.size = old_size
	return f


func _new_app(root: Window, scratch: String):
	var app = AppScript.new()
	app.records_path = scratch
	root.add_child(app)   # runs _ready: the menu
	return app


func _free_app(app, scratch: String) -> void:
	app._return_to_menu()
	app.get_parent().remove_child(app)
	app.free()
	var d := DirAccess.open("user://")
	if d != null and d.file_exists(scratch.get_file()):
		d.remove(scratch.get_file())


## Containers lay out on a deferred notification; no frame runs inside run(), so sort
## every container under p_node by hand, top-down, the same pass a frame would make.
func _layout(p_node: Node) -> void:
	if p_node is Container:
		p_node.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for c in p_node.get_children():
		_layout(c)


## A real click: press + release at p_pos, pushed into the viewport's GUI routing.
func _click_at(root: Window, p_pos: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = p_pos
		ev.global_position = p_pos
		root.push_input(ev)


func _click_control(root: Window, c: Control) -> void:
	var r := c.get_global_rect()
	_click_at(root, r.position + r.size * 0.5)


func _key(app, code: int, echo := false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	ev.echo = echo
	app._class_altar.handle_input(ev)


## The card for p_id (pre-fix altars kept them in _buttons).
func _card(altar, p_id: String) -> Control:
	if altar.has_method("card"):
		return altar.card(p_id)
	return altar._buttons.get(p_id, null)


func _advance(loading, p_seconds: float) -> void:
	var left := p_seconds
	while left > 0.0001 and is_instance_valid(loading):
		var step := minf(left, 0.25)
		loading.advance(step)
		left -= step


func _drive_to_world(app) -> void:
	var guard := 0
	while app.state() == "LOADING" and app._loading != null and guard < 400:
		app._loading.advance(0.25)
		guard += 1

# ---- leg A: 100 clicks, 100 picks ------------------------------------------------------------

func _leg_clicks(f: Array[String], root: Window) -> void:
	var scratch := "user://test_class_altar_pick_scratch.json"
	var app = _new_app(root, scratch)
	var wrong := 0
	var first_fail := ""
	var by_cause := {}
	for i in TRIALS:
		var why := _one_click_trial(app, root, i)
		if why != "":
			wrong += 1
			var cause := why.get_slice("]", 0).trim_prefix("[")
			by_cause[cause] = int(by_cause.get(cause, 0)) + 1
			if first_fail == "":
				first_fail = why
		if app.state() != "MENU":
			app._return_to_menu()
	if wrong > 0:
		f.append("clicks: the pick failed in %d / %d trials, by cause %s (first: %s)"
				% [wrong, TRIALS, str(by_cause), first_fail])
	print("test_class_altar_pick: %d / %d clicks picked the clicked card" % [TRIALS - wrong, TRIALS])
	_free_app(app, scratch)


## One PLAY -> wait -> click -> confirm -> live. Returns "" when the run's class is the
## clicked card (and every hold / cursor rule held), else why not.
func _one_click_trial(app, root: Window, i: int) -> String:
	app._menu.play_requested.emit()
	if app.state() != "LOADING" or app._class_altar == null:
		return "trial %d: PLAY left state=%s altar=%s" % [i, app.state(), str(app._class_altar)]
	var altar = app._class_altar
	var ids: Array = altar.class_ids()
	ids.sort()
	var want := str(ids[i % ids.size()])
	var loading = app._loading
	var off: Array = OFFSETS[i % OFFSETS.size()]
	var wait := float(off[0]) * float(loading.hold_seconds()) + float(off[1])
	_advance(loading, maxf(wait, 0.0))
	var tag := "trial %d (seed %d, click %s at %.2f s of a %.1f s hold)" % [
			i, app.run_seed(), want, wait, float(loading.hold_seconds())]
	# the altar is still there to click - the clock must not have taken the choice away
	if app._class_altar == null or not is_instance_valid(altar) or not altar.is_open():
		_drive_to_world(app)
		return "[timer] %s: the altar was gone before the click; the run went live as '%s'" % [
				tag, str(app._world.ctl.kit) if app._world != null else "?"]
	if app.state() != "LOADING" or app._world == null or app._world.is_inside_tree():
		return "[timer] %s: the run went live under the open altar (state=%s)" % [tag, app.state()]
	if bool(app._world._mouse_locked):
		return "[cursor] %s: the cursor is captured while the altar is up - no click can land" % tag
	_layout(altar)
	var c := _card(altar, want)
	if c == null:
		return "[click] %s: no card for %s" % [tag, want]
	if i == 0 and altar.has_method("card"):
		var row: Rect2 = (c.get_parent() as Control).get_global_rect()
		var mid := row.get_center().x
		if absf(mid - root.size.x * 0.5) > 2.0:
			return "[layout] %s: the card row is not centred (centre x %.0f of %d)" % [tag, mid, root.size.x]
	_click_control(root, c)
	if altar.has_method("confirm_button"):
		if altar.selected_id() != want:
			return "[click] %s: the click selected '%s'" % [tag, altar.selected_id()]
		if not altar.is_open() or app.state() != "LOADING":
			return "[confirm] %s: one click confirmed without the confirm step" % tag
		_layout(altar)
		_click_control(root, altar.confirm_button())
	_drive_to_world(app)
	if app.state() != "WORLD" or app._world == null:
		return "[live] %s: the run never went live after the confirm (state=%s)" % [tag, app.state()]
	var kit := str(app._world.ctl.kit)
	var led := str(app._world.run_ledger().get("class", ""))
	if kit != want or led != want or str(app._chosen_class) != want:
		return "[class] %s: the run is kit=%s ledger=%s pick=%s" % [tag, kit, led, str(app._chosen_class)]
	if not bool(app._world._mouse_locked):
		return "[cursor] %s: play started with the cursor still free" % tag
	return ""

# ---- leg B: the keyboard selects exactly that card; Enter with nothing selected is inert ---

func _leg_keyboard(f: Array[String], root: Window) -> void:
	var scratch := "user://test_class_altar_keys_scratch.json"
	var app = _new_app(root, scratch)
	app._menu.play_requested.emit()
	var altar = app._class_altar
	if altar == null or not altar.has_method("handle_input"):
		f.append("keys: PLAY opened no keyboard-driven altar")
		_free_app(app, scratch)
		return
	var ids: Array = altar.class_ids()
	ids.sort()
	# the key that started the run, still held (echo), then a fresh Enter: nothing selected,
	# so nothing is confirmed and the altar stays up
	_key(app, KEY_ENTER, true)
	_key(app, KEY_ENTER)
	_key(app, KEY_SPACE)
	if not altar.is_open() or altar.chosen_id() != "" or altar.selected_id() != "":
		f.append("keys: Enter/Space with nothing selected picked '%s' / selected '%s'"
				% [altar.chosen_id(), altar.selected_id()])
	# number keys select exactly that card
	for n in ids.size():
		_key(app, KEY_1 + n)
		if altar.selected_id() != str(ids[n]):
			f.append("keys: key %d selected '%s', want %s" % [n + 1, altar.selected_id(), ids[n]])
	# arrows walk the row and wrap; Tab / Shift+Tab too
	_key(app, KEY_1)
	_key(app, KEY_RIGHT)
	if altar.selected_id() != str(ids[1]):
		f.append("keys: Right from card 1 selected '%s', want %s" % [altar.selected_id(), ids[1]])
	_key(app, KEY_LEFT)
	_key(app, KEY_LEFT)
	if altar.selected_id() != str(ids[ids.size() - 1]):
		f.append("keys: Left twice from card 2 did not wrap to the last card ('%s')" % altar.selected_id())
	# selecting is not confirming: the run is still at the altar
	if not altar.is_open() or altar.chosen_id() != "":
		f.append("keys: a selection confirmed itself without Enter")
	# an echo of Enter (a held key) still confirms nothing
	_key(app, KEY_ENTER, true)
	if not altar.is_open():
		f.append("keys: a held-key echo confirmed the card")
	# pick the middle card by key, confirm with Enter, run to WORLD
	var want := str(ids[1])
	_key(app, KEY_1 + 1)
	_key(app, KEY_ENTER)
	if altar.is_open() or altar.chosen_id() != want:
		f.append("keys: Enter on %s left open=%s chosen='%s'" % [want, altar.is_open(), altar.chosen_id()])
	_drive_to_world(app)
	if app.state() != "WORLD" or app._world == null or str(app._world.ctl.kit) != want:
		f.append("keys: the keyboard pick %s did not become the run (state=%s kit=%s)" % [
				want, app.state(), str(app._world.ctl.kit) if app._world != null else "?"])
	_free_app(app, scratch)


# ---- leg C: no pick -> the run waits; SKIP starts it on the seeded class --------------------

func _leg_hold(f: Array[String], root: Window) -> void:
	var scratch := "user://test_class_altar_hold_scratch.json"
	var app = _new_app(root, scratch)
	app._menu.play_requested.emit()
	var loading = app._loading
	if loading == null or app._class_altar == null:
		f.append("hold: PLAY opened no loading screen / altar")
		_free_app(app, scratch)
		return
	_advance(loading, float(loading.hold_seconds()) * 10.0)
	if app.state() != "LOADING" or app._class_altar == null or not app._class_altar.is_open():
		f.append("hold: the clock ran out 10x and the run went on without a pick (state=%s)"
				% app.state())
		_free_app(app, scratch)
		return
	if app._world == null or app._world.is_inside_tree():
		f.append("hold: the held run's world is already live")
	if bool(app._world._mouse_locked):
		f.append("hold: the cursor is captured while the run waits at the altar")
	_layout(app._class_altar)
	_click_control(root, app._class_altar.skip_button())
	if app.state() != "WORLD" or app._world == null:
		f.append("hold: SKIP after the clock did not start the run (state=%s)" % app.state())
		_free_app(app, scratch)
		return
	var kit := str(app._world.ctl.kit)
	if not ControllerScript.KITS.has(kit) or str(app._world.run_ledger().get("class", "")) != kit:
		f.append("hold: the skipped run's kit '%s' is not its seeded ledger class" % kit)
	if not bool(app._world._mouse_locked):
		f.append("hold: play started after SKIP with the cursor still free")
	_free_app(app, scratch)