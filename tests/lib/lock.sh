#!/usr/bin/env bash
# LOCK DE EXECUCAO DAS SUITES. Este arquivo e SOURCED, nunca executado direto.
#
# ELE TAMBEM FIXA O `TMPDIR` DAS SUITES, e isso nao e escopo emprestado: este e o unico arquivo
# carregado por praticamente toda suite deste repositorio (38 de 47, medido), e o problema que
# se resolve aqui e da bancada inteira, nao de uma suite. Ver `tests/lib/tmpdir.sh`,
# `tollens_tmpdir_base`, para a medicao: `/tmp` e tmpfs com teto FIXO de 1.048.576 inodes, uma
# arena custa 2768 inodes, e a bancada travou tres vezes num dia com 12 G de espaco livre e
# inodes esgotados. Fixar a base aqui, uma vez, corrige todo `mktemp` das suites - inclusive os
# que nao passam base explicita - sem editar 47 arquivos e sem que um arquivo novo nasca errado.
if [ -r "$(dirname "${BASH_SOURCE[0]}")/tmpdir.sh" ]; then
  . "$(dirname "${BASH_SOURCE[0]}")/tmpdir.sh"
  _tollens_base="$(tollens_tmpdir_base 2>/dev/null || true)"
  if [ -n "$_tollens_base" ] && [ -d "$_tollens_base" ] && [ -w "$_tollens_base" ]; then
    export TMPDIR="$_tollens_base"
  fi
  unset _tollens_base
fi
#
# POR QUE EXISTE - reproduzido em 2026-08-04, nao inferido:
#   bash tests/mutation/contrato.sh &   # muta subagent-contract.sh NO LUGAR
#   sleep 6; bash tests/unit/run.sh     # le o mesmo arquivo
#   -> run.sh: "FAIL  BARRA blocos completos SEM ancora (got=0 want=2)", exit 1
#   -> isolada, no mesmo instante seguinte: PASS=45 FAIL=0, exit 0
#
# O perigo nao e a suite ficar vermelha: e a vermelhidao ser PLAUSIVEL. O caso acusado parece
# um defeito real no discriminador da ancora, e o operador iria depurar um bug que nao existe.
# A corrida simetrica tambem cabe: uma suite lendo o hook MUTADO (mais permissivo) durante a
# janela de mutacao pode mascarar defeito real - falso verde com a mesma causa.
#
# ESCOPO DA GARANTIA: isto protege contra corrida entre suites DESTE repositorio. Nao protege
# contra edicao manual concorrente nem contra outro clone apontando para o mesmo ~/.claude.
#
# DUAS DECISOES DE DESENHO, ambas deliberadas:
#
# 1. FALHA RAPIDO (`flock -n`), nao espera. Esperar serializaria e as duas execucoes passariam
#    - conveniente, e exatamente o tipo de absorcao silenciosa que este repositorio existe para
#    nao fazer. Exit 3 e codigo distinto de 0 (verde), 1 (vermelho) e 2 (bloqueio de hook):
#    "houve corrida" nunca se confunde com "ha defeito".
#
# 2. RE-ENTRANTE POR VARIAVEL EXPORTADA. Os runners de mutacao INVOCAM as suites de regressao.
#    Com lock nao reentrante o filho travaria no lock do pai - deadlock por desenho, e o
#    proprio mecanismo de protecao viraria o defeito. A marca no ambiente diz que a arvore ja
#    esta protegida por um ancestral.
#
# ARMADILHA JA PAGA (handoff, item 8): `$TMPDIR` pode estar VAZIO, nao apenas indefinido, no
# zsh - ai "$TMPDIR/x" vira "/x" e falha com permission denied. `${TMPDIR:-/tmp}` cobre os dois
# casos; `${TMPDIR-/tmp}` cobriria so o indefinido e reintroduziria o bug.

if [ "${TOLLENS_LOCK:-}" != "held" ]; then
  if ! command -v flock >/dev/null 2>&1; then
    # LACUNA DECLARADA, nao inercia silenciosa: sem flock nao ha exclusao mutua. Seguir e
    # correto (voltar ao comportamento anterior nao e regressao); calar nao seria.
    echo "AVISO: flock ausente - as suites rodam SEM protecao contra corrida (lacuna declarada)." >&2
  else
    _lk_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    # ONDE FICA O LOCK - importa mais do que parece. Ancorar em $TMPDIR abre um furo: dois
    # processos do MESMO repositorio com $TMPDIR diferente calculariam arquivos diferentes e
    # NAO se excluiriam - exclusao mutua que depende de variavel de ambiente nao e exclusao
    # mutua. Por isso a preferencia e `.git/`, que e o mesmo caminho para todo processo que
    # enxerga este repositorio, e e gravavel sempre que a arvore e.
    #   TOLLENS_LOCK_FILE: override explicito. Existe para tests/unit/concorrencia.sh,
    #   que precisa exercitar o lock sem colidir com o lock real tomado por scripts/status.sh.
    #   Nao usar em producao - apontar dois processos para arquivos distintos e desligar a
    #   garantia, nao configura-la.
    if [ -n "${TOLLENS_LOCK_FILE:-}" ]; then
      _lk_file="$TOLLENS_LOCK_FILE"
    elif [ -d "$_lk_root/.git" ] && [ -w "$_lk_root/.git" ]; then
      _lk_file="$_lk_root/.git/tollens-suite.lock"
    else
      # Sem `.git` gravavel (export por tarball, worktree somente-leitura): cai para o
      # temporario. LIMITE DECLARADO: aqui a exclusao volta a depender de $TMPDIR coincidir.
      #
      # SYMLINK (auditoria de 2026-08-04): o nome do arquivo e derivado de sha256(caminho do
      # repo) - deterministico e publico. Como `exec 9>"$f"` TRUNCA e SEGUE symlink, outro
      # usuario com escrita no diretorio podia plantar um link e fazer o lock zerar um arquivo
      # alheio. Medido: arquivo de 43 bytes truncado para 0.
      # Correcao: o lock passa a viver num diretorio PROPRIO, 0700, dono o usuario corrente -
      # ninguem mais consegue criar entradas la dentro. Se o diretorio ja existir com outro
      # dono ou modo frouxo, o fallback e RECUSADO em vez de usado: um lock que outro usuario
      # controla nao e lock.
      # ONDA 12: o predicado passou para `tests/lib/tmpdir.sh`, fonte unica. `tests/lib/arena.sh`
      # tinha uma COPIA deste bloco, e duas copias de uma checagem de seguranca divergem em
      # silencio - apontado pelas duas revisoes independentes da onda. O comportamento aqui nao
      # muda: recusa continua sendo recusa, e o fallback segue sem protecao com aviso.
      _lk_dir=""
      if [ -r "$(dirname "${BASH_SOURCE[0]}")/tmpdir.sh" ]; then
        . "$(dirname "${BASH_SOURCE[0]}")/tmpdir.sh"
        _lk_dir="$(tollens_tmpdir_privado)" || _lk_dir=""
      fi
      if [ -z "$_lk_dir" ]; then
        echo "AVISO: '${TMPDIR:-/tmp}/tollens-$(id -u)' nao e um diretorio 0700 do usuario" >&2
        echo "       corrente, ou tests/lib/tmpdir.sh esta ausente - fallback de lock" >&2
        echo "       RECUSADO. As suites rodam SEM protecao contra corrida (lacuna declarada)." >&2
        _lk_file=""
      else
        _lk_file="$_lk_dir/$(printf '%s' "$_lk_root" | sha256sum | cut -c1-16).lock"
      fi
    fi
    if [ -z "$_lk_file" ]; then
      :   # fallback recusado acima; o aviso ja foi emitido
    elif [ -L "$_lk_file" ]; then
      echo "AVISO: '$_lk_file' e um symlink - lock RECUSADO (nao truncamos alvo alheio)." >&2
    elif ! exec 9>"$_lk_file"; then
      echo "AVISO: nao foi possivel abrir o lock em '$_lk_file' - seguindo sem protecao." >&2
    elif ! flock -n 9; then
      {
        echo "LOCK: ja ha uma suite deste repositorio em execucao."
        echo "  arquivo de lock: $_lk_file"
        echo "As suites NAO sao reentrantes entre si. Ate a onda 10 a razao era que os runners de"
        echo "mutacao editavam arquivos do repositorio NO LUGAR; desde a onda 11 eles rodam em"
        echo "arena descartavel (tests/lib/arena.sh) e a arvore nao e mais tocada por eles. O lock"
        echo "continua necessario por TRES razoes que a arena nao cobre:"
        echo "  - install/manifest.sh LE a arvore para gravar digests de estado desejado;"
        echo "  - scripts/status.sh ESCREVE docs/status.generated.md nela;"
        echo "  - TOLLENS_ARENA=off devolve a mutacao para o lugar, e o modo existe."
        echo "Rode uma por vez; se algo ficou em background, espere terminar."
        echo "exit 3 = corrida detectada. NAO e defeito de codigo e NAO e resultado de teste."
      } >&2
      exit 3
    else
      export TOLLENS_LOCK=held
    fi
  fi
fi
