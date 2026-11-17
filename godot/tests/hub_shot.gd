extends SceneTree
func _init() -> void:
	change_scene_to_file("res://scenes/hub.tscn")
	for i in 5: await process_frame
	root.get_texture().get_image().save_png("/tmp/hub.png")
	quit()
