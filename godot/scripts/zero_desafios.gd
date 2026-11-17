class_name ZeroDesafios
## Black Zero (X4) e Nightmare Zero (X6): cada fase tem um desafio jogando de Zero.
## 4 fases dão as peças (capacete, corpo, braços, pernas) e 4 dão as melhorias de cada uma.
## Números da fase vindos do x4core (x4_mem 40..49, ver fangame.c fg_zero_track):
##   0 quadros jogando, 1 quadros com chefe, 2 danos, 3 danos no chefe, 4 mortes, 5 sub tank usado,
##   6 quadros de dash, 7 itens de vida pegos, 8 quadros de técnica no chefe, 9 vida perdida no chefe,
##   10 melhor sequência de inimigos destruídos sem levar dano (x4_mem 63)

const SLOTS := ["helmet", "body", "arms", "legs"]
const SLOT_NAME := {"helmet": "Capacete", "body": "Corpo", "arms": "Braços", "legs": "Pernas"}
# fase -> [prêmio, desafio, parâmetro]
const X4 := {
	1: ["helmet", "sem_dano_chefe", 0],      # Web Spider
	2: ["body", "sem_item_vida", 0],         # Frost Walrus
	3: ["arms", "so_sabre", 0],              # Split Mushroom
	6: ["legs", "tempo", 180],               # Cyber Peacock (segundos)
	4: ["arms+", "speed_kill", 40],          # Magma Dragoon (segundos com o chefe)
	7: ["legs+", "sem_dash", 0],             # Storm Owl
	8: ["body+", "sem_morrer_tank", 0],      # Slash Beast
	5: ["helmet+", "combo", 5],              # Jet Stingray
}
# X6 (Nightmare Zero): só desafios da fase inteira (o X6 roda emulado e não sabemos onde fica a vida do chefe)
const X6 := {
	1: ["helmet", "sem_item_vida", 0],       # Commander Yammark
	2: ["body", "max_golpes", 3],            # Blizzard Wolfang
	3: ["arms", "tempo", 270],               # Blaze Heatnix
	4: ["legs", "max_golpes", 5],            # Metal Shark Player
	5: ["helmet+", "sobrevivente", 0],       # Ground Scaravich
	6: ["body+", "sem_morrer_tank", 0],      # Rainy Turtloid
	7: ["arms+", "sem_dash", 0],             # Shield Sheldon
	8: ["legs+", "max_golpes", 1],           # Infinity Mijinion
}
const TEXTO := {
	"max_golpes": "terminar a fase levando no máximo %d golpe(s)",
	"sem_tecnica": "terminar a fase sem usar técnicas (só o sabre)",
	"sobrevivente": "terminar a fase com mais da metade da vida",
	"sem_dano_chefe": "vencer o chefe sem levar dano",
	"sem_item_vida": "terminar a fase sem pegar item de vida",
	"so_sabre": "vencer o chefe só com o sabre (sem técnicas)",
	"tempo": "terminar a fase em menos de %s",
	"speed_kill": "vencer o chefe em menos de %d s",
	"sem_dash": "terminar a fase sem usar o dash",
	"sem_morrer_tank": "terminar a fase sem morrer e sem sub tank",
	"combo": "destruir %d inimigos seguidos sem levar dano",
}

static func info(g: String, stage: int) -> Array:
	return X4.get(stage, []) if g == "x4" else (X6.get(stage, []) if g == "x6" else [])

static func table(g: String) -> Dictionary:
	return X4 if g == "x4" else (X6 if g == "x6" else {})

# números da fase no formato do X4 (zst) a partir dos do X6 (zst6), para usar as mesmas regras
static func from_x6(z6: Array) -> Array:
	# zst: 0 quadros, 1 quadros com chefe, 2 danos, 3 danos no chefe, 4 mortes, 5 sub tank, 6 dash, 7 itens de vida, 8 técnicas, 9 -, 10 combo
	var z := [z6[0], 0, z6[1], 0, z6[2], z6[3], z6[4], z6[5], z6[6], 0, 0]
	z.append(z6[7]); z.append(z6[8])   # 11 vida no fim, 12 vida máxima
	return z

static func describe(g: String, stage: int) -> String:
	var c := info(g, stage)
	if c.is_empty(): return ""
	var t: String = TEXTO[c[1]]
	if c[1] == "tempo": t = t % ("%d:%02d" % [int(c[2]) / 60, int(c[2]) % 60])
	elif c[1] == "speed_kill" or c[1] == "combo" or c[1] == "max_golpes": t = t % int(c[2])
	return t

static func prize_name(prize: String) -> String:
	var up := prize.ends_with("+")
	return SLOT_NAME[prize.trim_suffix("+")] + (" (melhoria)" if up else "")

# habilidades das peças do Nightmare Zero (X6; psx_embed.cpp nz_*), todas de alto risco
const NZ_ABIL := {"helmet": "Frenesi", "body": "Sobrecarga", "arms": "Eco do pesadelo", "legs": "Esquiva no limite"}
# nome da peça com a habilidade (Nightmare Zero): "Capacete (Frenesi)"
static func prize_label(g: String, prize: String) -> String:
	var n := prize_name(prize)
	if g == "x6" and NZ_ABIL.has(prize): n += " (%s)" % NZ_ABIL[prize]
	return n

static func key(g: String, prize: String) -> String:
	return ("BZ:" if g == "x4" else "NZ:") + prize

static func passed(c: Array, z: Array) -> bool:
	if z.size() < 10: return false
	match c[1]:
		"sem_dano_chefe": return int(z[1]) > 0 and int(z[3]) == 0
		"sem_item_vida": return int(z[7]) == 0
		"so_sabre": return int(z[1]) > 0 and int(z[8]) == 0
		"tempo": return int(z[0]) < int(c[2]) * 60
		"speed_kill": return int(z[1]) > 0 and int(z[1]) < int(c[2]) * 60
		"sem_dash": return int(z[6]) == 0
		"sem_morrer_tank": return int(z[4]) == 0 and int(z[5]) == 0
		"combo": return z.size() > 10 and int(z[10]) >= int(c[2])
		"max_golpes": return int(z[2]) <= int(c[2]) and int(z[4]) == 0
		"sem_tecnica": return int(z[8]) == 0
		"sobrevivente": return z.size() > 12 and int(z[11]) * 2 > int(z[12])
	return false

# o que o jogador fez (para mostrar quando o desafio não foi cumprido)
static func measured(c: Array, z: Array) -> String:
	if z.size() < 10: return ""
	match c[1]:
		"sem_dano_chefe": return "levou %d golpes do chefe" % int(z[3])
		"sem_item_vida": return "pegou %d itens de vida" % int(z[7])
		"so_sabre": return "usou técnicas no chefe"
		"tempo": return "fez em %d:%02d" % [int(z[0]) / 3600, (int(z[0]) / 60) % 60]
		"speed_kill": return "chefe em %d s" % (int(z[1]) / 60)
		"sem_dash": return "usou o dash"
		"sem_morrer_tank": return "%d mortes, sub tank %s" % [int(z[4]), "usado" if int(z[5]) > 0 else "não usado"]
		"combo": return "melhor sequência: %d" % (int(z[10]) if z.size() > 10 else 0)
		"max_golpes": return "levou %d golpes" % int(z[2])
		"sem_tecnica": return "usou técnicas"
		"sobrevivente": return "terminou com %d de %d de vida" % [int(z[11]), int(z[12])] if z.size() > 12 else ""
	return ""

# fim da fase de Zero vencida: libera a peça/melhoria se o desafio foi cumprido; devolve a chave nova ("" = nada)
static func apply(s: Dictionary, g: String, stage: int, won: bool, z: Array) -> String:
	var c := info(g, stage)
	if c.is_empty() or not won or not passed(c, z): return ""
	var k := key(g, c[0])
	if not s.has("zero"): s["zero"] = []
	if k in s.zero: return ""
	s.zero.append(k)
	return k

static func has(s: Dictionary, g: String, prize: String) -> bool:
	return key(g, prize) in s.get("zero", [])

# máscara para o x4core: bits 0-3 peças (capacete, corpo, braços, pernas), 4-7 melhorias
static func mask(s: Dictionary, g: String) -> int:
	var m := 0
	for i in 4:
		if has(s, g, SLOTS[i]): m |= 1 << i
		if has(s, g, SLOTS[i] + "+"): m |= 1 << (i + 4)
	return m

static func count(s: Dictionary, g: String) -> int:
	var n := 0
	for p in SLOTS:
		if has(s, g, p): n += 1
	return n
