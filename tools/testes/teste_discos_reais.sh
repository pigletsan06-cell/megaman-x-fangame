#!/bin/bash
# Pacote novo como o do amigo (só os arquivos do repositório) + discos reais: o launcher prepara tudo sozinho.
# uso: tools/testes/teste_discos_reais.sh   (depois: confere_assets.py "/tmp/amigo/Mega Man X Fusion/godot" MANIFESTO.json assets/x4c_disc_arc.sec assets/movies)
G=/home/claude/godot/Godot_v4.7.2-stable_linux.x86_64; REPO=/home/claude/megaman-x-fangame; P="/tmp/amigo/Mega Man X Fusion"
rm -rf /tmp/amigo; mkdir -p "$P/discos"
cd $REPO && git archive HEAD godot | tar -x -C "$P"
cp -r $REPO/launcher "$P/launcher"; rm -rf "$P/launcher/.godot"
mkdir -p "$P/tools"; cp -r $REPO/tools/extrator "$P/tools/"; cp $REPO/tools/receita.json "$P/tools/"
echo '{"versao": 54}' > "$P/versao.json"
ln -s "/home/claude/x4/Mega Man X4 (USA).bin" "$P/discos/"; ln -s "/home/claude/x5/Mega Man X5 (USA).bin" "$P/discos/"; ln -s "/home/claude/ext/MegaManX6Recomp/mmx6/Mega Man X6 (USA) (v1.1).bin" "$P/discos/"
rm -f /tmp/real_*.png; T0=$(date +%s)
DISPLAY=:99 FUSION_GODOT=$G timeout 3000 $G --path "$P/launcher" -- --auto --sem-jogo --foto=/tmp/real > /tmp/amigo/saida.txt 2>&1
echo "saída $? em $(( $(date +%s) - T0 ))s"
python3 -c "
import json;d=json.load(open('$P/gerado/relatorio_launcher.json'))
print('ok=%s msg=%s' % (d['ok'], d['mensagem']))
for e in d['etapas']: print('  ', e['id'], e['estado'], e['texto'])"
grep -E "ok: |ERRO|arquivo\(s\)" "$P/gerado/launcher.log"
