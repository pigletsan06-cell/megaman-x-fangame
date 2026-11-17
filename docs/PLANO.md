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

## Ordem de trabalho

1. [x] `captura` para Linux e Windows a partir das fontes do `psxcore` (mesmo resultado do harness).
2. [ ] Desenho por software igual ao llvmpipe (conferir com centenas de telas desenhadas aqui).
3. [~] Grupo `menus`: telas de seleção X4/X5/X6 (X5 e X6 prontos), títulos, botões, carregando, mini, donos.
4. [ ] `menus/intro` (317 quadros).
5. [ ] `sfx` e `musica`.
6. [ ] Sprites `x/parts`, `x/fx`, `zero`.
7. [ ] `psxcore` no pacote; `x4core` e recomp compilados no PC do amigo.
8. [ ] Teste final: pasta nova + discos → comparar tudo com o PC do dono; jogar uma fase; testar no Windows do dono.
