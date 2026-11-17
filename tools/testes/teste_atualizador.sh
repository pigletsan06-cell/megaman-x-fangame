#!/bin/bash
# Testa o atualizador do launcher com o GitHub de mentira. uso: teste_atualizador.sh PACOTE
P=$1; G=${FUSION_GODOT:-/home/claude/godot/Godot_v4.7.2-stable_linux.x86_64}; PORTA=8765
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
