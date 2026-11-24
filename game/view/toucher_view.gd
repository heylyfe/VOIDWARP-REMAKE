extends Node3D
#
# toucher view (ticket T-037; ENEMIES.md "Flesh -> toucher", DESIGN.md section 5.8,
# the T-083 anim block in sprites.json - read here, never re-declared).
#
# The finger sprite is driven THROUGH view/enemy_anim.gd (the T-084 shared player):
# this node duck-types the player's caller contract (set_stage / set_stage_frame /
# set_effect / set_texture) and the player pushes the frame + effect parameters of
# the current sim state into it. Frame choice, spawn fade, pulse timing and the
# attack_infect key are the anim block's own rows - nothing here re-declares a
# tick count. The view READS the sim row ("anim_state", "anim_state_t", "glitched"
# entries, "rt_tick") and never writes sim state.
#
# The corrupted floor is the anim block's attack_infect effect params: one decal
# per live glitched tile (the sim row's "glitched" list), 5 frames cycling at 8 fps
# with a (x + z) mod 5 per-tile offset, appearing alpha 0 -> 1 over 12 ticks under a
# 6-tick danger-red (#FF2A2A) tear flash, and in the last 60 ticks of a tile's life
# flickering at 10 Hz then fading alpha -> 0 over the final 12 ticks. thicc ben's
# cleanse (T-085, section 2.2 last row) takes the decals inside 8 u away in an
# outward wave over 18 ticks: on_cleanse() reads the sim's glitched_cleanse event.
#
# BILLBOARDING / TRANSPARENCY: the finger always faces the camera (billboard.gd,
# Y-rotation only, never rotated the other way - the anim block's face_player says
# "mirror_horizontal_only, never_rotated"); the sprite renders with the texture's
# alpha scissor so transparent padding never draws (billboard.gd's scissor rule).
#
# FLOOR-ONLY MODE (the playable world's hook): setup(..., true) builds ONLY the
# decal layer (no body billboard, no anim player) so a caller that already draws
# the body itself can still render the corrupted floor. The node then sits at the
# world origin: the sim's glitched entries carry ABSOLUTE tile coordinates and the
# decals are placed there verbatim (placing this node anywhere else offsets the
# decals by that amount). sync_floor_rows() is the one-call per-frame entry point
# for that mode: it merges every toucher row's glitched list (one decal per tile
# key, first listing wins) and ages them against the rows' shared rt_tick.

const EnemyAnimScript := preload("res://view/enemy_anim.gd")
const AssetLoadScript := preload("res://view/asset_load.gd")   # U4: fail-soft loads (text/scene/texture/stream)
const BillboardScript := preload("res://view/billboard.gd")

const SHEET_REL := "res://content/enemies/toucher/sprites.json"
const FOLDER_REL := "res://content/enemies/toucher"

# Decal fallbacks - every one is replaced by the anim block's attack_infect params
# when they are present (they are: glitchfloor_fps 8, offset (x+z) mod 5, appear 12,
# tear flash 6, flicker 10 Hz, fade 12).
const DECAL_APPEAR_TICKS := 12
const DECAL_FLASH_TICKS := 6
const DECAL_FLICKER_TICKS := 60
const DECAL_FADE_TICKS := 12
const DECAL_FLICKER_HZ := 10.0
const DECAL_SIZE_U := 1.0             # one decal covers exactly one tile (1 x 1 u)
const DANGER_RED := Color(1.0, 0.1647, 0.1647, 1.0)   # #FF2A2A; replaced by the block
## thicc ben's cleanse (section 2.2, last row): the decals inside 8 u leave in an
## outward wave over 18 ticks.
const CLEANSE_TICKS := 18

var billboard = null                  # BillboardScript instance (the finger PNG)
var anim: RefCounted = null           # the shared enemy_anim.gd player
var _sprite_wrap: Node3D = null       # scale_pulse lives here
var _decal_root: Node3D = null
var _decals: Dictionary = {}          # tile key -> {"sprite": Sprite3D}
var _decal_texts: Array = []         # the 5 Texture2Ds, in the block's frame order
var _anim_block: Dictionary = {}
var _doc: Dictionary = {}
var _folder := FOLDER_REL
var _appear := DECAL_APPEAR_TICKS
var _flash := DECAL_FLASH_TICKS
var _flicker := DECAL_FLICKER_TICKS
var _fade := DECAL_FADE_TICKS
var _flicker_hz := DECAL_FLICKER_HZ
var _red := DANGER_RED
var _last_state := ""
var _pulse_scale := 1.0
var _body_alpha := 1.0
var _cleanse: Dictionary = {}         # the live ben cleanse wave (see on_cleanse)
# the anim block's per-state frames (states[*].frames), loaded once per state
# (D-ART-TOUCHER-1): the shared player resolves frame_path through the block's
# global frame_map, which can only hold one file per spec frame name, so the
# per-state art is swapped in here, where the state id is known.
var _state_frames: Dictionary = {}    # state_id -> Array[Texture2D]
var _active_state := ""
var _floor_only := false               # floor-only mode (see the header comment)
var _floor_tick := 0                   # last rt_tick seen by sync_floor_rows


## The anim block's state ids, for callers/tests that prove the wiring.
func anim_state_ids() -> Array:
	return (_anim_block.get("states", {}) as Dictionary).keys()


## floor_only: build only the decal layer (no body billboard / anim player); the
## caller draws the body itself (the playable world's boards). The node must sit at
## the world origin in that mode - decal coordinates are the sim's absolute tiles.
func setup(sheet_path: String = SHEET_REL, folder: String = FOLDER_REL, floor_only: bool = false) -> void:
	for child in get_children():
		child.free()
	_folder = folder
	_floor_only = floor_only
	var parsed = JSON.parse_string(AssetLoadScript.text(sheet_path))
	if parsed is Dictionary:
		_doc = parsed
	_anim_block = _doc.get("anim", {})
	_read_anim_block()
	if not _floor_only:
		_sprite_wrap = Node3D.new()
		_sprite_wrap.name = "SpriteWrap"
		add_child(_sprite_wrap)
		billboard = BillboardScript.new()
		_sprite_wrap.add_child(billboard)
		if not _doc.is_empty():
			billboard.setup_from_sheet(_doc, folder)
		anim = EnemyAnimScript.new()
		anim.setup("toucher", _doc, folder)
		anim.bind_view(self)
	_build_decals()


## Pull the numbers this view needs from the anim block; the stated values above
## are only fallbacks (the block is the binding spec, nothing here re-declares it).
func _read_anim_block() -> void:
	var states: Dictionary = _anim_block.get("states", {})
	var spawn: Dictionary = states.get("spawn", {})
	var sp_params: Dictionary = (spawn.get("effect", {}) as Dictionary).get("params", {})
	if sp_params.has("spawn_blocks_contact_ticks") and (sp_params["spawn_blocks_contact_ticks"] is int or sp_params["spawn_blocks_contact_ticks"] is float):
		_appear = float(sp_params["spawn_blocks_contact_ticks"])
	var infect: Dictionary = states.get("attack_infect", {})
	var params: Dictionary = (infect.get("effect", {}) as Dictionary).get("params", {})
	if params.has("decal_appear_ticks"):
		_appear = float(params["decal_appear_ticks"])
	if params.has("tear_flash_ticks"):
		_flash = float(params["tear_flash_ticks"])
	if params.has("expire_fade_ticks"):
		_fade = float(params["expire_fade_ticks"])
	if params.has("expire_flicker_hz"):
		_flicker_hz = float(params["expire_flicker_hz"])
	if params.has("tear_flash_color"):
		_red = Color(str(params["tear_flash_color"]))
	var pulse: Dictionary = (states.get("telegraph", {}) as Dictionary).get("effect", {}).get("params", {})
	if pulse.has("scale_to"):
		_pulse_scale = float(pulse["scale_to"])
	_load_state_frames(states)


## Load the per-state frame textures listed in the anim block (states[*].frames).
## Missing files leave a null entry (TBD allowed; the block's frame_map path still
## resolves through the cycle sheet as before).
func _load_state_frames(states: Dictionary) -> void:
	_state_frames = {}
	for state_id in states.keys():
		var arr: Array = []
		for rel in (states[state_id] as Dictionary).get("frames", []):
			var full := "%s/%s" % [_folder, str(rel)]
			if ResourceLoader.exists(full):
				arr.append(load(full))
			else:
				arr.append(null)
		_state_frames[str(state_id)] = arr


## The texture of the frame the anim block pins for the active state at the current
## billboard frame index (null when unavailable).
func _active_state_texture() -> Texture2D:
	if billboard == null:
		return null
	var arr: Array = _state_frames.get(_active_state, [])
	if arr.is_empty():
		return null
	var i := clampi(int(billboard.frame_i), 0, arr.size() - 1)
	return arr[i]


# ---- the enemy_anim.gd caller contract (duck-typed; never stores sim state) -------

func set_stage(state_id: String) -> void:
	_active_state = state_id


func set_stage_frame(i: int) -> void:
	if billboard == null or not billboard.anims.has("cycle"):
		return
	billboard.frame_i = i
	billboard._apply_frame(i)
	var tex := _active_state_texture()
	if tex != null:
		billboard.texture = tex


func set_effect(k: String, v) -> void:
	match k:
		"scale_pulse":
			if v is float or v is int:
				_sprite_wrap.scale = Vector3(float(v), float(v), float(v))
		"alpha":
			if v is float or v is int:
				if billboard != null:
					_body_alpha = clampf(float(v), 0.0, 1.0)
					billboard.modulate.a = _body_alpha
		_:
			pass


func set_texture(tex) -> void:
	# the per-state art from the anim block wins over the frame_map target (the
	# frame_map can only hold one file per spec frame name; see D-ART-TOUCHER-1)
	var active := _active_state_texture()
	if active != null:
		if billboard != null:
			billboard.texture = active
		return
	if tex != null and billboard != null:
		billboard.texture = tex


# ---- one view frame -----------------------------------------------------------------

## row is the sim row (read-only); dt is seconds elapsed. The caller places this
## node at the world origin in floor-only mode (decals use the sim's absolute tile
## coordinates); in full mode it may sit wherever the body should be. Frames advance
## through the shared player at the sim's tick rate; decals read the row's glitched
## list against the row's rt_tick.
func sync(row: Dictionary, dt: float, cam_pos: Vector3 = Vector3.ZERO) -> void:
	if _floor_only:
		_sync_decals(row)
		return
	if billguard_free():
		return
	var state := str(row.get("anim_state", "idle_chase"))
	if state != _last_state:
		_last_state = state
		anim.on_state_changed(state)
	var n := int(round(dt * 60.0))
	for _i in range(maxi(n, 0)):
		anim.sim_tick()
	_sync_decals(row)
	if cam_pos != Vector3.ZERO and billboard != null:
		billboard.face_camera(cam_pos)


# A freed/unset player means the view is dead; keep sync harmless.
func billguard_free() -> bool:
	return anim == null or billboard == null


## Floor-only one-call pass for the playable world (floor-only mode): merges the
## glitched lists of every row in `rows` whose id is "toucher" (e.g. rt.enemies)
## and ages one decal per tile key against the rows' shared rt_tick (the runtime
## tick counter every row carries). First listing of a key wins, so two touchers
## listing the same tile still draw a single decal. Safe to call every frame and
## with an empty rows array (decals simply age against the last seen tick).
## Returns the number of live glitched tiles seen.
func sync_floor_rows(rows: Array) -> int:
	var merged: Array = []
	var seen: Dictionary = {}
	var now := _floor_tick
	for row in rows:
		if not (row is Dictionary):
			continue
		if str(row.get("id", "")) != "toucher":
			continue
		now = maxi(now, int(row.get("rt_tick", 0)))
		for entry in row.get("glitched", []):
			if not (entry is Dictionary):
				continue
			var key := str(entry.get("key", ""))
			if key == "" or seen.has(key):
				continue
			seen[key] = true
			merged.append(entry)
	_floor_tick = now
	_sync_decals({"glitched": merged, "rt_tick": now})
	return merged.size()


# ---- the corrupted floor decals ------------------------------------------------------

func _build_decals() -> void:
	_decal_root = Node3D.new()
	_decal_root.name = "GlitchFloor"
	add_child(_decal_root)
	_decal_texts = []
	var states: Dictionary = _anim_block.get("states", {})
	var params: Dictionary = (states.get("attack_infect", {}) as Dictionary).get("effect", {}).get("params", {})
	var frames: Array = params.get("glitchfloor_frames", [])
	var doc_anims: Dictionary = {}
	for a in _doc.get("animations", []):
		doc_anims[str(a.get("name", ""))] = a
	if frames.is_empty() and doc_anims.has("floor"):
		frames = doc_anims["floor"]["frames"]
	for f_path in frames:
		var full := "%s/%s" % [_folder, str(f_path)]
		if ResourceLoader.exists(full):
			_decal_texts.append(load(full))
		else:
			_decal_texts.append(null)


## Reconcile the decal set with the sim row's glitched list and age each decal's
## appear / tear-flash / expire-flicker / fade phases against the row's rt_tick.
func _sync_decals(row: Dictionary) -> void:
	var now: int = int(row.get("rt_tick", 0))
	var live: Dictionary = {}
	for entry in row.get("glitched", []):
		var key := str(entry.get("key", ""))
		if key == "":
			continue
		live[key] = entry
	# drop decals whose tile left the sim list - unless a ben cleanse wave is
	# still sweeping outward over them (section 2.2, last row)
	var dead: Array = []
	for key in _decals.keys():
		if live.has(key):
			continue
		var d: Dictionary = _decals[key]
		if _cleanse.is_empty():
			dead.append(key)
			continue
		var dist: float = _wave_dist(d)
		if dist > float(_cleanse["r"]) or dist <= _wave_front(now):
			dead.append(key)
		else:
			# the wave has not reached this tile yet: it keeps its decal
			(d["sprite"] as Sprite3D).modulate = Color(1.0, 1.0, 1.0, 1.0)
	for key in dead:
		var d: Dictionary = _decals[key]
		(d["node"] as Node3D).free()
		_decals.erase(key)
	# raise / age the rest
	for key in live.keys():
		var entry: Dictionary = live[key]
		var born: int = int(entry.get("born", 0))
		var life: int = int(entry.get("life", 0))
		var age: float = float(now - born)
		var d2: Variant = _decals.get(key, null)
		if d2 == null:
			d2 = _make_decal(entry)
			if d2 == null:
				continue
			_decals[key] = d2
		var sprite: Sprite3D = d2["sprite"]
		var frame_i: int = _decal_frame(entry, age)
		sprite.texture = _decal_texts[frame_i] if frame_i < _decals_texts_count() else null
		_age_decal(sprite, age, float(life), now, born)


func _decals_texts_count() -> int:
	return _decal_texts.size()


## thicc ben's ring cleanse (section 2.2, last row): the sim's glitched_cleanse
## event carries the centre (x, z), the radius and the tick. The decals inside
## the radius leave in an outward wave over CLEANSE_TICKS ticks - the wave front
## travels from the centre to r, and a tile loses its decal when the front
## reaches it.
func on_cleanse(ev: Dictionary) -> void:
	var r := float(ev.get("r", 0.0))
	if r <= 0.0:
		return
	_cleanse = {
		"tick": int(ev.get("tick", 0)),
		"x": float(ev.get("x", 0.0)),
		"z": float(ev.get("z", 0.0)),
		"r": r,
	}


## The wave front's radius at `now` (0 at the cleanse tick, r after 18 ticks).
func _wave_front(now: int) -> float:
	if _cleanse.is_empty():
		return 0.0
	var age: float = float(now - int(_cleanse["tick"]))
	return clampf(age / float(CLEANSE_TICKS), 0.0, 1.0) * float(_cleanse["r"])


## Horizontal distance from the cleanse centre to a decal (the view sits at the
## enemy's feet, so the decal's world position is this node's position + its own).
func _wave_dist(d: Dictionary) -> float:
	var p: Vector3 = position + (d["node"] as Node3D).position
	var dx: float = p.x - float(_cleanse["x"])
	var dz: float = p.z - float(_cleanse["z"])
	return sqrt(dx * dx + dz * dz)


func _floor_fps() -> float:
	var states: Dictionary = _anim_block.get("states", {})
	var params: Dictionary = (states.get("attack_infect", {}) as Dictionary).get("effect", {}).get("params", {})
	return float(params.get("glitchfloor_fps", 8.0))


## The (x + z) mod 5 frame offset (the anim block's glitchfloor_frame_offset),
## from the tile's grid coordinates: entries carry centres (x, z at +0.5).
func _tile_offset(entry: Dictionary) -> int:
	var gx := int(floor(float(entry.get("x", 0.0)) - 0.5))
	var gz := int(floor(float(entry.get("z", 0.0)) - 0.5))
	return posmod(gx + gz, 5)


## The decal frame: the 5-frame cycle at 8 fps (7.5 ticks per frame, section 2.2
## "7-8 ticks per frame"), each tile offset by (x + z) mod 5 frames so neighbours
## do not flash in unison.
func _decal_frame(entry: Dictionary, age: float) -> int:
	var n: int = _decals_texts_count()
	if n <= 0:
		return 0
	var step: int = int(age / (60.0 / maxf(_floor_fps(), 0.01)))
	return posmod(_tile_offset(entry) + step, n)


func _make_decal(entry: Dictionary) -> Variant:
	var tex_i: int = _tile_offset(entry)
	if _decal_texts.is_empty():
		return null
	var sprite := Sprite3D.new()
	sprite.pixel_size = DECAL_SIZE_U / 256.0
	sprite.rotation.x = -PI / 2.0
	sprite.shaded = false
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.alpha_scissor_threshold = 0.05
	sprite.render_priority = 1
	var node := Node3D.new()
	node.position = Vector3(float(entry.get("x", 0.0)), float(entry.get("y", 0.0)) + 0.02,
			float(entry.get("z", 0.0)))
	sprite.position = Vector3.ZERO
	node.add_child(sprite)
	_decal_root.add_child(node)
	return {"node": node, "sprite": sprite}


# appear: alpha 0 -> 1 over the appear ticks (danger-red tear flash under it);
# expiry: the last 60 ticks flicker at 10 Hz, the final 12 ticks fade to 0.
func _age_decal(sprite: Sprite3D, age: float, life: float, _now: int, _born: int) -> void:
	var alpha := 1.0
	var col := Color(1.0, 1.0, 1.0, 1.0)
	if age < _appear:
		alpha = age / maxf(_appear, 1.0)
	var left := life - age
	if left <= 0.0:
		alpha = 0.0
	elif left <= _fade:
		alpha = left / maxf(_fade, 1.0)
	elif left <= _flicker:
		# 10 Hz flicker: alpha chops between 0.15 and its base every half period
		var half_tick := 60.0 / (2.0 * maxf(_flicker_hz, 0.01))
		alpha = 0.15 if fmod(age, 2.0 * half_tick) < half_tick else 1.0
	if age < _flash:
		col = Color(_red.r, _red.g, _red.b, 1.0)
	sprite.modulate = Color(col.r, col.g, col.b, alpha)
