#!/bin/bash
# procura.sh JOGO DISCO QUADRO_INI QUADRO_FIM PASSO "botões" "poke" ALVO1.png [ALVO2.png ...]
# roda a captura, desenha os quadros e diz quais alvos (comparando RGB) aparecem em quais quadros
J=$1; DISC=$2; F0=$3; F1=$4; P=$5; B=$6; PK=$7; shift 7
d=/tmp/proc_$J; rm -rf $d; mkdir -p $d
L=$(seq $F0 $P $F1 | paste -sd,)
NORAM=1 DUMPDIR=$d DUMP_LIST=$L POKE="$PK" /tmp/captura_bin/captura x /home/claude/megaman-x-fangame/tools/captura/openbios.bin "DISC=$DISC" $((F1+1)) "$B" > $d/log.txt 2>&1
D=$(echo $L | tr ',' '\n' | sed "s|^|$d/|" | paste -sd,)
DISPLAY=:99 JOGO=$J DUMPS=$D /home/claude/godot/Godot_v4.7.2-stable_linux.x86_64 --path /tmp/mx5/godot --rendering-method gl_compatibility -s res://tests/render_dump.gd > /dev/null 2>&1
python3 - "$d" "$@" <<'PY'
import sys, glob, numpy as np
from PIL import Image
d=sys.argv[1]; alvos={a: np.asarray(Image.open(a).convert('RGB')).astype(int) for a in sys.argv[2:]}
fs=sorted(glob.glob(d+'/tela_*.png'), key=lambda f:int(f.split('_')[-1][:-4]))
melhor={a:(10**9,None) for a in alvos}; exatos={a:[] for a in alvos}
for f in fs:
    q=int(f.split('_')[-1][:-4]); t=np.asarray(Image.open(f).convert('RGB')).astype(int)
    for a,x in alvos.items():
        if x.shape!=t.shape: continue
        n=int((x!=t).any(axis=2).sum())
        if n==0: exatos[a].append(q)
        if n<melhor[a][0]: melhor[a]=(n,q)
print(len(fs),'quadros desenhados')
for a in alvos: print(a.split('/')[-1], 'IGUAL em', exatos[a][:4], '...' if len(exatos[a])>4 else '', '| mais perto:', melhor[a])
PY
