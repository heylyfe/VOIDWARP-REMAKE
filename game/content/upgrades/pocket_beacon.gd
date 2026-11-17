extends RefCounted
# Pocket Beacon (T-053; pocket_beacon.json, addendum R4, D-T053-3).
# "once per level: 3.0 s channel (must stand still) to teleport to the beacon dais"
# The channel is tick-counted in sim/upgrades.gd (180 ticks at 60 Hz); the ring that
# fills around the player over those 180 ticks is the HUD/vfx read of
# Upgrades.channels[p]["t"] (a cancelled channel restarts for free).

const UPGRADE_ID := "pocket_beacon"
const ROLE := "beacon_channel"
const CHANNEL_SECONDS := 3.0
const CHANNEL_TICKS := 180
