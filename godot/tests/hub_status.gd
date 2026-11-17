extends SceneTree
func _key(k: int) -> InputEventKey:
	var e := InputEventKey.new(); e.keycode = k; e.pressed = true; return e
func _init() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FangameSave.FILE))
	FangameSave.data = {}; FangameSave.slot = -1
	FangameSave.load_file(); FangameSave.select(0)
	var s := FangameSave.cur()
	s.games.x4.caps = 0x9; s.unlocked.append_array(["Falcon_X5:legs", "Blade_X6:legs", "Shadow_X6:helmet"])
	s.progress = {"x4": [1, 4], "x5": [1], "x6": [1, 3, 5]}; s.hearts = 3; s.tanks = [10]
	change_scene_to_file("res://scenes/hub.tscn")
	await process_frame; await process_frame
	var h = current_scene
	root.get_texture().get_image().save_png("/tmp/sha/st0.png")
	h._unhandled_input(_key(KEY_TAB))
	await process_frame; await process_frame
	root.get_texture().get_image().save_png("/tmp/sha/st1.png")
	h._status_input(_key(KEY_RIGHT)); h._status_input(_key(KEY_RIGHT)); h._status_input(_key(KEY_RIGHT)); h._status_input(_key(KEY_RIGHT)); h._status_input(_key(KEY_RIGHT))
	await process_frame; await process_frame
	root.get_texture().get_image().save_png("/tmp/sha/st2.png")
	quit()
