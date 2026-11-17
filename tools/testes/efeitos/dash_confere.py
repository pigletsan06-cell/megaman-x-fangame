# porte do build_dash.py: compara chaves de uma corrida com o atlas do dono
import numpy as np, json, os, sys
from PIL import Image
R='/tmp/rc/cap'
def st(d): return [list(map(int,l.split())) for l in open('%s/%s/estado.txt'%(R,d))]
def img(d,t): return np.asarray(Image.open('%s/%s/f%03d.ppm'%(R,d,t))).astype(int)
LAG=int(os.environ.get('LAG','2'))
def grab(run, key_of, op, ad):
    S=st(run+'0')
    for t in range(LAG, len(S)):
        s=S[t-LAG]
        if s[1]!=0x4A: continue
        key=key_of(S, t-LAG)
        if key is None or key in op: continue
        if not os.path.exists('%s/%s0/f%03d.ppm'%(R,run,t)): continue
        A=img(run+'0',t); B=img(run+'1',t); C=img(run+'2',t)
        sx=s[4]-s[6]; sy=s[5]-s[7]
        win=np.zeros(A.shape[:2],bool)
        y0,y1=max(0,sy-130),min(A.shape[0],sy+130); x0,x1=max(0,sx-150),min(A.shape[1],sx+150)
        win[y0:y1,x0:x1]=True
        win[0:135,0:50]=False
        mo=(np.abs(C-B).sum(2)>30)&win
        add=np.clip(A-C,0,255); ma=(np.abs(A-C).sum(2)>30)&win
        for store,m,col in ((op,mo,C),(ad,ma,add)):
            ys,xs=np.nonzero(m)
            if len(xs)==0: store[key]=None; continue
            bx0,by0,bx1,by1=xs.min(),ys.min(),xs.max()+1,ys.max()+1
            im=np.zeros((by1-by0,bx1-bx0,4),np.uint8)
            im[...,:3]=col[by0:by1,bx0:bx1]; im[...,3]=(m[by0:by1,bx0:bx1]*255)
            store[key]=(im, int(sx-bx0), int(sy-by0), t)
def phase_key(base_move):
    def f(S,i):
        s=S[i]
        if s[2]==0:
            j=i
            while j>0 and S[j-1][1]==0x4A and S[j-1][2]==0: j-=1
            return 500+min(i-j,19)
        j=i
        while j>0 and S[j-1][1]==0x4A and S[j-1][2]==1: j-=1
        return base_move+min(i-j,19)
    return f
G='/home/claude/game/assets/x/parts/Blade_X6'
def dono(d):
    A=np.array(Image.open(G+'/'+d+'/atlas.png').convert('RGBA')); F=json.load(open(G+'/'+d+'/frames.json'))['frames']; return A,F
if __name__=='__main__':
    run=sys.argv[1]; base=int(sys.argv[2])
    op={}; ad={}; grab(run, phase_key(base), op, ad)
    for nome,store in (('dash6',op),('dash6_add',ad)):
        A,F=dono(nome)
        for k in sorted(store):
            g=store[k]; f=F[k] if k<len(F) else None
            if g is None and f is None: continue
            if g is None or f is None: print(nome,k,'meu',None if g is None else g[0].shape,'dono',f); continue
            im,ox,oy,t=g; ref=A[f['y']:f['y']+f['h'], f['x']:f['x']+f['w']]
            s=f"{nome} {k} t{t} meu {im.shape[1]}x{im.shape[0]} ({ox},{oy}) dono {f['w']}x{f['h']} ({f['ox']},{f['oy']})"
            if im.shape==ref.shape: 
                # o atlas guarda RGB mesmo onde alfa=0? compara tudo
                s+=f" difpix {(im!=ref).any(-1).sum()}"
                if (im==ref).all(): s+=' IGUAL'
            print(s)
