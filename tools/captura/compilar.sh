#!/bin/bash
# Compila a captura (núcleo psxcore + roteiro) para Linux e Windows. uso: compilar.sh PASTA_DE_SAIDA
# Fontes do núcleo: PSXCORE (padrão /home/claude/psxcore), PSYZ (SPU), X4CORE (marcas e sysroot do núcleo).
set -e
O=$(realpath -m "${1:-/tmp/captura_bin}"); mkdir -p "$O"
X=${PSXCORE:-$(cd "$(dirname $0)/../psxcore" && pwd)}; PS=${PSYZ:-/home/claude/ext/mmx4/tools/psyz}; XC=${X4CORE:-$(cd "$(dirname $0)/../x4core" && pwd)}
MW=${LLVM_MINGW:-/home/claude/llvm-mingw}
D=$(cd "$(dirname $0)" && pwd)
LIVRE="-O2 -w -std=gnu11 -ffreestanding -fno-strict-aliasing -fno-stack-protector -fno-exceptions -fno-asynchronous-unwind-tables -nostdinc -isystem $(clang -print-resource-dir)/include -isystem $XC/sysroot"
for alvo in linux windows; do
  T=$(mktemp -d)
  if [ $alvo = linux ]; then CC="clang --target=x86_64-linux-gnu"; EXTRA=""; SAI="$O/captura"; else CC="$MW/bin/x86_64-w64-mingw32-clang"; EXTRA="-mno-stack-arg-probe"; SAI="$O/captura.exe"; fi
  for f in $XC/marca_inicio.c $XC/marca_fim.c $X/cpu.c $X/gte.c $X/hw.c $X/api.c; do $CC $LIVRE $EXTRA -I$X -c $f -o $T/$(basename $f).o; done
  for f in $PS/psyz/src/psyz/psyz_spu.c $PS/psyz/src/psyz/libspu.c; do $CC $LIVRE $EXTRA -D__psyz=1 -I$PS/psyz/include -I$PS/decomp/include -c $f -o $T/$(basename $f).o; done
  $CC -O2 -w -c $D/captura.c -o $T/captura.o
  # desenhista das telas: contas de ponto flutuante uma a uma (sem FMA automática), iguais em qualquer PC
  $CC -O2 -w -std=gnu11 -ffp-contract=off -fno-fast-math -c $D/desenho.c -o $T/desenho.o
  OBJS="$T/marca_inicio.c.o $(ls $T/*.o | grep -v -e marca_ -e captura.o -e desenho.o) $T/marca_fim.c.o $T/captura.o $T/desenho.o"
  if [ $alvo = linux ]; then $CC -o "$SAI" $OBJS; else $CC -static -o "$SAI" $OBJS; fi
  rm -rf $T
done
# captura pela recompilação do X6 (abre a DLL que o launcher monta no PC do jogador)
clang -O2 -w -o "$O/captura_rc" $D/captura_rc.c -ldl
$MW/bin/x86_64-w64-mingw32-clang -O2 -w -o "$O/captura_rc.exe" $D/captura_rc.c -lshell32
ls -la "$O"
