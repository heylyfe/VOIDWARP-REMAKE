extends Node3D
#
# Enemy view host (W11-A): one live runtime row's bespoke view behind ONE uniform feed, so
# app/world.gd can wire nine different per-enemy views without naming a single content id
# (tests/test_boundaries.gd scans app/; view/ may name ids). world.gd asks supports(id),
# builds a host per supported row, and feeds it:
#   on_spawn()            - once, the tick the row appears (the row's enemy_spawn tick)
#   on_event(e, row)      - a telegraph / screen_blur event route() assigned to this row
#   sync(row, ctx)        - every sim tick; ctx = {"dt", "cam", "player", "curses"}
#
# Every per-enemy signature below was read from the view file itself:
#   kiwi_cat    setup(folder) on_spawn() on_telegraph(kind, ticks) step(ticks)
#               set_curses_state(state) update_trail(row, player)
#   seal        setup(folder) on_spawn() on_telegraph(kind, ticks, shape) step(ticks)
#   gift_larper setup(folder) on_spawn() step(ticks) sync(eye)
#   thicc_ben   setup(folder) on_events(events) sync(row) advance(ticks)
#   you / address_me / claude   setup(sheet, folder) sync(row, dt, cam)
#   gin         setup(sheet, folder) update_from_row(row); its setup() never loads the
#               sheet into its billboard, so the host does (setup_from_sheet) and drives
#               the billboard's state, frame and facing itself
#   isagi       view/isagi_view.gd is a RefCounted helper, not a node: the body lives in
#               view/enemies/isagi_body.gd, which renders the helper's snapshot()
#
# The host stays at its parent's origin; the bespoke view node it owns is moved onto the
# row's feet each tick. Several views measure their world-space VFX (bands, rings, smoke,
# the dash line) against their OWN position, so the view node must carry the row position.

const KiwiCatViewScript := preload("res://view/kiwi_cat_view.gd")
const AssetLoadScript := preload("res://view/asset_load.gd")   # U4: fail-soft loads (text/scene/texture/stream)
const SealViewScript := preload("res://view/seal_view.gd")
const GiftLarperViewScript := preload("res://view/gift_larper_view.gd")
const ThiccBenViewScript := preload("res://view/thicc_ben_view.gd")
const YouViewScript := preload("res://view/you_view.gd")
const AddressMeViewScript := preload("res://view/address_me_view.gd")
const ClaudeViewScript := preload("res://view/claude_view.gd")
const GinViewScript := preload("res://view/gin_view.gd")
const IsagiBodyScript := preload("res://view/enemies/isagi_body.gd")

const KINDS := ["address_me", "claude", "gift_larper", "gin", "isagi", "kiwi_cat", "seal",
		"thicc_ben", "you"]
# gin's row states -> its sheet's animation names (the sheet has no attack_* rows)
const GIN_ANIM := {"attack_launch": "launch", "attack_void_zone": "idle"}

var id := ""
var view: Node3D = null     # the bespoke view node (isagi: the isagi_body adapter)
var spawned := false        # on_spawn() reached the view
var fed_ticks := 0          # sync() calls that reached the view
var events_fed := 0         # routed events that reached the view


## True when this id has a bespoke view the host can drive.
static func supports(p_id: String) -> bool:
	return KINDS.has(p_id)


## Show or hide the bespoke view. A row that fell with its platform (sim/enemy_runtime.gd
## _support_pass) is drawn while it falls and hidden once it is past the kill plane: the
## row stays in rt.enemies so every index in app/world.gd keeps pointing at it, but a body
## 40 u below the level must not keep animating there.
func set_shown(on: bool) -> void:
	if view != null:
		view.visible = on


## Builds the bespoke view for p_id from its content folder. False for an unsupported id
## (the caller keeps the generic billboard).
func setup(p_id: String, folder: String) -> bool:
	for child in get_children():
		child.free()
	view = null
	id = p_id
	var sheet := folder.path_join("sprites.json")
	match id:
		"kiwi_cat":
			view = KiwiCatViewScript.new()
			add_child(view)
			view.setup(folder)
		"seal":
			view = SealViewScript.new()
			add_child(view)
			view.setup(folder)
		"gift_larper":
			view = GiftLarperViewScript.new()
			add_child(view)
			view.setup(folder)
		"thicc_ben":
			view = ThiccBenViewScript.new()
			add_child(view)
			view.setup(folder)
		"you":
			view = YouViewScript.new()
			add_child(view)
			view.setup(sheet, folder)
		"address_me":
			view = AddressMeViewScript.new()
			add_child(view)
			view.setup(sheet, folder)
		"claude":
			view = ClaudeViewScript.new()
			add_child(view)
			view.setup(sheet, folder)
		"gin":
			view = GinViewScript.new()
			add_child(view)
			view.setup(sheet, folder)
			_load_gin_sheet(sheet, folder)
		"isagi":
			view = IsagiBodyScript.new()
			add_child(view)
			view.setup(folder)
	return view != null


func _load_gin_sheet(sheet: String, folder: String) -> void:
	if view.billboard == null:
		return
	var parsed: Variant = JSON.parse_string(AssetLoadScript.text(sheet))
	if parsed is Dictionary:
		view.billboard.setup_from_sheet(parsed, folder)


## The row appeared this tick (the runtime's enemy_spawn tick): restart the spawn fade.
## The row-driven views (you / address_me / claude / gin / isagi) read their spawn state
## off row["anim_state"] / row["st"] instead, so they take nothing here.
func on_spawn() -> void:
	if view == null:
		return
	spawned = true
	match id:
		"kiwi_cat", "seal", "gift_larper":
			view.on_spawn()
		"thicc_ben":
			view.on_events([{"e": "enemy_spawn", "id": id}])


## One sim event that route() assigned to this row. row is the live row (read-only) the
## seal's dash line is converted against: the sim's line is in world space, the view draws
## its dashes as its own children.
func on_event(e: Dictionary, row: Dictionary) -> void:
	if view == null:
		return
	var kind := str(e.get("e", ""))
	match id:
		"kiwi_cat":
			if kind == "telegraph":
				events_fed += 1
				view.on_telegraph(str(e.get("kind", "")), int(e.get("ticks", -1)))
		"seal":
			if kind == "telegraph":
				events_fed += 1
				view.position = _row_pos(row)
				view.on_telegraph(str(e.get("kind", "")), int(e.get("ticks", -1)),
						_local_shape(e.get("shape", {}), view.position))
		"thicc_ben":
			if kind == "telegraph" or kind == "screen_blur":
				events_fed += 1
				view.on_events([e])


## One sim tick of view state. ctx: dt (seconds), cam (camera position, the facing),
## player (the nearest player's {x, y, z}), curses (the curse dispatcher's state dict).
func sync(row: Dictionary, ctx: Dictionary) -> void:
	if view == null:
		return
	fed_ticks += 1
	var dt := float(ctx.get("dt", 1.0 / 60.0))
	var cam: Vector3 = ctx.get("cam", Vector3.ZERO)
	var player: Dictionary = ctx.get("player", {})
	var pos := _row_pos(row)
	match id:
		"kiwi_cat":
			view.position = pos
			view.set_curses_state(ctx.get("curses", {}))
			view.step(1)
			view.update_trail(row, player)
			_face(view.billboard, cam)
		"seal":
			view.position = pos
			view.step(1)
			_face(view.billboard, cam)
		"gift_larper":
			view.position = pos
			view.step(1)
			if cam != Vector3.ZERO:
				view.sync(cam)   # ZERO would force the tell on: no camera, no tell
		"thicc_ben":
			view.sync(row)   # the view places itself on the row (teleport arrivals)
			view.advance(1)
			_face(view.billboard, cam)
		"you", "address_me", "claude":
			view.position = pos
			if id == "claude":
				# T4 (D-T4-8): the anger timer lives in sim/clawds.gd, not on the row, so the body view is
				# fed it here; a warning the sim raised this tick flashes the logo and plays its cue.
				var cl = ctx.get("clawds", null)
				if cl != null:
					view.set_anger(float(cl.anger_ticks) / maxf(float(cl.kill_ticks), 1.0))
					# A pickup resets the sim's warning count (review round 1): re-arm the view's own
					# counter so the next 60 s / 120 s warnings flash and play their cues again.
					if int(cl.warned) < int(view._last_warned):
						view.rearm()
					if int(cl.warned) > int(view._last_warned):
						view.on_warning(int(cl.warned))
			view.sync(row, dt, cam)
		"gin":
			view.position = pos
			if row["cfg"].has("sword_attack"):
				view.update_sword_attack(row)
				return
			view.update_from_row(row)
			var bb = view.billboard
			if bb != null:
				var st := str(row.get("anim_state", ""))
				bb.set_animation(str(GIN_ANIM.get(st, st)))
				bb.advance_animation(dt)
				_face(bb, cam)
		"isagi":
			view.position = pos
			view.sync_row(row, player, dt, cam)


static func _face(bb, cam: Vector3) -> void:
	if bb != null and cam != Vector3.ZERO:
		bb.face_camera(cam)


static func _row_pos(row: Dictionary) -> Vector3:
	return Vector3(float(row.get("x", 0.0)), float(row.get("y", 0.0)), float(row.get("z", 0.0)))


## The shape with its dash_line (world space [x0,y0,z0, x1,y1,z1]) moved into the frame of
## a node standing at origin.
static func _local_shape(shape: Variant, origin: Vector3) -> Dictionary:
	if not (shape is Dictionary):
		return {}
	var out: Dictionary = (shape as Dictionary).duplicate(true)
	var line: Variant = out.get("dash_line", null)
	if line is Array and (line as Array).size() >= 6:
		var l: Array = line
		out["dash_line"] = [float(l[0]) - origin.x, float(l[1]) - origin.y, float(l[2]) - origin.z,
				float(l[3]) - origin.x, float(l[4]) - origin.y, float(l[5]) - origin.z]
	return out


## Which live row a sim event belongs to: the index into rows, or -1. Only "telegraph" and
## "screen_blur" are routed, and only to rows whose id is the event's source (the runtime
## stamps the source row's id on both). With several copies of one id, the row that owns
## the event is chosen by the event's geometry:
##   - a teleport telegraph is centred on the LOCKED destination, so the copy that locked
##     that point owns it (row lock_x / lock_z);
##   - any other telegraph is centred on its source body: the copy nearest the centre;
##   - a screen_blur (the eject, a body touch) has no shape: the copy nearest the player.
static func route(rows: Array, e: Dictionary, player_pos: Vector3) -> int:
	var kind := str(e.get("e", ""))
	if kind != "telegraph" and kind != "screen_blur":
		return -1
	var source := str(e.get("source", ""))
	if source == "" or not supports(source):
		return -1
	var shape: Dictionary = e.get("shape", {}) if e.get("shape", {}) is Dictionary else {}
	var target := player_pos
	var lock_key := false
	if kind == "telegraph" and shape.has("cx"):
		target = Vector3(float(shape["cx"]), 0.0, float(shape.get("cz", 0.0)))
		lock_key = str(e.get("kind", "")) == "teleport"
	var best := -1
	var best_d := INF
	for i in rows.size():
		var r: Dictionary = rows[i]
		if str(r.get("id", "")) != source:
			continue
		var p := _row_pos(r)
		if lock_key and r.has("lock_x"):
			p = Vector3(float(r["lock_x"]), 0.0, float(r.get("lock_z", 0.0)))
		var d := Vector2(p.x - target.x, p.z - target.z).length()
		if d < best_d:
			best_d = d
			best = i
	return best
