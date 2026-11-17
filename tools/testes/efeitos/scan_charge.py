import os, sys
os.environ.setdefault('X','')
D=sys.argv[1]
src=open('/home/claude/fusion/grab2.py').read().split("OFF={")[0]
src=src.replace("D='/tmp/x5fly3'","D='%s'"%D)
exec(src.replace('>80 or abs(cy-sy)>80','>60 or abs(cy-sy)>60'))
import hashlib
sel=lambda pr: pr['tpy']==0 and pr['tpx'] in (384,448) and pr['clut']==0x7802
hs=[]
for f in range(2700,2900):
    g=render_sel(f,sel)
    h=hashlib.md5(np.array(g[0]).tobytes()+bytes([g[1],g[2]])).hexdigest()[:6] if g else '-'
    hs.append((f,h))
print(' '.join(f'{f}:{h}' for f,h in hs))
