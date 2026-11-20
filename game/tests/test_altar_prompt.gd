extends RefCounted
#
# test_altar_prompt.gd (ALTAR SELECTION): the F-hold at an altar driven through the REAL app
# path (view/lobby/lobby_scene.gd, the node app.gd adds), and the prompt bar that tells the
# player what to press.
#
# Leg 1  walk + hold F -> a real Select index for an E bay; applied through
#        Intermission.step() it actually selects the enemy. And ONE continuous hold fires
#        exactly ONE Select: the hold/latch state keys on the altar SLOT, not on the wrapper
#        dict that refresh() rebuilds, so a pick can no longer be re-confirmed by the same
#        press (before the fix a 2 s hold on a shop bay bought three upgrades).
# Leg 2  negative control: the same walk with F NOT held -> NO_SELECT, and the same walk
#        standing 5 u away -> NO_SELECT.
# Leg 3  the bar is hidden with no altar in range, visible on exactly one altar when one is,
#        and its text carries the item's name and the keybind letter F.
# Leg 4  the bar CROSSES the exhibit body: its world Y is inside the body band, not above it.
# Leg 5  walking away hides the bar again.
#
# Headless, outside the scene tree, like test_app_lobby.gd.

const LobbySceneScript := preload("res://view/lobby/lobby_scene.gd")
const IntermissionScript := preload("res://sim/intermission.gd")
const InputScript := preload("res://sim/input.gd")
const Antechamber := preload("res://view/lobby/antechamber.gd")

const DT := 1.0 / 60.0
const SEED := 1234
const LEVEL := 1          # E (mandatory) + U (optional): the E bay is the one to select
const HOLD_TICKS := 40    # 0.67 s, comfortably past HOLD_S (0.35 s)
const LONG_HOLD := 120    # 2.0 s: one press, so still exactly one Select
const WALK_TICKS := 600


func run() -> Array[String]:
	var f: Array[String] = []
	_leg1_walk_and_select(f)
	_leg1_one_press_one_select(f)
	_leg2_negative_controls(f)
	_leg3_bar_visibility_and_text(f)
	_leg4_bar_crosses_the_exhibit(f)
	_leg5_walking_away_hides(f)
	return f


# ---- helpers -----------------------------------------------------------------------------

## Builds the real lobby scene for LEVEL. The caller frees it.
func _build() -> Node3D:
	var scene: Node3D = LobbySceneScript.new()
	if not scene.build(SEED, LEVEL, {"purse": 400}):
		return null
	return scene


## The first altar wrapper of p_bay_kind / p_row_kind, or {} when the bay drew none.
func _altar(scene: Node3D, p_bay_kind: String, p_row_kind: String = "offer") -> Dictionary:
	for a in scene.hall._altars:
		if str(a["bay_kind"]) == p_bay_kind and str(a["kind"]) == p_row_kind:
			return a
	return {}


## Walks the player from spawn to p_stop with the captured int8 axes, exactly as
## lobby_scene.step() feeds them (no teleport: this is the real walk).
func _walk_to(scene: Node3D, p_stop: Vector3) -> int:
	var frames := 0
	while frames < WALK_TICKS:
		var feet: Vector3 = scene.player.feet()
		var d: Vector3 = p_stop - feet
		if d.length() < 0.15:
			break
		var mx := 0
		var mz := 0
		if absf(d.x) > 0.1:
			mx = 127 if d.x > 0.0 else -127
		if absf(d.z) > 0.1:
			mz = 127 if d.z > 0.0 else -127
		scene.tick(DT, mx, mz, false)
		frames += 1
	return frames


## Faces the player at p_target (yaw only: the hall's look cone is the camera's forward).
func _face(scene: Node3D, p_target: Vector3) -> void:
	var to_t: Vector3 = p_target - scene.player.feet()
	to_t.y = 0.0
	if to_t.length() > 1e-4:
		scene.player.rig.yaw_deg = rad_to_deg(atan2(-to_t.x, -to_t.z))


## Holds F for p_ticks; returns every Select index the ticks reported, in order.
func _hold(scene: Node3D, p_ticks: int) -> Array:
	var out: Array = []
	for _i in p_ticks:
		var res: Dictionary = scene.tick(DT, 0, 0, true)
		if int(res["select"]) != IntermissionScript.NO_SELECT:
			out.append(int(res["select"]))
	return out


## The number of altars whose prompt bar is visible right now.
func _bars_shown(scene: Node3D) -> int:
	var n := 0
	for a in scene.hall._altars:
		var bar: Node3D = a.get("bar")
		if bar != null and is_instance_valid(bar) and bar.visible:
			n += 1
	return n


# ---- Leg 1: the walk, the hold, and the Select that lands --------------------------------

## The owner's report: "i cannot select an enemy". Walk the real hall from spawn to an E
## altar, hold F past HOLD_S, and the Select must be a REAL altar_table() index that the
## sim's own input path accepts and acts on.
func _leg1_walk_and_select(f: Array[String]) -> void:
	var scene := _build()
	if scene == null:
		f.append("leg1: the lobby scene failed to build")
		return
	var target: Dictionary = _altar(scene, "E")
	if target.is_empty():
		f.append("leg1: the lobby drew no E-bay altar")
		scene.free()
		return
	var ap: Vector3 = (target["root"] as Node3D).position
	var frames: int = _walk_to(scene, Vector3(ap.x, 0.0, ap.z + 1.8))
	if frames >= WALK_TICKS:
		f.append("leg1: the player never reached the altar in %d frames" % WALK_TICKS)
	_face(scene, ap)
	var votes_before: int = int(scene.lobby.votes_sum())
	# The table BEFORE the pick: a resolved bay drops out of altar_table(), so reading it
	# afterwards would compare the index against a shifted table.
	var table: Array = scene.lobby.altar_table()
	var fired: Array = _hold(scene, HOLD_TICKS)
	if fired.is_empty():
		f.append("leg1: holding F for %.2f s at an E altar never confirmed a pick"
				% (HOLD_TICKS * DT))
		scene.free()
		return
	var sel: int = int(fired[0])
	if sel < 0 or sel >= table.size():
		f.append("leg1: the Select index %d is outside altar_table() (%d entries)"
				% [sel, table.size()])
	elif str(table[sel]["kind"]) != "offer" or str(table[sel]["bay"]) != "E":
		f.append("leg1: the Select index %d is %s/%s, want an E offer"
				% [sel, str(table[sel]["kind"]), str(table[sel]["bay"])])
	if int(scene.lobby.votes_sum()) != votes_before + 1:
		f.append("leg1: votes after the hold = %d, want %d (the sim did not take the Select)"
				% [int(scene.lobby.votes_sum()), votes_before + 1])
	# The same index through the sim's own input path, on a fresh state: it must change it.
	var replay: RefCounted = IntermissionScript.create(scene.lobby.content, LEVEL, 400,
			scene.lobby.rng_s)
	var before: int = int(replay.votes_sum())
	replay.step([InputScript.new(0, 0, 0, sel)])
	if int(replay.votes_sum()) != before + 1:
		f.append("leg1: Intermission.step() refused the Select index %d (votes %d -> %d)"
				% [sel, before, int(replay.votes_sum())])
	scene.free()


## ONE press is ONE Select. The hold/latch state keys on the altar SLOT, so the state
## rebuild a pick triggers cannot hand the same press a second confirm. A shop bay never
## resolves, so before the fix a single 2 s hold bought the whole stock.
func _leg1_one_press_one_select(f: Array[String]) -> void:
	var scene := _build()
	if scene == null:
		f.append("leg1b: the lobby scene failed to build")
		return
	var target: Dictionary = _altar(scene, "U")
	if target.is_empty():
		f.append("leg1b: the lobby drew no U-bay altar")
		scene.free()
		return
	var ap: Vector3 = (target["root"] as Node3D).position
	_walk_to(scene, Vector3(ap.x, 0.0, ap.z + 1.8))
	_face(scene, ap)
	scene.tick(DT, 0, 0, false)
	var stacks_before: int = (scene.lobby.upgrade_stacks as Dictionary).size()
	var fired: Array = _hold(scene, LONG_HOLD)
	if fired.size() != 1:
		f.append("leg1b: one %.1f s hold fired %d Selects, want exactly 1"
				% [LONG_HOLD * DT, fired.size()])
	var bought: int = (scene.lobby.upgrade_stacks as Dictionary).size() - stacks_before
	if bought > 1:
		f.append("leg1b: one hold bought %d upgrades, want at most 1" % bought)
	# A release re-arms the latch: the next press confirms again.
	scene.tick(DT, 0, 0, false)
	var again: Array = _hold(scene, HOLD_TICKS)
	if again.is_empty():
		f.append("leg1b: a second press after releasing F never confirmed again")
	scene.free()


# ---- Leg 2: the negative controls --------------------------------------------------------

## The same walk, twice, with the two things the confirm needs removed: F not held, and the
## player standing out of PROMPT_R. Both must return NO_SELECT, or Leg 1 proves nothing.
func _leg2_negative_controls(f: Array[String]) -> void:
	var scene := _build()
	if scene == null:
		f.append("leg2: the lobby scene failed to build")
		return
	var target: Dictionary = _altar(scene, "E")
	if target.is_empty():
		f.append("leg2: the lobby drew no E-bay altar")
		scene.free()
		return
	var ap: Vector3 = (target["root"] as Node3D).position
	# (a) standing right at the altar, facing it, F NOT held.
	_walk_to(scene, Vector3(ap.x, 0.0, ap.z + 1.8))
	_face(scene, ap)
	var idle: Array = []
	for _i in HOLD_TICKS:
		var res: Dictionary = scene.tick(DT, 0, 0, false)
		if int(res["select"]) != IntermissionScript.NO_SELECT:
			idle.append(int(res["select"]))
	if not idle.is_empty():
		f.append("leg2: F not held still fired %d Selects at the altar" % idle.size())
	# (b) the same walk, F held, but standing 5 u away (PROMPT_R is 2.5).
	_walk_to(scene, Vector3(ap.x, 0.0, ap.z + 5.0))
	_face(scene, ap)
	var far: float = scene.player.feet().distance_to(Vector3(ap.x, 0.0, ap.z))
	if far < 4.5:
		f.append("leg2: the walk stalled %.2f u from the altar, so the range test is untested"
				% far)
	var away: Array = _hold(scene, HOLD_TICKS)
	if not away.is_empty():
		f.append("leg2: holding F %.2f u away fired %d Selects, want none"
				% [far, away.size()])
	scene.free()


# ---- Leg 3: one bar, on the altar you are at, carrying the name and the keybind ----------

## Hidden at spawn, visible on exactly one altar when the player stands at one, and its text
## carries the item's display name and the keybind letter F.
func _leg3_bar_visibility_and_text(f: Array[String]) -> void:
	var scene := _build()
	if scene == null:
		f.append("leg3: the lobby scene failed to build")
		return
	scene.tick(DT, 0, 0, false)
	if _bars_shown(scene) != 0:
		f.append("leg3: %d bars are visible at spawn, want 0" % _bars_shown(scene))
	var target: Dictionary = _altar(scene, "E")
	if target.is_empty():
		f.append("leg3: the lobby drew no E-bay altar")
		scene.free()
		return
	var ap: Vector3 = (target["root"] as Node3D).position
	_walk_to(scene, Vector3(ap.x, 0.0, ap.z + 1.8))
	_face(scene, ap)
	scene.tick(DT, 0, 0, false)
	var shown: int = _bars_shown(scene)
	if shown != 1:
		f.append("leg3: %d bars are visible at the altar, want exactly 1" % shown)
	var bar: Node3D = target.get("bar")
	if bar == null or not is_instance_valid(bar) or not bar.visible:
		f.append("leg3: the bar of the altar the player stands at is not visible")
		scene.free()
		return
	var name: String = str(target.get("label", ""))
	var panel: Label3D = target.get("panel")
	if panel == null or not is_instance_valid(panel):
		f.append("leg3: the bar has no name label")
	elif name == "":
		f.append("leg3: the altar resolved no display name")
	elif not panel.text.contains(name):
		f.append("leg3: the bar reads %s, want it to carry the name %s"
				% [panel.text, name])
	var key: Label3D = target.get("key")
	if key == null or not is_instance_valid(key):
		f.append("leg3: the bar has no keybind glyph")
	elif key.text != "F":
		f.append("leg3: the keybind glyph reads %s, want F" % key.text)
	# The prompt string other code reads must still name the key and the item.
	var res: Dictionary = scene.tick(DT, 0, 0, false)
	var prompt: String = str(res.get("prompt", ""))
	if not prompt.contains("F"):
		f.append("leg3: out[\"prompt\"] = %s, want it to name the key F" % prompt)
	if name != "" and not prompt.contains(name):
		f.append("leg3: out[\"prompt\"] = %s, want it to name %s" % [prompt, name])
	scene.free()


# ---- Leg 4: the bar crosses the exhibit, it does not float above it -----------------------

## The owner asked for the text to OVERLAP the enemy. The bar's world Y must sit inside the
## exhibit body's band, and its top must not clear the body's top.
func _leg4_bar_crosses_the_exhibit(f: Array[String]) -> void:
	var scene := _build()
	if scene == null:
		f.append("leg4: the lobby scene failed to build")
		return
	for bay in ["E", "C", "U"]:
		var target: Dictionary = _altar(scene, bay)
		if target.is_empty():
			continue
		var ap: Vector3 = (target["root"] as Node3D).position
		_walk_to(scene, Vector3(ap.x, 0.0, ap.z + 1.8))
		_face(scene, ap)
		scene.tick(DT, 0, 0, false)
		var bar: Node3D = target.get("bar")
		if bar == null or not is_instance_valid(bar):
			f.append("leg4: the %s altar has no bar" % bay)
			continue
		var band: Vector2 = scene.hall._body_band(target)
		var y: float = bar.position.y
		if y < band.x or y > band.y:
			f.append("leg4: the %s bar sits at y=%.2f, outside the body band [%.2f, %.2f]"
					% [bay, y, band.x, band.y])
		var half: float = Antechamber.BAR_H * 0.5
		if y - half > band.y:
			f.append("leg4: the %s bar floats above the exhibit (bottom %.2f > body top %.2f)"
					% [bay, y - half, band.y])
	scene.free()


# ---- Leg 5: walking away hides the bar ---------------------------------------------------

## The bar belongs to the altar the player is AT. Step out of range and it goes.
func _leg5_walking_away_hides(f: Array[String]) -> void:
	var scene := _build()
	if scene == null:
		f.append("leg5: the lobby scene failed to build")
		return
	var target: Dictionary = _altar(scene, "E")
	if target.is_empty():
		f.append("leg5: the lobby drew no E-bay altar")
		scene.free()
		return
	var ap: Vector3 = (target["root"] as Node3D).position
	_walk_to(scene, Vector3(ap.x, 0.0, ap.z + 1.8))
	_face(scene, ap)
	scene.tick(DT, 0, 0, false)
	if _bars_shown(scene) != 1:
		f.append("leg5: the bar is not visible at the altar, so the walk-away test is untested")
	# Walk back out of PROMPT_R with the real movement, still facing the altar.
	_walk_to(scene, Vector3(ap.x, 0.0, ap.z + 5.0))
	_face(scene, ap)
	scene.tick(DT, 0, 0, false)
	if _bars_shown(scene) != 0:
		f.append("leg5: %d bars are still visible %.1f u away, want 0"
				% [_bars_shown(scene), scene.player.feet().distance_to(Vector3(ap.x, 0.0, ap.z))])
	scene.free()
