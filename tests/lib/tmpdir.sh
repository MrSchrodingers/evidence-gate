#!/usr/bin/env bash
# DIRETORIO TEMPORARIO PRIVADO DO USUARIO - fonte unica do predicado de seguranca.
#
# POR QUE EXISTE. `tests/lib/lock.sh` e `tests/lib/arena.sh` computavam cada um o seu
# `${TMPDIR}/tollens-<uid>` e repetiam o mesmo bloco de validacao 0700. Duas revisoes
# independentes apontaram a mesma coisa: sao duas copias de uma checagem de SEGURANCA, e copias
# divergem em silencio. O repositorio ja proibe esse padrao em outro ponto - `install/apply.sh`
# registra que "duas copias da mesma lista divergiriam em silencio, e e o defeito central deste
# repositorio" - e ainda assim a arena imitou o lock em vez de reusa-lo.
#
# O QUE O PREDICADO GARANTE, e a atribuicao importa porque a primeira redacao a errou:
#
#   - O diretorio e 0700 e do usuario corrente. Isso e o que impede outro usuario local de criar
#     entradas la dentro - e portanto o que fecha a janela TOCTOU entre validar e escrever.
#   - `mkdir -p -m 700` NAO corrige diretorio PRE-EXISTENTE com modo frouxo (shellcheck SC2174,
#     verdadeiro e deliberado). Quem corrige e a checagem abaixo, que RECUSA em vez de seguir.
#     Medido sobre diretorio 0777 pre-criado: recusa.
#   - `stat` SEM `-L` e deliberado. Symlink reporta modo 777 proprio, entao um link plantado no
#     lugar do diretorio cai na recusa mesmo que aponte para um 0700 nosso. Nao "enderece" isto
#     para `stat -L`: reabre o furo.
#
# LIMITE DECLARADO: a garantia depende de o PAI ser sticky. Em `/tmp` (1777) o nao-dono nao
# consegue renomear nem remover o nosso diretorio. Com `TMPDIR` apontando para um diretorio
# world-writable SEM sticky, a janela volta a ser exploravel - aqui, no lock e na arena
# igualmente. Nao ha checagem do sticky do pai: seria mais uma copia de predicado, e o cenario
# pressupoe um ambiente que o processo ja nao controla.
#
# CONTRATO: `tollens_tmpdir_privado` ecoa o caminho e devolve 0 quando o diretorio e utilizavel;
# devolve 1 SEM ecoar nada quando recusa. Nao emite aviso - quem chama decide se a recusa e fatal
# (o lock segue sem protecao e avisa; a arena perde a atribuicao e o caso vira NOT_VERIFIED).

# BASE DOS TEMPORARIOS - e por que ela nao e `/tmp` por padrao.
#
# MEDIDO nesta maquina, depois de a bancada travar TRES vezes num dia: `/tmp` e tmpfs com teto
# FIXO de 1.048.576 inodes, e esse teto - nao o espaco - e o que estoura. No pior episodio havia
# 12 G livres em bytes e 437 inodes livres; `mktemp` falhava, a ferramenta de shell nao
# conseguia criar o proprio arquivo de saida, e o Stop-gate passou a declarar LACUNA em toda
# parada (fail-closed, correto, mas a bancada parou). Uma unica arena de suite custa 2768 inodes
# (a arvore com `.git`), e `tests/unit/delta-e2e.sh` cria um repositorio git por caso.
#
# `/home` e btrfs: `df -i` reporta 0/0/0, isto e, SEM teto fixo de inodes, com 244 G livres.
# Mover o trabalho temporario para la elimina a classe inteira em vez de administra-la.
#
# SEGURANCA NAO PIORA, MELHORA. O LIMITE DECLARADO acima adverte contra `TMPDIR` num diretorio
# world-writable sem sticky, porque isso reabre a janela TOCTOU. `$HOME/.cache/tollens/tmp` nao
# e world-writable: so o dono entra, e o predicado 0700 abaixo continua sendo verificado do
# mesmo jeito. A dependencia do sticky do pai existia porque o pai era `/tmp` (1777); aqui o pai
# e o proprio HOME.
#
# PRECEDENCIA: `TOLLENS_TMPDIR` (escotilha explicita, para CI ou para forcar /tmp) > HOME
# gravavel > `${TMPDIR:-/tmp}`. O CI roda em contentor efemero e pode nao ter HOME util; por
# isso o fallback permanece.
tollens_tmpdir_base(){
  if [ -n "${TOLLENS_TMPDIR:-}" ]; then
    mkdir -p "$TOLLENS_TMPDIR" 2>/dev/null || true
    [ -d "$TOLLENS_TMPDIR" ] && [ -w "$TOLLENS_TMPDIR" ] && { printf '%s\n' "$TOLLENS_TMPDIR"; return 0; }
  fi
  if [ -n "${HOME:-}" ] && [ -d "$HOME" ] && [ -w "$HOME" ]; then
    local b="$HOME/.cache/tollens/tmp"
    mkdir -p "$b" 2>/dev/null || true
    [ -d "$b" ] && [ -w "$b" ] && { printf '%s\n' "$b"; return 0; }
  fi
  printf '%s\n' "${TMPDIR:-/tmp}"
}

tollens_tmpdir_privado(){
  local d
  d="$(tollens_tmpdir_base)/tollens-$(id -u)"
  # shellcheck disable=SC2174
  mkdir -p -m 700 "$d" 2>/dev/null || true
  [ -d "$d" ] || return 1
  [ "$(stat -c '%u:%a' "$d" 2>/dev/null)" = "$(id -u):700" ] || return 1
  printf '%s\n' "$d"
}
