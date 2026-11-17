# gera tools/extrator/pecas/efeitos.json a partir das receitas conferidas (specs.py)
import sys, json; sys.path.insert(0,'/home/claude/work_ex')
from PIL import Image
from specs import *
AS='/home/claude/game/assets/'
out={'versao':1,'capturas':{},'selecoes':SEL,'atlas':{},'copias':COPIAS,'derivados':{}}
usadas=set()
for rel,fotos in ATL.items():
    im=Image.open(AS+rel+'/atlas.png')
    out['atlas'][rel]={'tam':[im.width,im.height],'fotos':[[f[0],f[1],f[2],f[3],f[4],f[5],f[6],f[7],f[8],f[9],f[10],f[11],f[12],f[14]] for f in fotos]}
    for f in fotos:
        assert not f[13], rel
        usadas.add(f[0])
for c in sorted(usadas):
    d=dict(CAP[c]); out['capturas'][c]={'jogo':d['jogo'],'armadura':d['arm'],'fase':d.get('fase','0001'),'extra':d.get('extra',''),'quadros':d['N']}
for rel,(tipo,base,pk,linhas) in DERIV.items():
    out['derivados'][rel]={'tipo':tipo,'de':base,'pacote':pk,'linhas':linhas}
out['selecoes']['roxo_giga']={'inc':[{'tpy':256,'tpx':[896],'clut':[0x7e50]}]}
# fundo roxo dos Gigas do X6 (6 objetos de efeito da Shadow): faixa de 64x240 da tela, x 40
out['faixas']=[{'saida':'zero/x6/giga/fundo.png','captura':'x6_a2_giga','quadro':2381,'sel':'roxo_giga','x':40,'y':0,'w':64,'h':240}]
json.dump(out,open('/home/claude/megaman-x-fangame/tools/extrator/pecas/efeitos.json','w'),separators=(',',':'))
print('atlas',len(out['atlas']),'capturas',len(out['capturas']),'fotos',sum(len(a['fotos']) for a in out['atlas'].values()))
