extends SceneTree
func _init() -> void:
	change_scene_to_file("res://scenes/hub.tscn")
	for i in 3: await process_frame
	var h = current_scene
	h.progress["x5"] = [1, 2, 3, 4, 5, 6, 7, 8, 16]
	h.page = 1; h.finals_open = true; h._refresh()
	for i in 3: await process_frame
	root.get_texture().get_image().save_png("/tmp/hubf1.png")
	h.page = 2; h._refresh()
	for i in 3: await process_frame
	root.get_texture().get_image().save_png("/tmp/hubf2.png")
	quit()
