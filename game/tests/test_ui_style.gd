extends RefCounted
#
# test_ui_style.gd (D-GUI-1): the front-end screens share one style (view/ui_style.gd) and
# one keyboard focus (view/ui_focus.gd). For every screen - main menu (and its HOW TO PLAY
# panel), class altar, pause overlay, settings, lobby purse HUD, loading screen - with the
# longest real strings loaded (a 3-digit level, a 6-digit purse, the longest class name with
# its "(last)" mark, every loading tip, the slider extremes):
#   1. FIT      every Label / Button text fits its own rect with >= 4 px on each side, and
#               sits inside its panel (or the 1280x720 screen when it has none);
#   2. HEIGHT   every visible interactive control (BaseButton, Range) is >= 32 px tall;
#   3. RING     after Tab, the focused control wears the focus ring and no other does;
#   4. TAB      Tab reaches every interactive control and wraps to the first; Shift+Tab
#               walks back;
#   5. PALETTE  every colour override, flat stylebox, ColorRect and bbcode colour is one
#               of the five house teals or pure white / black (alpha ignored).
# Plus the screen-owned back / activate keys (Escape closes the settings screen and the
# HOW TO PLAY panel; Enter on a focused control activates it).
# Headless, in the real tree (labels need a layout): each screen goes under a 1280x720
# holder and every container is sorted by hand, like test_class_altar_pick.gd does.

const UiStyle := preload("res://view/ui_style.gd")
const MenuScript := preload("res://app/menu.gd")
const AltarScript := preload("res://app/class_altar.gd")
const PauseScript := preload("res://app/pause_overlay.gd")
const SettingsMenuScript := preload("res://view/settings_menu.gd")
const LobbyHudScript := preload("res://view/lobby/lobby_hud.gd")
const LoadingScript := preload("res://app/loading_screen.gd")
const RecordsScript := preload("res://core/records.gd")

const SCREEN := Vector2(1280, 720)
const PAD := 4.0
const MIN_H := 32.0
const RECORDS := "user://test_ui_style_records.json"
const SETTINGS := "user://test_ui_style_settings.json"

const COLOR_KEYS := ["font_color", "font_hover_color", "font_pressed_color",
		"font_hover_pressed_color", "font_focus_color", "font_disabled_color",
		"font_outline_color", "default_color", "font_uneditable_color"]
const BOX_KEYS := ["panel", "normal", "hover", "pressed", "hover_pressed", "focus",
		"disabled", "background", "fill", "slider", "grabber_area", "grabber_area_highlight"]

var _root: Window
var _holder: Control


func run() -> Array[String]:
	var f: Array[String] = []
	_root = (Engine.get_main_loop() as SceneTree).root
	# a screen drawn on its own CanvasLayer (the pause overlay) lays out against the root
	# viewport, which --headless leaves tiny: measure everything at the reference size
	var old_size := _root.size
	_root.size = Vector2i(SCREEN)
	_holder = Control.new()
	_holder.name = "UiStyleHolder"
	_holder.size = SCREEN
	_root.add_child(_holder)
	var rec := RecordsScript.new()
	rec.best_level = 999
	rec.best_purse = 999999
	rec.save_to(RECORDS)
	_menu(f)
	_altar(f)
	_pause(f)
	_settings(f)
	_lobby_hud(f)
	_loading(f)
	_root.remove_child(_holder)
	_holder.free()
	_root.size = old_size
	for p in [RECORDS, SETTINGS]:
		var d := DirAccess.open("user://")
		if d != null and d.file_exists(str(p).get_file()):
			d.remove(str(p).get_file())
	return f


func _mount(p_c: Control) -> void:
	_holder.add_child(p_c)
	p_c.size = SCREEN
	_settle(p_c)


func _settle(p_c: Control) -> void:
	for _i in 3:
		_sort(p_c)


func _sort(p_n: Node) -> void:
	if p_n is Container:
		p_n.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for c in p_n.get_children():
		if c is SubViewport:
			continue
		_sort(c)


func _unmount(p_c: Control) -> void:
	_holder.remove_child(p_c)
	p_c.free()


func _key(p_code: int, p_shift := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = p_code
	e.pressed = true
	e.shift_pressed = p_shift
	return e


# ---- the five generic checks -------------------------------------------------------------

## Every Control under p_n that is drawn (visible in tree), skipping 3D viewports.
func _walk(p_n: Node, p_out: Array = []) -> Array:
	for c in p_n.get_children():
		if c is SubViewport or c is SubViewportContainer:
			continue
		if c is CanvasItem and not (c as CanvasItem).is_visible_in_tree():
			continue
		if c is Control:
			p_out.append(c)
		_walk(c, p_out)
	return p_out


func _interactive(p_screen: Control) -> Array:
	var out: Array = []
	for c in _walk(p_screen):
		if c is BaseButton or c is Range and not (c is ProgressBar) and not (c is ScrollBar):
			out.append(c)
	return out


func _name(c: Node) -> String:
	if c is Button and (c as Button).text != "":
		return "'%s'" % (c as Button).text
	if c is Label:
		return "'%s'" % (c as Label).text.left(40)
	return str(c.name)


func _margins(p_sb: StyleBox) -> Array:
	if p_sb == null:
		return [0.0, 0.0, 0.0, 0.0]
	return [p_sb.get_margin(SIDE_LEFT), p_sb.get_margin(SIDE_TOP),
			p_sb.get_margin(SIDE_RIGHT), p_sb.get_margin(SIDE_BOTTOM)]


func _align_k(p_align: int) -> float:
	match p_align:
		HORIZONTAL_ALIGNMENT_CENTER:
			return 0.5
		HORIZONTAL_ALIGNMENT_RIGHT:
			return 1.0
	return 0.0


## 1. FIT: the text block and its padding on all four sides, plus containment.
func _fit(f: Array[String], p_tag: String, p_screen: Control) -> void:
	for c in _walk(p_screen):
		_fit_one(f, p_tag, c)


func _fit_one(f: Array[String], p_tag: String, c: Control) -> void:
	var text := ""
	var font: Font = null
	var fs := 0
	var m := [0.0, 0.0, 0.0, 0.0]
	var hk := 0.0
	var vk := 0.5
	var wrap_w := -1.0
	var icon_w := 0.0
	if c is Label:
		var l := c as Label
		text = l.text
		font = l.get_theme_font("font")
		fs = l.get_theme_font_size("font_size")
		m = _margins(l.get_theme_stylebox("normal"))
		hk = _align_k(l.horizontal_alignment)
		vk = [0.0, 0.5, 1.0, 0.0][int(l.vertical_alignment)]
		if l.autowrap_mode != TextServer.AUTOWRAP_OFF:
			wrap_w = l.size.x - m[0] - m[2]
	elif c is Button:
		var b := c as Button
		text = b.text
		font = b.get_theme_font("font")
		fs = b.get_theme_font_size("font_size")
		m = _margins(b.get_theme_stylebox("normal"))
		hk = _align_k(b.alignment)
		if b is CheckButton:
			var ic := b.get_theme_icon("unchecked")
			icon_w = (float(ic.get_width()) if ic != null else 0.0) + float(b.get_theme_constant("h_separation"))
	else:
		return
	if text.strip_edges() == "" or font == null:
		return
	var ts: Vector2 = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, wrap_w, fs)
	var lines := maxi(1, int(round(ts.y / font.get_height(fs))))
	if c is Label:
		ts.y += float((c as Label).get_theme_constant("line_spacing")) * float(lines - 1)
	var sz: Vector2 = (c as Control).size
	var slack_x: float = sz.x - m[0] - m[2] - icon_w - ts.x
	var slack_y: float = sz.y - m[1] - m[3] - ts.y
	var left: float = m[0] + slack_x * hk
	var right: float = m[2] + icon_w + slack_x * (1.0 - hk)
	var top: float = m[1] + slack_y * vk
	var bottom: float = m[3] + slack_y * (1.0 - vk)
	if c is Button:
		left = m[0] + slack_x * hk
		top = (sz.y - ts.y) * 0.5
		bottom = top
	var worst := minf(minf(left, right), minf(top, bottom))
	if worst < PAD - 0.01:
		f.append("%s fit: %s (%s) is %.0fx%.0f for a %.0fx%.0f text block - pads L%.1f R%.1f T%.1f B%.1f, want >= %.0f"
				% [p_tag, _name(c), c.get_class(), sz.x, sz.y, ts.x, ts.y, left, right, top, bottom, PAD])
	_contained(f, p_tag, c)


## The text's own rect inside its nearest panel / button, else inside the screen.
func _contained(f: Array[String], p_tag: String, c: Control) -> void:
	var box := Rect2(Vector2.ZERO, SCREEN)
	var what := "the screen"
	var p := c.get_parent()
	while p != null and p != _holder:
		if p is PanelContainer or p is Button:
			box = (p as Control).get_global_rect()
			what = str(p.name)
			break
		p = p.get_parent()
	var r := c.get_global_rect()
	if not _inside(r, box):
		f.append("%s fit: %s rect %s spills out of %s %s" % [p_tag, _name(c), str(r), what, str(box)])
	elif what != "the screen" and not _inside(r, Rect2(Vector2.ZERO, SCREEN)):
		f.append("%s fit: %s rect %s (in %s) is off the 1280x720 screen" % [p_tag, _name(c), str(r), what])


func _inside(r: Rect2, box: Rect2) -> bool:
	return r.position.x >= box.position.x - 0.5 and r.position.y >= box.position.y - 0.5 \
			and r.end.x <= box.end.x + 0.5 and r.end.y <= box.end.y + 0.5


## 2. HEIGHT.
func _heights(f: Array[String], p_tag: String, p_screen: Control) -> void:
	for c in _interactive(p_screen):
		if (c as Control).size.y < MIN_H - 0.01:
			f.append("%s height: %s is %.0f px tall, want >= %.0f" % [p_tag, _name(c), (c as Control).size.y, MIN_H])


## 5. PALETTE (and no gradient textures in the chrome).
func _palette(f: Array[String], p_tag: String, p_screen: Control) -> void:
	var bad := {}
	var hexre := RegEx.create_from_string(r"\[color=(#[0-9A-Fa-f]{6,8})\]")
	for c in [p_screen] + _walk(p_screen):
		var ctl := c as Control
		for key in COLOR_KEYS:
			if ctl.has_theme_color_override(key):
				_one(bad, p_tag, ctl, key, ctl.get_theme_color(key))
		for key in BOX_KEYS:
			if ctl.has_theme_stylebox_override(key):
				var sb := ctl.get_theme_stylebox(key)
				if sb is StyleBoxFlat:
					var fl := sb as StyleBoxFlat
					_one(bad, p_tag, ctl, key + ".bg", fl.bg_color)
					if fl.border_width_left + fl.border_width_top + fl.border_width_right + fl.border_width_bottom > 0:
						_one(bad, p_tag, ctl, key + ".border", fl.border_color)
		if ctl is ColorRect:
			_one(bad, p_tag, ctl, "color", (ctl as ColorRect).color)
		if ctl is RichTextLabel:
			for mt in hexre.search_all((ctl as RichTextLabel).text):
				_one(bad, p_tag, ctl, "bbcode", Color(mt.get_string(1)))
		if ctl is TextureRect and ((ctl as TextureRect).texture is GradientTexture2D
				or (ctl as TextureRect).texture is GradientTexture1D):
			bad["%s palette: %s draws a gradient" % [p_tag, _name(ctl)]] = true
	for k in bad.keys():
		f.append(str(k))


func _one(bad: Dictionary, p_tag: String, c: Control, p_key: String, p_col: Color) -> void:
	if p_col.a <= 0.01 or UiStyle.in_palette(p_col):
		return
	bad["%s palette: %s %s is #%s, not a house colour" % [p_tag, _name(c), p_key,
			p_col.to_html(false).to_upper()]] = true


## True when p_c is p_item or inside it (a settings row holds its slider).
func _covered(p_c: Node, p_items: Array) -> bool:
	var n: Node = p_c
	while n != null:
		if p_items.has(n):
			return true
		n = n.get_parent()
	return false


## 3 + 4. RING and TAB. p_input feeds one key event to the screen; p_tick lets an eased
## screen (the menu) finish its easing before the ring is read.
func _focus(f: Array[String], p_tag: String, p_screen: Control, p_tick: Callable = Callable()) -> void:
	if not p_screen.has_method("focus_cycle") or not p_screen.has_method("handle_input"):
		f.append("%s tab: no focus_cycle() / handle_input() - the screen has no shared keyboard focus" % p_tag)
		return
	var fc = p_screen.focus_cycle()
	var n: int = fc.size()
	if n == 0:
		f.append("%s tab: the focus cycle is empty" % p_tag)
		return
	var seen: Array = []
	for i in n:
		if not p_screen.handle_input(_key(KEY_TAB)):
			f.append("%s tab: Tab was not consumed (step %d)" % [p_tag, i])
		if p_tick.is_valid():
			p_tick.call()
		var cur: Control = fc.current()
		if cur == null:
			f.append("%s tab: nothing focused after Tab %d" % [p_tag, i + 1])
			return
		if seen.has(cur):
			f.append("%s tab: Tab %d came back to %s before visiting every control" % [p_tag, i + 1, _name(cur)])
		seen.append(cur)
		if not UiStyle.has_focus_ring(cur):
			f.append("%s ring: the focused %s shows no focus ring" % [p_tag, _name(cur)])
		for other in fc.controls():
			if other != cur and UiStyle.has_focus_ring(other):
				f.append("%s ring: %s wears the ring while %s is focused" % [p_tag, _name(other), _name(cur)])
	p_screen.handle_input(_key(KEY_TAB))
	if fc.current() != seen[0]:
		f.append("%s tab: Tab after the last control did not wrap to the first" % p_tag)
	p_screen.handle_input(_key(KEY_TAB, true))
	if fc.current() != seen[n - 1]:
		f.append("%s tab: Shift+Tab from the first control did not go to the last" % p_tag)
	for c in _interactive(p_screen):
		if not _covered(c, seen):
			f.append("%s tab: Tab never reaches %s" % [p_tag, _name(c)])


func _all(f: Array[String], p_tag: String, p_screen: Control) -> void:
	_fit(f, p_tag, p_screen)
	_heights(f, p_tag, p_screen)
	_palette(f, p_tag, p_screen)


# ---- the screens -------------------------------------------------------------------------

func _menu(f: Array[String]) -> void:
	var m = MenuScript.new()
	m.records_path = RECORDS
	m.refresh_records()
	_mount(m)
	m.tick_ui(1.0)
	_settle(m)
	var bests: Label = m.bests_label()
	if not bests.text.contains("999") or not bests.text.contains("999999"):
		f.append("menu: the bests line does not show the 3-digit level / 6-digit purse ('%s')" % bests.text)
	_all(f, "menu", m)
	_focus(f, "menu", m, func() -> void: m.tick_ui(1.0))
	# the HOW TO PLAY panel: its own text fits; Escape (the pause binding) backs out
	m.open_howto()
	m.tick_ui(1.0)
	_settle(m)
	_all(f, "menu/howto", m)
	m.handle_input(_key(KEY_ESCAPE))
	if m.is_howto_open():
		f.append("menu/howto: Escape did not close the panel")
	m.tick_ui(1.0)
	_unmount(m)


func _altar(f: Array[String]) -> void:
	var a = AltarScript.new()
	_mount(a)
	var ids: Array = a.class_ids()
	var longest := ""
	for id in ids:
		if str(id).length() > longest.length():
			longest = str(id)
	a.open(longest)          # the longest name wears the "(last)" mark
	_settle(a)
	_all(f, "altar", a)
	_focus(f, "altar", a)
	# Enter on the focused first card picks it
	a.open("")
	_settle(a)
	a.handle_input(_key(KEY_TAB))
	a.handle_input(_key(KEY_ENTER))
	if ids.is_empty() or a.chosen_id() != str(ids[0]):
		f.append("altar: Tab + Enter picked '%s', want %s" % [a.chosen_id(), str(ids[0]) if not ids.is_empty() else "?"])
	_unmount(a)


func _pause(f: Array[String]) -> void:
	var p = PauseScript.new()
	_mount(p)
	p.open("LEVEL 999 - PURSE 999999 g")
	_settle(p)
	_all(f, "pause", p)
	_focus(f, "pause", p)
	# Enter on the focused RESUME resumes
	var resumed := [0]
	p.resumed.connect(func() -> void: resumed[0] += 1)
	if p.has_method("focus_cycle"):
		p.focus_cycle().focus_control(p.resume_button())
		p.handle_input(_key(KEY_ENTER))
	if resumed[0] != 1:
		f.append("pause: Enter on the focused RESUME did not resume")
	# SETTINGS opens over the overlay; Escape backs out to the overlay, not out of the pause
	p.open("LEVEL 1")
	p.open_settings()
	var s = p.settings_screen()
	s.settings_path = SETTINGS
	_settle(p)
	if s.has_method("handle_input"):
		s.handle_input(_key(KEY_ESCAPE))
	if s.is_open() or not p.is_open():
		f.append("pause/settings: Escape left settings open=%s, pause open=%s (want false / true)"
				% [str(s.is_open()), str(p.is_open())])
	_unmount(p)


func _settings(f: Array[String]) -> void:
	var s = SettingsMenuScript.new()
	s.settings_path = SETTINGS
	_mount(s)
	s.show_settings()
	s.store.volume = 100
	s.store.mouse_sensitivity = 0.30
	s.store.field_of_view = 90.0
	s._sync_controls()
	_settle(s)
	_all(f, "settings", s)
	_focus(f, "settings", s)
	# Left on the focused volume row turns it down one step
	if s.has_method("focus_cycle"):
		s.focus_cycle().focus(0)
		s.handle_input(_key(KEY_LEFT))
		if int(s.store.volume) != 99:
			f.append("settings: Left on the focused volume row left volume %d, want 99" % int(s.store.volume))
	AudioServer.set_bus_volume_db(0, 0.0)
	AudioServer.set_bus_mute(0, false)
	if s.has_method("handle_input"):
		s.handle_input(_key(KEY_ESCAPE))
	if s.is_open():
		f.append("settings: Escape did not close the screen")
	_unmount(s)


func _lobby_hud(f: Array[String]) -> void:
	var h = LobbyHudScript.new()
	_holder.add_child(h)
	h.sync(999999)
	_settle(h)
	if not h.purse_text().contains("999999"):
		f.append("lobby hud: the purse reads '%s' for 999999" % h.purse_text())
	_all(f, "lobby hud", h)
	_holder.remove_child(h)
	h.free()


func _loading(f: Array[String]) -> void:
	var l = LoadingScript.new()
	l.start(1, 0.0, false)
	_mount(l)
	l.set_load_progress(1.0)
	l.advance(0.0)
	_settle(l)
	_all(f, "loading", l)
	var tips: Array = l.load_tips()
	var bad := 0
	var first := ""
	for t in tips:
		l._tip_label.text = str((t as Dictionary).get("text", ""))
		_settle(l)
		var g: Array[String] = []
		_fit_one(g, "loading tip", l._tip_label)
		if not g.is_empty():
			bad += 1
			if first == "":
				first = g[0]
	if bad > 0:
		f.append("loading: %d / %d tips do not fit (first: %s)" % [bad, tips.size(), first])
	_unmount(l)
