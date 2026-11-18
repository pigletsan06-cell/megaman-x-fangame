#!/bin/bash
# Monta o atualizacao.zip de uma versão: o launcher baixa esse arquivo da versão mais nova publicada no GitHub
# (Releases, tag vN = "versao" do versao.json) e aplica por cima da pasta do jogo.
# Vai só o que é do repositório + a captura compilada (ferramentas/captura*.exe). Nada dos discos.
# uso: tools/atualizacao.sh SAIDA.zip [VERSAO_ANTERIOR]
#   VERSAO_ANTERIOR (tag ou commit): o que foi apagado desde ela vai para remover.txt (o launcher apaga)
set -e
REPO=$(cd "$(dirname $0)/.." && pwd); SAIDA=$(realpath -m "${1:?uso: atualizacao.sh SAIDA.zip [versao_anterior]}"); ANT=$2
CAMINHOS="godot launcher tools/extrator tools/receita.json tools/captura tools/x4core tools/psxcore versao.json novidades.json"
T=$(mktemp -d)
(cd "$REPO" && git archive HEAD $CAMINHOS) | tar -x -C "$T"
cp "$REPO/tools/LEIA-ME.txt" "$T/LEIA-ME.txt"
mkdir -p "$T/ferramentas"
CB=$(mktemp -d); "$REPO/tools/captura/compilar.sh" "$CB" > /dev/null; cp "$CB/captura.exe" "$CB/captura_rc.exe" "$T/ferramentas/"; rm -rf "$CB"
[ -n "$ANT" ] && (cd "$REPO" && git diff --name-only --diff-filter=D "$ANT" HEAD -- $CAMINHOS) > "$T/remover.txt"
# confere: nada dos discos
if find "$T" \( -iname "*.bin" -o -iname "*.iso" -o -iname "*.str" -o -iname "*.sec" -o -iname "*.ogv" -o -iname "*.xa" \) ! -name "openbios.bin" | grep -q .; then echo "ERRO: arquivo de disco na atualização"; exit 1; fi
rm -f "$SAIDA"; (cd "$T" && zip -qr -9 "$SAIDA" .)
rm -rf "$T"
ls -la "$SAIDA"; unzip -l "$SAIDA" | tail -1
