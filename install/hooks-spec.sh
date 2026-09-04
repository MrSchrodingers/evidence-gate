#!/usr/bin/env bash
# FONTE UNICA da especificacao de hooks. Emite o bloco `hooks` em JSON, com o diretorio-base
# dos scripts como parametro.
#
# POR QUE ISOLADO. Existem hoje dois consumidores: `install/apply.sh`, que registra os hooks no
# `settings.json` de escopo de usuario, e `install/apply-managed.sh`, que os declara no
# `managed-settings.json` root-owned. Manter a lista em cada um seria DUAS COPIAS da mesma
# verdade, divergindo em silencio - o defeito que originou este repositorio (32 componentes
# ativos, 12 versionados) e que ja reapareceu como comentario obsoleto dentro de um hook.
# `tests/unit/managed.sh` exige que os dois consumidores produzam a MESMA estrutura, diferindo
# somente no caminho.
#
# ONDA 22d. O REGISTRADOR DE ATIVACAO ENTROU AQUI PORQUE ESTAVA FORA DAQUI. Ate 2026-08-26 os tres
# registros que alimentam /var/log/tollens-activation.jsonl eram programas `jq` escritos A MAO
# direto em /etc/claude-code/managed-settings.json, ausentes desta especificacao e de todos os
# backups da politica. Um `install/apply-managed.sh --enforce` - operacao normal, publicada no
# README - regenerou a politica a partir DESTA fonte e os apagou: 2 registradores antes, 0 depois,
# log parado as 17:32 contra enforce as 17:34, sem uma linha de erro. E `install/verify.sh:114`
# publica `ATIVACAO: INDICIO N evento(s)` lendo esse log, entao a afirmacao de governanca do
# repositorio dependia de um instrumento que aplicar o repositorio destruia.
#
# Uso: bash install/hooks-spec.sh <base>
#   <base> e string LITERAL embutida no JSON. Para o escopo de usuario e '$HOME/.claude/hooks',
#   com o `$HOME` deliberadamente NAO expandido aqui: quem expande e o runtime, no momento da
#   execucao. Para o escopo managed e um caminho absoluto root-owned.
set -uo pipefail
BASE="${1:?uso: hooks-spec.sh <diretorio-base-dos-hooks>}"

# SUBSTITUICAO POR jq, NAO POR sed (auditoria de 2026-08-04). A versao anterior fazia
# `sed "s|@BASE@|$BASE|g"` sobre o texto do JSON. Medido: um `$BASE` contendo aspas fecha a
# string e ABRE UM OBJETO NOVO, e o resultado continua sendo JSON VALIDO - de modo que o
# `jq -e .` do consumidor nao barra nada:
#
#   BASE='/x","timeout":1},{"type":"command","command":"id > /tmp/PWNED","z":"/y'
#   -> {"type":"command","command":"id > /tmp/PWNED","z":"/y/session-integrity.sh",...}
#
# E esse documento vira POLITICA em /etc/claude-code/managed-settings.json. Injecao de comando
# na politica, atraves do gerador da politica.
# Havia ainda corrupcao silenciosa: `&` no valor e expandido pelo sed como retrovisor.
#
# Com `--arg` o valor NUNCA e reparseado: entra como escalar e sai escapado pelo proprio jq.
# O heredoc segue nao-expansivel para que `$HOME` saia literal - quem o expande e o runtime.
command -v jq >/dev/null 2>&1 || { echo "hooks-spec: jq e obrigatorio" >&2; exit 1; }
cat <<'JSON' | jq --arg b "$BASE" \
  'walk(if type=="object" and has("command") then .command |= sub("@BASE@"; $b) else . end)'
{
  "SessionStart": [{"hooks":[{"type":"command","command":"bash @BASE@/session-integrity.sh","timeout":15}]}],
  "PreToolUse": [
    {"matcher":"Write|Edit|MultiEdit|NotebookEdit","hooks":[
      {"type":"command","command":"bash @BASE@/artifact-discipline.sh"},
      {"type":"command","command":"bash @BASE@/self-mod-audit.sh","timeout":5}]},
    {"matcher":"Agent|Task|Bash|Workflow","hooks":[
      {"type":"command","command":"bash @BASE@/fable-guard.sh","timeout":5}]},
    {"matcher":"Read","hooks":[
      {"type":"command","command":"bash @BASE@/read-budget.sh","timeout":10}]},
    {"matcher":"Skill","hooks":[
      {"type":"command","command":"bash @BASE@/activation-log.sh","timeout":5}]}
  ],
  "UserPromptSubmit": [{"hooks":[
      {"type":"command","command":"bash @BASE@/lentes.sh","timeout":5},
      {"type":"command","command":"bash @BASE@/ds4-notify.sh","timeout":5},
      {"type":"command","command":"bash @BASE@/graphify-scout-mode.sh","timeout":5}]}],
  "PostToolUse": [
    {"matcher":"Write|Edit|MultiEdit|NotebookEdit","hooks":[
      {"type":"command","command":"bash @BASE@/poka-yoke-lint.sh"},
      {"type":"command","command":"bash @BASE@/risk-trigger.sh"}]},
    {"matcher":"Bash","hooks":[
      {"type":"command","command":"bash @BASE@/output-budget.sh"}]}
  ],
  "Stop": [{"hooks":[
      {"type":"command","command":"bash @BASE@/verify-gate.sh","timeout":200},
      {"type":"command","command":"bash @BASE@/ds4-notify.sh","timeout":5}]}],
  "SubagentStop": [
    {"hooks":[{"type":"command","command":"bash @BASE@/subagent-probe.sh"}]},
    {"hooks":[{"type":"command","command":"bash @BASE@/subagent-contract.sh"}]},
    {"hooks":[{"type":"command","command":"bash @BASE@/ds4-notify.sh","timeout":5}]}
  ],
  "SubagentStart": [{"hooks":[
      {"type":"command","command":"bash @BASE@/subagent-probe.sh"},
      {"type":"command","command":"bash @BASE@/activation-log.sh","timeout":5}]}],
  "InstructionsLoaded": [{"hooks":[{"type":"command","command":"bash @BASE@/activation-log.sh","timeout":5}]}],
  "Notification": [{"hooks":[{"type":"command","command":"bash @BASE@/ds4-notify.sh","timeout":5}]}]
}
JSON
