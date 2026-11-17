extends SceneTree
## cápsula do X6 (fase 4 = capacete da Shadow) e do X5 (fase 1 = pernas da Falcon): peça liberada e aviso no hub
func _init() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FangameSave.FILE))
	FangameSave.data = {}; FangameSave.slot = -1
	FangameSave.load_file(); FangameSave.select(0)
	var st := FangameSave.launch_info("x6", 4)
	print("pokes x6: ", st.pokes)
	var en := {"hp": st.hp, "upg": st.upg, "ext": st.ext, "tanks": [0, 0], "parts": 0x10, "parts0": 0}
	X4Machine.last_result = {"game": "x6", "stage": 4, "won": false, "save_start": st, "save_end": en}
	change_scene_to_file("res://scenes/hub.tscn")
	await process_frame; await process_frame
	var h = current_scene
	print("liberadas: ", FangameSave.cur().unlocked, " x6 parts ", FangameSave.cur().games.x6.parts, " msg: ", h.new_part_msg)
	await process_frame
	root.get_texture().get_image().save_png("/tmp/sha/caps.png")
	print("x6 de novo: ", FangameSave.launch_info("x6", 2).pokes.back())
	quit()
