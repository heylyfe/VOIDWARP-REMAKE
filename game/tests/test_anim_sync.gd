extends RefCounted
#
# test_anim_sync.gd - ticket T-084: the animation player and telegraph sync.
#
# For each of the 12 enemies, a scripted sim drives view/enemy_anim.gd one 60 Hz tick at
# a time and asserts, with 0 ticks of error:
#   1. every telegraph state lasts exactly its DESIGN.md binding tick count (the counts
#      below are this test's own transcription of DESIGN.md sections 5.1-5.12 - if the
#      anim blocks drift from DESIGN.md, this fails);
#   2. on the tick the attack event fires, the frame shown is the attack frame - the
#      state switch and the frame land on the same sim tick, never one tick late;
#   3. the billboard normal faces the camera from 8 angles in every state (BILLBOARDING);
#   4. a probe in the transparent padding of the CURRENT frame never hits, and a probe
#      on a body pixel of the frame does, when the frame has one (HITBOXES + TRANSPARENCY);
#   5. the hit shape follows the body_rect of the frame SHOWN (coil: extended in flight,
#      squashed 1.0 u on landing);
#   6. the spawn fade blocks contact (30 ticks; address me's own 12-tick fade per its
#      [CONTESTABLE] table row);
#   7. effects are computed as shader parameter values from the sim tick (kiwi's pulse
#      peaks 1.12 at tick 6 of 12; ben's white flash dies by tick 6; isagi's recover
#      dim is 0.7; YOU-ish rumble shakes 0.05 u).

const EnemyAnim := preload("res://view/enemy_anim.gd")
const Billboard := preload("res://view/billboard.gd")

const ENEMIES := ["kiwi_cat", "coil", "thicc_ben", "isagi", "nuke", "you",
		"gift_larper", "toucher", "seal", "address_me", "claude", "gin"]

# Binding telegraph tick counts, transcribed from DESIGN.md sections 5.1-5.12 (the
# seconds of the "cue TIMINGS are binding" rule, times 60). nuke has two telegraph
# states (tracking 150 + locked 90); gift Larper has none - its tell is the look.
const TELEGRAPH := {
	"kiwi_cat": {"telegraph": 12},
	"coil": {"telegraph": 36},
	"thicc_ben": {"telegraph": 75},
	"isagi": {"telegraph": 72},
	"nuke": {"telegraph_tracking": 150, "telegraph_locked": 90},
	"you": {"telegraph": 90},
	"gift_larper": {},
	"toucher": {"telegraph": 18},
	"seal": {"telegraph": 45},
	"address_me": {"telegraph": 300},
	"claude": {"telegraph_strings": 36},
	"gin": {"telegraph": 120},
}

# The scripted sim walks each enemy's states in this order (the order of its DESIGN.md
# section 5.x table, matching section 1's tables). nuke has no spawn state (no sprite);
# gift Larper has no spawn fade (present from level start).
const ORDER := {
	"kiwi_cat": ["spawn", "idle_chase", "telegraph", "attack", "recover"],
	"coil": ["spawn", "idle", "telegraph", "attack_flight", "attack_landing", "recover"],
	"thicc_ben": ["spawn", "idle", "telegraph", "attack_arrival", "attack_ring", "recover"],
	"isagi": ["spawn", "idle", "telegraph", "attack", "recover"],
	"nuke": ["telegraph_tracking", "telegraph_locked", "attack_descent", "attack_explosion", "recover"],
	"you": ["spawn", "idle_chase", "telegraph", "attack", "recover"],
	"gift_larper": ["idle", "attack_detonation", "defused"],
	"toucher": ["spawn", "idle_chase", "telegraph", "attack_infect", "recover"],
	"seal": ["spawn", "idle_flap", "telegraph", "attack", "recover"],
	"address_me": ["spawn", "telegraph", "attack", "leaves"],
	"claude": ["spawn", "idle", "telegraph_strings", "attack_strings"],
	"gin": ["spawn", "idle", "telegraph", "attack_launch", "attack_void_zone", "recover"],
}

# The sim tick (local to the state) on which the attack event fires, per state. The
# kill resolves on the entry tick of the attack state - the attack frame must already
# be showing on that very tick.
const FIRE_ON := {
	"kiwi_cat": {"attack": 0},
	"coil": {"attack_landing": 0},
	"thicc_ben": {"attack_arrival": 0},
	"isagi": {"attack": 0},
	"nuke": {"attack_explosion": 0},
	"you": {"attack": 0},
	"gift_larper": {"attack_detonation": 0},
	"toucher": {"attack_infect": 0},
	"seal": {"attack": 0},
	"address_me": {"attack": 0},
	"claude": {"attack_strings": 0},
	"gin": {"attack_launch": 0},
}

# Extra attack events inside one attack state: isagi's balls leave on ticks 72, 81, 90
# (attack-local 0, 9, 18) - each is an event tick, the shoot frame holds through all.
const EXTRA_FIRE := {
	"isagi": {"attack": [9, 18]},
}

# How many ticks the scripted sim runs per non-telegraph, non-attack state (binding
# counts are asserted for telegraphs; long states are sampled, not run to the end).
const SAMPLE_TICKS := 5


func run() -> Array[String]:
	var f: Array[String] = []
	for eid in ENEMIES:
		var doc := _load_doc(f, eid)
		if doc.is_empty():
			continue
		var p = EnemyAnim.new()
		p.setup(eid, doc, "res://content/enemies/" + eid)
		var before := f.size()
		_check_order_exists(f, eid, p)
		if f.size() > before:
			continue
		_drive(f, eid, p)
		_spot_effects(f, eid, doc)
	_coil_hitbox_story(f)
	return f


func _load_doc(f: Array[String], eid: String) -> Dictionary:
	var path := "res://content/enemies/%s/sprites.json" % eid
	var txt := FileAccess.get_file_as_string(path)
	if txt == "":
		f.append("%s: cannot read %s" % [eid, path])
		return {}
	var doc = JSON.parse_string(txt)
	if doc == null or not (doc is Dictionary) or not (doc as Dictionary).has("anim"):
		f.append("%s: %s is not a sprites.json with an anim block" % [eid, path])
		return {}
	return doc


func _check_order_exists(f: Array[String], eid: String, p) -> void:
	for s in ORDER[eid]:
		if not p.has_state(s):
			f.append("%s: anim block has no state %s (scripted order drives it)" % [eid, s])
	for s in TELEGRAPH[eid].keys():
		if not p.has_state(s):
			f.append("%s: anim block has no telegraph state %s" % [eid, s])


## Drives one enemy through its scripted sim, one 60 Hz tick at a time.
func _drive(f: Array[String], eid: String, p) -> void:
	var b = Billboard.new()
	b.position = Vector3(0.5, 0.0, 0.5)
	var sim_tick := 0
	var held := ""                # the last frame name actually shown
	var body_checked := false
	for s in ORDER[eid]:
		p.on_state_changed(s)
		if p.state_id != s:
			f.append("%s: player did not enter state %s (stayed on %s)" % [eid, s, p.state_id])
			continue
		# (1) telegraph duration: the block's total must equal the DESIGN.md binding count,
		# and the scripted sim runs exactly that many ticks in the state.
		if TELEGRAPH[eid].has(s):
			var tot := _total_of(p, s)
			if tot != int(TELEGRAPH[eid][s]):
				f.append("%s/%s: total_ticks %d, DESIGN.md binding is %d" % [eid, s, tot, TELEGRAPH[eid][s]])
		var n := _run_length(p, s)
		var fires: Array = []
		if FIRE_ON[eid].has(s):
			fires.append(int(FIRE_ON[eid][s]))
		var extra: Dictionary = EXTRA_FIRE.get(eid, {})
		if extra.has(s):
			for x in extra[s]:
				fires.append(int(x))
		for i in range(n):
			var expected := _expected_frame_at(p, s, i)
			var got: String = p.frame_name()   # ticks_in_state == i at this point
			if expected == "":
				if got != held:
					f.append("%s/%s t%d: frame %s but the state has no frames - %s must be held" % [eid, s, i, got, held])
			elif got != expected:
				f.append("%s/%s t%d: frame %s, want %s" % [eid, s, i, got, expected])
			if fires.has(i):
				# (2) the attack frame is the frame shown on the tick the event fires
				p.attack_event(sim_tick)
				if p.last_attack_tick != sim_tick:
					f.append("%s/%s t%d: attack event not recorded on tick %d" % [eid, s, i, sim_tick])
				if p.last_attack_frame != p.frame_index():
					f.append("%s/%s t%d: recorded attack frame %d != shown %d" % [eid, s, i, p.last_attack_frame, p.frame_index()])
			# (6) the spawn fade blocks contact (checked at tick i, before the advance)
			if s == "spawn":
				if p.contact_blocked() != (i < _fade_ticks(p)):
					f.append("%s/spawn t%d: contact_blocked %s, want %s (fade %d ticks)" % [eid, i, p.contact_blocked(), i < _fade_ticks(p), _fade_ticks(p)])
			# (4) a probe in the transparent padding of the CURRENT frame never hits
			if p.probe_hits(Vector2i(2, 2)):
				f.append("%s/%s t%d: probe (2,2) hit - transparent padding must never hit" % [eid, s, i])
			if not body_checked:
				body_checked = _body_probe_once(f, eid, p)
			p.sim_tick()
			if got != "":
				held = got
			sim_tick += 1
		# (3) the billboard normal faces the camera from 8 angles in every state
		_check_billboard(f, eid, s, b)
	b.free()


func _total_of(p, s: String) -> int:
	var v = p.states().get(s, {}).get("total_ticks")
	return -1 if v == null else int(v)


func _run_length(p, s: String) -> int:
	var t := _total_of(p, s)
	if s.begins_with("telegraph"):
		return t if t > 0 else 1
	var sp: Dictionary = p.states().get(s, {})
	var ranges = sp.get("tick_ranges")
	var has_ranges: bool = ranges != null and not (ranges as Array).is_empty()
	if t > 0 and (has_ranges or t <= 90):
		return t
	if t > 0:
		return 90
	return SAMPLE_TICKS


## The frame the state shows at local tick t - the test's own reading of the anim
## block (tick_ranges first, else ticks_per_frame; loop wraps, one-shot holds).
func _expected_frame_at(p, s: String, t: int) -> String:
	var sp: Dictionary = p.states().get(s, {})
	var sf: Array = sp.get("spec_frames", [])
	if sf.is_empty():
		return ""
	var ranges = sp.get("tick_ranges")
	if ranges != null and not (ranges as Array).is_empty():
		var last := ""
		for r in ranges:
			if t >= int(r[1]) and t <= int(r[2]):
				return str(r[0])
			last = str(r[0])
		return last
	var v = sp.get("ticks_per_frame")
	if v == null:
		return str(sf[0])
	var tpf := float(v)
	if tpf <= 0.0:
		return str(sf[0])
	var idx := int(floor(float(t) / tpf))
	if bool(sp.get("loop", false)):
		idx = idx % sf.size()
	else:
		idx = mini(idx, sf.size() - 1)
	return str(sf[idx])


## The spawn fade length the block declares (default 30, the section 1.0 common fade).
func _fade_ticks(p) -> int:
	var sp: Dictionary = p.states().get("spawn", {})
	var eff: Dictionary = sp.get("effect", {}) if sp.get("effect") != null else {}
	var params: Dictionary = eff.get("params", {}) if eff.get("params") != null else {}
	for k in ["spawn_blocks_contact_ticks", "duration_ticks", "ticks"]:
		if params.has(k) and (params[k] is float or params[k] is int):
			return int(params[k])
	return 30


## (3) BILLBOARDING in every state: after face_camera() the sprite normal (+Z basis)
## opposed the camera's forward from all 8 angles, normal . forward <= -0.999.
func _check_billboard(f: Array[String], eid: String, s: String, b) -> void:
	for i in range(8):
		var ang := float(i) * PI / 4.0
		var cam: Vector3 = b.position + Vector3(sin(ang), 0.0, cos(ang)) * 4.0
		b.face_camera(cam)
		var nrm: Vector3 = b.transform.basis.z
		var fwd: Vector3 = (b.position - cam).normalized()
		if nrm.dot(fwd) > -0.999:
			f.append("%s/%s: billboard normal faces away at angle %d (dot %.4f)" % [eid, s, i, nrm.dot(fwd)])


## (4) positive half of the probe rule: a body pixel (alpha > 16) inside the body_rect
## of the frame SHOWN does register a hit. Returns true when a body pixel was found.
func _body_probe_once(f: Array[String], eid: String, p) -> bool:
	var br: Array = p.body_rect()
	if br.is_empty():
		return false
	var tex = p.frame_texture()
	if tex == null:
		return false
	var img: Image = tex.get_image()
	if img == null:
		return false
	if img.is_compressed():
		img.decompress()
	var y := int(br[1])
	while y < int(br[1]) + int(br[3]):
		var x := int(br[0])
		while x < int(br[0]) + int(br[2]):
			if int(img.get_pixel(x, y).a * 255.0) > 16:
				if not p.probe_hits(Vector2i(x, y)):
					f.append("%s: body pixel (%d,%d) inside body_rect did not hit" % [eid, x, y])
				return true
			x += 4
		y += 4
	return false


## (7) effects come out as shader parameter values computed from the sim tick. Runs on
## a fresh player so the driven timeline above stays untouched.
func _spot_effects(f: Array[String], eid: String, doc: Dictionary) -> void:
	var p = EnemyAnim.new()
	p.setup(eid, doc, "res://content/enemies/" + eid)
	if eid == "kiwi_cat":
		p.on_state_changed("telegraph")
		var e: Dictionary = p.effect_params()
		for k in ["flash", "tint", "scale_pulse", "shake", "alpha"]:
			if not e.has(k):
				f.append("kiwi_cat/telegraph: effect_params is missing %s" % k)
		if absf(float(e["scale_pulse"]) - 1.0) > 1e-6:
			f.append("kiwi_cat/telegraph t0: pulse %s, want 1.0" % str(e["scale_pulse"]))
		for i in range(6):
			p.sim_tick()
		if absf(float(p.effect_params()["scale_pulse"]) - 1.12) > 1e-6:
			f.append("kiwi_cat/telegraph t6: pulse %s, want the 1.12 peak" % str(p.effect_params()["scale_pulse"]))
		for i in range(6):
			p.sim_tick()
		if absf(float(p.effect_params()["scale_pulse"]) - 1.0) > 1e-6:
			f.append("kiwi_cat/telegraph t12: pulse %s, want 1.0 (cue exact)" % str(p.effect_params()["scale_pulse"]))
	if eid == "thicc_ben":
		p.on_state_changed("attack_arrival")
		if float(p.effect_params()["flash"].a) < 0.999:
			f.append("thicc_ben/attack_arrival t0: flash alpha %s, want full white" % str(p.effect_params()["flash"].a))
		for i in range(6):
			p.sim_tick()
		if float(p.effect_params()["flash"].a) != 0.0:
			f.append("thicc_ben/attack_arrival t6: flash alpha %s, want 0 (6-tick flash)" % str(p.effect_params()["flash"].a))
	if eid == "isagi":
		p.on_state_changed("recover")
		var e: Dictionary = p.effect_params()
		if absf(float(e["tint"].r) - 0.7) > 1e-6:
			f.append("isagi/recover: tint %s, want the 0.7 cannot-fire dim" % str(e["tint"].r))
	if eid == "you":
		p.on_state_changed("telegraph")
		var e: Dictionary = p.effect_params()
		if absf(float(e["shake"].x)) < 1e-6 or absf(float(e["shake"].x)) > 0.05 + 1e-6:
			f.append("you/telegraph: shake %s, want the 0.05 u rumble" % str(e["shake"]))
	if eid == "toucher":
		p.on_state_changed("telegraph")
		if absf(float(p.effect_params()["scale_pulse"]) - 1.0) > 1e-6:
			f.append("toucher/telegraph t0: pulse %s, want 1.0" % str(p.effect_params()["scale_pulse"]))
		for i in range(9):
			p.sim_tick()
		if absf(float(p.effect_params()["scale_pulse"]) - 1.15) > 1e-6:
			f.append("toucher/telegraph t9: pulse %s, want the 1.15 ramp mid" % str(p.effect_params()["scale_pulse"]))


## (5) HITBOXES: the hit shape follows the body_rect of the frame SHOWN. Coil's landing
## is the squashed frame (1.0 u, SR-2); mid-flight it shows the extended coil_03 body.
func _coil_hitbox_story(f: Array[String]) -> void:
	var doc := _load_doc(f, "coil")
	if doc.is_empty():
		return
	var p = EnemyAnim.new()
	p.setup("coil", doc, "res://content/enemies/coil")
	p.on_state_changed("attack_flight")
	for i in range(20):
		p.sim_tick()
	var h_flight: Dictionary = p.hit_shape()
	p.on_state_changed("attack_landing")
	var h_land: Dictionary = p.hit_shape()
	if h_flight.is_empty() or h_land.is_empty():
		f.append("coil: hit_shape empty (flight %s, landing %s)" % [h_flight, h_land])
		return
	if absf(float(h_flight["height"]) - 1.714) > 0.02:
		f.append("coil/attack_flight t20: hit height %s, want the coil_03 body 1.714 u" % str(h_flight["height"]))
	if absf(float(h_land["height"]) - 1.0) > 0.02:
		f.append("coil/attack_landing: hit height %s, want the squashed coil_00 body 1.0 u" % str(h_land["height"]))
	if float(h_land["diameter"]) <= 0.0:
		f.append("coil/attack_landing: hit diameter %s, want 0.8 x body width" % str(h_land["diameter"]))



