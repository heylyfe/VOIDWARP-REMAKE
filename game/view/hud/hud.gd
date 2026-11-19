extends Control
#
# HUD root (ticket T-025; DESIGN.md section 14). One Control that builds and lays
# out exactly the elements section 14 lists, and nothing else:
#
#   gifts counter  bottom-centre  ("collected / REAL total")
#   purse + chain  top-right      ("149.00  1.50x")
#   void charge pips  bottom-left (2, or 1 under Hungry Void; filled = held)
#     + Last Light icon right of the pips (section 3.1 mandate, fable 2.4)
#   class ability cooldown  bottom-left (right of the pip cluster, D-T025-3)
#   curse + upgrade icon rows  top (collapsible with Tab)
#   enemy roster icons with counts  top-left
#   radar arrows  screen edge     (T-053 addendum R4: chevrons + distance labels;
#                  the caller builds the entry list from the sim radar queries)
#   cartographer map  top-right   (T-053 addendum R4: the footprint minimap;
#                  hidden unless the run owns the footprint map)
#   screen_fx  full-screen void flash / Last Light bloom / death black-out (T-086);
#              drawn topmost; re-emits blackout_finished for the app layer
#
# The other two section 14 elements are separate top-level nodes, because they
# are not screen-fixed 2D: danger_text.gd (Node3D, world spawn points) and
# run_over.gd (shown on death). Both live in this folder.
#
# sync(snapshot) takes one dictionary (all fields optional, sane empties):
#   gifts_collected: int, gifts_total: int   (REAL gifts only - pass
#                      total_real - remaining() / total_real from sim/gifts.gd)
#   purse_centi: int, chain: float           (economy.purse_centi / chain_display())
#   charges: int, charge_cap: int, last_light: String   (controller.charges /
#                      .charge_cap / .hud_last_light())
#   kit: String, ability_remaining: float, ability_total: float
#   curses: Array[{id, stacks}], upgrades: Array[{id, stacks}]
#   roster: Array[{id, name, count}]
#   radar_entries: Array[{angle, dist}]   (world-space atan2(dz, dx), u)
#   footprint_map: Dictionary  {visible, lv, p_index, scale_px, colours, facing}; an
#                  absent or visible==false dict keeps the map hidden and cost-free
#
# The HUD never writes sim state.

const GiftCounterScript := preload("res://view/hud/gift_counter.gd")
const PurseChainScript := preload("res://view/hud/purse_chain.gd")
const VoidPipsScript := preload("res://view/hud/void_pips.gd")
const AbilityCooldownScript := preload("res://view/hud/ability_cooldown.gd")
const IconRowsScript := preload("res://view/hud/icon_rows.gd")
const EnemyRosterScript := preload("res://view/hud/enemy_roster.gd")
const ScreenFxScript := preload("res://view/hud/screen_fx.gd")
const RadarArrowsScript := preload("res://view/hud/radar_arrows.gd")
const CartographerMapScript := preload("res://view/hud/cartographer_map.gd")

var gift_counter: Control
var purse_chain: Control
var void_pips: Control
var ability_cooldown: Control
var icon_rows: Control
var enemy_roster: Control
var radar_arrows: Control
var cartographer_map: Control
var screen_fx: Control   # T-086: full-screen void flash / white bloom / death black-out

signal blackout_finished


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	gift_counter = GiftCounterScript.new()
	add_child(gift_counter)
	purse_chain = PurseChainScript.new()
	add_child(purse_chain)
	void_pips = VoidPipsScript.new()
	add_child(void_pips)
	ability_cooldown = AbilityCooldownScript.new()
	add_child(ability_cooldown)
	icon_rows = IconRowsScript.new()
	add_child(icon_rows)
	enemy_roster = EnemyRosterScript.new()
	add_child(enemy_roster)
	radar_arrows = RadarArrowsScript.new()
	add_child(radar_arrows)
	cartographer_map = CartographerMapScript.new()
	cartographer_map.visible = false   # until sync() says the run owns the footprint map
	add_child(cartographer_map)
	# T-086: the screen-wide effects draw over every other HUD element
	screen_fx = ScreenFxScript.new()
	add_child(screen_fx)
	screen_fx.blackout_finished.connect(func() -> void: blackout_finished.emit())


func sync(snapshot: Dictionary) -> void:
	gift_counter.sync(int(snapshot.get("gifts_collected", 0)), int(snapshot.get("gifts_total", 0)))
	purse_chain.sync(int(snapshot.get("purse_centi", 0)), float(snapshot.get("chain", 1.0)))
	void_pips.set_charges(int(snapshot.get("charges", 2)), int(snapshot.get("charge_cap", 2)))
	void_pips.set_last_light(str(snapshot.get("last_light", "lit")))
	ability_cooldown.sync(str(snapshot.get("kit", "dasher")),
			float(snapshot.get("ability_remaining", 0.0)), float(snapshot.get("ability_total", 3.0)))
	icon_rows.set_curses(snapshot.get("curses", []))
	icon_rows.set_upgrades(snapshot.get("upgrades", []))
	enemy_roster.set_roster(snapshot.get("roster", []))
	radar_arrows.sync(snapshot.get("radar_entries", []))
	# The footprint map draws only for a run that owns the footprint map; otherwise
	# it stays hidden and clears itself (sync(null)) at zero cost.
	var cart: Dictionary = snapshot.get("footprint_map", {})
	var show_cart := bool(cart.get("visible", false))
	cartographer_map.visible = show_cart
	if show_cart:
		cartographer_map.sync(cart.get("lv"), int(cart.get("p_index", 0)),
				float(cart.get("scale_px", 2.75)), cart.get("colours", {}),
				float(cart.get("facing", -PI / 2.0)))
	else:
		cartographer_map.sync(null, 0, 2.75, {}, -PI / 2.0)


## Begin the 18-tick death black-out (section 2.4); blackout_finished fires when it
## lands. The caller then shows run_over.gd (opacity black on black - seamless).
func death_blackout() -> void:
	screen_fx.black_out()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		icon_rows.toggle_collapsed()
		accept_event()
