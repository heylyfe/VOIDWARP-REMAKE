extends "res://view/hud/gift_counter.gd"
#
# Gold gift counter, bottom-centre (D-GUI-1; the owner's reference build: "1 / 46" with a
# small gift icon). How many GOLD gifts the player has collected this level out of how
# many exist: gold gifts appear at every REAL slot on the black -> gold flip (sim/gifts.gd:
# "a gold gift then exists at every slot that held a black gift"), so the denominator is
# total_real and the numerator is the gold_taken bitset over the real slots.
#
# Hidden through the whole black phase (there are no gold gifts yet); it takes the gift
# counter's slot the tick the phase flips to gold. hud.gd swaps the two pills.
#
# read() is the one place the HUD turns the gift sim into these numbers; app/world.gd
# _sync_hud calls it and the GUI test calls it on a real sim. Read-only on sim state.

const GiftsScript := preload("res://sim/gifts.gd")

var active := false   # true only in the gold phase


## {active, collected, total} from a sim/gifts.gd instance (null -> inactive zeros).
## collected walks the gold_taken bitset over REAL slots only (occ == 1 mine slots are
## never a gift); total is total_real. Pure read: nothing on `gifts` is written.
static func read(gifts: RefCounted) -> Dictionary:
	if gifts == null:
		return {"active": false, "collected": 0, "total": 0}
	var n := 0
	for i in gifts.slots.size():
		if gifts.is_real(i) and GiftsScript.bit_get(gifts.gold_taken, i):
			n += 1
	return {
		"active": str(gifts.phase) == GiftsScript.PHASE_GOLD,
		"collected": n,
		"total": int(gifts.total_real),
	}


func _init() -> void:
	super()
	name = "GoldCounter"
	visible = false


## p_active false (black phase) hides the pill and zeroes the pair.
func sync_gold(p_active: bool, p_collected: int, p_total: int) -> void:
	active = p_active
	visible = p_active
	if p_active:
		sync(p_collected, p_total)
	else:
		sync(0, 0)


func _is_gold() -> bool:
	return true
