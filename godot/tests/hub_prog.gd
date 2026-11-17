extends SceneTree
func _init() -> void:
	X4Machine.last_result = {"game": "x5", "stage": 3, "won": true}
	change_scene_to_file("res://scenes/hub.tscn")
	for i in 5: await process_frame
	root.get_texture().get_image().save_png("/tmp/hub.png")
	quit()
