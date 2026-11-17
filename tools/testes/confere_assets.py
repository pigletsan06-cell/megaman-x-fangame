"""Confere os arquivos gerados pelo extrator com a lista (tamanho + SHA-1) tirada do projeto que já funciona.

uso: confere_assets.py PASTA_DO_JOGO MANIFESTO.json [prefixo ...]
Mostra quantos batem byte por byte, quais faltam e quais saíram diferentes. Sai com 1 se algum não bater.
"""
import hashlib
import json
import os
import sys


def main(argv):
    jogo, man = argv[0], json.load(open(argv[1]))
    pref = argv[2:]
    alvo = {p: v for p, v in man.items() if not pref or any(p.startswith(x) for x in pref)}
    iguais, faltam, dif = [], [], []
    for p, (tam, sha) in sorted(alvo.items()):
        c = os.path.join(jogo, p)
        if not os.path.exists(c):
            faltam.append(p)
            continue
        h = hashlib.sha1(open(c, "rb").read()).hexdigest()
        (iguais if h == sha else dif).append(p)
    print(f"{len(iguais)} iguais, {len(faltam)} faltando, {len(dif)} diferentes (de {len(alvo)})")
    for p in dif[:30]:
        print("  diferente:", p)
    for p in faltam[:30]:
        print("  faltando:", p)
    return 0 if not faltam and not dif else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
