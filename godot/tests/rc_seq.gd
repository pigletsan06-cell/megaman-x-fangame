extends SceneTree
## Grava uma sequência fixa de botões numa fase do X6 (recompilação) e salva um recorte em volta do X a cada quadro.
## PECAS="h,b,a,l" (vazio = X do jogo), ARM=armadura, SAIDA=pasta
const RIGHT := 1 << 13
const LEFT := 1 << 15
const JUMP := 1 << 6      # X
const DASH := 1 << 5      # bola (círculo)
const SHOT := 1 << 7      # quadrado
func _init() -> void:
	FangameSave.load_file(); FangameSave.select(0)
	change_scene_to_file("res://scenes/hub.tscn")
	for i in 5: await process_frame
	var h = current_scene
	h.jogo_open = false; h.in_page = true; h.page = 2; h.is_zero = false
	h.armor_idx["x6"] = int(OS.get_environment("ARM"))
	var l: Dictionary = h._build_launch()
	var pc := OS.get_environment("PECAS").split(",")
	if pc.size() == 4: l["parts"] = {"helmet": pc[0], "body": pc[1], "arms": pc[2], "legs": pc[3]}
	X4Machine.launch = l; X4Machine.handoff = {}
	change_scene_to_file("res://scenes/fase.tscn")
	for f in 3000:
		await process_frame
		if current_scene and current_scene.get("launch_phase") == 2: break
	var m = current_scene
	for f in 300: await process_frame
	var seq := [[40, RIGHT], [20, RIGHT | JUMP], [20, RIGHT], [12, RIGHT | DASH], [20, 0], [10, SHOT], [20, 0], [25, LEFT], [15, LEFT | JUMP], [20, 0]]
	var dir := OS.get_environment("SAIDA")
	DirAccess.make_dir_recursive_absolute(dir)
	var n := 0
	for st in seq:
		m.forced = st[1]
		for f in st[0]:
			await process_frame
			root.get_texture().get_image().save_png("%s/q_%03d.png" % [dir, n]); n += 1
	m.forced = 0
	quit()
