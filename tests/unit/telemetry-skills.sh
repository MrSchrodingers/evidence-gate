#!/usr/bin/env bash
# ISSUE #53 (G109) - dois proxies textuais ruins substituindo o unico sinal estrutural.
#
# O script sob teste (evidence/telemetry/medir-skills.sh) tinha uma causa raiz com duas
# manifestacoes simetricas: presenca textual do nome vira proxy de invocacao (falso positivo),
# ausencia de registro vira proxy de nao-uso (falso negativo, porque a subtracao as cegas de
# TODO transcript de subagente descarta o unico canal estrutural confiavel). As duas juntas
# produzem a INVERSAO: a skill genuinamente invocada (so em subagente) e classificada como
# morta, e a nunca invocada (so mencionada em documento colado) aparece viva.
#
# CADA ASSERCAO ABAIXO VEM COM UM PAR DE CONTROLE cujo resultado esperado e DIFERENTE - regra
# explicita do prompt de delegacao. Sem o par, um `print` fixo passaria: A, C e D em especial
# sao grep de string na saida, e so viram teste real quando a saida MUDA com a entrada (T1, T2,
# T4, T5, T6 abaixo).
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
SCRIPT="$PWD/evidence/telemetry/medir-skills.sh"
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# escreve um SKILL.md minimo. $1=dir da skill $2=description $3=linha extra crua (opcional)
skillmd(){
  mkdir -p "$1"
  {
    echo '---'
    echo "name: $(basename "$1")"
    echo "description: $2"
    [ -n "${3:-}" ] && echo "$3"
    echo '---'
    echo
    echo "# $(basename "$1")"
  } > "$1/SKILL.md"
}

# extrai o campo NOMEADO ($3, ex.: "total") da linha da skill ($2) na tabela ($1).
# BUSCA POR NOME, nao por indice numerico: o schema de colunas MUDA entre o script antigo (6
# campos) e o corrigido (8 campos, "modelo(sub)" e "mencao" novos) - indice fixo leria a coluna
# errada num dos dois lados e o teste passaria pelo motivo errado (medido: com indice fixo em 6,
# "total" do script antigo lia na verdade a coluna "custo").
campo(){
  local saida="$1" skill="$2" col="$3"
  awk -v s="$skill" -v col="$col" '
    $1=="skill" { for (i=1;i<=NF;i++) if ($i==col) idx=i }
    $1==s { if (idx=="") print ""; else print $(idx+0); exit }
  ' <<<"$saida"
}

# ================================================================================================
echo "== FIXTURE BASE: skill-usada (tool_use SO em subagente) x skill-fantasma (SO mencao em prosa) =="
BASE="$T/base"
skillmd "$BASE/skills/skill-usada" "descricao de teste, skill usada"
skillmd "$BASE/skills/skill-fantasma" "descricao de teste, skill fantasma"
mkdir -p "$BASE/proj/subagents" "$BASE/proj/sess-main" "$BASE/artbase"
echo '{}' > "$BASE/artmap.json"
cat > "$BASE/proj/subagents/b.jsonl" <<'JSONL'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Skill","input":{"skill":"skill-usada"}}]}}
JSONL
cat > "$BASE/proj/sess-main/c.jsonl" <<'JSONL'
{"type":"user","userType":"external","message":{"role":"user","content":"O hook injeta o nudge 'ORIENTE por /skill-fantasma query <tema>' antes de decidir."}}
JSONL

OUT1="$(bash "$SCRIPT" "$BASE/proj" "$BASE/skills" "$BASE/artmap.json" "$BASE/artbase" 2>&1)"
echo "$OUT1" | sed 's/^/    /'

# A - o recorte de subagentes e DECLARADO na saida (n e fracao)
chk "A: cabecalho declara recorte principais/subagente com fracao calculada" \
    "$(echo "$OUT1" | grep -qE 'total = [0-9]+ principais \+ [0-9]+ de subagente \([0-9]+%\)' && echo sim || echo nao)" sim

# T1 - CONTROLE de A: o numero declarado tem de ser FUNCAO do corpus, nao string impressa.
# Medido contra o script antigo: triplicar os transcripts de subagente NAO mudava a saida
# ("transcripts varridos: 2" identico nas duas execucoes) - por isso esta assercao discrimina.
T1DIR="$T/t1"; mkdir -p "$T1DIR/proj/subagents" "$T1DIR/skills" "$T1DIR/artbase"
skillmd "$T1DIR/skills/skill-x" "descricao de teste"
echo '{}' > "$T1DIR/artmap.json"
cp "$BASE/proj/subagents/b.jsonl" "$T1DIR/proj/subagents/b.jsonl"
OUT_T1A="$(bash "$SCRIPT" "$T1DIR/proj" "$T1DIR/skills" "$T1DIR/artmap.json" "$T1DIR/artbase" 2>&1)"
N1="$(echo "$OUT_T1A" | grep -oE '\+ [0-9]+ de subagente' | grep -oE '[0-9]+')"
cp "$T1DIR/proj/subagents/b.jsonl" "$T1DIR/proj/subagents/b2.jsonl"
cp "$T1DIR/proj/subagents/b.jsonl" "$T1DIR/proj/subagents/b3.jsonl"
OUT_T1B="$(bash "$SCRIPT" "$T1DIR/proj" "$T1DIR/skills" "$T1DIR/artmap.json" "$T1DIR/artbase" 2>&1)"
N2="$(echo "$OUT_T1B" | grep -oE '\+ [0-9]+ de subagente' | grep -oE '[0-9]+')"
REAL="$(ls "$T1DIR/proj/subagents" | wc -l | tr -d ' ')"
chk "T1a: 1 arquivo de subagente -> denominador declarado = 1" "${N1:-x}" 1
chk "T1b: apos triplicar (real=$REAL no disco), o denominador declarado muda para 3" "${N2:-x}" 3

# B - skill usada SO em subagente NAO e candidata a depreciacao nem aparece como zero-uso
TOTU="$(campo "$OUT1" skill-usada total)"
chk "B1: skill-usada (invocada so em subagente) tem total > 0" \
    "$([ "${TOTU:-0}" -gt 0 ] 2>/dev/null && echo sim || echo nao)" sim
chk "B2: skill-usada NAO aparece na listagem de zero-uso" \
    "$(grep -c '  skill-usada:' <<<"$OUT1")" 0

# E - mencao em prosa (sem marcador estrutural) NAO conta como uso no total
TOTF="$(campo "$OUT1" skill-fantasma total)"
chk "E1: skill-fantasma (so mencionada em prosa) tem total == 0" "${TOTF:-x}" 0
MENF="$(campo "$OUT1" skill-fantasma mencao)"
chk "E2: a mencao em prosa E capturada em coluna separada (rotulada, nao descartada)" \
    "$([ "${MENF:-0}" -gt 0 ] 2>/dev/null && echo sim || echo nao)" sim

# T2 - CONTROLE de A/B/E: a classificacao DISCRIMINA. Nenhuma string fixa satisfaz isto sem
# o script ler de fato o plano de subagente - medido contra o script antigo, as duas fixtures
# minimas recebiam "ZERO USO" identico.
chk "T2: skill-usada e skill-fantasma tem total DIFERENTE (classificacao discrimina)" \
    "$([ "$TOTU" != "$TOTF" ] && echo dif || echo igual)" dif

# C / C2 - zero uso SEM denominador (artefato nao mapeado): ROUTING/OPPORTUNITY UNRESOLVED,
# nunca CANDIDATA A DEPRECIACAO
chk "C: zero uso sem denominador imprime ROUTING/OPPORTUNITY UNRESOLVED" \
    "$(grep -q 'ROUTING/OPPORTUNITY UNRESOLVED' <<<"$OUT1" && echo sim || echo nao)" sim
chk "C2: nao afirma CANDIDATAS A DEPRECIACAO sem denominador estimado" \
    "$(grep -c 'CANDIDATAS A DEPRECIACAO' <<<"$OUT1")" 0

# ================================================================================================
echo "== T4/T5: ressalva (c) - rotulo e a linha do artefato sao FUNCAO do disco, nao string fixa =="
T4="$T/t4"; mkdir -p "$T4/skills/skill-obscura" "$T4/proj" "$T4/artbase_com" "$T4/artbase_sem"
skillmd "$T4/skills/skill-obscura" "descricao de teste, nunca invocada em canal nenhum"
touch "$T4/proj/.keep"   # nenhum transcript -> zero uso garantido, sem ruido de outro canal
echo '{}' > "$T4/semmapa.json"
echo '{"skill-obscura":"artefato.txt"}' > "$T4/commapa.json"
echo "conteudo" > "$T4/artbase_com/artefato.txt"
# artbase_sem fica vazio de proposito - mesmo mapa, disco diferente

OUT_UNRES="$(bash "$SCRIPT" "$T4/proj" "$T4/skills" "$T4/semmapa.json" "$T4/artbase_com" 2>&1)"
OUT_ENC="$(bash "$SCRIPT" "$T4/proj" "$T4/skills" "$T4/commapa.json" "$T4/artbase_com" 2>&1)"
OUT_AUS="$(bash "$SCRIPT" "$T4/proj" "$T4/skills" "$T4/commapa.json" "$T4/artbase_sem" 2>&1)"

chk "T4a: sem mapeamento -> ROUTING/OPPORTUNITY UNRESOLVED" \
    "$(grep -q 'ROUTING/OPPORTUNITY UNRESOLVED' <<<"$OUT_UNRES" && echo sim || echo nao)" sim
chk "T4b: mapeado+PRESENTE produz rotulo DIFERENTE de sem-mapeamento (mesma skill, mesmo transcript)" \
    "$([ "$(grep 'skill-obscura' <<<"$OUT_UNRES" | tail -1)" != "$(grep 'skill-obscura' <<<"$OUT_ENC" | tail -1)" ] \
       && echo dif || echo igual)" dif
chk "T5a: artefato ENCONTRADO no disco aparece na saida" \
    "$(grep -q 'encontrado' <<<"$OUT_ENC" && echo sim || echo nao)" sim
chk "T5b: artefato AUSENTE no disco aparece na saida (mesma skill, mesmo transcript, disco diferente)" \
    "$(grep -q 'ausente' <<<"$OUT_AUS" && echo sim || echo nao)" sim
chk "T5c: CONTROLE - encontrado e ausente produzem saidas DIFERENTES (o script toca o disco de fato)" \
    "$([ "$OUT_ENC" != "$OUT_AUS" ] && echo dif || echo igual)" dif
chk "D1: artefato mapeado e AUSENTE estima o denominador -> skill VIRA candidata (rotulo alcancavel)" \
    "$(grep -q 'CANDIDATAS A DEPRECIACAO' <<<"$OUT_AUS" && grep -q 'skill-obscura' <<<"$OUT_AUS" && echo sim || echo nao)" sim
chk "D2: artefato ENCONTRADO rebaixa (uso possivel fora do canal medido), NAO vira candidata" \
    "$(grep -q 'CANDIDATAS A DEPRECIACAO' <<<"$OUT_ENC" && echo sim || echo nao)" nao

# ================================================================================================
echo "== T6: disable-model-invocation nao pode virar 'falha de roteamento' identica a outro zero =="
T6="$T/t6"; mkdir -p "$T6/skills/skill-manual" "$T6/skills/skill-comum" "$T6/proj" "$T6/artbase"
skillmd "$T6/skills/skill-manual" "descricao de teste, manual" "disable-model-invocation: true"
skillmd "$T6/skills/skill-comum" "descricao de teste, comum"
touch "$T6/proj/.keep"
echo '{}' > "$T6/semmapa.json"
OUT_T6="$(bash "$SCRIPT" "$T6/proj" "$T6/skills" "$T6/semmapa.json" "$T6/artbase" 2>&1)"
ROWM="$(grep '^skill-manual ' <<<"$OUT_T6")"
ROWC="$(grep '^skill-comum ' <<<"$OUT_T6")"
chk "T6a: skill-manual (modelo=0 por config) e skill-comum (modelo=0 sem config) tem linha DIFERENTE" \
    "$([ "$ROWM" != "$ROWC" ] && echo dif || echo igual)" dif
chk "T6b: a marcacao de skill-manual cita a configuracao, nao 'ZERO USO' generico" \
    "$(grep -q 'disable-model-invocation' <<<"$ROWM" && echo sim || echo nao)" sim

# ================================================================================================
echo "== guardas minimas do canal fraco (1.3): tamanho e bloco de codigo =="
# os dois falsos positivos MEDIDOS na issue tinham 104588 e 49303 caracteres. CONTROLE: o mesmo
# nome, em documento pequeno (fixture base acima, ~130 caracteres), CONTA como mencao - sem o
# controle, um filtro que sempre zera passaria aqui pelo motivo errado.
GBIG="$T/gbig"; mkdir -p "$GBIG/skills/skill-fantasma" "$GBIG/proj/sess-main" "$GBIG/artbase"
skillmd "$GBIG/skills/skill-fantasma" "descricao de teste"
echo '{}' > "$GBIG/artmap.json"
python3 - "$GBIG/proj/sess-main/big.jsonl" <<'PY'
import json, sys
txt = "x" * 9000 + " /skill-fantasma " + "y" * 100
open(sys.argv[1], "w").write(json.dumps(
    {"type": "user", "userType": "external", "message": {"role": "user", "content": txt}}) + "\n")
PY
OUT_GBIG="$(bash "$SCRIPT" "$GBIG/proj" "$GBIG/skills" "$GBIG/artmap.json" "$GBIG/artbase" 2>&1)"
MENGBIG="$(campo "$OUT_GBIG" skill-fantasma mencao)"
chk "guarda de tamanho: documento gigante (9000+ chars) nao conta nem como mencao fraca" \
    "${MENGBIG:-x}" 0
chk "  CONTROLE: a mesma mencao, em documento pequeno (fixture base), CONTA (ja verificado em E2)" \
    "$([ "${MENF:-0}" -gt 0 ] 2>/dev/null && echo sim || echo nao)" sim

GCB="$T/gcb"; mkdir -p "$GCB/skills/skill-fantasma" "$GCB/proj/sess-main" "$GCB/artbase"
skillmd "$GCB/skills/skill-fantasma" "descricao de teste"
echo '{}' > "$GCB/artmap.json"
python3 - "$GCB/proj/sess-main/cb.jsonl" <<'PY'
import json, sys
txt = "antes ```\ncodigo com /skill-fantasma dentro do bloco\n``` depois"
open(sys.argv[1], "w").write(json.dumps(
    {"type": "user", "userType": "external", "message": {"role": "user", "content": txt}}) + "\n")
PY
OUT_GCB="$(bash "$SCRIPT" "$GCB/proj" "$GCB/skills" "$GCB/artmap.json" "$GCB/artbase" 2>&1)"
MENGCB="$(campo "$OUT_GCB" skill-fantasma mencao)"
chk "guarda de bloco de codigo: mencao DENTRO de bloco de codigo nao conta" "${MENGCB:-x}" 0

# ================================================================================================
echo "== defeito adjacente (plano 1.7): a mensagem de uso aponta para o caminho real =="
chk "1.7: 'Uso:' cita evidence/telemetry/medir-skills.sh, nao scripts/medir-skills.sh" \
    "$(grep -c 'Uso: bash evidence/telemetry/medir-skills.sh' "$SCRIPT")" 1

echo
echo "================ PASS=$P  FAIL=$F ================"
EXPECTED=23
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
[ "$F" -eq 0 ] && echo "telemetry-skills verde ($P/$EXPECTED)" || echo "telemetry-skills VERMELHO"
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
