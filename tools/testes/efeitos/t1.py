import sys; sys.path.insert(0,'/tmp/ex')
from motor import *
D='/tmp/ex/c5'; P=X5['P']; BG=X5['BG']
# carga: fase k = (f-S0)%10 (+10 cheia), foto do quadro f com a RAM de f-1
S0=2727; F0=S0+70; sel={'inc':[{'tpy':0,'tpx':[384,448],'clut':[0x7802]}]}
fotos={}
for f in range(S0,F0+25):
    k=(f-S0)%10+(10 if f>=F0 else 0)
    if k in fotos: continue
    g=foto(D,f,f-1,P,BG,sel,60,60)
    if g: fotos[k]=g
print('charge_fx',confere(fotos,'/home/claude/game/assets/x/parts/Fourth_X5/charge_fx'))
# soltura: 10 quadros a partir de R0 (RAM de f, foto de f+1), sempre espelhado
R0=2832; sel={'inc':[{'tpy':0,'tpx':[640,960]}]}
fotos={i:foto(D,f+1,f,P,BG,sel,90,90,C=240,espelho='sempre') for i,f in enumerate(range(R0,R0+10))}
print('charge_release',confere(fotos,'/home/claude/game/assets/x/parts/Falcon_X5/charge_release'))
