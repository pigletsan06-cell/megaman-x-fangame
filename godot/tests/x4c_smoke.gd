extends SceneTree
func _init() -> void:
	X4R.init()
	var mo := X4R.addr("main_objects")
	var gp := X4R.addr("g_Player")
	print("main_objects=%x g_Player=%x" % [mo, gp])
	# jogador em (200, 300)
	X4R.st32(gp + 8, 200 << 16); X4R.st32(gp + 12, 300 << 16)
	# abelha (main 5) no slot 0, em (300, 280)
	X4R.st8(mo + 0, 0x41); X4R.st8(mo + 1, 5); X4R.st8(mo + 2, 0)
	X4R.st32(mo + 8, 300 << 16); X4R.st32(mo + 12, 280 << 16)
	var t0 := Time.get_ticks_usec()
	for f in 120:
		X4M_mains_main_05_robot_bee.c_robot_bee_update(mo)
		if f % 20 == 0:
			print(f, " state=", X4R.ld8(mo + 4), " step=", X4R.ld8(mo + 5), "/", X4R.ld8(mo + 6), " x=", X4R.s32(mo + 8) / 65536.0, " y=", X4R.s32(mo + 12) / 65536.0, " hp=", X4R.s8(mo + 128), " frame=", X4R.ld8(mo + 95))
	print("us por quadro: ", (Time.get_ticks_usec() - t0) / 120)
	print("faltando: ", X4R.missing.keys())
	quit()
