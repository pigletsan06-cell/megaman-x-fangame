extends SceneTree
func _init() -> void:
	FangameSave.load_file(); FangameSave.select(0)
	change_scene_to_file("res://scenes/hub.tscn")
	for i in 5: await process_frame
	var h = current_scene
	h.jogo_open = false; h.in_page = true; h.page = h.GAMES.find("x4"); h.is_zero = true
	h.zero_idx["x4"] = 0
	var l: Dictionary = h._build_launch()
	X4Machine.launch = l; X4Machine.handoff = {}
	change_scene_to_file("res://scenes/fase.tscn")
	for f in 900: await process_frame
	root.get_texture().get_image().save_png("/tmp/x4_zero_hud.png")
	quit()
