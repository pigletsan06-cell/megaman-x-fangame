import sys; sys.path.insert(0,'/tmp/ex')
from motor import *
from diag import diag
D='/tmp/ex/f5'; REF='/home/claude/game/assets/x/parts/Falcon_X5/shot'
sel={'inc':[{'tpy':0,'tpx':[320],'clut':[0x7802]}]}
fotos,orig=varre_armas(D,2836,2860,X5,[0x13],sel,24,clamp=True)
diag(fotos,REF)
