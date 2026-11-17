"""Extrator do Mega Man X Fusion: gera no PC do jogador, a partir dos discos dele, os arquivos que o jogo usa.

uso: extrair.py PASTA_DO_JOGO GRUPO [GRUPO...] disco_x4=CAMINHO disco_x5=CAMINHO disco_x6=CAMINHO

Cada grupo escreve seus arquivos em PASTA_DO_JOGO/assets. O launcher lê as linhas "@progresso a/b texto".
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from disco import Disco  # noqa: E402
import grupos  # noqa: E402


def progresso(a, b, texto=""):
    print(f"@progresso {a}/{b} {texto}", flush=True)


def main(argv):
    pos = [a for a in argv if "=" not in a]
    opc = dict(a.split("=", 1) for a in argv if "=" in a)
    if len(pos) < 2:
        print(__doc__)
        return 2
    jogo, nomes = pos[0], pos[1:]
    grupos.OPCOES.update(opc)
    discos = {}
    for jg in ("x4", "x5", "x6"):
        c = opc.get("disco_" + jg, "")
        if c and os.path.exists(c):
            discos[jg] = Disco(c)
    total = len(nomes)
    for i, nm in enumerate(nomes):
        g = grupos.GRUPOS.get(nm)
        if g is None:
            print(f"grupo desconhecido: {nm}", file=sys.stderr)
            return 2
        precisa = g.get("discos", [])
        falta = [d for d in precisa if d not in discos]
        if falta:
            print(f"{nm}: falta o disco {', '.join(falta)}", file=sys.stderr)
            return 3
        t0 = time.time()

        def prog(a, b, texto="", _i=i):
            # progresso do grupo dentro do total desta etapa
            progresso(_i * 1000 + int(1000 * a / max(1, b)), total * 1000, texto or nm)

        prog(0, 1, nm)
        n = g["faz"](jogo, discos, prog)
        print(f"{nm}: {n} arquivo(s) em {time.time() - t0:.1f} s", flush=True)
    progresso(total, total, "pronto")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
