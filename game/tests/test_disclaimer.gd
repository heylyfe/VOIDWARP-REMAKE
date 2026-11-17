extends RefCounted
#
# A15 (FLEET_PACK.md T-024): the ENEMIES.md DISCLAIMER paragraph appears VERBATIM in
#   (a) the About screen (game/app/menu.gd - the exact text the About panel renders), and
#   (b) README.md at the repository root.
# The paragraph is pinned here as a constant, so editing either location away fails this test.
#
# A15 (FLEET_PACK.md section 5, T-001 spec): the T-001 disclaimer sentence appears VERBATIM in
#   (c) README.md at the repository root, and
#   (d) the lobby About plaque (game/view/lobby/antechamber.gd - the exact text the plaque label renders).
# The T-001 sentence is pinned here as a constant; the plaque text is read from the real source
# (the const the plaque label renders), never from a copy in this test.

const MenuScript := preload("res://app/menu.gd")
const AntechamberScript := preload("res://view/lobby/antechamber.gd")

const ENEMIES_MD_DISCLAIMER := "this is a personal, non-commercial project with no money involved. It is not affiliated with, endorsed by, or connected to any person, brand, character, or IP referenced or depicted in the game."

# FLEET_PACK.md T-001's spec, em dash (U+2014) as the repo writes it (README.md, FLEET_PACK.md).
const T001_DISCLAIMER := "VOIDWRAP RUN is a personal, non-commercial project — no money is involved, and it is not affiliated with, endorsed by, or connected to any person, brand, character, or IP referenced or depicted in the game."


func run() -> Array[String]:
	var f: Array[String] = []
	_test_about_text_carries_disclaimer(f)
	_test_readme_carries_disclaimer(f)
	_test_menu_entries(f)
	_test_readme_carries_t001_disclaimer(f)
	_test_lobby_plaque_carries_t001_disclaimer(f)
	return f


func _test_about_text_carries_disclaimer(f: Array[String]) -> void:
	if str(MenuScript.ABOUT_DISCLAIMER) != ENEMIES_MD_DISCLAIMER:
		f.append("about: ABOUT_DISCLAIMER is not the ENEMIES.md paragraph verbatim")
	var about: String = MenuScript.about_text()
	if not about.contains(ENEMIES_MD_DISCLAIMER):
		f.append("about: About text does not contain the ENEMIES.md disclaimer verbatim")


func _test_readme_carries_disclaimer(f: Array[String]) -> void:
	var readme_path := ProjectSettings.globalize_path("res://") + "../README.md"
	var file := FileAccess.open(readme_path, FileAccess.READ)
	if file == null:
		f.append("readme: cannot open %s" % readme_path)
		return
	var text := file.get_as_text()
	if not text.contains(ENEMIES_MD_DISCLAIMER):
		f.append("readme: README.md does not contain the ENEMIES.md disclaimer verbatim")


func _test_readme_carries_t001_disclaimer(f: Array[String]) -> void:
	var readme_path := ProjectSettings.globalize_path("res://") + "../README.md"
	var file := FileAccess.open(readme_path, FileAccess.READ)
	if file == null:
		f.append("readme: cannot open %s" % readme_path)
		return
	var text := file.get_as_text()
	if not text.contains(T001_DISCLAIMER):
		f.append("readme: README.md does not contain the T-001 disclaimer verbatim")


func _test_lobby_plaque_carries_t001_disclaimer(f: Array[String]) -> void:
	# The plaque's text is read from the real source: the const the label renders.
	var plaque_text: String = str(AntechamberScript.ABOUT_PLAQUE_TEXT)
	var disclaimer: String = str(AntechamberScript.DISCLAIMER)
	if disclaimer != T001_DISCLAIMER:
		f.append("plaque: DISCLAIMER is not the T-001 disclaimer byte-identical")
	if not plaque_text.contains(T001_DISCLAIMER):
		f.append("plaque: rendered plaque text does not contain the T-001 disclaimer verbatim")


func _test_menu_entries(f: Array[String]) -> void:
	if MenuScript.MENU_ENTRIES != ["PLAY", "HOW TO PLAY", "QUIT"]:
		f.append("menu: MENU_ENTRIES is %s, want [PLAY, HOW TO PLAY, QUIT]" % str(MenuScript.MENU_ENTRIES))


