# roda as capturas das receitas (só os quadros pedidos) e confere cada atlas inteiro com o do dono
import sys, os, json, subprocess, shutil; sys.path.insert(0,'/home/claude/work_ex'); sys.path.insert(0,'/tmp/ex')
import numpy as np
from PIL import Image
import motor
from specs import *
AS='/home/claude/game/assets/'
PRECISA={}
for _rel,_fotos in ATL.items():
    for ft in _fotos: PRECISA.setdefault(ft[0],set()).update([ft[2],ft[3]])
def captura(nome):
    c=CAP[nome]; d=f'/tmp/ex/cap_{nome}'
    if os.path.exists(d+'/ok'): return d
    shutil.rmtree(d,ignore_errors=True); os.makedirs(d)
    if c['jogo']=='x5':
        B="start:700-710,down:830-835,down:870-875,down:910-915,cross:960-966,cross:1210-1216"
        for i in range(1900,2601,30): B+=f",cross:{i}-{i+3}"
        POKE=f"d1c0c:0001:1255-1600,d1c48:0{c['arm']}00:1000-1800"; DISC="/home/claude/Mega Man X5 (USA).bin"
    else:
        B="start:900-905,cross:1000-1006,start:1400-1403,start:1460-1463"
        POKE=f"ccf2e:000{c['arm']}:1010-{c['N']},ccedc:{c.get('fase','0001')}:1440-1900"; DISC="/home/claude/Mega Man X6 (USA).bin"
    if c.get('extra'): B+=','+c['extra']
    if c.get('poke'): POKE+=','+c['poke']
    env=dict(os.environ,DUMPDIR=d,POKE=POKE,DUMP_LIST=','.join(str(q) for q in sorted(PRECISA[nome])))
    env.pop('NORAM',None); env.pop('DUMP',None)
    subprocess.run(['/tmp/captura_bin/captura','x','/home/claude/megaman-x-fangame/tools/captura/openbios.bin','DISC='+DISC,str(c['N']),B],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=900)
    open(d+'/ok','w').write('1'); return d
def monta(rel,fotos):
    REF=AS+rel; A=np.array(Image.open(REF+'/atlas.png').convert('RGBA')); Fj=json.load(open(REF+'/frames.json')); Fj=Fj['frames'] if isinstance(Fj,dict) else Fj
    out=np.zeros_like(A); prob=[]
    for cap,k,fi,fr,obj,bg,bo,sel,bx,by,C,clamp,esp,tira,extras in fotos:
        d=captura(cap)
        if extras: g=motor.foto_extra(d,fi,fr,obj,bg,SEL[sel],bx,by,C=C,clamp=bool(clamp),espelho=esp,bo=bool(bo),extras=extras)
        elif tira: g=motor.foto_camadas(d,fi,fr,obj,bg,SEL[sel],bx,by,C=C,clamp=bool(clamp),espelho=esp,bo=bool(bo),tira=tira)[1]
        else: g=motor.foto(d,fi,fr,obj,bg,SEL[sel],bx,by,C=C,clamp=bool(clamp),espelho=esp,bo=bool(bo))
        f=Fj[k]
        if g is None: prob.append((k,'vazio')); continue
        a,ox,oy=g
        if a.shape[:2]!=(f['h'],f['w']) or (ox,oy)!=(f['ox'],f['oy']): prob.append((k,'tamanho/origem')); continue
        sub=out[f['y']:f['y']+f['h'], f['x']:f['x']+f['w']]; m=a[...,3]>0; sub[m]=a[m]
    igual=(out==A).all()
    return igual,prob,int((out!=A).any(-1).sum())
sys.path.insert(0,'/tmp/parts')
def deriva(rel,spec,feitos):
    tipo,base,pk,linhas=spec
    from match import pkg_any, ent, pals
    A=feitos.get(base)
    if A is None: A=np.array(Image.open(AS+base+'/atlas.png').convert('RGBA'))
    P=pals(ent(pkg_any(pk[0],pk[1]),9))&0x7fff
    cores=set()
    for l in linhas:
        if isinstance(l,list): cores.add(int(P[l[0]][l[1]]))
        else: cores|=set(P[l][1:].tolist())
    c=(A[...,0].astype(np.int32)>>3)|((A[...,1].astype(np.int32)>>3)<<5)|((A[...,2].astype(np.int32)>>3)<<10)
    keep=(A[...,3]>0)&~np.isin(c,list(cores))
    out=np.where(keep[...,None],A,0).astype(np.uint8)
    R=np.array(Image.open(AS+rel+'/atlas.png').convert('RGBA'))
    return (out==R).all()
if __name__=='__main__':
    sel=sys.argv[1:] or list(ATL)+list(DERIV)
    for rel in sel:
        if rel in DERIV: print(rel,'IGUAL' if deriva(rel,DERIV[rel],{}) else 'DIFERENTE'); continue
        ig,prob,nd=monta(rel,ATL[rel])
        print(rel,'IGUAL' if ig else f'DIFERENTE ({nd} pontos) {prob[:6]}',flush=True)
