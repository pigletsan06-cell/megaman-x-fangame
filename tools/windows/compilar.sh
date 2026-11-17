#!/bin/bash
# Compila "Mega Man X Fusion.exe" (abre o launcher) no Linux: clang + lld-link, sem MinGW nem Visual Studio.
# uso: tools/windows/compilar.sh SAIDA.exe
set -e
D=$(cd "$(dirname $0)" && pwd); O=${1:-"$D/Mega Man X Fusion.exe"}; T=$(mktemp -d)
printf 'LIBRARY kernel32.dll\nEXPORTS\nGetModuleFileNameW\nCreateProcessW\nCloseHandle\nGetFileAttributesW\nExitProcess\n' > $T/k32.def
printf 'LIBRARY user32.dll\nEXPORTS\nMessageBoxW\n' > $T/u32.def
llvm-dlltool -m i386:x86-64 -d $T/k32.def -l $T/kernel32.lib
llvm-dlltool -m i386:x86-64 -d $T/u32.def -l $T/user32.lib
clang --target=x86_64-pc-windows-msvc -O2 -ffreestanding -fno-builtin -mno-stack-arg-probe -fno-stack-protector -c "$D/abrir.c" -o $T/abrir.o
RES=""
if [ -f "$D/icone.ico" ]; then printf '1 ICON "%s"\n' "$D/icone.ico" > $T/r.rc; llvm-rc /fo $T/r.res $T/r.rc; RES=$T/r.res; fi
lld-link /subsystem:windows /entry:inicio /nodefaultlib /out:"$O" $T/abrir.o $T/kernel32.lib $T/user32.lib $RES
rm -rf $T
ls -la "$O"
