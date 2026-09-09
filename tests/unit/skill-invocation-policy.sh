#!/usr/bin/env bash
# Narrow policy oracle: the known GitHub-mutating workflow must be user-triggered, while a
# read-oriented skill remains eligible for routing. This is deliberately NOT a lexical classifier
# for every possible side effect; it protects the two decisions actually made by this PR.
#
# G102 (issue #46). `default_activation` nao tinha executor nem definicao operacional, e o campo
# `capabilities.<skill>.activation` de orchestration/registry.json nunca era conferido contra o
# frontmatter real das skills - chegou a divergir em 3 das 8 (depreciar, forge, prd-to-issues
# diziam "contextual" enquanto o SKILL.md de cada uma tem `disable-model-invocation: true`), sem
# que nada ficasse vermelho. Os checks abaixo fecham essa lacuna com DOIS lados independentes:
# o ESPERADO vem da PRESENCA de uma chave YAML em execution/skills/<n>/SKILL.md; o OBTIDO e um
# VALOR lido de orchestration/registry.json. Nenhum dos dois arquivos contem a string do outro.
#
# LIMITE DECLARADO, e ele e o que impede overclaim: isto fecha `PolicyDeclared != PolicyEnforced`
# na camada de ARTEFATO (os tres registros concordam entre si e com o vocabulario fechado da
# policy). Isto NAO mede E_A - nao observa se o runtime de fato roteou ou deixou de rotear uma
# skill. Ler isto como prova de ativacao repetiria G6a (ADR 0036): representacao do mecanismo
# nao e o fenomeno.
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
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

frontmatter(){ sed -n '1,/^---$/p' "$1"; }

ISSUES="execution/skills/prd-to-issues/SKILL.md"
GRAPH="execution/skills/graphify/SKILL.md"

chk "prd-to-issues exists" "$([ -f "$ISSUES" ] && echo sim)" sim
chk "prd-to-issues really contains the remote write this policy protects" \
    "$(grep -q 'gh issue create' "$ISSUES" && echo sim || echo nao)" sim
chk "prd-to-issues is manual-only" \
    "$(frontmatter "$ISSUES" | grep -c '^disable-model-invocation: true$' || true)" 1

# Negative control. The PR is not allowed to solve routing risk by disabling every Skill.
chk "graphify remains available to model routing" \
    "$(frontmatter "$GRAPH" | grep -c '^disable-model-invocation: true$' || true)" 0

# ------------------------------------------------------------------------------------------
# G102. VOCABULARIO FECHADO, lido da policy - nao hardcoded aqui, para que um `activation`
# fora do enum (M5: "banana") reprove por nome, e nao so por diferir do esperado.
VOCAB="$(jq -r '.activation.vocabulary[]' orchestration/skill-policy.json 2>/dev/null)"
chk "policy declara vocabulario de ativacao nao vazio" \
    "$([ -n "$VOCAB" ] && echo sim || echo nao)" sim

for d in execution/skills/*/; do
  n="$(basename "$d")"
  if frontmatter "$d/SKILL.md" | grep -q '^disable-model-invocation: true$'; then
    esperado=manual
  else
    esperado=contextual
  fi
  obtido="$(jq -r --arg n "$n" '.capabilities[$n].activation // "AUSENTE"' orchestration/registry.json)"

  # ASSERCAO PRINCIPAL. Os dois lados vem de arquivos diferentes: `esperado` da presenca de uma
  # chave de frontmatter em SKILL.md, `obtido` de um valor em registry.json.
  chk "activation declarada bate com o frontmatter: $n" "$obtido" "$esperado"

  # ENUM FECHADO. `obtido` tem de pertencer ao vocabulario declarado na policy - defesa contra
  # um valor que nao e nem "manual" nem "contextual" (M5).
  if printf '%s\n' "$VOCAB" | grep -qx "$obtido"; then enum_ok=sim; else enum_ok=nao; fi
  chk "activation pertence ao vocabulario fechado da policy: $n" "$enum_ok" sim

  # CRITERIO 2 DA ISSUE. Toda skill cujo efetivo (frontmatter) seja "contextual" precisa de
  # entrada em `activation.model_invocable_exceptions` com `reason` nao vazio - a excecao passa
  # a viver no artefato de politica, nao so no controle negativo do graphify abaixo.
  if [ "$esperado" = contextual ]; then
    reason="$(jq -r --arg n "$n" \
      '(.activation.model_invocable_exceptions // [])[] | select(.skill == $n) | .reason // ""' \
      orchestration/skill-policy.json)"
    if [ -n "$reason" ]; then exc_ok=sim; else exc_ok=nao; fi
    chk "excecao de ativacao por modelo declarada com reason: $n" "$exc_ok" sim
  fi
done

echo
printf 'PASS=%s FAIL=%s\n' "$P" "$F"
EXPECTED=26
[ "$P" -eq "$EXPECTED" ] || { echo "CONTAGEM INESPERADA: PASS=$P esperado=$EXPECTED" >&2; exit 1; }
[ "$F" -eq 0 ]
