extends SceneTree
func _init() -> void:
	printerr("a")
	X4R.init()
	printerr("b init")
	var s = load("res://scripts/x4c/gen/X4M_godot_frame.gd")
	printerr("c load ", s)
	quit()
