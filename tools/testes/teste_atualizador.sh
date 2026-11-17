#!/bin/bash
# Testa o atualizador do launcher com o GitHub de mentira. uso: teste_atualizador.sh [PACOTE]
# sem PACOTE: monta um pacote novo em /tmp/lt_upd (launcher sem .godot/, receita de teste, discos X4 X5 X6)
P=$1; G=${FUSION_GODOT:-/home/claude/godot/Godot_v4.7.2-stable_linux.x86_64}; PORTA=8765
REPO=$(cd "$(dirname $0)/../.." && pwd)
pgrep -x Xvfb >/dev/null || { setsid nohup Xvfb :99 -screen 0 1920x1080x24 >/dev/null 2>&1 & sleep 2; }
if [ -z "$P" ]; then
  P=/tmp/lt_upd; rm -rf $P; mkdir -p $P/discos $P/gerado $P/godot $P/tools/teste
  cp -r "$REPO/launcher" $P/launcher; rm -rf $P/launcher/.godot
  printf 'import sys, time\nn = int(sys.argv[2])\nfor i in range(n):\n    print(f"@progresso {i+1}/{n} item", flush=True); time.sleep(0.05)\n' > $P/tools/teste/passo.py
  echo '{"versao_receita":1,"etapas":[{"id":"arte","nome":"Arte","discos":["x4"],"cmd":["{python}","{tools}/teste/passo.py","arte","10"],"arquivos":["{tools}/teste/passo.py"]},{"id":"codigo","nome":"Codigo","discos":["x5","x6"],"cmd":["{python}","{tools}/teste/passo.py","cod","10"]},{"id":"importar","nome":"Importar","cmd":["{python}","{tools}/teste/passo.py","imp","5"],"depois_de":["arte","codigo"]}]}' > $P/tools/receita.json
  ln -s "${X4:-/home/claude/x4/Mega Man X4 (USA).bin}" "$P/discos/Mega Man X4 (USA).bin"
  ln -s "${X5:-/home/claude/x5/Mega Man X5 (USA).bin}" "$P/discos/Mega Man X5 (USA).bin"
  ln -s "${X6:-/home/claude/ext/MegaManX6Recomp/mmx6/Mega Man X6 (USA) (v1.1).bin}" "$P/discos/Mega Man X6 (USA) (v1.1).bin"
  echo "{\"versao\": 54, \"repo\": \"dono/repo\", \"api\": \"http://127.0.0.1:$PORTA\", \"token\": \"teste123\"}" > $P/versao.json
fi
: > /tmp/github_falso.log
roda() { DISPLAY=:99 FUSION_DISCOS="$P/discos" timeout 600 $G --path "$P/launcher" -- --auto --sem-jogo --atualizar "$@" >/tmp/launcher_saida.txt 2>&1; echo $?; }
rel() { python3 -c "import json;d=json.load(open('$P/gerado/relatorio_launcher.json'));print(d['ok'], d['atualizacao']['estado'], '|', ' '.join(e['id']+':'+e['estado'] for e in d['etapas']))"; }
servidor() { pkill -f github_falso.py; sleep 0.5; python3 "$(dirname $0)/github_falso.py" $PORTA "$1" /tmp/atualizacao_teste.zip "$2" & sleep 1; }
# a atualização de teste: versão 55, um script mudado e um arquivo para remover
rm -rf /tmp/upd && mkdir -p /tmp/upd/tools/teste /tmp/upd/godot
cp "$P/tools/teste/passo.py" /tmp/upd/tools/teste/ && echo "# mudou na 55" >> /tmp/upd/tools/teste/passo.py
python3 -c "import json;d=json.load(open('$P/versao.json'));d['versao']=55;json.dump(d,open('/tmp/upd/versao.json','w'))"
echo "godot/velho.txt" > /tmp/upd/remover.txt
(cd /tmp/upd && rm -f /tmp/atualizacao_teste.zip && zip -qr /tmp/atualizacao_teste.zip .)
echo "arquivo antigo" > "$P/godot/velho.txt"
echo "== 1) sem internet (servidor desligado)"; pkill -f github_falso.py; echo "saida: $(roda)"; rel
echo "== 2) chave errada"; servidor v55 outra_chave; echo "saida: $(roda)"; rel
echo "== 3) versão 55 disponível -> baixa, aplica e refaz só o que mudou"; servidor v55 teste123; echo "saida: $(roda)"; rel
python3 -c "import json;print('versao.json agora:', json.load(open('$P/versao.json'))['versao'])"
[ -f "$P/godot/velho.txt" ] && echo "FALHA: velho.txt não foi removido" || echo "ok: velho.txt removido"
grep -c "mudou na 55" "$P/tools/teste/passo.py" | sed 's/^/linhas novas no script: /'
grep "== \|ok: " "$P/gerado/launcher.log" | tail -8
echo "== 4) já na 55 -> nada para fazer"; echo "saida: $(roda)"; rel
pkill -f github_falso.py
echo "== pedidos que o servidor recebeu:"; tail -12 /tmp/github_falso.log
