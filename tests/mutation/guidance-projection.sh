#!/usr/bin/env bash
# G110 (issue #54) - VALIDACAO POR MUTACAO do oraculo de tests/unit/guidance-projection.sh.
#
# Por que existe: tests/unit/guidance-projection.sh so prova que o oraculo reprova as fixtures
# HOJE. Isso nao prova que a reprovacao vem da garantia certa - precedente proprio deste
# repositorio (tests/mutation/risk-policy.sh): um teste que sobrevive a remocao da garantia nao
# testa a garantia, testa outra coisa.
#
# O oraculo vive DENTRO de tests/unit/guidance-projection.sh (heredoc `$TMP/oraculo.py`), nao em
# orchestration/ (custo de cobertura evitado, ver o topo daquele arquivo). Por isso ORIG e REG
# aqui sao o MESMO arquivo: cada mutante troca uma linha literal do oraculo embutido e reexecuta
# a suite inteira, verificando que o caso-alvo especifico (fixture que aquela garantia protege)
# passa a reprovar.
#
# TRES MUTANTES, um por garantia citada no plano de G110:
#   M1 - guarda de vacuidade do dominio (<2 classes) deixa de abortar;
#   M2 - vocabulario de agente deixa de vir do registry e passa a ser literal hard-coded;
#   M3 - not_risk_selected_actors deixa de ser somado ao alcance (ignorado).
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
# ARENA: muta uma COPIA da arvore, nunca a arvore candidata. Ver tests/lib/arena.sh.
. "$(dirname "$0")/../lib/arena.sh"
ORIG="tests/unit/guidance-projection.sh"
REG="tests/unit/guidance-projection.sh"
# ORDEM DO TRAP: restaurar ANTES de remover o diretorio temporario que guarda a copia limpa.
TMP="$(mktemp -d)"; trap 'cp -f "$TMP/orig.sh" "$ORIG" 2>/dev/null || true; rm -rf "$TMP"' EXIT
cp -f "$ORIG" "$TMP/orig.sh"
P=0; F=0; BASELINE=nao; EXPECTED_MUTANTS=3

echo "== baseline: a suite precisa passar ANTES de qualquer mutacao =="
if bash "$REG" >/dev/null 2>&1; then echo "  PASS  baseline verde"; BASELINE=ok
else echo "  FAIL  baseline VERMELHO - mutacao nao tem significado; abortando"; exit 1; fi
echo

# `troca` opera sobre string literal, nao regex de sed (mesma razao de tests/mutation/risk-policy.sh).
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
  cp -f "$TMP/orig.sh" "$ORIG"
  "$@"
  if cmp -s "$TMP/orig.sh" "$ORIG"; then
    echo "  FAIL  $nome NAO FOI APLICADO - o padrao nao casa com o codigo atual."
    echo "        Mutante nao aplicado nao e mutante sobrevivente: e teste invalido."
    F=$((F+1)); cp -f "$TMP/orig.sh" "$ORIG"; return
  fi
  if ! bash -n "$ORIG" 2>/dev/null; then
    echo "  FAIL  $nome nao tem sintaxe valida apos a mutacao"; F=$((F+1)); cp -f "$TMP/orig.sh" "$ORIG"; return
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
  cp -f "$TMP/orig.sh" "$ORIG"
}

echo "== mutacao: cada garantia removida DEVE quebrar o caso que a exercita =="

# M1 - GUARDA DE VACUIDADE (dominio). Sem ela, um kernel com dominio degenerado (<2 classes) nao
# aborta mais - a fixture G1 deixa de acusar a ausencia da guarda.
mutante M1 "dominio de risco com menos de 2 classes aborta o oraculo (GUARDA DE VACUIDADE)" \
  "G1 diagnostica a guarda, nao aprova por ausencia de ramo" \
  troca "assert len(classes) >= 2, f'guarda de vacuidade: dominio de classes de risco tem menos de 2 elementos ({classes})'" \
        "assert True, f'guarda de vacuidade: dominio de classes de risco tem menos de 2 elementos ({classes})'"

# M2 - VOCABULARIO DE AGENTE NAO E HARD-CODED. O oraculo tem de ler os nomes de agente das
# CHAVES do registry, nunca de uma lista fixa - senao um agente orfao NOVO, fora dessa lista,
# deixaria de ser acusado. A fixture NEG usa 'agente-orfao', que nao esta na lista hard-coded do
# mutante.
mutante M2 "nomes de agente vem do registry, nunca de literal hard-coded" \
  "NEG fixture negativa \(hook prescreve agente orfao\): RECUSADO" \
  troca "agentes = set(reg.get('agents') or {})" \
        "agentes = {'agente-a', 'agente-b', 'agente-c', 'agente-fora-do-alcance'}"

# M3 - not_risk_selected_actors E SOMADO AO ALCANCE, NAO IGNORADO - o proprio achado de G110.
# Ignora-lo faz todo agente ali declarado (agente-fora-do-alcance na fixture; revisor-frontend,
# analista-otimalidade e analista-fluxos na politica real) virar orfao de novo.
mutante M3 "not_risk_selected_actors e somado ao alcance, nao ignorado" \
  "POS fixture positiva \(toda prescricao alcancavel ou declarada\): aprova" \
  troca "nao_selecionados = set(pol.get('not_risk_selected_actors') or {})" \
        "nao_selecionados = set()"

cp -f "$TMP/orig.sh" "$ORIG"
echo
printf 'baseline=%s  mutantes_esperados=%s  mortos=%s  invalidos_ou_sobreviventes=%s\n' \
       "$BASELINE" "$EXPECTED_MUTANTS" "$P" "$F"
echo "================================================================"
if [ "$F" -ne 0 ]; then echo "mutacao VERMELHA: ha garantia que a suite nao protege"; exit 1; fi
if [ "$P" -ne "$EXPECTED_MUTANTS" ]; then
  echo "mutacao VERMELHA: $P mortos para $EXPECTED_MUTANTS mutantes - algum nao executou"; exit 1; fi
echo "mutacao verde: os $EXPECTED_MUTANTS mutantes morreram no caso-alvo correspondente"; exit 0
