extends SceneTree
## Teste rápido da recompilação: entra numa fase do X5 ou X6 (JOGO=x5|x6) pelo hub, anda um pouco e tira uma foto.
## Diz se a fase rodou pela recompilação (DLL bin/xNrecomp) ou pelo núcleo de PS1. FOTO=arquivo.png
func _init() -> void:
	var g := OS.get_environment("JOGO") if OS.get_environment("JOGO") != "" else "x6"
	FangameSave.load_file(); FangameSave.select(0)
	change_scene_to_file("res://scenes/hub.tscn")
	for i in 5: await process_frame
	var h = current_scene
	h.jogo_open = false; h.in_page = true; h.page = h.GAMES.find(g); h.is_zero = false
	var l: Dictionary = h._build_launch()
	X4Machine.launch = l; X4Machine.handoff = {}
	change_scene_to_file("res://scenes/fase.tscn")
	var ok := false
	for f in 4000:
		await process_frame
		if current_scene and current_scene.get("launch_phase") == 2: ok = true; break
	var m = current_scene
	var info := "rc_fumaca: jogo=%s carregou=%s recomp=%s nucleo=%s" % [g, ok, m.get("recomp"), m.get("core")]
	print(info)
	if OS.get_environment("RESULTADO") != "":
		var fr := FileAccess.open(OS.get_environment("RESULTADO"), FileAccess.WRITE); fr.store_line(info); fr.close()
	m.forced = 1 << 13   # anda para a direita
	for f in 240: await process_frame
	m.forced = 0
	var foto := OS.get_environment("FOTO")
	if foto != "": root.get_texture().get_image().save_png(foto)
	print("rc_fumaca: fim")
	quit()
