"""Monta o kit da recompilação do X5/X6 para o pacote do amigo (roda aqui, na hora de empacotar).

O kit tem tudo o que NÃO vem do disco, já compilado aqui exatamente como foi para as DLLs do PC do dono
(build_win dos projetos MegaManX5Recomp/MegaManX6Recomp + nossas mudanças): os objetos do runtime (psxrecomp),
as bibliotecas (SDL3, zlib, ...), as bibliotecas do sistema (mingw-w64, libc++), o recompilador para Windows e
os arquivos de configuração. O código do jogo (SLUS_*.c) é gerado do disco do jogador, compilado e ligado no PC
dele pelo extrator (tools/extrator/extrair.gd, codigo_recomp).

uso: python3 kit.py SAIDA [RECOMPILADOR.exe]
"""
import json
import os
import re
import shlex
import shutil
import subprocess
import sys

W = "/home/claude/wtc/prefix"
LIB = W + "/x86_64-w64-mingw32/lib"
AR = W + "/bin/llvm-ar"
JOGOS = {"x5": ("/home/claude/ext/MegaManX5Recomp", "SLUS_013.34", "mmx5"),
         "x6": ("/home/claude/ext/MegaManX6Recomp", "SLUS_013.95", "mmx6")}
RT_JOGO = "/home/claude/game/bin/recomp_%s/game.toml"   # game.toml de execução (o mesmo do PC do dono)


def comando_ligador(build):
    """o comando do ld.lld que o clang++ do link.sh roda (com -###)"""
    sh = open(os.path.join(build, "emb/link.sh")).read()
    sh = sh.replace("x86_64-w64-mingw32-clang++ ", "x86_64-w64-mingw32-clang++ -### ", 1)
    r = subprocess.run(["bash", "-c", sh], cwd=build, capture_output=True, text=True)
    linha = [l for l in r.stderr.splitlines() if "ld.lld" in l][-1]
    return shlex.split(linha)


def main(argv):
    out = os.path.realpath(argv[0])
    exe_rc = argv[1] if len(argv) > 1 else "/tmp/rcwin/psxrecomp-game.exe"
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out + "/lib")
    libs_usadas = set()
    for g, (proj, exe, pasta) in JOGOS.items():
        build = proj + "/build_win"
        d = os.path.join(out, g)
        for s in ("deps", "res", "include", "recompilar/seeds", "recompilar/bios", "execucao/bios"):
            os.makedirs(os.path.join(d, s), exist_ok=True)
        cmd = comando_ligador(build)
        # objetos (.obj/.o/.res) na ordem do link; os gerados ficam de fora (são feitos no PC do jogador)
        args = cmd[1:]
        objs = [a for a in args if a.endswith((".obj", ".o", ".res")) and not a.startswith(W)]
        gen = [o for o in objs if "/generated/SLUS_" in o]
        i0 = objs.index(gen[0]); i1 = objs.index(gen[-1])
        assert all("/generated/SLUS_" in o for o in objs[i0:i1 + 1])
        antes = [o for o in objs[:i0] if o.endswith(".obj")]
        depois = [o for o in objs[i1 + 1:] if o.endswith(".obj")]
        emb = [o for o in objs if o.startswith("emb/")]
        res = [o for o in objs if o.endswith(".res")]
        for nome, lista in (("antes.a", antes), ("depois.a", depois)):
            subprocess.run([AR, "qcs", os.path.join(d, nome)] + lista, cwd=build, check=True)
        for o in emb:
            shutil.copy(os.path.join(build, o), os.path.join(d, os.path.basename(o)))
        for o in res:
            shutil.copy(os.path.join(build, o), os.path.join(d, "res", os.path.basename(o)))
        # bibliotecas: as do projeto vão em deps/, as do sistema em lib/ (comum aos dois jogos)
        ligar = []   # o que vem depois dos objetos, na ordem
        i_emb = max(args.index(e) for e in emb)
        for a in args[i_emb + 1:]:
            if a.startswith("-l"):
                nome = a[3:] if a.startswith("-l:") else "lib%s.a" % a[2:]
                libs_usadas.add(os.path.join(LIB, nome)); ligar.append(a)
            elif a.startswith(W):
                libs_usadas.add(a); ligar.append("lib/" + os.path.basename(a))
            elif a.endswith(".a"):
                shutil.copy(os.path.join(build, a), os.path.join(d, "deps", os.path.basename(a)))
                ligar.append("deps/" + os.path.basename(a))
            else:
                ligar.append(a)
        # cabeçalhos que o código gerado inclui (só os do runtime; os do sistema vão em sysinc/)
        nin = open(os.path.join(build, "build.ninja")).read()
        m = re.search(r"build CMakeFiles/psx-runtime.dir/generated/%s_full_00\.c\.obj:.*?\n  DEFINES = (.*?)\n.*?\n  FLAGS = (.*?)\n  INCLUDES = (.*?)\n" % re.escape(exe), nin, re.S)
        defines, flags, includes = m.group(1), m.group(2), m.group(3)
        gerados = [os.path.basename(o)[:-4] for o in gen]   # SLUS_..._full_00.c ...
        dep = subprocess.run(W + "/bin/x86_64-w64-mingw32-clang %s %s %s -M %s" % (defines, includes, flags,
                             " ".join(os.path.join(proj, "generated", f) for f in gerados)),
                             shell=True, cwd=build, capture_output=True, text=True)
        hs = set(t for t in dep.stdout.replace("\\\n", " ").split() if t.endswith(".h"))
        for h in hs:
            if h.startswith(W) or "/generated/" in h:
                continue
            shutil.copy(h, os.path.join(d, "include", os.path.basename(h)))
        sys_h = sorted(set(os.path.realpath(h) for h in hs if h.startswith(W)))
        for h in sys_h:
            rel = h.split("/include/", 1)[1] if "/include/" in h else os.path.basename(h)
            base = "clang" if "/lib/clang/" in h else "mingw"
            dst = os.path.join(out, "sysinc", base, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy(h, dst)
        # o que o recompilador lê (game.toml do projeto com os nossos ganchos, sementes, perfil da BIOS)
        shutil.copy(os.path.join(proj, "game.toml"), os.path.join(d, "recompilar/game.toml"))
        shutil.copy(os.path.join(proj, "seeds/ghidra_funcs.txt"), os.path.join(d, "recompilar/seeds/ghidra_funcs.txt"))
        shutil.copy(os.path.join(proj, "psxrecomp-v4/bios/SCPH1001.toml"), os.path.join(d, "recompilar/bios/SCPH1001.toml"))
        # pasta de execução (bin/recomp_xN do jogo): game.toml de execução e a OpenBIOS
        shutil.copy(RT_JOGO % g, os.path.join(d, "execucao/game.toml"))
        shutil.copy(os.path.join(proj, "psxrecomp-v4/bios/openbios.bin"), os.path.join(d, "execucao/bios/openbios.bin"))
        shutil.copy(os.path.join(proj, "psxrecomp-v4/bios/OpenBIOS.LICENSE"), os.path.join(d, "execucao/bios/OpenBIOS.LICENSE"))
        # licenças
        shutil.copy(os.path.join(proj, "LICENSE"), os.path.join(d, "LICENCA_%s_RECOMP.txt" % g.upper()))
        tp = os.path.join(proj, "THIRD-PARTY-LICENSES")
        if os.path.isdir(tp):
            shutil.copytree(tp, os.path.join(d, "LICENCAS_DE_TERCEIROS"))
        elif os.path.exists(tp):
            shutil.copy(tp, os.path.join(d, "LICENCAS_DE_TERCEIROS.txt"))
        shutil.copy(os.path.join(proj, "psxrecomp-v4/LICENSE"), os.path.join(d, "LICENCA_PSXRECOMP.txt"))
        json.dump({
            "exe": exe, "pasta": pasta, "gerados": gerados,
            "defines": shlex.split(defines), "flags": shlex.split(flags),
            "emb": [os.path.basename(e) for e in emb], "res": [os.path.basename(r) for r in res],
            "ligar": ligar,
            "inicio": ["-m", "i386pep", "--shared", "-Bstatic", "-e", "DllMainCRTStartup", "--enable-auto-image-base"],
            "pilha": ["--stack", "67108864"],
        }, open(os.path.join(d, "kit.json"), "w"), indent=1)
        print(g, "objetos antes", len(antes), "depois", len(depois), "gerados", len(gerados), "cabeçalhos", len(hs))
    libs_usadas.update(os.path.join(LIB, f) for f in ("dllcrt2.o", "crtbegin.o", "crtend.o"))
    for l in sorted(libs_usadas):
        if os.path.exists(l):
            shutil.copy(l, os.path.join(out, "lib", os.path.basename(l)))
        else:
            print("biblioteca não achada:", l)
    shutil.copy(exe_rc, os.path.join(out, "psxrecomp-game.exe"))
    print("kit em", out)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
