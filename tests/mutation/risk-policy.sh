#!/usr/bin/env bash
# VALIDACAO POR MUTACAO - a politica risco->workflow em orchestration/render.py (G103, issue
# #47; docs/adr/0020, regra de metodo 2).
#
# Por que existe: tests/unit/risk-policy.sh so prova que o validador REJEITA as fixtures hoje.
# Isso nao prova que a rejeicao vem da garantia certa - o precedente proprio deste repositorio
# (ADR 0020, tests/mutation/schedule.sh) e um teste que sobrevive a remocao da garantia nao testa
# a garantia, testa outra coisa. Cada mutante abaixo remove UMA das cinco garantias do modelo -
# (i) totalidade do dominio, (ii) ausencia de classe orfa, (iii) resolucao do workflow, (iv)
# ausencia declarada (nao inferida), (v) alcance de todo workflow em disco - e EXIGE que
# tests/unit/risk-policy.sh reprove no caso especifico que aquela garantia protege.
#
# O MUTANTE CENTRAL e MR1 (totalidade): sem ele a politica pode omitir uma classe inteira do
# kernel e a suite continuaria verde - exatamente o estado que existia antes desta correcao,
# so que com um JSON no lugar em vez de prosa.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
# ARENA: muta uma COPIA da arvore, nunca a arvore candidata. Ver tests/lib/arena.sh para os
# seis incidentes medidos que motivaram isto.
. "$(dirname "$0")/../lib/arena.sh"
ORIG="orchestration/render.py"
REG="tests/unit/risk-policy.sh"
# ORDEM DO TRAP: restaurar ANTES de remover o diretorio temporario que guarda a copia limpa -
# uma interrupcao no meio do jogo nao pode deixar o mutante instalado no arquivo real
# (defeito ja medido em tests/mutation/run.sh, ver o comentario la).
TMP="$(mktemp -d)"; trap 'cp -f "$TMP/orig.py" "$ORIG" 2>/dev/null || true; rm -rf "$TMP"' EXIT
cp -f "$ORIG" "$TMP/orig.py"
P=0; F=0; BASELINE=nao; EXPECTED_MUTANTS=5

echo "== baseline: a suite precisa passar ANTES de qualquer mutacao =="
if bash "$REG" >/dev/null 2>&1; then echo "  PASS  baseline verde"; BASELINE=ok
else echo "  FAIL  baseline VERMELHO - mutacao nao tem significado; abortando"; exit 1; fi
echo

# `troca` opera sobre string literal, nao regex de sed: evita escapar colchetes/parenteses do
# alvo (mesma razao registrada em tests/mutation/schedule.sh).
troca(){ # $1=de  $2=para
  python3 - "$ORIG" "$1" "$2" <<'PY'
import sys
p, de, para = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
n = s.count(de)
if n != 1:
    sys.exit(f"padrao nao e unico no arquivo (achado {n}x): {de!r}")
open(p, 'w').write(s.replace(de, para, 1))
PY
}

mutante(){ # $1=nome $2=descricao $3=caso-alvo (regex) que DEVE reprovar $4..=comando de mutacao
  local nome="$1" desc="$2" alvo="$3"; shift 3
  cp -f "$TMP/orig.py" "$ORIG"
  "$@"
  if cmp -s "$TMP/orig.py" "$ORIG"; then
    echo "  FAIL  $nome NAO FOI APLICADO - o padrao nao casa com o codigo atual."
    echo "        Mutante nao aplicado nao e mutante sobrevivente: e teste invalido."
    F=$((F+1)); cp -f "$TMP/orig.py" "$ORIG"; return
  fi
  if ! python3 -m py_compile "$ORIG" 2>/dev/null; then
    echo "  FAIL  $nome nao compila apos a mutacao"; F=$((F+1)); cp -f "$TMP/orig.py" "$ORIG"; return
  fi
  local out rc
  out="$(bash "$REG" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  FAIL  $nome SOBREVIVEU - a suite passa sem a garantia: $desc"; F=$((F+1))
  elif printf '%s\n' "$out" | grep -qE "^  FAIL.*$alvo"; then
    echo "  PASS  $nome morto pelo caso certo ($alvo)"; P=$((P+1))
  else
    echo "  FAIL  $nome: suite reprovou, mas NAO em '$alvo' - kill nao atribuivel"; F=$((F+1))
    printf '%s\n' "$out" | grep '^  FAIL' | sed 's/^/        /'
  fi
  cp -f "$TMP/orig.py" "$ORIG"
}

echo "== mutacao: cada garantia removida DEVE quebrar o caso que a exercita =="

# MR1 - garantia (i), MUTANTE CENTRAL: TOTALIDADE. Sem ela, uma classe do kernel sem entrada na
# politica deixa de ser recusada - a politica pode omitir uma classe inteira e o portao aprova.
mutante MR1 "toda classe do kernel tem entrada na politica (TOTALIDADE)" \
  "N1 politica sem a classe 'trivial'" \
  troca "  if c not in mapa_norm: erros.append(f\"classe do kernel sem entrada na politica: '{c}'\")" \
        "  if False: erros.append(f\"classe do kernel sem entrada na politica: '{c}'\")"

# MR2 - garantia (ii): SEM CLASSE ORFA. Sem ela, a politica pode declarar uma classe que o
# kernel nao conhece (ex.: um risco ja removido do kernel) sem ser acusada.
mutante MR2 "toda classe da politica existe no kernel (SEM CLASSE ORFA)" \
  "N2 politica com 'catastrofico' que o kernel nao declara" \
  troca "  if c not in dominio: erros.append(f\"classe na politica que o kernel nao declara: '{c}'\")" \
        "  if False: erros.append(f\"classe na politica que o kernel nao declara: '{c}'\")"

# MR3 - garantia (iii): RESOLUCAO. Sem ela, uma classe pode apontar para um workflow que nao
# existe em disco e a politica seria aceita mesmo assim - a funcao deixaria de ser resolvivel.
mutante MR3 "todo workflow nao-nulo existe em disco (RESOLUCAO)" \
  "N3 'medio' aponta para workflow inexistente" \
  troca "  elif wf not in existentes:" \
        "  elif False:"

# MR4 - garantia (iv): AUSENCIA DECLARADA (criterio 2 da issue #47). Sem ela, uma classe pode
# ficar sem workflow SEM nenhuma justificativa - ausencia INFERIDA, nao declarada, exatamente o
# que a issue proibe.
mutante MR4 "workflow nulo exige rationale nao vazia (AUSENCIA DECLARADA)" \
  "N4 'trivial' -> null SEM rationale" \
  troca "   if not str(v.get('rationale', '')).strip():" \
        "   if False:"

# MR5 - garantia (v): ALCANCE. Sem ela, um workflow em disco pode ficar fora da imagem da
# politica E fora de 'not_risk_selected' sem ser acusado - o inverso de MR1, e o que fecha o
# ciclo de que TODO workflow real e contabilizado por alguma via declarada.
mutante MR5 "todo workflow em disco e alcancavel ou declarado (ALCANCE)" \
  "N5 sem not_risk_selected: investigation-only fica orfao" \
  troca "  if wid not in imagem and wid not in nao_por_risco:" \
        "  if False:"

cp -f "$TMP/orig.py" "$ORIG"
echo
printf 'baseline=%s  mutantes_esperados=%s  mortos=%s  invalidos_ou_sobreviventes=%s\n' \
       "$BASELINE" "$EXPECTED_MUTANTS" "$P" "$F"
echo "================================================================"
if [ "$F" -ne 0 ]; then echo "mutacao VERMELHA: ha garantia que a suite nao protege"; exit 1; fi
if [ "$P" -ne "$EXPECTED_MUTANTS" ]; then
  echo "mutacao VERMELHA: $P mortos para $EXPECTED_MUTANTS mutantes - algum nao executou"; exit 1; fi
echo "mutacao verde: os $EXPECTED_MUTANTS mutantes morreram no caso-alvo correspondente"; exit 0
