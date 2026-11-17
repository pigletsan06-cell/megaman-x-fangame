# Gera tabelas/lanczos_DE_PARA.json: os pesos inteiros do redimensionamento LANCZOS do Pillow (ImagingResample,
# 8 bits por canal, 22 bits de precisão). Com os pesos guardados a conta no extrator é só de inteiros (igual em
# qualquer PC). uso: python3 gera_lanczos.py SAIDA.json [DE PARA]  (o teste no fim confere com o Pillow)
import math, json, sys
import numpy as np
PREC=22
def sinc(x):
    if x==0.0: return 1.0
    x=x*math.pi; return math.sin(x)/x
def lanczos(x):
    if -3.0<=x<3.0: return sinc(x)*sinc(x/3)
    return 0.0
def coefs(inSize,outSize):
    scale=inSize/outSize; filterscale=max(scale,1.0); support=3.0*filterscale
    ksize=int(math.ceil(support))*2+1
    out=[]
    for xx in range(outSize):
        center=(xx+0.5)*scale; ww=0.0; ss=1.0/filterscale
        xmin=int(center-support+0.5)
        if xmin<0: xmin=0
        xmax=int(center+support+0.5)
        if xmax>inSize: xmax=inSize
        xmax-=xmin
        k=[]
        for x in range(xmax):
            w=lanczos((x+xmin-center+0.5)*ss); k.append(w); ww+=w
        k=[(v/ww if ww!=0.0 else v) for v in k]
        ki=[(int(-0.5+v*(1<<PREC)) if v<0 else int(0.5+v*(1<<PREC))) for v in k]
        out.append([xmin,ki])
    return out
def aplica_h(img,co):
    H,W,_=img.shape; out=np.zeros((H,len(co),3),np.uint8)
    for xx,(xmin,k) in enumerate(co):
        s=np.full((H,3),1<<(PREC-1),np.int64)
        for j,kv in enumerate(k): s+=img[:,xmin+j,:].astype(np.int64)*kv
        s=np.where(s>=(1<<PREC<<8),255<<PREC,s); s=np.where(s<=0,0,s)
        out[:,xx,:]=(s>>PREC).astype(np.uint8)
    return out
if __name__=='__main__':
    from PIL import Image
    de=int(sys.argv[2]) if len(sys.argv)>2 else 512; para=int(sys.argv[3]) if len(sys.argv)>3 else 320
    co=coefs(de,para)
    teste=np.random.RandomState(1).randint(0,256,(40,de,3)).astype(np.uint8)   # confere com o Pillow
    assert (aplica_h(teste,co)==np.array(Image.fromarray(teste).resize((para,40),Image.LANCZOS))).all()
    json.dump({"nota":"Coeficientes do LANCZOS do Pillow (ImagingResample, 8 bits: 22 bits de precisão) de %d para %d pontos na horizontal: [primeira coluna, [pesos]] por coluna de saída (tabelas/gera_lanczos.py)." % (de,para),"de":de,"para":para,"precisao":PREC,"colunas":co},open(sys.argv[1],'w'),separators=(',',':'))
