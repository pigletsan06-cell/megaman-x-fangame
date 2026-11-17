"""Confere o CONTEÚDO dos arquivos gerados com a lista (tamanho + SHA-1) tirada do PC do dono.

uso: confere_conteudo.py PASTA_DO_JOGO_GERADO MANIFESTO.json PASTA_DO_JOGO_DO_DONO [prefixo ...]

Para cada arquivo da lista que existe na pasta gerada:
  - mesmo SHA-1 ............................................. "idêntico"
  - PNG com os mesmos pontos (RGBA) ........................... "mesmos pontos"
  - OGG/WAV com o mesmo som depois de decodificar (ffmpeg) .... "mesmo som"
  - WebP (com perdas): PSNR em dB contra o do dono ............ "aproximado (PSNR mín.)"
  - o resto ................................................... "diferente"
Mostra também quantos faltam, por pasta.
"""
import collections
import hashlib
import io
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image


def sha1(p):
    return hashlib.sha1(open(p, "rb").read()).hexdigest()


def pontos(p):
    return np.asarray(Image.open(p).convert("RGBA"))


def som(p):
    r = subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-i", p, "-f", "s16le", "-ac", "2", "-ar", "44100", "-"],
                       capture_output=True)
    return r.stdout


def psnr(a, b):
    a = a.astype(float); b = b.astype(float)
    m = ((a - b) ** 2).mean()
    return 99.0 if m == 0 else 10 * np.log10(255 * 255 / m)


def main(argv):
    jogo, man, dono = argv[0], json.load(open(argv[1])), argv[2]
    pref = argv[3:]
    alvo = {p: v for p, v in man.items() if not pref or any(p.startswith(x) for x in pref)}
    res = collections.defaultdict(list)
    faltam = collections.Counter()
    psnr_min = {}
    for p, (tam, sha) in sorted(alvo.items()):
        c = os.path.join(jogo, p); d = os.path.join(dono, p)
        pasta = "/".join(p.split("/")[:3])
        if not os.path.exists(c):
            faltam[pasta] += 1
            continue
        if sha1(c) == sha:
            res["idêntico"].append(p); continue
        ext = p.rsplit(".", 1)[-1].lower()
        if not os.path.exists(d):
            res["diferente (sem o do dono para comparar)"].append(p); continue
        if ext == "png":
            a, b = pontos(c), pontos(d)
            res["mesmos pontos" if a.shape == b.shape and (a == b).all() else "diferente"].append(p)
        elif ext in ("ogg", "wav"):
            res["mesmo som" if som(c) == som(d) else "diferente"].append(p)
        elif ext == "webp":
            a = np.asarray(Image.open(c).convert("RGB")); b = np.asarray(Image.open(d).convert("RGB"))
            v = psnr(a, b) if a.shape == b.shape else 0.0
            psnr_min[pasta] = min(psnr_min.get(pasta, 99.0), v)
            res["aproximado (WebP)"].append(p)
        else:
            res["diferente"].append(p)
    total = len(alvo)
    print(f"{total} arquivos na lista")
    for k in ("idêntico", "mesmos pontos", "mesmo som", "aproximado (WebP)", "diferente", "diferente (sem o do dono para comparar)"):
        if res[k]:
            print(f"  {k}: {len(res[k])}")
    for pasta, v in sorted(psnr_min.items()):
        print(f"    WebP {pasta}: PSNR mínimo {v:.1f} dB")
    for p in res["diferente"][:20]:
        print("    diferente:", p)
    print(f"  faltando: {sum(faltam.values())}")
    for pasta, n in faltam.most_common(25):
        print(f"    {n:5d} {pasta}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
