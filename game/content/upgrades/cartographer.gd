extends RefCounted
# Cartographer (T-053; cartographer.json, addendum R4, D-T053-2, D-T053-8).
# "minimap of every piece within 40 u of anywhere you have stood, with real gifts"
# Reveal = any piece within 40 u of any 1 u tile the player has stood on; the 220 px
# north-up minimap rendering is view/hud/cartographer_map.gd over the sim rows.

const UPGRADE_ID := "cartographer"
const ROLE := "cartographer"
const REVEAL_RANGE_U := 40.0
