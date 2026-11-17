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

## Ordem de trabalho

1. [ ] `captura` para Linux e Windows a partir das fontes do `psxcore` (mesmo resultado do harness).
2. [ ] Desenho por software igual ao llvmpipe (conferir com centenas de telas desenhadas aqui).
3. [ ] Grupo `menus`: telas de seleção X4/X5/X6, títulos, botões, carregando, mini, donos.
4. [ ] `menus/intro` (317 quadros).
5. [ ] `sfx` e `musica`.
6. [ ] Sprites `x/parts`, `x/fx`, `zero`.
7. [ ] `psxcore` no pacote; `x4core` e recomp compilados no PC do amigo.
8. [ ] Teste final: pasta nova + discos → comparar tudo com o PC do dono; jogar uma fase; testar no Windows do dono.
