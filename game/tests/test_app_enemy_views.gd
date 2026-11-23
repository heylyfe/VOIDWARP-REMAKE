extends RefCounted
#
# W11-A wiring test (headless): the nine bespoke enemy views are INSTANTIATED and FED by
# the real run loop. Every view existed, was complete and was tested in isolation, and
# app/world.gd preloaded none of them - every enemy rendered as the generic billboard.
#
# Each leg goes through world.build() and world.step() ONLY: the enemy is voted into the
# level's plan (the ledger's votes, exactly the lobby's shape), the runtime spawns it on
# its own spawn rule, and world.step() drives the sim + view pass. Nothing here calls a
# view. Per enemy the leg asserts:
#   - the row's bespoke view exists, is a descendant of the world, is inside the tree;
#   - the generic billboard was NOT also built for that row (nothing drawn twice);
#   - the view stands on the row's feet;
#   - the feed reached it: that view's OWN observable state moved (read from each file).
# NEGATIVE CONTROL: the same assertions run on a world with bespoke_enemy_views = false
# (the wiring off, every row back on the billboard) and MUST fail for every enemy; the
# test fails if any enemy's assertions pass with the wiring off.
#
# Screen effects (the three calls that only tests made before): a paid void fall flashes
# the screen edge; a Last Light save (controller.try_kill's last_light_save event, raised
# here by a real runtime body contact) blooms white and shatters the pips' icon.

const WorldScript := preload("res://app/world.gd")
const RT := preload("res://sim/enemy_runtime.gd")

const SEED := 1
const LEVEL := 1
const DT := 1.0 / 60.0
const SPAWN_WAIT := 900      # ticks to wait for the planned row (the spawn delay is 360)
const FEED_TICKS := 40       # ticks stepped after the row appears

const IDS := ["address_me", "claude", "gift_larper", "gin", "isagi", "kiwi_cat", "seal",
		"thicc_ben", "you"]

var negative_failures := 0   # the negative control's assertion failures (reported)


# A parked body that kills on contact: it rides the player's feet, so the next
# runtime contact check reaches controller.try_kill.
class ContactBehavior:
	extends RT.EnemyBehavior

	var target = null

	func tick(row: Dictionary, _api, _dt_ticks: int) -> void:
		if target != null:
			row["x"] = float(target.x)
			row["y"] = float(target.y)
			row["z"] = float(target.z)


# Fires one real api.telegraph(kind, shape, ticks) at age `at` (shape: Callable(row) ->
# Dictionary, so it can read the row's own position). Parked 40 u up: never touches.
class TellBehavior:
	extends RT.EnemyBehavior

	var at := -1
	var kind := ""
	var ticks := 0
	var shape_of: Callable
	var age := 0

	func tick(row: Dictionary, api, _dt_ticks: int) -> void:
		if age == at:
			api.telegraph(kind, shape_of.call(row), ticks)
		age += 1


func run() -> Array[String]:
	var f: Array[String] = []
	var per_id_neg := {}
	for id in IDS:
		_leg_view(f, id, true)
		var neg: Array[String] = []
		_leg_view(neg, id, false)
		per_id_neg[id] = neg.size()
		negative_failures += neg.size()
		if neg.is_empty():
			f.append("%s: NEGATIVE CONTROL passed with the wiring off - the assertions prove nothing" % id)
	_leg_telegraph_routing(f, true)
	var neg_route: Array[String] = []
	_leg_telegraph_routing(neg_route, false)
	per_id_neg["telegraph_routing"] = neg_route.size()
	negative_failures += neg_route.size()
	if neg_route.is_empty():
		f.append("telegraph routing: NEGATIVE CONTROL passed with the wiring off")
	print("NEGATIVE CONTROL failures=%d per leg %s" % [negative_failures, str(per_id_neg)])
	_leg_void_flash(f)
	_leg_last_light(f)
	return f


func _ledger(votes: Dictionary) -> Dictionary:
	return {"class": "athletic", "votes": votes, "curses": {}, "stacks": {}, "purse": 0}


func _root() -> Node:
	var ml := Engine.get_main_loop()
	return (ml as SceneTree).root if ml is SceneTree else null


## Build a real level with p_votes, inside the tree. null on failure (f gets the line).
func _build(f: Array[String], tag: String, votes: Dictionary, wired: bool):
	var world = WorldScript.new()
	world.bespoke_enemy_views = wired
	var root := _root()
	if root != null:
		root.add_child(world)
	if not world.build(SEED, LEVEL, _ledger(votes)):
		f.append("%s: world failed to build level %d seed %d" % [tag, LEVEL, SEED])
		_drop(world)
		return null
	return world


func _drop(world) -> void:
	world.teardown()
	if world.get_parent() != null:
		world.get_parent().remove_child(world)
	world.free()


func _row_index(world, id: String) -> int:
	for i in world.rt.enemies.size():
		if str(world.rt.enemies[i]["id"]) == id:
			return i
	return -1


# ---- the nine views ------------------------------------------------------------------------

func _leg_view(f: Array[String], id: String, wired: bool) -> void:
	var tag := "%s%s" % [id, "" if wired else " (wiring off)"]
	var world = _build(f, tag, {id: 1}, wired)
	if world == null:
		return
	var idx := -1
	for _i in range(SPAWN_WAIT):
		world.step(DT)
		idx = _row_index(world, id)
		if idx >= 0 or bool(world.ctl.dead):
			break
	if idx < 0:
		f.append("%s: the planned row never spawned (dead %s)" % [tag, str(world.ctl.dead)])
		_drop(world)
		return
	for _i in range(FEED_TICKS):
		if bool(world.ctl.dead):
			break
		world.step(DT)
	var row: Dictionary = world.rt.enemies[idx]
	var host = world.enemy_views[idx] if idx < world.enemy_views.size() else null
	var view = host.view if host != null else null
	# 1. the bespoke view exists, in the world, in the tree
	if view == null:
		f.append("%s: no bespoke view built for the row" % tag)
	else:
		if not world.is_ancestor_of(view):
			f.append("%s: the view is not a descendant of the world" % tag)
		if not (view as Node).is_inside_tree():
			f.append("%s: the view is not inside the scene tree" % tag)
	# 2. nothing drawn twice: no generic billboard for a row with a bespoke view
	if idx < world.boards.size() and world.boards[idx] != null:
		f.append("%s: the generic billboard was built for the row" % tag)
	# 3. the view stands on the row's feet
	var feet := Vector3(float(row["x"]), float(row["y"]), float(row["z"]))
	if view != null and (view as Node3D).position.distance_to(feet) > 0.01:
		f.append("%s: view at %s, row at %s" % [tag, str((view as Node3D).position), str(feet)])
	# 4. the feed reached it: the view's OWN state moved
	if host == null or int(host.fed_ticks) <= 0:
		f.append("%s: the view was never stepped" % tag)
	var why := _fed(id, view, row)
	if why != "":
		f.append("%s: %s" % [tag, why])
	_drop(world)


## The view's own observable state after FEED_TICKS of world.step(), read from each view
## file. "" = fed; else what did not move.
func _fed(id: String, view, row: Dictionary) -> String:
	if view == null:
		return "no view to read the feed from"
	match id:
		"kiwi_cat":
			# step(): the bob clock advances 1/60 s per tick
			if float(view._bob_t) <= 0.0:
				return "kiwi bob clock never advanced (_bob_t %.3f)" % float(view._bob_t)
		"seal":
			# step(): the flipper-flap cadence re-arms to its 9-tick period
			if int(view._flap_audio_left) <= 0:
				return "seal flap cadence never armed (%d)" % int(view._flap_audio_left)
			if float(view.billboard.modulate.a) < 0.99:
				return "seal spawn fade never completed (alpha %.2f)" % float(view.billboard.modulate.a)
		"gift_larper":
			if int(view._anim_ticks) <= 0:
				return "gift larper tick clock never advanced"
		"thicc_ben":
			# setup() parks the spawn fade at alpha 0; advance() runs it to 1 over 30 ticks
			if float(view.billboard.modulate.a) < 0.99:
				return "ben spawn fade never ran (alpha %.2f)" % float(view.billboard.modulate.a)
		"you":
			if float(view._t) <= 0.0:
				return "you view clock never advanced"
		"address_me":
			# the state-entered latch tracks the row's anim_state ("" until fed)
			if str(view._prev_state) != str(row.get("anim_state", "")) or str(view._prev_state) == "":
				return "state latch '%s', row anim_state '%s'" % [str(view._prev_state),
						str(row.get("anim_state", ""))]
		"gin":
			if view._overlay == null or view._sword == null or view._sword.texture == null:
				return "gin overlay or imported sword failed to build"
			if view.billboard.visible:
				return "gin retained the old world billboard"
		"claude":
			if str(view._state) != str(row.get("anim_state", "")) \
					or str(view.anim_player.state_id) != str(row.get("anim_state", "")):
				return "claude state '%s' / player '%s', row '%s'" % [str(view._state),
						str(view.anim_player.state_id), str(row.get("anim_state", ""))]
		"isagi":
			var snap: Dictionary = view.last_snapshot
			if snap.is_empty() or str(snap.get("state", "")) != str(row.get("st", "")):
				return "isagi snapshot %s, row st '%s'" % [str(snap), str(row.get("st", ""))]
	return ""


# ---- telegraph routing ---------------------------------------------------------------------

func _tell(world, id: String, off: Vector3, at: int, kind: String, ticks: int,
		shape_of: Callable) -> int:
	var beh := TellBehavior.new()
	beh.at = at
	beh.kind = kind
	beh.ticks = ticks
	beh.shape_of = shape_of
	var c = world.ctl
	world.rt.spawn_at(id, "TELL " + id, beh, {"contact_kill": false, "id": id, "name": id},
			Vector3(float(c.x), float(c.y), float(c.z)) + off)
	return world.rt.enemies.size() - 1


## Real api.telegraph calls through the runtime reach the right view through world.step():
## the dash line (two copies of one id: only the copy that raised it changes state, and the
## line is drawn in the view's own frame, not doubled into world space), the teleport and
## the meow.
func _leg_telegraph_routing(f: Array[String], wired: bool) -> void:
	var tag := "telegraph routing%s" % ("" if wired else " (wiring off)")
	var world = _build(f, tag, {}, wired)
	if world == null:
		return
	var dash := func(row: Dictionary) -> Dictionary:
		var a := Vector3(float(row["x"]), float(row["y"]) + 0.3, float(row["z"]))
		var b := a + Vector3(0.0, 0.0, 20.0)
		return {"shape": "circle", "cx": a.x, "cz": a.z, "r": 0.0,
				"dash_line": [a.x, a.y, a.z, b.x, b.y, b.z]}
	var at_body := func(row: Dictionary) -> Dictionary:
		return {"shape": "circle", "cx": float(row["x"]), "cz": float(row["z"]), "r": 0.0}
	var seal_a := _tell(world, "seal", Vector3(30.0, 40.0, 0.0), 3, "dash_line", 45, dash)
	var seal_b := _tell(world, "seal", Vector3(-30.0, 40.0, 0.0), -1, "dash_line", 45, dash)
	var dest := Vector3(float(world.ctl.x) + 4.0, float(world.ctl.y), float(world.ctl.z))
	var tp := func(_row: Dictionary) -> Dictionary:
		return {"shape": "circle", "cx": dest.x, "cz": dest.z, "r": 1.5, "y0": dest.y}
	var ben := _tell(world, "thicc_ben", Vector3(0.0, 40.0, 30.0), 3, "teleport", 75, tp)
	var cat := _tell(world, "kiwi_cat", Vector3(0.0, 40.0, -30.0), 3, "meow", 12, at_body)
	for _i in range(6):
		world.step(DT)
	var hosts: Array = world.enemy_views
	var ha = hosts[seal_a] if seal_a < hosts.size() else null
	var hb = hosts[seal_b] if seal_b < hosts.size() else null
	var hben = hosts[ben] if ben < hosts.size() else null
	var hcat = hosts[cat] if cat < hosts.size() else null
	if ha == null or str(ha.view._state) != "telegraph" or int(ha.events_fed) != 1:
		f.append("%s: the dash line never reached the copy that raised it" % tag)
	elif ha.view._line_root == null or ha.view._line_root.get_child_count() == 0:
		f.append("%s: the dash line was not drawn" % tag)
	else:
		var first: Vector3 = (ha.view._line_root.get_child(0) as Node3D).position
		if first.length() > 1.0:
			f.append("%s: the first dash sits %s from the body - drawn in world space" % [tag, str(first)])
	if hb == null or str(hb.view._state) != "idle" or int(hb.events_fed) != 0:
		f.append("%s: the other copy took the dash line (or has no view)" % tag)
	if hben == null or str(hben.view._phase) != "telegraph":
		f.append("%s: the teleport never reached the ben view" % tag)
	if hcat == null or int(hcat.view._meow_left) <= 0:
		f.append("%s: the meow never reached the kiwi view" % tag)
	_drop(world)


# ---- screen effects ------------------------------------------------------------------------

## A paid void fall (the controller's void_fall event, free false) flashes the screen edge.
func _leg_void_flash(f: Array[String]) -> void:
	var world = _build(f, "void flash", {}, true)
	if world == null:
		return
	var fx = world.hud.screen_fx
	world.step(DT)
	if bool(fx.flash_active()):
		f.append("void flash: the edge flash is on before any fall")
	world.ctl.x = 10000.5
	world.ctl.y = 0.0
	world.ctl.z = 10000.5
	world.ctl.vx = 0.0
	world.ctl.vy = 0.0
	world.ctl.vz = 0.0
	world.ctl.grounded = false
	var before := int(world.ctl.charges)
	var fell := false
	for _i in range(400):
		world.step(DT)
		if int(world.ctl.charges) < before:
			fell = true
			break
		if bool(world.ctl.dead):
			break
	if not fell:
		f.append("void flash: no paid void fall happened (dead %s)" % str(world.ctl.dead))
	elif not bool(fx.flash_active()) or float(fx.flash_alpha()) <= 0.0:
		f.append("void flash: the paid fall did not flash the screen edge")
	_drop(world)


## A Last Light save (controller.try_kill -> last_light_save, here from a runtime body
## contact) blooms the screen white and shatters the pips row's Last Light icon.
func _leg_last_light(f: Array[String]) -> void:
	var world = _build(f, "last light", {}, true)
	if world == null:
		return
	var fx = world.hud.screen_fx
	var pips = world.hud.void_pips
	world.step(DT)
	if bool(fx.bloom_active()) or bool(pips.shatter_active()):
		f.append("last light: bloom / shatter on before any save")
	var beh := ContactBehavior.new()
	beh.target = world.ctl
	var c = world.ctl
	world.rt.spawn_at("kiwi_cat", "LAST LIGHT PROBE", beh,
			{"contact_kill": true, "id": "kiwi_cat", "name": "LAST LIGHT PROBE"},
			Vector3(float(c.x), float(c.y), float(c.z)))
	var saved := false
	for _i in range(240):
		world.step(DT)
		if bool(world.ctl.last_light_spent):
			saved = true
			break
		if bool(world.ctl.dead):
			break
	if not saved:
		f.append("last light: no save happened (dead %s)" % str(world.ctl.dead))
	else:
		if not bool(fx.bloom_active()):
			f.append("last light: the save did not start the white bloom")
		if not bool(pips.shatter_active()):
			f.append("last light: the save did not shatter the pips' Last Light icon")
	_drop(world)
