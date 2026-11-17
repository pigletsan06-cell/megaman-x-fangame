extends SceneTree
## tela de saves do hub + volta de uma fase (corações e sub tank novos entram no slot)
func _key(k: int) -> InputEventKey:
	var e := InputEventKey.new(); e.keycode = k; e.pressed = true; return e
func _init() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FangameSave.FILE))
	FangameSave.data = {}; FangameSave.slot = -1
	change_scene_to_file("res://scenes/hub.tscn")
	await process_frame; await process_frame
	var h = current_scene
	await process_frame
	root.get_texture().get_image().save_png("/tmp/sha/hub_slots.png")
	h._slot_input(_key(KEY_DOWN)); h._slot_input(_key(KEY_ENTER))
	print("slot escolhido: ", FangameSave.slot)
	await process_frame; await process_frame
	root.get_texture().get_image().save_png("/tmp/sha/hub_main.png")
	# volta de uma fase do X5: venceu o chefe 4, pegou 1 coração e o sub tank 1
	var st := FangameSave.launch_info("x5", 4)
	X4Machine.last_result = {"game": "x5", "stage": 4, "won": true, "save_start": st,
		"save_end": {"hp": st.hp + 2, "upg": st.upg | 0x1000 | 0x08, "ext": 5, "tanks": [0x90, 0]}}
	change_scene_to_file("res://scenes/hub.tscn")
	await process_frame; await process_frame
	var s := FangameSave.cur()
	print("depois: chefes ", s.progress, " corações ", s.hearts, " tanks ", s.tanks, " x5 ", s.games.x5)
	print("X4 recebe: ", FangameSave.launch_info("x4", 1))
	FangameSave.slot = -1; FangameSave.data = {}
	change_scene_to_file("res://scenes/hub.tscn")
	await process_frame; await process_frame; await process_frame
	root.get_texture().get_image().save_png("/tmp/sha/hub_slots2.png")
	quit()
