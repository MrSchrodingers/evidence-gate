#!/usr/bin/env bash
set -euo pipefail
# TMPDIR DAS SUITES: esta suite nao toma o lock (por desenho), mas cria temporarios igual as
# outras. Sem esta linha ela continuaria escrevendo em `/tmp`, que e tmpfs com teto FIXO de
# inodes - a causa medida de tres travamentos da bancada num dia. Ver tests/lib/tmpdir.sh.
if [ -r "$(dirname "$0")/../lib/tmpdir.sh" ]; then
  . "$(dirname "$0")/../lib/tmpdir.sh"
  _tb="$(tollens_tmpdir_base 2>/dev/null || true)"
  [ -n "$_tb" ] && [ -d "$_tb" ] && [ -w "$_tb" ] && export TMPDIR="$_tb"
  unset _tb
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail=0

for path in \
  logitech-flow-kvm package.json quebrado.py servico.js solto.py \
  .bootstrap .bootstrap-trigger .materialize-trigger \
  .github/workflows/materialize-multiruntime.yml \
  .github/workflows/export-source.yml; do
  if [[ -e "$path" ]]; then
    echo "FAIL legado/transport temporario presente: $path"
    fail=1
  fi
done

allowed_root='^(\.agents|\.claude|\.claude-plugin|\.codex|\.git|\.github|\.gitignore|AGENTS\.md|CLAUDE\.md|CONTRIBUTING\.md|LICENSE|README\.md|README\.pt-BR\.md|SECURITY\.md|control|docs|evidence|execution|install|orchestration|scripts|tests)$'
# RESIDUO IGNORADO PELO GIT NAO E ENTRADA NAO DECLARADA.
#
# Este laco varre o FILESYSTEM, nao o indice do git. Ate 2026-08-10 ele reprovava em
# `.mypy_cache` e `.ruff_cache` - que o proprio `.gitignore` deste repo declara nas linhas 7-8.
# Consequencia medida: qualquer maquina que tivesse rodado a suite (ruff cria o cache) nao
# conseguia mais rodar este teste. Na CI passava por ORDEM, nao por desenho: `runtime-ports`
# roda antes dos casos que invocam ruff. Verde por acidente de sequencia e o modo de falha que
# este repositorio existe para nao ter.
#
# A intencao original permanece intacta: os arquivos-lixo da lista acima (`quebrado.py`,
# `solto.py`, `servico.js`, gatilhos de transporte) NAO estao no `.gitignore` e continuam
# reprovando. O que passa a ser tolerado e exclusivamente o que o repositorio ja declarou
# como residuo de ferramenta.
# A TOLERANCIA VALE SO PARA O `.gitignore` VERSIONADO.
#
# `git check-ignore` honra tres fontes: `.gitignore` (versionado), `.git/info/exclude` e
# `core.excludesFile` global. As duas ultimas NAO sao versionadas e nao aparecem em diff nenhum -
# entao a versao anterior desta funcao podia ser neutralizada por um canal que nenhum revisor ve.
# Medido: `echo "payload/" >> .git/info/exclude` fazia o teste inteiro passar (exit 0) com um
# diretorio nao declarado na raiz. Achado do portao final.
#
# `-v` reporta a FONTE da regra que casou; exigir que seja `.gitignore` fecha os outros dois
# canais sem perder a correcao do falso positivo, porque o que se quer tolerar - residuo de
# ferramenta - esta declarado no arquivo versionado, onde a decisao e revisavel.
# O EXIT CODE TAMBEM, e nao so a fonte. Medido pelo portao final da onda 10: `git check-ignore -v`
# imprime a regra que CASOU, inclusive quando ela e uma NEGACAO (`!padrao`) - e negacao significa
# exatamente "NAO ignore isto". A versao anterior lia so a fonte da linha e descartava o exit
# code, entao uma unica linha `!backdoor/` no .gitignore fazia o portao tratar lixo nao ignorado
# como "residuo tolerado": controle sem a linha reprovava (exit 1), com a linha passava (exit 0),
# e o `git status` continuava mostrando `?? backdoor/`.
#
# Isso falsificava a frase que justificou remover a isencao de mascara neste mesmo arquivo -
# "nao cria classe isentavel nenhuma". Criava, em uma linha, e o predicado se chama `ignorado`.
# Terceira correcao consecutiva nesta regiao; por isso o predicado agora exige as DUAS condicoes
# e recusa padrao de negacao explicitamente, em vez de mais uma emenda em cima.
ignorado(){
  local v
  v="$(git check-ignore -v -- "$1" 2>/dev/null)" || return 1   # exit != 0: git NAO ignora
  [ "${v%%:*}" = ".gitignore" ] || return 1                    # fonte tem de ser o arquivo versionado
  case "${v#*:*:}" in '!'*) return 1 ;; esac                   # padrao de negacao nunca isenta
  return 0
}
# MASCARA DO RUNTIME - POR QUE NAO HA ISENCAO AQUI, e por que houve uma por algumas horas.
#
# Rodando dentro do Claude Code, `find` na raiz devolve `.mcp.json` como CHARACTER SPECIAL FILE:
# o runtime monta 176 bind mounts sobre arquivos de configuracao no namespace da sessao. Nove
# caminhos desta arvore estao nessa condicao. Eles nao existem em disco e somem com a sessao, e
# sem tratamento a suite dava FALSO VERMELHO para qualquer pessoa que a rodasse de dentro do
# agente - foi o que aconteceu, e ainda arrastou junto `evidence/cobertura.sh`, que corretamente
# se recusa a medir cobertura sobre um oraculo ja vermelho.
#
# A PRIMEIRA CORRECAO FOI UMA FUNCAO `mascara_de_runtime()` QUE ISENTAVA A ENTRADA. Ela durou
# poucas horas e foi REMOVIDA por revisao independente, que provou dois contraexemplos - ambos
# sem privilegio nenhum, ambos em uma linha:
#
#   1. `ln -s /dev/null ./backdoor && git add -f backdoor`
#      `test -c` SEGUE symlink, entao a isencao casava. E o git versiona symlink (modo 120000):
#      medido, `git ls-files -s` devolveu `120000 dc1dc0c... backdoor`, enquanto a mensagem da
#      suite dizia "nao versionavel". A justificativa que eu havia escrito - "o git so versiona
#      arquivo regular, symlink e gitlink, logo char device nao pode ser commitado" - se
#      auto-refuta na propria enumeracao, porque symlink esta nela.
#
#   2. `unshare -rm bash -c ': > ./payload && mount --bind vazio ./payload'`
#      Satisfazia as TRES condicoes que eu havia exigido em conjunto (montado, nao rastreado,
#      vazio) com lixo arbitrario na raiz. As tres eram propriedades que o atacante escolhe.
#
# A CORRECAO REAL E O `.gitignore`, e ela e melhor por tres razoes. Fecha a janela do `git add`
# (que ja tinha commitado nove blobs vazios, no commit e4ab92e desta mesma onda). E revisavel -
# uma linha por caminho, visivel em diff, com decisao escrita. E nao cria classe isentavel
# nenhuma: um DECIMO caminho mascarado no futuro reprova esta suite de forma VISIVEL, e a
# correcao sera acrescentar uma linha que alguem le, em vez de um predicado que alguem contorna.
#
# LICAO QUE FICA, e ela vale mais que o caso: a funcao removida tinha comentario declarando
# "as tres condicoes sao exigidas em CONJUNTO para nao abrir buraco". O comentario descrevia a
# intencao; o codigo, por precedencia de `||`/`&&`, avaliava a primeira e retornava. Comentario
# nao e mecanismo, nem quando o mecanismo esta na linha de baixo.
while IFS= read -r entry; do
  if ! [[ "$entry" =~ $allowed_root ]]; then
    if ignorado "$entry"; then continue; fi
    echo "FAIL entrada nao declarada na raiz: $entry"
    fail=1
  fi
done < <(find . -maxdepth 1 -mindepth 1 -printf '%f\n' | sort)

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi

echo "PASS higiene do repositorio"
