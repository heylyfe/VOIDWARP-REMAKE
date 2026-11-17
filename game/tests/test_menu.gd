extends RefCounted
#
# Main menu (ticket MENU): keyboard navigation, confirm, the HOW TO PLAY panel, the version tag,
# the disclaimer footer and the roster backdrop - headless, no scene tree (run_all.gd calls run()
# from its _init). Every key comes from data/bindings.json, the same file the play capture reads,
# so the test proves the menu speaks the game's mapping, not a hardcoded one.

const MenuScript := preload("res://app/menu.gd")
const StageScript := preload("res://app/menu_stage.gd")
const HowToScript := preload("res://app/menu_howto.gd")
const InputCaptureScript := preload("res://app/input_capture.gd")
const BillboardScript := preload("res://view/billboard.gd")

const MAIN_SCENE := "res://app/main.tscn"


func run() -> Array[String]:
	var f: Array[String] = []
	var b: Dictionary = InputCaptureScript.load_bindings()
	if not (b["errors"] as Array).is_empty():
		f.append("bindings: data/bindings.json failed to load: %s" % str(b["errors"]))
		return f
	_test_scene_loads(f)
	var m = MenuScript.new()
	_test_entries(f, m)
	_test_navigation(f, m, b)
	_test_confirm_play(f, m, b)
	_test_howto(f, m, b)
	_test_quit(f, m, b)
	_test_feedback(f, m, b)
	_test_version_and_disclaimer(f, m)
	_test_roster(f, m)
	_test_bot_path(f, b)
	m.free()
	_test_howto_text(f, b)
	return f


func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func _first(b: Dictionary, action: String) -> int:
	var keys: Array = b["key_bindings"].get(action, [])
	return int(keys[0]) if not keys.is_empty() else KEY_NONE


func _test_scene_loads(f: Array[String]) -> void:
	var ps: PackedScene = load(MAIN_SCENE)
	if ps == null:
		f.append("scene: %s does not load" % MAIN_SCENE)
		return
	var root: Node = ps.instantiate()
	if root == null or root.get_script() != MenuScript:
		f.append("scene: %s root is not app/menu.gd" % MAIN_SCENE)
	if root != null:
		root.free()


func _test_entries(f: Array[String], m) -> void:
	if MenuScript.MENU_ENTRIES != ["PLAY", "HOW TO PLAY", "QUIT"]:
		f.append("entries: MENU_ENTRIES is %s" % str(MenuScript.MENU_ENTRIES))
	var buttons: Array = m.entry_buttons()
	if buttons.size() != MenuScript.MENU_ENTRIES.size():
		f.append("entries: %d buttons for %d entries" % [buttons.size(), MenuScript.MENU_ENTRIES.size()])
		return
	for i in buttons.size():
		if (buttons[i] as Button).text != str(MenuScript.MENU_ENTRIES[i]):
			f.append("entries: button %d reads '%s'" % [i, (buttons[i] as Button).text])
		if (buttons[i] as Button).focus_mode != Control.FOCUS_NONE:
			f.append("entries: button %d takes keyboard focus (ui_accept would double-fire)" % i)
	if m.selected_index() != MenuScript.ENTRY_PLAY:
		f.append("entries: the menu opens on %d, want PLAY" % m.selected_index())


func _test_navigation(f: Array[String], m, b: Dictionary) -> void:
	var down := _first(b, "move_back")
	var up := _first(b, "move_forward")
	var want_down := [1, 2, 0]           # wraps past QUIT to PLAY
	for w in want_down:
		if not m.handle_input(_key(down)):
			f.append("nav: move_back key not consumed")
		if m.selected_index() != int(w):
			f.append("nav: move_back -> %d, want %d" % [m.selected_index(), int(w)])
	var want_up := [2, 1, 0]             # wraps past PLAY to QUIT
	for w in want_up:
		m.handle_input(_key(up))
		if m.selected_index() != int(w):
			f.append("nav: move_forward -> %d, want %d" % [m.selected_index(), int(w)])
	# a key the bindings do not give the menu is not consumed
	if m.handle_input(_key(KEY_K)):
		f.append("nav: an unbound key was consumed")
	# held-key repeat (echo) still steps, so holding the key scrolls
	var echo := _key(down)
	echo.echo = true
	m.handle_input(echo)
	if m.selected_index() != 1:
		f.append("nav: echo of move_back did not step")
	m.handle_input(_key(up))
	# gamepad: the left stick (the game's move axis) steps once per push
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_Y
	stick.axis_value = 0.9
	m.handle_input(stick)
	m.handle_input(stick)                # still held: no second step
	if m.selected_index() != 1:
		f.append("nav: stick push -> %d, want 1 (one step per push)" % m.selected_index())
	stick.axis_value = 0.0
	m.handle_input(stick)
	stick.axis_value = -0.9
	m.handle_input(stick)
	if m.selected_index() != 0:
		f.append("nav: stick back -> %d, want 0" % m.selected_index())


func _test_confirm_play(f: Array[String], m, b: Dictionary) -> void:
	var played := [0]
	var cb := func() -> void: played[0] += 1
	m.play_requested.connect(cb)
	m.activate(MenuScript.ENTRY_PLAY)
	played[0] = 0
	if not m.handle_input(_key(_first(b, "jump"))):
		f.append("confirm: the jump key was not consumed")
	if played[0] != 1:
		f.append("confirm: jump on PLAY emitted play_requested %d times, want 1" % played[0])
	m.handle_input(_key(_first(b, "interact")))
	if played[0] != 2:
		f.append("confirm: interact on PLAY did not emit play_requested")
	# Enter is not the game's confirm: it must do nothing
	if m.handle_input(_key(KEY_ENTER)) or played[0] != 2:
		f.append("confirm: Enter activated the menu (confirm must be the jump/interact binding)")
	# a released key and a held repeat never confirm
	var rel := _key(_first(b, "jump"))
	rel.pressed = false
	m.handle_input(rel)
	var echo := _key(_first(b, "jump"))
	echo.echo = true
	m.handle_input(echo)
	if played[0] != 2:
		f.append("confirm: a release or key repeat confirmed")
	# the bound gamepad buttons confirm too
	var pad := InputEventJoypadButton.new()
	pad.button_index = int(b["joy_bindings"]["jump"]) as JoyButton
	pad.pressed = true
	m.handle_input(pad)
	if played[0] != 3:
		f.append("confirm: the bound gamepad jump button did not confirm")
	m.play_requested.disconnect(cb)


func _test_howto(f: Array[String], m, b: Dictionary) -> void:
	var played := [0]
	var cb := func() -> void: played[0] += 1
	m.play_requested.connect(cb)
	m.handle_input(_key(_first(b, "move_back")))            # PLAY -> HOW TO PLAY
	if m.selected_index() != MenuScript.ENTRY_HOWTO:
		f.append("howto: could not select HOW TO PLAY")
	m.handle_input(_key(_first(b, "jump")))
	if not m.is_howto_open():
		f.append("howto: confirm on HOW TO PLAY did not open the panel")
	m.tick_ui(1.0)
	var panel: Control = m.get_node("HowToPanel")
	if not panel.visible:
		f.append("howto: the panel is open but not visible")
	var text: RichTextLabel = m.get_node("HowToPanel/Body/HowToText")
	if text.get_parsed_text().find("VOID CHARGES") < 0:
		f.append("howto: the panel does not show the void charges section")
	# while open, navigation scrolls the panel and never moves the menu selection or plays
	m.handle_input(_key(_first(b, "move_back")))
	m.handle_input(_key(_first(b, "move_back")))
	if m.selected_index() != MenuScript.ENTRY_HOWTO:
		f.append("howto: navigation leaked through the open panel")
	m.handle_input(_key(_first(b, "jump")))                # confirm closes
	if m.is_howto_open():
		f.append("howto: confirm did not close the panel")
	m.tick_ui(1.0)
	if panel.visible:
		f.append("howto: the closed panel is still visible after its fade")
	if played[0] != 0:
		f.append("howto: opening/closing the panel emitted play_requested")
	m.handle_input(_key(_first(b, "interact")))            # reopen
	m.handle_input(_key(_first(b, "pause")))               # pause backs out
	if m.is_howto_open():
		f.append("howto: the pause key did not close the panel")
	m.tick_ui(1.0)
	m.play_requested.disconnect(cb)


func _test_quit(f: Array[String], m, b: Dictionary) -> void:
	var quits := [0]
	var cb := func() -> void: quits[0] += 1
	m.quit_requested.connect(cb)
	m.handle_input(_key(_first(b, "move_back")))            # HOW TO PLAY -> QUIT
	if m.selected_index() != MenuScript.ENTRY_QUIT:
		f.append("quit: could not select QUIT (at %d)" % m.selected_index())
	m.handle_input(_key(_first(b, "jump")))
	if quits[0] != 1:
		f.append("quit: confirm on QUIT emitted quit_requested %d times" % quits[0])
	m.quit_requested.disconnect(cb)
	m.handle_input(_key(_first(b, "move_back")))            # back to PLAY (wrap)


func _test_feedback(f: Array[String], m, b: Dictionary) -> void:
	m.handle_input(_key(_first(b, "move_back")))            # PLAY -> HOW TO PLAY
	m.tick_ui(1.0)
	var buttons: Array = m.entry_buttons()
	for i in buttons.size():
		var btn: Button = buttons[i]
		var col: Color = btn.get_theme_color("font_color")
		var sb := btn.get_theme_stylebox("normal") as StyleBoxFlat
		if i == m.selected_index():
			if not col.is_equal_approx(MenuScript.C_GOLD):
				f.append("feedback: the selected entry is not gold (%s)" % str(col))
			if sb == null or sb.border_width_left <= 0:
				f.append("feedback: the selected entry has no selection bar")
		else:
			if not col.is_equal_approx(MenuScript.C_MUTED):
				f.append("feedback: unselected entry %d is not muted (%s)" % [i, str(col)])
			if sb != null and sb.border_width_left != 0:
				f.append("feedback: unselected entry %d shows a selection bar" % i)
	var hint: Label = m.get_node("MenuColumn/EntryHint")
	if hint.text != str(MenuScript.ENTRY_HINTS[m.selected_index()]):
		f.append("feedback: the entry hint does not follow the selection")
	var keys: RichTextLabel = m.get_node("MenuColumn/KeysHint")
	var plain := keys.get_parsed_text()
	for action in ["move_forward", "move_back", "jump", "interact"]:
		var name := HowToScript.keys_for(b, action)
		if plain.find(name) < 0:
			f.append("feedback: the key hint does not name the %s binding (%s)" % [action, name])
	m.handle_input(_key(_first(b, "move_forward")))         # back to PLAY


func _test_version_and_disclaimer(f: Array[String], m) -> void:
	var v: Label = m.version_label()
	if v == null or v.text.strip_edges() == "" or v.text != MenuScript.VERSION_TAG:
		f.append("version: the version tag is missing")
	if not str(MenuScript.VERSION_TAG).begins_with("v"):
		f.append("version: VERSION_TAG '%s' is not a v-tag" % MenuScript.VERSION_TAG)
	var d: Label = m.disclaimer_label()
	if d == null or not d.text.contains(MenuScript.ABOUT_DISCLAIMER):
		f.append("disclaimer: the footer does not carry ABOUT_DISCLAIMER verbatim")
	if not MenuScript.about_text().contains(MenuScript.ABOUT_DISCLAIMER):
		f.append("disclaimer: about_text() lost the disclaimer")


func _test_roster(f: Array[String], m) -> void:
	var stage = m.stage
	if stage == null:
		f.append("roster: the menu has no stage")
		return
	var found: Array = StageScript.discover_roster()
	if found.size() < 12:
		f.append("roster: only %d enemies discovered, want the 12-strong roster" % found.size())
	var sprites: Array = stage.roster_billboards()
	if sprites.size() != found.size():
		f.append("roster: %d billboards for %d enemies" % [sprites.size(), found.size()])
	var ids: Array = stage.roster_ids()
	for i in sprites.size():
		var s: Sprite3D = sprites[i]
		var id := str(ids[i])
		if s.texture == null:
			f.append("roster: %s has no texture" % id)
			continue
		var path := s.texture.resource_path
		if not path.begins_with("res://content/enemies/%s/sprites/" % id) or not path.ends_with(".png"):
			f.append("roster: %s shows '%s', not its own sprite PNG" % [id, path])
		for bad in ["attack", "telegraph", "launch", "dash", "fire_", "shoot"]:
			if path.get_file().contains(bad):
				f.append("roster: %s poses with a '%s' frame (%s), want its idle" % [id, bad, path.get_file()])
		if s.texture.get_width() <= 0 or s.texture.get_height() <= 0:
			f.append("roster: %s texture is empty" % id)
		if s.scale.x <= 0.0:
			f.append("roster: %s billboard has zero scale" % id)
		# the visible body stands on its platform (not sunk into it, not floating)
		var bb: float = StageScript.body_bottom(s)
		if absf(bb) > 0.03:
			f.append("roster: %s body bottom sits %.3f u off its platform" % [id, bb])
	# stable layout: same input -> same slots; no two enemies share a slot
	var a: Array = StageScript.layout(found)
	var c: Array = StageScript.layout(found)
	var seen := {}
	for i in a.size():
		var pa: Vector3 = a[i]["pos"]
		if not pa.is_equal_approx(c[i]["pos"]) or str(a[i]["entry"]["id"]) != str(c[i]["entry"]["id"]):
			f.append("roster: the layout is not stable")
			break
		var key := "%.2f,%.2f" % [pa.x, pa.z]
		if seen.has(key):
			f.append("roster: two enemies share slot %s" % key)
		seen[key] = true
	# the stage clock moves the camera and cycles the danger-line caption
	var t0: Transform3D = stage.camera.transform
	stage.advance(5.0)
	if stage.camera.transform.origin.is_equal_approx(t0.origin):
		f.append("roster: the camera does not drift")
	if stage.caption_index() < 0:
		f.append("roster: no roster caption is showing")
	# after the clock moved (frames changed), every body still stands on its platform
	for i in sprites.size():
		var bb2: float = StageScript.body_bottom(sprites[i])
		if absf(bb2) > 0.03:
			f.append("roster: %s drifts %.3f u off its platform once animating" % [str(ids[i]), bb2])
	_test_photo_cards(f, stage)


## D-MENU-10: a pose frame that is a full opaque rectangle (a photo keeping its background) stands
## in a doorway, graded; a cut-out never does. Detection is from pixels, so it is checked on
## synthetic textures first, then for consistency over the real roster.
func _test_photo_cards(f: Array[String], stage) -> void:
	var solid := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	solid.fill(Color(0.8, 0.8, 0.8, 1.0))
	var cut := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	cut.fill(Color(0, 0, 0, 0))
	cut.fill_rect(Rect2i(16, 8, 32, 48), Color(1, 1, 1, 1))
	for tc in [[solid, true, "a fully opaque frame"], [cut, false, "a cut-out frame"]]:
		var s: Sprite3D = BillboardScript.new()
		s.texture = ImageTexture.create_from_image(tc[0])
		s.anims["t"] = {"frames": [s.texture], "fps": 1.0, "loop": true, "body_rect": [[0, 0, 64, 64]]}
		s.anim_name = "t"
		if StageScript.is_photo_card(s) != bool(tc[1]):
			f.append("cards: %s detected as photo card = %s, want %s (coverage %.3f)" % [tc[2],
					str(StageScript.is_photo_card(s)), str(tc[1]), StageScript.opaque_coverage(s)])
		s.free()
	var cards := 0
	for r in stage.roster:
		var s: Sprite3D = r["sprite"]
		var id := str(r["id"])
		var card: Variant = r.get("card", null)
		var want: bool = (not bool(r["flying"])) and StageScript.is_photo_card(s)
		if want != (card is Node3D):
			f.append("cards: %s photo card %s but doorway %s" % [id, str(want), str(card is Node3D)])
			continue
		if not want:
			if s.modulate != Color(1, 1, 1, 1):
				f.append("cards: cut-out %s is graded (%s); only photo cards are" % [id, str(s.modulate)])
			continue
		cards += 1
		if s.modulate != StageScript.CARD_GRADE:
			f.append("cards: photo card %s is not graded" % id)
		var rect: Rect2 = StageScript.card_rect(s)
		if rect.size.x <= 0.0 or absf(rect.position.y) > 0.03:
			f.append("cards: photo card %s rect %s does not stand on its platform" % [id, str(rect)])
		if absf(wrapf((card as Node3D).rotation.y - s.rotation.y, -PI, PI)) > 1e-4:
			f.append("cards: %s doorway faces %.4f, its photo %.4f" % [id, (card as Node3D).rotation.y, s.rotation.y])
		var vig: Node = (card as Node3D).get_node_or_null("Vignette")
		if vig == null:
			f.append("cards: %s doorway has no inner shadow" % id)
	if cards > 0:
		# the doorway turns with its photo as the camera sways
		stage.advance(9.0)
		for r in stage.roster:
			var card2: Variant = r.get("card", null)
			if card2 is Node3D:
				var s2: Sprite3D = r["sprite"]
				if absf(wrapf((card2 as Node3D).rotation.y - s2.rotation.y, -PI, PI)) > 1e-4:
					f.append("cards: %s doorway lags its photo after the camera moved" % str(r["id"]))


## The bot's path: a fresh menu, keyboard only, ends in play_requested (the orchestrator then
## runs level 1 - APP-FLOW's app.gd; this proves everything up to that seam).
func _test_bot_path(f: Array[String], b: Dictionary) -> void:
	var m = MenuScript.new()
	var played := [0]
	m.play_requested.connect(func() -> void: played[0] += 1)
	for i in 3:
		m.handle_input(_key(_first(b, "move_back")))        # a full lap: back on PLAY
	m.handle_input(_key(_first(b, "jump")))
	if played[0] != 1:
		f.append("bot: a keyboard-only lap + confirm did not emit play_requested")
	m.free()


func _test_howto_text(f: Array[String], b: Dictionary) -> void:
	var t: String = HowToScript.plain_text(b)
	var facts: Dictionary = HowToScript.facts()
	var must := [
		"%d void charges" % int(facts["charges_start"]),
		"restores 1 charge",
		"0 charges",
		"kill on contact - instantly",
		"opens the beacon",
		"Last Light",
	]
	for s in must:
		if t.find(str(s)) < 0:
			f.append("howto text: missing '%s'" % str(s))
	if int(facts["charges_start"]) != 2 or int(facts["charge_cap"]) != 2:
		f.append("howto text: charges read %d/%d from the controller, the shipped value is 2/2" % [int(facts["charges_start"]), int(facts["charge_cap"])])
	if t.find("{h}") >= 0 or t.find("%s") >= 0 or t.find("%d") >= 0:
		f.append("howto text: an unformatted placeholder leaked")
