extends SceneTree
## tela de montagem: peças liberadas, descrição, Giga só com as 4 peças iguais; env que vai para o x4core
func _key(k: int) -> InputEventKey:
	var e := InputEventKey.new(); e.keycode = k; e.pressed = true; return e
func _init() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FangameSave.FILE))
	FangameSave.data = {}; FangameSave.slot = -1
	FangameSave.load_file(); FangameSave.select(0)
	FangameSave.cur().games.x4.caps = 0x1 | 0x8   # capacete e pernas do X4
	FangameSave.cur().unlocked.append("Shadow_X6:arms")
	change_scene_to_file("res://scenes/hub.tscn")
	await process_frame; await process_frame
	var h = current_scene
	h._unhandled_input(_key(KEY_C))
	await process_frame; await process_frame
	root.get_texture().get_image().save_png("/tmp/sha/build1.png")
	print("escolhas braço: ", h._build_choices("arms"), " capacete: ", h._build_choices("helmet"))
	h._build_input(_key(KEY_DOWN)); h._build_input(_key(KEY_DOWN))   # braço
	h._build_input(_key(KEY_RIGHT)); h._build_input(_key(KEY_RIGHT))
	h._build_input(_key(KEY_DOWN)); h._build_input(_key(KEY_LEFT))   # pernas
	await process_frame; await process_frame
	root.get_texture().get_image().save_png("/tmp/sha/build2.png")
	var p: Dictionary = FangameSave.cur().parts
	print("peças: ", p, " giga: '", FangameParts.giga_name(p), "' env: ", FangameParts.core_env(p))
	h._build_input(_key(KEY_C))
	var l: Dictionary = h._build_launch()
	print("launch: ", l.get("parts"), " skin '", l.skin, "' caps ", l.save.caps)
	for s in ["Shadow_X6", "Falcon_X5", "Fourth_X4"]:
		var q := {}
		for k in FangameParts.SLOTS: q[k] = s
		print(s, " completa: ", FangameParts.core_env(q), " giga '", FangameParts.giga_name(q), "' skin ", FangameParts.needs_skin(q))
	quit()
