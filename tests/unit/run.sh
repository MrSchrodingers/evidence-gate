#!/usr/bin/env bash
# AGREGADOR das suites de tests/unit/ (issue #55, G111).
#
# ATE A ONDA 27 este arquivo era a suite de regressao de hooks, com o nome convencional de
# agregador e nada que impusesse essa promessa: quem lia "run.sh 74 PASS / 0 FAIL, exit 0"
# inferia as 32 suites e recebia 1. A suite antiga foi renomeada para
# tests/unit/gate-e-guardas.sh, conteudo inalterado; este arquivo nasce agregador de verdade.
#
# DESPACHO POR DISCO, nao lista digitada a mao - a lista curada envelhece, e o argumento ja
# esta escrito em scripts/status.sh sobre a mesma classe de defeito. O conjunto e
# tests/unit/*.sh e tests/unit/*.py, exceto este proprio arquivo (sem auto-recursao).
#
# INTERPRETADOR POR SUFIXO: `.py` roda com `python3`, o resto com `bash`. Armadilha ja
# documentada em scripts/status.sh:25-32 - bash sobre um `.py` tipicamente sai 2 sem executar
# nada do arquivo, e ainda pode rodar como comando as crases de um docstring, se houver.
#
# POLITICA DE rc=2 (NAO VERIFICADO), DECLARADA E NAO IMPLICITA: uma suite que sai 2 declarou
# que NAO PODE ser executada aqui (dependencia ou precondicao ausente) - e diferente de ter
# reprovado uma garantia. As duas formas tornam a saida agregada NAO-ZERO (fail-closed: nem uma
# vira PASS em silencio), mas o relatorio rotula cada uma pelo nome certo (VERMELHAS para quem
# reprovou, NAO VERIFICADO para quem declarou que nao pode medir), para quem le nao confundir
# "defeito encontrado" com "experimento nao pode ser feito aqui".
#
# LOCK: este arquivo toma o lock de execucao (tests/lib/lock.sh) ele mesmo, pelo PROTOCOLO do
# arquivo - nao por um flock cru por fora dele. Cada suite despachada TAMBEM sourcea a mesma
# biblioteca ao ser carregada; como este arquivo sourcea primeiro, ele EXPORTA
# TOLLENS_LOCK=held antes de despachar, e os filhos, ao sourcear a mesma biblioteca, veem a
# marca herdada e PULAM a propria aquisicao (re-entrancia por desenho de tests/lib/lock.sh). Um
# agregador que tomasse um flock por fora desse protocolo (por exemplo `flock` cru envolvendo o
# laco de despacho, sem exportar a marca) arriscaria o filho tentar o MESMO lock sem a marca -
# a classe de autobloqueio que a issue #55 mediu ao desenhar esta correcao.
# tests/unit/agregador.sh prova o despacho, a agregacao de rc e a nao-ocorrencia de rc=3 aqui
# por OBSERVACAO, nunca por leitura de texto deste arquivo.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. "$(dirname "$0")/../lib/lock.sh"

# DEFESA EM PROFUNDIDADE, nao substituicao: cada suite despachada ja isola EVIDENCE_LEDGER_DIR
# por si mesma (conferido por tests/unit/contrato-de-instalador.sh, caso CI11). Exportar aqui
# tambem cobre uma suite nova que ainda nao tenha esse isolamento, sem depender dela para nao
# gravar paradas sinteticas no ledger do operador.
TMP_AGREG="$(mktemp -d)"; trap 'rm -rf "$TMP_AGREG"' EXIT
export EVIDENCE_LEDGER_DIR="$TMP_AGREG/ledger"

ALVOS=""
for t in tests/unit/*.sh tests/unit/*.py; do
  [ -f "$t" ] || continue
  [ "$(basename "$t")" = "run.sh" ] && continue
  ALVOS="$ALVOS $t"
done

VERMELHAS=""
NAO_VERIFICADAS=""
N=0
for t in $ALVOS; do
  N=$((N + 1))
  case "$t" in
    *.py) python3 "$t"; rc=$? ;;
    *)    bash "$t";    rc=$? ;;
  esac
  printf 'SUITE %s rc=%s\n' "$t" "$rc"
  if [ "$rc" -eq 2 ]; then
    NAO_VERIFICADAS="$NAO_VERIFICADAS $t"
  elif [ "$rc" -ne 0 ]; then
    VERMELHAS="$VERMELHAS $t"
  fi
done

# AUTOFIXACAO DA PROPRIA CONTAGEM - a mesma convencao de `pino_da_suite` em scripts/status.sh:
# EXPECTED derivado do DISCO, nao literal, porque o numero de suites varia entre commits ("o
# que discrimina nao e quanto a suite conta, e se ela se AUTOFIXA"). Protege contra um bug de
# glob/exclusao que despachasse silenciosamente menos suites do que existem no disco.
EXPECTED=$(($(ls tests/unit/*.sh tests/unit/*.py 2>/dev/null | wc -l) - 1))
if [ "$N" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: despachadas=$N, esperado $EXPECTED. Suite adicionada ou removida em silencio da varredura."
  exit 1
fi

N_VERMELHAS=$(printf '%s\n' $VERMELHAS | grep -c .)
N_NAO_VERIF=$(printf '%s\n' $NAO_VERIFICADAS | grep -c .)
echo
echo "================ DESPACHADAS=$N  VERMELHAS=$N_VERMELHAS  NAO_VERIFICADAS=$N_NAO_VERIF ================"
[ -n "$VERMELHAS" ] && echo "VERMELHAS:$VERMELHAS"
[ -n "$NAO_VERIFICADAS" ] && echo "NAO VERIFICADO:$NAO_VERIFICADAS"
if [ -z "$VERMELHAS" ] && [ -z "$NAO_VERIFICADAS" ]; then
  echo "bateria verde"
  exit 0
fi
echo "bateria com reprovacao ou pendencia de verificacao"
exit 1
