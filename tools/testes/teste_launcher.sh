#!/bin/bash
# Casos de borda do launcher, cada um numa pasta nova (sem .godot/, como chega no PC do amigo).
# uso: tools/testes/teste_launcher.sh      precisa dos 3 discos (variáveis X4 X5 X6) e do Godot (FUSION_GODOT)
G=${FUSION_GODOT:-/home/claude/godot/Godot_v4.7.2-stable_linux.x86_64}
REPO=$(cd "$(dirname $0)/../.." && pwd)
X4="${X4:-/home/claude/x4/Mega Man X4 (USA).bin}"; X5="${X5:-/home/claude/x5/Mega Man X5 (USA).bin}"
X6="${X6:-/home/claude/ext/MegaManX6Recomp/mmx6/Mega Man X6 (USA) (v1.1).bin}"
pgrep -x Xvfb >/dev/null || { setsid nohup Xvfb :99 -screen 0 1920x1080x24 >/dev/null 2>&1 & sleep 2; }
FALHAS=0
pacote() {   # pacote PASTA RECEITA
  P="$1"; rm -rf "$P"; mkdir -p "$P/discos" "$P/gerado" "$P/tools/teste"
  cp -r "$REPO/launcher" "$P/launcher"; rm -rf "$P/launcher/.godot"
  cp -r "$REPO/tools/extrator" "$P/tools/extrator"
  cat > "$P/tools/teste/passo.py" <<'PY'
import sys, time
n = int(sys.argv[2]); falha = len(sys.argv) > 3 and sys.argv[3] == "falha"
for i in range(n):
    print(f"@progresso {i+1}/{n} item {i+1}", flush=True); time.sleep(0.05)
    if falha and i == n // 2: print("deu ruim de propósito", file=sys.stderr, flush=True); sys.exit(3)
print("terminou", sys.argv[1], flush=True)
PY
  ln -s "$X4" "$P/discos/Mega Man X4 (USA).bin"; ln -s "$X5" "$P/discos/Mega Man X5 (USA).bin"; ln -s "$X6" "$P/discos/Mega Man X6 (USA) (v1.1).bin"
  echo "$2" > "$P/tools/receita.json"; echo '{"versao": 54}' > "$P/versao.json"
}
roda() {   # roda [args...] -> código de saída do launcher
  DISPLAY=:99 FUSION_DISCOS="$P/discos" timeout 300 "$G" --path "$P/launcher" -- --auto --sem-jogo "$@" > "$P/saida.txt" 2>&1
  local c=$?; grep -q "SCRIPT ERROR" "$P/saida.txt" && { echo "  !! SCRIPT ERROR:"; grep -A1 "SCRIPT ERROR" "$P/saida.txt" | head -4; }
  [ $c = 124 ] && echo "  !! travou (timeout)"; return $c
}
confere() {   # confere DESCRIÇÃO EXPRESSÃO_PYTHON (d = relatório)
  if python3 -c "import json,sys;d=json.load(open('$P/gerado/relatorio_launcher.json'));e={x['id']:x['estado'] for x in d['etapas']};s={k:v['estado'] for k,v in d['discos'].items()};sys.exit(0 if ($2) else 1)" 2>/dev/null
  then echo "  ok   $1"; else echo "  FALHOU $1"; FALHAS=$((FALHAS+1)); fi
}
mostra() { python3 -c "
import json;d=json.load(open('$P/gerado/relatorio_launcher.json'))
print('       msg:', d['mensagem'][:100])
print('       discos:', ' '.join(k+'='+v['estado'] for k,v in d['discos'].items()), '| etapas:', ' '.join(e['id']+'='+e['estado'] for e in d['etapas']))"; }
R='{"versao_receita":1,"etapas":[{"id":"a","nome":"Etapa A","discos":["x4"],"cmd":["{python}","{tools}/teste/passo.py","a","10"],"arquivos":["{tools}/teste/passo.py"]},{"id":"b","nome":"Etapa B","discos":["x5","x6"],"cmd":["{python}","{tools}/teste/passo.py","b","10","XX"]},{"id":"c","nome":"Etapa C","cmd":["{python}","{tools}/teste/passo.py","c","10"],"depois_de":["a","b"]}]}'
T0=$(date +%s)

echo "== 1) pasta nova, tudo certo (pasta com espaço e acento)"
pacote "/tmp/lt teste/Área de Trabalho/jogo" "$R"; roda; echo "  saída $?"; mostra
confere "3 discos ok" "all(v=='ok' for v in s.values())"; confere "3 etapas feitas" "list(e.values())==['feita']*3"; confere "ok=true" "d['ok']"

echo "== 2) falta o disco do X6"
pacote /tmp/lt_2 "$R"; rm "$P/discos/Mega Man X6 (USA) (v1.1).bin"; roda; echo "  saída $?"; mostra
confere "X6 faltando, X4/X5 ok" "s['x6']=='faltando' and s['x4']=='ok' and s['x5']=='ok'"; confere "não rodou nada" "all(v=='pendente' for v in e.values())"; confere "ok=false" "not d['ok']"

echo "== 3) arquivo com o nome do X6 mas outro conteúdo"
pacote /tmp/lt_3 "$R"; rm "$P/discos/Mega Man X6 (USA) (v1.1).bin"; truncate -s 599985792 "$P/discos/Mega Man X6 (USA) (v1.1).bin"; roda; echo "  saída $?"; mostra
confere "X6 diferente" "s['x6']=='diferente'"; confere "não rodou nada" "all(v=='pendente' for v in e.values())"

echo "== 4) disco do X5 com outro nome (acha pelo tamanho + SHA-1)"
pacote /tmp/lt_4 "$R"; mv "$P/discos/Mega Man X5 (USA).bin" "$P/discos/meu x5 backup.bin"; roda; echo "  saída $?"; mostra
confere "X5 ok" "s['x5']=='ok' and d['discos']['x5']['caminho'].endswith('meu x5 backup.bin')"; confere "etapas feitas" "list(e.values())==['feita']*3"

echo "== 5) etapa B falha no meio"
pacote /tmp/lt_5 "$(echo "$R" | sed 's/"XX"/"falha"/')"; roda; echo "  saída $?"; mostra
confere "A feita, B erro, C pendente" "e=={'a':'feita','b':'erro','c':'pendente'}"; confere "ok=false" "not d['ok']"
grep -q "deu ruim de propósito" "$P/gerado/launcher.log" && echo "  ok   erro da etapa aparece no log" || { echo "  FALHOU erro no log"; FALHAS=$((FALHAS+1)); }

echo "== 6) consertou a B e abriu de novo: A não repete, B e C rodam"
sed -i 's/"falha"/"ok"/' "$P/tools/receita.json"; N0=$(wc -l < "$P/gerado/launcher.log"); roda; echo "  saída $?"; mostra
confere "tudo feito" "list(e.values())==['feita']*3"
RODOU=$(tail -n +$((N0+1)) "$P/gerado/launcher.log" | grep "== " | sed 's/.*== //' | tr '\n' ',' ); echo "       rodou agora: $RODOU"
[[ "$RODOU" != *"Etapa A"* && "$RODOU" == *"Etapa B"* && "$RODOU" == *"Etapa C"* ]] && echo "  ok   só B e C rodaram" || { echo "  FALHOU quais etapas rodaram"; FALHAS=$((FALHAS+1)); }

echo "== 7) abriu de novo sem mudar nada: não roda nada"
N0=$(wc -l < "$P/gerado/launcher.log"); roda; echo "  saída $?"
RODOU=$(tail -n +$((N0+1)) "$P/gerado/launcher.log" | grep -c "== "); [ "$RODOU" = 0 ] && echo "  ok   nenhuma etapa rodou" || { echo "  FALHOU rodou $RODOU etapas"; FALHAS=$((FALHAS+1)); }
confere "ok=true" "d['ok']"

echo "== 8) apagaram um arquivo de uma etapa (passo.py mudou): A e C refazem"
echo "# mexi" >> "$P/tools/teste/passo.py"; N0=$(wc -l < "$P/gerado/launcher.log"); roda; echo "  saída $?"
RODOU=$(tail -n +$((N0+1)) "$P/gerado/launcher.log" | grep "== " | sed 's/.*== //' | tr '\n' ','); echo "       rodou agora: $RODOU"
[[ "$RODOU" == *"Etapa A"* && "$RODOU" != *"Etapa B"* && "$RODOU" == *"Etapa C"* ]] && echo "  ok   A e C refeitas, B não" || { echo "  FALHOU"; FALHAS=$((FALHAS+1)); }

echo "== 9) gerado/estado.json corrompido: recomeça sem travar"
echo "{lixo" > "$P/gerado/estado.json"; roda; echo "  saída $?"; mostra; confere "tudo feito de novo" "list(e.values())==['feita']*3"

echo "== 10) receita.json quebrada: avisa e não trava"
pacote /tmp/lt_10 '{"etapas": [ {"id": '; roda; echo "  saída $?"; mostra; confere "ok=false com mensagem" "not d['ok'] and 'receita' in d['mensagem'].lower()"

echo "== 11) disco trocado depois de preparar (SHA-1 em cache não engana: mudou a data/tamanho, confere de novo)"
pacote /tmp/lt_11 "$R"; roda >/dev/null; rm "$P/discos/Mega Man X4 (USA).bin"; truncate -s 592217136 "$P/discos/Mega Man X4 (USA).bin"; roda; echo "  saída $?"; mostra
confere "X4 diferente agora" "s['x4']=='diferente'"; confere "ok=false" "not d['ok']"

echo "== FIM: $FALHAS falha(s), $(( $(date +%s) - T0 ))s"
