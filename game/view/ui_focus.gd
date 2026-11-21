extends RefCounted
#
# view/ui_focus.gd - the keyboard focus every menu screen shares (D-GUI-1, view/ui_style.gd).
#
# A screen registers its interactive controls in visual order; this object owns which one
# is focused and paints the focus ring (UiStyle.focus_box) on exactly that one. Keys:
#   Tab / Shift+Tab   next / previous, wrapping            (key repeat allowed)
#   Up / Down         previous / next, wrapping            (when `vertical`)
#   Left / Right      adjust the focused control (sliders) - or previous / next when
#                     the control has no adjust and `horizontal` is set
#   Enter / Space     activate the focused control         (never on a key repeat)
# Escape is NOT handled here: every screen's way back is its owner's (app.gd's pause
# binding, the menu's panel close, the settings screen's close).
# The controls keep FOCUS_NONE, so Godot's ui_accept / ui_focus_next never act on them.
# Headless: handle_key() is plain logic; no scene tree is needed.

const UiStyle := preload("res://view/ui_style.gd")

var index := -1                 # -1 = nothing focused yet
var vertical := true
var horizontal := false
var scale := 1.0
var hover_focus := true         # false: mouse-over never moves the ring (the class altar)
var _items: Array = []          # [{c, kind, act: Callable, adj: Callable, paint: Callable}]
var changed: Callable = Callable()   # called with the new index after every move


func add(p_c: Control, p_kind: String, p_activate: Callable = Callable(),
		p_adjust: Callable = Callable(), p_paint: Callable = Callable()) -> int:
	_items.append({"c": p_c, "kind": p_kind, "act": p_activate, "adj": p_adjust,
			"paint": p_paint})
	if hover_focus and (p_c is BaseButton or p_c is PanelContainer):
		p_c.mouse_entered.connect(func() -> void: hover(p_c))
	_paint_one(_items.size() - 1)
	return _items.size() - 1


func size() -> int:
	return _items.size()


func controls() -> Array:
	var out: Array = []
	for it in _items:
		out.append(it["c"])
	return out


func current() -> Control:
	if index < 0 or index >= _items.size():
		return null
	return _items[index]["c"]


func focus(p_i: int) -> void:
	if _items.is_empty():
		return
	index = posmod(p_i, _items.size())
	repaint()
	if changed.is_valid():
		changed.call(index)


func focus_control(p_c: Control) -> void:
	for i in _items.size():
		if _items[i]["c"] == p_c:
			focus(i)
			return


func clear() -> void:
	index = -1
	repaint()


## One step; from "nothing focused" the first step forward lands on the first control and
## the first step back on the last.
func step(p_dir: int) -> void:
	if _items.is_empty():
		return
	if index < 0:
		focus(0 if p_dir > 0 else _items.size() - 1)
	else:
		focus(index + p_dir)


## Mouse-over moves the focus (one ring on screen, never one per input device).
func hover(p_c: Control) -> void:
	if p_c is BaseButton and (p_c as BaseButton).disabled:
		return
	focus_control(p_c)


func activate() -> bool:
	if index < 0:
		return false
	var it: Dictionary = _items[index]
	if it["c"] is BaseButton and (it["c"] as BaseButton).disabled:
		return false
	var cb: Callable = it["act"]
	if not cb.is_valid():
		return false
	cb.call()
	return true


func adjust(p_dir: int) -> bool:
	if index < 0:
		return false
	var cb: Callable = _items[index]["adj"]
	if not cb.is_valid():
		return false
	cb.call(p_dir)
	return true


## The shared key map (see the header). Returns true when the key was used.
func handle_key(p_event: InputEvent) -> bool:
	if not (p_event is InputEventKey):
		return false
	var k := p_event as InputEventKey
	if not k.pressed:
		return false
	var code: int = int(k.keycode) if k.keycode != KEY_NONE else int(k.physical_keycode)
	match code:
		KEY_TAB:
			step(-1 if k.shift_pressed else 1)
			return true
		KEY_UP:
			if vertical:
				step(-1)
				return true
		KEY_DOWN:
			if vertical:
				step(1)
				return true
		KEY_LEFT, KEY_RIGHT:
			var d := -1 if code == KEY_LEFT else 1
			if adjust(d):
				return true
			if horizontal:
				step(d)
				return true
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if k.echo:
				return false
			return activate()
	return false


func repaint() -> void:
	for i in _items.size():
		_paint_one(i)


func _paint_one(p_i: int) -> void:
	var it: Dictionary = _items[p_i]
	var c: Control = it["c"]
	if not is_instance_valid(c):
		return
	var on := p_i == index
	var cb: Callable = it["paint"]
	if cb.is_valid():
		cb.call(c, on)
	elif c is Button:
		UiStyle.paint(c as Button, str(it["kind"]), on, scale)
	elif c is PanelContainer:
		var px := roundf(UiStyle.PAD_X * scale)
		var py := roundf(UiStyle.PAD_Y * scale)
		c.add_theme_stylebox_override("panel", UiStyle.focus_box(px, py) if on
				else UiStyle.rest_box(str(it["kind"]), px, py))
