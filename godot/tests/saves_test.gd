extends SceneTree
func _k(k: int) -> InputEventKey:
	var e := InputEventKey.new(); e.keycode = k; e.pressed = true; return e
func _init() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FangameSave.FILE))
	FangameSave.data = {}; FangameSave.slot = -1
	FangameSave.load_file(); FangameSave.select(0)
	var s := FangameSave.cur(); s.progress = {"x4": [1, 4], "x5": [1], "x6": [1, 3, 5]}; s.hearts = 3; s.tanks = [10]
	s.parts = {"helmet": "", "body": "Falcon_X6", "arms": "Fourth_X5", "legs": "Falcon_X6"}
	FangameSave.select(1); FangameSave.write(); FangameSave.slot = -1
	change_scene_to_file("res://scenes/title.tscn")
	await process_frame; await process_frame
	var tt = current_scene
	tt.t = 2.2; tt._unhandled_input(_k(KEY_ENTER)); tt._unhandled_input(_k(KEY_ENTER))
	await process_frame; await process_frame
	root.get_texture().get_image().save_png("/tmp/sha/sv1.png")
	tt._unhandled_input(_k(KEY_UP)); tt._unhandled_input(_k(KEY_C))
	await process_frame; await process_frame
	root.get_texture().get_image().save_png("/tmp/sha/sv2.png")
	quit()
