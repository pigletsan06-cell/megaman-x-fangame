# Motor genérico de "fotos" de sprites a partir das capturas (igual aos grab*.py): é o que o extrator fará em GDScript
import sys, os, json, struct
import numpy as np
from PIL import Image
G=open('/home/claude/fusion/grab.py').read().split("if __name__")[0]
_ns={}
exec(G,_ns)
prims_full=_ns['prims_full']; raster_ns=_ns
def u16(r,a): return struct.unpack_from('<H',r,a)[0]
def sel_ok(pr,sel):
    # sel = {"inc":[regra...], "exc":[regra...]}; regra = {"tpy":..,"tpx":[..],"clut":[..],"clut_lt":..,"tpx_ge":..}
    def m(rule):
        if 'tpy' in rule and pr['tpy']!=rule['tpy']: return False
        if 'tpx' in rule and pr['tpx'] not in rule['tpx']: return False
        if 'clut' in rule and pr['clut'] not in rule['clut']: return False
        if 'clut_lt' in rule and not pr['clut']<rule['clut_lt']: return False
        if 'tpx_ge' in rule and not pr['tpx']>=rule['tpx_ge']: return False
        return True
    return any(m(x) for x in sel['inc']) and not any(m(x) for x in sel.get('exc',[]))
_cache={}
def foto(D,fi,fr,obj,bg,sel,BX,BY,C=200,clamp=False,espelho='obj',bo=True):
    r=open(f'{D}/r_{fr}.bin','rb').read()
    x=u16(r,obj+0xA); y=u16(r,obj+0xE)
    B=bg+(r[obj+0x14]*0x54 if bo else 0)
    sx=x-u16(r,B+0xA); sy=y-u16(r,B+0xE)
    k=(D,fi)
    if k not in _cache:
        _cache.clear()
        _cache[k]=(prims_full(f'{D}/p_{fi}.bin'),np.fromfile(f'{D}/v_{fi}.bin',dtype='<u2').reshape(512,1024))
    prs,v=_cache[k]
    raster_ns['CLAMP_UV']=clamp
    img=np.zeros((C,C,4),np.uint8); h=C//2
    for pr in prs:
        if not sel_ok(pr,sel): continue
        cx=sum(p[0] for p in pr['P'])/len(pr['P']); cy=sum(p[1] for p in pr['P'])/len(pr['P'])
        if abs(cx-sx)>BX or abs(cy-sy)>BY: continue
        raster_ns['raster'](img,v,pr,h-sx,h-sy)
    a=img[...,3]>0
    if not a.any(): return None
    ys,xs=np.nonzero(a); x0,x1,y0,y1=xs.min(),xs.max()+1,ys.min(),ys.max()+1
    crop=img[y0:y1,x0:x1]; ox=h-x0; oy=h-y0
    if espelho=='sempre' or (espelho=='obj' and r[obj+0x15]!=0):
        crop=np.ascontiguousarray(crop[:,::-1]); ox=crop.shape[1]-ox
    return crop,int(ox),int(oy)
def confere(fotos,REF):
    A=np.array(Image.open(REF+'/atlas.png').convert('RGBA')); F=json.load(open(REF+'/frames.json')); F=F['frames'] if isinstance(F,dict) else F
    ok=0; bad=[]; falta=[]
    for k,f in enumerate(F):
        if not f: continue
        ref=A[f['y']:f['y']+f['h'], f['x']:f['x']+f['w']]
        if not (ref[...,3]>0).any(): continue
        if k not in fotos or fotos[k] is None: falta.append(k); continue
        a,ox,oy=fotos[k]
        if a.shape==ref.shape and (a==ref).all() and (ox,oy)==(f['ox'],f['oy']): ok+=1
        else: bad.append(k)
    return ok,bad,falta
X5=dict(P=0x9A0A0,BG=0x9A1F8,W=0x98120,WS=0x9c); X6=dict(P=0x970A0,BG=0x971F8,W=0x950A0,WS=0xA0)
def varre_armas(D,f0,f1,G,ids,sel,box,C=240,clamp=False,chave='frame',filtro=None,BXY=None):
    # como o grabw.py: cada objeto do banco de tiros com o id pedido; chave = quadro do objeto (+64 por id)
    fotos={}; origem={}
    for f in range(f0,f1):
        try: r=open(f'{D}/r_{f}.bin','rb').read()
        except FileNotFoundError: continue
        if not os.path.exists(f'{D}/p_{f+1}.bin'): continue
        for k in range(32):
            W=G['W']+k*G['WS']
            if not (r[W]&1) or r[W+1] not in ids or r[W+4]==0: continue
            if filtro and not filtro(r,W): continue
            key=r[W+0x47] if chave=='frame' else (r[W+4]-1)*32+r[W+0x47]
            key+=64*ids.index(r[W+1])
            if key in fotos: continue
            bx,by=(box,box) if BXY is None else BXY
            g=foto(D,f+1,f,W,G['BG'],sel,bx,by,C=C,clamp=clamp,espelho='obj',bo=False)
            if g: fotos[key]=g; origem[key]=(f,k)
    return fotos,origem
