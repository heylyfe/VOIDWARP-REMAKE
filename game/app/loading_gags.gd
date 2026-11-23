extends RefCounted

const AssetLoadScript := preload("res://view/asset_load.gd")   # U4: fail-soft loads (text/scene/texture/stream)
#
# Loading-screen gags (TICKET LOADING; DECISIONS D-LOAD-1..8). Pure model, no nodes: for a gag id and
# a display time `t` it returns the list of "items" the stage (app/loading_stage.gd) draws - real enemy
# PNG sprites (game/content/enemies/<id>/sprites/*.png) with a procedural pose (position, rotation,
# squash/stretch, tint, frame swap), plus a few drawn props (a gift box, speech bubbles, smoke).
# No image model exists here, so every motion is a function of `t`; tests step it headlessly.
#
# TIMING LAW OF A GAG: a gag is a CYCLE_SECONDS (5.0 s) timeline whose first BEAT_A_SECONDS (2.0 s)
# already contain the whole joke - set-up and punchline - because a restart shows the screen for
# exactly 2.0 s and must still land it. The remaining 3.0 s are the "tag" (the second, funnier
# beat) that a first launch (5.0 s) gets. Every gag starts and ends with its enemy off stage or at
# rest, so a load slower than 5.0 s loops the timeline without a visible pop.
#
# Stage space: 1280 x 720 virtual pixels, y grows downward, feet rest on GROUND_Y. The enemies are in on
# the joke: they never address the player about the game, only about their own bad day.

const STAGE_W := 1280.0
const STAGE_H := 720.0
const GROUND_Y := 470.0
const CYCLE_SECONDS := 5.0
const BEAT_A_SECONDS := 2.0

const CYAN := Color(0.486, 1.0, 0.957)      # #7CFFF4 - the gift rim / beam colour
const PINK := Color(1.0, 0.31, 0.847)       # #FF4FD8 - the tripmine tell
const RED := Color(1.0, 0.165, 0.165)       # #FF2A2A - danger text
const INK := Color(0.03, 0.03, 0.08)
const PAPER := Color(0.97, 0.97, 1.0)

const GAG_IDS: Array[String] = ["toucher_slip", "seal_giftbox", "coil_launch", "kiwi_larper", "ben_bonk"]

## res:// path of the gag cast + sprite sheets: gag id -> Array of [enemy_id, sprite_name].
## The app layer may not name a content id (the FIX-A14 boundary scan), so the cast lives
## in the content tree and is read at run time; first appearance order fixes each gag's
## cast slots (the timeline code indexes cast in that order).
const GAG_DATA := "res://content/loading_gags.json"

static var _gag_data: Dictionary = {}
static var _gag_loaded := false


static func _data() -> Dictionary:
	if _gag_loaded:
		return _gag_data
	_gag_loaded = true
	_gag_data = {}
	var text := AssetLoadScript.text(GAG_DATA)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		for key in (parsed as Dictionary):
			var k := str(key)
			if k.begins_with("_"):
				continue   # metadata fields such as _doc
			_gag_data[k] = (parsed as Dictionary)[key]
	return _gag_data


## gag id -> the [enemy_id, sprite_name] pairs it draws ([] when the gag is unknown or
## the manifest is unreadable).
static func sprites_for(id: String) -> Array:
	var pairs: Variant = _data().get(id, [])
	return (pairs as Array).duplicate(true) if pairs is Array else []


## gag id -> Array[String] of the enemies it draws, first-appearance order (the cast slots
## the timeline code indexes).
static func cast_for(id: String) -> Array[String]:
	var out: Array[String] = []
	for ref in sprites_for(id):
		if ref is Array and not (ref as Array).is_empty():
			var e := str((ref as Array)[0])
			if not out.has(e):
				out.append(e)
	return out


## Gag for a load: seeded, deterministic, never the same as the previous load's gag.
static func pick_gag(seed_value: int, previous: String = "") -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var idx := rng.randi() % GAG_IDS.size()
	if GAG_IDS[idx] == previous:
		idx = (idx + 1) % GAG_IDS.size()
	return GAG_IDS[idx]


## res:// path of one enemy sprite (billboard PNG).
static func sprite_path(enemy_id: String, sprite_name: String) -> String:
	return "res://content/enemies/%s/sprites/%s.png" % [enemy_id, sprite_name]


## The timeline time for a display time: loops every CYCLE_SECONDS.
static func cycle_time(t: float) -> float:
	return fposmod(maxf(t, 0.0), CYCLE_SECONDS)


## All items to draw for gag `id` at display time `t`. Unknown id -> [].
static func items(id: String, t: float) -> Array[Dictionary]:
	var tt := cycle_time(t)
	var cast := cast_for(id)
	match id:
		"toucher_slip":
			return _toucher_slip(tt, cast)
		"seal_giftbox":
			return _seal_giftbox(tt, cast)
		"coil_launch":
			return _coil_launch(tt, cast)
		"kiwi_larper":
			return _kiwi_larper(tt, cast)
		"ben_bonk":
			return _ben_bonk(tt, cast)
	var none: Array[Dictionary] = []
	return none


# ---- item builders ----------------------------------------------------------------------------

static func _spr(enemy: String, sprite_name: String, x: float, y: float, h: float,
		extra: Dictionary = {}) -> Dictionary:
	var d := {"k": "sprite", "enemy": enemy, "name": sprite_name, "x": x, "y": y, "h": h,
			"rot": 0.0, "sx": 1.0, "sy": 1.0, "flip": false, "a": 1.0, "p": 0.0,
			"shadow": true, "tint": Color(1, 1, 1, 1)}
	for key in extra:
		d[key] = extra[key]
	return d


static func _gift(x: float, y: float, w: float, extra: Dictionary = {}) -> Dictionary:
	var d := {"k": "gift", "x": x, "y": y, "w": w, "rot": 0.0, "sy": 1.0, "a": 1.0}
	for key in extra:
		d[key] = extra[key]
	return d


static func _lid(x: float, y: float, w: float, rot: float) -> Dictionary:
	return {"k": "lid", "x": x, "y": y, "w": w, "rot": rot, "a": 1.0}


static func _say(text: String, x: float, y: float, s: float = 1.0) -> Dictionary:
	return {"k": "bubble", "text": text, "x": x, "y": y, "s": s}


static func _text(text: String, x: float, y: float, size: int, color: Color, s: float = 1.0) -> Dictionary:
	return {"k": "text", "text": text, "x": x, "y": y, "size": size, "color": color, "s": s}


static func _puff(x: float, y: float, r: float, a: float, color: Color = Color(0.1, 0.09, 0.14)) -> Dictionary:
	return {"k": "puff", "x": x, "y": y, "r": r, "a": a, "color": color}


static func _ring(x: float, y: float, r: float, a: float, color: Color) -> Dictionary:
	return {"k": "ring", "x": x, "y": y, "r": r, "a": a, "color": color}


static func _shake(amp: float) -> Dictionary:
	return {"k": "shake", "amp": amp}


# ---- easing -----------------------------------------------------------------------------------

## 0..1 progress of t across [a, b], clamped.
static func _u(t: float, a: float, b: float) -> float:
	return clampf((t - a) / (b - a), 0.0, 1.0)


static func _eo(u: float) -> float:
	return 1.0 - (1.0 - u) * (1.0 - u)


static func _ei(u: float) -> float:
	return u * u


## 0 -> 1 -> 0 parabola over u in 0..1 (a hop).
static func _hop(u: float) -> float:
	return 4.0 * u * (1.0 - u)


## A one-shot window: 1 inside [a, b], 0 outside, with a short ramp at both ends (bubble pop).
static func _pop(t: float, a: float, b: float) -> float:
	if t < a or t > b:
		return 0.0
	return minf(minf((t - a) / 0.12, (b - t) / 0.12), 1.0)


# ---- gag 1: the lead slips on its own glitched floor ------------------------------------------
# A: it strolls in, steps on the one glitching tile, and tumbles into the air. The "!" lands at 0.9.
# B: it flops flat, announces it meant to do that, gets up with dignity and leaves.

static func _toucher_slip(tt: float, cast: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if cast.size() < 1:
		return out
	var lead := cast[0]
	var tile_x := 660.0
	# the glitched tile: a floor decal that will not hold still
	var fl := "floor_0%d" % (int(tt * 14.0) % 5)
	out.append(_spr(lead, fl, tile_x + 5.0 * sin(tt * 41.0), GROUND_Y + 22.0, 74.0,
			{"shadow": false, "a": 0.95}))
	var x := 0.0
	var y := GROUND_Y
	var rot := 0.0
	var sy := 1.0
	var sx := 1.0
	var flip := true                       # the finger points where it walks
	var frame := "cycle_0%d" % (int(tt * 9.0) % 3)
	if tt < 0.85:                           # stroll in
		var u := _u(tt, 0.0, 0.85)
		x = lerpf(-160.0, tile_x - 30.0, u)
		y = GROUND_Y - 12.0 * absf(sin(tt * 15.0))
		rot = 0.07 * sin(tt * 15.0)
	elif tt < 1.55:                         # the slip: one full tumble through the air
		var u2 := _u(tt, 0.85, 1.55)
		x = lerpf(tile_x - 30.0, tile_x + 170.0, _eo(u2))
		y = GROUND_Y - 150.0 * _hop(u2) - 55.0
		rot = -TAU * _eo(u2)
		frame = "cycle_02"
	elif tt < 1.75:                         # splat, then flat on its back
		var u3 := _u(tt, 1.55, 1.75)
		x = tile_x + 170.0 + 25.0 * u3
		y = GROUND_Y - 55.0 * (1.0 - u3)
		rot = -TAU - 1.45 * _eo(u3)
		sy = 1.0 - 0.25 * _hop(u3)
		frame = "cycle_02"
	elif tt < 3.25:                         # lying there
		x = tile_x + 195.0
		y = GROUND_Y
		rot = -TAU - 1.45 + sin(tt * 23.0) * 0.015
		frame = "cycle_01"
	elif tt < 3.55:                         # gets up
		var u4 := _u(tt, 3.25, 3.55)
		x = tile_x + 195.0
		y = GROUND_Y - 30.0 * _hop(u4)
		rot = -TAU - 1.45 * (1.0 - _eo(u4))
	else:                                   # walks off, pretending nothing happened
		var u5 := _u(tt, 3.55, 4.9)
		x = lerpf(tile_x + 195.0, 1500.0, _ei(u5))
		y = GROUND_Y - 10.0 * absf(sin(tt * 11.0))
		rot = -TAU + 0.05 * sin(tt * 11.0)
	var tpos := Vector2(x, y)
	out.append(_spr(lead, frame, tpos.x, tpos.y - 70.0, 150.0,
			{"rot": rot, "sx": sx, "sy": sy, "flip": flip, "p": 0.5, "shadow": true}))
	if tt >= 0.9 and tt < 1.5:
		out.append(_text("!", x, GROUND_Y - 300.0, 70, RED, _pop(tt, 0.9, 1.5)))
	if tt >= 1.7 and tt < 3.3:
		out.append(_say("i meant to do that.", x, GROUND_Y - 170.0, _pop(tt, 1.7, 3.3)))
	return out


# ---- gag 2: the pup gets its head stuck in a gift box ------------------------------------------
# The art is a white pup lying on its belly, facing the camera, head at the left of its
# sprite. So it never turns round (a mirror flip would teleport the box across the sprite); it
# belly-scoots, head first. A: it scoots in looking straight at the camera, a black gift drops over its face
# (the box is wider than the head), "mfph!". B: it scoots blind back and forth, rates the box, leaves
# with it on.

static func _seal_x(tt: float) -> float:
	if tt < 1.0:
		return lerpf(1450.0, 780.0, _eo(_u(tt, 0.0, 1.0)))
	if tt < 3.9:
		return 780.0 + 120.0 * sin((tt - 1.0) * 3.0)
	return lerpf(780.0 + 120.0 * sin(2.9 * 3.0), -380.0, _ei(_u(tt, 3.9, 5.0)))


static func _seal_giftbox(tt: float, cast: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if cast.size() < 1:
		return out
	var lead := cast[0]
	var h := 170.0
	var sx_pos := _seal_x(tt)
	var frame := "idle_0%d" % (int(tt * 6.0) % 2)
	var rot := 0.0
	var y := GROUND_Y
	var sy := 1.0
	var sxs := 1.0
	# belly scoot: the body humps up and stretches out once per scoot (no legs to waddle on)
	var scoot := sin(tt * 14.0)
	if tt < 1.0 or tt >= 3.9:
		sy = 1.0 + 0.05 * scoot
		sxs = 1.0 - 0.04 * scoot
		y = GROUND_Y - 3.0 * absf(scoot)
	else:
		rot = 0.06 * sin(tt * 17.0)               # blind
		sy = 1.0 + 0.07 * scoot
		sxs = 1.0 - 0.05 * scoot
		y = GROUND_Y - 5.0 * absf(scoot)
	if tt >= 0.95 and tt < 1.15:               # the box lands: squash
		var us := _u(tt, 0.95, 1.15)
		sy = 1.0 - 0.18 * _hop(us)
		sxs = 1.0 + 0.1 * _hop(us)
	out.append(_spr(lead, frame, sx_pos, y, h, {"rot": rot, "sy": sy, "sx": sxs, "p": 0.0}))
	# the box: falls from above onto the face (0.55-0.95), then rides it. The face is ~70 px left of
	# the sprite centre; the box sits on the ground so it hides the whole head.
	var bx := sx_pos - 70.0
	var by := GROUND_Y
	var brot := rot
	if tt < 0.95:
		if tt < 0.55:
			return out
		var uf := _u(tt, 0.55, 0.95)
		by = lerpf(-160.0, by, _ei(uf))
		brot = 0.3 * (1.0 - uf)
	elif tt < 1.15:
		by -= 14.0 * _hop(_u(tt, 0.95, 1.15))
	out.append(_gift(bx, by, 125.0, {"rot": brot}))
	if tt >= 1.2 and tt < 2.3:
		out.append(_say("mfph!", bx, by - 165.0, _pop(tt, 1.2, 2.3)))
	if tt >= 2.7 and tt < 4.1:
		out.append(_say("10/10. keeping the box.", bx, by - 165.0, _pop(tt, 2.7, 4.1)))
	return out


# ---- gag 3: the spring-loaded one launches itself into the void ---------------------------------
# A: winds up, BOING, gone - straight off the top of the screen.
# B: comes back down somewhere else, bounces, says it was worth it, and goes again.

static func _coil_launch(tt: float, cast: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if cast.size() < 1:
		return out
	var lead := cast[0]
	var h := 210.0
	if tt < 1.15:
		var x := 640.0
		var pop := _eo(_u(tt, 0.0, 0.2))
		var sx := pop
		var sy := pop
		var y := GROUND_Y
		if tt >= 0.2 and tt < 0.85:             # wind-up: squash, shake
			var uw := _eo(_u(tt, 0.2, 0.85))
			sy = 1.0 - 0.5 * uw
			sx = 1.0 + 0.45 * uw
			x += 5.0 * uw * sin(tt * 70.0)
		elif tt >= 0.85:                        # launch
			var ul := _ei(_u(tt, 0.85, 1.15))
			y = GROUND_Y - ul * 1000.0
			sy = 1.8
			sx = 0.65
			for g in 3:
				var ga := 0.32 - 0.1 * float(g)
				out.append(_spr(lead, "cycle_00", x, y + 80.0 * float(g + 1), h,
						{"sx": sx, "sy": sy, "a": ga, "shadow": false}))
		out.append(_spr(lead, "cycle_00", x, y, h, {"sx": sx, "sy": sy}))
		if tt >= 0.85:
			out.append(_text("BOING", 640.0, 250.0, 84, CYAN, _pop(tt, 0.85, 1.5)))
	if tt >= 1.55 and tt < 2.9:
		out.append(_say("ok. that went well.", 640.0, GROUND_Y - 40.0, _pop(tt, 1.55, 2.9)))
	if tt >= 2.9 and tt < 4.75:
		var lx := 900.0
		if tt < 3.5:                            # falls back in, spinning
			var uf := _u(tt, 2.9, 3.5)
			out.append(_spr(lead, "cycle_00", lx, lerpf(-260.0, GROUND_Y, _ei(uf)), h,
					{"rot": TAU * 3.0 * uf, "p": 0.5}))
		else:                                    # lands: damped spring
			var k := tt - 3.5
			var sy2 := 1.0 - 0.45 * exp(-5.0 * k) * cos(22.0 * k)
			var sx2 := 1.0 / sqrt(sy2)
			var fade := 1.0 - _u(tt, 4.55, 4.75)
			out.append(_spr(lead, "cycle_00", lx, GROUND_Y, h, {"sx": sx2 * fade, "sy": sy2 * fade}))
			if tt >= 3.65 and tt < 4.6:
				out.append(_say("worth it.", lx, GROUND_Y - 260.0, _pop(tt, 3.65, 4.6)))
	return out


# ---- gag 4: the cat meets a gift that is not a gift ----------------------------------------------
# A: the cat floats up to a black gift, the gift pops its lid and an impostor springs out - the cat
#    leaves at speed.
# B: the impostor tries to act natural, the lid drops back, the cat peeks in, the box hops.

static func _kiwi_larper(tt: float, cast: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if cast.size() < 2:
		return out
	var cat := cast[0]
	var impostor := cast[1]
	var bx := 900.0
	var box_w := 150.0
	var box_y := GROUND_Y
	var lid_on := true
	var lid_y := 0.0
	var lid_rot := 0.0
	if tt >= 1.35 and tt < 1.6:
		box_y -= 40.0 * _hop(_u(tt, 1.35, 1.6))
	if tt >= 4.6 and tt < 4.9:
		box_y -= 30.0 * _hop(_u(tt, 4.6, 4.9))
	# lid: off from 1.6 (flies up and away), back on at 3.4-3.9 (falls onto the box)
	var lid_rest := box_y - box_w * 0.88
	if tt >= 1.6 and tt < 3.4:
		lid_on = false
		var ul := _u(tt, 1.6, 2.4)
		lid_y = lerpf(lid_rest, lid_rest - 230.0, _eo(ul))
		if tt > 2.4:
			lid_y = lid_rest - 230.0 + 0.0
		lid_rot = 5.0 * _eo(ul)
	elif tt >= 3.4 and tt < 3.9:
		lid_on = false
		var ud := _u(tt, 3.4, 3.9)
		lid_y = lerpf(lid_rest - 230.0, lid_rest, _ei(ud))
		lid_rot = 5.0 * (1.0 - ud)
	out.append(_gift(bx, box_y, box_w))
	# the Larper inside: grows out of the box at 1.6-1.9, turns once per 4.0 s, sinks back 3.7-3.9
	var lg := _eo(_u(tt, 1.6, 1.9)) * (1.0 - _u(tt, 3.7, 3.95))
	if lg > 0.0:
		out.append(_spr(impostor, "cycle_00", bx, box_y - box_w * 0.5 - 95.0 * lg, 200.0,
				{"rot": tt * TAU / 4.0, "p": 0.5, "sx": lg, "sy": lg, "shadow": false}))
	if not lid_on:
		out.append(_lid(bx + 30.0 * lg, lid_y, box_w, lid_rot))
	else:
		out.append(_lid(bx, lid_rest, box_w, 0.0))
	# the cat
	var h := 170.0
	var hover := 112.0 + 12.0 * sin(tt * 5.0)
	var cx := -300.0
	var flip := true
	var rot := 0.0
	var cy := GROUND_Y - hover
	var visible := true
	if tt < 1.0:
		cx = lerpf(-280.0, 520.0, _eo(_u(tt, 0.0, 1.0)))
	elif tt < 1.8:
		cx = 520.0
		rot = 0.14 * _eo(_u(tt, 1.0, 1.35))
	elif tt < 2.6:                              # runs for it, the way it came
		var uf := _u(tt, 1.8, 2.6)
		cx = lerpf(520.0, -420.0, _ei(uf))
		flip = false
		cy -= 40.0 * _hop(_u(tt, 1.8, 2.05))
		rot = -0.1
	elif tt >= 4.1 and tt < 5.0:                # peeks back in from the left edge
		var up := _u(tt, 4.1, 4.4)
		var down := _u(tt, 4.75, 5.0)
		cx = lerpf(-220.0, 120.0, _eo(up)) - 340.0 * _ei(down)
		flip = true
	else:
		visible = false
	if visible:
		out.append(_spr(cat, "cycle_00", cx, cy, h, {"rot": rot, "flip": flip}))
	if tt >= 1.05 and tt < 1.75:
		out.append(_text("?", cx, cy - 150.0, 70, RED, _pop(tt, 1.05, 1.75)))
	if tt >= 1.8 and tt < 2.3:
		out.append(_text("!", cx + 10.0, cy - 150.0, 80, RED, _pop(tt, 1.8, 2.3)))
	if tt >= 2.4 and tt < 3.5:
		out.append(_say("act natural.", bx, GROUND_Y - 280.0, _pop(tt, 2.4, 3.5)))
	if tt >= 4.35 and tt < 5.0:
		out.append(_say("...is it gone?", cx + 120.0, cy - 110.0, _pop(tt, 4.35, 5.0)))
	return out


# ---- gag 5: the teleporter teleports ... and launches itself ------------------------------------
# A: smoke marks the destination, the chime, it arrives and the arrival launch sends it through the
#    top of the screen.
# B: it comes back down, the whole stage shakes, "ow.", and it teleports out.

static func _ben_bonk(tt: float, cast: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if cast.size() < 1:
		return out
	var lead := cast[0]
	var h := 300.0
	var dest_x := 300.0
	var home_x := 950.0
	# the smoke at the destination (the telegraph): 0.15 - 1.3 s, grows then lingers
	if tt >= 0.15 and tt < 2.0:
		var us := _u(tt, 0.15, 1.0)
		var fade := 1.0 - _u(tt, 1.6, 2.0)
		for i in 5:
			var ox := (float(i) - 2.0) * 34.0
			out.append(_puff(dest_x + ox, GROUND_Y - 30.0 - 16.0 * float(i % 2), 50.0 * _eo(us), 0.85 * fade))
	if tt >= 0.7 and tt < 1.3:
		out.append(_text("BONG", dest_x, 210.0, 90, Color(1.0, 0.85, 0.3), _pop(tt, 0.7, 1.3)))
	# ben at home: appears, then vanishes into the smoke
	if tt < 1.05:
		var grow := _eo(_u(tt, 0.0, 0.2)) * (1.0 - _u(tt, 0.9, 1.05))
		out.append(_spr(lead, "cycle_00", home_x, GROUND_Y, h, {"sx": grow, "sy": grow}))
	# arrival at the destination, ring, then the launch
	if tt >= 1.15 and tt < 1.5:
		var ua := _u(tt, 1.15, 1.3)
		var sy := 0.85 + 0.15 * _eo(ua)
		out.append(_spr(lead, "cycle_00", dest_x, GROUND_Y, h, {"sx": _eo(ua), "sy": sy * _eo(ua)}))
		out.append(_ring(dest_x, GROUND_Y, 260.0 * _u(tt, 1.15, 1.6), 0.8 * (1.0 - _u(tt, 1.15, 1.6)), CYAN))
	elif tt >= 1.5 and tt < 1.95:
		var ul := _ei(_u(tt, 1.5, 1.95))
		out.append(_spr(lead, "cycle_00", dest_x, GROUND_Y - ul * 1100.0, h, {"sx": 0.9, "sy": 1.12}))
	if tt >= 1.85 and tt < 2.7:
		out.append(_text("BONK", dest_x, 70.0, 80, RED, _pop(tt, 1.85, 2.7)))
	# B: the fall
	if tt >= 2.95 and tt < 4.5:
		var land := 3.5
		if tt < land:
			var uf := _ei(_u(tt, 2.95, land))
			out.append(_spr(lead, "cycle_00", dest_x, lerpf(-420.0, GROUND_Y, uf), h,
					{"sx": 0.92, "sy": 1.1}))
		else:
			var k := tt - land
			var sy2 := 1.0 - 0.25 * exp(-6.0 * k) * cos(20.0 * k)
			out.append(_spr(lead, "cycle_00", dest_x, GROUND_Y, h, {"sx": 1.0 / sqrt(sy2), "sy": sy2}))
			out.append(_shake(14.0 * exp(-7.0 * k)))
			if k < 0.5:
				for i in 4:
					var dir := -1.0 if i % 2 == 0 else 1.0
					out.append(_puff(dest_x + dir * (70.0 + 120.0 * k * float(i + 1)), GROUND_Y - 10.0,
							26.0 * (1.0 - k), 0.6 * (1.0 - 2.0 * k), Color(0.35, 0.3, 0.4)))
		if tt >= 3.65 and tt < 4.5:
			out.append(_say("ow.", dest_x + 150.0, GROUND_Y - 230.0, _pop(tt, 3.65, 4.5)))
	# the exit: teleports away in a puff
	if tt >= 4.5 and tt < 5.0:
		var ux := _u(tt, 4.5, 4.7)
		out.append(_spr(lead, "cycle_00", dest_x, GROUND_Y, h,
				{"sx": 1.0 - ux, "sy": 1.0 - ux, "a": 1.0 - ux}))
		out.append(_puff(dest_x, GROUND_Y - 120.0, 120.0 * _eo(ux), 0.8 * (1.0 - _u(tt, 4.7, 5.0))))
	return out
