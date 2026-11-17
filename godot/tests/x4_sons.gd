extends SceneTree
## Gravações do X4 para os sons do extrator (roteiros com "motor": "x4som"): o X4 na fase 1 pela cena da fase
## (fase.tscn), como foram gravados os sons do PC do dono, e cada som sai da diferença entre uma gravação com o som e
## outra sem ele (a cachoeira da fase 1 some na conta). Grava SAIDA/<nome>.raw (44,1 kHz estéreo 16 bits).
## Ambiente: SAIDA (pasta), MODO e:
##   MODO=lista: SONS="10D,10B,00C" (tipo<<8|id), SEM=1 para não tocar; 400 quadros de espera e, para cada som,
##     30 quadros + o som + 90 quadros gravados (<SAIDA>/x4_<som>[_sem].raw)
##   MODO=seq: SEQ="10B@20" (som@quadro), NOME; 430 quadros de espera e 90 gravados (<SAIDA>/seq_<NOME>.raw)
## (float -> 16 bits: int(x * 32767), cortando para o zero, igual ao gravador da época)

func _init() -> void:
	Opcoes.data = Opcoes.defaults()   # as gravações do dono são com as opções de fábrica (falas do X6)
	# sem a música do CD (as do dono foram gravadas sem o disco): o jogo procura o disco primeiro em PSX_BIN
	OS.unset_environment("X4_BIN")
	OS.set_environment("PSX_BIN", ProjectSettings.globalize_path("res://.sem_musica_nos_sons.bin"))
	X4Machine.launch = {"game": "x4", "stage": 1, "char": 0, "armor": 1, "char_code": 1, "skin": ""}
	change_scene_to_file("res://scenes/fase.tscn")
	await process_frame; await process_frame
	var m = current_scene
	m.set_process(false)
	var saida := OS.get_environment("SAIDA")
	DirAccess.make_dir_recursive_absolute(saida)
	var n := 0
	if OS.get_environment("MODO") == "seq":
		for f in 430: m.forced = 0; m.step_frame(false); ClassDB.class_call_static("X4Core", "audio", 735)
		var ev := {}
		for e in OS.get_environment("SEQ").split(",", false):
			var a := e.split("@"); ev[int(a[1])] = a[0].hex_to_int()
		var data := PackedByteArray()
		for f in 90:
			if ev.has(f): ClassDB.class_call_static("X4Core", "mem", 0xFFFFFF13, ev[f], -1)
			m.step_frame(false)
			data.append_array(_pcm(ClassDB.class_call_static("X4Core", "audio", 735)))
		if _grava(saida.path_join("seq_%s.raw" % OS.get_environment("NOME")), data): n += 1
	else:
		var sem := OS.get_environment("SEM") != ""
		for f in 400: m.forced = 0; m.step_frame(false); ClassDB.class_call_static("X4Core", "audio", 735)
		for code in OS.get_environment("SONS").split(",", false):
			for f in 30: m.step_frame(false); ClassDB.class_call_static("X4Core", "audio", 735)
			if not sem: ClassDB.class_call_static("X4Core", "mem", 0xFFFFFF13, code.hex_to_int(), -1)
			var data := PackedByteArray()
			for f in 90:
				m.step_frame(false)
				data.append_array(_pcm(ClassDB.class_call_static("X4Core", "audio", 735)))
			if _grava(saida.path_join("x4_%s%s.raw" % [code, "_sem" if sem else ""]), data): n += 1
	print("x4_sons: %d gravação(ões)" % n)
	quit(0 if n > 0 else 1)

func _pcm(buf: PackedVector2Array) -> PackedByteArray:
	var p := PackedByteArray(); p.resize(buf.size() * 4)
	for i in buf.size():
		p.encode_s16(i * 4, int(clampf(buf[i].x, -1, 1) * 32767)); p.encode_s16(i * 4 + 2, int(clampf(buf[i].y, -1, 1) * 32767))
	return p

func _grava(caminho: String, data: PackedByteArray) -> bool:
	var f := FileAccess.open(caminho, FileAccess.WRITE)
	if f == null: printerr("x4_sons: não consegui gravar ", caminho); return false
	f.store_buffer(data); f.close()
	return true
