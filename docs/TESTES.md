# Testes do launcher (16→17/nov)

Todos rodam numa **pasta nova** (sem `.godot/`, como chega no PC do amigo). Godot 4.7.2, Linux, tela virtual.

## `tools/testes/teste_launcher.sh` — 11 casos, 0 falhas (38 s)

| # | Caso | Esperado | Resultado |
|---|---|---|---|
| 1 | pasta nova com espaço e acento no caminho | 3 discos certos, 3 etapas feitas | ok |
| 2 | falta o disco do X6 | X6 "não encontrado", nada roda | ok |
| 3 | arquivo com o nome do X6 mas outro conteúdo | X6 "não é este disco", nada roda | ok |
| 4 | disco do X5 com outro nome | acha pelo tamanho + SHA-1 | ok |
| 5 | uma etapa falha no meio | essa etapa "deu erro", as seguintes esperam, erro no registro | ok |
| 6 | consertou e abriu de novo | só a etapa que falhou e as que dependem dela rodam | ok |
| 7 | abriu de novo sem mudar nada | não roda nada | ok |
| 8 | um arquivo de uma etapa mudou | só ela e as que dependem dela refazem | ok |
| 9 | `gerado/estado.json` estragado | recomeça sem travar | ok |
| 10 | `tools/receita.json` estragada | avisa "receita quebrada", não trava | ok |
| 11 | trocaram o disco depois de preparar | percebe (data/tamanho mudou → confere de novo) | ok |

## `tools/testes/teste_atualizador.sh` — GitHub de mentira, 4 casos

| # | Caso | Resultado |
|---|---|---|
| 1 | sem internet | avisa e prepara/joga normal |
| 2 | chave errada | "chave inválida", prepara/joga normal |
| 3 | versão 55 publicada | baixa (a chave não vai para o servidor do arquivo), aplica, apaga o que saiu (`remover.txt`), mantém `chave.txt` e o repositório no `versao.json`, refaz só a etapa que mudou |
| 4 | já está na 55 | nada a fazer, a chave continua valendo |

## `tools/testes/teste_discos_reais.sh` — receita de verdade com os 3 discos

Pacote novo + discos → o launcher sozinho: 5 etapas em ~82 s (dados do X4 0,3 s, vídeos do X4 63 s, X5 5 s, X6 7 s, importar 4 s).
Conferido com a lista do PC do dono (`confere_assets.py`):
- `x4c_disc_arc.sec`: **idêntico byte a byte**.
- 15 vídeos: mesmos ajustes; tamanhos ±0,11%; imagem igual (X1_U: 55 dB; CAPCOM20: 135 de 142 quadros idênticos e o brilho igual em todos;
  extrator em GDScript × em Python: quadros idênticos nos vídeos do X5 e do X6 conferidos). Os bytes do .ogv nunca batem porque o Ogg sorteia um número de série a cada conversão.

## Jogo a partir do repositório

`git archive` da pasta `godot/` + os assets e o `bin/` da cópia de trabalho → importou sem erro (88 s) e as fotos dos menus
(`menus_shot`, `char_shot`) saíram iguais às da cópia de trabalho a partir do mesmo save (diferenças só de animação no meio).
`hub_smoke` chega no hub igual nas duas. Ou seja: o código do jogo no repositório está completo.

## Pacote do Windows (`tools/empacotar.sh`)

153 MB (352 MB aberto), 247 arquivos, nada dos discos. Descompactado e rodado (no Linux, com o Godot do Linux): prepara tudo com um
disco renomeado ("meu disco x6.bin"). O abridor `Mega Man X Fusion.exe` (70 KB) é um executável de janela do Windows com só
kernel32/user32 — **ainda não testado num Windows de verdade**, nem o `godot.exe`/`ffmpeg.exe` rodando as etapas lá.

## Capturas do núcleo de PS1 (para o próximo grupo do extrator)

As 8 telas de seleção do X5 refeitas pelo `psxcore` + `render_dump.gd` andando com o controle de verdade, numa captura de 30 s:
**as 8 com o mesmo SHA-1** dos arquivos do PC do dono (`assets/menus/x5_1.png` … `x5_8.png`).
