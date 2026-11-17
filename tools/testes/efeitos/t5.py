import sys; sys.path.insert(0,'/tmp/ex')
from motor import *
from diag import diag
D='/tmp/ex/g5'; REF='/home/claude/game/assets/x/parts/Gaea_X5/shot'
sel={'inc':[{'tpy':0,'tpx':[320],'clut':[0x7844]}]}
fotos={}; orig={}
for f in range(2690,2958):
    r=open(f'{D}/r_{f}.bin','rb').read()
    for k in range(16):
        W=0x98120+k*0x9c
        if not (r[W]&1) or r[W+1] not in (0x2d,0x2e) or r[W+4] not in (1,2): continue
        key=(0 if r[W+1]==0x2d else 32)+(16 if r[W+4]==2 else 0)+r[W+0x47]
        if key in fotos: continue
        g=foto(D,f+1,f,W,0x9A1F8,sel,48,48,C=200,espelho='obj',bo=False)
        if g: fotos[key]=g; orig[key]=(f,k)
print(sorted(orig.items()))
print(confere(fotos,REF)); diag(fotos,REF)
