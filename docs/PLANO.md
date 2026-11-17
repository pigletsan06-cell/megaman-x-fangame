# Plano: o jogo inteiro gerado no PC do amigo, igual ao do dono

Pedido do dono (17/nov, 01:45): o amigo baixa, abre o launcher, PREPARAR, JOGAR — e o jogo tem que ficar **igual ao do PC
do dono**. Só dizer "pronto" quando uma pasta nova + os 3 discos gerar o jogo conferido arquivo por arquivo e uma fase jogada.

## Critério de "igual"

- Imagens: **mesmos pixels** (RGBA decodificado igual). Bytes do PNG podem mudar (codificador diferente), os pixels não.
- Sons/vídeos codificados (ogg/ogv): mesmo PCM/quadros antes de codificar e mesmos ajustes do codificador.
- JSON/dados: mesmo conteúdo.
- Referência: arquivos do PC do dono (`D:\x project\godot\assets`, lista em `/tmp/manifest_pc.json`; 2118 arquivos).

## Fatos já medidos

- O núcleo `psxcore` + `harness` é determinístico: as 8 telas de seleção do X5 saem com o mesmo SHA-1 do PC do dono
  (roteiro em `docs/INVENTARIO.md`).
- O desenho das telas passa pela GPU (shader `psx_gpu.gdshader` no Godot). Com outro rasterizador (Mesa softpipe no lugar do
  llvmpipe) 736 pontos de uma tela mudam 1 unidade (a mistura semitransparente). Ou seja: numa placa de vídeo qualquer as
  capturas saem quase iguais, mas não idênticas → a captura no PC do amigo tem que desenhar **sem depender da placa**.
- Sem PyPI/npm nesta máquina (só GitHub). Nada de numpy/Pillow no PC do amigo: as ferramentas de lá são C (compiladas aqui)
  e GDScript (no Godot que já vai no pacote).

## Ferramentas

- `llvm-mingw 20261104` (GitHub mstorsjo/llvm-mingw): `/home/claude/llvm-mingw` (Linux → Windows) e
  `~/.cache/fusion/llvm-mingw-20261104-ucrt-x86_64.zip` (compilador que vai no pacote, para compilar no PC do amigo).
- Godot 4.7.2 win64 e FFmpeg (BtbN) em `~/.cache/fusion`.

## Arquitetura no PC do amigo

1. `ferramentas/captura.exe` (C, nosso): núcleo `psxcore` + roteiro de controle + "fotografias" (VRAM, primitivas, RAM, som)
   + **desenho por software** idêntico ao do Godot/llvmpipe. Lê uma receita JSON (nossa) e escreve imagens cruas/WAV.
2. GDScript (`tools/extrator`) transforma: recortes, montagem de atlas, PNG/WebP, WAV → ogg (ffmpeg).
3. Código: `psxcore` vai pronto (é nosso); `x4core` (decompilação pública + nossas mudanças) e `recomp_x5/x6`
   compilados no PC do amigo com o llvm-mingw do pacote. Enquanto o recomp não estiver pronto, X5/X6 rodam no `psxcore`
   (o jogo já cai nele sozinho quando não acha o recomp).

## Andamento (17/nov madrugada)

- FEITO `tools/captura` (captura.c = harness com o núcleo junto; `compilar.sh` → Linux e Windows/llvm-mingw). No Linux sai
  idêntico ao harness (220 fotos iguais). Windows: compila, falta rodar num Windows.
- FEITO grupos `menus_x5` e `menus_x6` (roteiros em `tools/extrator/roteiros/*.json`; X5 anda com o controle, X6 escreve o
  cursor em 0x800CCEF7 via POKE `ccef6:0N00`): 16 telas com o mesmo SHA-1 do PC do dono, pelo launcher, pasta nova.
  O Godot precisa estar importado antes das capturas (etapa `godot_inicial`), senão as classes (X4Machine, X4R) não existem.
- Desenho das capturas no Windows: cópia do godot.exe em `ferramentas/render/` + `opengl32.dll` do Mesa llvmpipe 25.2.7
  (`~/.cache/fusion/mesa-llvmpipe-x64-25.2.7.7z`, GitHub mmozeiko/build-mesa; 7-Zip em `/home/claude/7z/7zz`). Falta testar.
- X4 (telas `x4_N`): foram feitas pelo x4core (`tests/x4ms.gd`, MMX4_ORACLE_SCENE=mission-briefing) → dependem do x4core
  compilado no PC do amigo.
- `mini`: as 24 normais são recortes das telas de seleção com máscara (`assets/menus/mascaras.json`); `*_cinza` é uma conta
  em cima delas (achar a fórmula). `donos` e `loading` são telas inteiras de outros momentos (achar o quadro/roteiro).
- x4core: decomp pública sozud/mmx4 no commit 4e16dfc + 22 arquivos mudados por nós + `src/godot/frame.c` (nosso) +
  `/home/claude/x4core/*` (nosso) + submódulo tools/psyz (sozud/psyz, ramo mmx4). Compilado com clang freestanding
  (`/home/claude/x4core/build.sh`). No PC do amigo: baixar o zip da decomp no commit, aplicar nossas mudanças, compilar com o
  llvm-mingw do pacote (de preferência LLVM 18, igual ao daqui).
- recomp X5/X6: `/home/claude/tools/rc_build.sh` (MegaManX{5,6}Recomp + psxrecomp-v4 + SDL3 + nosso psx_embed.cpp/gpu.c).
  É a parte mais pesada. Enquanto isso o jogo cai no psxcore sozinho (x4_machine.gd: usa recomp só se a classe existir).

- FEITO `mini_x4/x5/x6` (48 com os mesmos pontos; x4 depende das telas do X4) e `donos` (máscaras nossas, no repositório).
- Títulos: `titulo_x5` igual (quadro 600; cores "5bits": round(c*31/255)<<3 — os títulos foram desenhados com o shader
  antigo). `titulo_x6` APROXIMADO (diferença até 117 em 65% dos pontos: outro quadro/outra conversão; investigar).
  `titulo_x4` depende do X4. Faltam `loading/x5_a,b x6_a,b`, `press_start`, `menu_*_on/off`, `titulo_fusion`.
- Ideia para o que não der para refazer idêntico (feito à mão antes, sem script): refazer também no PC do dono com o mesmo
  caminho novo (perguntar ao dono) — aí os dois PCs ficam iguais entre si.
- Ferramenta de busca de quadros: /tmp/procura.sh (captura + desenho + compara com um alvo).

- FEITO grupo `codigo_x4` (extrair.gd): baixa a decompilação pública (sozud/mmx4 4e16dfc + sozud/psyz da55621; aqui os
  zips vêm de `git archive` porque o codeload é bloqueado: /tmp/zip_mmx4.zip /tmp/zip_psyz.zip), aplica `tools/x4core/*.patch`
  (aplicador de diff em GDScript), põe `frame.c`, compila com clang (llvm-mingw 23; precisou de -Wno-error=incompatible-pointer-types)
  e junta: Linux `libx4core.so` e Windows `x4core.dll` (ld.lld -flavor link, base 0x10000000, exporta x4core_init) — 9 s aqui.
  O x4core novo (clang 23) se comporta igual ao antigo (clang 18) no teste tests/x4ms.gd. Depois de compilar é preciso
  importar de novo (o Godot só carrega a extensão listada em .godot/extension_list.cfg).
- ATENÇÃO: o mesmo teste do X4 dá resultado diferente na pasta do dono (/home/claude/game) e numa pasta nova (/tmp/mx5/godot)
  com a MESMA biblioteca → algum arquivo de assets muda o caminho do X4 (achar qual quando os assets estiverem completos).
- Falta no pacote: o llvm-mingw (191 MB) — melhor o extrator baixar do GitHub na 1ª vez só o necessário (clang, ld.lld,
  DLLs do LLVM, lib/clang/23/include). Variáveis do launcher {clang} {lld} já existem.

- Teste completo (tools/testes/teste_discos_reais.sh, pasta nova + discos): 13 etapas em 146 s, tudo ok. 101 arquivos gerados
  que existem no PC do dono, 52 idênticos byte a byte (o resto: vídeos com a mesma imagem, miniaturas e título do X5 com os
  mesmos pontos, título do X6 aproximado).
- FEITO `textos_x5` (press_start + menu_*_on/off): sprites 16x16 direto da VRAM fotografada (`sprite_da_vram` em
  extrair.gd: página 384,0 de 4 bits, CLUT 0x7800 apagado / 0x7801 aceso, linha y, cores <<3, recorte nos opacos) — 7 iguais.
- FEITO `loading_x5/x6` (Now Loading aceso/apagado: X5 quadros 1288/1300, X6 1484/1480 do roteiro do hub, cores 5bits) — 4 iguais.
- X4 telas: tentativa /tmp/x4_telas_busca.gd (X4Machine + mission-briefing + mem(8,0) + mem(9,cursor), step_frame(true),
  foto do root) deu só um retângulo cinza — falta achar como as x4_N foram desenhadas (ver tests/x4ms.gd e scripts de
  fotos do X4 no hub; talvez desenhar pelo stream de primitivas como o render_dump).
- X4 no psxcore (sem x4core): engine_obj US = 0x801721C0 (state +0, unk1 +1, unk3 +3 = cursor, stage +0xC, unkE +0xE).
  Botões "start:900-905,start:1000-1005,cross:1100-1105,cross:1200-1205,start:1300-1305,cross:1400-1405" → estado 3 no
  quadro 1494, 3/8 no 1579 (QG: "Mavericks have been found at point 5567!"), unkE=0x0a. POKE unkE=0 (1721ce:0000:1580-1590)
  + cross a cada 40 quadros NÃO chegou na seleção até 3400. Próximas tentativas: unkE=0 desde 1494 até o fim (faixa), ou
  junto com stage; ver no x4core (runtime.c MMX4_ORACLE_SCENE) o que exatamente ele faz para "mission-briefing".
- PISTA X4: a decompilação tem um "oracle" (src/pc/oracle.c) que grava a tela direto da VRAM do psyz (buffer mostrado,
  y = (SP_DRAW_BUFFER^1)*240, cores 5 bits << 3) quando MMX4_ORACLE_SCENE bate ("mission-briefing" = engine.state 3).
  As x4_N devem ter saído daí, via /home/claude/x4core/test_main(.c). O X4Core no Godot NÃO devolve a VRAM ("vram" vem vazio).
  Caminho: rodar o test_main (ou igual) com o x4core compilado no PC do amigo, cena mission-briefing, unkE=0, cursor unk3.
  CORREÇÃO: o test_main não grava telas. Mais provável: X4Machine (game x4) roda o x4core e o step_frame pega
  `X4Core.vram` (só vem quando a VRAM muda: guardar a última não vazia) + `X4Core.prims`; gravar v_N/p_N como o harness e
  desenhar com tests/render_dump.gd (JOGO=x4), depois testar com e sem "5bits". Script de partida: /tmp/x4_vram_busca.gd.
  Tentado (17/nov ~04h): X4R.vram_draw vem com 1 MB, mas `m.stream` fica vazio mesmo com step_frame(true) no jogo x4 →
  ver em x4_machine.gd (step_frame, ~linhas 387-438) de onde vêm as primitivas do x4 nativo antes de repetir.
  ACHADO: sem X4_SEM_VIDEO=1 o X4 fica parado esperando o vídeo (headless) → 0 primitivas; é isso que fazia a pasta do dono e a
  pasta nova darem resultados diferentes (a nova não tem os .ogv e pula). Com X4_SEM_VIDEO=1: quadro 300 estado 3/9 (conversa
  do QG), 1822 primitivas. Falta: apertar cross a cada 40 quadros (como tests/x4ms.gd: m.forced = 1<<6) até a seleção, então
  mem(8,0) / mem(9,cursor), gravar v/p e desenhar (JOGO=x4); comparar com e sem "5bits".
  CUIDADO: forçar mem(8,0) em TODOS os quadros 60-700 + cross derrubou o x4core (SIGSEGV). Escrever unkE uma vez só, no
  momento certo (ver no x4ms quando 3/8 → 3/1), ou achar no x4core/runtime.c como o hub chegou na seleção do X4.
  Também caiu (SIGSEGV) com mem(8,0) uma vez no quadro 60 + cross a cada 40 (X4_SEM_VIDEO=1, pasta do dono). Sem cross e sem
  X4_SEM_VIDEO não cai (mas fica no QG). Investigar com calma: rodar com o x4core de depuração ou ler o código da cena.
- `titulo_x6`: não é quadro do X6OP.STR nem do boot no psxcore (cores contínuas 0..255) — talvez do recomp. Fica aproximado.
- `titulo_fusion` (66x12, "FUSION" laranja itálico): montado por nós com letras de alguma fonte do jogo — achar as letras
  (provavelmente a fonte dos nomes de fase das telas de seleção X5/X6) e a posição de cada uma.
- FEITO `menus_x4` (17/nov 04h30): as 8 telas `x4_N` saem com o MESMO SHA-1 do PC do dono, pelo x4core compilado no PC do
  jogador. Caminho: `godot/tests/x4_fotos.gd` (X4Machine + MMX4_ORACLE_SCENE=mission-briefing, X4_SEM_VIDEO=1, mem(8,0) no
  quadro 3; o estado 3/4 é a seleção, a partir do quadro 363; sem apertar confirmar) grava v/p e o `render_dump.gd`
  (JOGO=x4) desenha. Cursor pelo controle (direita 480/560/640, baixo 720, esquerda 800/880/960); o pisca do cursor tem
  ciclo de 36 quadros. Cursor → arquivo: 0→x4_1 (q394), 1→x4_6 (514), 2→x4_7 (562), 3→x4_4 (646), 7→x4_2 (730),
  6→x4_8 (826), 5→x4_3 (886), 4→x4_5 (984). Roteiro `menus_x4.json` com "motor": "x4core" (extrair.gd roda o próprio jogo).
  `mini_x4` (16) com os mesmos pontos. Tudo em 1,5 s.
- PRÓXIMOS: (1) X4: telas x4_N + título + mini_x4 (achar o roteiro com o x4core; ver tests/x4ms.gd e a diferença de pasta);
  (2) loading x5/x6, press_start, menu_*, titulo_fusion; (3) intro (317); (4) sfx/musica; (5) sprites x/parts, zero;
  (6) psxcore no pacote (+ testar fase do X5/X6 pelo psxcore com X4_PSXCORE=1); (7) llvm-mingw baixado na 1ª vez;
  (8) Mesa no pacote; (9) recomp X5/X6.

## Andamento (17/nov tarde)

- **Windows: vídeos ficavam `.tmp.ogv`** (o extrator abria o arquivo para ver o tamanho e não fechava antes de renomear;
  no Windows não dá para renomear arquivo aberto). Corrigido em `extrair.gd`.
- **Vídeos idênticos byte a byte**: os .ogv do PC do dono foram feitos por um FFmpeg 4.4 **de Windows** (Lavf58.76.100).
  `tools/ffmpeg/compilar.sh` monta o FFmpeg 4.4.2 + libtheora 1.1.1 + libvorbis 1.3.7 + libogg 1.3.5 (mingw gcc 13.3,
  asm x86_64) e o pacote leva esse `ffmpeg.exe` no lugar do da BtbN. Mudanças nossas: números de série do Ogg pedidos
  (`FUSION_OGG_SERIAIS`, guardados no `VIDEOS` do extrator), texto do muxer (`FUSION_OGG_VENDOR`), a libvorbis sem o
  `rint` → `floor(x+.5)` do Windows (`os.h`), contas da libm com o resultado da glibc (`memo.c`, tabela gerada por
  `gera_registro.py`) e `qsort` estável. Teste no Wine, pasta nova: **15 de 15 vídeos com o mesmo SHA-1**.
  No Linux a libtheora sai diferente da do Windows (233 de 1044 quadros do X1_U), então o teste de vídeo é no Wine.
- **Músicas**: as do dono são do FFmpeg 6.1 do Linux; com o nosso ffmpeg + `serial`/`vendor`/`codificador` no roteiro
  o `titulo.ogg` sai igual byte a byte (o som decodificado já era igual; o x6_selecao segue aproximado).
- **Aberturas (317 WebP)**: gravadas pelo Pillow com a libwebp 1.6.0, qualidade 88, método 6. `tools/webp/webpenc.c`
  faz o mesmo caminho (`WebPEncode` com ARGB + `WebPMux`); as 317 saem iguais (8 quadros do X6 estavam 1 quadro antes).
- **Dash da Blade** (`dash6`, `dash6_add`): foi capturado da recompilação do X6. Roteiros achados (frente
  `88:0,6:4000,4:0,40:2000,40:0`, cima `...,40:0010`, baixo com pulo de 10 quadros) e `dash.gd` refaz igual pela DLL
  do X6 que o launcher monta (`tools/captura/captura_rc.c`, roda dentro da pasta da captura: os `psx_*.json` da
  recompilação faziam o launcher refazer tudo).
- **Sons**: `x5_nova` pela captura sem a música do CD (`SPUDBG ffffff:1:0`): igual do quadro 66 em diante;
  `fg_tele_out` pelo comando do x4core que toca um som do X4 (0xFFFFFF13 = 0x10B): mesmo som, outro volume.
- **Corte do Zero Nightmare** (`zero/x6/giga`): a luta fica na área secreta da fase 22 (área 0; as fases 19-22 têm
  2 áreas cada, as 8 áreas secretas). `corte_nz.gd` + `pecas/corte_nz.json`: a recompilação do X6 atravessa a área
  voando com a vida cheia (`captura_rc` ganhou opções: fase/área, paletas escondidas, escritas por quadro e voo), entra na
  sala, passa a conversa e espera o corte; o X pula no quadro 2499 (a onda mira o jogador: assim ela sobe meio ponto por
  quadro como na foto do dono). Cada quadro = pedaço ligado (8 vizinhos) dos pontos que mudam sem a paleta 0x794B, acima
  de y 200; 1x numa grade 91x91 e Scale3x do atlas inteiro (bordas repetidas). Os 25 quadros saem com os mesmos pontos
  do PC do dono (Linux e Windows iguais).
- **Sons do X4** (`menu_move`, `menu_ok`, `fg_tele_in`, `fg_tele_out`): gravados na fase 2 (a fase 1 tem a cachoeira por
  baixo, que deixava os teletransportes diferentes); ficam com no máximo 4 de diferença em 32768 (a gravação do dono tem
  ruído de arredondamento: não dá para sair byte a byte), no Linux e no Windows.
- **Teste final (17/nov, 17h)**: pacote novo + pasta nova + 3 discos no Windows (Wine): 37 etapas, "pronto"; 496 idênticos,
  306 mesmos pontos, 45 mesmo som; fases do X4, X5 e X6 carregam e jogam.
- **Falta**: `titulo_x6.png` e `x6_selecao.ogg` aproximados (o dono fez de outro jeito); `x5_nova` com um som a mais no
  começo da gravação do dono (meio segundo).

## Ordem de trabalho

1. [x] `captura` para Linux e Windows a partir das fontes do `psxcore` (mesmo resultado do harness).
2. [ ] Desenho por software igual ao llvmpipe (conferir com centenas de telas desenhadas aqui).
3. [~] Grupo `menus`: telas de seleção X4/X5/X6 (X5 e X6 prontos), títulos, botões, carregando, mini, donos.
4. [ ] `menus/intro` (317 quadros).
5. [ ] `sfx` e `musica`.
6. [ ] Sprites `x/parts`, `x/fx`, `zero`.
7. [ ] `psxcore` no pacote; `x4core` e recomp compilados no PC do amigo.
8. [ ] Teste final: pasta nova + discos → comparar tudo com o PC do dono; jogar uma fase; testar no Windows do dono.
