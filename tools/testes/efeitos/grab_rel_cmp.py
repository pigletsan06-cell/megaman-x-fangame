import os, sys, json
exec(open('/home/claude/fusion/grab.py').read().split("if __name__")[0])
import struct
def grab_rel(d,R0,X6=False):
    P=0x970A0 if X6 else 0x9A0A0; BG0=0x971F8 if X6 else 0x9A1F8; got={}
    for i,f in enumerate(range(R0,R0+10)):
        r=open(f'{d}/r_{f}.bin','rb').read()
        x=struct.unpack_from('<H',r,P+0xA)[0]; y=struct.unpack_from('<H',r,P+0xE)[0]; bo=r[P+0x14]; B=BG0+bo*0x54
        sx=x-struct.unpack_from('<H',r,B+0xA)[0]; sy=y-struct.unpack_from('<H',r,B+0xE)[0]
        v=np.fromfile(f'{d}/v_{f+1}.bin',dtype='<u2').reshape(512,1024)
        img=np.zeros((240,240,4),np.uint8)
        for pr in prims_full(f'{d}/p_{f+1}.bin'):
            if pr['tpy']!=0 or pr['tpx'] not in (640,960): continue
            cx=sum(p[0] for p in pr['P'])/len(pr['P']); cy=sum(p[1] for p in pr['P'])/len(pr['P'])
            if abs(cx-sx)>90 or abs(cy-sy)>90: continue
            raster(img,v,pr,120-sx,120-sy)
        a=img[...,3]>0
        if not a.any(): continue
        ys,xs=np.nonzero(a); x0,x1,y0,y1=xs.min(),xs.max()+1,ys.min(),ys.max()+1
        crop=img[y0:y1,x0:x1][:,::-1]; ox=120-x0; oy=120-y0; ox=crop.shape[1]-ox
        got[i]=(np.ascontiguousarray(crop),int(ox),int(oy),f)
    return got
def cmp(got,REF,n):
    A=np.array(Image.open(REF+'/atlas.png').convert('RGBA')); F=json.load(open(REF+'/frames.json'))['frames']
    res=[]
    for k in range(n):
        if k not in got: res.append('-'); continue
        a,ox,oy,f=got[k]; fr=F[k]; ref=A[fr['y']:fr['y']+fr['h'], fr['x']:fr['x']+fr['w']]
        res.append('ok' if a.shape==ref.shape and (a==ref).all() and (ox,oy)==(fr['ox'],fr['oy']) else 'x')
    return res
if __name__=='__main__':
    d=sys.argv[1]
    for R0 in range(int(sys.argv[2]),int(sys.argv[3])):
        r=cmp(grab_rel(d,R0),sys.argv[4],10); print(R0,' '.join(r))
