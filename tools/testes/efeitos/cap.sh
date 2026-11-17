#!/bin/bash
# uso: cap.sh pasta jogo armadura "botoes extra" N dump_de [poke extra]
d=$1; g=$2; arm=$3; extra=$4; N=$5; DF=$6; PX=$7
rm -rf $d; mkdir -p $d
if [ $g = x5 ]; then
  B="start:700-710,down:830-835,down:870-875,down:910-915,cross:960-966,cross:1210-1216"; for i in $(seq 1900 30 2600); do B="$B,cross:$i-$((i+3))"; done
  POKE="d1c0c:0001:1255-1600,d1c48:0${arm}00:1000-1800"; DISC="/home/claude/Mega Man X5 (USA).bin"
else
  B="start:900-905,cross:1000-1006,start:1400-1403,start:1460-1463"
  POKE="ccf2e:000${arm}:1010-$N,ccedc:${STAGE:-0001}:1440-1900"; DISC="/home/claude/Mega Man X6 (USA).bin"
fi
[ -n "$extra" ] && B="$B,$extra"
[ -n "$PX" ] && POKE="$POKE,$PX"
echo "$B" > $d/botoes.txt; echo "$POKE" > $d/poke.txt
DUMP=1 DUMP_FROM=$DF DUMPDIR=$d POKE="$POKE" timeout 900 /tmp/captura_bin/captura x /home/claude/megaman-x-fangame/tools/captura/openbios.bin "DISC=$DISC" $N "$B" > $d/log.txt 2>&1
echo "$d: $(ls $d | wc -l) arquivos"
