extends RefCounted
#
# slipstream.gd - script upgrade (DESIGN.md section 8 row "slipstream").
# Rule sentence: "+20% speed for 2.0 s after any gift pickup".
# Dispatched by sim/upgrade_runtime.gd on every gift_collected event (black or gold).
# The boost is a tick counter in the dispatcher's api: the app multiplies the controller's
# run_speed stat by it for the next 120 controller steps (2.0 s at 60 Hz). A pickup during
# a running boost refreshes it to the full 2.0 s; it never stacks past +20%.

const UPGRADE_ID := "slipstream"
const SPEED_MUL := 1.2
const BOOST_TICKS := 120   # 2.0 s at 60 Hz


static func on_gift_collected(state: Dictionary, api) -> void:
	if api == null or int(state.get("upgrades_held", {}).get(UPGRADE_ID, 0)) <= 0:
		return
	api.boost_speed(SPEED_MUL, BOOST_TICKS)
