#!/usr/bin/env bash
# G102 (issue #46). Este arnes cobre a politica de invocacao de skill em tres direcoes: o
# controle manual-only removido (M1), uma mudanca inerte (M2, controle de direcao) e o defeito
# de FATO que G102 nomeia - o campo `activation` do registry mentindo sobre o frontmatter (M3).
#
# ERRATA (refutador da onda 27, F3). A versao anterior deste cabecalho justificava a AUSENCIA
# de M3 alegando que `docs/status.generated.md` e `scripts/status.sh` estavam "fora do escopo
# de edicao autorizado nesta correcao". A justificativa era falsa: o mesmo commit editou
# `docs/status.generated.md` tres vezes. O arquivo estava vetado aos SUBAGENTES da onda, nao a
# onda. M3 foi incorporado e a contagem publicada regenerada pelo gerador, nao digitada.
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

# M3 is the defect G102 actually names: registry.activation lying about the frontmatter.
# M1 only covers the frontmatter side; without M3 the arness never exercised the registry side.
REG="orchestration/registry.json"
RBAK="$(mktemp)"; cp "$REG" "$RBAK"
python3 - "$REG" <<'PYEOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding="utf-8"))
caps = d["capabilities"]
alvo = next(k for k, v in caps.items() if v.get("kind") == "skill" and v.get("activation") == "manual")
caps[alvo]["activation"] = "contextual"
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
open(p, "a", encoding="utf-8").write("\n")
PYEOF
bash "$SUITE" >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then echo "  MORTO M3 - registry mentindo sobre o frontmatter foi recusado"; P=$((P+1)); else echo "  SOBREVIVEU M3"; F=$((F+1)); fi
cp "$RBAK" "$REG"; rm -f "$RBAK"

echo "MUTANTES=$((P+F)) CORRETOS=$P DIVERGENTES=$F"
EXPECTED_MUTANTS=3
[ "$((P+F))" -eq "$EXPECTED_MUTANTS" ] || exit 1
[ "$F" -eq 0 ]
