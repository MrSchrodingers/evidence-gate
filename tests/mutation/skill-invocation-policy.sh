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
#
# G106 (issue #50), onda 28. M1-M3 cobrem ATIVACAO; nada aqui cobria EFEITO. M4, M5 e M6 fecham
# essa lacuna, e a CONSTRUCAO importa mais que a contagem (criterio 5 da issue):
#
#   M4  skill FICTICIA (nome novo, forma de escrita remota DIFERENTE de `gh issue create`),
#       declarada `pure`, `contextual`, com registro e excecao CONSISTENTES em tudo - so o
#       efeito mente. Sem essa preparacao completa o mutante morreria por "activation ...
#       got=AUSENTE" ou por falta de excecao/registro - pelo motivo ERRADO, provando que o
#       oraculo conhece NOME em vez de CLASSE. Por isso o teste abaixo confere a MENSAGEM da
#       assercao que matou o mutante, nao so o `rc`.
#   M5  skill ficticia declarada `remote-write`, corpo SEM string reconhecivel, `contextual`.
#       Morre pelo bloco (b) (invariante de classe) e nao pelo (c) (deteccao sintatica) -
#       prova de que a CLASSE vem da DECLARACAO, nao do detector.
#   M6  regressao literal de G106: `gh issue create` de volta no corpo de write-a-prd, agora
#       declarado `local-write`. Morre pelo bloco (c).
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

# ------------------------------------------------------------------------------------------
# M4 (G106, criterio 5 da issue #50). Skill FICTICIA - nome novo (`publicar-relatorio`), forma
# de escrita remota DIFERENTE de `gh issue create` (`curl -X POST`) - declarada `pure`,
# registrada `contextual` com excecao e `reason` no lugar certo: CONSISTENTE em toda dimensao
# que os blocos (a) e a excecao ja conferiam, e falsa SO no efeito. A verificacao abaixo confere
# a MENSAGEM que matou o mutante (bloco (c)), nao so o exit code - medido nesta investigacao que
# um M4 preparado pela metade morre por motivos ERRADOS ("got=AUSENTE"/"got=nao" nas checagens
# de ativacao/registro/excecao), o que provaria o oraculo antigo, nao a invariante nova.
POLICY="orchestration/skill-policy.json"
REG2="orchestration/registry.json"
FAKE="execution/skills/publicar-relatorio"
POL_BAK="$(mktemp)"; cp "$POLICY" "$POL_BAK"
REG2_BAK="$(mktemp)"; cp "$REG2" "$REG2_BAK"
mkdir -p "$FAKE"
cat > "$FAKE/SKILL.md" <<'SKILLEOF'
---
name: publicar-relatorio
description: skill ficticia de arnes de mutacao (M4/G106), nao instalar.
---

# /publicar-relatorio (ficticia - existe so para este arnes)

Publica metrica agregada num endpoint de terceiros.

    curl -X POST https://metrics.example.internal/v1/reports -d @relatorio.json
SKILLEOF
python3 - "$POLICY" "$REG2" <<'PYEOF'
import json, sys
pol_path, reg_path = sys.argv[1], sys.argv[2]
pol = json.load(open(pol_path, encoding="utf-8"))
pol["effects"]["by_skill"]["publicar-relatorio"] = "pure"
pol["activation"]["model_invocable_exceptions"].append({
    "skill": "publicar-relatorio",
    "reason": "skill ficticia de arnes de mutacao (M4): consistente em ativacao, registro e "
              "excecao - so o efeito mente.",
    "ref": "execution/skills/publicar-relatorio/SKILL.md",
})
json.dump(pol, open(pol_path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
open(pol_path, "a", encoding="utf-8").write("\n")
reg = json.load(open(reg_path, encoding="utf-8"))
reg["capabilities"]["publicar-relatorio"] = {
    "kind": "skill",
    "source": "execution/skills/publicar-relatorio",
    "state": "quarantine",
    "installed": False,
    "activation": "contextual",
    "evidence": {"dossier": None, "status": "absent", "dimensions": {}},
    "projection": "user",
}
json.dump(reg, open(reg_path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
open(reg_path, "a", encoding="utf-8").write("\n")
PYEOF
saida="$(bash "$SUITE" 2>&1)"
rc=$?
if [ "$rc" -ne 0 ] && printf '%s\n' "$saida" \
    | grep -q 'corpo com padrao de escrita remota exige efeito >= remote-write: publicar-relatorio'; then
  echo "  MORTO M4 - skill ficticia com forma de escrita remota diferente, declarada pure, recusada pelo bloco (c)"
  P=$((P+1))
else
  echo "  SOBREVIVEU M4, ou morreu pelo motivo errado (mensagem do bloco (c) ausente da saida):"
  printf '%s\n' "$saida" | grep -i publicar-relatorio | sed 's/^/    /'
  F=$((F+1))
fi
rm -rf "$FAKE"
cp "$POL_BAK" "$POLICY"; rm -f "$POL_BAK"
cp "$REG2_BAK" "$REG2"; rm -f "$REG2_BAK"

# ------------------------------------------------------------------------------------------
# M5 (G106). Skill ficticia declarada `remote-write`, corpo SEM NENHUMA string reconhecivel
# pelo detector sintatico, `contextual`. Tem de morrer pelo bloco (b) - a invariante de classe -,
# nunca pelo (c), porque nao ha padrao algum a casar. Esta e a prova de que a CLASSE de uma
# skill vem da DECLARACAO em `effects.by_skill`, e o detector sintatico do bloco (c) e apenas
# um auditor que pode agravar a declaracao, nunca a base sob a qual ela e julgada.
FAKE5="execution/skills/sincronizar-crm"
POL_BAK5="$(mktemp)"; cp "$POLICY" "$POL_BAK5"
REG2_BAK5="$(mktemp)"; cp "$REG2" "$REG2_BAK5"
mkdir -p "$FAKE5"
cat > "$FAKE5/SKILL.md" <<'SKILLEOF'
---
name: sincronizar-crm
description: skill ficticia de arnes de mutacao (M5/G106), nao instalar.
---

# /sincronizar-crm (ficticia - existe so para este arnes)

Mantem dois sistemas alinhados. Nenhum comando, nenhuma chamada, nenhuma string reconhecivel
pelo detector sintatico de escrita remota - so prosa.
SKILLEOF
python3 - "$POLICY" "$REG2" <<'PYEOF'
import json, sys
pol_path, reg_path = sys.argv[1], sys.argv[2]
pol = json.load(open(pol_path, encoding="utf-8"))
pol["effects"]["by_skill"]["sincronizar-crm"] = "remote-write"
pol["activation"]["model_invocable_exceptions"].append({
    "skill": "sincronizar-crm",
    "reason": "skill ficticia de arnes de mutacao (M5): consistente em ativacao, registro e "
              "excecao - so o efeito declarado viola a invariante de classe.",
    "ref": "execution/skills/sincronizar-crm/SKILL.md",
})
json.dump(pol, open(pol_path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
open(pol_path, "a", encoding="utf-8").write("\n")
reg = json.load(open(reg_path, encoding="utf-8"))
reg["capabilities"]["sincronizar-crm"] = {
    "kind": "skill",
    "source": "execution/skills/sincronizar-crm",
    "state": "quarantine",
    "installed": False,
    "activation": "contextual",
    "evidence": {"dossier": None, "status": "absent", "dimensions": {}},
    "projection": "user",
}
json.dump(reg, open(reg_path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
open(reg_path, "a", encoding="utf-8").write("\n")
PYEOF
saida="$(bash "$SUITE" 2>&1)"
rc=$?
if [ "$rc" -ne 0 ] && printf '%s\n' "$saida" \
    | grep -q 'invariante efeito remoto => activation!=contextual: sincronizar-crm'; then
  echo "  MORTO M5 - efeito remote-write com activation=contextual recusado pelo bloco (b), sem padrao sintatico algum"
  P=$((P+1))
else
  echo "  SOBREVIVEU M5, ou morreu pelo motivo errado (mensagem do bloco (b) ausente da saida):"
  printf '%s\n' "$saida" | grep -i sincronizar-crm | sed 's/^/    /'
  F=$((F+1))
fi
rm -rf "$FAKE5"
cp "$POL_BAK5" "$POLICY"; rm -f "$POL_BAK5"
cp "$REG2_BAK5" "$REG2"; rm -f "$REG2_BAK5"

# ------------------------------------------------------------------------------------------
# M6 (regressao de G106). `gh issue create` de volta no corpo de write-a-prd, que apos a
# correcao esta declarado `local-write`. Tem de morrer pelo bloco (c): efeito declarado abaixo
# de `remote-write` com o corpo evidenciando escrita remota.
WAP="execution/skills/write-a-prd/SKILL.md"
WAP_BAK="$(mktemp)"; cp "$WAP" "$WAP_BAK"
printf '\nRegressao M6: publique o PRD assim que terminar usando `gh issue create`.\n' >> "$WAP"
saida="$(bash "$SUITE" 2>&1)"
rc=$?
if [ "$rc" -ne 0 ] && printf '%s\n' "$saida" \
    | grep -q 'corpo com padrao de escrita remota exige efeito >= remote-write: write-a-prd'; then
  echo "  MORTO M6 - regressao de gh issue create em write-a-prd (local-write) recusada pelo bloco (c)"
  P=$((P+1))
else
  echo "  SOBREVIVEU M6, ou morreu pelo motivo errado:"
  printf '%s\n' "$saida" | grep -i write-a-prd | sed 's/^/    /'
  F=$((F+1))
fi
cp "$WAP_BAK" "$WAP"; rm -f "$WAP_BAK"

echo "MUTANTES=$((P+F)) CORRETOS=$P DIVERGENTES=$F"
EXPECTED_MUTANTS=6
[ "$((P+F))" -eq "$EXPECTED_MUTANTS" ] || exit 1
[ "$F" -eq 0 ]
