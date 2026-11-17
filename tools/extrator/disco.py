"""Leitura de disco de PS1 em .bin (MODE2/2352, uma trilha): setores, sistema de arquivos ISO9660 e arquivos.

Nada do disco fica guardado aqui: o extrator lê o disco do próprio jogador e gera os arquivos no PC dele.
"""
import os
import struct

SETOR = 2352


class Disco:
    def __init__(self, caminho):
        self.caminho = caminho
        self.f = open(caminho, "rb")
        self.n_setores = os.path.getsize(caminho) // SETOR
        self._arquivos = None

    def dados(self, lba, n=1):
        """os 2048 bytes de dados (modo 2 forma 1) de n setores a partir do lba"""
        out = bytearray()
        for i in range(n):
            self.f.seek((lba + i) * SETOR + 24)
            out += self.f.read(2048)
        return bytes(out)

    def bruto(self, lba, n=1):
        """os 2352 bytes inteiros de cada setor"""
        self.f.seek(lba * SETOR)
        return self.f.read(SETOR * n)

    def subcabecalho(self, lba):
        self.f.seek(lba * SETOR + 16)
        return self.f.read(8)

    # ---- ISO9660 ----
    def arquivos(self):
        """{caminho em maiúsculas sem ';1': (lba, tamanho)} de todos os arquivos do disco"""
        if self._arquivos is not None:
            return self._arquivos
        pvd = self.dados(16)
        raiz = pvd[156:156 + 34]
        lba, tam = struct.unpack_from("<I", raiz, 2)[0], struct.unpack_from("<I", raiz, 10)[0]
        out = {}
        self._le_dir(lba, tam, "", out)
        self._arquivos = out
        return out

    def _le_dir(self, lba, tam, pref, out):
        d = self.dados(lba, (tam + 2047) // 2048)
        i = 0
        while i < tam:
            n = d[i]
            if n == 0:   # resto do setor vazio
                i = (i // 2048 + 1) * 2048
                continue
            reg = d[i:i + n]
            l2, t2 = struct.unpack_from("<I", reg, 2)[0], struct.unpack_from("<I", reg, 10)[0]
            flags = reg[25]
            nl = reg[32]
            nome = reg[33:33 + nl]
            if nome not in (b"\x00", b"\x01"):
                nm = nome.decode("ascii", "replace").split(";")[0]
                if flags & 2:
                    self._le_dir(l2, t2, pref + nm + "/", out)
                else:
                    out[pref + nm] = (l2, t2)
            i += n

    def le_arquivo(self, nome):
        lba, tam = self.arquivos()[nome.upper()]
        return self.dados(lba, (tam + 2047) // 2048)[:tam]
