extends SceneTree
## X4 no hub: grava o fluxo de primitivas e os dados do jogador (quadro, direção, posição na tela)
func _init() -> void:
	X4Machine.launch = {"game": "x4", "stage": int(OS.get_environment("FASE") if OS.get_environment("FASE") != "" else "1"), "char": 0, "armor": int(OS.get_environment("ARM") if OS.get_environment("ARM") != "" else "0"), "char_code": 0, "skin": OS.get_environment("SKIN")}
	change_scene_to_file("res://scenes/fase.tscn")
	await process_frame; await process_frame
	var m = current_scene
	m.set_process(false)
	var out := []
	for f in int(OS.get_environment("NF") if OS.get_environment("NF") != "" else "1200"):
		var b := 0
		if f > 200: b |= 1 << 13   # direita
		if f > 200 and (f / 40) % 2 == 0: b |= 1 << 6   # pula
		if f > 400 and f < 470: b = (1 << 15)   # esquerda
		m.forced = b
		var pre_f: int = ClassDB.class_call_static("X4Core", "mem", 11, 0, 1)
		m.step_frame(f % 25 == 0 or (f > 700 and f % 3 == 0))
		if f % 25 == 0 and f > 150 or (f > 700 and f % 3 == 0):
			var info := []
			for a in [11, 12, 13, 14, 15, 16, 17]: info.append(ClassDB.class_call_static("X4Core", "mem", a, 0, 1))
			var fa := FileAccess.open("/tmp/probe/s_%d.bin" % f, FileAccess.WRITE); fa.store_buffer(m.stream.to_byte_array()); fa.close()
			info.append(pre_f)
			out.append({"f": f, "info": info})
			await process_frame; await process_frame
			root.get_texture().get_image().save_png("/tmp/probe/t_%d.png" % f)
	var fj := FileAccess.open("/tmp/probe/info.json", FileAccess.WRITE); fj.store_string(JSON.stringify(out)); fj.close()
	quit()
