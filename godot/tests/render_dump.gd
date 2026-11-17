extends SceneTree
## Desenha um fluxo de primitivas + VRAM gravados pelo harness (DUMPS="/tmp/sel6/11000,..." -> PNG ao lado)
func _init() -> void:
	X4Machine.render_only = true
	var m := X4Machine.new(); m.game = OS.get_environment("JOGO") if OS.get_environment("JOGO") != "" else "x6"; root.add_child(m)
	await process_frame
	m.set_process(false)
	for base in OS.get_environment("DUMPS").split(",", false):
		var d := base.get_base_dir(); var n := base.get_file()
		var v := FileAccess.get_file_as_bytes(d + "/v_" + n + ".bin")
		var p := FileAccess.get_file_as_bytes(d + "/p_" + n + ".bin")
		X4R.vram_draw = v; X4R.vram_draw_dirty = true
		m.stream = p.to_int32_array()
		m._render()
		await process_frame; await process_frame
		root.get_texture().get_image().save_png(d + "/tela_" + n + ".png")
		print("ok ", base)
	quit()
