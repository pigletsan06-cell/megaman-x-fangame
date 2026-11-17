#!/bin/bash
# Monta o pacote do amigo (Windows): só os arquivos do repositório + Godot e FFmpeg (programas livres). Nada dos discos.
# uso: tools/empacotar.sh SAIDA.zip [ARQUIVO_COM_A_CHAVE_DE_LEITURA]
# (a chave vai para chave.txt dentro do pacote; nunca para o repositório)
set -e
REPO=$(cd "$(dirname $0)/.." && pwd); SAIDA=$(realpath -m "${1:?uso: empacotar.sh SAIDA.zip [chave]}"); CHAVE=$2
CACHE=${CACHE:-$HOME/.cache/fusion}; mkdir -p "$CACHE"
GV=4.7.2
GZ=$CACHE/Godot_v${GV}-stable_win64.exe.zip
FZ=$CACHE/ffmpeg-master-latest-win64-gpl.zip
[ -s "$GZ" ] || curl -sSfL -o "$GZ" "https://github.com/godotengine/godot/releases/download/${GV}-stable/Godot_v${GV}-stable_win64.exe.zip"
[ -s "$FZ" ] || curl -sSfL -o "$FZ" "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
T=$(mktemp -d); P="$T/Mega Man X Fusion"
mkdir -p "$P/engine" "$P/ferramentas" "$P/discos" "$P/gerado"
(cd "$REPO" && git archive HEAD godot launcher tools/extrator tools/receita.json versao.json) | tar -x -C "$P"
cp "$REPO/tools/LEIA-ME.txt" "$P/LEIA-ME.txt"
echo "Coloque aqui os 3 discos (.bin): Mega Man X4 (USA).bin, Mega Man X5 (USA).bin, Mega Man X6 (USA) (v1.1).bin" > "$P/discos/COLOQUE OS DISCOS AQUI.txt"
unzip -q -o -j "$GZ" "Godot_v${GV}-stable_win64.exe" -d "$P/engine"; mv "$P/engine/Godot_v${GV}-stable_win64.exe" "$P/engine/godot.exe"
cp "$REPO/tools/windows/LICENCA_GODOT.txt" "$P/engine/" 2>/dev/null || true
unzip -q -o -j "$FZ" "*/bin/ffmpeg.exe" "*/LICENSE.txt" -d "$P/ferramentas"; mv "$P/ferramentas/LICENSE.txt" "$P/ferramentas/LICENCA_FFMPEG.txt"
"$REPO/tools/windows/compilar.sh" "$P/Mega Man X Fusion.exe" > /dev/null
[ -n "$CHAVE" ] && tr -d ' \r\n' < "$CHAVE" > "$P/chave.txt"
# confere: nada dos discos (sem .bin/.iso/.STR/.sec, sem assets gerados) e nenhum arquivo fora da lista do repositório
if find "$P" -iname "*.bin" -o -iname "*.iso" -o -iname "*.str" -o -iname "*.sec" -o -iname "*.ogv" | grep -q .; then echo "ERRO: arquivo de disco no pacote"; exit 1; fi
rm -f "$SAIDA"; (cd "$T" && zip -qr -9 "$SAIDA" "Mega Man X Fusion")
rm -rf "$T"
ls -la "$SAIDA"; unzip -l "$SAIDA" | tail -1
