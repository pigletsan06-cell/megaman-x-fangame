import sys; sys.path.insert(0,'/tmp/ex')
from motor import *
def diag(fotos,REF,ks=None):
    A=np.array(Image.open(REF+'/atlas.png').convert('RGBA')); F=json.load(open(REF+'/frames.json')); F=F['frames'] if isinstance(F,dict) else F
    for k in (ks or sorted(fotos)):
        if k not in fotos or not F[k]: continue
        a,ox,oy=fotos[k]; f=F[k]; ref=A[f['y']:f['y']+f['h'], f['x']:f['x']+f['w']]
        info=f'{k}: meu {a.shape[:2]} o=({ox},{oy}) | dono {ref.shape[:2]} o=({f["ox"]},{f["oy"]})'
        if a.shape==ref.shape:
            info+=f' difs={(a!=ref).any(-1).sum()} espelho_igual={(a[:,::-1]==ref).all()}'
        print(info)
