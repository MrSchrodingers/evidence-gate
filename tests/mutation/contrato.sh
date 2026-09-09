#!/usr/bin/env bash
# VALIDACAO POR MUTACAO do CONTRATO DE SUBAGENTE. Remove cada garantia de
# `evidence/hooks/subagent-contract.sh` e EXIGE que `tests/unit/gate-e-guardas.sh` reprove NO
# CASO-ALVO (renomeado da issue #55/G111; `tests/unit/run.sh` e agora o agregador de suites).
#
# Por que este arquivo existe (2026-08-04): `tests/mutation/run.sh` so mutava o verify-gate.
# O contrato de subagente - o hook com o pior historico do projeto, origem dos ADRs 0014, 0018
# e do adendo 6 do 0022 - nunca fora validado por mutacao. O resultado era previsivel e foi
# medido: a regressao R4, escrita justamente para proteger a normalizacao de acento, montava o
# payload com campos que o hook NAO LE (`transcript_path`, `subagent_type` em vez de
# `agent_type`, `last_assistant_message`). O hook saia no filtro de tipo antes de qualquer
# verificacao, e um mutante que apagava TODA a normalizacao seguia verde.
#
# Regra herdada de tests/mutation/run.sh: mutante nao aplicado e FALHA, nao sobrevivencia; e
# kill nao atribuivel ao caso-alvo tambem e FALHA - a suite pode ter reprovado por acidente.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
# ARENA: muta uma COPIA da arvore, nunca a arvore candidata. Ver tests/lib/arena.sh para os
# seis incidentes medidos que motivaram isto.
. "$(dirname "$0")/../lib/arena.sh"
ORIG="evidence/hooks/subagent-contract.sh"
REG="tests/unit/gate-e-guardas.sh"
TMP="$(mktemp -d)"
cp -f "$ORIG" "$TMP/orig.sh"
# O trap restaura o ORIGINAL antes de apagar o TMP - na ordem inversa o arquivo se perde.
trap 'cp -f "$TMP/orig.sh" "$ORIG" 2>/dev/null || true; rm -rf "$TMP"' EXIT
P=0; F=0; BASELINE=nao; EXPECTED_MUTANTS=9

echo "== baseline: a suite precisa passar ANTES de qualquer mutacao =="
if bash "$REG" >/dev/null 2>&1; then echo "  PASS  baseline verde"; BASELINE=ok
else echo "  FAIL  baseline VERMELHO - mutacao nao tem significado; abortando"; exit 1; fi
echo

# $1=nome  $2=descricao da garantia  $3=trecho do caso-alvo  $4=python de mutacao (stdin)
mutante(){
  local nome="$1" desc="$2" alvo="$3"
  cp -f "$TMP/orig.sh" "$ORIG"
  python3 - "$ORIG" || { echo "  FAIL  $nome: script de mutacao falhou"; F=$((F+1)); cp -f "$TMP/orig.sh" "$ORIG"; return; }
  if cmp -s "$TMP/orig.sh" "$ORIG"; then
    echo "  FAIL  $nome NAO FOI APLICADO - o padrao nao casa com o codigo atual."
    echo "        Mutante nao aplicado nao e mutante sobrevivente: e teste invalido."
    F=$((F+1)); cp -f "$TMP/orig.sh" "$ORIG"; return
  fi
  if ! bash -n "$ORIG" 2>/dev/null; then
    echo "  FAIL  $nome nao compila apos a mutacao"; F=$((F+1)); cp -f "$TMP/orig.sh" "$ORIG"; return
  fi
  local out rc
  out="$(bash "$REG" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  FAIL  $nome SOBREVIVEU - a suite passa sem a garantia: $desc"; F=$((F+1))
  elif printf '%s' "$out" | grep -q "FAIL.*$alvo"; then
    echo "  PASS  $nome morto pelo caso certo ($alvo)"; P=$((P+1))
  else
    echo "  FAIL  $nome: suite reprovou, mas NAO em '$alvo' - kill nao atribuivel"; F=$((F+1))
  fi
  cp -f "$TMP/orig.sh" "$ORIG"
}

echo "== mutacao do contrato: cada garantia removida DEVE quebrar o caso que a protege =="

# MC1 - a tolerancia a pontuacao de markdown no "exit code" volta ao padrao estrito de antes
#       do defeito. Alvo: o caso de ancora UNICA com crase.
mutante MC1 "exit code tolerante a crase" "exit code' com crase" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace(r"'|exit[^0-9A-Za-z]{0,4}(code|status)?[^0-9A-Za-z]{0,4}[0-9]'",
            r"'|exit[[:space:]]*(code)?[[:space:]]*[=:]?[[:space:]]*[0-9]'")
open(p,'w').write(s)
PY

# MC2 - a FORMA de comando volta a ser uma allowlist FECHADA de nomes. Alvo: o comando `xxd`,
#       que nao estava na lista antiga - e que representa a classe inteira dos que nunca vao estar.
mutante MC2 "forma de comando em vez de allowlist de nomes" "FORA da antiga allowlist" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace(r"'|(^|[`$(>|])[[:space:]]*[a-z][a-z0-9_.+-]*([[:space:]]+[a-z0-9_.+-]+){0,3}[[:space:]]+-{1,2}[A-Za-z0-9]'",
            r"'|^[[:space:]]*(git|npm|pytest|ruff|mypy|eslint|pip-audit|npx|go|cargo|jq|grep|rg|sed|awk|tail) '")
open(p,'w').write(s)
PY

# MC3 - a saida honesta deixa de ser aceita. Alvo: o caso `nao verificado`. Sem esta garantia o
#       hook volta a bloquear exatamente o que a sua propria mensagem instrui o agente a fazer.
mutante MC3 "nao-verificado e saida valida" "saida honesta" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace(r'|| grep -qE "$NAO_VERIFICADO" <<<"$NORM" ', '')
open(p,'w').write(s)
PY

# MC4 - o oraculo vira VACUO: aceita qualquer coisa. Alvo: o discriminador negativo. Este e o
#       mutante que a suite anterior nao tinha como matar, porque nao havia caso negativo para
#       a ancora - so positivos. Positivo sem negativo mede presenca, nao poder de decisao.
mutante MC4 "o oraculo DECIDE (nao aceita tudo)" "BARRA blocos completos SEM ancora" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("ANCORA='[A-Za-z0-9_./-]+\\.[A-Za-z0-9]+:[0-9]+'", "ANCORA='.*'")
open(p,'w').write(s)
PY

# MC5 - a normalizacao de acento some. Alvo: o caso de EVIDENCIA acentuada (ADR 0018).
#       Este e o mutante que a R4 antiga deixava SOBREVIVER.
mutante MC5 "normalizacao de acento (ADR 0018)" "aceita EVIDENCIA acentuada" <<'PY'
import sys, re
p=sys.argv[1]; s=open(p).read()
s2=re.sub(r'NORM="\$\(printf.*?\)"\n', 'NORM="$LAST"\n', s, flags=re.S)
assert s2 != s, "padrao da normalizacao nao encontrado"
open(p,'w').write(s2)
PY

# MC6 - a alternativa de prompt de shell volta a casar em QUALQUER posicao. Alvo: o caso da
#       moeda. Em PT-BR `R$ ` e notacao corrente; sem a ancora de inicio de linha ela
#       satisfazia sozinha a exigencia de evidencia. Achado por revisao independente.
mutante MC6 "prompt de shell ancorado no inicio da linha" "cifrao de MOEDA" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
alvo = "ANCORA=\"$ANCORA\"'|^[[:space:]]*\\$[[:space:]]'"
assert alvo in s, "padrao do prompt ancorado nao encontrado"
s = s.replace(alvo, "ANCORA=\"$ANCORA\"'|\\$ '")
open(p, 'w').write(s)
MUT

# MC7 - o token de nao-verificacao volta a casar minusculas por substring, sem polaridade.
#       Alvo: a frase NEGADA, que AFIRMA verificacao e atravessava - e que o proprio hook
#       ensinava, por conter a frase na mensagem de bloqueio. Achado por revisao independente.
mutante MC7 "token NAO VERIFICADO em caixa alta" "nada ficou nao verificado" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
alvo = "NAO_VERIFICADO='NAO[[:space:]]+VERIFICADO'"
assert alvo in s, "padrao do token nao encontrado"
s = s.replace(alvo, "NAO_VERIFICADO='(nao|not)[[:space:]]+(verificad[oa]|verified)'")
alvo2 = 'grep -qE "$NAO_VERIFICADO" <<<"$NORM"'
assert alvo2 in s, "chamada do token nao encontrada"
s = s.replace(alvo2, 'grep -qiE "$NAO_VERIFICADO" <<<"$NORM"')
open(p, 'w').write(s)
MUT

# MC8 - a exigencia do bloco RISCOS some. Alvo: o caso que cobra o contrato inteiro, e nao
#       metade dele. A mensagem do hook sempre cobrou quatro blocos; o codigo conferia dois.
mutante MC8 "o bloco RISCOS e cobrado" "BARRA retorno sem RISCOS" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
alvo = "grep -qiE '^[[:space:]]*[-*#]*[[:space:]]*RISCOS' <<<\"$NORM\"    || MISS=\"$MISS RISCOS\""
assert alvo in s, "padrao de RISCOS nao encontrado"
s = s.replace(alvo, "true")
open(p, 'w').write(s)
MUT

# MC9 - a exigencia do bloco PROPAGACAO some. Alvo: o caso correspondente.
mutante MC9 "o bloco PROPAGACAO e cobrado" "BARRA retorno sem PROPAGACAO" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
alvo = "grep -qiE '^[[:space:]]*[-*#]*[[:space:]]*PROPAGACAO' <<<\"$NORM\" || MISS=\"$MISS PROPAGACAO\""
assert alvo in s, "padrao de PROPAGACAO nao encontrado"
s = s.replace(alvo, "true")
open(p, 'w').write(s)
MUT

cp -f "$TMP/orig.sh" "$ORIG"
echo
printf 'baseline=%s  mutantes_esperados=%s  mortos=%s  invalidos_ou_sobreviventes=%s\n' \
       "$BASELINE" "$EXPECTED_MUTANTS" "$P" "$F"
echo "================================================================"
if [ "$F" -ne 0 ]; then echo "mutacao VERMELHA: ha garantia que a suite nao protege"; exit 1; fi
if [ "$P" -ne "$EXPECTED_MUTANTS" ]; then
  echo "mutacao VERMELHA: $P mortos para $EXPECTED_MUTANTS mutantes - algum nao executou"; exit 1; fi
echo "mutacao verde: os $EXPECTED_MUTANTS mutantes morreram no caso-alvo correspondente"; exit 0
