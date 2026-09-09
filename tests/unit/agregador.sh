#!/usr/bin/env bash
# ISSUE #55 (G111) - prova, por OBSERVACAO e nao por leitura de texto, que tests/unit/run.sh
# despacha e agrega as suites de tests/unit/, em vez de ser uma suite de regressao com o nome
# convencional de agregador e nada que imponha essa promessa.
#
# NAO TAUTOLOGICO, DE PROPOSITO: o oraculo abaixo NUNCA faz grep de nome de suite DENTRO do
# texto de tests/unit/run.sh - isso repetiria "mencao nao e execucao" dentro da propria correcao
# que a persegue (a mesma classe medida em tests/unit/capability-conformance.py:462-490 e em
# scripts/status.sh:140-141). Em vez disso, cada tests/unit/*.sh e *.py (exceto run.sh) e
# SUBSTITUIDO, numa arena descartavel (tests/lib/arena.sh), por um stub instrumentado que so
# prova a propria execucao gravando o proprio caminho relativo num log. O ESPERADO vem do
# DISCO (`ls tests/unit`); o OBSERVADO vem da EXECUCAO real do candidato a agregador.
#
# CUSTO: os stubs nao fazem trabalho algum, entao o custo desta suite e segundos - contra os
# ~15 s medidos nesta arvore para `bash tests/unit/run.sh` rodar as suites de verdade. E por
# isso que o fixture existe, em vez de rodar a arvore real a cada assercao.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

# LOCK e ARENA: esta suite MUTA arquivos de tests/unit/ para exercitar o agregador, e isso nao
# pode tocar a arvore real - o mesmo motivo que tests/mutation/*.sh usa arena descartavel.
. "$(dirname "$0")/../lib/lock.sh"
. "$(dirname "$0")/../lib/arena.sh"
ARENA="$PWD"   # tests/lib/arena.sh ja fez cd para a copia descartavel

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
LOG="$T/despachados.log"
MARKER_PY="$T/py-marker"

# ESPERADO vem do DISCO da arena, nao de lista digitada a mao - lista curada envelhece (o
# proprio argumento ja escrito em scripts/status.sh sobre a mesma classe de defeito).
ESPERADO="$(cd "$ARENA" && ls tests/unit/*.sh tests/unit/*.py 2>/dev/null | grep -vxF 'tests/unit/run.sh' | sort)"
N_ESPERADO=$(printf '%s\n' "$ESPERADO" | grep -c .)

echo "== A6. ANTIVACUIDADE: a arena tem suites suficientes para a varredura ter poder de decisao =="
chk "  >= 15 alvos substituiveis (espirito de regressao-gate.sh:63-65)" \
    "$([ "$N_ESPERADO" -ge 15 ] && echo sim || echo "nao($N_ESPERADO)")" sim

# ALVO DEDICADO PARA A2 (agregacao de rc): um .sh qualquer que NAO seja telemetry-skills.sh -
# nao reusa-lo evita confundir o despacho explicito ja existente (issue #53) com o despacho
# GERAL que esta suite mede. Todo .py da arena entra em A4 (interpretador por sufixo).
FALVO="$(printf '%s\n' "$ESPERADO" | grep -v '\.py$' \
    | grep -vxF 'tests/unit/telemetry-skills.sh' | grep -vxF 'tests/unit/agregador.sh' | head -1)"

# Gera o stub .sh de um alvo: grava o proprio caminho relativo no LOG e sai com o rc pedido.
# LOCK-AWARE DE PROPOSITO (A5): o stub sourcea tests/lib/lock.sh de verdade, como toda suite
# real deste repositorio - sem isso a suite nunca exerceria contencao real de lock, e A5
# mediria vacuidade (um stub que nunca toca o mecanismo nao pode discriminar autobloqueio).
escreve_stub_sh(){   # $1=caminho relativo na arena  $2=rc de saida
  {
    printf '#!/usr/bin/env bash\n'
    printf 'set -uo pipefail\n'
    printf 'cd "$(dirname "$0")/../.." || exit 1\n'
    printf '. "$(dirname "$0")/../lib/lock.sh"\n'
    printf 'echo "%s" >> "%s"\n' "$1" "$LOG"
    printf 'exit %s\n' "$2"
  } > "$ARENA/$1"
}
# Gera o stub .py de um alvo: so grava (no LOG e no marcador partilhado MARKER_PY) quando
# executado por python3. Sob bash, `import pathlib` nao e comando valido e o processo sai sem
# gravar nada - a armadilha documentada em scripts/status.sh:25-32 (bash sobre .py nao executa
# e ainda pode rodar cracas do docstring como comando).
escreve_stub_py(){   # $1=caminho relativo do .py na arena
  {
    printf 'import pathlib\n'
    printf 'pathlib.Path("%s").open("a").write("%s\\n")\n' "$LOG" "$1"
    printf 'pathlib.Path("%s").write_text("ok")\n' "$MARKER_PY"
  } > "$ARENA/$1"
}

monta_fixture(){   # $1=caminho do alvo que deve sair 1 (vazio = nenhum, todos saem 0)
  # TODO .py vira stub python - a arena tem mais de um .py
  # (capability-conformance.py, governance-links.py, methodology.py), e escrever conteudo bash
  # num arquivo .py faria o candidato correto (que despacha .py com python3) reprova-lo por
  # sintaxe - falso vermelho medindo o fixture, nao o agregador.
  local falha="$1" f rc
  for f in $ESPERADO; do
    case "$f" in
      *.py) escreve_stub_py "$f" ;;
      *)
        [ "$f" = "$falha" ] && rc=1 || rc=0
        escreve_stub_sh "$f" "$rc"
        ;;
    esac
  done
}

# CANDIDATO A AGREGADOR, dentro da arena. `env -u TOLLENS_LOCK` e defensivo, nao decorativo: se
# esta propria suite for despachada PELO agregador real (ela e um membro de tests/unit/*.sh), o
# processo-pai ja exportou TOLLENS_LOCK=held, e sem a limpeza o experimento do agregador
# CANDIDATO dentro da arena herdaria a marca por acidente e nunca exerceria lock algum -
# exatamente a forma de teste vacuo que tests/unit/concorrencia.sh ja precisou fechar.
roda_candidato(){ ( cd "$ARENA" && env -u TOLLENS_LOCK bash tests/unit/run.sh ) 2>&1; }

echo "== A1+A3+A4. CONTROLE NEGATIVO: todos os stubs saem 0 =="
rm -f "$LOG" "$MARKER_PY"
monta_fixture ""
SAIDA1="$(roda_candidato)"; RC1=$?
OBSERVADO="$(sort -u "$LOG" 2>/dev/null)"
ESPERADO_ORD="$(printf '%s\n' "$ESPERADO" | sort -u)"
chk "  A1 completude por observacao: despachados == disco (nem a mais, nem a menos)" \
    "$OBSERVADO" "$ESPERADO_ORD"
chk "  A3 controle negativo: todos passam -> agregador sai 0" "$RC1" 0
chk "  A4 interpretador por sufixo: o .py so grava quando rodado por python3" \
    "$([ -f "$MARKER_PY" ] && echo sim || echo nao)" sim

echo "== A2. O ORACULO: uma suite falha -> agregador reprova E nomeia a suite =="
rm -f "$LOG" "$MARKER_PY"
monta_fixture "$FALVO"
SAIDA2="$(roda_candidato)"; RC2=$?
chk "  rc != 0 quando uma suite falha" "$([ "$RC2" -ne 0 ] && echo sim || echo nao)" sim
chk "  a saida NOMEIA a suite que falhou ($FALVO)" \
    "$(printf '%s' "$SAIDA2" | grep -qF "$FALVO" && echo sim || echo nao)" sim

echo "== A5. LOCK: o agregador nao pode se autobloquear no lock que cada suite ja toma =="
if command -v flock >/dev/null 2>&1; then
  rm -f "$LOG" "$MARKER_PY"
  monta_fixture ""
  SAIDA5="$(roda_candidato)"; RC5=$?
  chk "  execucao integral: nenhuma suite despachada devolve 3 (corrida)" \
      "$(printf '%s' "$SAIDA5" | grep -c 'rc=3')" 0
  # LIMITE DECLARADO, medido nesta investigacao: um discriminador sintetico foi tentado aqui
  # (segurar o lock da arena neste processo e invocar um filho SEM TOLLENS_LOCK=held herdado,
  # esperando bloqueio real). Ele se mostrou NAO DETERMINISTICO neste ambiente - reproduzido
  # isoladamente com `exec 9>ARQUIVO` no pai e no filho apontando para o MESMO arquivo: quando o
  # filho reabre o MESMO NUMERO de descritor ja herdado do pai (fd 9, a convencao de
  # tests/lib/lock.sh), o filho adquire o lock em vez de ser bloqueado - comportamento de
  # flock(2) associado a open file description e fork, e nao um defeito deste teste. Manter um
  # oraculo que varia entre PASS e FAIL sem mudanca de codigo violaria "medicao errada e pior
  # que nenhuma medicao". A assercao acima permanece por OBSERVACAO do candidato real (protege
  # contra a classe relatada - agregador que se autobloqueia -, sem alegar prova adversarial de
  # que o oraculo discrimina o caso quebrado).
  HAVE_FLOCK=1
else
  echo "  NAO MEDIDO  A5 (flock ausente neste ambiente - o mecanismo sob teste nao existe aqui)"
  HAVE_FLOCK=0
fi

echo
echo "================ PASS=$P  FAIL=$F ================"
EXPECTED=$((6 + HAVE_FLOCK * 1))
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
[ "$F" -eq 0 ] && echo "agregador verde" || echo "agregador VERMELHO"
exit "$F"
