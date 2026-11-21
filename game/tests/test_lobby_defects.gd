extends RefCounted
#
# test_lobby_defects.gd - three Antechamber defects the owner raised (cycle 4 items 2, 3, 5).
#
#   item 2: the lobby HUD shows the purse (sim/intermission.gd `purse`) and tracks a purchase.
#   item 3: every priced altar shows the gold the shop charges - the same altar["price"] the
#           sim deducts, moved by shop_price_mul - and a distinct cannot-afford state.
#   item 5: the About plaque text is centred in its board and wraps without an orphan line;
#           every other free-standing lobby label is centred on its anchor too.
#
# Label3D geometry is only built after a rendered frame and this suite runs synchronously,
# so item 5 asserts the layout RULE (alignment decides where the box sits around the
# origin - measured in-engine on 4.7.2, see antechamber.gd label_box_x) over TextServer's
# own line breaks, not a screenshot.

const LobbySceneScript := preload("res://view/lobby/lobby_scene.gd")
const AntechamberScript := preload("res://view/lobby/antechamber.gd")
const IntermissionScript := preload("res://sim/intermission.gd")
const InputScript := preload("res://sim/input.gd")
const OffersSim := preload("res://sim/offers.gd")

const SEED := 4242
const DT := 1.0 / 60.0
const RICH := 10000
const MUL := 1.5


func run() -> Array[String]:
	var f: Array[String] = []
	_leg_hud(f)
	_leg_price(f)
	_leg_price_mul(f)
	_leg_afford(f)
	_leg_plaque(f)
	_leg_other_labels(f)
	_leg_bar_spacing(f)
	return f


## Level 1's schedule is [E, U]: a lobby scene with a shop bay.
func _scene(p_ledger: Dictionary) -> Node3D:
	var s = LobbySceneScript.new()
	if not bool(s.build(SEED, 1, p_ledger)):
		s.free()
		return null
	return s


## The first U offer's wrapper in the hall, or {}.
func _u_offer(p_hall: Node3D) -> Dictionary:
	for w in p_hall._altars:
		if str(w["bay_kind"]) == "U" and str(w["kind"]) == "offer":
			return w
	return {}


## Buys the wrapper's altar through the sim's own input path, then one scene tick.
func _buy(p_scene: Node3D, p_wrap: Dictionary) -> void:
	p_scene.lobby.step([InputScript.new(0, 0, 0, int(p_wrap["index"]))])
	p_scene.tick(DT, 0, 0, false)


func _done(p_scene: Node3D) -> void:
	p_scene.teardown()
	p_scene.free()


# ---- item 2 ---------------------------------------------------------------------------

func _leg_hud(f: Array[String]) -> void:
	var s := _scene({"purse": RICH})
	if s == null:
		f.append("hud: the lobby scene did not build")
		return
	var hud = s.hud
	if hud == null or not is_instance_valid(hud):
		f.append("hud: the lobby scene built no purse HUD")
		_done(s)
		return
	if not (hud.get_parent() is CanvasLayer) or hud.get_parent().get_parent() != s:
		f.append("hud: the purse HUD is not on a CanvasLayer under the lobby scene")
	if int(hud.purse_gold()) != RICH:
		f.append("hud: shows %d g on entry, the purse is %d" % [int(hud.purse_gold()), RICH])
	if not str(hud._label.text).contains(str(RICH)):
		f.append("hud: the label reads '%s', want the purse %d" % [hud._label.text, RICH])
	var w := _u_offer(s.hall)
	if w.is_empty():
		f.append("hud: level 1's lobby drew no U offer - the leg proves nothing")
		_done(s)
		return
	var price := int(w["price"])
	_buy(s, w)
	var want := RICH - price
	if int(s.lobby.purse) != want:
		f.append("hud: the purchase left the purse at %d, want %d" % [int(s.lobby.purse), want])
	if int(hud.purse_gold()) != want:
		f.append("hud: shows %d g after a %d g purchase, want %d" % [int(hud.purse_gold()), price, want])
	if not str(hud._label.text).contains(str(want)):
		f.append("hud: the label reads '%s' after the purchase, want %d" % [hud._label.text, want])
	_done(s)


# ---- item 3 ---------------------------------------------------------------------------

## Every priced selectable shows altar_price(), which is the number the sim deducts.
func _leg_price(f: Array[String]) -> void:
	var s := _scene({"purse": RICH})
	if s == null:
		f.append("price: the lobby scene did not build")
		return
	var priced := 0
	for w in s.hall._altars:
		var bay: Dictionary = s.lobby.bays[int(w["bay_index"])]
		var kind := str(w["kind"])
		var want := -1
		if kind == "offer" and (str(bay["kind"]) == "U" or str(bay["kind"]) == "REST"):
			want = int((bay["altars"] as Array)[int(w["altar"])]["price"])
		elif kind == "reroll" and str(bay["kind"]) != "C":
			want = OffersSim.reroll_cost(int(bay.get("rerolls_used", 0)), s.lobby.content)
		elif kind == "tithe":
			want = OffersSim.tithe_cost(int(s.lobby.tithes), s.lobby.content)
		if want < 0:
			if w.has("price_label"):
				f.append("price: '%s' costs nothing but shows a price line" % str(w["label"]))
			continue
		priced += 1
		if not w.has("price_label"):
			f.append("price: '%s' shows no price (the shop charges %d g)" % [str(w["label"]), want])
			continue
		if int(w["price"]) != want:
			f.append("price: '%s' shows %d g, the shop charges %d g" % [str(w["label"]), int(w["price"]), want])
		var text: String = (w["price_label"] as Label3D).text
		if not text.contains("%d g" % want):
			f.append("price: '%s' price line reads '%s', want %d g" % [str(w["label"]), text, want])
	if priced == 0:
		f.append("price: no priced selectable in level 1's lobby - the leg proves nothing")
	# the gold a purchase actually takes is the number the altar showed
	var w := _u_offer(s.hall)
	if not w.is_empty():
		var shown := int(w["price"])
		var before := int(s.lobby.purse)
		_buy(s, w)
		var taken := before - int(s.lobby.purse)
		if taken != shown:
			f.append("price: the altar showed %d g but the purchase took %d g" % [shown, taken])
	_done(s)


## shop_price_mul (Bargain / Inflation) moves the displayed price with the charged one.
func _leg_price_mul(f: Array[String]) -> void:
	var s := _scene({"purse": RICH, "stats": {"shop_price_mul": MUL}})
	if s == null:
		f.append("mul: the lobby scene did not build")
		return
	var checked := 0
	for w in s.hall._altars:
		var bay: Dictionary = s.lobby.bays[int(w["bay_index"])]
		if str(w["kind"]) != "offer" or str(bay["kind"]) != "U":
			continue
		var altar: Dictionary = (bay["altars"] as Array)[int(w["altar"])]
		var u: Dictionary = s.lobby.content.upgrade(str(altar["id"]))
		var disc := (100.0 - float(int(bay.get("discount_pct", 0)))) / 100.0
		var stacks := int(altar.get("stacks", 0))
		var with_mul := OffersSim.price_for(u, stacks, MUL, disc)
		var base := OffersSim.price_for(u, stacks, 1.0, disc)
		if with_mul == base:
			continue
		checked += 1
		if int(w.get("price", -1)) != with_mul:
			f.append("mul: '%s' shows %d g, want %d g at shop_price_mul %.2f (base %d g)" % [str(w["label"]), int(w.get("price", -1)), with_mul, MUL, base])
	if checked == 0:
		f.append("mul: no U offer whose price moves at %.2f - the leg proves nothing" % MUL)
	# a mid-visit re-price (set_stats) reaches the altars on the next tick
	s.lobby.set_stats({"shop_price_mul": 1.0})
	s.tick(DT, 0, 0, false)
	for w in s.hall._altars:
		var bay: Dictionary = s.lobby.bays[int(w["bay_index"])]
		if str(w["kind"]) != "offer" or str(bay["kind"]) != "U":
			continue
		var altar: Dictionary = (bay["altars"] as Array)[int(w["altar"])]
		if int(w.get("price", -1)) != int(altar["price"]):
			f.append("mul: after set_stats '%s' shows %d g, the shop now charges %d g" % [str(w["label"]), int(w.get("price", -1)), int(altar["price"])])
	_done(s)


## A purse below the price shows the cannot-afford state: its own text and the danger colour.
func _leg_afford(f: Array[String]) -> void:
	var s := _scene({"purse": RICH})
	if s == null:
		f.append("afford: the lobby scene did not build")
		return
	var w := _u_offer(s.hall)
	if w.is_empty():
		f.append("afford: no U offer - the leg proves nothing")
		_done(s)
		return
	var gold: Color = s.hall._c("gold_gift")
	var danger: Color = s.hall._c("danger")
	if gold == danger:
		f.append("afford: the gold and danger roles resolve to one colour - the states read alike")
	if not bool(w.get("affordable", false)) or (w["price_label"] as Label3D).modulate != gold:
		f.append("afford: a %d g offer with %d g in the purse is not shown affordable (gold)" % [int(w["price"]), RICH])
	# the purse drops below the price (as a purchase elsewhere would); next tick redraws
	s.lobby.purse = int(w["price"]) - 1
	s.tick(DT, 0, 0, false)
	var w2 := _u_offer(s.hall)
	if w2.is_empty() or bool(w2.get("affordable", true)):
		f.append("afford: with %d g in the purse the %d g offer still reads affordable" % [int(s.lobby.purse), int(w["price"])])
	else:
		var lbl: Label3D = w2["price_label"]
		if lbl.modulate != danger:
			f.append("afford: the cannot-afford price is %s, want the danger role %s" % [str(lbl.modulate), str(danger)])
		if not lbl.text.contains("CANNOT AFFORD"):
			f.append("afford: the cannot-afford price line reads '%s'" % lbl.text)
	_done(s)


# ---- item 5 ---------------------------------------------------------------------------

func _hall() -> Node3D:
	var api = load("res://core/content_api.gd").load()
	var h = AntechamberScript.new()
	h.build_all(api, IntermissionScript.create(api, 1, RICH, SEED), "", 1)
	return h


## World-x extent of a Label3D's text block whose widest line is p_text_w world units.
func _block_x(p_label: Label3D, p_text_w: float) -> Vector2:
	var box: Vector2 = AntechamberScript.label_box_x(p_label.horizontal_alignment, p_text_w)
	var xa: Vector3 = p_label.transform.basis.x.normalized()
	var e1: float = p_label.position.x + xa.x * box.x
	var e2: float = p_label.position.x + xa.x * box.y
	return Vector2(minf(e1, e2), maxf(e1, e2))


func _line_w(p_text: String, p_font: int, p_pix: float) -> float:
	var widest := 0.0
	for line in p_text.split("\n"):
		widest = maxf(widest, ThemeDB.fallback_font.get_string_size(line,
				HORIZONTAL_ALIGNMENT_LEFT, -1, p_font).x * p_pix)
	return widest


func _leg_plaque(f: Array[String]) -> void:
	var h := _hall()
	var label: Label3D = null
	var board: Node3D = null
	for c in h.get_children():
		if c.has_meta("about_label"):
			label = c
		elif c.has_meta("about"):
			board = c
	if label == null or board == null:
		f.append("plaque: no About board / label in the hall")
		h.free()
		return
	if label.text != AntechamberScript.ABOUT_PLAQUE_TEXT:
		f.append("plaque: the label text is not ABOUT_PLAQUE_TEXT")
	var pix: float = label.pixel_size
	var inner: float = AntechamberScript.PLAQUE_W - AntechamberScript.PLAQUE_PAD * 2.0
	if float(label.width) * pix > inner + 1e-4:
		f.append("plaque: the wrap box is %.3f u, the board's inner width %.3f u" % [label.width * pix, inner])
	var lines: PackedStringArray = AntechamberScript.plaque_lines(label.width)
	var widest := _line_w("\n".join(lines), label.font_size, pix)
	var ext := _block_x(label, widest)
	var offset := (ext.x + ext.y) * 0.5 - board.position.x
	if absf(offset) > 1e-3:
		f.append("plaque: the text block's centre is %.3f u off the board's centre" % offset)
	var half := AntechamberScript.PLAQUE_W * 0.5
	if ext.x < board.position.x - half or ext.y > board.position.x + half:
		f.append("plaque: the text block spans x %.3f..%.3f, past the board's %.3f..%.3f" % [ext.x, ext.y, board.position.x - half, board.position.x + half])
	if label.vertical_alignment != VERTICAL_ALIGNMENT_CENTER or absf(label.position.y - board.position.y) > 1e-4:
		f.append("plaque: the text block is not centred vertically on the board")
	var tall: float = lines.size() * ThemeDB.fallback_font.get_height(label.font_size) * pix
	if tall > AntechamberScript.PLAQUE_H:
		f.append("plaque: %d lines are %.2f u tall, the board %.2f u" % [lines.size(), tall, AntechamberScript.PLAQUE_H])
	# no orphan: the last line carries more than a word or two (the owner's shot: "game.")
	var last: String = lines[lines.size() - 1] if lines.size() > 0 else ""
	if last.split(" ", false).size() < 3:
		f.append("plaque: the last wrapped line is an orphan: '%s'" % last)
	h.free()


## Every other lobby label sits where it is meant to: the banners and subtitles centred on
## their bay, the gate readout centred on the gate, and the bar lines starting at the bar's
## text edge and ending inside the slab.
func _leg_other_labels(f: Array[String]) -> void:
	var h := _hall()
	h._gate_label_refresh(false)
	var slots: Array = AntechamberScript._bay_slots(h.lobby)
	var seen := 0
	for b in h._banners:
		var x := float(AntechamberScript.BAY_X[int(slots[int(b["bay_index"])])])
		for key in ["title", "subtitle"]:
			var l: Label3D = b[key]
			seen += 1
			var ext := _block_x(l, _line_w(l.text, l.font_size, l.pixel_size))
			if absf((ext.x + ext.y) * 0.5 - x) > 1e-3:
				f.append("labels: banner %s '%s' is centred at %.3f, its bay at %.3f" % [key, l.text, (ext.x + ext.y) * 0.5, x])
	var g: Label3D = h._gate_label
	if g == null:
		f.append("labels: no sealed-gate readout on a sealed gate")
	else:
		seen += 1
		var ext := _block_x(g, _line_w(g.text, g.font_size, g.pixel_size))
		if absf((ext.x + ext.y) * 0.5 - AntechamberScript.GATE_POS.x) > 1e-3:
			f.append("labels: the gate readout is centred at %.3f, the gate at %.3f" % [(ext.x + ext.y) * 0.5, AntechamberScript.GATE_POS.x])
	var left := -AntechamberScript.BAR_W * 0.5 + AntechamberScript.BAR_TEXT_X
	var right := AntechamberScript.BAR_W * 0.5 - AntechamberScript.BAR_RIGHT_PAD
	for w in h._altars:
		for key in ["panel", "price_label"]:
			if not w.has(key) or w[key] == null:
				continue
			var l: Label3D = w[key]
			seen += 1
			var k: float = l.scale.x
			var ext := _block_x(l, _line_w(l.text, l.font_size, l.pixel_size) * k)
			if absf(ext.x - left) > 1e-3 or ext.y > right + 1e-3:
				f.append("labels: bar %s '%s' spans %.3f..%.3f, want it to start at %.3f and end by %.3f" % [key, l.text, ext.x, ext.y, left, right])
	if seen == 0:
		f.append("labels: no lobby label checked - the leg proves nothing")
	h.free()


## The price line has its own row on the bar: under the description, not over it, and
## inside the slab (font line heights from the font the Label3D draws with).
func _leg_bar_spacing(f: Array[String]) -> void:
	var font: Font = ThemeDB.fallback_font
	var pix: float = AntechamberScript.BAR_PIXEL
	var name_h: float = font.get_height(AntechamberScript.BAR_FONT) * pix
	var desc_h: float = font.get_height(AntechamberScript.BAR_FONT_DESC) * pix
	var price_h: float = font.get_height(AntechamberScript.BAR_FONT_PRICE) * pix
	var name_bot: float = AntechamberScript.BAR_NAME_DY - name_h * 0.5
	var desc_top: float = AntechamberScript.BAR_DESC_DY + desc_h * 0.5
	var desc_bot: float = AntechamberScript.BAR_DESC_DY - desc_h * 0.5
	var price_top: float = AntechamberScript.BAR_PRICE_DY + price_h * 0.5
	var price_bot: float = AntechamberScript.BAR_PRICE_DY - price_h * 0.5
	if desc_top > name_bot + 1e-4:
		f.append("bar: the description line (top %.3f) overlaps the name (bottom %.3f)" % [desc_top, name_bot])
	if price_top > desc_bot + 1e-4:
		f.append("bar: the price line (top %.3f) overlaps the description (bottom %.3f)" % [price_top, desc_bot])
	if price_bot < -AntechamberScript.BAR_H * 0.5:
		f.append("bar: the price line (bottom %.3f) runs off the slab (%.3f)" % [price_bot, -AntechamberScript.BAR_H * 0.5])
