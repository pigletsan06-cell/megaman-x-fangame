# Inventário: o que é nosso e o que sai dos discos

O repositório só tem arquivos nossos. Tudo o que vem dos jogos é gerado **no PC do jogador, a partir dos discos dele**,
pelo launcher (receita em `tools/receita.json`, extrator em `tools/extrator/extrair.gd`, que roda dentro do próprio Godot).
Alvo: deixar a pasta `godot/` do jogador igual à do PC do dono (lista de referência: 2118 arquivos, 220,8 MB).

## Já está no repositório (nosso)

| O quê | Onde |
|---|---|
| Código do fangame (scripts, cenas, shaders, testes) | `godot/` |
| Fonte de pixel dos menus | `godot/assets/fonte` |
| 7 sons dos menus + `meta.json` dos sons | `godot/assets/sfx` |
| Máscaras do hub | `godot/assets/menus/mascaras.json` |
| Launcher (discos, preparação, atualização) | `launcher/` |
| Extrator, receita, pacote do Windows, testes | `tools/` |

## Gerado dos discos

| Grupo | Arquivos | MB | Como foi feito no PC do dono | Situação |
|---|---:|---:|---|---|
| `x4c_disc_arc.sec` | 1 | 26,5 | 12947 primeiros setores do disco do X4 | **pronto, idêntico byte a byte** |
| `movies` (vídeos) | 15 | 115,5 | .STR do disco → ffmpeg (Theora q8 / Vorbis q5, 44,1 kHz) | **pronto, mesma imagem** (o .ogv muda alguns bytes a cada conversão: número de série do Ogg; tamanhos ±0,11%) |
| `menus` (telas de seleção, títulos, botões) | 36 | 1,8 | capturas do nosso núcleo de PS1 (`psxcore`) + `render_dump.gd` | falta. Teste: a tela do X5 sai **idêntica pixel a pixel**, menos a janelinha de prévia da fase (64×48), que depende do estado do jogo na hora da captura |
| `menus/intro` | 317 | 7,1 | capturas (quadros das aberturas) | falta |
| `menus/mini`, `donos`, `loading` | 76 | 0,2 | recortes das capturas | falta |
| `musica` | 4 | 4,1 | som capturado do núcleo + laço (`tools/loop.py`) → Vorbis | falta |
| `sfx` (sons dos jogos) | ~52 | 3,5 | som capturado do núcleo | falta |
| `x/parts`, `x/fx`, `x` | 314 | 13,2 | capturas de sprites (`fusion/grab*.py`) | falta |
| `zero` (+ x5, x6, sabre, giga…) | 31 | 2,5 | capturas de sprites | falta |
| `x4c` | 3 | 3,7 | só reserva do X4 (o jogo usa o `.sec`) | falta (baixa prioridade) |
| `stages`, `enemy`, `retratos`, `x4_*.json` | 1258 | 42,5 | versão antiga do projeto | **não precisa** (o jogo de agora não abre) |

## Código dos jogos (pasta `godot/bin`, compilado no PC do jogador)

| Biblioteca | De onde | Situação |
|---|---|---|
| `psxcore` (núcleo de PS1) + OpenBIOS | nosso código + OpenBIOS (MIT) | pode ir pronto no pacote (não tem nada dos jogos) — falta pôr no pacote |
| `x4core` (X4) | decompilação pública (sozud/mmx4) + nossas mudanças | falta: compilar no PC do jogador |
| `recomp_x5`, `recomp_x6` | recompilação do código do disco (psxrecomp) | falta: gerar e compilar no PC do jogador (compilador junto no pacote) |

## Pacote do Windows (`tools/empacotar.sh`)

`Mega Man X Fusion.exe` (abridor nosso, 70 KB) · `engine/godot.exe` (Godot 4.7.2, MIT) · `ferramentas/ffmpeg.exe` (GPL) ·
`launcher/` · `godot/` · `tools/` · `discos/` · `LEIA-ME.txt`. Não precisa de Python. Nada dos discos (o script confere).

## Ordem sugerida

1. Testar o pacote no Windows de verdade (abridor, saída do Godot filho, ffmpeg.exe).
2. `menus` + `mini/donos/loading` (a captura já reproduz a tela; falta a prévia da fase e rodar a captura dentro do Godot com o `psxcore`).
3. `sfx` e `musica` (captura de som determinística + mesmo corte de laço).
4. `x` e `zero` (sprites).
5. Código: `x4core` (decompilação) e `recomp_x5/x6` (compilador junto no pacote).
6. Teste final: pasta nova + discos → comparar com a lista de referência do PC do dono.
