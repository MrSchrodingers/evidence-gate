#!/usr/bin/env bash
set -euo pipefail
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

python3 orchestration/render.py --check
python3 orchestration/schedule.py --check
python3 tests/unit/governance-links.py
python3 tests/unit/methodology.py
python3 tests/mutation/methodology.py
python3 tests/unit/capability-conformance.py
bash tests/unit/repository-hygiene.sh
bash tests/unit/managed-root-trust.sh
# G103 (issue #47) - politica de risco->workflow, ver tests/unit/risk-policy.sh. Sem passo
# proprio no CI (o mesmo caminho ja usado por repository-hygiene.sh e managed-root-trust.sh
# acima, que tambem nao tem passo dedicado em verify-pr.yml/verify-push.yml).
bash tests/unit/risk-policy.sh

# G110 (issue #54) - ALCANCE DE ATOR, simetrico ao alcance de workflow que risk-policy.sh acima
# verifica. Ver tests/unit/guidance-projection.sh. Mesmo caminho sem passo proprio no CI.
bash tests/unit/guidance-projection.sh

# ONDA 18 - O RENDERER DO CORPUS, EXERCITADO NOS DOIS MODOS.
#
# `evidence/corpus/render.py` nasceu na onda 18 e a CAMADA 3 de `evidence/cobertura.sh` o pegou
# imediatamente: candidato Python sob `evidence/` sem piso e sem exclusao, "aparece em silencio".
# O mecanismo fez o que existe para fazer. O que falhou foi a verificacao LOCAL desta sessao, que
# nao rodava `evidence/cobertura.sh --check` - passo dedicado do workflow - e por isso fechou
# verde enquanto a CI reprovava.
#
# A saida NAO e mais uma entrada em ABSOLUTO_PENDENTE: a auditoria acabou de apontar que as
# justificativas de la envelheceram e nao expiram. O `main()` passa a ser executado aqui.
#
# IDEMPOTENCIA E A ASSERCAO QUE IMPORTA. `--update` recalcula o bloco derivado; sobre um corpus
# ja correto ele tem de nao mudar byte algum. Se mudar, o corpus estava estagnado - que e
# exatamente o defeito G11 - e o teste reprova em vez de silenciar a correcao.
python3 evidence/corpus/render.py >/dev/null
_cor="evidence/corpus/agente-x-defeito.json"
_antes="$(sha256sum "$_cor" | cut -d' ' -f1)"
python3 evidence/corpus/render.py --update >/dev/null
_depois="$(sha256sum "$_cor" | cut -d' ' -f1)"
if [ "$_antes" != "$_depois" ]; then
  echo "FAIL corpus: o bloco derivado estava estagnado - render.py --update o alterou." >&2
  echo "     Isso e o defeito G11 (frame declarado divergindo do observado), agora detectado." >&2
  exit 1
fi
echo "PASS render do corpus: dois modos executados, e --update e idempotente sobre corpus correto"

# ONDA 27 (G105/issue #49) - GERACAO DE PROJECOES DE AGENTE, NOS DOIS MODOS.
#
# ADR 0024 registrava, como decisao aceita, um renderizador com "modo de convergencia" que
# GERA as projecoes. `orchestration/render.py` nunca teve esse modo: era um verificador puro
# desde o commit inicial, e `--check` era inerte porque `p.parse_args()` descartava o
# namespace do argparse - as duas invocacoes produziam a MESMA saida e o MESMO exit code em
# qualquer estado de arvore. As dez projecoes em `.claude/agents/*.md` e `.codex/agents/*.toml`
# eram mantidas A MAO, contra o que o ADR e o comentario deste arquivo afirmavam.
#
# Este bloco roda sobre uma COPIA DESCARTAVEL em $TMPDIR, nunca na arvore de trabalho: editar a
# FONTE canonica e comparar as PROJECOES geradas e o unico jeito de provar PROPAGACAO, nao so
# existencia de arquivo (regra do repo: o teste nao pode ler e conferir o MESMO arquivo).
_g105_w="$(mktemp -d)"
trap 'rm -rf "$_g105_w"' EXIT
mkdir -p "$_g105_w/execution" "$_g105_w/.claude" "$_g105_w/.codex"
cp -r execution/agents "$_g105_w/execution/agents"
# execution/config/CLAUDE.md: fonte do DOMINIO da politica de risco (G103/issue #47) que
# orchestration/render.py passou a ler. Sem esta copia, a geracao reprova aqui com
# "RISK_POLICY_ERROR kernel ausente" antes mesmo de chegar as asserções de propagação de agente
# que este bloco existe para provar - defeito medido ao introduzir a checagem.
mkdir -p "$_g105_w/execution/config"
cp execution/config/CLAUDE.md "$_g105_w/execution/config/CLAUDE.md"
cp -r .claude/agents "$_g105_w/.claude/agents"
cp .claude/settings.json "$_g105_w/.claude/settings.json"
cp -r .codex/agents "$_g105_w/.codex/agents"
cp .codex/config.toml "$_g105_w/.codex/config.toml"
cp .codex/hooks.json "$_g105_w/.codex/hooks.json"
cp CLAUDE.md AGENTS.md "$_g105_w/"
cp -r orchestration "$_g105_w/orchestration"

# TOKEN UNICO GERADO EM RUNTIME (timestamp+PID): sem isso, um residuo de execucao anterior
# poderia casar por acidente e o teste passaria sem ter propagado nada nesta execucao.
_g105_tok="G105-$(date +%s)-$$"
sed -i "3s/\$/ ${_g105_tok}/" "$_g105_w/execution/agents/investigador.md"
grep -q "$_g105_tok" "$_g105_w/execution/agents/investigador.md" \
  || { echo "FAIL G105: setup do teste nao gravou o token na fonte da copia" >&2; exit 1; }

# PASSO 4: geracao (sem --check) a partir da copia editada. Exigir EXIT 0.
if ! python3 "$_g105_w/orchestration/render.py" >/dev/null; then
  echo "FAIL G105: geracao (orchestration/render.py, sem --check) deveria sair 0 apos editar" >&2
  echo "     so a fonte canonica; render.py continua verificador puro (nunca gera)." >&2
  exit 1
fi

# PASSO 5 (ASSERCAO PRINCIPAL): o token editado na fonte alcanca as DUAS projecoes.
grep -q "$_g105_tok" "$_g105_w/.claude/agents/investigador.md" \
  || { echo "FAIL G105: token da fonte nao propagou para .claude/agents/investigador.md" >&2; exit 1; }
grep -q "$_g105_tok" "$_g105_w/.codex/agents/investigador.toml" \
  || { echo "FAIL G105: token da fonte nao propagou para .codex/agents/investigador.toml" >&2; exit 1; }

# PASSO 6 (ASSERCAO DE NAO-PERDA): campos runtime-only sobrevivem a geracao. Sem isto, um
# gerador que reescreve a projecao so com os campos do canonico (e derruba permissionMode,
# maxTurns, sandbox_mode, model_reasoning_effort) passaria no passo 5 e destruiria configuracao
# real disfarcado de correcao.
grep -q "^permissionMode:" "$_g105_w/.claude/agents/investigador.md" \
  || { echo "FAIL G105: geracao apagou permissionMode: de .claude/agents/investigador.md" >&2; exit 1; }
grep -q "^maxTurns:" "$_g105_w/.claude/agents/investigador.md" \
  || { echo "FAIL G105: geracao apagou maxTurns: de .claude/agents/investigador.md" >&2; exit 1; }
grep -q '^sandbox_mode=' "$_g105_w/.codex/agents/investigador.toml" \
  || { echo "FAIL G105: geracao apagou sandbox_mode= de .codex/agents/investigador.toml" >&2; exit 1; }
grep -q '^model_reasoning_effort=' "$_g105_w/.codex/agents/investigador.toml" \
  || { echo "FAIL G105: geracao apagou model_reasoning_effort= de .codex/agents/investigador.toml" >&2; exit 1; }

# PASSO 7 (CASO NEGATIVO EXPLICITO): `color:` e canonico-only e NAO vaza para a projecao Claude
# - prova que a geracao e seletiva por regra declarada em registry.json, nao copia bruta do
# frontmatter inteiro.
if grep -q "^color:" "$_g105_w/.claude/agents/investigador.md"; then
  echo "FAIL G105: color: (canonico-only) vazou para a projecao Claude" >&2
  exit 1
fi

# PASSO 8 (VALOR NAO-UNIFORME): mata o gerador que hardcoda uma constante para todos os
# agentes. `revisor-frontend` e `refutador` sao as tres excecoes medidas (model e
# model_reasoning_effort); um gerador que emitisse "gpt-5.6"/"high" para todos passaria nos
# passos 5-7 e falha aqui.
grep -q 'model="gpt-5.6-terra"' "$_g105_w/.codex/agents/revisor-frontend.toml" \
  || { echo "FAIL G105: revisor-frontend deveria manter model=\"gpt-5.6-terra\" na projecao Codex" >&2; exit 1; }
grep -q 'model_reasoning_effort="xhigh"' "$_g105_w/.codex/agents/refutador.toml" \
  || { echo "FAIL G105: refutador deveria manter model_reasoning_effort=\"xhigh\" na projecao Codex" >&2; exit 1; }

# PASSO 9 (IDEMPOTENCIA): sha256 das 20 projecoes antes e depois de uma SEGUNDA geracao sem
# editar nada - mesmo criterio que o bloco do corpus acima ja usa, e que pega gerador
# nao-deterministico (ex.: ordem de dict/set na saida).
_g105_antes="$(cd "$_g105_w" && sha256sum .claude/agents/*.md .codex/agents/*.toml | sort)"
python3 "$_g105_w/orchestration/render.py" >/dev/null
_g105_depois="$(cd "$_g105_w" && sha256sum .claude/agents/*.md .codex/agents/*.toml | sort)"
if [ "$_g105_antes" != "$_g105_depois" ]; then
  echo "FAIL G105: segunda geracao sem editar nada mudou byte(s) das projecoes (nao-determinismo)" >&2
  exit 1
fi

# PASSO 10: `--check` deixou de ser inerte. Sobre a arvore recem-gerada, `--check` tem de sair
# 0; depois de mutar UM byte de uma projecao, `--check` tem de sair 1. Hoje (antes da correcao)
# as duas invocacoes davam a MESMA saida e o MESMO exit code em qualquer estado - este par e o
# que prova que deixaram de ser a mesma coisa duas vezes.
if ! python3 "$_g105_w/orchestration/render.py" --check >/dev/null; then
  echo "FAIL G105: --check deveria sair 0 sobre uma arvore recem-gerada" >&2
  exit 1
fi
printf 'x' >> "$_g105_w/.claude/agents/investigador.md"
if python3 "$_g105_w/orchestration/render.py" --check >/dev/null 2>&1; then
  echo "FAIL G105: --check deveria sair 1 apos mutar 1 byte de uma projecao gerada" >&2
  exit 1
fi

rm -rf "$_g105_w"
trap - EXIT
echo "PASS geracao de projecoes de agente: propagacao, nao-perda, seletividade, nao-uniformidade, idempotencia e --check nao-inerte"
