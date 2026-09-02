#!/usr/bin/env bash
# MECANISMO - a suite de evidence/cobertura.sh (piso de cobertura de DECISAO por arquivo).
#
# O caso que importa aqui NAO e "o piso bate com o numero medido hoje" (isso e verificado a
# cada execucao do CI, nao e propriedade do MECANISMO). O caso que importa e o DISCRIMINANTE:
# remover um caso de teste que exercita um ramo tem que fazer `--check` REPROVAR. Sem esse
# caso negativo, `evidence/cobertura.sh` podia estar sempre imprimindo "OK" e nada aqui notaria
# - exatamente a forma do defeito que motivou esta ferramenta (mutation testing cego a omissao).
#
# COPIA, NAO MUTACAO NO LUGAR: ao contrario de tests/mutation/*.sh (que editam o ARQUIVO SOB
# TESTE no proprio repositorio, protegidos pelo lock reentrante), aqui removemos um CASO DE
# TESTE de uma COPIA descartavel de tests/unit/schedule.sh. Mutar a suite real, mesmo com
# restauracao por trap, arriscaria uma leitura concorrente de outro processo observar o
# arquivo sem o caso F12 e reportar uma contagem errada por corrida - o mesmo risco que
# tests/lib/lock.sh existe para fechar, mas aqui o alvo mutado seria a PROPRIA suite, nao um
# executavel de producao. Trabalhar em copia elimina a janela por construcao.
#
# ALVO: orchestration/schedule.py + tests/unit/schedule.sh (o par mais rapido dos cinco -
# ~3s por execucao). O caso F12 ("ciclo no grafo do workflow") e o UNICO que exercita a branch
# `if processados != len(nodes): raise ValueError("ciclo detectado"...)` em
# orchestration/schedule.py; nenhum outro caso do arquivo passa por ali (F14/F15 cobrem arestas
# fantasma, que sao rejeitadas ANTES do nivelamento). Removê-lo e o menor mutante possivel que
# ainda muda a cobertura MEDIDA de um jeito atribuivel a um ramo especifico.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

for bin in coverage python3 jq; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "NAO VERIFICADO: '$bin' ausente - o mecanismo sob teste nao pode ser exercitado." >&2
    exit 2
  }
done

prepara_copia(){ # $1 = diretorio destino - COPIA descartavel de tudo que o par mais rapido
  # dos cinco alvos (orchestration/schedule.py + tests/unit/schedule.sh) precisa para rodar
  # isolado. Fatorado para servir aos casos novos (CB-FROUXA em diante) sem repetir os sete
  # `cp -f` tres vezes.
  local d="$1"
  mkdir -p "$d/evidence" "$d/orchestration/workflows" "$d/orchestration/schedule" \
           "$d/tests/unit" "$d/tests/lib"
  cp -f evidence/cobertura.sh          "$d/evidence/cobertura.sh"
  cp -f orchestration/schedule.py      "$d/orchestration/schedule.py"
  # orchestration/schedule.py resolve a RAIZ pelo proprio `__file__` (nao por $PWD/cwd) quando
  # TOLLENS_ROOT nao esta setado - o grupo "os TRES workflows reais" de schedule.sh chama
  # o validador SEM override, entao a copia precisa dos dados de producao tambem, ou aquele grupo
  # reprova por dado ausente (NAO pelo piso) e a suite falha antes do que queremos medir.
  cp -f orchestration/registry.json          "$d/orchestration/registry.json"
  cp -f orchestration/workflows/*.json       "$d/orchestration/workflows/"
  cp -f orchestration/schedule/*.json        "$d/orchestration/schedule/"
  cp -f tests/unit/schedule.sh         "$d/tests/unit/schedule.sh"
  cp -f tests/lib/lock.sh              "$d/tests/lib/lock.sh"
  chmod +x "$d/evidence/cobertura.sh"
}

SCRATCH="$(mktemp -d)"; trap 'rm -rf "$SCRATCH"' EXIT
prepara_copia "$SCRATCH"

# `medido()`: roda a copia em modo relatorio (piso 0 - nunca reprova por si) e devolve o
# percentual MEDIDO (ja arredondado para baixo a 1 casa, a mesma unidade que --check compara).
medido(){
  COBERTURA_ALVOS="orchestration/schedule.py:0.0" \
  COBERTURA_SUITES="tests/unit/schedule.sh" \
    bash "$SCRATCH/evidence/cobertura.sh" 2>/dev/null \
    | awk -F'\t' '$1=="COBFILE"{print $3}'
}

echo "== baseline: cobertura medida da copia intacta =="
BASE="$(medido)"
[ -n "$BASE" ]; chk "baseline produziu um numero" $? 0

echo
echo "== CB1. piso == medido (limite inclusive): --check PASSA =="
COBERTURA_ALVOS="orchestration/schedule.py:$BASE" \
COBERTURA_SUITES="tests/unit/schedule.sh" \
  bash "$SCRATCH/evidence/cobertura.sh" --check >/dev/null 2>&1
chk "piso igual ao medido nao reprova" $? 0

echo
echo "== CB2. piso 0.1 ACIMA do medido, sem tocar nada: --check REPROVA (sanity de direcao) =="
ACIMA="$(python3 -c "print(round($BASE + 0.1, 1))")"
COBERTURA_ALVOS="orchestration/schedule.py:$ACIMA" \
COBERTURA_SUITES="tests/unit/schedule.sh" \
  bash "$SCRATCH/evidence/cobertura.sh" --check >/dev/null 2>&1
RC_ACIMA=$?
echo "  (rc observado: $RC_ACIMA)"
chk "piso acima do medido reprova mesmo sem mutacao" "$RC_ACIMA" 1

echo
echo "== CB-FROUXA. piso 0.1 ABAIXO do medido, sem tocar nada (catraca frouxa - fato (3) do "
echo "prompt: dois commits subiram a cobertura sem reapertar o piso e o antigo 'medido >= piso' "
echo "deixava passar): --check tem que REPROVAR, nao passar em silencio =="
ABAIXO="$(python3 -c "print(round($BASE - 0.1, 1))")"
COBERTURA_ALVOS="orchestration/schedule.py:$ABAIXO" \
COBERTURA_SUITES="tests/unit/schedule.sh" \
  bash "$SCRATCH/evidence/cobertura.sh" --check >"$SCRATCH/check-frouxa.log" 2>&1
RC_FROUXA=$?
echo "  (rc observado: $RC_FROUXA)"
chk "piso abaixo do medido (catraca frouxa) reprova - o antigo '>=' deixava passar" "$RC_FROUXA" 1
grep -qF "CATRACA FROUXA" "$SCRATCH/check-frouxa.log"
chk "  CB-FROUXA rotula como CATRACA FROUXA (pede reaperto), nao como ABAIXO DO PISO" $? 0

echo
echo "== CB-ANCORA1. quinto campo (ancora) da isencao BATE com o fonte: a isencao permanece "
echo "valida e '--check' continua OK no mesmo piso exato - G67/A4: nenhum caso ate aqui "
echo "exercitava o ramo da ancora (CB-ABS2 so escreve isencoes de quatro campos) =="
python3 - "$SCRATCH/evidence/cobertura.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
alvo = "orchestration/schedule.py|linha|107|heranca-piso-absoluto-2026-08-11\n"
if s.count(alvo) != 1:
    print("ENTRADA_ISENCAO_AUSENTE_OU_DUPLICADA", file=sys.stderr)
    sys.exit(1)
# quinto campo: texto exato (sem indentacao) que a linha 107 do fonte precisa ter.
ancorada = alvo.rstrip("\n") + '|print(f"SCHEDULE_ERROR {msg}")\n'
s = s.replace(alvo, ancorada, 1)
open(p, "w", encoding="utf-8").write(s)
PY
chk "CB-ANCORA1: ancora correta escrita na entrada existente (linha 107)" $? 0

COBERTURA_ALVOS="orchestration/schedule.py:$BASE" \
COBERTURA_SUITES="tests/unit/schedule.sh" \
  bash "$SCRATCH/evidence/cobertura.sh" --check >"$SCRATCH/check-ancora1.log" 2>&1
RC_ANCORA1=$?
chk "CB-ANCORA1: --check continua OK com a ancora batendo" "$RC_ANCORA1" 0
grep -qF "ramos/linhas: OK" "$SCRATCH/check-ancora1.log"
chk "  CB-ANCORA1: a camada 2 relata OK (isencao ancorada continua valendo)" $? 0

echo
echo "== CB-ANCORA2. quinto campo (ancora) NAO BATE com o fonte: a isencao e RECUSADA - nao "
echo "ignorada -, '--check' tem que reprovar nomeando o texto ESPERADO (ancora) e o ACHADO "
echo "(fonte real) =="
python3 - "$SCRATCH/evidence/cobertura.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
anterior = 'orchestration/schedule.py|linha|107|heranca-piso-absoluto-2026-08-11|print(f"SCHEDULE_ERROR {msg}")\n'
if s.count(anterior) != 1:
    print("ANCORA_ANTERIOR_AUSENTE", file=sys.stderr)
    sys.exit(1)
# mesma entrada, ancora agora cita um texto que a linha 107 nao tem.
divergente = anterior.replace('print(f"SCHEDULE_ERROR {msg}")', "return 1", 1)
s = s.replace(anterior, divergente, 1)
open(p, "w", encoding="utf-8").write(s)
PY
chk "CB-ANCORA2: ancora divergente escrita na MESMA entrada (linha 107)" $? 0

COBERTURA_ALVOS="orchestration/schedule.py:$BASE" \
COBERTURA_SUITES="tests/unit/schedule.sh" \
  bash "$SCRATCH/evidence/cobertura.sh" --check >"$SCRATCH/check-ancora2.log" 2>&1
RC_ANCORA2=$?
chk "CB-ANCORA2: --check reprova quando a ancora nao bate com o fonte" "$RC_ANCORA2" 1
grep -qF "NAO JUSTIFICADO" "$SCRATCH/check-ancora2.log"
chk "  CB-ANCORA2: a isencao com ancora divergente e RECUSADA, nao apenas ignorada" $? 0
grep -qF "linha 107: ancora esperava 'return 1', achou 'print(f\"SCHEDULE_ERROR {msg}\")'" \
  "$SCRATCH/check-ancora2.log"
chk "  CB-ANCORA2: a mensagem nomeia o ESPERADO (ancora) e o ACHADO (fonte real)" $? 0

python3 - "$SCRATCH/evidence/cobertura.sh" <<'PY'
# restaura a entrada ao estado sem ancora - CB3 em diante nao deve herdar uma ancora
# divergente que reprovaria por um motivo alheio ao que aquelas secoes medem.
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
divergente = "orchestration/schedule.py|linha|107|heranca-piso-absoluto-2026-08-11|return 1\n"
original = "orchestration/schedule.py|linha|107|heranca-piso-absoluto-2026-08-11\n"
if s.count(divergente) != 1:
    print("ESTADO_INESPERADO_PARA_RESTAURAR", file=sys.stderr)
    sys.exit(1)
s = s.replace(divergente, original, 1)
open(p, "w", encoding="utf-8").write(s)
PY
chk "CB-ANCORA2: entrada restaurada ao estado sem ancora para as secoes seguintes" $? 0

echo
echo "== mutacao (em COPIA): remove o UNICO caso que exercita 'ciclo detectado' (F12) =="
python3 - "$SCRATCH/tests/unit/schedule.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
bloco = '''OUT12="$(roda f12-ciclo 2>&1)"; RC12=$?
chk "F12 ciclo no grafo do workflow: RECUSADO" "$RC12" 1
printf '%s' "$OUT12" | grep -qF "ciclo detectado"
chk "  F12 diagnostica ciclo" $? 0

'''
if bloco not in s:
    print("BLOCO_NAO_ENCONTRADO", file=sys.stderr)
    sys.exit(1)
s = s.replace(bloco, "", 1)
# dois `chk` removidos - a copia precisa continuar se autovalidando (EXPECTED) para que o
# oraculo de "suite falhou" de evidence/cobertura.sh nao mascare o resultado que queremos medir.
#
# A SUBSTITUICAO FALHA ALTO. Ate a onda 15 isto era um `str.replace` mudo: quando
# `tests/unit/schedule.sh` ganhou os casos F16-F18 e a linha virou `EXPECTED=34`, o replace
# deixou de casar, nao reclamou, e a copia ficou exigindo 34 acertos com 32 casos. Sete
# assercoes desta suite cairam em cascata e o diagnostico apontava para o mecanismo de
# cobertura, nao para a ancora perdida. Ancora que nao casa e defeito, nao no-op.
import re
m = re.search(r"^EXPECTED=(\d+)", s, re.M)
if not m:
    print("EXPECTED_NAO_ENCONTRADO", file=sys.stderr)
    sys.exit(1)
s = s[:m.start()] + f"EXPECTED={int(m.group(1)) - 2}" + s[m.end():]
open(p, "w", encoding="utf-8").write(s)
PY
chk "bloco F12 removido da copia" $? 0

echo
echo "== CB3. cobertura MEDIDA cai na copia mutada =="
# controle: a copia mutada ainda precisa se autovalidar (dois casos a menos) - senao o --check
# reprovaria por SUITE QUEBRADA (NOT_VERIFIED, exit 2), nao pelo piso, e o caso deixaria de ser
# atribuivel ao mecanismo de cobertura.
bash "$SCRATCH/tests/unit/schedule.sh" >"$SCRATCH/copia-mutada.log" 2>&1
RC_SUITE_MUTADA=$?
chk "copia mutada ainda se autovalida (dois casos a menos, exit 0)" "$RC_SUITE_MUTADA" 0
BASE2="$(medido)"
[ -n "$BASE2" ] && python3 -c "import sys; sys.exit(0 if float('$BASE2') < float('$BASE') else 1)"
chk "medido caiu apos remover F12 (antes=$BASE depois=$BASE2)" $? 0

echo
echo "== CB4. MESMO piso que passava em CB1 agora REPROVA (o discriminante) =="
COBERTURA_ALVOS="orchestration/schedule.py:$BASE" \
COBERTURA_SUITES="tests/unit/schedule.sh" \
  bash "$SCRATCH/evidence/cobertura.sh" --check >"$SCRATCH/check-c4.log" 2>&1
RC_CB4=$?
[ "$RC_CB4" -eq 1 ]; chk "piso antigo agora reprova apos remover o caso que o sustentava" $? 0

echo
echo "== CB5. a reprovacao NOMEIA o arquivo abaixo do piso =="
grep -qF "orchestration/schedule.py" "$SCRATCH/check-c4.log"
chk "saida nomeia orchestration/schedule.py como abaixo do piso" $? 0

echo
echo "== CB6. SEM --check (modo relatorio), a mesma copia mutada NAO reprova =="
COBERTURA_ALVOS="orchestration/schedule.py:$BASE" \
COBERTURA_SUITES="tests/unit/schedule.sh" \
  bash "$SCRATCH/evidence/cobertura.sh" >/dev/null 2>&1
chk "modo relatorio (sem --check) nunca reprova, mesmo abaixo do piso" $? 0

echo
echo "== CB7. 'coverage' ausente do PATH: NAO_VERIFICADO (exit 2), nunca PASS nem FAIL silencioso =="
COVDIR="$(dirname "$(command -v coverage)")"
SEMCOV="$(printf '%s\n' "$PATH" | tr ':' '\n' | grep -vF "$COVDIR" | paste -sd: -)"
PATH="$SEMCOV" COBERTURA_SUITES="tests/unit/schedule.sh" \
  bash "$SCRATCH/evidence/cobertura.sh" >"$SCRATCH/c7.log" 2>&1
RC_CB7=$?
[ "$RC_CB7" -eq 2 ]; chk "coverage ausente produz exit 2 (got=$RC_CB7)" $? 0
grep -qF "NAO VERIFICADO" "$SCRATCH/c7.log"
chk "  CB7 rotula a lacuna como NAO VERIFICADO, nao como reprovacao" $? 0

echo
echo "== CB-ABS. camada 2 (predicado absoluto sobre ramos/linhas) - fato (1) do prompt: um ramo "
echo "novo nao exercitado tem que reprovar mesmo com o piso percentual EXATO no numero novo "
echo "(reaperto preguicoso que so copia o percentual sem olhar o diff de cobertura) =="
SCRATCH2="$SCRATCH/dilui"
prepara_copia "$SCRATCH2"
python3 - "$SCRATCH2/orchestration/schedule.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
anchor = 'if __name__ == "__main__":\n    raise SystemExit(main())\n'
if not s.endswith(anchor):
    print("ANCORA_AUSENTE", file=sys.stderr)
    sys.exit(1)
extra = "\n".join(f"_REPRO_ABS_{i} = 1" for i in range(1, 31))
ramo = f'''{extra}


def _repro_fato1_ramo_nao_exercitado() -> bool:
    """Fixture de teste do mecanismo (CB-ABS): um ramo nao exercitado por nenhum caso da
    suite, mais 30 statements cobertos ao lado - a MESMA forma do fato (1) medido no prompt
    desta tarefa (o denominador dilui o mesmo ramo nao coberto). Inserido no FIM do arquivo,
    depois da ultima linha que ISENCOES referencia, para nao deslocar os numeros de linha
    das 35 entradas ja isentas - a mutacao precisa introduzir UM gap novo, nao invalidar os
    antigos por acidente de posicionamento."""
    se_debug = os.environ.get("SCHEDULE_DEBUG_REPRO_ABS")
    if se_debug:
        print("ramo nunca exercitado por teste algum")
        return True
    return False


_repro_fato1_ramo_nao_exercitado()


'''
s = s[: -len(anchor)] + ramo + anchor
open(p, "w", encoding="utf-8").write(s)
PY
chk "CB-ABS: ramo + 30 statements inseridos no fim da copia (sem deslocar as isencoes)" $? 0

DILUI_MEDIDO="$(COBERTURA_ALVOS="orchestration/schedule.py:0.0" \
COBERTURA_SUITES="tests/unit/schedule.sh" \
  bash "$SCRATCH2/evidence/cobertura.sh" 2>/dev/null | awk -F'\t' '$1=="COBFILE"{print $3}')"
[ -n "$DILUI_MEDIDO" ]; chk "CB-ABS: copia diluida mede um numero" $? 0

echo
echo "== CB-ABS1. piso reapertado (preguicosamente) para o numero diluido: a camada 1 "
echo "(percentual) fica OK, mas o ramo novo continua sem isencao - a camada 2 tem que reprovar "
echo "sozinha, mesmo com a camada 1 satisfeita =="
COBERTURA_ALVOS="orchestration/schedule.py:$DILUI_MEDIDO" \
COBERTURA_SUITES="tests/unit/schedule.sh" \
  bash "$SCRATCH2/evidence/cobertura.sh" --check >"$SCRATCH2/check-abs1.log" 2>&1
RC_ABS1=$?
chk "CB-ABS1: --check reprova mesmo com o piso percentual exato (reaperto preguicoso nao basta)" "$RC_ABS1" 1
grep -qF "COBFILE	orchestration/schedule.py	$DILUI_MEDIDO	$DILUI_MEDIDO	OK" "$SCRATCH2/check-abs1.log"
chk "  CB-ABS1: a camada 1 (percentual) de fato deu OK - quem reprova e so a camada 2" $? 0
grep -qF "NAO JUSTIFICADO" "$SCRATCH2/check-abs1.log"
chk "  CB-ABS1: a saida rotula o ramo/linha novo como NAO JUSTIFICADO" $? 0

FALTAS="$(grep 'ramos/linhas: NAO JUSTIFICADO:' "$SCRATCH2/check-abs1.log" | sed 's/.*NAO JUSTIFICADO: //')"
[ -n "$FALTAS" ]; chk "CB-ABS1: a lista de faltas foi capturada para o controle CB-ABS2" $? 0

echo
echo "== CB-ABS2. controle: os MESMOS itens, agora com isencao declarada (motivo escrito, na "
echo "PROPRIA copia - nao um override de teste) - --check tem que PASSAR (a camada 2 respeita "
echo "isencao real, nao reprova as cegas so por existir ramo novo) =="
python3 - "$SCRATCH2/evidence/cobertura.sh" "$FALTAS" <<'PY'
import sys
p, faltas = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
# ANCORA NO FIM DO HEREDOC, NAO NUMA LINHA DE ISENCAO. Ate a onda 15 isto casava a ULTIMA
# entrada literal da lista (`...|ramo|388->-1|...`), e a lista e por numero de linha: quando
# `orchestration/schedule.py` ganhou o bloco de separacao de oraculo, todos os numeros
# deslocaram, a ancora sumiu e os dois casos CB-ABS2 reprovaram apontando para o mecanismo de
# cobertura em vez de para a ancora. Ancorar no delimitador do heredoc nao desloca.
import re as _re
m = _re.search(r"(ISENCOES=\"?\$\{COBERTURA_ISENCOES:-\$\(cat <<'EOF'\n.*?\n)EOF\n", s, _re.S)
if not m:
    print("ANCORA_ISENCOES_AUSENTE", file=sys.stderr)
    sys.exit(1)
ancora = m.group(0)
novas = []
for item in faltas.split(", "):
    if item.startswith("linha "):
        novas.append(f"orchestration/schedule.py|linha|{item[6:]}|teste-cb-abs2-justificado")
    elif item.startswith("ramo "):
        novas.append(f"orchestration/schedule.py|ramo|{item[5:]}|teste-cb-abs2-justificado")
    else:
        print(f"ITEM_INESPERADO {item!r}", file=sys.stderr)
        sys.exit(1)
substituto = m.group(1) + "\n".join(novas) + "\nEOF\n"
s = s.replace(ancora, substituto, 1)
open(p, "w", encoding="utf-8").write(s)
PY
chk "CB-ABS2: isencao dos itens novos inserida na copia do mecanismo" $? 0

COBERTURA_ALVOS="orchestration/schedule.py:$DILUI_MEDIDO" \
COBERTURA_SUITES="tests/unit/schedule.sh" \
  bash "$SCRATCH2/evidence/cobertura.sh" --check >"$SCRATCH2/check-abs2.log" 2>&1
RC_ABS2=$?
chk "CB-ABS2: com isencao escrita para o ramo novo, --check passa" "$RC_ABS2" 0

echo
echo "== CB-COMPL. completude de ALVOS - COPIA PRISTINA PROPRIA (SCRATCH3, nao a mutada por "
echo "F12 acima): reusar \$SCRATCH aqui deixaria \$BASE desalinhado do medido real (a suite ja "
echo "foi mutada para CB3-CB6) e a camada 1 reprovaria por SI, mascarando o que a completude "
echo "(camada 3) de fato contribui - o RC deixaria de ser atribuivel, a mesma classe de defeito "
echo "que este mecanismo existe para fechar. Isolar em copia propria, com piso exato medido "
echo "nela, torna a completude a UNICA variavel possivel no RC abaixo =="
SCRATCH3="$SCRATCH/completude"
prepara_copia "$SCRATCH3"
BASE3="$(COBERTURA_ALVOS="orchestration/schedule.py:0.0" COBERTURA_SUITES="tests/unit/schedule.sh" \
  bash "$SCRATCH3/evidence/cobertura.sh" 2>/dev/null | awk -F'\t' '$1=="COBFILE"{print $3}')"
[ -n "$BASE3" ]; chk "CB-COMPL: copia propria mede um numero" $? 0

echo
echo "== CB-COMPL1. a copia intacta (so schedule.py em orchestration/), piso exato: nao acusa "
echo "candidato sem piso =="
COBERTURA_ALVOS="orchestration/schedule.py:$BASE3" \
COBERTURA_SUITES="tests/unit/schedule.sh" \
  bash "$SCRATCH3/evidence/cobertura.sh" --check >"$SCRATCH3/compl1.log" 2>&1
RC_COMPL1=$?
chk "CB-COMPL1: --check passa na copia intacta com piso exato (nada mais divergente)" "$RC_COMPL1" 0
grep -qF "todo candidato varrido esta em ALVOS ou em EXCLUSOES" "$SCRATCH3/compl1.log"
chk "  CB-COMPL1: nenhum candidato novo na copia intacta" $? 0
! grep -qF "COBCOMPL" "$SCRATCH3/compl1.log"
chk "  CB-COMPL1: nenhuma linha COBCOMPL emitida" $? 0

echo
echo "== CB-COMPL2. um probe NOVO (com guarda __main__, sem piso nem exclusao) nasce em "
echo "silencio - a completude tem que acusar, --check tem que reprovar (fato: ALVOS e digitada "
echo "a mao, sem checagem). Piso continua o MESMO exato de CB-COMPL1 - a UNICA mudanca e o "
echo "arquivo novo, entao a reprovacao so pode ser atribuida a camada 3 =="
cat > "$SCRATCH3/orchestration/probe_orfao.py" <<'PY'
#!/usr/bin/env python3
"""Fixture CB-COMPL2: probe novo, nunca declarado em ALVOS nem em EXCLUSOES."""
if __name__ == "__main__":
    raise SystemExit(0)
PY
COBERTURA_ALVOS="orchestration/schedule.py:$BASE3" \
COBERTURA_SUITES="tests/unit/schedule.sh" \
  bash "$SCRATCH3/evidence/cobertura.sh" --check >"$SCRATCH3/compl2.log" 2>&1
RC_COMPL2=$?
chk "CB-COMPL2: --check reprova com um candidato nao contabilizado" "$RC_COMPL2" 1
grep -qF "COBFILE	orchestration/schedule.py	$BASE3	$BASE3	OK" "$SCRATCH3/compl2.log"
chk "  CB-COMPL2: a camada 1 (percentual) de fato deu OK - so a completude mudou" $? 0
grep -qF "COBCOMPL	orchestration/probe_orfao.py" "$SCRATCH3/compl2.log"
chk "  CB-COMPL2: a saida nomeia o arquivo orfao especifico" $? 0

echo
echo "================ PASS=$P  FAIL=$F ================"
EXPECTED=36
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
[ "$F" -eq 0 ] && echo "mecanismo de cobertura verde ($P/$EXPECTED)" || echo "mecanismo de cobertura VERMELHO"
exit "$F"
