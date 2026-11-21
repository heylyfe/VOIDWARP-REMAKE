extends RefCounted
#
# test_death_master.gd - item 12: the death screen hosted by The Master, through the REAL
# app path. The app is added to the root window, PLAY goes through the menu signal and the
# class altar (SKIP), the run goes live, the player dies through the sim (a real void fall;
# the controller's own _die() for an enemy, a mine and a curse - the store every killing
# blow writes), world.gd emits run_over, the HUD's black-out runs, and the app opens the
# run-over screen. Keys and clicks are real InputEvents pushed into the root viewport, so
# focus navigation, ui_accept and click routing are the engine's own.
#
# Per death kind (enemy, mine, void, curse):
#   - The Master is on screen (the owner's cat image is the texture);
#   - his line names the right killer (the enemy's / mine's roster name, "void", the
#     curse's display name) and the killer resolution (name + code) is unchanged;
#   - an enemy / mine death shows that enemy's own sprite;
#   - the cursor is free (the world's capture state);
#   - RESTART and BACK TO LOBBY both exist; RESTART has focus; Right / Left / Tab /
#     Shift+Tab move focus between the two; Enter / Space / a click activate them, and
#     each one lands where it says (RESTART -> a new run; BACK TO LOBBY -> the menu).
#
#   - the screen draws on a canvas layer strictly above the dead world's black-out and
#     every other world CanvasLayer (the 78fc9e4 regression, caught by shot_death.gd).
#
# Negative control: this test against the pre-item-12 run_over.gd (see the report).

const AppScript := preload("res://app/app.gd")
const ScreenFxScript := preload("res://view/hud/screen_fx.gd")
const RunOverScript := preload("res://view/hud/run_over.gd")

const DT := 1.0 / 60.0

# [tag, code, the name the line must contain, how to leave the screen]
const CASES := [
	["enemy", "D-SEAL", "seal", "keys_restart_enter"],
	["mine", "D-MINE", "gift Larper", "click_lobby"],
	["void", "D-VOID", "void", "keys_lobby_enter"],
	["curse", "D-CURSE:brittle", "Brittle", "keys_restart_space"],
]


func run() -> Array[String]:
	var f: Array[String] = []
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		f.append("no scene tree: this test drives the real viewport")
		return f
	var old_size := tree.root.size
	tree.root.size = Vector2i(1280, 720)
	for c in CASES:
		_case(f, tree.root, c)
	tree.root.size = old_size
	return f


func _key(root: Window, code: int, shift := false) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.shift_pressed = shift
		ev.pressed = pressed
		root.push_input(ev)


func _click(root: Window, c: Control) -> void:
	var p := c.get_global_rect().get_center()
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = p
		ev.global_position = p
		root.push_input(ev)


func _layout(p_node: Node) -> void:
	if p_node is Container:
		p_node.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for c in p_node.get_children():
		_layout(c)


func _focus(root: Window) -> Control:
	return root.gui_get_focus_owner()


## PLAY -> SKIP at the altar -> WORLD -> the given death -> RUN_OVER with the screen up.
func _die_into_run_over(f: Array[String], app, tag: String, code: String) -> bool:
	app._menu.play_requested.emit()
	if app._class_altar != null and app._class_altar.is_open():
		app._class_altar.skip()
	var guard := 0
	while app.state() == "LOADING" and app._loading != null and guard < 400:
		app._loading.advance(0.25)
		guard += 1
	if app.state() != "WORLD" or app._world == null:
		f.append("%s: the run never went live (state=%s)" % [tag, app.state()])
		return false
	var world = app._world
	var ctl = world.ctl
	ctl.charges = 0
	ctl.respawn_t = -1.0
	ctl.invuln = 0.0
	if code == "D-VOID":
		ctl.x = -500.0   # over the void, past the kill plane: the sim's own void fall
		ctl.y = -41.0
		ctl.z = 0.0
		ctl.vy = -1.0
		ctl.grounded = false
	else:
		ctl._die(code, "", [])   # the controller's killing-blow store
	world.step(DT)
	if app.state() != "RUN_OVER":
		f.append("%s: state %s after the death, want RUN_OVER" % [tag, app.state()])
		return false
	world.hud.screen_fx.advance(ScreenFxScript.BLACKOUT_TICKS)
	if app._run_over == null or not app._run_over.visible:
		f.append("%s: no run-over screen after the black-out" % tag)
		return false
	_check_layer(f, app, tag)
	return true


## The canvas layer a CanvasItem actually draws on: its nearest CanvasLayer ancestor's
## layer, or 0 (the viewport's default canvas) when it has none.
static func _effective_layer(p_node: Node) -> int:
	var n := p_node.get_parent()
	while n != null:
		if n is CanvasLayer:
			return (n as CanvasLayer).layer
		n = n.get_parent()
	return 0


static func _canvas_layers(p_node: Node, p_out: Array) -> void:
	for c in p_node.get_children():
		if c is CanvasLayer:
			p_out.append(c)
		_canvas_layers(c, p_out)


## The 78fc9e4 regression: the run-over screen was a Control parented straight to the app
## (canvas layer 0) while the dead world's HUD sits on a CanvasLayer (layer 1) with its
## black-out still up, so the player saw black instead of The Master. The screen must draw
## STRICTLY above the black-out and above every canvas layer the dead world still owns
## (equal layers fall back to tree order, which is not a contract).
func _check_layer(f: Array[String], app, tag: String) -> void:
	var mine := _effective_layer(app._run_over)
	var world = app._world
	if world == null or not is_instance_valid(world):
		f.append("%s: the dead world is gone, so the layer check proves nothing" % tag)
		return
	var fx_layer := _effective_layer(world.hud.screen_fx)
	if fx_layer < 1:
		f.append("%s: the world's black-out draws on layer %d - the HUD layout changed, "
				% [tag, fx_layer] + "re-check this guard")
	if mine <= fx_layer:
		f.append("%s: the run-over screen draws on canvas layer %d, not above the black-out's %d"
				% [tag, mine, fx_layer])
	var layers: Array = []
	_canvas_layers(world, layers)
	for cl in layers:
		if (cl as CanvasLayer).visible and mine <= (cl as CanvasLayer).layer:
			f.append("%s: the run-over screen (layer %d) is not above the world's %s (layer %d)"
					% [tag, mine, (cl as Node).name, (cl as CanvasLayer).layer])

func _case(f: Array[String], root: Window, c: Array) -> void:
	var tag := str(c[0])
	var code := str(c[1])
	var want_name := str(c[2])
	var leave := str(c[3])
	var scratch := "user://test_death_master_%s_scratch.json" % tag
	var app = AppScript.new()
	app.records_path = scratch
	root.add_child(app)
	if _die_into_run_over(f, app, tag, code):
		_check_screen(f, root, app, tag, code, want_name, leave)
	if is_instance_valid(app):
		app._return_to_menu()
		root.remove_child(app)
		app.free()
	var d := DirAccess.open("user://")
	if d != null and d.file_exists(scratch.get_file()):
		d.remove(scratch.get_file())


func _check_screen(f: Array[String], root: Window, app, tag: String, code: String,
		want_name: String, leave: String) -> void:
	var ro = app._run_over
	var world = app._world
	# --- the content ---
	if str(ro.code) != code:
		f.append("%s: the screen shows code '%s', want %s" % [tag, str(ro.code), code])
	var want_killer := RunOverScript.killer_name(code, str(app._death_info.get("killer", "")))
	if str(ro.killer_text) != want_killer:
		f.append("%s: killer line '%s' != the documented resolution '%s'"
				% [tag, str(ro.killer_text), want_killer])
	if not ro.has_method("master_texture") or ro.master_texture() == null:
		f.append("%s: The Master is not on the screen" % tag)
	var voice := str(ro.get("voice_text")) if ro.get("voice_text") != null else ""
	if voice == "" or not voice.to_lower().contains(want_name.to_lower()):
		f.append("%s: The Master's line '%s' does not name the killer '%s'" % [tag, voice, want_name])
	if tag == "enemy" or tag == "mine":
		if not ro.has_method("killer_texture") or ro.killer_texture() == null:
			f.append("%s: no killer sprite for %s" % [tag, code])
	if world != null and bool(world._mouse_locked):
		f.append("%s: the cursor is still captured on the death screen" % tag)
	# --- the two buttons, by keyboard ---
	var restart: Button = ro.restart_button() if ro.has_method("restart_button") else null
	var lobby: Button = ro.lobby_button() if ro.has_method("lobby_button") else null
	if restart == null or lobby == null:
		f.append("%s: the screen lacks RESTART (%s) / BACK TO LOBBY (%s)" % [tag, str(restart), str(lobby)])
		return
	if restart.text != "RESTART" or lobby.text != "BACK TO LOBBY":
		f.append("%s: the buttons read '%s' / '%s'" % [tag, restart.text, lobby.text])
	if not restart.is_visible_in_tree() or not lobby.is_visible_in_tree():
		f.append("%s: a button is not visible" % tag)
	if _focus(root) != restart:
		f.append("%s: RESTART does not hold focus when the screen opens (%s)" % [tag, str(_focus(root))])
		restart.grab_focus()
	_key(root, KEY_RIGHT)
	if _focus(root) != lobby:
		f.append("%s: Right from RESTART did not reach BACK TO LOBBY" % tag)
	_key(root, KEY_LEFT)
	if _focus(root) != restart:
		f.append("%s: Left from BACK TO LOBBY did not reach RESTART" % tag)
	_key(root, KEY_TAB)
	if _focus(root) != lobby:
		f.append("%s: Tab from RESTART did not reach BACK TO LOBBY" % tag)
	_key(root, KEY_TAB, true)
	if _focus(root) != restart:
		f.append("%s: Shift+Tab from BACK TO LOBBY did not reach RESTART" % tag)
	_key(root, KEY_DOWN)
	if _focus(root) != lobby:
		f.append("%s: Down from RESTART did not reach BACK TO LOBBY" % tag)
	_key(root, KEY_UP)
	if _focus(root) != restart:
		f.append("%s: Up from BACK TO LOBBY did not reach RESTART" % tag)
	# --- leave the screen the way this case says, and land where the button says ---
	match leave:
		"keys_restart_enter":
			_key(root, KEY_ENTER)
		"keys_restart_space":
			_key(root, KEY_SPACE)
		"keys_lobby_enter":
			_key(root, KEY_RIGHT)
			_key(root, KEY_ENTER)
		"click_lobby":
			_layout(ro)
			_click(root, lobby)
	var to_lobby := leave.contains("lobby")
	if to_lobby:
		if app.state() != "MENU" or app._run_over != null or app._world != null:
			f.append("%s: BACK TO LOBBY (%s) left state=%s run_over=%s world=%s, want the menu"
					% [tag, leave, app.state(), str(app._run_over), str(app._world)])
		elif not app._menu.visible:
			f.append("%s: BACK TO LOBBY did not show the menu" % tag)
	else:
		if app.state() != "LOADING" and app.state() != "WORLD":
			f.append("%s: RESTART (%s) left state=%s, want a new run" % [tag, leave, app.state()])
		if app._run_over != null:
			f.append("%s: RESTART left the death screen up" % tag)