extends RefCounted
#
# D-GUI-1: the HUD rebuild in the owner's reference panel language. Headless.
#
#   leg 1 gold reader:   gold_counter.gd read() on a REAL sim (RunState level, real
#                        collects) - hidden/zero before the flip, then exactly the
#                        gold_taken bitset over REAL slots / total_real; a planted bit on
#                        a mine slot never counts; read() writes nothing.
#   leg 2 hud swap:      black phase -> gift counter shown, gold counter hidden; gold
#                        phase -> the reverse, never both.
#   leg 3 world wiring:  a real world.build() + step(): the counter follows the sim, and
#                        the CTRL hint follows world's real lock flag through the real
#                        state machine (_mouse_lock_pass with the APP_MOUSE_TOGGLE edge),
#                        in both states.
#   leg 4 layout:        every panel element's rect (anchors + offsets, the same maths
#                        the engine applies) sits inside the viewport and no two visible
#                        panels overlap, at 1280x720 and 1920x1080, in both phases, with
#                        every row full and the collapse warning up; content-sized panels
#                        fit their slot.
#   leg 5 negative:      the bounds/overlap checker catches a planted overlap and a
#                        planted off-screen panel; the hint check catches an inverted text.

const VoidGenScript := preload("res://terrain/voidgen.gd")
const RunStateScript := preload("res://sim/run_state.gd")
const GiftsScript := preload("res://sim/gifts.gd")
const HudScript := preload("res://view/hud/hud.gd")
const GoldCounterScript := preload("res://view/hud/gold_counter.gd")
const MouseHintScript := preload("res://view/hud/mouse_hint.gd")
const IconRowsScript := preload("res://view/hud/icon_rows.gd")
const HudStyle := preload("res://view/hud/hud_style.gd")
const WorldScript := preload("res://app/world.gd")
const InputCaptureScript := preload("res://app/input_capture.gd")

const SEED := 42
const LEVEL := 25   # rolls mine slots (occ == 1) beside the real ones: the exclusion is exercised
const W_SEED := 1
const W_LEVEL := 1
const DT := 1.0 / 60.0
const VIEWPORTS := [Vector2(1280, 720), Vector2(1920, 1080)]


func run() -> Array[String]:
	var f: Array[String] = []
	_leg_gold_reader(f)
	_leg_hud_swap(f)
	_leg_world_wiring(f)
	_leg_layout(f)
	_leg_negative(f)
	return f


## Independent popcount of gold_taken over REAL slots (the test's own reading).
static func _gold_bits(g: RefCounted) -> int:
	var n := 0
	for i in g.slots.size():
		if int(g.slots[i]["occ"]) == 0 and (g.gold_taken[i >> 3] & (1 << (i & 7))) != 0:
			n += 1
	return n


func _leg_gold_reader(f: Array[String]) -> void:
	var L := VoidGenScript.generate(SEED, LEVEL)
	var rs: RefCounted = RunStateScript.new_run(SEED, 1, [])
	rs.load_level(L, LEVEL)
	var g: RefCounted = rs.level.gifts
	var real := int(g.total_real)
	var mine_id := -1
	for i in g.slots.size():
		if not g.is_real(i):
			mine_id = i
			break
	if real <= 0 or mine_id < 0:
		f.append("gold reader: seed %d level %d has %d real slots, mine slot %d" % [SEED, LEVEL, real, mine_id])
		return
	var r: Dictionary = GoldCounterScript.read(g)
	if bool(r["active"]) or int(r["collected"]) != 0:
		f.append("gold reader before the flip: %s, want inactive / 0" % str(r))
	# black phase, half the black gifts taken: still no gold counter
	var half := 0
	for i in g.slots.size():
		if g.is_real(i) and half < real / 2:
			g.collect(i, 100 + i, 0, [])
			half += 1
	r = GoldCounterScript.read(g)
	if bool(r["active"]) or int(r["collected"]) != 0:
		f.append("gold reader mid black phase: %s, want inactive / 0" % str(r))
	# the last black gift flips the phase
	for i in g.slots.size():
		if g.is_real(i) and not g.collected(i):
			g.collect(i, 1000 + i, 0, [])
	if str(g.phase) != GiftsScript.PHASE_GOLD:
		f.append("gold reader: phase %s after every black gift, want gold" % g.phase)
		return
	r = GoldCounterScript.read(g)
	if not bool(r["active"]) or int(r["collected"]) != 0 or int(r["total"]) != real:
		f.append("gold reader at the flip: %s, want active 0 / %d" % [str(r), real])
	# take 7 gold gifts through the sim's own collect()
	var took := 0
	for i in g.slots.size():
		if took < 7 and g.present(i):
			g.collect(i, 5000 + i, 0, [])
			took += 1
	var before: PackedByteArray = g.gold_taken.duplicate()
	r = GoldCounterScript.read(g)
	if g.gold_taken != before:
		f.append("gold reader wrote the gold_taken bitset")
	if int(r["collected"]) != 7 or int(r["collected"]) != _gold_bits(g):
		f.append("gold reader after 7 gold pickups: %d, bitset says %d, want 7" % [int(r["collected"]), _gold_bits(g)])
	# a bit planted on a mine slot is not a gift and never counts
	GiftsScript.bit_set(g.gold_taken, mine_id)
	r = GoldCounterScript.read(g)
	if int(r["collected"]) != 7:
		f.append("gold reader counted a mine slot's bit: %d, want 7" % int(r["collected"]))
	var c = GoldCounterScript.new()
	c.sync_gold(bool(r["active"]), int(r["collected"]), int(r["total"]))
	if c.counter_text() != "7 / %d" % real or not c.visible:
		f.append("gold counter text '%s' visible %s, want '7 / %d' shown" % [c.counter_text(), str(c.visible), real])
	c.sync_gold(false, 7, real)
	if c.visible or c.counter_text() != "0 / 0":
		f.append("gold counter in the black phase: visible %s text '%s', want hidden 0 / 0" % [str(c.visible), c.counter_text()])
	print("HUD GUI gold reader seed %d level %d: %d real, 7 gold taken -> '7 / %d'" % [SEED, LEVEL, real, real])
	c.free()


func _leg_hud_swap(f: Array[String]) -> void:
	var hud = HudScript.new()
	hud.sync({"gifts_collected": 3, "gifts_total": 40})
	if not hud.gift_counter.visible or hud.gold_counter.visible:
		f.append("hud swap, no gold dict: gift %s gold %s, want gift shown only"
				% [str(hud.gift_counter.visible), str(hud.gold_counter.visible)])
	hud.sync({"gifts_collected": 40, "gifts_total": 40,
			"gold": {"active": false, "collected": 0, "total": 40}})
	if not hud.gift_counter.visible or hud.gold_counter.visible:
		f.append("hud swap, black phase: gold counter shown")
	hud.sync({"gifts_collected": 2, "gifts_total": 40,
			"gold": {"active": true, "collected": 2, "total": 40}})
	if hud.gift_counter.visible or not hud.gold_counter.visible:
		f.append("hud swap, gold phase: gift %s gold %s, want gold shown only"
				% [str(hud.gift_counter.visible), str(hud.gold_counter.visible)])
	if hud.gold_counter.counter_text() != "2 / 40":
		f.append("hud gold counter text '%s', want '2 / 40'" % hud.gold_counter.counter_text())
	hud.free()


func _leg_world_wiring(f: Array[String]) -> void:
	var world = WorldScript.new()
	var ledger := {"class": "dasher", "votes": {}, "curses": {}, "stacks": {},
			"purse": 500, "tithes": 0, "hunger": 0, "last_vote": ""}
	if not world.build(W_SEED, W_LEVEL, ledger):
		f.append("world wiring: build(%d, %d) failed" % [W_SEED, W_LEVEL])
		world.free()
		return
	world.step(DT)
	var hud = world.hud
	var g: RefCounted = world.lstate.gifts
	if str(g.phase) != GiftsScript.PHASE_BLACK:
		f.append("world wiring: level starts in phase %s" % g.phase)
	if hud.gold_counter.visible or not hud.gift_counter.visible:
		f.append("world wiring, black phase: gold counter shown or gift counter hidden")
	# finish the black phase on the sim, then let the world's own step feed the HUD
	for i in g.slots.size():
		if g.is_real(i) and not g.collected(i):
			g.collect(i, int(world.lstate.tick), 0, [])
	var took := 0
	for i in g.slots.size():
		if took < 2 and g.present(i):
			g.collect(i, int(world.lstate.tick), 0, [])
			took += 1
	world.step(DT)
	var want := "%d / %d" % [_gold_bits(g), int(g.total_real)]
	if not hud.gold_counter.visible or hud.gift_counter.visible:
		f.append("world wiring, gold phase: gold %s gift %s, want gold shown only"
				% [str(hud.gold_counter.visible), str(hud.gift_counter.visible)])
	if hud.gold_counter.counter_text() != want or _gold_bits(g) < 2:
		f.append("world wiring: gold counter '%s', the bitset says '%s' (>= 2 taken)"
				% [hud.gold_counter.counter_text(), want])
	_check_hint(f, world, "after build")
	# CTRL edge through the real state machine: locked -> free -> locked
	for k in 2:
		world._mouse_lock_pass(0)
		world._mouse_lock_pass(InputCaptureScript.APP_MOUSE_TOGGLE)
		world._mouse_lock_pass(0)
		world._sync_hud()
		_check_hint(f, world, "after CTRL press %d" % (k + 1))
	if not bool(world._mouse_locked):
		f.append("world wiring: two CTRL presses left the mouse %s, want locked again"
				% str(world._mouse_locked))
	world.teardown()
	world.free()


## The hint must state what CTRL does now: locked -> UNLOCK, free -> LOCK.
func _check_hint(f: Array[String], world, tag: String) -> void:
	var locked := bool(world._mouse_locked)
	var want := MouseHintScript.TEXT_LOCKED if locked else MouseHintScript.TEXT_FREE
	var got: String = world.hud.mouse_hint.hint_text()
	var shown: String = world.hud.mouse_hint._label.text
	if got != want or shown != want:
		f.append("CTRL hint %s: mouse locked %s, hint '%s' label '%s', want '%s'"
				% [tag, str(locked), got, shown, want])
	else:
		print("HUD GUI hint %s: locked=%s '%s'" % [tag, str(locked), shown])


## The rect the engine gives an anchored Control inside a parent of size vp.
static func _rect(c: Control, vp: Vector2) -> Rect2:
	var x0 := c.anchor_left * vp.x + c.offset_left
	var y0 := c.anchor_top * vp.y + c.offset_top
	var x1 := c.anchor_right * vp.x + c.offset_right
	var y1 := c.anchor_bottom * vp.y + c.offset_bottom
	return Rect2(x0, y0, x1 - x0, y1 - y0)


## Every problem with a {name: Control} panel set at viewport vp: off-screen, empty, or
## two visible panels sharing pixels. Returns the problems (empty = clean).
static func layout_problems(panels: Dictionary, vp: Vector2) -> Array[String]:
	var out: Array[String] = []
	var screen := Rect2(Vector2.ZERO, vp)
	var shown: Array = []
	for key in panels:
		var c: Control = panels[key]
		if not c.visible:
			continue
		var r := _rect(c, vp)
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			out.append("%s at %s: empty rect %s" % [key, str(vp), str(r)])
		elif not screen.encloses(r):
			out.append("%s at %s: rect %s leaves the viewport" % [key, str(vp), str(r)])
		shown.append([key, r])
	for i in shown.size():
		for j in range(i + 1, shown.size()):
			if (shown[i][1] as Rect2).intersects(shown[j][1] as Rect2):
				out.append("%s %s overlaps %s %s at %s" % [shown[i][0], str(shown[i][1]),
						shown[j][0], str(shown[j][1]), str(vp)])
	return out


## A HUD with every row full: 12 enemy types, 20 curses (the "+N" fold), 12 upgrades,
## the collapse warning up, the dasher's cooldown, the footprint map on.
func _full_hud(gold_phase: bool):
	var hud = HudScript.new()
	var roster: Array = []
	for k in 12:
		roster.append({"id": "probe_%d" % k, "count": 1 + k % 3})
	var curses: Array = []
	for k in 20:
		curses.append({"id": "curse_%d" % k, "stacks": 1 + k % 2})
	var ups: Array = []
	for k in 12:
		ups.append({"id": "up_%d" % k, "stacks": 1})
	hud.sync({"gifts_collected": 124, "gifts_total": 124,
			"gold": {"active": gold_phase, "collected": 88, "total": 124},
			"purse_centi": 1234567, "chain": 12.5, "charges": 2, "charge_cap": 2,
			"kit": "dasher", "ability_remaining": 1.2, "ability_total": 3.0,
			"curses": curses, "upgrades": ups, "roster": roster,
			"collapse": {"active": true, "cracking": true, "seconds": 4.2, "zones_left": 3},
			# T4 (D-T4-8): the clawd counter + anger meter pill, live so the layout leg counts it
			"clawds": {"active": true, "taken": 3, "total": 8, "anger_ticks": 3600,
				"warned": 1, "kill_ticks": 10800, "next_at": 7200, "paused": false},
			"mouse_locked": true})
	hud.cartographer_map.visible = true   # the footprint-map owner's worst case
	# in the tree, so theme constants and panel margins resolve for the fit checks
	(Engine.get_main_loop() as SceneTree).root.add_child(hud)
	return hud


func _leg_layout(f: Array[String]) -> void:
	for gold_phase in [false, true]:
		var hud = _full_hud(gold_phase)
		var panels: Dictionary = hud.panel_elements()
		var shown := 0
		for key in panels:
			if (panels[key] as Control).visible:
				shown += 1
		# every panel but one of the two counters is up
		if shown != panels.size() - 1:
			f.append("layout (gold %s): %d of %d panels visible, want %d"
					% [str(gold_phase), shown, panels.size(), panels.size() - 1])
		for vp in VIEWPORTS:
			for p in layout_problems(panels, vp):
				f.append("layout (gold %s): %s" % [str(gold_phase), p])
			if not gold_phase:
				print("HUD GUI layout %s: %s" % [str(vp), _dump(panels, vp)])
		# the content-sized panels fit their reserved slots at their fullest
		var rows: Control = hud.icon_rows
		# the icon panel is sized by hand: it must fit the slot AND hold what the engine
		# says the rows need (their laid-out minimum plus the panel padding)
		var rows_min: Vector2 = rows._panel.size
		if rows_min.x > rows.offset_right - rows.offset_left + 0.5 \
				or rows_min.y > rows.offset_bottom - rows.offset_top + 0.5:
			f.append("icon rows panel %s overflows its slot" % str(rows_min))
		var need: Vector2 = rows._rows.get_combined_minimum_size() \
				+ Vector2(HudStyle.PAD_X * 2.0, HudStyle.PAD_Y * 2.0)
		if need.y > rows_min.y + 0.5:
			f.append("icon rows need %s, the panel gives %s" % [str(need), str(rows_min)])
		var widest: float = maxf(rows._curses_row.get_combined_minimum_size().x,
				rows._upgrades_row.get_combined_minimum_size().x) + HudStyle.PAD_X * 2.0
		if absf(widest - rows_min.x) > 0.5:
			f.append("icon rows panel width %.0f, the widest row needs %.0f" % [rows_min.x, widest])
		if rows._curses_row.get_child_count() != IconRowsScript.MAX_PER_ROW:
			f.append("20 curses drew %d cells, want %d (11 + the +N fold)"
					% [rows._curses_row.get_child_count(), IconRowsScript.MAX_PER_ROW])
		var er: Control = hud.enemy_roster
		var er_min: Vector2 = er._panel.get_combined_minimum_size()
		if er_min.x > er.offset_right - er.offset_left + 0.5 \
				or er_min.y > er.offset_bottom - er.offset_top + 0.5:
			f.append("enemy roster panel %s overflows its slot" % str(er_min))
		if gold_phase:
			print("HUD GUI fit: icon rows panel %s in slot %s; roster panel %s in slot %s" % [
					str(rows_min), str(Vector2(rows.offset_right - rows.offset_left,
					rows.offset_bottom - rows.offset_top)), str(er_min),
					str(Vector2(er.offset_right - er.offset_left, er.offset_bottom - er.offset_top))])
		if er_min.x < 100.0 or rows_min.x < 500.0:
			f.append("fit check measured nothing: roster %s rows %s" % [str(er_min), str(rows_min)])
		hud.get_parent().remove_child(hud)
		hud.free()


static func _dump(panels: Dictionary, vp: Vector2) -> String:
	var parts: PackedStringArray = []
	for key in panels:
		if (panels[key] as Control).visible:
			var r := _rect(panels[key], vp)
			parts.append("%s=(%d,%d %dx%d)" % [key, r.position.x, r.position.y, r.size.x, r.size.y])
	return " ".join(parts)


func _leg_negative(f: Array[String]) -> void:
	var hud = _full_hud(false)
	var panels: Dictionary = hud.panel_elements()
	# planted overlap: the collapse warning back at its pre-D-GUI-1 y = 100 meets the
	# icon rows' panel slot (which now ends at 118)
	var w: Control = hud.collapse_warning
	var keep_top := w.offset_top
	var keep_bottom := w.offset_bottom
	w.offset_top = 100.0
	w.offset_bottom = 134.0
	if layout_problems(panels, VIEWPORTS[0]).is_empty():
		f.append("negative control: a collapse warning at y = 100 was not reported as overlapping")
	w.offset_top = keep_top
	w.offset_bottom = keep_bottom
	# planted off-screen: the purse pushed past the right edge
	var p: Control = hud.purse_chain
	p.offset_right += 40.0
	if layout_problems(panels, VIEWPORTS[0]).is_empty():
		f.append("negative control: a purse past the right edge was not reported")
	p.offset_right -= 40.0
	if not layout_problems(panels, VIEWPORTS[0]).is_empty():
		f.append("negative control: the restored layout still reports problems")
	# an inverted hint is caught: the locked state must never read "CTRL TO LOCK MOUSE"
	hud.mouse_hint.sync(true)
	if hud.mouse_hint.hint_text() == MouseHintScript.TEXT_FREE:
		f.append("negative control: a locked mouse reads '%s'" % MouseHintScript.TEXT_FREE)
	hud.mouse_hint.sync(false)
	if hud.mouse_hint.hint_text() == MouseHintScript.TEXT_LOCKED:
		f.append("negative control: a free mouse reads '%s'" % MouseHintScript.TEXT_LOCKED)
	hud.get_parent().remove_child(hud)
	hud.free()
