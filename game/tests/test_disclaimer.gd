extends RefCounted
#
# A15 (FLEET_PACK.md T-024): the ENEMIES.md DISCLAIMER paragraph appears VERBATIM in
#   (a) the About screen (game/app/menu.gd - the exact text the About panel renders), and
#   (b) README.md at the repository root.
# The paragraph is pinned here as a constant, so editing either location away fails this test.

const MenuScript := preload("res://app/menu.gd")

const ENEMIES_MD_DISCLAIMER := "this is a personal, non-commercial project with no money involved. It is not affiliated with, endorsed by, or connected to any person, brand, character, or IP referenced or depicted in the game."


func run() -> Array[String]:
	var f: Array[String] = []
	_test_about_text_carries_disclaimer(f)
	_test_readme_carries_disclaimer(f)
	_test_menu_entries(f)
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


func _test_menu_entries(f: Array[String]) -> void:
	if MenuScript.MENU_ENTRIES != ["Play", "Settings", "About", "Quit"]:
		f.append("menu: MENU_ENTRIES is %s, want [Play, Settings, About, Quit]" % str(MenuScript.MENU_ENTRIES))


