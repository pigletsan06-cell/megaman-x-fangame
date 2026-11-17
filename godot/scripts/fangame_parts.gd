class_name FangameParts
## Armaduras montadas por peça (capacete, corpo, braço, pernas), cada peça de uma armadura.
## As peças são liberadas pegando as cápsulas do Dr. Light; Fourth (X5) e Falcon (X6) já vêm liberadas.
## O Giga Attack de uma armadura só existe com as 4 peças dela.

const SLOTS := ["helmet", "body", "arms", "legs"]
const SLOT_NAME := {"helmet": "Capacete", "body": "Corpo", "arms": "Braço", "legs": "Pernas"}
# armaduras que podem ir em cada peça ("" = sem armadura). Fourth_X4P = braço do X4 com Plasma (Fourth_X4 = Stock)
const CHOICES := {
	"helmet": ["", "Fourth_X4", "Fourth_X5", "Falcon_X5", "Gaea_X5", "Falcon_X6", "Blade_X6", "Shadow_X6"],
	"body": ["", "Fourth_X4", "Fourth_X5", "Falcon_X5", "Gaea_X5", "Falcon_X6", "Blade_X6", "Shadow_X6"],
	"arms": ["", "Fourth_X4", "Fourth_X4P", "Fourth_X5", "Falcon_X5", "Gaea_X5", "Falcon_X6", "Blade_X6", "Shadow_X6"],
	"legs": ["", "Fourth_X4", "Fourth_X5", "Falcon_X5", "Gaea_X5", "Falcon_X6", "Blade_X6", "Shadow_X6"],
}
const NAME := {"": "sem armadura", "Fourth_X4": "Fourth (X4)", "Fourth_X4P": "Fourth (X4) Plasma", "Fourth_X5": "Fourth (X5)",
	"Falcon_X5": "Falcon (X5)", "Gaea_X5": "Gaea (X5)", "Falcon_X6": "Falcon (X6)", "Blade_X6": "Blade (X6)", "Shadow_X6": "Shadow (X6)"}
# código das habilidades no x4core (fg_head/fg_body/fg_arm/fg_legs)
const CODE := {"": 0, "Fourth_X4": 9, "Fourth_X4P": 9, "Falcon_X5": 1, "Gaea_X5": 2, "Fourth_X5": 3, "Falcon_X6": 5, "Blade_X6": 6, "Shadow_X6": 7}
const START_UNLOCKED := ["Fourth_X5", "Falcon_X6"]
# bits das cápsulas do X4 (x4core fg_caps): peça -> bit
const X4_CAP := {"helmet": 1, "body": 2, "arms": 4, "legs": 8}
const X4_CAP_PLASMA := 0x10
# o que cada peça faz (menu da tela de montagem)
const DESC := {
	"": {"helmet": "Nenhum efeito.", "body": "Nenhum efeito.", "arms": "Tiro carregado normal do X.", "legs": "Movimento normal (dash no chão)."},
	"Fourth_X4": {"helmet": "Socorro automático: se um golpe fosse matar o X, ele usa o Sub Tank mais cheio sozinho (não salva de buraco nem de espinho).",
		"body": "Escudo: segura um golpe inteiro e volta 10 s depois. Com as 4 peças: Nova Strike.",
		"arms": "Stock Charge: guarda até 4 tiros carregados.", "legs": "Dash no ar e Hover."},
	"Fourth_X4P": {"arms": "Plasma Charge: o tiro carregado deixa bolas de plasma."},
	"Fourth_X5": {"helmet": "Reação em cadeia: inimigo destruído explode em plasma e machuca quem está perto (e essa explosão pode destruir outro).",
		"body": "Plasma reativo: ao levar dano solta 4 bolas de plasma em volta, que machucam os inimigos por 1,5 s.",
		"arms": "Plasma Charge (como a Fourth do X5).", "legs": "Dash no ar e Hover."},
	"Falcon_X5": {"helmet": "Marca da presa: o 1º inimigo acertado leva o dobro de dano até morrer.",
		"body": "Aerodinâmico: anda e dá dash 20% mais rápido.",
		"arms": "Spear Charge: tiro carregado que atravessa.", "legs": "Voo livre por um tempo (Falcon Flight)."},
	"Gaea_X5": {"helmet": "Firmeza: não leva recuo e a carga não para.",
		"body": "Couraça: leva só 1/3 do dano, mas anda e dá dash 20% mais devagar.",
		"arms": "Gaea Shot: tiro curto e forte que quebra blocos (sem armas carregadas).", "legs": "Gruda nas paredes, anda em espinhos."},
	"Falcon_X6": {"helmet": "Mergulho: no ar, baixo + dash: mergulho rápido na diagonal para baixo que machuca o que acertar.",
		"body": "Superioridade aérea: tiros dados no ar causam 50% a mais.",
		"arms": "Tiro carregado que atravessa os inimigos.", "legs": "Dash no ar em qualquer direção."},
	"Blade_X6": {"helmet": "Saque rápido: a carga enche 2x mais rápido.",
		"body": "Contra-ataque: ao levar dano a carga enche e o próximo tiro sai cheio.",
		"arms": "Carga cheia: o X dá um golpe de sabre que solta uma rajada que explode e acerta várias vezes.", "legs": "Dash no ar que muda de direção."},
	"Shadow_X6": {"helmet": "Dash translúcido: o X fica transparente e não leva dano durante o dash (1 s de espera entre um dash protegido e outro).",
		"body": "Leva o dobro de dano, mas causa +0,5 de dano em cada golpe.",
		"arms": "Kunais no tiro normal e Engetsurin no carregado.", "legs": "Pulo bem alto e anda em espinhos."},
}
# habilidades novas do capacete e do corpo: número da armadura de onde veio a peça (X5/X6: psx_embed.cpp hab_*,
# x4_mem 0x1F900700/0x1F900701; X4: o x4core tira do código da peça)
const HAB := {"Shadow_X6": 1, "Blade_X6": 2, "Falcon_X6": 3, "Falcon_X5": 4, "Gaea_X5": 5, "Fourth_X5": 6, "Fourth_X4": 7}
static func hab_id(s: String) -> int:
	return int(HAB.get(asset(s), 0))
const GIGA := {"Fourth_X4": "Nova Strike", "Falcon_X5": "Giga Attack (Falcon)", "Gaea_X5": "Giga Attack (Gaea)",
	"Falcon_X6": "Giga Attack (Falcon)", "Blade_X6": "Giga Attack (Blade)", "Shadow_X6": "Giga Attack (Shadow)"}

static func asset(s: String) -> String:   # pasta dos sprites
	return "Fourth_X4" if s == "Fourth_X4P" else s

static func desc(s: String, slot: String) -> String:
	var d: Dictionary = DESC.get(s, {})
	if d.has(slot): return d[slot]
	return DESC.get(asset(s), {}).get(slot, "")

# armadura completa (4 peças da mesma): o nome dela, senão ""
static func full_set(parts: Dictionary) -> String:
	var a := asset(str(parts.get("helmet", "")))
	if a == "": return ""
	for p in SLOTS:
		if asset(str(parts.get(p, ""))) != a: return ""
	return a

# X6 montado: qual armadura do próprio X6 o jogo carrega (pernas, senão corpo, braço, capacete; 0 = nenhuma)
const X6_CODE := {"Falcon_X6": 1, "Shadow_X6": 2, "Blade_X6": 3, "Ultimate_X6": 4}
# o X6 carrega a armadura de UMA peça (desenhos, animações e velocidades dos golpes dela).
# Pernas primeiro: o voo e o dash no ar só andam na velocidade certa com a armadura das pernas carregada.
# Exceção: braço Shadow ou Ultimate. O tiro carregado deles sem a armadura carregada enche a tela de lixo
# (testado: braço Blade/Falcon funcionam com qualquer armadura carregada).
static func x6_native(parts: Dictionary) -> int:
	var arms := str(parts.get("arms", ""))
	if arms == "Shadow_X6" or arms == "Ultimate_X6": return X6_CODE[arms]
	# braço Falcon do X5 (lança) com pernas de fora do X6: a lança só aparece com a Falcon do X6 carregada (com a Falcon
	# do X5 inteira o X6 ficava sem armadura e soltava o tiro normal; testado: lança e voo do X5 funcionam com ela)
	if arms == "Falcon_X5" and not X6_CODE.has(str(parts.get("legs", ""))): return 1
	for p in ["legs", "arms", "body", "helmet"]:
		var a := str(parts.get(p, ""))
		if X6_CODE.has(a): return X6_CODE[a]
	# só peças de fora do X6: Fourth/Ultimate usam as habilidades da Ultimate do X6 (flutuar, Plasma, Nova) -> carrega ela
	for p in ["legs", "arms", "body", "helmet"]:
		if str(parts.get(p, "")).begins_with("Fourth") or str(parts.get(p, "")).begins_with("Ultimate"): return 4
	return 0

# peças do X4/X5 no X6: cada uma pega a habilidade do X6 que é a mesma. A Ultimate do X6 tem o flutuar e o dash no ar
# da Fourth (pernas), o Plasma (braço) e o Nova Strike; corpo = metade do dano, capacete = armas gastam menos.
# Braço Fourth do X4 sem Plasma (Stock Charge): o X6 não tem; tiro carregado normal + mods bit 5 (0x20): a recompilação
# guarda até 4 tiros cheios como no X4 (psx_embed.cpp stock_step).
# Braço Falcon do X5 (Spear Charge) = o tiro carregado da Falcon do X6 (a mesma lança que atravessa).
# Pernas Gaea do X5 (gruda na parede, anda em espinhos) = pernas da Shadow do X6 sem o pulo alto ("high": 0).
# Pernas Falcon do X5: o voo livre do X5 (8 direções, 180 quadros). Entra pelo flutuar da Ultimate do X6 (pulo no ar),
# a recompilação move o X como o X5 (psx_embed.cpp falcon5_step) e o fangame desenha o X5 (mods bit 0).
# Braço Gaea do X5: o limão e a carga cheia do X6 viram o tiro da Gaea e o Gaea Shot do X5 (alcance curto, somem
# animando; psx_embed.cpp gaea_step) e o fangame desenha (mods bit 1).
# Armadura completa Falcon_X5 / Gaea_X5: o Giga do X5 (R2 com a barra cheia; psx_embed.cpp giga5_step faz igual ao X5 e
# o fangame desenha o X5, os raios e o efeito) = mods bit 2 / bit 3.
const X6_FOREIGN := {
	"Fourth_X4":  {"legs": 4, "arms": 0, "body": 4, "helmet": 4},
	"Fourth_X4P": {"arms": 4},
	"Fourth_X5":  {"legs": 4, "arms": 4, "body": 4, "helmet": 4},
	"Falcon_X5":  {"legs": 0, "arms": 1, "body": 1, "helmet": 1},
	"Gaea_X5":    {"legs": 2, "arms": 0, "body": 1, "helmet": 1, "high": 0},
}
# Giga Attack (R2): só com as 4 peças da mesma armadura, igual ao X4 (fg_armor do x4core) e ao menu da montagem.
# Fourth do X4 completa = Nova Strike (o da Ultimate do X6, desenhado com as peças da Fourth).
const X6_GIGA := {"Falcon_X6": 1, "Shadow_X6": 2, "Blade_X6": 3, "Ultimate_X6": 4, "Fourth_X4": 4}
# código da armadura do X6 de cada peça [pernas, braço, corpo, capacete, Giga, pulo alto (cima + pulo, da Shadow),
# extras (bit 0 = voo livre da Falcon do X5, bit 1 = tiros da Gaea do X5)]
static func x6_part_codes(parts: Dictionary) -> Array:
	var r := []
	for p in ["legs", "arms", "body", "helmet"]:
		var a := str(parts.get(p, ""))
		r.append(int(X6_CODE[a]) if X6_CODE.has(a) else int(X6_FOREIGN.get(a, {}).get(p, 0)))
	r.append(int(X6_GIGA.get(full_set(parts), 0)))
	r.append(int(X6_FOREIGN.get(str(parts.get("legs", "")), {}).get("high", r[0])))
	var mods := 1 if asset(str(parts.get("legs", ""))) == "Falcon_X5" else 0
	if asset(str(parts.get("arms", ""))) == "Gaea_X5": mods |= 2   # tiros da Gaea do X5 (limão e carga cheia)
	if str(parts.get("arms", "")) == "Fourth_X4": mods |= 0x20   # Stock Charge do X4 (psx_embed.cpp stock_step)
	var fs := full_set(parts)
	if fs == "Falcon_X5": mods |= 4   # Giga da Falcon do X5 (raios)
	elif fs == "Gaea_X5": mods |= 8   # Giga da Gaea do X5
	r.append(mods)
	return r

# ---- X5 montado ----
# o X5 carrega a armadura de UMA peça. Pernas primeiro: o voo da Falcon fica parado no começo com outra armadura
# carregada (a animação dele só existe na Falcon) e a física da Gaea vem junto. Sem peça do X5: Fourth (X4) -> Fourth.
const X5_CODE := {"Fourth_X5": 1, "Falcon_X5": 2, "Gaea_X5": 3, "Ultimate_X5": 4}
static func x5_native(parts: Dictionary) -> int:
	# pernas Falcon: o voo só anda com a Falcon carregada. Senão, braço Falcon/Gaea: a lança e o tiro da Gaea só
	# aparecem com a armadura deles carregada (as pernas Fourth e a física da Gaea funcionam com qualquer uma)
	if str(parts.get("legs", "")) == "Falcon_X5": return 2
	var am := str(parts.get("arms", ""))
	if am == "Falcon_X5" or am == "Falcon_X6": return 2
	if am == "Gaea_X5": return 3
	for p in ["legs", "arms", "body", "helmet"]:
		var a := str(parts.get(p, ""))
		if X5_CODE.has(a): return X5_CODE[a]
	for p in ["legs", "arms", "body", "helmet"]:
		if str(parts.get(p, "")).begins_with("Fourth"): return 1
	return 0
# peças do X4/X6 no X5: a habilidade do X5 que é a mesma. Fourth do X4: pernas = flutuar + dash no ar (Fourth do X5),
# braço Plasma = Plasma; braço Falcon do X6 = a lança da Falcon. Corpo/capacete de qualquer armadura: metade do dano /
# armas gastam 2/3. Pernas e braço da Blade/Shadow não existem no X5: código 0 e a recompilação faz os golpes do X6
# (psx_embed.cpp x6p5_*: pulo alto/teto/parede/espinhos e dash da Blade nas pernas; shurikens/Engetsurin e sabre no braço).
const X5_FOREIGN := {
	"Fourth_X4":  {"legs": 1, "arms": 0, "body": 1, "helmet": 1},
	"Fourth_X4P": {"arms": 1},
	"Falcon_X6":  {"legs": 1, "arms": 2, "body": 2, "helmet": 2},   # pernas: dash no ar da Fourth -> voo da Falcon do X6
	"Blade_X6":   {"legs": 0, "arms": 0, "body": 1, "helmet": 1},
	"Shadow_X6":  {"legs": 0, "arms": 0, "body": 1, "helmet": 1},
}
# Giga (R2) só com as 4 peças da mesma armadura; Fourth do X4 completa = Nova Strike (o da Ultimate do X5); as do X6
# completas (Falcon/Blade/Shadow) fazem o Giga do X6 pela recompilação (extras bits 2-3)
const X5_GIGA := {"Falcon_X5": 2, "Gaea_X5": 3, "Ultimate_X5": 4, "Fourth_X4": 4}
# [pernas, braço, corpo, capacete, Giga, pulo alto (só no X6), extras]
# extras (bit 4 = pernas Falcon do X6: o dash no ar / pulo no ar viram o voo da Falcon do X6, psx_embed.cpp falcon6x5_step;
# bit 5 = braço Fourth do X4: Stock Charge, psx_embed.cpp stock_step; peças da Blade/Shadow do X6 (psx_embed.cpp x6p5_*):
# bit 0 braço Shadow, bit 1 braço Blade, bit 6 pernas Shadow, bit 7 pernas Blade; bits 2-3 = Giga do X6 com a armadura
# completa: 0x04 Falcon, 0x08 Blade, 0x0C Shadow, psx_embed.cpp g6_step)
static func x5_part_codes(parts: Dictionary) -> Array:
	var nat := x5_native(parts)
	var r := []
	for p in ["legs", "arms", "body", "helmet"]:
		var a := str(parts.get(p, ""))
		var c := int(X5_CODE[a]) if X5_CODE.has(a) else int(X5_FOREIGN.get(a, {}).get(p, 0))
		# lança da Falcon / tiro da Gaea com outra armadura carregada ficam invisíveis (os desenhos deles não estão na
		# memória; testado no X5 recompilado). O tiro da Gaea o fangame desenha (x4_machine mix6_x5gaea): fica o do X5.
		# A lança não acontece (braço Falcon sempre carrega a Falcon). O Plasma serve com todas.
		if p == "arms" and c == 2 and c != nat: c = 0
		r.append(c)
	r.append(int(X5_GIGA.get(full_set(parts), 0)))
	r.append(r[0])
	var la := asset(str(parts.get("legs", ""))); var aa := asset(str(parts.get("arms", "")))
	var ex := (0x10 if la == "Falcon_X6" else 0) | (0x20 if str(parts.get("arms", "")) == "Fourth_X4" else 0)
	ex |= (0x40 if la == "Shadow_X6" else 0) | (0x80 if la == "Blade_X6" else 0)
	ex |= (0x01 if aa == "Shadow_X6" else 0) | (0x02 if aa == "Blade_X6" else 0)
	# Giga do X6 (armadura completa): psx_embed.cpp g6_step faz o golpe do X6 no R2
	var fs6 := full_set(parts)
	ex |= 0x04 if fs6 == "Falcon_X6" else 0x08 if fs6 == "Blade_X6" else 0x0C if fs6 == "Shadow_X6" else 0
	r.append(ex)
	return r

static func giga_name(parts: Dictionary) -> String:
	return GIGA.get(full_set(parts), "")

# ---- liberação ----
static func default_unlocked() -> Array:
	var u := []
	for s in START_UNLOCKED:
		for p in SLOTS: u.append("%s:%s" % [s, p])
	return u

static func is_unlocked(save: Dictionary, s: String, slot: String) -> bool:
	if s == "": return true
	if s.begins_with("Fourth_X4"):   # cápsulas do X4 ficam no próprio bit do jogo
		var caps := int(save.get("games", {}).get("x4", {}).get("caps", 0))
		if s == "Fourth_X4P": return slot == "arms" and (caps & X4_CAP_PLASMA) != 0
		return (caps & X4_CAP[slot]) != 0
	return ("%s:%s" % [s, slot]) in Array(save.get("unlocked", []))

# ---- o que vai para o x4core ----
# devolve {"ARMOR": máscara das peças do X4, "SKILL": código da armadura completa, "PARTS": "h,b,a,l", "ARMTYPE": 1/2}
static func core_env(parts: Dictionary) -> Dictionary:
	var c := {}
	for p in SLOTS: c[p] = int(CODE.get(str(parts.get(p, "")), 0))
	var fs := full_set(parts)
	var mask := 0
	if c.helmet == 9: mask |= 1
	if c.body == 9: mask |= 2
	if c.arms != 0 and c.arms != 2: mask |= 4
	if c.legs in [3, 5, 6, 9]: mask |= 8
	var skill := 0
	if fs != "" and fs != "Fourth_X4" and X4Machine.SKIN_INFO.has(fs):
		mask = int(X4Machine.SKIN_INFO[fs][0]); skill = int(X4Machine.SKIN_INFO[fs][1])
	var at := 2 if str(parts.get("arms", "")) == "Fourth_X4P" else 1
	return {"ARMOR": str(mask), "SKILL": str(skill), "PARTS": "%d,%d,%d,%d" % [c.helmet, c.body, c.arms, c.legs], "ARMTYPE": str(at)}

# precisa dos sprites próprios (alguma peça que não é do X4)
static func needs_skin(parts: Dictionary) -> bool:
	for p in SLOTS:
		var s := asset(str(parts.get(p, "")))
		if s != "" and s != "Fourth_X4": return true
	return false
