extends Control
#
# view/tester/debug_panel.gd - the TESTER build's debug panel (cycle 7, track T2).
#
# THE OWNER'S WORDS: "tester build with debug panel (owner only, never in public releases)".
#
# This script lives ONLY in exports built with the custom "tester" feature tag
# (export_presets.cfg preset "Tester"; the three public presets exclude view/tester/* from
# their pack). app.gd holds exactly one GUARDED REFERENCE to it - a load() (never
# preload()) behind OS.has_feature("tester") - so a public build can never resolve the
# path: the tag is absent (the branch is dead) and the file is not in the pack either.
# It is never uploaded, never in a release, and CI's matrix only names the three public
# presets.
#
# WHAT IT DOES (all actions mutate LIVE app/world state through the game's own public
# functions - the sim layer's code, its state-hash dump format and its 60 Hz determinism
# are untouched; see D-T2-1..D-T2-8 in DECISIONS.md):
#   F10                    open / close (the mouse is released while it is open)
#   spawn any enemy        in front of the player or at the cursor's ground point, through
#                          enemy_runtime.spawn_at() - the runtime's own direct-spawn
#                          entry. The dropdown carries EVERY registry enemy plus one
#                          pinned Peter entry (D-T2-10): the boss is not registry
#                          content, so his row is fixed here and _spawn routes it to the
#                          FORCE PETER machinery - _enter_boss_arena(), never a second
#                          boss spawn path. Both dropdowns' popups are capped to the
#                          window height, so a long list SCROLLS and every entry stays
#                          reachable (D-T2-10).
#   give any upgrade       +1 owned stack: folded into the ledger (carries to every later
#                          level) and re-applied to the live stats (world's
#                          apply_tester_upgrade_stack; the stack's EVENT hooks go live from
#                          the next level's build)
#   give gold / give gifts gold straight into the economy's purse; N gifts collected
#                          through sim/gifts.gd collect() nearest-first AS A QUEUED TICK
#                          JOB (D-T2-4/D-T2-9) - the natural collect path, beacon open
#                          included, with the SAME tick's economy / upgrade-hook / fx
#                          passes consuming the events (payouts and hooks land)
#   skip to level N /      the app's own level-transition calls (run_ledger -> build ->
#                          go live), never a sim bypass
#   skip the current level world completion signal path -> the Antechamber
#   set charges            the controller's own void-charge count
#   god mode               per-frame top-up: try_kill's invulnerability window stays open
#                          and void charges never run out (D-T2-6)
#   force a collapse       sim/collapse.gd CollapseScript.start() on the live schedule -
#                          world.step() then drives the cracks/falls exactly as normal
#   force Peter boss /     through the REAL T8 API (merged main): _enter_boss_arena() -
#   force Bankai           the arena's own full entry (teleport, first-person rig, HUD) -
#                          as a queued tick job; Bankai plays the dormant owner cinematic
#                          THROUGH its signals (target_hit drives boss.damage(hp_max) -
#                          the easter egg's insta-kill); an explicit boss-API force
#                          entry, if the T8b track adds one, wins over the fallback
#   state hash             sim/state_hash.gd's digest over the LIVE level: the same dump
#                          every replay checkpoint pins, minus the RNG lines (D-T2-8: the
#                          app driver holds no sim rng streams - the sim-driver contexts
#                          test_replay / bot_run keep the full hash untouched)
#
# The whole layout is built in _init (no .tscn, the pause-overlay precedent): constructible
# and assertable headless, and one folder to exclude from the public packs.

const UiStyle := preload("res://view/ui_style.gd")
const CameraRigScript := preload("res://app/camera_rig.gd")
const CollisionScript := preload("res://sim/collision.gd")
const CollapseScript := preload("res://sim/collapse.gd")
const ContentApiScript := preload("res://core/content_api.gd")
const EconomyScript := preload("res://sim/economy.gd")
const StateHashScript := preload("res://sim/state_hash.gd")

## Above the pause overlay's layer (129): a debug panel must sit over everything, and the
## pause overlay can still freeze the run under it (only the DEPTH matters - F10 works
## while paused, and the pause overlay's own keys keep working).
const PANEL_LAYER := 130
const TOGGLE_KEY := KEY_F10
const SPAWN_AHEAD_U := 4.0    # "in front of the player": this many u along the look dir
const CURSOR_MAX_U := 200.0   # "at the cursor": the ray never marches past this
const GROUND_LIMIT_U := 12.0  # ground snap window over the target's feet plane

## D-T2-10: the owner's cycle-8 ask - the boss must be IN the list and spawnable. He is
## not registry content (he lives in data/boss.json + sim/boss.gd), so the row is pinned
## here and _spawn routes it to the FORCE PETER machinery, never to the enemy runtime.
const PETER_ID := "peter"
const PETER_LABEL := "Peter Griffin (peter)"
## D-T2-10: a dropdown popup caps at this share of the viewport height, so a list that
## outgrows the window scrolls inside the popup and every entry stays reachable.
const POPUP_MAX_H_SHARE := 0.6

## T8 (merged, D-T2-7-amend): the real boss API - sim/boss.gd one instance per arena,
## lstate.boss holds it; world.gd's _enter_boss_arena() is the arena's own full entry
## (boss.start(run_seed, level), the arena rebuild, the teleport, the first-person rig,
## the HUD), so the panel routes FORCE PETER through it, never through boss.start alone.
const BossScript := preload("res://sim/boss.gd")
## Bankai: an explicit force entry on the boss object (the T8b attack track may add one)
## is preferred when present; otherwise the panel plays the dormant owner cinematic
## through its own signals (D-T2-7-amend): target_hit drives boss.damage() - the
## contract's insta-kill - animation_finished frees the node.
const BANKAI_FORCE_METHODS: Array[String] = ["force_bankai", "play_bankai"]
const BANKAI_CINEMATIC_PATH := "res://view/cinematics/bankai_gift_animation.gd"

var _app: Node = null          # game/app/app.gd (passed by setup(); never a scene ref)
var _layer: CanvasLayer = null  # every drawn node lives here (PANEL_LAYER)
var _content: OptionButton = null   # enemy dropdown (content registry ids, runtime-loaded)
var _upgrade_pick: OptionButton = null
var _gold_spin: SpinBox = null
var _gift_spin: SpinBox = null
var _charge_spin: SpinBox = null
var _level_edit: LineEdit = null
var _boss_button: Button = null
var _bankai_button: Button = null
var _god_button: Button = null
var _status_line: Label = null
var _meta_line: Label = null
var _hash_line: Label = null
var _god := false
var _frame := 0
## Queued per-tick jobs (D-T2-4/D-T2-9): each {"run": Callable} drains INSIDE the world's
## next tick; the callable appends its events to the tick's own list and may return true
## to finish the tick itself (the forced arena entry does).
var _pending: Array = []


## Binds the panel to the app. Called by app.gd's tester hook, behind the feature tag.
func setup(p_app: Node) -> void:
	_app = p_app


func _init() -> void:
	name = "TesterDebugPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # clicks outside the column reach the game
	visible = false
	_layer = CanvasLayer.new()
	_layer.name = "TesterPanelLayer"
	_layer.layer = PANEL_LAYER
	_layer.visible = false
	add_child(_layer)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	scroll.offset_left = UiStyle.EDGE
	scroll.offset_top = UiStyle.EDGE
	scroll.offset_bottom = -float(UiStyle.EDGE)
	scroll.custom_minimum_size = Vector2(370.0, 0.0)
	_layer.add_child(scroll)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_theme_constant_override("separation", UiStyle.SP_2)
	scroll.add_child(column)

	var title := UiStyle.label("TESTER", "display")
	title.add_theme_font_size_override("font_size", 32)
	column.add_child(title)
	column.add_child(UiStyle.label("owner build - never released", "label"))
	_meta_line = UiStyle.label("no run", "small", UiStyle.TEXT_MUTED)
	_meta_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_meta_line)
	column.add_child(UiStyle.rule(28.0))

	# ---- enemies -----------------------------------------------------------------------
	# D-T2-10: the dropdown owns its row (full column width) and the two spawn buttons
	# share the row below it - the old single row was 432 u wide inside a 370 u column,
	# so the CURSOR button sat outside the viewport and pieces of the section were cut
	# off. Every row now fits the scroll column with room to spare.
	column.add_child(_section_label("ENEMIES"))
	_content = OptionButton.new()
	_content.name = "EnemyPick"
	_content.custom_minimum_size = Vector2(0.0, UiStyle.BUTTON_H)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_font_size_override("font_size", UiStyle.FS_SMALL)
	UiStyle.style_button(_content, UiStyle.SECONDARY)
	column.add_child(_content)
	var ep := HBoxContainer.new()
	ep.add_theme_constant_override("separation", UiStyle.SP_2)
	column.add_child(ep)
	var ahead := _mkbtn(ep, "SPAWN AHEAD", _spawn_ahead, UiStyle.PRIMARY, 156.0)
	ahead.name = "SpawnAhead"
	var atcur := _mkbtn(ep, "SPAWN AT CURSOR", _spawn_at_cursor, UiStyle.PRIMARY, 156.0)
	atcur.name = "SpawnCursor"

	# ---- upgrades / gold / gifts -------------------------------------------------------
	# D-T2-10: the same shape as the enemies section - the option's CONTENT (its widest
	# item) sets its minimum, so an upgrade id can force the picker wider than the paired
	# button row ever fits (337 + 64 + 8 = 409 px inside the 370-px column). The picker
	# owns a full-width row; GIVE +1 lives under it.
	column.add_child(_section_label("UPGRADE"))
	_upgrade_pick = OptionButton.new()
	_upgrade_pick.name = "UpgradePick"
	_upgrade_pick.custom_minimum_size = Vector2(0.0, UiStyle.BUTTON_H)
	_upgrade_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrade_pick.add_theme_font_size_override("font_size", UiStyle.FS_SMALL)
	UiStyle.style_button(_upgrade_pick, UiStyle.SECONDARY)
	column.add_child(_upgrade_pick)
	var give_up := _mkbtn(column, "GIVE +1 STACK", _give_upgrade, UiStyle.PRIMARY, -1.0)
	give_up.name = "GiveUpgrade"

	var gh := HBoxContainer.new()
	gh.add_theme_constant_override("separation", UiStyle.SP_2)
	column.add_child(gh)
	_gold_spin = SpinBox.new()
	_gold_spin.min_value = 1
	_gold_spin.max_value = 100000
	_gold_spin.value = 25
	_gold_spin.custom_minimum_size = Vector2(112.0, UiStyle.BUTTON_H)
	gh.add_child(_gold_spin)
	var give_gold := _mkbtn(gh, "GIVE GOLD", _give_gold, UiStyle.PRIMARY, -1.0)
	give_gold.name = "GiveGold"

	_gift_spin = SpinBox.new()
	_gift_spin.min_value = 1
	_gift_spin.max_value = 200
	_gift_spin.value = 1
	_gift_spin.custom_minimum_size = Vector2(112.0, UiStyle.BUTTON_H)
	column.add_child(_gift_spin)
	var give_gifts := _mkbtn(column, "GIVE N GIFTS (NEAREST, VIA THE TICK)", _give_gifts,
			UiStyle.SECONDARY, -1.0)
	give_gifts.name = "GiveGifts"

	# ---- level / charges / god ---------------------------------------------------------
	column.add_child(_section_label("RUN"))
	var lh := HBoxContainer.new()
	lh.add_theme_constant_override("separation", UiStyle.SP_2)
	column.add_child(lh)
	_level_edit = LineEdit.new()
	_level_edit.text = "2"
	_level_edit.custom_minimum_size = Vector2(80.0, UiStyle.BUTTON_H)
	lh.add_child(_level_edit)
	var skip_to := _mkbtn(lh, "SKIP TO LEVEL", _skip_to_level, UiStyle.PRIMARY, -1.0)
	skip_to.name = "SkipToLevel"
	var skip_lvl := _mkbtn(column, "SKIP LEVEL -> ANTICHAMBER", _skip_level, UiStyle.SECONDARY, -1.0)
	skip_lvl.name = "SkipLevel"

	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", UiStyle.SP_2)
	column.add_child(ch)
	_charge_spin = SpinBox.new()
	_charge_spin.min_value = 0
	_charge_spin.max_value = 99
	_charge_spin.value = 2
	_charge_spin.custom_minimum_size = Vector2(80.0, UiStyle.BUTTON_H)
	ch.add_child(_charge_spin)
	var set_charges := _mkbtn(ch, "SET CHARGES", _set_charges, UiStyle.PRIMARY, 148.0)
	set_charges.name = "SetCharges"
	var god := _mkbtn(column, "GOD MODE: OFF", _toggle_god, UiStyle.SECONDARY, -1.0)
	god.name = "GodToggle"
	_god_button = god

	var force_collapse := _mkbtn(column, "FORCE COLLAPSE", _force_collapse, UiStyle.SECONDARY, -1.0)
	force_collapse.name = "ForceCollapse"

	# ---- boss / bankai -----------------------------------------------------------------
	column.add_child(_section_label("BOSS (T8)"))
	_boss_button = _mkbtn(column, "FORCE PETER BOSS", _force_boss, UiStyle.SECONDARY, -1.0)
	_boss_button.name = "ForceBoss"
	_bankai_button = _mkbtn(column, "FORCE BANKAI", _force_bankai, UiStyle.SECONDARY, -1.0)
	_bankai_button.name = "ForceBankai"

	# ---- state hash --------------------------------------------------------------------
	column.add_child(_section_label("STATE HASH (D-T2-8)"))
	_hash_line = UiStyle.label("...", "small")
	_hash_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_hash_line)

	_status_line = UiStyle.label("F10 opens and closes this panel", "small", UiStyle.TEXT_MUTED)
	_status_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status_line)
	var hints := UiStyle.key_hints([["F10", "toggle panel"]])
	column.add_child(hints)


func _mkbtn(p_parent: Control, p_text: String, p_press: Callable, p_kind: String,
		p_width: float) -> Button:
	var b := Button.new()
	b.text = p_text
	if p_width > 0.0:
		b.custom_minimum_size = Vector2(p_width, UiStyle.BUTTON_H)
	else:
		b.custom_minimum_size = Vector2(UiStyle.BUTTON_W, UiStyle.BUTTON_H)
	UiStyle.style_button(b, p_kind)
	b.pressed.connect(p_press)
	p_parent.add_child(b)
	return b


func _section_label(p_text: String) -> Label:
	var l := UiStyle.label(p_text, "label", UiStyle.TEXT_DIM)
	return l


# ---- open / close / input -----------------------------------------------------------------


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	_layer.visible = true
	_refresh_options()
	_refresh_boss_labels()
	_set_capture(false)
	_status("tester panel open - the mouse is free while it shows")


func close() -> void:
	visible = false
	_layer.visible = false
	_set_capture(true)
	_status("")


## A CanvasLayer does not follow its parent's visibility (the pause-overlay idiom).
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and _layer != null:
		_layer.visible = is_visible_in_tree()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and int((event as InputEventKey).keycode) == TOGGLE_KEY:
		if visible:
			close()
		else:
			open()
		if is_inside_tree():
			get_viewport().set_input_as_handled()


## Release (or re-capture) the mouse of the live run, the single-writer way: the frozen
## node's _mouse_locked flag, then its own apply_mouse_mode() (the pause overlay's rule).
func _set_capture(p_captured: bool) -> void:
	if _app == null:
		return
	var frozen = null
	match str(_app.state()):
		"WORLD":
			frozen = _app.get("_world")
		"LOBBY":
			frozen = _app.get("_lobby")
	if frozen == null:
		return
	frozen.set("_mouse_locked", p_captured)
	frozen.call("apply_mouse_mode")


# ---- live-state access (never cached: the app tears worlds down mid-tick) -------------------


## The live world node, or null outside a run (the app nulls _world on every teardown).
func _world() -> Node:
	if _app == null:
		return null
	var w = _app.get("_world")
	return w if w != null and (w is Node) and w.is_inside_tree() else null


## The world's content registry; falls back to a fresh load when no level is live (the
## menu and the lobby carry no world, and the list must never come up empty there).
func _api() -> RefCounted:
	var w := _world()
	if w != null:
		var a = w.get("_api")
		if a is RefCounted:
			return a
	var fallback: RefCounted = ContentApiScript.load()
	return fallback if fallback.is_ok() else null


func _player_feet(w: Node) -> Vector3:
	var ctl = w.get("ctl")
	if ctl == null:
		return Vector3.ZERO
	return Vector3(float(ctl.get("x")), float(ctl.get("y")), float(ctl.get("z")))


func _status(p_line: String) -> void:
	if _status_line != null:
		_status_line.text = p_line


## Refill the enemy / upgrade dropdowns from the content registry - ids are read from the
## running registry, never named here (the boundary rule holds inside the tester too).
## D-T2-10: the enemy list ends with the pinned Peter row (the boss is not registry
## content, and the owner wants him pickable from the same list), and both popups are
## re-capped to the window height so a long list scrolls and every entry is reachable.
func _refresh_options() -> void:
	var api := _api()
	if api == null:
		return
	_content.clear()
	for id in api.enemy_ids():
		var entry: Dictionary = api.enemy(str(id))
		_add_option(_content, "%s (%s)" % [str(entry.get("name", id)), str(id)], str(id))
	_add_option(_content, PETER_LABEL, PETER_ID)
	_content.selected = 0 if _content.item_count > 0 else -1
	_upgrade_pick.clear()
	for id in api.upgrade_ids():
		var entry: Dictionary = api.upgrade(str(id))
		_add_option(_upgrade_pick, "%s (%s)" % [str(entry.get("name", id)), str(id)], str(id))
	_upgrade_pick.selected = 0 if _upgrade_pick.item_count > 0 else -1
	_cap_popups()


## Cap both dropdown popups to a share of the viewport height (D-T2-10): the popup is a
## Window, so max_size (height half) clamps it and PopupMenu scrolls inside it - entries
## below the fold stay reachable (this engine build has NO PopupMenu.max_height; the
## Window cap is the supported equivalent). A no-op outside the tree (nothing to
## measure) - the cap is re-applied on every refresh while open.
func _cap_popups() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var cap := int(vp.get_visible_rect().size.y * POPUP_MAX_H_SHARE)
	for pick in [_content, _upgrade_pick]:
		if pick != null:
			var pop: PopupMenu = pick.get_popup()
			pop.max_size = Vector2i(0, cap)


## T8 (merged) worked buttons: the labels say what the press will act on.
func _refresh_boss_labels() -> void:
	if _boss_button != null:
		_boss_button.text = "FORCE PETER BOSS"
	if _bankai_button != null:
		_bankai_button.text = "FORCE BANKAI"


## app.gd's handoff point (D-T2-9): every world reaches the panel here BEFORE it enters
## the tree and takes its first step, so the per-tick probe is armed from the world's
## first tick on - a promised god mode covers it, and queued jobs always find their hook.
## A fallback in _process() catches worlds that arrive any other way.
func on_world_built(p_world: Node) -> void:
	if p_world == null:
		return
	_arm_world(p_world)
	_refresh_options()


func _arm_world(p_world: Node) -> void:
	p_world.set("tester_tick_hook", Callable(self, "_tick_hook"))
	p_world.set("tester_god", _god)
	if _god:
		_god_pass()


## The panel's per-tick probe (world.gd step() calls it at the tick top, before anything
## this tick can kill - D-T2-9). Returns {"ev": this tick's panel events, "skip": whether
## an action finished the tick itself} so the queued jobs' events ride the SAME list the
## tick's own economy / upgrade-hook / fx passes consume (Terra review round 1 findings
## 1-5). God mode tops up HERE as well, so it protects a fresh world's first tick.
func _tick_hook() -> Dictionary:
	var out := {"ev": [], "skip": false}
	if _god:
		_god_pass()
	while not _pending.is_empty():
		var job: Dictionary = _pending.pop_front()
		var run: Callable = job.get("run", Callable())
		if run.is_valid():
			if bool(run.call(out["ev"])):
				out["skip"] = true
	return out


## Queue one job for the world's next tick.
func _queue_job(p_run: Callable, p_note: String) -> void:
	_pending.append({"run": p_run})
	_status(p_note)


## Pure: the first (object, method) pair where the object answers the method. Script
## objects are asked for SCRIPT methods via has_script_method() (the T8 API is a sim
## script; the panel never instantiates sim classes itself, and get_script_method_list
## proves statics are covered). p_methods is untyped deliberately: callers hand in
## plain array literals, and a typed Array[String] parameter rejects those at runtime.
static func _first_matching(p_objects: Array, p_methods: Array) -> Dictionary:
	var is_script: bool = false
	for o in p_objects:
		is_script = o is Script
		for m in p_methods:
			var ok := false
			if is_script:
				var s: Script = o
				ok = s.has_script_method(m)
			elif o is Object:
				ok = (o as Object).has_method(m)
			if ok:
				return {"obj": o, "method": m}
	return {}


## Refresh the meta line + the state hash while the panel shows. Every read is live state;
## nothing is cached across frames.
func _process(_delta: float) -> void:
	if _god:
		_god_pass()
	_frame += 1
	# Arming fallback (D-T2-9): app.gd hands every _build_world world to on_world_built;
	# worlds that arrive by any other path get the probe here, before their visible checks.
	var live := _world()
	if live != null:
		var hook = live.get("tester_tick_hook")
		if hook == null or not (hook as Callable).is_valid():
			_arm_world(live)
	if not visible:
		return
	var w := live
	if _frame % 15 != 0:
		return
	if w == null:
		_meta_line.text = "no live level - state %s" % str(_app.state()) if _app != null \
				else "no app"
		_hash_line.text = "..."
		return
	var ls: RefCounted = w.get("lstate")
	var level := int(w.get("_level_number"))
	var tick := int(ls.get("tick")) if ls != null else 0
	var g = ls.get("gifts") if ls != null else null
	var phase := str(g.get("phase")) if g != null else "-"
	var eco = w.get("_economy")
	var purse := int(eco.call("purse_gold")) if eco != null else -1
	_meta_line.text = "SEED %d  STATE %s  LEVEL %d  TICK %d   PHASE %s   PURSE %d" % [
		int(_app.call("run_seed")), str(_app.state()), level, tick, phase, purse]
	var rs := _build_live_run_state(w)
	if rs == null:
		_hash_line.text = "..."
		return
	_hash_line.text = StateHashScript.sha256(rs)


## God mode (D-T2-6): top the controller's invulnerability window up every frame - the
## framework's try_kill() then suppresses every raised kill (kill_suppressed) - and keep
## the void charges at the fall cost so a fall is paid, respawning instead of dying.
## The last-light / field-dressing logic is untouched; god mode only ever ADDS the two
## values it tops up. Runs even while the panel is closed (a toggle, not a modal state).
func _god_pass() -> void:
	var w := _world()
	if w == null:
		return
	var ctl = w.get("ctl")
	if ctl == null:
		return
	if float(ctl.get("invuln")) < 1.0:
		ctl.set("invuln", 1.0)
	var cost := int(ctl.get("void_fall_charge_cost"))
	if int(ctl.get("charges")) < cost:
		ctl.set("charges", cost)


# ---- actions --------------------------------------------------------------------------------


func _selected_id(p_pick: OptionButton) -> String:
	if p_pick == null or p_pick.selected < 0 or p_pick.item_count == 0:
		return ""
	return p_pick.get_item_metadata(p_pick.selected) \
		if p_pick.get_item_metadata(p_pick.selected) != null else ""


## Row ids ride the item metadata (the label is display text).
func _add_option(p_pick: OptionButton, p_label: String, p_id: String) -> void:
	p_pick.add_item(p_label)
	p_pick.set_item_metadata(p_pick.item_count - 1, p_id)


func _spawn_ahead() -> void:
	_spawn(false)


func _spawn_at_cursor() -> void:
	_spawn(true)


## Spawn through enemy_runtime.spawn_at() - the runtime's own direct-spawn entry (the same
## row shape the vote plan produces). The view/billboard pass adopts the new row on the
## next frame, exactly as it does the planned bodies. D-T2-10: the pinned Peter row routes
## to _force_boss() - the arena's own full entry - so the boss spawns through the boss
## machinery, never through the enemy runtime (he is not a registry enemy).
func _spawn(p_at_cursor: bool) -> void:
	var w := _world()
	if w == null:
		_status("no live level - spawn needs a run in WORLD state")
		return
	var api := _api()
	var id := _selected_id(_content)
	if id == "" or api == null:
		_status("pick an enemy first (or the registry is down)")
		return
	if id == PETER_ID:
		_force_boss()
		return
	var entry: Dictionary = api.enemy(id)
	var beh = w.call("_behavior_for", id)
	var cfg: Dictionary = w.call("_cfg_for", entry, id, int(w.get("_level_number")), 1, beh)
	var pos := _spawn_position(w, p_at_cursor)
	var ename := str(entry.get("name", id))
	var rt = w.get("rt")
	if rt == null:
		_status("no enemy runtime on this level")
		return
	rt.call("spawn_at", id, ename, beh, cfg, pos)
	_status("spawned %s at (%.1f, %.1f, %.1f)%s" % [ename, pos.x, pos.y, pos.z,
			" at the cursor" if p_at_cursor else " ahead of the player"])


## The spawn ground point: "at the cursor" walks the camera ray onto the player's feet
## plane (any surface above the plane up to GROUND_LIMIT_U wins, so a look at a tall tile
## lands on it), "ahead" is SPAWN_AHEAD_U along the screen-centre ray's ground shadow.
## Both fall back to just in front of the player when the camera is missing.
func _spawn_position(w: Node, p_at_cursor: bool) -> Vector3:
	var feet := _player_feet(w)
	var plane_y := feet.y
	var cam: Camera3D = w.get("camera")
	if cam == null or not cam.is_inside_tree():
		return _ground_snap(w, feet + Vector3(0.0, 0.0, -SPAWN_AHEAD_U))
	var vp := get_viewport().get_visible_rect().size
	var param := get_viewport().get_mouse_position() if p_at_cursor else vp * 0.5
	var origin := cam.project_ray_origin(param)
	var dir := cam.project_ray_normal(param)
	var t := (plane_y - origin.y) / dir.y if not is_zero_approx(dir.y) else 0.0
	if dir.y >= -1e-4 or t <= 0.0:
		t = CURSOR_MAX_U * 0.25   # looking level or up: drop it far out along the look
	t = clampf(t, 0.5, CURSOR_MAX_U)
	var hit := origin + dir * t
	if p_at_cursor:
		return _ground_snap(w, hit)
	var d2 := Vector2(hit.x - feet.x, hit.z - feet.z)
	if d2.length() < 0.05:
		d2 = Vector2(0.0, 1.0)
	d2 = d2.normalized() * SPAWN_AHEAD_U
	return _ground_snap(w, Vector3(feet.x + d2.x, plane_y, feet.z + d2.y))


## Highest standable surface at (x, z) within GROUND_LIMIT_U over the plane, else the
## plane itself (the runtime's support pass drops a floating body onto real ground).
static func _ground_snap(w: Node, p: Vector3) -> Vector3:
	var world: Dictionary = w.get("w")
	var sup: Variant = CollisionScript.support_at(world, p.x, p.z, p.y, GROUND_LIMIT_U)
	if sup is float and float(sup) > -1e30:
		return Vector3(p.x, float(sup), p.z)
	return p


func _give_upgrade() -> void:
	var w := _world()
	var id := _selected_id(_upgrade_pick)
	if w == null:
		_status("no live level - the stack would be lost")
		return
	if id == "":
		_status("pick an upgrade first")
		return
	w.call("apply_tester_upgrade_stack", id)
	_status("gave +1 stack of %s: stats re-applied; its event hooks go live next level" % id)


func _give_gold() -> void:
	var w := _world()
	if w == null:
		_status("no live level - gold needs a run in WORLD state")
		return
	var eco = w.get("_economy")
	if eco == null:
		_status("no economy on this level")
		return
	var n := int(_gold_spin.value)
	eco.set("purse_centi", int(eco.get("purse_centi")) + n * EconomyScript.CENTI)
	_status("gave %d gold (purse %d)" % [n, int(eco.call("purse_gold"))])


## N gifts collected nearest-first through sim/gifts.gd's own collect() - the normal
## collection path, and the beacon open exactly as GiftsScript.tick performs it.
## QUEUED (Terra review round 1 finding 2, D-T2-4-amend): the job runs inside the world's
## next tick and appends to that tick's own event list, so the gold payouts, the upgrade
## hooks and every other per-tick consumer of gift_collected see the collects - never a
## collect that skips its normal effects. In the boss arena there are no gifts: the run
## inside _run_give_gifts reports it live, on the tick.
func _give_gifts() -> void:
	var w := _world()
	if w == null:
		_status("no live level - gifts need a run in WORLD state")
		return
	var n := int(_gift_spin.value)
	_queue_job(Callable(self, "_run_give_gifts").bind(n),
			"giving %d gift(s) on the next tick" % n)


## The queued job body: returns false (a normal collect; the tick continues).
func _run_give_gifts(n: int, ev: Array) -> bool:
	var w := _world()
	if w == null:
		return false
	var ls: RefCounted = w.get("lstate")
	var g = ls.get("gifts") if ls != null else null
	if g == null:
		_status("no gift state on this tick (the boss arena has no gifts)")
		return false
	var feet := _player_feet(w)
	var by_dist: Array = []
	for i in int(g.get("slots").size()):
		if not bool(g.call("present", i)):
			continue
		var pos: Vector3 = g.call("slot_pos", i)
		by_dist.append({"i": i, "d": feet.distance_squared_to(pos)})
	by_dist.sort_custom(func(a, b) -> bool: return float(a["d"]) < float(b["d"]))
	var got := 0
	var opened := false
	for row in by_dist:
		if got >= n:
			break
		g.call("collect", int(row["i"]), int(ls.get("tick")), 0, ev)
		got += 1
		if str(g.get("phase")) == "gold" and not opened:
			opened = true
	if opened:
		var b = ls.get("beacon")
		if b != null and not bool(b.call("is_open")):
			ev.append(b.call("open", int(ls.get("tick"))))
	_status("collected %d gift(s) nearest-first%s" % [got,
			"; the beacon is open" if opened else ""])
	return false


func _set_charges() -> void:
	var w := _world()
	if w == null:
		_status("no live level - charges need a run in WORLD state")
		return
	var ctl = w.get("ctl")
	if ctl == null:
		_status("no controller on this level")
		return
	var n := int(_charge_spin.value)
	ctl.set("charges", n)
	_status("charges set to %d (cap stays %d - the HUD reads the live count)" % [
		n, int(ctl.get("charge_cap"))])


func _toggle_god() -> void:
	_god = not _god
	# the world mirror (D-T2-6-amend): the boss ARENA kills via ctl._die directly, so the
	# flag rides the world too (world.gd honours it there); the tick hook also tops the
	# controller up at every tick top, which covers a fresh world's first tick.
	var w := _world()
	if w != null:
		w.set("tester_god", _god)
	if _god and w != null:
		_god_pass()
	if _god_button != null:
		_god_button.text = "GOD MODE: %s" % ("ON" if _god else "OFF")
	_status("god mode %s - kills suppressed (levels and arena), falls never drain the last charge" %
			("on" if _god else "off"))


## Skip the CURRENT level through the app's own completion path (the run ledger is read,
## the world is torn down, the Antechamber opens) - never a sim bypass.
func _skip_level() -> void:
	if _app == null:
		return
	if str(_app.state()) != "WORLD" or _app.get("_world") == null:
		_status("no live level to skip (state %s)" % str(_app.state()))
		return
	var level := int(_app.get("_world").call("level_number"))
	_app.call("_on_level_completed")
	_status("skipped level %d - the Antechamber opens; skip again from there if needed"
			% level)


## Skip to level N with the run's carried ledger: the app's own hand-off, the same
## sequence _on_lobby_exited runs (ledger -> free the old nodes -> _build_world -> go
## live). The next level is a pure function of (seed, level, ledger), as every build is.
func _skip_to_level() -> void:
	if _app == null:
		return
	var st := str(_app.state())
	if (st != "WORLD" and st != "LOBBY") or \
			(st == "WORLD" and _app.get("_world") == null):
		_status("skip-to-level needs a live run (state %s)" % st)
		return
	var txt := _level_edit.text.strip_edges()
	if not txt.is_valid_int():
		_status("level must be a whole number >= 1")
		return
	var n := int(txt)
	if n < 1:
		_status("level must be >= 1")
		return
	var ledger := {}
	if st == "WORLD":
		ledger = _app.get("_world").call("run_ledger")
	elif st == "LOBBY":
		var lob = _app.get("_lobby")
		ledger = lob.call("ledger") if lob != null else {}
	var lob2 = _app.get("_lobby")
	if lob2 != null:
		lob2.queue_free()
		_app.set("_lobby", null)
	var old = _app.get("_world")
	if old != null:
		old.call("teardown")
		old.queue_free()
		_app.set("_world", null)
	_app.set("_step_acc", 0.0)
	if not bool(_app.call("_build_world", n, ledger)):
		# the mirror of _on_lobby_exited's failure path (end the run, back to menu)
		_app.call("_end_run")
		_app.call("_show_menu")
		_status("build of level %d failed - run ended, back to the menu" % n)
		return
	var fresh = _app.get("_world")
	_app.add_child(fresh)
	fresh.set("_mouse_locked", true)
	_app.set("_state", "WORLD")
	_set_capture(false)
	_status("skipped to level %d (seed %d, carried ledger)" % [n, int(_app.call("run_seed"))])


## Force the platform collapse: sim/collapse.gd's own start() on the live schedule, from
## IDLE. world.step() then drives the cracks/falls and the sweep exactly as it does when
## the beacon opened them; a later beacon open calls start() again and is a no-op.
func _force_collapse() -> void:
	var w := _world()
	if w == null:
		_status("no live level - collapse needs a run in WORLD state")
		return
	var cst: Dictionary = w.get("_collapse")
	if cst.is_empty():
		_status("this level carries no collapse schedule")
		return
	if not bool(w.get("platform_collapse")):
		_status("platform_collapse is off for this level (the meshes were built flat)"
		)
		return
	var ls: RefCounted = w.get("lstate")
	if CollapseScript.phase(cst) != CollapseScript.PHASE_IDLE:
		_status("collapse already running (phase %d)" % CollapseScript.phase(cst))
		return
	var cev: Dictionary = CollapseScript.start(cst, int(ls.get("tick")))
	var b = ls.get("beacon")
	if cev.is_empty():
		_status("collapse armed on tick %d - zone 0 cracks after the %d-tick start delay"
				% [int(cst.get("start_tick", -1)), int(cst.get("delay_ticks", 0))])
		return
	_status("collapse forced: zone %d cracking (%d tiles, falls in %d ticks) - the beacon"
			+ " open path later sees it started and stays a no-op" % [
			int(cev.get("zone", 0)), int(cev.get("n", 0)), int(cst.get("crack_ticks", 0))])


## FORCE PETER through the REAL arena entry (Terra review round 1 finding 1, D-T2-7-amend):
## _enter_boss_arena() is the arena's own full setup - boss.start(run_seed, level), the
## arena terrain rebuild, the teleport, the first-person rig, the HUD - so the panel never
## calls boss.start() alone. On a level whose build made no boss instance (any level but
## the boss level), the object the level-10 build would carry is created first from
## boss.gd's own config path. The whole entry runs as a QUEUED tick job (D-T2-9) so the
## tick's own list carries the entry events, and the job finishes the tick itself (the
## all-collected path in world.step returns after the same entry triple).
func _force_boss() -> void:
	var w := _world()
	if w == null:
		_status("no live level - the boss fight needs a run in WORLD state")
		return
	var ls: RefCounted = w.get("lstate")
	if ls == null:
		_status("no level state on this level")
		return
	var ctl = w.get("ctl")
	if ctl != null and bool(ctl.get("dead")):
		_status("the run is dead - retry or cheat the respawn first")
		return
	var boss = ls.get("boss")
	if boss != null and bool(boss.get("arena_entered")):
		_status("already fighting Peter - finish this one or skip the level")
		return
	if boss == null:
		# not the boss level: the owner forces the encounter anyway - the same object
		# shape the level-10 build() carries (sim/boss.gd one instance per arena).
		boss = BossScript.new()
		boss.set("config", BossScript.load_config())
		ls.set("boss", boss)
	_queue_job(Callable(self, "_run_force_boss"),
			"boss fight queued - the arena entry runs on the next tick")


## The queued job body: the entry + economy + publish triple the all-collected path in
## world.step runs. Returns true: the action finished this tick itself.
func _run_force_boss(ev: Array) -> bool:
	var w := _world()
	var ls: RefCounted = w.get("lstate") if w != null else null
	var boss = ls.get("boss") if ls != null else null
	if w == null or ls == null or boss == null or bool(boss.get("arena_entered")):
		_status("boss force skipped - the world changed under it")
		return false
	w.call("_enter_boss_arena", ev)
	w.call("_economy_pass", ev)
	w.call("_publish_boss_tick", ev)
	_status("boss fight forced: teleported into the arena - close the panel with F10 and"
			+ " throw gifts at Peter")
	return true


## FORCE BANKAI (D-T2-7-amend). Preferred: an explicit force entry on the live boss
## object (the T8b attack track may add one) - probed with has_method(). Otherwise the
## dormant owner cinematic is played THROUGH its signals: bankai_active stands the boss
## down (the contract's own flag), target_hit drives boss.damage(hp_max) - the easter
## egg's insta-kill - through the world's own _apply_boss_events (reward, beacon), and
## animation_finished frees the node. With no live boss it plays as a standalone preview.
func _force_bankai() -> void:
	var w := _world()
	var ls: RefCounted = w.get("lstate") if w != null else null
	var boss = ls.get("boss") if ls != null else null
	if boss != null:
		var forced := _first_matching([boss], BANKAI_FORCE_METHODS)
		if not forced.is_empty():
			boss.call(str(forced["method"]))
			_status("bankai forced via the boss API (%s())" % str(forced["method"]))
			return
		if bool(boss.get("active")) and not bool(boss.get("bankai_active")):
			_play_bankai(w, boss)
			return
	_status("no active boss to bankai - FORCE PETER BOSS first (this previews standalone)")
	var anim = _make_bankai_anim(w)
	if anim == null:
		_status("bankai: the dormant cinematic did not load")
		return
	anim.play()
	_status("bankai: standalone preview (no active boss on this level)")


## Instantiate the cinematic, attach it to the live world (it owns its cameras), position
## it at the player, free it on animation_finished. Returns the node, or null.
func _make_bankai_anim(w: Node):
	var K = load(BANKAI_CINEMATIC_PATH)
	if K == null:
		return null
	var anim = K.new()
	if w != null and w.is_inside_tree():
		w.add_child(anim)
		anim.position = _player_feet(w)
	else:
		add_child(anim)
	if anim.has_signal("animation_finished"):
		anim.animation_finished.connect(func() -> void:
				_status("bankai cinematic finished")
				if is_instance_valid(anim):
					anim.queue_free())
	return anim


## The in-arena force: the boss stands down via bankai_active (its tick() returns nothing
## while it plays - the contract's own mechanism), and the cinematic's target_hit drives
## the insta-kill through the sim API + the world's own event handling.
func _play_bankai(w: Node, boss) -> void:
	var anim = _make_bankai_anim(w)
	if anim == null:
		_status("bankai: the dormant cinematic did not load")
		return
	boss.set("bankai_active", true)
	if anim.has_signal("animation_started"):
		anim.animation_started.connect(func() -> void:
				_status("bankai forced: cinematic playing - input stays yours meanwhile"))
	if anim.has_signal("target_hit"):
		anim.target_hit.connect(func(_target) -> void:
				var dmg: Array = boss.call("damage", int(boss.get("hp_max")), false)
				var world_now := _world()
				if world_now == null:
					return
				world_now.call("_apply_boss_events", dmg, dmg)
				world_now.call("_publish_boss_tick", dmg)
				_status("bankai target_hit: Peter insta-killed through boss.damage()"))
	var target = w.get("_boss_view") if w != null else null
	anim.play(target)


# ---- the live state hash (D-T2-8) ------------------------------------------------------------


## A RunState-shaped view over the LIVE world - the same fields sim/state_hash.gd's dump
## reads - so the panel can show the run's state hash at any moment. The RNG sub-streams
## do not exist in the app driver (they live in the sim-driver contexts: test_replay's
## random-input run and bot_run's recorded runs), so rng is {} and the dump simply writes
## no RNG lines. Everything else - the level hash, the tick, the player row, the gift
## bitsets, the beacon, the mines, the collapse schedule - is the live sim state, and the
## digest changes exactly when that state changes.
func _build_live_run_state(w: Node) -> RefCounted:
	if _app == null or w == null:
		return null
	var ls: RefCounted = w.get("lstate")
	if ls == null:
		return null
	var out := LiveRunState.new()
	out.run_seed = int(_app.call("run_seed"))
	out.players = 1
	var api := _api()
	out.content_ids = api.call("content_ids").duplicate() if api != null else []
	var ledger: Dictionary = w.call("run_ledger")
	out.run_votes = ledger.get("votes", {})
	out.run_hunger = int(ledger.get("hunger", 0))
	out.level_number = int(w.get("_level_number"))
	out.level = ls
	out.rng = {}
	return out


## state_hash.gd's dump() reads these member names; this holder exists only so the panel
## can call that function without touching a single sim file.
class LiveRunState extends RefCounted:
	var run_seed: int = 0
	var players: int = 1
	var content_ids: Array = []
	var level_number: int = 0
	var run_votes: Dictionary = {}
	var run_hunger: int = 0
	var level: RefCounted = null
	var rng: Dictionary = {}
