#!/bin/bash
# webpenc (codificador WebP do fangame, tools/webp/webpenc.c) com a libwebp 1.6.0 (licença BSD, Google), para o Windows.
# As aberturas das telas de seleção do PC do dono foram gravadas pelo Pillow com a libwebp 1.6.0 (qualidade 88, método 6):
# com o webpenc os 317 quadros saem iguais byte a byte. memo_webp.c: pow() com o resultado da glibc para essas contas.
# uso: compilar.sh PASTA_DE_SAIDA   (precisa: git, mingw-w64 gcc 13.3 (xpack) em MINGW=.../bin; LINUX=1 também faz o do Linux)
set -e
O=$(realpath -m "${1:?uso: compilar.sh PASTA_DE_SAIDA}"); mkdir -p "$O"
D=$(cd "$(dirname "$0")" && pwd)
MINGW=${MINGW:-/home/claude/mingwgcc/xpack-mingw-w64-gcc-13.3.0-1/bin}
F=${FONTES:-$(mktemp -d)}; mkdir -p "$F"
[ -d "$F/libwebp" ] || git clone -q --depth 1 --branch v1.6.0 https://github.com/webmproject/libwebp.git "$F/libwebp"
L=$F/libwebp
monta() {   # monta CC AR SAIDA EXTRA...
  local CC=$1 AR=$2 SAI=$3; shift 3; local W; W=$(mktemp -d)
  for f in $L/src/dec/*.c $L/src/enc/*.c $L/src/dsp/*.c $L/src/utils/*.c $L/src/mux/*.c $L/src/demux/*.c $L/sharpyuv/*.c; do
    local FL=""; case $f in *_sse41.c) FL="-msse4.1";; *_avx2.c) FL="-mavx2";; esac
    $CC -O2 $FL -w -I$L -I$L/src -c "$f" -o "$W/$(basename $(dirname $f))_$(basename $f .c).o"
  done
  $AR rcs "$W/libwebp.a" "$W"/*.o
  $CC -O2 -I$L/src -o "$SAI" "$D/webpenc.c" "$D/memo_webp.c" "$W/libwebp.a" -Wl,--wrap=pow "$@"
  rm -rf "$W"
}
monta "$MINGW/x86_64-w64-mingw32-gcc" "$MINGW/x86_64-w64-mingw32-ar" "$O/webpenc.exe" -static -lshell32
[ -n "$LINUX" ] && monta gcc ar "$O/webpenc" -lm -lpthread
cat > "$O/LICENCA_WEBP.txt" <<EOT
webpenc.exe do Mega Man X Fusion: libwebp 1.6.0 (licença BSD, Copyright Google Inc., https://chromium.googlesource.com/webm/libwebp),
com o programa tools/webp/webpenc.c do fangame. Montado por tools/webp/compilar.sh.
EOT
[ -z "$FONTES" ] && rm -rf "$F"
ls -la "$O"
