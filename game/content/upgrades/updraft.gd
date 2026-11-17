extends RefCounted
# Updraft (T-053; updraft.json, DESIGN.md section 8, D-T053-6).
# "Glider only: once per glide, press jump to rise 3 u (6 s cooldown)" - the rise
# lives on the controller (apply_updraft; vy = sqrt(2 x 32 x 3), 6 s cooldown).

const UPGRADE_ID := "updraft"
const CLASS_ONLY := "glider"
const RISE_U := 3.0
const COOLDOWN_S := 6.0
