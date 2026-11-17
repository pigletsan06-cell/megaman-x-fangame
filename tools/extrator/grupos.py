"""Grupos do extrator: cada um gera uma parte de assets/ a partir dos discos do jogador.

GRUPOS[nome] = {"discos": [...], "faz": função(pasta_do_jogo, discos, progresso) -> nº de arquivos}
"""
import os
import subprocess
import tempfile

OPCOES = {}   # vindas da linha de comando (ex.: ffmpeg=CAMINHO)


def _escreve(jogo, rel, dados):
    p = os.path.join(jogo, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = p + ".tmp"
    with open(tmp, "wb") as f:
        f.write(dados)
    os.replace(tmp, p)


# ---- X4: os dados do disco que o núcleo do X4 lê (os primeiros 12947 setores, só a parte de dados) ----
X4_ARC_SETORES = 12947


def x4_arc(jogo, discos, prog):
    d = discos["x4"]
    partes = []
    bloco = 512
    for i in range(0, X4_ARC_SETORES, bloco):
        n = min(bloco, X4_ARC_SETORES - i)
        partes.append(d.dados(i, n))
        prog(i + n, X4_ARC_SETORES, "dados do disco do X4")
    _escreve(jogo, "assets/x4c_disc_arc.sec", b"".join(partes))
    return 1


# ---- vídeos: os .STR do disco convertidos para Theora/Vorbis (.ogv), que o Godot toca ----
# mesmos ajustes da conversão original: vídeo -q:v 8, som -q:a 5 a 44100 Hz (320x240, 15 quadros/s)
VIDEOS = {
    "x4": [("STR/CAPCOM20.STR", "CAPCOM20"), ("STR/OP_U.STR", "OP_U"), ("STR/X1_U.STR", "X1_U"), ("STR/X2_U.STR", "X2_U"),
           ("STR/X3_U.STR", "X3_U"), ("STR/X4_U.STR", "X4_U"), ("STR/Z1_U.STR", "Z1_U"), ("STR/Z2_U.STR", "Z2_U"),
           ("STR/Z3_U.STR", "Z3_U"), ("STR/Z4_U.STR", "Z4_U"), ("STR/Z5_U.STR", "Z5_U")],
    "x5": [("STR/CAPLOGO.STR", "x5_CAPLOGO"), ("STR/X5OP.STR", "x5_X5OP")],
    "x6": [("STR/CAPLOGO.STR", "x6_CAPLOGO"), ("STR/X6OP.STR", "x6_X6OP")],
}


def _ffmpeg():
    return OPCOES.get("ffmpeg") or os.environ.get("FUSION_FFMPEG") or "ffmpeg"


def _videos(jg):
    def faz(jogo, discos, prog):
        d = discos[jg]
        lista = VIDEOS[jg]
        os.makedirs(os.path.join(jogo, "assets/movies"), exist_ok=True)
        with tempfile.TemporaryDirectory() as tmp:
            for i, (nome, saida) in enumerate(lista):
                prog(i, len(lista), "vídeo " + saida)
                lba, tam = d.arquivos()[nome]
                n = (tam + 2047) // 2048
                src = os.path.join(tmp, saida + ".STR")
                with open(src, "wb") as f:   # o .STR precisa dos setores inteiros (vídeo + som XA)
                    for k in range(0, n, 256):
                        f.write(d.bruto(lba + k, min(256, n - k)))
                dst = os.path.join(jogo, "assets/movies", saida + ".ogv")
                cmd = [_ffmpeg(), "-v", "error", "-y", "-i", src, "-c:v", "libtheora", "-q:v", "8",
                       "-c:a", "libvorbis", "-q:a", "5", "-ar", "44100", dst + ".tmp.ogv"]
                r = subprocess.run(cmd, capture_output=True, text=True)
                # (o leitor de STR do ffmpeg reclama no fim do arquivo: normal, o vídeo sai inteiro)
                if not os.path.exists(dst + ".tmp.ogv") or os.path.getsize(dst + ".tmp.ogv") == 0:
                    raise RuntimeError(f"ffmpeg falhou em {saida}: {r.stderr[-300:]}")
                os.replace(dst + ".tmp.ogv", dst)
        prog(len(lista), len(lista), "vídeos prontos")
        return len(lista)
    return faz


GRUPOS = {
    "x4_arc": {"discos": ["x4"], "faz": x4_arc},
    "videos_x4": {"discos": ["x4"], "faz": _videos("x4")},
    "videos_x5": {"discos": ["x5"], "faz": _videos("x5")},
    "videos_x6": {"discos": ["x6"], "faz": _videos("x6")},
}
