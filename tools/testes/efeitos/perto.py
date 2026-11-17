import sys; sys.path.insert(0,'/tmp/ex')
from motor import *
import collections
D=sys.argv[1]; f=int(sys.argv[2]); g=X5 if sys.argv[3]=='x5' else X6; k=int(sys.argv[4]); R=int(sys.argv[5]) if len(sys.argv)>5 else 48
r=open(f'{D}/r_{f}.bin','rb').read(); W=g['W']+k*g['WS']
bx=u16(r,g['BG']+0xA); by=u16(r,g['BG']+0xE); sx=u16(r,W+0xA)-bx; sy=u16(r,W+0xE)-by
print('obj',hex(r[W+1]),'pos',sx,sy)
c=collections.Counter()
for pr in prims_full(f'{D}/p_{f+1}.bin'):
    cx=sum(p[0] for p in pr['P'])/len(pr['P']); cy=sum(p[1] for p in pr['P'])/len(pr['P'])
    if abs(cx-((sx+32768)%65536-32768))<=R and abs(cy-sy)<=R: c[(pr['tpx'],pr['tpy'],hex(pr['clut']),len(pr['P']))]+=1
print(c.most_common())
