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
