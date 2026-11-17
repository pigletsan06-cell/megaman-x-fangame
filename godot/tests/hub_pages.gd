extends SceneTree
func _init() -> void:
	X4Machine.last_result = {"game": "x6", "stage": 3, "won": true}
	change_scene_to_file("res://scenes/hub.tscn")
	for i in 3: await process_frame
	for p in 3:
		var h = current_scene
		h.page = p; h._refresh()
		for i in 3: await process_frame
		root.get_texture().get_image().save_png("/tmp/hubp_%d.png" % p)
	quit()
