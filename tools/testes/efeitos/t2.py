import sys; sys.path.insert(0,'/tmp/ex')
from motor import *
D='/tmp/ex/c5'
sel={'inc':[{'tpy':0,'tpx':[896],'clut':[0x7802,0x7803]}]}
fotos,orig=varre_armas(D,2832,2899,X5,[0x14],sel,48)
print(sorted(orig.items()))
print('plasma X5',confere(fotos,'/home/claude/game/assets/x/parts/Fourth_X5/plasma'))
