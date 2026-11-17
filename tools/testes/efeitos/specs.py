# Receitas das capturas dos efeitos das armaduras.
# foto = [captura, chave, quadro_foto, quadro_ram, objeto, câmera, usa_banco_da_câmera, seleção, janela_x, janela_y, tela,
#         clamp, espelho, tirar_paletas]
SEL={
 'carga':{'inc':[{'tpy':0,'tpx':[384,448],'clut':[0x7802]}]},
 'soltura':{'inc':[{'tpy':0,'tpx':[640,960]}]},
 'plasma':{'inc':[{'tpy':0,'tpx':[896],'clut':[0x7802,0x7803]}]},
 'lanca':{'inc':[{'tpy':0,'tpx':[320],'clut':[0x7802]}]},
 'gaea_tiro':{'inc':[{'tpy':0,'tpx':[320],'clut':[0x7844]}]},
 'blade_expl':{'inc':[{'tpy':0,'tpx':[960,768],'clut':[0x784a]},{'tpy':0,'tpx':[320,448],'clut':[0x7803]}]},
 'shadow_tiro':{'inc':[{'tpy':0,'tpx':[320],'clut':[0x7849]}]},
 'corpo5':{'inc':[{'tpy':0,'tpx':[320],'clut':[0x7800,0x7802,0x7843]}]},
 'jato5':{'inc':[{'tpy':0,'tpx':[960],'clut':[0x7802]}]},
 'corpo6':{'inc':[{'tpy':0,'tpx':[320],'clut':[0x7800,0x7843]}]},
 'voo6':{'inc':[{'tpy':0,'tpx':[320],'clut':[0x7800,0x7802,0x7843,0x780d,0x780e,0x780f]},{'tpy':0,'tpx':[384,960],'clut':[0x7802]}]},
 'fx6':{'inc':[{'tpy':0,'clut_lt':0x7880}],'exc':[{'tpx':[320],'clut':[0x7800,0x7843,0x7841,0x7802]},{'tpx':[768],'clut':[0x7805]},{'tpx':[384],'clut':[0x7841]}]},
 'dash6c':{'inc':[{'tpy':0,'tpx_ge':320,'clut_lt':0x7880}],'exc':[{'clut':[0x7841]},{'tpx':[768],'clut':[0x7805]}]},
 'fx_blade':{'inc':[{'tpy':0,'clut_lt':0x7880,'tpx':[320,384,448,512,576,640,704,768,832,896,960]}],'exc':[{'tpx':[320],'clut':[0x7800,0x7843,0x7841]},{'tpx':[768],'clut':[0x7805]},{'tpx':[384],'clut':[0x7841]}]},
 'gaea_onda':{'inc':[{'tpy':0,'tpx':[320],'clut':[0x7844]}]},
}
P5,BG5,W5,WS5=0x9A0A0,0x9A1F8,0x98120,0x9c
P6,BG6,W6,WS6=0x970A0,0x971F8,0x950A0,0xA0
CORPO=[0x7800,0x7843]
CAP={
 'x5_a1_carga':dict(jogo='x5',arm=1,extra='square:2700-2830',N=2900),
 'x6_a4_carga_esq':dict(jogo='x6',arm=4,extra='left:2280-2282,square:2300-2420',N=2520),
 'x5_a2_carga':dict(jogo='x5',arm=2,extra='square:2700-2830',N=2900),
 'x5_a3_tiros':dict(jogo='x5',arm=3,extra='square:2700-2702,square:2745-2875',N=2985),
 'x6_a1_carga':dict(jogo='x6',arm=1,extra='square:2300-2420',N=2470),
 'x6_a2_tiros':dict(jogo='x6',arm=2,extra='square:2300-2302,square:2330-2450',N=2520),
 'x6_a3_tiros':dict(jogo='x6',arm=3,extra='square:2300-2302,square:2330-2450',N=2560),
 'x5_a2_giga':dict(jogo='x5',arm=2,extra='b9:2700-2703',N=2920),
 'x5_a2_giga_ar':dict(jogo='x5',arm=2,extra='cross:2700-2703,b9:2708-2711',N=2790),
 'x5_a3_giga':dict(jogo='x5',arm=3,extra='b9:2700-2703',N=2925),
 'x5_a4_nova':dict(jogo='x5',arm=4,extra='b9:2700-2703',N=2790),
 'x6_a4_nova':dict(jogo='x6',arm=4,extra='b9:2300-2303',N=2400),
 'x6_a1_voo':dict(jogo='x6',arm=1,extra='cross:2300-2303,circle:2310-2312',N=2345),
 'x6_a1_giga':dict(jogo='x6',arm=1,extra='b9:2300-2303',N=2500),
 'x6_a2_carga':dict(jogo='x6',arm=2,extra='square:2300-2420',N=2470),
 'x6_a2_carga_ar':dict(jogo='x6',arm=2,extra='square:2300-2428,cross:2420-2440',N=2470),
 'x6_a2_teto':dict(jogo='x6',arm=2,fase='0004',extra='up:2299-2330,cross:2300-2320',N=2330),
 'x6_a2_teto2':dict(jogo='x6',arm=2,fase='0004',extra='up:2299-2330,cross:2300-2320,square:2340-2342,square:2350-2470,circle:2480-2490',N=2560),
 'x6_a2_giga':dict(jogo='x6',arm=2,extra='b9:2300-2303',N=2530),
 'x6_a3_giga':dict(jogo='x6',arm=3,extra='b9:2300-2303',N=2420),
 'x6_a3_dash_frente':dict(jogo='x6',arm=3,extra='cross:2300-2303,circle:2310-2325',N=2345),
 'x6_a3_dash_cima':dict(jogo='x6',arm=3,extra='cross:2300-2308,up:2304-2360,circle:2306-2315',N=2345),
 'x6_a3_dash_baixo':dict(jogo='x6',arm=3,extra='cross:2300-2308,down:2304-2360,circle:2306-2315',N=2345),
 'x5_a2_voo':dict(jogo='x5',arm=2,extra='cross:2700-2705,cross:2712-2716,right:2740-2770,left:2772-2774,up:2785-2805,down:2815-2835',N=2900),
}
ATL={}
def F(cap,k,fi,fr,obj,bg,bo,sel,bx,by,C=200,clamp=0,esp='obj',tira=(),extras=()): return [cap,k,fi,fr,obj,bg,bo,sel,bx,by,C,clamp,esp,list(tira),[list(e) for e in extras]]
def carga_fotos(S0):
    F0=S0+70; out={}
    for f in range(S0,F0+25):
        k=(f-S0)%10+(10 if f>=F0 else 0)
        if k not in out: out[k]=F('x5_a1_carga',k,f,f-1,P5,BG5,1,'carga',60,60)
    return [out[k] for k in sorted(out)]
ATL['x/parts/Fourth_X5/charge_fx']=carga_fotos(2727)
ATL['x/parts/Falcon_X5/charge_release']=[F('x5_a1_carga',i,2832+i+1,2832+i,P5,BG5,1,'soltura',90,90,240,0,'sempre') for i in range(10)]
ATL['x/parts/Fourth_X5/plasma']=[F('x5_a1_carga',15+i,2839+3*i+1,2839+3*i,W5,BG5,0,'plasma',48,48,240) for i in range(4)]
ATL['x/parts/Ultimate_X6/plasma']=[F('x6_a4_carga_esq',15+i,2429+3*i+1,2429+3*i,W6,BG6,0,'plasma',48,48,240,1) for i in range(4)]
ATL['x/parts/Falcon_X5/shot']=[F('x5_a2_carga',i,2839+3*i+1,2839+3*i,W5,BG5,0,'lanca',24,24,240) for i in range(4)]
_g=[(0,2701),(1,2705),(2,2709),(20,2713),(21,2717),(22,2721),(23,2725),(32,2884),(33,2888),(34,2892),(52,2896),(53,2901),(54,2906),(55,2911)]
ATL['x/parts/Gaea_X5/shot']=[F('x5_a3_tiros',k,f+1,f,W5,BG5,0,'gaea_tiro',48,48) for k,f in _g]
ATL['x/parts/Falcon_X6/shot']=[F('x6_a1_carga',i,2429+3*i+1,2429+3*i,W6,BG6,0,'lanca',24,24,240) for i in range(3)]
_s=[(0,2301),(2,2302),(4,2303),(6,2304),(8,2305)]+[(10+i,2306+i) for i in range(8)]
ATL['x/parts/Shadow_X6/shot']=[F('x6_a2_tiros',k,f+1,f,W6,BG6,0,'shadow_tiro',24,24,240) for k,f in _s]
ATL['x/parts/Blade_X6/shot']=[F('x6_a3_tiros',i,f+1,f,W6,BG6,0,'blade_expl',48,48,240) for i,f in ((0,2452),(1,2454),(2,2458))]+[F('x6_a3_tiros',10+t,2462+t+1,2462,W6,BG6,0,'blade_expl',50,50,240,0,'sempre') for t in range(14)]
_l=[(4,2774,1),(5,2777,1),(6,2769,1),(7,2771,1),(8,2769,0),(9,2762,0),(10,2763,0),(11,2766,0)]
ATL['x/parts/Falcon_X5/giga_laser']=[F('x5_a2_giga',k,f+1,f,W5+s*WS5,BG5,0,'lanca',12,40,200,0,'nunca') for k,f,s in _l]
# voo da Falcon do X5 (X + jato), poses do Giga no chão e no ar; rastro = o mesmo quadro sem os pontos do X
_v={47: 2714, 48: 2716, 49: 2718, 50: 2720, 51: 2722, 52: 2724, 53: 2727, 54: 2729, 55: 2731, 56: 2790, 57: 2792, 58: 2795, 59: 2797, 60: 2787, 61: 2820, 62: 2822, 63: 2825, 64: 2827, 65: 2817, 151: 2722, 152: 2724, 153: 2727, 154: 2729, 155: 2731}
_gc={66: 2702, 68: 2705, 70: 2707, 72: 2757, 73: 2759}; _ga={67: 2710, 69: 2713, 71: 2715}
def voo5(tira=()):
    out=[F('x5_a2_voo',k,f,f-1,P5,BG5,1,'corpo5',80,80,tira=tira) for k,f in sorted(_v.items())]
    out+=[F('x5_a2_giga',k,f,f-1,P5,BG5,1,'corpo5',40,45,tira=tira) for k,f in sorted(_gc.items())]
    out+=[F('x5_a2_giga_ar',k,f,f-1,P5,BG5,1,'corpo5',40,45,tira=tira) for k,f in sorted(_ga.items())]
    return out
ATL['x/parts/Falcon_X5/flight']=voo5()
_j={0: 2724, 1: 2724, 2: 2785, 3: 2727, 4: 2727, 5: 2774, 6: 2730, 7: 2730, 8: 2776, 9: 2733, 10: 2733, 11: 2779, 12: 2722, 13: 2722, 14: 2782, 15: 2724, 16: 2724, 18: 2727, 19: 2727, 21: 2730, 22: 2730, 24: 2733, 25: 2733, 27: 2722, 28: 2722, 30: 2787, 31: 2787, 33: 2789, 34: 2789, 36: 2792, 37: 2792, 39: 2795, 40: 2795, 42: 2798, 43: 2798, 45: 2817, 46: 2817, 48: 2819, 49: 2819, 51: 2822, 52: 2822, 54: 2825, 55: 2825, 57: 2828, 58: 2828}
ATL['x/parts/Falcon_X5/flight_fx']=[F('x5_a2_voo',k,f,f-1,P5,BG5,1,'jato5',80,80) for k,f in sorted(_j.items())]
import json as _json, os as _os
def mapa(n): return {int(k):v for k,v in _json.load(open(_os.path.join(_os.path.dirname(__file__),'mapas',n+'.json'))).items()}
ATL['x/parts/Gaea_X5/flight']=[F('x5_a3_giga',k,f,f-1,P5,BG5,1,'corpo5',45,45) for k,f in sorted(mapa('gaea5_voo').items())]
ATL['x/parts/Gaea_X5/giga_fx']=[F('x5_a3_giga',k,f,f-1,P5,BG5,1,'gaea_onda',95,95) for k,f in sorted(mapa('gaea5_giga').items())]
ATL['x/parts/Ultimate_X5/flight']=[F('x5_a4_nova',k,f,f-1,P5,BG5,1,'corpo5',75,60) for k,f in sorted(mapa('ult5_voo').items())]
ATL['x/parts/Ultimate_X6/flight']=[F('x6_a4_nova',k,f,f-1,P6,BG6,1,'corpo6',70,60,500,1) for k,f in sorted(mapa('ult6_voo').items())]
_f6=_json.load(open(_os.path.join(_os.path.dirname(__file__),'mapas','falcon6.json')))
def voo6(tira=()):
    out=[F('x6_a1_giga',int(k),f,f-1,P6,BG6,1,'corpo5',40,45,tira=tira) for k,f in sorted(_f6['giga'].items(),key=lambda t:int(t[0]))]
    out+=[F('x6_a1_voo',int(k),f,f-1,P6,BG6,1,'voo6',220,60,500,tira=tira) for k,f in sorted(_f6['voo'].items(),key=lambda t:int(t[0]))]
    return out
ATL['x/parts/Falcon_X6/flight']=voo6()
_l6=[(4,2389,1),(5,2392,1),(6,2384,1),(8,2385,0),(9,2378,0),(10,2379,0),(11,2382,0)]
ATL['x/parts/Falcon_X6/giga_laser']=[F('x6_a1_giga',k,f+1,f,W6+s*WS6,BG6,0,'lanca',12,40,200,0,'nunca') for k,f,s in _l6]+[F('x6_a1_giga',7,2387,2386,W6+1*WS6,BG6,0,'lanca',16,40,200,0,'nunca',extras=[(W6+0*WS6,16,-28,12,40)])]
_sv=_json.load(open(_os.path.join(_os.path.dirname(__file__),'mapas','shadow6_voo.json')))
ATL['x/parts/Shadow_X6/flight']=[F(cap,int(k),f,f-1,P6,BG6,1,'corpo6',60,60,500,1) for cap,mp in _sv.items() for k,f in sorted(mp.items(),key=lambda t:int(t[0]))]
_sc=_json.load(open(_os.path.join(_os.path.dirname(__file__),'mapas','shadow6_corte.json')))
ATL['x/parts/Shadow_X6/giga_fx']=[F('x6_a2_giga',k,f,f-1,P6,BG6,1,'fx6',160,120,500,1) for k,f in sorted(mapa('shadow6_giga').items())]+[F('x6_a2_carga' if v[0].endswith('se1') else 'x6_a2_carga_ar',int(k),v[1],v[1]-1,P6,BG6,1,'fx6',160,120,500,1) for k,v in sorted(_sc.items(),key=lambda t:int(t[0]))]
_b6=_json.load(open(_os.path.join(_os.path.dirname(__file__),'mapas','blade6.json')))
_bd={**{400+i:2312 for i in range(6)},**{406+i:2318 for i in range(9)},**{420+t:2328+t for t in range(15)}}
ATL['x/parts/Blade_X6/flight']=([F('x6_a3_giga',int(k),f,f-1,P6,BG6,1,'corpo5',45,50,500) for k,f in sorted(_b6['giga_x'].items(),key=lambda t:int(t[0]))]
  +[F('x6_a3_tiros',int(k),f,f-1,P6,BG6,1,'corpo5',45,50,500) for k,f in sorted(_b6['tiro_x'].items(),key=lambda t:int(t[0]))]
  +[F('x6_a3_dash_frente',k,f,f-1,P6,BG6,1,'dash6c',220,70,500) for k,f in sorted(_bd.items())]
  +[F('x6_a3_dash_cima',440+t,2318+t,2317+t,P6,BG6,1,'dash6c',220,70,500) for t in range(10)]
  +[F('x6_a3_dash_baixo',460+t,2318+t,2317+t,P6,BG6,1,'dash6c',220,70,500) for t in range(5)])
ATL['x/parts/Blade_X6/giga_fx']=[F('x6_a3_giga',int(k),f,f-1,P6,BG6,1,'fx_blade',200,90,500) for k,f in sorted(_b6['giga_fx'].items(),key=lambda t:int(t[0]))]
# rastro = o atlas do voo sem os pontos com as cores das paletas do corpo e da armadura (banco 0 e 1 do pacote)
DERIV={'x/parts/Falcon_X5/flight_trail':('rastro_cor','x/parts/Falcon_X5/flight',['x5',94],[0,1]),
 'x/parts/Falcon_X6/flight_trail':('rastro_cor','x/parts/Falcon_X6/flight',['x6',87],[0,1]),
 'x/parts/Shadow_X6/flight_trail':('rastro_cor','x/parts/Shadow_X6/flight',['x6',88],[0,1]),
 'x/parts/Blade_X6/flight_trail':('rastro_cor','x/parts/Blade_X6/flight',['x6',89],[0,1,[2,8],[2,12]])}
COPIAS={
 'x/parts/Fourth_X5/charge_fx':['x/parts/%s/charge_fx'%a for a in ('Blade_X6','Falcon_X5','Falcon_X6','Gaea_X5','Shadow_X6','Ultimate_X5','Ultimate_X6')],
 'x/parts/Falcon_X5/charge_release':['x/parts/%s/charge_release'%a for a in ('Falcon_X6','Fourth_X5','Gaea_X5','Ultimate_X5')],
 'x/parts/Fourth_X5/plasma':['x/parts/Ultimate_X5/plasma'],
}
