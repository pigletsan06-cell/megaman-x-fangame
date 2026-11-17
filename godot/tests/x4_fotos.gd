extends SceneTree
## Fotos do X4 pelo x4core (usado pelo extrator do launcher, roteiros com "motor": "x4core"): roda o jogo com um roteiro
## de controle e grava a VRAM e as primitivas dos quadros pedidos (SAIDA/v_N.bin e p_N.bin) para o tests/render_dump.gd
## desenhar, igual às fotos do núcleo de PS1.
## Ambiente: SAIDA (pasta), QUADROS ("394,514"), TOTAL (quadros), BOTOES ("right:480-482,cross:500-503"),
## MEM ("8:0:3" = X4Core.mem(8, 0) no quadro 3), X4ENV ("CHAVE=valor;CHAVE=valor" vai para X4R.env).
const BOTAO := {"l2": 0, "r2": 1, "l1": 2, "r1": 3, "triangle": 4, "circle": 5, "cross": 6, "square": 7, "select": 8,
	"start": 11, "up": 12, "right": 13, "down": 14, "left": 15}

func _init() -> void:
	for par in OS.get_environment("X4ENV").split(";", false):
		var kv := par.split("=", true, 1)
		X4R.env[kv[0]] = kv[1] if kv.size() > 1 else ""
	var m := X4Machine.new(); root.add_child(m)
	await process_frame
	m.set_process(false)
	var saida := OS.get_environment("SAIDA")
	var total := int(OS.get_environment("TOTAL"))
	var quadros := {}
	for q in OS.get_environment("QUADROS").split(",", false): quadros[int(q)] = true
	var botoes := []   # [bit, de, até]
	for b in OS.get_environment("BOTOES").split(",", false):
		var a := b.split(":"); var r := a[1].split("-")
		if not BOTAO.has(a[0]): printerr("botão desconhecido: ", a[0]); quit(2); return
		botoes.append([BOTAO[a[0]], int(r[0]), int(r[r.size() - 1])])
	var mem := []      # [índice, valor, quadro]
	for c in OS.get_environment("MEM").split(",", false):
		var a := c.split(":"); mem.append([int(a[0]), int(a[1]), int(a[2])])
	var feitos := 0
	for f in total:
		for c in mem:
			if f == c[2]: ClassDB.class_call_static("X4Core", "mem", c[0], c[1], -1)
		var forced := 0
		for b in botoes:
			if f >= b[1] and f <= b[2]: forced |= 1 << b[0]
		m.forced = forced
		m.step_frame(quadros.has(f))
		if quadros.has(f):
			var fv := FileAccess.open(saida.path_join("v_%d.bin" % f), FileAccess.WRITE); fv.store_buffer(X4R.vram_draw); fv.close()
			var fp := FileAccess.open(saida.path_join("p_%d.bin" % f), FileAccess.WRITE)
			fp.store_buffer(PackedInt32Array(m.stream).to_byte_array()); fp.close()
			feitos += 1
	print("x4_fotos: %d quadro(s) gravado(s) em %d" % [feitos, total])
	quit(0 if feitos == quadros.size() else 1)
