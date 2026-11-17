#!/bin/bash
# Compila o recompilador (psxrecomp-game) para Windows, sem DLLs (o pacote do amigo roda ele no PC dele).
# uso: recompilador.sh PASTA_DE_SAIDA   (fontes: psxrecomp do projeto MegaManX6Recomp, compilador: /home/claude/wtc)
set -e
O=$(realpath -m "${1:-/tmp/rcwin}")
F=${PSXRECOMP:-/home/claude/ext/MegaManX6Recomp/psxrecomp-v4/recompiler}
cmake -S "$F" -B "$O" -G Ninja -DCMAKE_TOOLCHAIN_FILE=/home/claude/wtc/mingw.cmake -DCMAKE_BUILD_TYPE=Release \
  -DPSXRECOMP_ENABLE_CHD=OFF -DBUILD_TESTING=OFF "-DCMAKE_EXE_LINKER_FLAGS=-static -static-libgcc -static-libstdc++" > "$O.cfg.log" 2>&1
ninja -C "$O" psxrecomp-game > "$O.build.log" 2>&1
ls -la "$O/psxrecomp-game.exe"
