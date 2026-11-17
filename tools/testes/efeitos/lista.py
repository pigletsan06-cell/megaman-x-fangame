import sys; sys.path.insert(0,'/tmp/ex')
from motor import *
import collections
D=sys.argv[1]; f=int(sys.argv[2]); g=sys.argv[3]; W0=X5 if g=='x5' else X6
r=open(f'{D}/r_{f}.bin','rb').read()
bx=u16(r,W0['BG']+0xA); by=u16(r,W0['BG']+0xE)
print('X', u16(r,W0['P']+0xA)-bx, u16(r,W0['P']+0xE)-by, 'estado',r[W0['P']+5],'quadro',r[W0['P']+0x47])
for k in range(32):
    W=W0['W']+k*W0['WS']
    if r[W]&1: print('arma',k,hex(r[W+1]),'est',r[W+4],'q',r[W+0x47],'pos',u16(r,W+0xA)-bx,u16(r,W+0xE)-by,'vira',r[W+0x15])
prs=prims_full(f'{D}/p_{f+1}.bin')
c=collections.Counter()
for pr in prs:
    cx=sum(p[0] for p in pr['P'])/len(pr['P']); cy=sum(p[1] for p in pr['P'])/len(pr['P'])
    c[(pr['tpx'],pr['tpy'],hex(pr['clut']))]+=1
print(c.most_common(30))
