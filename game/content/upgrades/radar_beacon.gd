extends RefCounted
# Radar Module: Beacon (T-053; radar_beacon.json, DESIGN.md section 8, D-T053-1).
# "HUD compass and distance to the beacon" - the heading/distance pairs come from
# sim/upgrades.gd beacon_compass(); this script carries the id -> role pairing only.

const UPGRADE_ID := "radar_beacon"
const ROLE := "beacon_compass"
