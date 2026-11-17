extends RefCounted
#
# enemy_anim.gd - the per-enemy animation player and telegraph sync (ticket T-084).
#
# VIEW LAYER: it reads the simulation's state names and tick counters and never runs a
# wall-clock or frame timer of its own. The frame shown at any instant comes from the
# anim block (T-083 shape, content/enemies/<id>/sprites.json "anim") and the sim tick
# counter of the state, exactly as research/fable-tickets.md section 1.0 states:
#
#     frame = table[state][ (ticks_in_state * fps) / 60 ]
#
# which in the block's units is simply: index = ticks_in_state / ticks_per_frame, or the
# tick_ranges row containing ticks_in_state when the state declares explicit ranges
# (e.g. the spring flight: cycle_03 0-20, cycle_04 21-144, cycle_03 145-164). Because the
# advance is a pure function of (state, ticks_in_state), the telegraph animation fills
# its cue exactly and the attack frame is the frame shown on the tick the attack event
# fires - 0 ticks of error, no lerping, no catch-up.
#
# Effects that are not frames (flash, tint, scale pulse, shake, alpha) are computed as
# shader parameter values (effect_params()) and pushed to the billboard; they never
# change which frame is shown and never change body_rect, so the hit shape always
# follows the body_rect of the frame SHOWN (ENEMIES.md HITBOXES). A probe in the
# transparent padding of the current frame never hits (TRANSPARENCY: only pixels with
# alpha > BODY_ALPHA_MIN and inside body_rect are body).
#
# Spawn fade: a spawn state blocks contact for 30 ticks (SPAWN_FADE_TICKS, section 1.0
# common fade; a state's fade params may carry spawn_blocks_contact_ticks to state it
# explicitly). The diegetic spawn text is billboard.gd's job (T-027); this player only
# owns frames, effects and the hit shape.

const TICKS_PER_SECOND := 60
const SPAWN_FADE_TICKS := 30        # the common fade is 0.50 s (section 1.0)
const BODY_ALPHA_MIN := 16          # HITBOXES: body pixels have alpha > 16
const HIT_WIDTH_FRACTION := 0.8     # hit cylinder diameter = 0.8 x body width (HITBOXES)

# Default effect values, used only when a state's effect params omit them. Every number
# here is one the section tables state for at least one enemy (never invented).
const DEFAULTS := {
	"common_fade": {"alpha_from": 0.0, "alpha_to": 1.0, "scale_from": 0.8, "scale_to": 1.0, "ticks": SPAWN_FADE_TICKS},
	"scale_pulse": {"from": 1.0, "peak": 1.12, "to": 1.0, "ticks": 12},
	"white_flash": {"ticks": 6},
	"dim": {"brightness": 0.7},
}

var enemy_id := ""
var doc: Dictionary = {}            # the parsed sprites.json
var folder_dir := ""                # the enemy folder as a res:// path
var state_id := ""                  # the state the sim says is playing
var ticks_in_state := 0             # the sim's tick counter for the current state
var last_attack_tick := -1          # the sim tick of the last attack event
var last_attack_frame := -1         # the frame index shown on that tick
var last_named_frame := ""          # the last frame name actually shown (held across frame-less states)
var view = null                     # duck-typed billboard (billboard.gd) or null

var _tex_cache: Dictionary = {}     # disk path -> Texture2D (loaded once)
var _img_cache: Dictionary = {}     # disk path -> Image (decoded once)
var _frame_docs: Dictionary = {}    # disk path -> {body_rect, world_height} from the sheet


## Binds the player to one enemy. doc is the parsed sprites.json (it must carry the
## T-083 anim block; the T-016 animations list is used for body_rect/world_height).
func setup(p_enemy_id: String, p_doc: Dictionary, p_folder_dir: String) -> void:
	enemy_id = p_enemy_id
	doc = p_doc
	folder_dir = p_folder_dir
	state_id = ""
	ticks_in_state = 0
	last_attack_tick = -1
	last_attack_frame = -1
	last_named_frame = ""
	_build_frame_docs()


func bind_view(p_view) -> void:
	view = p_view


func _build_frame_docs() -> void:
	_frame_docs.clear()
	var dw = doc.get("world_height", 1.0)
	var default_h: float = float(dw) if (dw is float or dw is int) else 1.0
	for a in doc.get("animations", []):
		var frames: Array = a.get("frames", [])
		var rects: Array = a.get("body_rect", [])
		var wh = a.get("world_height", null)
		var per_frame: bool = wh is Array
		for i in range(frames.size()):
			var meta := {}
			if i < rects.size() and rects[i] is Array and (rects[i] as Array).size() == 4:
				meta["body_rect"] = rects[i]
			# per-frame world_height (e.g. 1.0 -> 2.0), a scalar for every frame,
			# or the doc default
			if per_frame and i < (wh as Array).size() and ((wh as Array)[i] is float or (wh as Array)[i] is int):
				meta["world_height"] = float((wh as Array)[i])
			elif wh is float or wh is int:
				meta["world_height"] = float(wh)
			else:
				meta["world_height"] = default_h
			_frame_docs[str(frames[i])] = meta


# ---- state machine (driven by the sim, never by a timer) --------------------------------------


func states() -> Dictionary:
	return doc.get("anim", {}).get("states", {})


func has_state(p_state: String) -> bool:
	return states().has(p_state)


## The sim announces the current state. Resets that state's tick counter and shows the
## frame at tick 0 immediately (this is what makes an attack frame land on its event
## tick with 0 ticks of error: state change and frame pick are the same tick).
func on_state_changed(p_state: String) -> void:
	if not has_state(p_state):
		return                       # not this enemy's state (e.g. a spawn state): keep current
	state_id = p_state
	ticks_in_state = 0
	_sync_view()


## One simulation tick (60 Hz) inside the current state. Pure function of the counter.
func sim_tick() -> void:
	ticks_in_state += 1
	_sync_view()


## The gameplay layer reports the attack event on the tick it fires. The frame shown is
## whatever the state table says for THAT tick - recorded so tests can prove 0 error.
## Returns the frame index shown on the event tick.
func attack_event(p_sim_tick: int) -> int:
	last_attack_tick = p_sim_tick
	last_attack_frame = frame_index()
	_sync_view()
	return last_attack_frame


# ---- frames ------------------------------------------------------------------------------------


## The state spec dictionary (empty when the state is unknown).
func spec() -> Dictionary:
	if state_id == "":
		return {}
	return states().get(state_id, {})


## Frame index from the tick counter. tick_ranges win over ticks_per_frame; a looping
## state wraps, a one-shot holds its last frame.
func frame_index() -> int:
	var sp := spec()
	if sp.is_empty():
		return -1
	var t := ticks_in_state
	var ranges: Array = sp.get("tick_ranges", []) if sp.get("tick_ranges") != null else []
	if not ranges.is_empty():
		var last_i := 0
		for r in ranges:
			var arr: Array = r
			if t >= int(arr[1]) and t <= int(arr[2]):
				return _spec_index(str(arr[0]), sp)
			last_i = _spec_index(str(arr[0]), sp)
		return last_i                 # past the last range: one-shot holds its last frame
	var tpf := ticks_per_frame()
	if tpf <= 0.0:
		return 0
	var spec_frames: Array = sp.get("spec_frames", [])
	if spec_frames.is_empty():
		return 0
	var idx := int(floor(float(t) / tpf))
	if bool(sp.get("loop", false)):
		return idx % spec_frames.size()
	return mini(idx, spec_frames.size() - 1)


## Index of a spec frame name in the state's spec_frames (frame_map falls back).
func _spec_index(p_name: String, sp: Dictionary) -> int:
	var spec_frames: Array = sp.get("spec_frames", [])
	var i: int = spec_frames.find(p_name)
	if i >= 0:
		return i
	return 0


func ticks_per_frame() -> float:
	var v = spec().get("ticks_per_frame")
	if v == null:
		return 0.0
	return float(v)


## The spec frame name currently shown ("" when no frame was ever shown). A state with
## no frames of its own (the contact-kill attack, the big explosion) holds the
## last frame shown - a billboard never blanks out.
func frame_name() -> String:
	var n := _frame_name_raw()
	if n != "":
		return n
	return last_named_frame


func _frame_name_raw() -> String:
	var spec_frames: Array = spec().get("spec_frames", [])
	var i := frame_index()
	if spec_frames.is_empty() or i < 0 or i >= spec_frames.size():
		return ""
	return str(spec_frames[i])


## The disk path of the frame currently shown, via frame_map ("" when none).
func frame_path() -> String:
	var n := frame_name()
	if n == "":
		return ""
	var fm: Dictionary = doc.get("anim", {}).get("frame_map", {})
	return str(fm.get(n, n))


## The binding tick count of the current state (-1 when the state table has none: the
## state ends when the SIM ends it, e.g. the contact-driven attack).
func state_total() -> int:
	var v = spec().get("total_ticks")
	return -1 if v == null else int(v)


# ---- hit shape (HITBOXES hard rule) -------------------------------------------------------------


## The body_rect of the frame SHOWN (from the T-016 sheet), in sheet pixels.
func body_rect() -> Array:
	var meta: Dictionary = _frame_docs.get(frame_path(), {})
	return meta.get("body_rect", [])


## The hit cylinder of the frame SHOWN, in world units. Height = body height, diameter
## = 0.8 x body width; the scale is the one billboard.gd derives (body is world_height
## u tall), so a squashed frame has a squashed hitbox. Empty when no frame shows.
func hit_shape() -> Dictionary:
	var br := body_rect()
	var meta: Dictionary = _frame_docs.get(frame_path(), {})
	if br.is_empty() or meta.is_empty():
		return {}
	var world_h: float = float(meta.get("world_height", 1.0))
	var body_h_px: float = maxf(float(br[3]), 1.0)
	var u_per_px: float = world_h / body_h_px
	var diameter: float = float(br[2]) * u_per_px * HIT_WIDTH_FRACTION
	return {"height": world_h, "diameter": diameter, "frame": frame_index()}


## TRANSPARENCY rule: a probe hits only if it lands inside the body_rect of the frame
## SHOWN AND that pixel has alpha > BODY_ALPHA_MIN. Transparent padding never hits.
## p_px is the probe point in sheet-pixel coordinates ([x, y] from the top left).
func probe_hits(p_px: Vector2i) -> bool:
	var br := body_rect()
	var path := frame_path()
	if br.is_empty() or path == "":
		return false
	if p_px.x < int(br[0]) or p_px.y < int(br[1]) \
			or p_px.x >= int(br[0]) + int(br[2]) or p_px.y >= int(br[1]) + int(br[3]):
		return false                  # transparent padding (or off-frame): never a hit
	var img := _image_for(path)
	if img == null:
		return true                   # no pixels readable: inside body_rect counts as body
	var x: int = clampi(p_px.x, 0, img.get_width() - 1)
	var y: int = clampi(p_px.y, 0, img.get_height() - 1)
	return int(img.get_pixel(x, y).a * 255.0) > BODY_ALPHA_MIN


func _image_for(p_path: String) -> Image:
	if _img_cache.has(p_path):
		return _img_cache[p_path]
	var tex := _texture_for(p_path)
	if tex == null:
		_img_cache[p_path] = null
		return null
	_textures_checked[p_path] = true
	var img := tex.get_image()
	if img != null and img.is_compressed():
		img.decompress()
	_img_cache[p_path] = img
	return img


var _textures_checked: Dictionary = {}   # p_path -> true (probe audit trail for tests)


func _texture_for(p_path: String) -> Texture2D:
	if _tex_cache.has(p_path):
		return _tex_cache[p_path]
	var full := folder_dir.path_join(p_path)
	var tex: Texture2D = null
	if ResourceLoader.exists(full):
		tex = load(full)
	_tex_cache[p_path] = tex
	return tex


## The Texture2D shown right now (null when the frame file is missing - TBD allowed).
func frame_texture() -> Texture2D:
	var p := frame_path()
	return null if p == "" else _texture_for(p)


# ---- billboard effects as shader parameters -----------------------------------------------------


## The shader parameter values for the current state and tick. Uniform names (the enemy
## billboard shader contract): flash (Color, additive white), tint (Color),
## scale_pulse (float multiplier), shake (Vector2 offset in u), alpha (float 0-1).
## None of these ever change frame_index() or body_rect().
func effect_params() -> Dictionary:
	var sp := spec()
	var eff: Dictionary = sp.get("effect", {}) if sp.get("effect") != null else {}
	var name: String = str(eff.get("name", "none"))
	var params: Dictionary = eff.get("params", {}) if eff.get("params") != null else {}
	var out := {
		"flash": Color(0, 0, 0, 0),
		"tint": Color(1, 1, 1, 1),
		"scale_pulse": 1.0,
		"shake": Vector2.ZERO,
		"alpha": 1.0,
	}
	match name:
		"common_fade", "fade", "fade_fast":
			var ticks: int = _param(params, "ticks", "duration_ticks", DEFAULTS["common_fade"]["ticks"])
			var t: float = clampf(float(ticks_in_state) / float(maxi(ticks, 1)), 0.0, 1.0)
			out["alpha"] = lerpf(_p(params, "alpha_from", 0.0), _p(params, "alpha_to", 1.0), t)
			var s: float = lerpf(_p(params, "scale_from", 0.8), _p(params, "scale_to", 1.0), t)
			out["scale_pulse"] = s
		"scale_pulse":
			var T: int = _param(params, "ticks", "ticks", 0)
			if T <= 0:
				T = maxi(state_total(), 1)
			var peak: float = _p(params, "peak", _p(params, "scale_to", 1.12))
			var half := maxi(T / 2, 1)
			var t: int = ticks_in_state
			var m: float = clampf(1.0 - absf(float(t - half) / float(half)), 0.0, 1.0)
			out["scale_pulse"] = lerpf(_p(params, "from", 1.0), peak, m)
			if t >= T:
				out["scale_pulse"] = _p(params, "to", 1.0)
		"white_flash":
			var T: int = _param(params, "ticks", "ticks", DEFAULTS["white_flash"]["ticks"])
			if ticks_in_state < T:
				out["flash"] = Color(1, 1, 1, 1.0 - float(ticks_in_state) / float(T))
		"dim":
			out["tint"] = Color(_p(params, "brightness", 0.7), _p(params, "brightness", 0.7), _p(params, "brightness", 0.7), 1.0)
		"rumble":
			var amp := _p(params, "shake_u", 0.0)
			var sgn := 1.0 if ticks_in_state % 2 == 0 else -1.0
			out["shake"] = Vector2(amp, amp * 0.5) * sgn
	return out


func _p(params: Dictionary, key: String, fallback: float) -> float:
	if params.has(key) and (params[key] is float or params[key] is int):
		return float(params[key])
	return fallback


func _param(params: Dictionary, key: String, alt: String, fallback: int) -> int:
	for k in [key, alt]:
		if params.has(k) and (params[k] is float or params[k] is int):
			return int(params[k])
	return fallback


# ---- spawn fade contact rule ---------------------------------------------------------------------


## Section 1.0: during the spawn fade the body cannot touch or kill. Blocked for
## SPAWN_FADE_TICKS (30) unless the state's fade params state the count explicitly.
## Only a fade-type spawn blocks (a "no sprite" spawn state is not a fade;
## gift Larper is present from level start with no fade at all).
func contact_blocked() -> bool:
	if state_id != "spawn":
		return false
	var eff: Dictionary = spec().get("effect", {}) if spec().get("effect") != null else {}
	var name: String = str(eff.get("name", "none"))
	if not ["common_fade", "fade", "fade_fast"].has(name):
		return false
	var params: Dictionary = eff.get("params", {}) if eff.get("params") != null else {}
	var blocked: int = _param(params, "spawn_blocks_contact_ticks", "duration_ticks", SPAWN_FADE_TICKS)
	return ticks_in_state < blocked


# ---- view sync -----------------------------------------------------------------------------------


## Pushes the current frame and effect params into the bound billboard. The view is
## duck-typed (billboard.gd): set_stage / set_stage_frame when it grows them, plus the
## shader parameters through set_effect. Never stores sim state here.
func _sync_view() -> void:
	var raw := _frame_name_raw()
	if raw != "":
		var sp := spec()
		var loop: bool = bool(sp.get("loop", false))
		var total := state_total()
		# a finished looping state's wrapped frame is computed but never shown (the sim
		# switches on that tick) - it must not become the held frame
		if not (loop and total > 0 and ticks_in_state >= total):
			last_named_frame = raw
	if view == null:
		return
	if view.has_method("set_stage") and state_id != "":
		view.set_stage(state_id)
	if view.has_method("set_stage_frame"):
		view.set_stage_frame(frame_index())
	if view.has_method("set_effect"):
		var p := effect_params()
		for k in p.keys():
			view.set_effect(str(k), p[k])
	if view.has_method("set_texture") and frame_texture() != null:
		view.set_texture(frame_texture())



