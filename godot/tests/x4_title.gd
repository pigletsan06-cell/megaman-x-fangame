extends SceneTree
func _init() -> void:
	X4Machine.launch = {}
	for k in ["MMX4_ORACLE_SCENE", "MMX4_DIRECT_STAGE", "MMX4_DIRECT_LOADOUT"]: X4R.env.erase(k)
	change_scene_to_file("res://scenes/x4_original.tscn")
	await process_frame; await process_frame
	var m = current_scene
	m.set_process(false)
	for f in 1500:
		m.forced = 0
		var snap: bool = f % 100 == 0 and f >= 300
		m.step_frame(snap)
		if snap:
			await process_frame; await process_frame
			root.get_texture().get_image().save_png("/tmp/tit4/%d.png" % f)
	quit()
