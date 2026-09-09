#!/usr/bin/env bash
# VALIDACAO POR MUTACAO DA SUITE DOS HOOKS DE GUARDA.
#
# CLAUDE.md secao 6.3, regra 2: "todo teste de garantia de seguranca e validado por MUTACAO -
# remova a garantia do codigo e exija que o teste REPROVE. Um teste que sobrevive ao mutante nao
# testa a garantia, testa outra coisa." A suite `tests/unit/hooks-de-guarda.sh` nasce afirmando
# que oito hooks antes nao executados fazem o que declaram fazer. Sem este arnes essa
# afirmacao vale o mesmo que valia a tabela irreproduzivel de mutantes do ADR 0033: nada que
# alguem possa refutar amanha.
#
# CADA MUTANTE REMOVE UMA GARANTIA DO HOOK, NUNCA UMA ASSERCAO DA SUITE. Mutar a suite provaria
# que ela reage a si mesma; o que precisa ser provado e que ela reage ao HOOK.
#
# ARENA (onda 11): a mutacao roda numa copia descartavel, jamais na arvore candidata. Restaurar
# depois nao desfaz a janela em que outro processo pode ter observado o mutante -
# `EventuallyRestored` nao implica `NeverObservableAsMutant`.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/lib/lock.sh
. tests/lib/arena.sh

P=0; F=0; EXPECTED_MUTANTS=19
SUITE="tests/unit/hooks-de-guarda.sh"
AD="control/hooks/artifact-discipline.sh"
SM="control/hooks/self-mod-audit.sh"
RT="control/hooks/risk-trigger.sh"
PK="execution/hooks/poka-yoke-lint.sh"
FG="control/hooks/fable-guard.sh"
LT="execution/hooks/lentes.sh"
GS="execution/hooks/graphify-scout-mode.sh"
SP="evidence/hooks/subagent-probe.sh"
DS="execution/hooks/ds4-notify.sh"
OB="execution/hooks/output-budget.sh"

# BASELINE. Sem ele todo "MORTO" abaixo poderia ser erro de ambiente (jq ausente, ruff ausente,
# HOME nao gravavel) em vez de assercao. O arnes de `tests/mutation/methodology.py` ja pagou
# exatamente essa forma nesta mesma semana: matava 16/16 por FileNotFoundError, com a arvore nao
# mutada ja reprovando.
bash "$SUITE" >/dev/null 2>&1
_base=$?
if [ "$_base" -ne 0 ]; then
  echo "BASELINE VERMELHO (exit=$_base): a suite ja reprova na arvore NAO mutada." >&2
  echo "Sem baseline verde, todo 'MORTO' abaixo seria falha de ambiente - o arnes e VACUO." >&2
  exit 1
fi
echo "baseline verde: a suite sai 0 na arvore nao mutada"

# BLOCOS PULAVEIS POR AMBIENTE. Achado A8 de revisao independente: dois casos da suite se
# declaram NAO VERIFICADO conforme a estacao - GS1 quando `graphify` e alcancavel no PATH do
# hook, e o bloco DS inteiro quando ha helper escutando em 127.0.0.1:8791. Nesses ambientes os
# mutantes que dependem deles (MHG12 e MHG14) seriam reportados SOBREVIVEU: falso alarme, nao
# falso verde, mas ainda assim um arnes que sai 1 por motivo de ambiente treina o operador a
# ignorar vermelho. O arnes passa a LER o baseline e declarar o mutante inaplicavel em vez de
# divergente - e a contagem esperada acompanha, para que "pulou" nao vire "nao existe".
_BASE_OUT="$(bash "$SUITE" 2>&1 || true)"
GS_EXERCITADO=1; DS_EXERCITADO=1
case "$_BASE_OUT" in *"NAO VERIFICADO  GS1"*) GS_EXERCITADO=0 ;; esac
case "$_BASE_OUT" in *"NAO VERIFICADO  DS1"*) DS_EXERCITADO=0 ;; esac
[ "$GS_EXERCITADO" = 1 ] || { echo "  INAPLICAVEL MHG12 - GS1 pulado neste ambiente (graphify alcancavel)"; EXPECTED_MUTANTS=$((EXPECTED_MUTANTS-1)); }
[ "$DS_EXERCITADO" = 1 ] || { echo "  INAPLICAVEL MHG14 - bloco DS pulado neste ambiente (helper em 8791)"; EXPECTED_MUTANTS=$((EXPECTED_MUTANTS-1)); }

# A mutacao viaja por AMBIENTE, nao por interpolacao de shell. Os alvos sao trechos de shell
# cheios de aspas simples, duplas e barras; monta-los dentro de `python3 -c "..."` foi tentado e
# produz codigo ilegivel cujo erro mais provavel e a mutacao NAO APLICAR - falha que se
# disfarcaria de "mutante sobreviveu".
_aplica(){
  ALVO="$1" DE="$2" PARA="$3" python3 -c '
import os, pathlib, sys
p = pathlib.Path(os.environ["ALVO"]); t = p.read_text(encoding="utf-8")
de, para = os.environ["DE"], os.environ["PARA"]
if t.count(de) != 1:
    print(f"ancora ocorre {t.count(de)}x (esperado 1)", file=sys.stderr); sys.exit(1)
p.write_text(t.replace(de, para, 1), encoding="utf-8")
'
}

mutante(){ # $1=nome $2=alvo $3=descricao $4=exit esperado $5=de $6=para
  local nome="$1" alvo="$2" desc="$3" want="$4" got
  cp "$alvo" "$alvo.bak"
  if ! _aplica "$alvo" "$5" "$6"; then
    echo "  ERRO  $nome: a mutacao nao aplicou"; F=$((F+1)); mv -f "$alvo.bak" "$alvo"; return
  fi
  if cmp -s "$alvo" "$alvo.bak"; then
    # Mutacao que nao muda byte algum e o modo de falha silencioso deste tipo de arnes: a suite
    # passa, o mutante e contado como sobrevivente e o diagnostico culpa a suite, nao a mutacao.
    echo "  ERRO  $nome: a mutacao deixou o arquivo IDENTICO"; F=$((F+1)); mv -f "$alvo.bak" "$alvo"; return
  fi
  bash "$SUITE" >/dev/null 2>&1; got=$?
  if [ "$got" -eq "$want" ]; then echo "  MORTO $nome - $desc (exit=$got)"; P=$((P+1))
  else echo "  SOBREVIVEU $nome - $desc (exit=$got, esperado=$want)"; F=$((F+1)); fi
  mv -f "$alvo.bak" "$alvo"
}

mutante_duplo(){ # $1=nome $2=alvo $3=desc $4=want $5=de1 $6=para1 $7=de2 $8=para2
  local nome="$1" alvo="$2" desc="$3" want="$4" got
  cp "$alvo" "$alvo.bak"
  if ! _aplica "$alvo" "$5" "$6" || ! _aplica "$alvo" "$7" "$8"; then
    echo "  ERRO  $nome: a mutacao dupla nao aplicou"; F=$((F+1)); mv -f "$alvo.bak" "$alvo"; return
  fi
  bash "$SUITE" >/dev/null 2>&1; got=$?
  if [ "$got" -eq "$want" ]; then echo "  MORTO $nome - $desc (exit=$got)"; P=$((P+1))
  else echo "  SOBREVIVEU $nome - $desc (exit=$got, esperado=$want)"; F=$((F+1)); fi
  mv -f "$alvo.bak" "$alvo"
}

echo "== artifact-discipline.sh - o portao que CLAUDE.md secao 8 declara =="
mutante MHG1 "$AD" "sem a checagem de emoji" 1 \
  '  0) echo '\''Bloqueado: emojis não permitidos.'\'' >&2; exit 2 ;;' \
  '  0) : ;;'
mutante MHG2 "$AD" "sem a checagem de lexico" 1 \
  '  0) echo '\''Bloqueado: léxico de hype/persona não deve vazar.'\'' >&2; exit 2 ;;' \
  '  0) : ;;'
mutante MHG3 "$AD" "sem a excecao de .claude/ - passa a bloquear o que nao devia" 1 \
  '*/.claude/*) exit 0;;' '*/.claude/nunca-casa/*) exit 0;;'
mutante MHG4 "$AD" "sentinela de autorizacao deixa de ser barrado" 1 \
  '*.fable-allowed|*/verify-cmd-approved)' '*.jamais-casa|*/nunca-casa)'

echo "== poka-yoke-lint.sh =="
mutante MHG5 "$PK" "stop-the-line trocado por passe livre" 1 \
  '} >&2
exit 2' '} >&2
exit 0'

echo "== self-mod-audit.sh - instrumento fail-open, nao portao =="
mutante MHG6 "$SM" "instrumento vira portao: passa a BLOQUEAR" 1 \
  'command -v jq >/dev/null 2>&1 || exit 0' \
  'command -v jq >/dev/null 2>&1 || exit 0
exit 2'
mutante MHG7 "$SM" "sem a trilha duravel em log" 1 \
  'LOG="${HOME}/.claude/logs/self-mod-audit.log"' 'LOG="/dev/null"'

echo "== risk-trigger.sh =="
mutante MHG8 "$RT" "sem o throttle: repete o mesmo aviso indefinidamente" 1 \
  '"$((NOW-LAST))" -lt 600' '"$((NOW-LAST))" -lt 0'

echo "== fable-guard.sh =="
mutante MHG9 "$FG" "deteccao de escrita do sentinela desarmada" 1 \
  'if printf '\''%s'\'' "$CMD" | grep -qE '\''\.fable-allowed'\''; then' \
  'if false; then'

echo "== os quatro que run.sh classificava sem nunca executar =="
mutante MHG11 "$LT" "guidance deixa de ser incondicional: a saida passa a depender do prompt" 1 \
  "cat <<'EOF'" "cat; cat <<'EOF'"
[ "$GS_EXERCITADO" = 1 ] && \
mutante MHG12 "$GS" "sem a guarda de topo: passa a falar em repo que nao usa graphify" 1 \
  '   && [ ! -f "$GRAPH" ]; then
  exit 0
fi' '   && [ ! -f "$GRAPH" ]; then
  :
fi'
mutante MHG19 "$GS" "sem o portao TOLLENS_ROUTING_NUDGES: braco A do E_A deixa de conseguir desligar o nudge (G108/#52)" 1 \
  'off|0|false) exit 0 ;; esac' 'off|0|false) : ;; esac'
mutante MHG13 "$SP" "instrumento passa a TRUNCAR o registro em vez de acrescentar" 1 \
  "printf '%s\\n' \"\$IN\" >> \"\$LOG\"" "printf '%s\\n' \"\$IN\" > \"\$LOG\""
[ "$DS_EXERCITADO" = 1 ] && \
mutante MHG14 "$DS" "forwarder deixa de errar fechado e passa a bloquear" 1 \
  'exit 0' 'exit 2'

# MHG15 E EQUIVALENTE, E O ARNES DIZ ISSO EM VEZ DE FORCAR UMA MORTE. Removida a guarda de
# tamanho, `output-budget.sh` AINDA nao emite nada para saida pequena, porque uma SEGUNDA guarda
# independente (`[ "$NEWSZ" -ge "$SZ" ] && exit 0`, linha 97) descarta o corte que nao encolhe.
# O mutante nao muda comportamento observavel algum: e defesa em profundidade real, medida aqui,
# nao assercao fraca. Declarar `want=0` registra a redundancia; MHG16 remove AS DUAS e mostra que
# a assercao OB1 e, de fato, sensivel ao comportamento que afirma medir.
mutante MHG15 "$OB" "EQUIVALENTE: sem a guarda de tamanho, a segunda guarda ainda protege" 0 \
  '[ "$SZ" -le "$LIM" ] && exit 0' '[ "$SZ" -le 0 ] && exit 0'
mutante_duplo MHG16 "$OB" "sem NENHUMA das duas guardas: passa a reescrever saida pequena" 1 \
  '[ "$SZ" -le "$LIM" ] && exit 0' '[ "$SZ" -le 0 ] && exit 0' \
  '[ "$NEWSZ" -ge "$SZ" ] && exit 0' '[ "$NEWSZ" -ge 0 ] && :'

echo "== o defeito de locale que a suite achou, e a classe dele =="
mutante MHG17 "$AD" "sem o locale pinado: o portao de emoji desliga sob LC_ALL=C" 1 \
  'printf '\''%s'\'' "$CONTENT" | LC_ALL="$_EMOJI_LOCALE" grep -qP "$EMOJI" 2>/dev/null || _rc=$?' \
  'printf '\''%s'\'' "$CONTENT" | grep -qP "$EMOJI" 2>/dev/null || _rc=$?'
# AS DUAS guardas de fail-closed, nao uma. Com so a do emoji mutada, o stub de `grep` do caso
# AD10 tambem faz a checagem de LEXICO errar, e a guarda dela ainda bloqueava - o mutante
# sobrevivia por uma razao que nada tinha a ver com a garantia sob teste.
mutante_duplo MHG18 "$AD" "erro do grep volta a ser tratado como ausencia (fail-open)" 1 \
  '  *) echo "Bloqueado (fail-closed): nao foi possivel verificar emoji - grep -P indisponivel ou locale sem UTF-8 (LC_ALL=$_EMOJI_LOCALE)." >&2; exit 2 ;;' \
  '  *) : ;;' \
  "  *) echo 'Bloqueado (fail-closed): nao foi possivel verificar o lexico.' >&2; exit 2 ;;" \
  '  *) : ;;'

echo "== CONTROLE DE VACUIDADE =="
# Sem este caso, uma suite que reprovasse a QUALQUER edicao do hook - por digest, por contagem de
# linhas, por mtime - mataria os quinze mutantes acima sem testar garantia nenhuma. O comentario
# extra muda bytes e nao muda comportamento: a suite TEM de continuar verde.
mutante MHG10 "$AD" "CONTROLE: comentario inerte - a suite deve PASSAR" 0 \
  '#!/usr/bin/env bash' \
  '#!/usr/bin/env bash
# comentario inerte inserido pelo controle de vacuidade MHG10'

echo
echo "MUTANTES=$((P+F)) ESPERADOS=$EXPECTED_MUTANTS CORRETOS=$P DIVERGENTES=$F"
if [ "$((P+F))" -ne "$EXPECTED_MUTANTS" ]; then
  echo "ERRO: $((P+F)) mutantes executados, $EXPECTED_MUTANTS declarados." >&2
  exit 1
fi
[ "$F" -eq 0 ]
