#!/usr/bin/env bash
# VALIDACAO POR MUTACAO - o proprio piso de cobertura de decisao (evidence/cobertura.sh).
#
# Regra de metodo 2 (ADR 0020): garantia de seguranca so vale se, ao remove-la, o teste
# REPROVA. Seis mutantes, um por garantia introduzida ou preservada nesta correcao da folga
# estrutural apontada pelo portao final da onda 5 (piso ABSOLUTO == medido, predicado
# absoluto sobre ramos/linhas com isencao, e completude de ALVOS):
#   MCB1 - `float(piso)` lido de ALVOS e descartado em favor de 0.0 na leitura da CLI (a
#         garantia de que o piso DECLARADO e o que de fato entra na comparacao).
#   MCB2 - `--check` DEIXA DE COMPARAR (a violacao e detectada e impressa, mas nunca vira
#         reprovacao - o passo de CI ficaria sempre verde).
#   MCB3 - camada 1 (piso exato) para de reprovar quando o piso esta FROUXO (medido > piso,
#         catraca nao reapertada apos melhora de cobertura) - fato (3) do prompt desta
#         tarefa: dois commits subiram a cobertura sem reapertar o piso e nada notou.
#   MCB4 - camada 2 (predicado absoluto sobre ramos/linhas) para de reprovar um ramo novo sem
#         isencao - fato (1) do prompt: o mesmo ramo nao exercitado, diluido por statements
#         cobertos ao lado, teria que reprovar por FORA do percentual.
#   MCB5 - camada 3 (completude de ALVOS) para de reprovar um candidato novo sem piso nem
#         exclusao - um probe nasce sem cobertura, em silencio.
#   MCB6 - conferencia da ANCORA (quinto campo de ISENCOES, G67/A4) para de recusar uma
#         isencao cujo texto NAO bate com o fonte - a isencao volta a valer so pelo numero de
#         linha, o modo de falha que a ancora existe para fechar.
# tests/unit/cobertura.sh (REG) e quem precisa morder cada um: ele ja teve motivo pra existir
# (a mesma suite discrimina o mutante de CONTEUDO em orchestration/schedule.py - ver CB3/CB4
# daquele arquivo); aqui o alvo sob mutacao e o MECANISMO, nao o conteudo medido por ele.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. "$(dirname "$0")/../lib/lock.sh"
# ARENA: muta uma COPIA da arvore, nunca a arvore candidata. Ver tests/lib/arena.sh para os
# seis incidentes medidos que motivaram isto.
. "$(dirname "$0")/../lib/arena.sh"
ORIG="evidence/cobertura.sh"
REG="tests/unit/cobertura.sh"
TMP="$(mktemp -d)"; trap 'cp -f "$TMP/orig.sh" "$ORIG" 2>/dev/null || true; rm -rf "$TMP"' EXIT
cp -f "$ORIG" "$TMP/orig.sh"
P=0; F=0; BASELINE=nao; EXPECTED_MUTANTS=6

echo "== baseline: tests/unit/cobertura.sh precisa passar ANTES de qualquer mutacao =="
if bash "$REG" >/dev/null 2>&1; then echo "  PASS  baseline verde"; BASELINE=ok
else echo "  FAIL  baseline VERMELHO - mutacao nao tem significado; abortando"; exit 1; fi
echo

troca(){ # $1=de  $2=para  - string literal, nao regex
  python3 - "$ORIG" "$1" "$2" <<'PY'
import sys
p, de, para = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
if de not in s:
    sys.exit(1)
open(p, "w").write(s.replace(de, para, 1))
PY
}

mutante(){ # $1=nome $2=descricao $3=caso-alvo $4..=comando
  local nome="$1" desc="$2" alvo="$3"; shift 3
  cp -f "$TMP/orig.sh" "$ORIG"
  if ! "$@"; then
    echo "  FAIL  $nome NAO FOI APLICADO - o padrao nao casa com o codigo atual."
    echo "        Mutante nao aplicado nao e mutante sobrevivente: e teste invalido."
    F=$((F+1)); cp -f "$TMP/orig.sh" "$ORIG"; return
  fi
  if cmp -s "$TMP/orig.sh" "$ORIG"; then
    echo "  FAIL  $nome NAO FOI APLICADO - o padrao nao casa com o codigo atual."
    F=$((F+1)); cp -f "$TMP/orig.sh" "$ORIG"; return
  fi
  bash -n "$ORIG" || { echo "  FAIL  $nome nao compila (bash -n) apos a mutacao"; F=$((F+1)); cp -f "$TMP/orig.sh" "$ORIG"; return; }
  local out rc
  out="$(bash "$REG" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  FAIL  $nome SOBREVIVEU - $REG passa sem a garantia: $desc"; F=$((F+1))
  elif printf '%s' "$out" | grep -qF "FAIL  $alvo"; then
    echo "  PASS  $nome morto pelo caso certo ($alvo)"; P=$((P+1))
  else
    echo "  FAIL  $nome: $REG reprovou, mas NAO em '$alvo' - kill nao atribuivel"; F=$((F+1))
    printf '%s\n' "$out" | grep '  FAIL  ' | sed 's/^/        visto: /'
  fi
  cp -f "$TMP/orig.sh" "$ORIG"
}

echo "== mutacao: cada garantia removida DEVE fazer tests/unit/cobertura.sh reprovar =="

# MCB1 - o piso declarado e descartado em favor de 0.0 na leitura de ALVOS. Com piso=0.0 para
# TODO alvo, a comparacao exata (camada 1) nunca mais bate com o que foi de fato declarado -
# CB1 (piso == medido nao reprova) e quem prova isso primeiro na saida.
mutante MCB1 "o piso e MEDIDO/comparado - nao pode ir a zero por baixo do CLI" \
  "piso igual ao medido nao reprova" \
  troca 'alvos.append((caminho, float(piso)))' \
        'alvos.append((caminho, 0.0))'

# MCB2 - `--check` deixa de comparar com o piso: a violacao ainda e IMPRESSA (abaixo continua
# populado), mas o exit code nunca reflete isso - o passo de CI ficaria sempre verde, tornando
# o piso decoracao (o mesmo defeito, na FERRAMENTA, que motivou esta ferramenta sobre o probe).
mutante MCB2 "'--check' reprova (exit 1) quando ha item divergente" \
  "piso acima do medido reprova mesmo sem mutacao" \
  troca '    if check:
        sys.exit(1)' \
        '    if False:
        sys.exit(1)'

# MCB3 - camada 1 (piso EXATO): a direcao "catraca frouxa" (medido > piso, cobertura subiu e
# ninguem reapertou o piso) para de contar como problema. Esta e a forma PRECISA do fato (3)
# do prompt - `medido >= piso` (o desenho antigo) deixava passar exatamente este caso.
mutante MCB3 "medido > piso (catraca frouxa) tem que reprovar, nao so medido < piso" \
  "piso abaixo do medido (catraca frouxa) reprova - o antigo '>=' deixava passar" \
  troca '        status_piso = f"CATRACA FROUXA (reapertar para {medido:.1f})"
        problema = True' \
        '        status_piso = f"CATRACA FROUXA (reapertar para {medido:.1f})"
        problema = problema'

# MCB4 - camada 2 (predicado absoluto sobre ramos/linhas): um ramo/linha ausente e sem isencao
# e detectado (a mensagem NAO JUSTIFICADO ainda e impressa) mas para de contar como motivo de
# reprovacao - a forma exata do fato (1) do prompt sobrevivendo a um reaperto que so copiou o
# percentual novo sem olhar o diff de cobertura.
mutante MCB4 "ramo/linha sem isencao tem que reprovar mesmo com o piso percentual OK" \
  "CB-ABS1: --check reprova mesmo com o piso percentual exato (reaperto preguicoso nao basta)" \
  troca '            status_abs = "NAO JUSTIFICADO: " + ", ".join(faltas)
            problema = True' \
        '            status_abs = "NAO JUSTIFICADO: " + ", ".join(faltas)
            problema = problema'

# MCB5 - camada 3 (completude de ALVOS): um candidato sem piso e sem exclusao e listado
# (COBCOMPL ainda e impresso) mas para de contar como motivo de reprovacao - o probe novo
# nasceria medido em 0% e no relatorio, mas `--check` sairia verde do mesmo jeito.
mutante MCB5 "candidato nao contabilizado tem que reprovar, nao so aparecer no relatorio" \
  "CB-COMPL2: --check reprova com um candidato nao contabilizado" \
  troca '    problema = True
    print("completude de ALVOS: candidato(s) sem piso e sem exclusao (aparece em silencio):")' \
        '    problema = problema
    print("completude de ALVOS: candidato(s) sem piso e sem exclusao (aparece em silencio):")'

# MCB6 - conferencia da ANCORA (quinto campo de ISENCOES): uma isencao cujo texto NAO bate
# com o fonte precisa ser RECUSADA, nunca aceita so pelo numero de linha. G67/A4: ate esta
# correcao nenhum mutante e nenhum caso de tests/unit/cobertura.sh exercitava este ramo -
# CB-ABS2 so escrevia isencoes de quatro campos, e o ramo da ancora nunca rodava.
mutante MCB6 "ancora divergente do fonte tem que RECUSAR a isencao, nao aceitar pelo numero" \
  "CB-ANCORA2: --check reprova quando a ancora nao bate com o fonte" \
  troca '                if achado != esperado:' \
        '                if False:'

cp -f "$TMP/orig.sh" "$ORIG"
echo
printf 'baseline=%s  mutantes_esperados=%s  mortos=%s  invalidos_ou_sobreviventes=%s\n' \
       "$BASELINE" "$EXPECTED_MUTANTS" "$P" "$F"
echo "================================================================"
if [ "$F" -ne 0 ]; then echo "mutacao VERMELHA: ha garantia que $REG nao protege"; exit 1; fi
if [ "$P" -ne "$EXPECTED_MUTANTS" ]; then
  echo "mutacao VERMELHA: $P mortos para $EXPECTED_MUTANTS mutantes - algum nao executou"; exit 1; fi
echo "mutacao verde: os $EXPECTED_MUTANTS mutantes morreram no caso-alvo correspondente"; exit 0
