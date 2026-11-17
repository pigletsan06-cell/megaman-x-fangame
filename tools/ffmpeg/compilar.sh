#!/bin/bash
# FFmpeg do fangame para o Windows: o mesmo FFmpeg 4.4.2 + libtheora 1.1.1 + libvorbis 1.3.7 + libogg 1.3.5 que fez
# os vídeos do PC do dono (os 15 .ogv saem com o mesmo SHA-1, e as músicas também). Só o que o extrator usa:
# leitor de STR (vídeo MDEC + som XA), Theora, Vorbis, Ogg. Licença: LGPL 2.1+ (FFmpeg) e BSD (Xiph).
# Mudanças nossas (ffmpeg-4.4.2-fusion.patch, libvorbis-1.3.7-windows.patch):
#   - FUSION_OGG_SERIAIS / FUSION_OGG_VENDOR: números de série e texto do muxer pedidos (o original sorteia);
#   - a libvorbis não troca o rint() por floor(x+0.5) no Windows (arredondamento igual ao do Linux);
#   - memo.c: contas da libm com o resultado da glibc (tabela) e qsort estável, para não depender da libm do Windows.
# uso: compilar.sh PASTA_DE_SAIDA    (precisa: git, nasm, mingw-w64 gcc 13.3 (xpack) em MINGW=.../bin)
set -e
O=$(realpath -m "${1:?uso: compilar.sh PASTA_DE_SAIDA}"); mkdir -p "$O"
D=$(cd "$(dirname "$0")" && pwd)
MINGW=${MINGW:-/home/claude/mingwgcc/xpack-mingw-w64-gcc-13.3.0-1/bin}
CC=$MINGW/x86_64-w64-mingw32-gcc; AR=$MINGW/x86_64-w64-mingw32-ar
F=${FONTES:-$(mktemp -d)}; mkdir -p "$F"
pega() { [ -d "$F/$1" ] || git clone -q --depth 1 --branch "$2" "$3" "$F/$1"; }
pega ffmpeg n4.4.2 https://github.com/FFmpeg/FFmpeg.git
pega theora v1.1.1 https://github.com/xiph/theora.git
pega vorbis v1.3.7 https://github.com/xiph/vorbis.git
pega ogg v1.3.5 https://github.com/xiph/ogg.git
(cd "$F/ffmpeg" && (git apply --check "$D/ffmpeg-4.4.2-fusion.patch" 2> /dev/null && git apply "$D/ffmpeg-4.4.2-fusion.patch") || true)
(cd "$F/vorbis" && (patch -p1 -N --dry-run < "$D/libvorbis-1.3.7-windows.patch" > /dev/null 2>&1 && patch -p1 -N < "$D/libvorbis-1.3.7-windows.patch" > /dev/null) || true)
P="$F/pref"; W=$(mktemp -d)
mkdir -p "$P/lib/pkgconfig" "$P/include/ogg" "$P/include/vorbis" "$P/include/theora"
printf '#ifndef __CONFIG_TYPES_H__\n#define __CONFIG_TYPES_H__\n#include <stdint.h>\ntypedef int16_t ogg_int16_t;\ntypedef uint16_t ogg_uint16_t;\ntypedef int32_t ogg_int32_t;\ntypedef uint32_t ogg_uint32_t;\ntypedef int64_t ogg_int64_t;\ntypedef uint64_t ogg_uint64_t;\n#endif\n' > "$P/include/ogg/config_types.h"
cp "$F/ogg/include/ogg/ogg.h" "$F/ogg/include/ogg/os_types.h" "$P/include/ogg/"
cp "$F/vorbis/include/vorbis/"*.h "$P/include/vorbis/"; cp "$F/theora/include/theora/"*.h "$P/include/theora/"
# libogg e libvorbis com os ajustes do Ubuntu (-ffast-math -fsigned-char); libtheora com os dela e o asm x86_64
for f in bitwise framing; do $CC -O2 -ffast-math -fsigned-char -w -I"$P/include" -c "$F/ogg/src/$f.c" -o "$W/ogg_$f.o"; done
$AR rcs "$P/lib/libogg.a" "$W"/ogg_*.o
for f in analysis bitrate block codebook envelope floor0 floor1 info lookup lpc lsp mapping0 mdct psy registry res0 sharedbook smallft synthesis window; do
  $CC -O3 -ffast-math -D_REENTRANT -fsigned-char -O2 -w -I"$P/include" -I"$F/vorbis/lib" -c "$F/vorbis/lib/$f.c" -o "$W/vb_$f.o"; done
$CC -O3 -ffast-math -D_REENTRANT -fsigned-char -O2 -w -I"$P/include" -I"$F/vorbis/lib" -c "$F/vorbis/lib/vorbisenc.c" -o "$W/ve_vorbisenc.o"
$AR rcs "$P/lib/libvorbis.a" "$W"/vb_*.o; $AR rcs "$P/lib/libvorbisenc.a" "$W"/ve_*.o
TF="-Wall -Wno-parentheses -O3 -fforce-addr -fomit-frame-pointer -finline-functions -funroll-loops -O2 -DOC_X86_ASM -DOC_X86_64_ASM -w -I$P/include -I$F/theora/include -I$F/theora/lib"
for f in analyze fdct encfrag encapiwrapper encinfo encode enquant huffenc mathops mcenc rate tokenize apiwrapper fragment idct internal state quant x86/mmxencfrag x86/mmxfdct x86/x86enc x86/sse2fdct x86/mmxfrag x86/mmxidct x86/mmxstate x86/x86state; do
  $CC $TF -c "$F/theora/lib/$f.c" -o "$W/te_$(basename $f).o"; done
$AR rcs "$P/lib/libtheoraenc.a" "$W"/te_*.o
for f in apiwrapper bitpack decapiwrapper decinfo decode dequant fragment huffdec idct info internal quant state x86/mmxidct x86/mmxfrag x86/mmxstate x86/x86state; do
  $CC $TF -c "$F/theora/lib/$f.c" -o "$W/td_$(basename $f).o"; done
$AR rcs "$P/lib/libtheoradec.a" "$W"/td_*.o
for n in ogg vorbis vorbisenc theoraenc theoradec; do
  case $n in vorbis) R="Requires: ogg"; L="-lvorbis -lm";; vorbisenc) R="Requires: vorbis"; L="-lvorbisenc";; ogg) R=""; L="-logg";; theoraenc) R="Requires: ogg"; L="-ltheoraenc";; theoradec) R="Requires: ogg"; L="-ltheoradec";; esac
  printf "prefix=$P\nName: $n\nDescription: $n\nVersion: 1.0\n$R\nLibs: -L$P/lib $L\nCflags: -I$P/include\n" > "$P/lib/pkgconfig/$n.pc"
done
$CC -O2 -c "$D/memo.c" -I"$D" -o "$W/memo.o"
WR="-Wl,--wrap=acos -Wl,--wrap=asin -Wl,--wrap=atan -Wl,--wrap=cos -Wl,--wrap=cosh -Wl,--wrap=exp -Wl,--wrap=exp2 -Wl,--wrap=log -Wl,--wrap=log10 -Wl,--wrap=sin -Wl,--wrap=sinh -Wl,--wrap=tan -Wl,--wrap=tanh -Wl,--wrap=atan2 -Wl,--wrap=hypot -Wl,--wrap=pow -Wl,--wrap=acosf -Wl,--wrap=sincos -Wl,--wrap=sincosf -Wl,--wrap=qsort"
B=$(mktemp -d); cd "$B"
PATH=$MINGW:$PATH PKG_CONFIG_PATH="$P/lib/pkgconfig" PKG_CONFIG_LIBDIR="$P/lib/pkgconfig" "$F/ffmpeg/configure" --target-os=mingw32 --arch=x86_64 \
  --cross-prefix=x86_64-w64-mingw32- --enable-cross-compile --pkg-config=pkg-config --disable-everything --disable-doc --disable-debug \
  --disable-autodetect --disable-network --disable-ffplay --disable-ffprobe --enable-w32threads --enable-libtheora --enable-libvorbis \
  --enable-protocol=file,pipe --enable-demuxer=str,pcm_s16le,ogg --enable-decoder=mdec,adpcm_xa,pcm_s16le,theora,vorbis \
  --enable-encoder=libtheora,libvorbis,rawvideo,pcm_s16le --enable-muxer=ogg,ogv,oga,rawvideo,pcm_s16le \
  --enable-filter=scale,aresample,format,aformat,null,anull,setpts,asetpts,trim,atrim,copy,acopy --enable-swscale --enable-swresample \
  --extra-cflags="-I$P/include" --extra-ldflags="-L$P/lib -static $WR" --extra-libs="$W/memo.o -lm" --pkg-config-flags="--static" > configure.log
PATH=$MINGW:$PATH make -j$(nproc) ffmpeg.exe > make.log
cp ffmpeg.exe "$O/ffmpeg.exe"
cat > "$O/LICENCA_FFMPEG.txt" <<EOT
ffmpeg.exe do Mega Man X Fusion: FFmpeg 4.4.2 (LGPL 2.1 ou posterior, https://ffmpeg.org), com libtheora 1.1.1,
libvorbis 1.3.7 e libogg 1.3.5 (licença BSD da Xiph.Org, https://xiph.org). Montado por tools/ffmpeg/compilar.sh,
com as mudanças em tools/ffmpeg/*.patch e tools/ffmpeg/memo.c (fontes no repositório do fangame).
EOT
rm -rf "$W" "$B"; [ -z "$FONTES" ] && rm -rf "$F"
ls -la "$O/ffmpeg.exe"
