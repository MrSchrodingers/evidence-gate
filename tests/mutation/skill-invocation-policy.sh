#!/usr/bin/env bash
# G102 (issue #46) considerou 4 mutantes novos para este arnes - registry.forge.activation
# mentindo "contextual" com frontmatter manual; remocao do graphify de
# activation.model_invocable_exceptions; registry.depreciar.activation fora do enum ("banana");
# e um controle de direcao (comentario inerte em SKILL.md). Os quatro foram VALIDADOS AD-HOC
# durante a correcao (backup/mutacao/execucao/restauracao manual de
# orchestration/registry.json, orchestration/skill-policy.json e
# execution/skills/graphify/SKILL.md) e os tres primeiros reprovam tests/unit/skill-invocation-policy.sh
# enquanto o quarto permanece verde - mas NAO foram incorporados a este arquivo. Acrescentar
# mutante aqui muda `EXPECTED_MUTANTS` e, por consequencia, a contagem publicada em
# docs/status.generated.md:54 (`skill-invocation-policy (auto) | 2 | ...`) - arquivo e script
# geradores fora do escopo de edicao autorizado nesta correcao. Decisao registrada em
# evidence/corpus/agente-x-defeito.json (G102): manter M1/M2, sem mutante dedicado ao defeito de
# FATO (campo `activation` mentiroso), ate que a regeneracao de docs/status.generated.md seja
# autorizada.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# TMPDIR DAS SUITES: esta suite nao toma o lock (por desenho), mas cria temporarios igual as
# outras. Sem esta linha ela continuaria escrevendo em `/tmp`, que e tmpfs com teto FIXO de
# inodes - a causa medida de tres travamentos da bancada num dia. Ver tests/lib/tmpdir.sh.
if [ -r "$(dirname "$0")/../lib/tmpdir.sh" ]; then
  . "$(dirname "$0")/../lib/tmpdir.sh"
  _tb="$(tollens_tmpdir_base 2>/dev/null || true)"
  [ -n "$_tb" ] && [ -d "$_tb" ] && [ -w "$_tb" ] && export TMPDIR="$_tb"
  unset _tb
fi
ORIG="execution/skills/prd-to-issues/SKILL.md"
SUITE="tests/unit/skill-invocation-policy.sh"
# shellcheck source=tests/lib/arena.sh
source tests/lib/arena.sh
P=0; F=0

bash "$SUITE" >/dev/null 2>&1 || { echo "BASELINE VERMELHO" >&2; exit 1; }
BAK="$(mktemp)"; cp "$ORIG" "$BAK"

# M1 removes the manual-only control but leaves the remote write intact.
sed -i '/^disable-model-invocation: true$/d' "$ORIG"
bash "$SUITE" >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then echo "  MORTO M1 - side-effect skill voltou ao routing automatico"; P=$((P+1)); else echo "  SOBREVIVEU M1"; F=$((F+1)); fi
cp "$BAK" "$ORIG"

# M2 inert control.
printf '\n<!-- inert-control -->\n' >> "$ORIG"
bash "$SUITE" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then echo "  CONTROLE M2 - mudanca inerte permanece verde"; P=$((P+1)); else echo "  DIVERGIU CONTROLE M2"; F=$((F+1)); fi
cp "$BAK" "$ORIG"; rm -f "$BAK"

echo "MUTANTES=$((P+F)) CORRETOS=$P DIVERGENTES=$F"
EXPECTED_MUTANTS=2
[ "$((P+F))" -eq "$EXPECTED_MUTANTS" ] || exit 1
[ "$F" -eq 0 ]
