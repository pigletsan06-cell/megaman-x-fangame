#!/bin/bash
# Monta o pacote do amigo (Windows): só os arquivos do repositório + Godot e FFmpeg (programas livres). Nada dos discos.
# uso: tools/empacotar.sh SAIDA.zip [ARQUIVO_COM_A_CHAVE_DE_LEITURA]
# (a chave vai para chave.txt dentro do pacote; nunca para o repositório)
set -e
REPO=$(cd "$(dirname $0)/.." && pwd); SAIDA=$(realpath -m "${1:?uso: empacotar.sh SAIDA.zip [chave]}"); CHAVE=$2
CACHE=${CACHE:-$HOME/.cache/fusion}; mkdir -p "$CACHE"
GV=4.7.2
GZ=$CACHE/Godot_v${GV}-stable_win64.exe.zip
[ -s "$GZ" ] || curl -sSfL -o "$GZ" "https://github.com/godotengine/godot/releases/download/${GV}-stable/Godot_v${GV}-stable_win64.exe.zip"
# FFmpeg nosso (4.4.2 + libtheora/libvorbis/libogg, tools/ffmpeg): os vídeos e as músicas saem iguais aos do PC do dono
FV=$(cat "$REPO"/tools/ffmpeg/compilar.sh "$REPO"/tools/ffmpeg/*.patch "$REPO"/tools/ffmpeg/memo* | sha1sum | cut -c1-12); FF=$CACHE/ffmpeg-fusion-$FV
[ -s "$FF/ffmpeg.exe" ] || "$REPO/tools/ffmpeg/compilar.sh" "$FF" > /dev/null
# codificador WebP nosso (libwebp 1.6.0, tools/webp): as aberturas das telas de seleção saem iguais às do PC do dono
WV=$(cat "$REPO"/tools/webp/* | sha1sum | cut -c1-12); WP=$CACHE/webpenc-$WV
[ -s "$WP/webpenc.exe" ] || "$REPO/tools/webp/compilar.sh" "$WP" > /dev/null
T=$(mktemp -d); P="$T/Mega Man X Fusion"
mkdir -p "$P/engine" "$P/ferramentas" "$P/discos" "$P/gerado"
(cd "$REPO" && git archive HEAD godot launcher tools/extrator tools/receita.json tools/captura tools/x4core tools/psxcore versao.json novidades.json) | tar -x -C "$P"
cp "$REPO/tools/LEIA-ME.txt" "$P/LEIA-ME.txt"
echo "Coloque aqui os 3 discos (.bin): Mega Man X4 (USA).bin, Mega Man X5 (USA).bin, Mega Man X6 (USA) (v1.1).bin" > "$P/discos/COLOQUE OS DISCOS AQUI.txt"
unzip -q -o -j "$GZ" "Godot_v${GV}-stable_win64.exe" -d "$P/engine"; mv "$P/engine/Godot_v${GV}-stable_win64.exe" "$P/engine/godot.exe"
cp "$REPO/tools/windows/LICENCA_GODOT.txt" "$P/engine/" 2>/dev/null || true
cp "$FF/ffmpeg.exe" "$FF/LICENCA_FFMPEG.txt" "$WP/webpenc.exe" "$WP/LICENCA_WEBP.txt" "$P/ferramentas/"
# recompilação do X5/X6: kit com o runtime já compilado (psxrecomp, licença PolyForm Noncommercial) + recompilador;
# o código do jogo é gerado do disco e compilado no PC do jogador
[ -s "${RCWIN:-/tmp/rcwin}/psxrecomp-game.exe" ] || "$REPO/tools/recomp/recompilador.sh" "${RCWIN:-/tmp/rcwin}" > /dev/null
python3 "$REPO/tools/recomp/kit.py" "$P/ferramentas/recomp" "${RCWIN:-/tmp/rcwin}/psxrecomp-game.exe" > /dev/null
# captura (nosso núcleo de PS1 + SPU do psyz, MPL 2.0: código em github.com/sozud/psyz); também desenha as telas
# das fotos (desenho.c), sem placa de vídeo
CB=$(mktemp -d); "$REPO/tools/captura/compilar.sh" "$CB" > /dev/null; cp "$CB/captura.exe" "$CB/captura_rc.exe" "$P/ferramentas/"; rm -rf "$CB"
"$REPO/tools/windows/compilar.sh" "$P/Mega Man X Fusion.exe" > /dev/null
[ -n "$CHAVE" ] && tr -d ' \r\n' < "$CHAVE" > "$P/chave.txt"
# confere: nada dos discos (sem .bin/.iso/.STR/.sec, sem assets gerados) e nenhum arquivo fora da lista do repositório
if find "$P" \( -iname "*.bin" -o -iname "*.iso" -o -iname "*.str" -o -iname "*.sec" -o -iname "*.ogv" -o -iname "*.xa" \) ! -name "openbios.bin" | grep -q .; then echo "ERRO: arquivo de disco no pacote"; exit 1; fi
rm -f "$SAIDA"; (cd "$T" && zip -qr -9 "$SAIDA" "Mega Man X Fusion")
rm -rf "$T"
ls -la "$SAIDA"; unzip -l "$SAIDA" | tail -1
