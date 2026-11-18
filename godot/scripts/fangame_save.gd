class_name FangameSave
## Save único do fangame (um arquivo para X4, X5 e X6, com 3 slots).
## Cada slot guarda: chefes vencidos por jogo (as armas vêm deles, como no jogo original), os itens já pegos em
## cada jogo (bits do próprio jogo, para não aparecerem de novo) e o que é compartilhado entre os 3 jogos:
## corações (vida máxima) e sub tanks (quantos e quanta energia cada um tem).

const FILE := "user://fangame_save.json"
const OLD_FILE := "user://fangame_progresso.json"
const SLOTS := 3
const GAMES := ["x4", "x5", "x6"]
const BASE_HP := 0x20     # vida inicial nos 3 jogos
const MAX_HEARTS := 24    # heart tanks dos 3 jogos (8 em cada)
const HEARTS_PER_UP := 3  # cada 3 heart tanks = +2 de vida máxima: com os 24, 8 aumentos = 0x30 (o máximo dos jogos)
# endereços no X5/X6 (bloco do jogo: X5 0x800D1C00, X6 0x800CCED0; mesma estrutura do engine_obj do X4)
const PSX := {
	"x5": {"hp": [0xD1C47, 0xD1C48], "bosses": 0xD1C4C, "upg": 0xD1C7E, "ext": 0xD1C80, "tanks": [0xD1C76, 0xD1C77], "parts": 0xD1CA0, "wpn": 0x9A169},
	"x6": {"hp": [0xCCF2B, 0xCCF2C], "bosses": 0xCCF30, "upg": 0xCCF3A, "ext": 0xCCF3C, "tanks": [0xCCF33, 0xCCF34], "parts": 0xCCF38, "wpn": 0x97169},
}
# programas de armadura das cápsulas do Dr. Light (X5 0x800D1CA0, X6 0x800CCF38, u16): cada fase tem uma cápsula;
# a peça que ela dá (fase -> [armadura, peça]):
const CAPSULE := {
	"x5": {5: ["Falcon_X5", "helmet"], 3: ["Falcon_X5", "body"], 6: ["Falcon_X5", "arms"], 1: ["Falcon_X5", "legs"],
		2: ["Gaea_X5", "helmet"], 8: ["Gaea_X5", "body"], 4: ["Gaea_X5", "arms"], 7: ["Gaea_X5", "legs"]},
	"x6": {5: ["Blade_X6", "helmet"], 7: ["Blade_X6", "body"], 8: ["Blade_X6", "arms"], 1: ["Blade_X6", "legs"],
		4: ["Shadow_X6", "helmet"], 6: ["Shadow_X6", "body"], 3: ["Shadow_X6", "arms"], 2: ["Shadow_X6", "legs"]},
}
const SUBTANK_BITS := [0x1000, 0x2000]   # collected_upgrades: sub tank 1 e 2 (os 3 jogos)
# sub tanks: 2 em cada jogo (6). O 1o achado dá o 1o sub tank, o 2o dá o 2o (o máximo dos jogos); a eficácia (quanto
# cada um guarda) sobe com o total achado: 25% a 100% da vida máxima (48)
const MAX_SUBTANKS := 6
const ST_CAP := [0, 12, 19, 26, 34, 41, 48]
const ST_PCT := [0, 25, 40, 55, 70, 85, 100]

static var data := {}
static var slot := -1      # slot em uso (-1 = ainda não escolhido nesta sessão)

static func empty_slot() -> Dictionary:
	return {"progress": {"x4": [], "x5": [], "x6": []}, "games": {"x4": {"upg": 0, "ext": 0}, "x5": {"upg": 0, "ext": 0}, "x6": {"upg": 0, "ext": 0}},
		"hearts": 0, "tanks": [], "used": false,
		"unlocked": FangameParts.default_unlocked(),   # peças de armadura liberadas ("Falcon_X5:legs"...); as do X4 ficam em games.x4.caps
		"parts": {"helmet": "Fourth_X5", "body": "Fourth_X5", "arms": "Fourth_X5", "legs": "Fourth_X5"}}   # armadura montada

static func load_file() -> void:
	if not data.is_empty(): return
	data = {"slots": [], "last": 0}
	if FileAccess.file_exists(FILE):
		var d = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		if d is Dictionary and d.get("slots") is Array: data = d
	while data.slots.size() < SLOTS: data.slots.append(empty_slot())
	for i in SLOTS: data.slots[i] = _fix(data.slots[i])
	# progresso antigo (só chefes vencidos) vira o slot 1
	if FileAccess.file_exists(OLD_FILE) and not data.slots[0].used:
		var o = JSON.parse_string(FileAccess.get_file_as_string(OLD_FILE))
		if o is Dictionary:
			for g in GAMES:
				if o.has(g): data.slots[0].progress[g] = Array(o[g]).map(func(v): return int(v))
			data.slots[0].used = true
			write()
			DirAccess.rename_absolute(ProjectSettings.globalize_path(OLD_FILE), ProjectSettings.globalize_path(OLD_FILE + ".antigo"))

static func _fix(s) -> Dictionary:
	var e := empty_slot()
	if not (s is Dictionary): return e
	for k in e:
		if not s.has(k): s[k] = e[k]
	for g in GAMES:
		if not s.progress.has(g): s.progress[g] = []
		s.progress[g] = Array(s.progress[g]).map(func(v): return int(v))
		if not s.games.has(g): s.games[g] = {"upg": 0, "ext": 0}
		s.games[g].parts = int(s.games[g].get("parts", 0))
		s.games[g].upg = int(s.games[g].get("upg", 0)); s.games[g].ext = int(s.games[g].get("ext", 0))
		s.games[g].st = int(s.games[g].get("st", 0))
	s.games.x4.caps = int(s.games.x4.get("caps", 0))
	s.unlocked = Array(s.unlocked)
	for p in FangameParts.SLOTS:
		if not s.parts.has(p): s.parts[p] = ""
	s.hearts = int(s.hearts)
	s.tanks = Array(s.tanks).map(func(v): return int(v))
	if not s.has("st_legado"): s.st_legado = mini(s.tanks.size(), 2)   # sub tanks de antes da eficácia (não se sabe de qual jogo)
	s.st_legado = int(s.st_legado)
	return s

static func write() -> void:
	var f := FileAccess.open(FILE, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(data, "\t")); f.close()

static func cur() -> Dictionary:
	load_file()
	return data.slots[clampi(slot, 0, SLOTS - 1)]

static func select(i: int) -> void:
	load_file(); slot = i; data.last = i
	data.slots[i].used = true
	write()

static func erase(i: int) -> void:
	load_file(); data.slots[i] = empty_slot(); write()

static func copy(src: int, dst: int) -> void:
	load_file(); data.slots[dst] = _fix(JSON.parse_string(JSON.stringify(data.slots[src]))); write()

static func st_found(s: Dictionary) -> int:
	var n := int(s.get("st_legado", 0))
	for g in GAMES: n += (int(s.games[g].get("st", 0)) & 1) + ((int(s.games[g].get("st", 0)) >> 1) & 1)
	return mini(n, MAX_SUBTANKS)

static func st_usable(s: Dictionary) -> int:
	return mini(st_found(s), 2)

static func st_cap(s: Dictionary) -> int:
	return ST_CAP[st_found(s)]

static func max_hp(s: Dictionary) -> int:
	return hp_for(int(s.hearts))

static func hp_for(hearts: int) -> int:
	return BASE_HP + 2 * mini(hearts / HEARTS_PER_UP, MAX_HEARTS / HEARTS_PER_UP)

# quantos heart tanks faltam para o próximo aumento (0 = vida no máximo)
static func hearts_to_next(s: Dictionary) -> int:
	var h := int(s.hearts)
	if h >= MAX_HEARTS: return 0
	return HEARTS_PER_UP - h % HEARTS_PER_UP

static func bosses_mask(s: Dictionary, g: String, stage: int) -> int:
	var m := 0
	for v in s.progress[g]:
		# X5/X6: a fase atual fica de fora (com o chefe marcado ele não aparece); X4: fica marcada (a arma continua e
		# o chefe aparece de novo, como no X4 original)
		if v >= 1 and v <= 8 and (v != stage or g == "x4"): m |= 1 << (v - 1)
	return m

# itens do jogo + sub tanks compartilhados: os slots que o jogador já tem (em qualquer jogo) ficam marcados
static func upgrades(s: Dictionary, g: String) -> int:
	var u: int = int(s.games[g].upg) & ~0x3000
	for i in st_usable(s): u |= SUBTANK_BITS[i]
	return u

static func tank_bytes(s: Dictionary) -> Array:
	var t := [0, 0]
	var c := st_cap(s)
	for i in st_usable(s): t[i] = 0x80 | clampi(int(s.tanks[i]) if i < s.tanks.size() else 0, 0, c)
	return t

# o que o hub passa para a fase (X4: variável de ambiente; X5/X6: escritas na RAM durante o carregamento)
static func launch_info(g: String, stage: int) -> Dictionary:
	var s := cur()
	var hp := max_hp(s); var up := upgrades(s, g); var bo := bosses_mask(s, g, stage); var tk := tank_bytes(s)
	var info := {"hearts": int(s.hearts), "hp": hp, "upg": up, "bosses": bo, "tanks": tk, "ext": int(s.games[g].ext), "caps": int(s.games.x4.get("caps", 0)),
		"parts": int(s.games[g].get("parts", 0))}
	info["key"] = "%x" % hash([hp, up, bo, tk, info.ext, info.parts, st_found(s)])
	info["st_cap"] = st_cap(s)
	if g == "x4":
		info["env"] = "%d,%d,%d,%d,%d,%d" % [hp, up, bo, tk[0], tk[1], int(s.games[g].get("wt", 0))]
		var m4 := int(s.games.x4.get("st", 0)) & 3
		info["tanks_env"] = "%d,%d" % [st_found(s) - (m4 & 1) - (m4 >> 1), m4]   # x4core: sub tanks achados fora do X4, máscara do X4
	else:
		var a: Dictionary = PSX[g]
		var pk := []
		for ad in a.hp: pk.append([ad, hp, 1])
		pk.append([a.bosses, bo, 1]); pk.append([a.upg, up, 2]); pk.append([a.ext, info.ext, 4])
		if info.parts != 0: pk.append([a.parts, info.parts, 2])   # programas de armadura já pegos (a palavra lida no fim da fase)
		for i in 2: pk.append([a.tanks[i], tk[i], 1])
		info["pokes"] = pk
		if g == "x6":   # X6 com armas: o jogo não enche a energia/capacidade delas quando o X aparece (o menu dividiria por 0)
			var fx := [[0x970A0 + 330, 0x120, 2]]
			for i in 16: fx.append([0x970A0 + 0xA8 + 2 * i, 0x120, 2])
			info["fix_pokes"] = fx
	return info

# fim da fase: o que mudou volta para o slot (r = valores lidos do jogo; start = launch_info usado)
static func apply_result(g: String, stage: int, won: bool, start: Dictionary, r: Dictionary) -> void:
	var s := cur()
	if won and not stage in s.progress[g]: s.progress[g].append(stage)
	if not r.is_empty() and not start.is_empty():
		if r.has("hearts_got"): s.hearts = mini(int(s.hearts) + int(r.hearts_got), MAX_HEARTS)   # heart tanks pegos nesta fase
		elif int(r.hp) > int(start.hp): s.hearts = mini(int(s.hearts) + (int(r.hp) - int(start.hp)) / 2, MAX_HEARTS)
		var up_end := int(r.upg)
		var novos := up_end & ~int(start.upg)
		# sub tanks achados nesta fase (X4: máscara do x4core; X5/X6: o bit novo do jogo)
		if r.has("st"): s.games[g].st = int(r.st) & 3
		else: s.games[g].st = int(s.games[g].get("st", 0)) | ((novos >> 12) & 3)
		var tanks: Array = s.tanks
		while tanks.size() < st_usable(s): tanks.append(0)   # sub tank novo entra vazio
		# energia dos sub tanks no fim da fase (o jogo enche e gasta)
		for i in mini(tanks.size(), 2):
			var b := int(r.tanks[i])
			if b & 0x80: tanks[i] = mini(b & 0x7F, st_cap(s))
		s.tanks = tanks
		s.games[g].upg = up_end & ~0x3000
		s.games[g].ext = int(r.ext)
		if r.has("wt"): s.games[g].wt = int(r.wt)   # tanque de arma do X4 (não é compartilhado)
		if r.has("parts") and r.has("parts0"):   # X5/X6: programa de armadura pego nesta fase -> peça liberada na montagem
			var np := int(r.parts) & ~int(r.parts0)
			s.games[g].parts = int(r.parts)
			if np != 0 and CAPSULE.has(g) and CAPSULE[g].has(stage):
				var c: Array = CAPSULE[g][stage]
				var k := "%s:%s" % [c[0], c[1]]
				if not k in s.unlocked: s.unlocked.append(k)
				s["new_part"] = k
		if r.has("caps"):   # cápsulas do Dr. Light pegas nesta fase
			var novas := int(r.caps) & 0xFF; var vestidas := (int(r.caps) >> 8) & 0xFF
			s.games[g].caps = int(s.games[g].get("caps", 0)) | novas
			for p in FangameParts.SLOTS:   # vestida no lugar vazio: continua vestida
				if vestidas & FangameParts.X4_CAP[p] and str(s.parts[p]) == "": s.parts[p] = "Fourth_X4"
			if vestidas & FangameParts.X4_CAP_PLASMA and str(s.parts.arms) == "": s.parts.arms = "Fourth_X4P"
	s.used = true
	write()

# lê do jogo rodando (chamado pelo x4_machine ao sair da fase)
static func read_game(g: String, core: String) -> Dictionary:
	if g == "x4":
		var t: int = ClassDB.class_call_static(core, "mem", 33, 0, 1)
		return {"st": int(ClassDB.class_call_static(core, "mem", 37, 0, 1)), "hp": int(ClassDB.class_call_static(core, "mem", 30, 0, 1)), "upg": int(ClassDB.class_call_static(core, "mem", 31, 0, 1)),
			"ext": 0, "tanks": [t & 0xFF, (t >> 8) & 0xFF], "wt": (t >> 16) & 0xFF, "caps": int(ClassDB.class_call_static(core, "mem", 36, 0, 1))}
	var a: Dictionary = PSX[g]
	return {"hp": int(ClassDB.class_call_static(core, "mem", a.hp[0], 0, 1)), "upg": int(ClassDB.class_call_static(core, "mem", a.upg, 0, 2)),
		"parts": int(ClassDB.class_call_static(core, "mem", a.parts, 0, 2)),
		"ext": int(ClassDB.class_call_static(core, "mem", a.ext, 0, 4)),
		"tanks": [int(ClassDB.class_call_static(core, "mem", a.tanks[0], 0, 1)), int(ClassDB.class_call_static(core, "mem", a.tanks[1], 0, 1))]}

static func summary(i: int) -> String:
	load_file()
	var s: Dictionary = data.slots[i]
	if not s.used: return "vazio"
	var parts := []
	for g in GAMES: parts.append("%s %d/8" % [g.to_upper(), s.progress[g].filter(func(v): return v >= 1 and v <= 8).size()])
	return "%s   heart tanks %d/%d   sub tanks %d/%d" % ["  ".join(parts), mini(int(s.hearts), MAX_HEARTS), MAX_HEARTS, st_found(s), MAX_SUBTANKS]
