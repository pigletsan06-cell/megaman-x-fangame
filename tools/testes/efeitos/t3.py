import sys; sys.path.insert(0,'/tmp/ex')
from motor import *
D='/tmp/ex/u6'
sel={'inc':[{'tpy':0,'tpx':[896],'clut':[0x7802,0x7803]}]}
REF='/home/claude/game/assets/x/parts/Ultimate_X6/plasma'
A=np.array(Image.open(REF+'/atlas.png').convert('RGBA')); F=json.load(open(REF+'/frames.json'))['frames']
for clamp in (False,True):
    for box in (48,40,60):
        fotos,orig=varre_armas(D,2422,2480,X6,[0x14],sel,box,clamp=clamp)
        print('clamp',clamp,'box',box,confere(fotos,REF), [(k,fotos[k][0].shape,fotos[k][1:],(F[k]['h'],F[k]['w'],F[k]['ox'],F[k]['oy'])) for k in sorted(fotos)][:2])
