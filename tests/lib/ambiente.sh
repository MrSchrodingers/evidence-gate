#!/usr/bin/env bash
# AMBIENTE FIXADO DAS SUITES QUE EXERCITAM O PORTAO - fonte unica.
#
# POR QUE EXISTE. Tres recorrencias consecutivas do MESMO padrao nesta onda, todas nomeadas por
# revisao independente: fechar um buraco e quebrar, no mesmo movimento, o instrumento que o mede.
#
#   G76 -> G5/G11   isolei o ledger via EVIDENCE_LEDGER_DIR e um leitor ficou apontando para o
#                   ledger REAL; a garantia passou a reprovar por ler dado velho.
#   G74 -> G79      escrevi a regressao do parser com fixture que bloqueava por OUTRO motivo
#                   (E902), e o mutante sobrevivia com a suite 45/45 verde.
#   G79 -> locale   a fixture corrigida so discrimina sob locale ESTRITO. Sob `C`/`C.UTF-8` o
#                   Python liga o modo UTF-8 (PEP 540) e usa `surrogateescape` no stdin, entao o
#                   parser DEFEITUOSO nao estoura e o mutante MVG8 sobrevive.
#
# Cada correcao pontual redescobriu a contaminacao DEPOIS de ja ter publicado o numero. Este
# arquivo existe para que a proxima suite herde o ambiente em vez de descobri-lo.
#
# O QUE E FIXADO, E POR QUE CADA UM:
#
#   PYTHONIOENCODING=utf-8:strict
#     NAO e preferencia: e o que torna o teste INDEPENDENTE do locale da maquina. Medido:
#       LC_ALL=en_US.UTF-8 -> stdin ESTRITO  -> parser defeituoso ESTOURA (mutante morre)
#       LC_ALL=C.UTF-8     -> surrogateescape -> parser defeituoso PASSA  (mutante sobrevive)
#       LC_ALL=C           -> surrogateescape -> idem
#     Fixar `LC_ALL=en_US.UTF-8` seria fragil: esse locale pode nao estar gerado no runner do CI.
#     `PYTHONIOENCODING` obtem o mesmo efeito sem depender de locale instalado, e reproduz a
#     condicao REAL da estacao do operador (LANG=en_US.UTF-8), que e onde o defeito ocorreu.
#     O portao CORRIGIDO le `sys.stdin.buffer` e nao e afetado por esta variavel - que e
#     exatamente o que a torna um discriminante, e nao um enfeite.
#
#   EVIDENCE_LEDGER_DIR
#     O ledger e CACHE alem de registro: `pass` do mesmo (snapshot, verifiers, env) curto-circuita.
#     Sem isolar, um caso herda `pass` de outro caso com a mesma arvore e nunca executa o
#     verificador que afirma medir - e as paradas sinteticas contaminam o ledger operacional
#     (medido: 1637 arquivos criados em dois dias).
#     ATENCAO ao ler de volta: o portao nomeia o arquivo por `sha256(ROOT) | cut -c1-32`. Ler
#     `cat "$DIR"/*.jsonl | tail -1` devolve a ultima linha do ULTIMO arquivo do glob, nao a deste
#     repositorio - foi a causa exata da nao determinacao de G5/G11 (~12,6% de aprovacao).
#     Use `ledger_do_repo` abaixo.
#
#   TOLLENS_BASELINE_DIR
#     A catraca sobrevive entre execucoes e `[ ! -f "$BLPATH" ]` impede re-semeadura: uma catraca
#     vazia herdada de outro caso bloqueia para sempre. Medido na maquina do operador: 31 de 33
#     catracas com `[]`.
#
# NAO fixa TMPDIR: `tests/lib/tmpdir.sh` ja e a fonte unica do predicado 0700, e duplicar aqui
# seria a copia divergente que este repositorio proibe em outros pontos.

# $1 = diretorio base descartavel da suite (normalmente $TMP)
ambiente_de_suite(){
  local base="${1:?ambiente_de_suite exige o diretorio base da suite}"
  export PYTHONIOENCODING="utf-8:strict"
  export EVIDENCE_LEDGER_DIR="$base/ledger"
  export TOLLENS_BASELINE_DIR="$base/baselines"
  mkdir -p "$EVIDENCE_LEDGER_DIR" "$TOLLENS_BASELINE_DIR" 2>/dev/null || true
}

# Caminho do ledger DO REPOSITORIO CORRENTE, com a mesma chave que o portao usa.
ledger_do_repo(){
  printf '%s/%s.jsonl' "${EVIDENCE_LEDGER_DIR:-$HOME/.claude/evidence}" \
         "$(printf '%s' "${1:-$PWD}" | sha256sum | cut -c1-32)"
}
