#!/bin/bash
# Pacote novo como o do amigo (só os arquivos do repositório) + discos reais: o launcher prepara tudo sozinho.
# uso: tools/testes/teste_discos_reais.sh   (depois: confere_assets.py "/tmp/amigo/Mega Man X Fusion/godot" MANIFESTO.json assets/x4c_disc_arc.sec assets/movies)
G=/home/claude/godot/Godot_v4.7.2-stable_linux.x86_64; REPO=/home/claude/megaman-x-fangame; P="/tmp/amigo/Mega Man X Fusion"
rm -rf /tmp/amigo; mkdir -p "$P/discos"
cd $REPO && git archive HEAD godot | tar -x -C "$P"
cp -r $REPO/launcher "$P/launcher"; rm -rf "$P/launcher/.godot"
mkdir -p "$P/tools"; cp -r $REPO/tools/extrator "$P/tools/"; rm -rf "$P/tools/extrator/.godot"; cp $REPO/tools/receita.json "$P/tools/"; cp -r $REPO/tools/captura $REPO/tools/x4core $REPO/tools/psxcore "$P/tools/"
echo '{"versao": 54}' > "$P/versao.json"
# aqui o GitHub não deixa baixar os zips da decompilação: põe os zips (feitos com git archive) onde o extrator procura
mkdir -p "$P/gerado/fontes"; cp /tmp/zip_mmx4.zip "$P/gerado/fontes/mmx4.zip"; cp /tmp/zip_psyz.zip "$P/gerado/fontes/psyz.zip"
ln -s "/home/claude/x4/Mega Man X4 (USA).bin" "$P/discos/"; ln -s "/home/claude/x5/Mega Man X5 (USA).bin" "$P/discos/"; ln -s "/home/claude/ext/MegaManX6Recomp/mmx6/Mega Man X6 (USA) (v1.1).bin" "$P/discos/"
rm -f /tmp/real_*.png; T0=$(date +%s)
[ -x /tmp/captura_bin/captura_rc ] || $REPO/tools/captura/compilar.sh /tmp/captura_bin > /dev/null
# (no Linux o launcher não monta a recompilação do X6: o dash da Blade usa a do PC do dono)
export FUSION_CAPTURA_RC=/tmp/captura_bin/captura_rc FUSION_RECOMP_X6=/home/claude/game/bin/libx6recomp.so FUSION_GAMEDIR_X6=/home/claude/recomp_x6
DISPLAY=:99 FUSION_GODOT=$G FUSION_CAPTURA=/tmp/captura_bin/captura timeout 3000 $G --path "$P/launcher" -- --auto --sem-jogo --foto=/tmp/real > /tmp/amigo/saida.txt 2>&1
echo "saída $? em $(( $(date +%s) - T0 ))s"
python3 -c "
import json;d=json.load(open('$P/gerado/relatorio_launcher.json'))
print('ok=%s msg=%s' % (d['ok'], d['mensagem']))
for e in d['etapas']: print('  ', e['id'], e['estado'], e['texto'])"
grep -E "ok: |ERRO|arquivo\(s\)" "$P/gerado/launcher.log"
