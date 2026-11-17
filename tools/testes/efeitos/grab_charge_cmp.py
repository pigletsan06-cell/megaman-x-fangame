import os, sys, json
D=sys.argv[1]; S0=int(sys.argv[2]); F0=int(sys.argv[3]); REF=sys.argv[4]
src=open('/home/claude/fusion/grab2.py').read().split("OFF={")[0].replace("D='/tmp/x5fly3'","D='%s'"%D)
exec(src.replace('>80 or abs(cy-sy)>80','>60 or abs(cy-sy)>60'))
sel=lambda pr: pr['tpy']==0 and pr['tpx'] in (384,448) and pr['clut']==0x7802
FX={}
for f in range(S0,F0+25):
    ph=(f-S0)%10; full=f>=F0
    k=ph+(10 if full else 0)
    if k in FX: continue
    g=render_sel(f,sel)
    if g: FX[k]=g
A=np.array(Image.open(REF+'/atlas.png').convert('RGBA')); F=json.load(open(REF+'/frames.json'))['frames']
res=[]
for k in range(20):
    if k not in FX: res.append('-'); continue
    im,ox,oy,f=FX[k]; a=np.array(im); fr=F[k]
    ref=A[fr['y']:fr['y']+fr['h'], fr['x']:fr['x']+fr['w']]
    res.append('ok' if a.shape==ref.shape and (a==ref).all() and (ox,oy)==(fr['ox'],fr['oy']) else 'x')
print(S0,F0,' '.join(res))
