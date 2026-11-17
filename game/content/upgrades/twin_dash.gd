extends RefCounted
# Twin Dash (T-053; twin_dash.json, DESIGN.md section 8, D-T053-5).
# "Dasher only: 2 dash charges" - the second stock lives on the controller
# (apply_twin_dash); the class gate is this file's CLASS_ONLY guard, asserted
# by test_upgrades_script.gd.

const UPGRADE_ID := "twin_dash"
const CLASS_ONLY := "dasher"
