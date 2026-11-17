extends SceneTree
## Duas fases seguidas passando pelo hub (testa reiniciar os núcleos)
func _init() -> void:
	var specs := OS.get_environment("LANCAR").split(",")
	var dir := "/tmp/h2"
	for i in specs.size():
		var p := specs[i].split(":")
		X4Machine.launch = {"game": p[0], "stage": int(p[1]), "char": int(p[2]), "armor": int(p[3]), "char_code": int(p[3])}
		change_scene_to_file("res://scenes/fase.tscn")
		var played := 0
		for f in 1500:
			await process_frame
			var m = current_scene
			if m and m.get("launch_phase") == 2:
				played += 1
				if played == 200:
					root.get_texture().get_image().save_png(dir + "/fase_%d.png" % i)
					m._back_to_hub()
					break
		for f in 10: await process_frame
		print("depois da fase ", i, ": cena=", current_scene.name if current_scene else "nenhuma", " jogou=", played)
		root.get_texture().get_image().save_png(dir + "/hub_%d.png" % i)
	quit()
