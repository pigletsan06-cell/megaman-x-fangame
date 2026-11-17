# Mega Man X Fangame (projeto particular)

Fangame que junta o Mega Man X4, X5 e X6: hub com os chefes dos três jogos, armaduras montadas peça por peça,
Black Zero / Nightmare Zero e co-op online para 2 jogadores.

## O que tem aqui (e o que não tem)

Este repositório guarda **só o que foi feito para o fangame**: os scripts e cenas do Godot, a fonte e os sons dos
menus, o launcher e as ferramentas que preparam o jogo.

**Não tem nada dos discos**: nem as imagens, nem os sons, nem os vídeos, nem o código dos jogos. Tudo isso é gerado
no PC de cada jogador, a partir dos discos dele, pelo launcher.

## Como funciona para quem joga

1. Extrair o pacote e abrir o launcher.
2. Mostrar onde estão os 3 discos (`.bin`): Mega Man X4 (USA), Mega Man X5 (USA) e Mega Man X6 (USA) (v1.1).
   O launcher confere o SHA-1 de cada um.
3. Na primeira vez o launcher prepara tudo (tira a arte e os sons dos discos e monta o código dos três jogos).
   Demora alguns minutos.
4. Jogar. Das próximas vezes abre direto; quando sair uma versão nova, o launcher baixa só o que mudou.

## Pastas

- `godot/` — o projeto do jogo (sem os arquivos que vêm dos discos).
- `launcher/` — o launcher (projeto Godot separado).
- `tools/` — o extrator e os scripts que montam o jogo a partir dos discos.
