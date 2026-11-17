# gera mat_log.c (Linux: grava as chamadas) — funções de 1 argumento double/float e as de 2
F1D=['acos','asin','atan','cos','cosh','exp','exp2','log','log10','sin','sinh','tan','tanh']
F2D=['atan2','hypot','pow']
F1F=['acosf']
out=['#include <stdlib.h>','#include <stdio.h>','#include <string.h>','#include <stdint.h>','static FILE* lg;','static void L(int id, uint64_t a, uint64_t b, uint64_t r){ if(!lg){ const char* p=getenv("MATLOG"); lg=fopen(p?p:"/tmp/matlog.bin","ab"); } uint64_t v[4]={id,a,b,r}; fwrite(v,8,4,lg); }','#include <stdlib.h>']
def u(x,t): return f'({{ union{{ {t} f; uint64_t u; }} cv_; cv_.u=0; cv_.f=({x}); cv_.u; }})'
ids={}
for i,f in enumerate(F1D+F2D+F1F+['sincos_s','sincos_c','sincosf_s','sincosf_c']): ids[f]=i
for f in F1D:
    out.append(f'double __real_{f}(double); double __wrap_{f}(double x){{ double r=__real_{f}(x); L({ids[f]},{u("x","double")},0,{u("r","double")}); return r; }}')
for f in F2D:
    out.append(f'double __real_{f}(double,double); double __wrap_{f}(double x,double y){{ double r=__real_{f}(x,y); L({ids[f]},{u("x","double")},{u("y","double")},{u("r","double")}); return r; }}')
for f in F1F:
    out.append(f'float __real_{f}(float); float __wrap_{f}(float x){{ float r=__real_{f}(x); L({ids[f]},{u("x","float")},0,{u("r","float")}); return r; }}')
out.append(f'void __real_sincos(double,double*,double*); void __wrap_sincos(double x,double*s,double*c){{ __real_sincos(x,s,c); L({ids["sincos_s"]},{u("x","double")},0,{u("*s","double")}); L({ids["sincos_c"]},{u("x","double")},0,{u("*c","double")}); }}')
out.append(f'void __real_sincosf(float,float*,float*); void __wrap_sincosf(float x,float*s,float*c){{ __real_sincosf(x,s,c); L({ids["sincosf_s"]},{u("x","float")},0,{u("*s","float")}); L({ids["sincosf_c"]},{u("x","float")},0,{u("*c","float")}); }}')
open('/tmp/mat_log.c','w').write('\n'.join(out)+'\n')
print(','.join('--wrap='+f for f in F1D+F2D+F1F+['sincos','sincosf']))
import json; json.dump(ids,open('/tmp/mat_ids.json','w'))
