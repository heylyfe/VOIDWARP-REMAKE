extends RefCounted
# Radar Module: Threats (T-053; radar_threats.json, DESIGN.md section 8, D-T053-1).
# "screen-edge markers for enemies within 30 u" - the markers come from
# sim/upgrades.gd threat_markers; this script carries the id -> role pairing.

const UPGRADE_ID := "radar_threats"
const ROLE := "threat_radar"
const RANGE_U := 30.0
