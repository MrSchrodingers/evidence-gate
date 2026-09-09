#!/usr/bin/env bash
# graphify-scout-mode.sh - UserPromptSubmit hook (non-blocking).
# Nudges efficient, robust, quality use of the graphify knowledge graph as a
# cheap orientation SCOUT (never an oracle). Always exits 0; never blocks a prompt.
# Companion to the graphify skill (kept out of the vendored SKILL.md so it
# survives graphify upgrades). See ~/.claude/CLAUDE.md secao 9 (ferramentas).
set +e

# Este hook e uma co-variavel de routing, nao ambiente neutro: stdout de UserPromptSubmit chega
# ao modelo como contexto (docs/method/CONHECIMENTO.md secao 4), em paralelo a description da
# skill graphify. O braco A_router_puro de um E_A (orchestration/evaluation-protocol.json,
# routing_covariates) exige este nudge desligado, sem editar o arquivo a mao; a variavel
# TOLLENS_ROUTING_NUDGES=off e o desligamento mecanico. Portao antes de qualquer leitura de
# disco, para que o silencio seja atribuivel a variavel e nao a ausencia de graphify.
case "${TOLLENS_ROUTING_NUDGES:-on}" in off|0|false) exit 0 ;; esac

DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
GRAPH="$DIR/graphify-out/graph.json"

# graphify e opcional e NAO e redistribuida com o plugin (skill de terceiro). Sem ela
# instalada, este hook fica calado: sugerir `graphify extract` a quem nao tem o binario
# nem a skill e ruido que o usuario nao pode acionar. Verificado em tempo de execucao.
if ! command -v graphify >/dev/null 2>&1 \
   && [ ! -f "$HOME/.claude/skills/graphify/SKILL.md" ] \
   && [ ! -f "$GRAPH" ]; then
  exit 0
fi

# Only speak inside a code repo; stay silent for non-repos and trivial dirs.
is_repo=0
if [ -d "$DIR/.git" ] || [ -d "$DIR/backend" ] || [ -d "$DIR/src" ] || [ -d "$DIR/frontend" ]; then
  is_repo=1
fi

if [ -f "$GRAPH" ]; then
  msg="[GRAFO] graphify-out/graph.json existe. Tarefa nao-trivial: ORIENTE por /graphify query \"<tema>\" ou /graphify explain \"<simbolo>\" (fast-path, sem rebuild) antes de fan-out de grep/read - acha hotspots/call-sites/blast-radius. GUARDRAIL: grafo e BATEDOR, nao oraculo (AST nao ve dispatch dinamico; semantica e LLM). Todo sinal e HIPOTESE a verificar no codigo real. Fresco: /graphify . --update."
  # Staleness hint: graph built at a different commit than current HEAD.
  if [ "$is_repo" = 1 ]; then
    head_sha="$(git -C "$DIR" rev-parse HEAD 2>/dev/null)"
    built_sha="$(grep -o '"built_at_commit"[[:space:]]*:[[:space:]]*"[0-9a-f]*"' "$GRAPH" 2>/dev/null | grep -o '[0-9a-f]\{7,40\}' | head -1)"
    if [ -n "$head_sha" ] && [ -n "$built_sha" ] && [ "$head_sha" != "$built_sha" ]; then
      msg="$msg AVISO STALE: grafo construido em $built_sha != HEAD atual - rode /graphify . --update antes de confiar no mapa."
    fi
  fi
  printf '%s\n' "$msg"
elif [ "$is_repo" = 1 ]; then
  printf '%s\n' "[GRAFO] Repo sem knowledge graph. Para orientacao de CODIGO (otimizacao/refactor/auditoria/exploracao ampla), construa o mapa SO-CODIGO com 'graphify extract . --code-only' (AST, sem LLM, sem API key, gratis) - ja da god-nodes/blast-radius/call-graph; reserve o '/graphify . --directed' completo (semantico, caro: ~milhoes de tokens) so p/ mapear docs/rationale. Depois oriente por /graphify query. Grafo e batedor, nao oraculo: verifique no codigo."
fi

exit 0
