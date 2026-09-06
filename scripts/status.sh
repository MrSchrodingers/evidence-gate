#!/usr/bin/env bash
# Gera docs/status.generated.md a partir de execucao real. Numeros de suites e mutantes sao
# derivados dos proprios oraculos; o README referencia este artefato em vez de duplica-los.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/../tests/lib/lock.sh"
export LC_ALL=C
OUT="docs/status.generated.md"
CHECK=0
# ARGUMENTO DESCONHECIDO VIRAVA NOME DE ARQUIVO, e o resultado era sucesso falso. `--check` era a
# unica forma reconhecida; qualquer outra coisa caia no `else` e virava $OUT. Medido nesta sessao:
# `bash scripts/status.sh --regenerate` (flag que nunca existiu) gerava o relatorio, tentava
# `mv "$TMP" -- --regenerate`, o mv recusava o hifen duplo, e o script imprimia `gerado:
# --regenerate` com rc=0. O artefato NAO era regerado e nada dizia isso - o portao seguinte
# reprovava por "DESATUALIZADO" e a causa ficava a duas camadas de distancia. Custou tres ciclos
# completos de suite ate a saida ser lida em vez de mandada para /dev/null.
case "${1:-}" in
  --check) CHECK=1 ;;
  --*)     echo "uso: $0 [--check | <caminho-de-saida>]" >&2
           echo "argumento desconhecido: $1 - recusado para nao virar nome de arquivo." >&2
           exit 2 ;;
  *)       OUT="${1:-$OUT}" ;;
esac

# INTERPRETADOR PELO SUFIXO. Achado da revisao da onda 13: a lista abaixo era invocada com
# `bash "$t"` e ganhou um `.py`. Bash sobre Python devolve exit 2 com stdout vazio - a coluna de
# assercoes virava `?` e a de exit virava `2` PERMANENTE no artefato publicado, que e
# normalizacao de desvio. Pior: o bash executa as crases do docstring como substituicao de
# comando; `python3 tests/unit/methodology.py` entre crases foi de fato invocado.
# Verificar o artefato nao e verificar a integracao (regra 3 da §6.3): os sete mutantes do portao
# novo morreram porque eu o chamei a mao. O mutante que faltava era o do WIRING.
roda_suite(){ case "$1" in *.py) python3 "$1" ;; *) bash "$1" ;; esac; }

# ONDA 21. DUAS CORRECOES NA MESMA FUNCAO, e as duas nasceram do mesmo defeito de desenho:
# a contagem era obtida REEXECUTANDO a suite.
#
# (1) DUPLA EXECUCAO. O laco abaixo rodava a suite para colher o `rc` e chamava `conta()`, que
#     rodava A MESMA SUITE DE NOVO para extrair o `PASS=N`. Medido por experimento com suite
#     instrumentada que conta invocacoes: 2 execucoes para as 18 suites sem o marcador de
#     ambiente, 1 para as 2 que o tem. Custo aferido: ~125 s por execucao de `status.sh`, e o
#     passo que o chama consome 933 s de um job de 1882 s - 49,6% do CI num passo so. A saida
#     agora e capturada UMA vez e usada para as duas colunas.
#
# (2) CONTAGEM DEPENDENTE DA BASE. `capability-conformance.py` emite 31 assercoes quando a
#     arvore DIFERE de `origin/main` e 29 quando e identica - as duas comparacoes contra a base
#     viram `NAO VERIFICADO` ("arvore identica a base, nada a discriminar") em vez de PASS.
#     O artefato era gerado na BRANCH (31) e conferido byte a byte em `main` (29), entao TODO
#     merge para main reprovava. Nao foi deslize: `main` ficou vermelho em 2026-08-21, 08-24 e
#     08-25, tres merges seguidos, e a leitura verde da CI do PR escondeu isso porque sao runs
#     distintos. Rotulo constante e a mesma correcao ja aplicada a `managed-root-trust.sh`
#     (sudo) e a `run.sh` (ambiente): um numero que depende do contexto de observacao nao pode
#     ser gravado como invariante num artefato conferido por igualdade de bytes.
# ONDA 21c. A LISTA CURADA SAIU, E QUEM A DERRUBOU FOI O `refutador`. As ondas 21 e 21b
# publicaram, aqui e no ADR 0040, a afirmacao "procurei um detector derivavel e NAO ACHEI um que
# se sustente". Isso e claim de EXISTENCIA, e era FALSA - a classe que a onda 20 inteira corrigiu,
# cometida na correcao dela.
#
# O detector existe e e a convencao dominante do proprio repositorio: **a suite fixa e impoe a
# propria contagem?**
#
#     EXPECTED=<literal>  + exit 1    publica o numero - desvio JA e vermelho na suite
#     EXPECTED=$((...))                `variavel (ambiente)`
#     sem pino                         `variavel (base)` - pode variar em silencio
#
# Medido nas 20: 14 com pino literal, 2 dinamicas, 4 SEM PINO - e as 4 sao exatamente
# `capability-conformance.py`, `hooks-de-guarda.sh`, `fronteira-externa.sh` e
# `contrato-de-instalador.sh`. ZERO falsos negativos: nenhuma suite que possa variar em silencio
# publica numero. Dois falsos positivos hoje (as duas ultimas nao tem caminho de pulo medido),
# removiveis pondo pino nelas - e o falso positivo custa informacao, nao correcao.
#
# POR QUE ESTE SE SUSTENTA E OS TRES ANTERIORES NAO. Ele e propriedade ESTATICA DO FONTE, entao e
# simetrico entre branch e main - o furo do detector que lia a saida capturada. E nao tenta
# DERIVAR a contagem, que era a coisa errada a medir: o que discrimina nao e quanto a suite conta,
# e se ela se AUTOFIXA.
#
# EFEITO COLATERAL QUE FECHA OUTRO ACHADO (F4 do `refutador`, que nenhum outro revisor viu). A
# lista curada introduzia uma SEGUNDA ocorrencia textual de duas suites dentro deste arquivo, numa
# string de DADOS que nao executa nada. O portao `tests/unit/capability-conformance.py:485-488`
# usa `ref in _ger` - substring de `status.sh` - como proxy de "foi executada pelo gerador".
# Medido: removendo SO a linha do laco, o portao continuava creditando `E_M`, e 13 das 17
# evidencias `executed_suite` pagas apontam para `hooks-de-guarda.sh`, que NAO tem passo dedicado
# em nenhum workflow. Era "mencao nao e execucao" reintroduzido dentro do arquivo que persegue
# essa forma. Sem a lista, a unica ocorrencia volta a ser a do laco.
pino_da_suite(){
  if   grep -qE '^[[:space:]]*EXPECTED=[0-9]+' "$1"; then printf 'literal'
  elif grep -qE 'EXPECTED=\$\(\(' "$1";          then printf 'dinamico'
  else printf 'ausente'; fi
}
conta_da_saida(){ printf '%s' "$1" | grep -oE 'PASS=[0-9]+|TOTAL=[0-9]+' | tail -1 | cut -d= -f2; }
TMP="$(mktemp)" || exit 1
trap 'rm -f "$TMP"' EXIT

{
  printf '# Estado gerado\n\n'
  printf 'NAO EDITAR. Gerado por `scripts/status.sh` a partir de execucao real.\n'
  printf 'O README referencia este arquivo em vez de duplicar numeros.\n\n'

  printf '## Suites\n\n| Suite | Assercoes | Exit |\n|---|---:|---:|\n'
  for t in tests/unit/regressao-gate.sh tests/unit/document-tools.sh tests/unit/supply-chain.sh \
           tests/unit/reprodutibilidade.sh tests/unit/concorrencia.sh tests/unit/claims.sh \
           tests/unit/propriedades.sh tests/unit/fronteira-externa.sh tests/unit/managed.sh \
           tests/unit/conformidade-managed.sh tests/unit/arnes-de-mutacao.sh \
           tests/unit/schedule.sh tests/unit/fronteira-viva.sh tests/unit/literatura.sh \
           tests/unit/capabilities.sh tests/unit/cobertura.sh \
           tests/unit/contrato-de-instalador.sh \
           tests/unit/hooks-de-guarda.sh \
           tests/unit/capability-conformance.py \
           tests/unit/run.sh; do
    _saida="$(roda_suite "$t" 2>&1)"; rc=$?
    case "$(pino_da_suite "$t")" in
      literal)  n="$(conta_da_saida "$_saida")" ;;
      dinamico) n='variavel (ambiente)' ;;
      *)        n='variavel (base)' ;;
    esac
    printf '| `%s` | %s | %s |\n' "$t" "${n:-?}" "$rc"
  done
  bash tests/unit/managed-root-trust.sh >/dev/null 2>&1; rc=$?
  printf '| `tests/unit/managed-root-trust.sh` | variavel (sudo) | %s |\n' "$rc"

  printf '\n## Mutacao\n\n| Alvo | Mutantes | Exit |\n|---|---:|---:|\n'
  # ONDA 21. ESTES ARNESES NAO SAO MAIS EXECUTADOS AQUI, e o argumento nao e novo: ja estava
  # escrito neste arquivo, duas vezes, para `install.sh` e para a varredura automatica logo
  # abaixo - "rodar a suite e descartar o `$?` e execucao que nao produz sinal algum".
  #
  # Medido: os dez consomem 624 s por execucao de `status.sh` (run 32795311156: run 103, contrato
  # 19, fronteira 1, conformidade 4, schedule 9, fronteira-viva 75, literatura 40, claims 79,
  # capabilities 21, cobertura 273), e TODOS tem passo dedicado no workflow. O veredito vinha do
  # passo dedicado; aqui o exit code so era reimpresso numa tabela markdown. Como `verify-push` e
  # passo-a-passo identico a `verify-pr`, o desperdicio contava em dobro.
  #
  # O ROTULO E COMPUTADO, NAO LITERAL. A onda 15 pagou por publicar "passo dedicado no CI" sem
  # conferir que o passo existisse - e para dois arneses nao existia. A funcao abaixo confere no
  # workflow, e imprime `NAO executado no CI` quando o passo falta, que e o sinal de que a
  # cobertura sumiu junto com a execucao.
  # `.sh` E OBRIGATORIO NO PADRAO, e a falta dele era falso positivo provado por mutacao:
  # `tests/mutation/fronteira` e prefixo de `tests/mutation/fronteira-viva.sh`, entao remover o
  # passo dedicado de `fronteira.sh` do workflow ainda imprimia "passo dedicado no CI". O oraculo
  # afirmava o que nao media - a mesma classe que a onda 15 corrigiu ao tornar este rotulo
  # computado em vez de literal.
  onde_roda(){ if grep -qF "tests/mutation/$1.sh" .github/workflows/verify-pr.yml 2>/dev/null
               then printf 'passo dedicado no CI'; else printf 'NAO executado no CI'; fi; }
  n_mut(){ _v="$(grep -oE 'EXPECTED_MUTANTS=[0-9]+' "tests/mutation/$1.sh" | head -1 | cut -d= -f2)"
           [ -n "$_v" ] || _v="$(grep -c '^mutante M' "tests/mutation/$1.sh")"
           printf '%s' "${_v:-?}"; }
  while IFS='|' read -r _arq _rotulo; do
    [ -n "$_arq" ] || continue
    printf '| %s | %s | %s |\n' "$_rotulo" "$(n_mut "$_arq")" "$(onde_roda "$_arq")"
  done <<'ARNESES'
run|gate
contrato|contrato de subagente
install|instalador
fronteira|fronteira externa
conformidade|conformidade de dois escopos
schedule|escalonamento
fronteira-viva|fronteira viva
literatura|camada de literatura
claims|claim ledger
capabilities|capability declarada
cobertura|cobertura de decisao
ARNESES

  # COMPLETUDE, nao lista digitada a mao. As linhas acima tem rotulo curado por arnes; esta
  # varredura garante que um arnes NOVO nunca nasca fora do relatorio. Foi o que aconteceu com
  # tests/mutation/fable-guard.sh, escrito na onda 7 (12 mutantes sobre 148 linhas de superficie
  # de autorizacao) e ausente daqui ate esta correcao - a MESMA classe que a varredura de
  # completude de ALVOS fechou em evidence/cobertura.sh. Instrumento escrito e nao reportado e
  # a versao pequena do instrumento escrito e nao executado (ADR 0029).
  CURADOS='run install fronteira conformidade schedule fronteira-viva literatura claims capabilities cobertura contrato'
  for _mf in tests/mutation/*.sh; do
    _b="$(basename "$_mf" .sh)"
    case " $CURADOS " in *" $_b "*) continue ;; esac
    _n="$(grep -oE 'EXPECTED_MUTANTS=[0-9]+' "$_mf" | head -1 | cut -d= -f2)"
    # MESMO FALLBACK DA TABELA CURADA (`n_mut`, acima), que esta varredura nao tinha: contar os
    # mutantes DECLARADOS no arquivo. Sem ele, arnes sem `EXPECTED_MUTANTS=` publicava `?` -
    # e `?` num artefato de status e a ausencia que ele existe para nao ter. Medido na onda 25c:
    # `lint-delta` e `verify-gate-delta` sairam com `?` mesmo tendo 11 e 7 mutantes contaveis.
    # DERIVADO, nao declarado: escrever o numero a mao no arnes o faria divergir do arquivo no
    # primeiro mutante novo, que e a classe de defeito que este repositorio persegue.
    [ -n "$_n" ] || _n="$(grep -c '^mutante M' "$_mf")"
    [ "${_n:-0}" -gt 0 ] 2>/dev/null || _n=""
    # ROTULO CONSTANTE, NAO EXIT CODE MEDIDO. Defeito meu, pago com uma CI vermelha (run
    # 31607753782): a primeira versao desta varredura EXECUTAVA o arnes e gravava o `$?` no
    # artefato. `fable-guard.sh` deu 0 nesta maquina e 1 no runner - o ubuntu-24.04 restringe
    # user namespace nao privilegiado por AppArmor, e 3 dos 12 mutantes dependem de
    # `unshare --map-root-user` para exercitar posse de root sem sudo. Resultado: o artefato
    # NUNCA poderia bater nos dois ambientes, e `--check` reprovava para sempre.
    # E exatamente o que o comentario 30 linhas acima ja explicava sobre `install.sh`, e que eu
    # li antes de escrever isto. Enunciar a regra nao a executa.
    # A execucao real acontece no passo dedicado do workflow, que e onde o veredito importa.
    # ROTULO COMPUTADO, NAO LITERAL (onda 15, achado do portao final). Esta linha imprimia
    # "passo dedicado no CI" para todo arnes, sem conferir que o passo existisse - e para dois
    # deles nao existia. Claim publicada que ninguem recalcula envelhece em silencio, que e a
    # forma que este arquivo ja pagou em outra linha (ver o comentario sobre lavagem, abaixo).
    if grep -qF "tests/mutation/$_b.sh" .github/workflows/verify-pr.yml 2>/dev/null; then
      _onde='passo dedicado no CI'
    else
      _onde='NAO executado no CI'
    fi
    printf '| %s (auto) | %s | %s |\n' "$_b" "${_n:-?}" "$_onde"
  done

  printf '\n## Cobertura de decisao (branch), medida via subprocesso instrumentado\n\n'
  printf 'Piso por arquivo (evidence/cobertura.sh --check); ver o script para a mecanica de\n'
  printf 'medicao e o LIMITE declarado (cobertura prova execucao de ramo, nao correcao de\n'
  printf 'assercao).\n\n'
  printf '| Arquivo | Medido | Piso | Status |\n|---|---:|---:|---|\n'
  bash evidence/cobertura.sh 2>/dev/null \
    | awk -F'\t' '$1=="COBFILE"{printf "| `%s` | %s%% | %s%% | %s |\n", $2, $3, $4, $5}'

  printf '\n## Componentes\n\n| Tipo | Qtd |\n|---|---:|\n'
  awk -F'\t' '!/^#/{c[$1]++} END{for(t in c) printf "| %s | %s |\n", t, c[t]}' install/manifest.lock | sort
  printf '| **total** | **%s** |\n' "$(grep -vc '^#' install/manifest.lock)"

  printf '\n## Limites declarados\n\n'
  printf -- '- `allowManagedHooksOnly` continua sendo uma decisao administrativa de deploy; o repositorio nao afirma que esteja ativo em toda instalacao.\n'
  printf -- '- a execucao root do instalador stock agora recusa fonte que nao seja integralmente `root:root`, livre de symlinks e sem escrita de grupo/outros; isso e uma precondicao operacional, nao autenticacao criptografica do release.\n'
  printf -- '- `TOLLENS_REPO`, quando usado por hooks managed para localizar verificadores, continua sendo uma dependencia que deve receber uma fronteira de confianca compativel com o ambiente onde for ativada.\n'
  printf -- '- o ambiente de CI e auditavel, nao hermetico: `ubuntu-24.04` fixa a familia da imagem, nao seu digest, e a excecao `apt` permanece declarada.\n'
  printf -- '- sem corpus proprio de desfecho, nao ha claim de superioridade universal de engenharia; a governanca de skills e evidence-gated e falsificavel.\n'
  printf -- '- parsers e adaptadores documentais nao constituem sandbox de sistema operacional.\n'
  printf -- '- rollback cobre falhas observadas pelo supervisor. `SIGKILL` do supervisor, falha de host/filesystem e comprometimento administrativo permanecem fora da garantia.\n'
  printf -- '- ownership/mode checks usam semantica POSIX/GNU exercitada no CI; ACLs, capabilities e atributos de filesystem fora desse contrato exigem verificacao especifica antes de ampliar a claim.\n'
  printf -- '- o ruleset impoe o check requerido enquanto a regra estiver ativa; administradores com autoridade para alterar a regra permanecem fora desse mecanismo.\n'
  printf -- '- cobertura de decisao (branch, evidence/cobertura.sh) prova que um ramo foi executado por algum teste; nao prova que a assercao daquele teste esta correta. E piso, nao teto: torna a omissao detectavel (ramo nunca exercitado), nunca a torna impossivel (ramo exercitado e mal testado continua passando).\n'

  printf '\n## Propriedades de seguranca medidas\n\n'
  printf -- '- fonte privilegiada user-owned, symlinkada ou group/world-writable e rejeitada antes da delegacao quando o supervisor roda como root na raiz real.\n'
  printf -- '- `TOLLENS_MANAGED_WORKER` e proibido em execucao root sobre a raiz real; o override permanece apenas para ensaios com `MANAGED_PREFIX`.\n'
  printf -- '- modos esperados sao revalidados apos o deploy (`0755` para diretorios/scripts/document-tools; `0644` para os demais arquivos regulares), e divergencia provoca rollback.\n'
  printf -- '- ownership usa `find ... \\( ! -user root -o ! -group root \\) -print -quit`, evitando o bug de precedencia onde `owner!=root, group=root` podia nao produzir saida.\n'
  printf -- '- confinamento de origem/destino do manifesto, re-hash do staging, restauracao transacional e verificacao de permissao continuam cobertos pelas suites managed existentes.\n'
} > "$TMP"

if [ "$CHECK" -eq 1 ]; then
  # EXIT NAO-ZERO REPROVA, e nao apenas "o artefato mudou". Ate a onda 13 este portao era
  # SO `cmp -s`: o documento registra o exit de cada suite como VALOR numa tabela, entao uma
  # suite vermelha gravada como `| 30 | 1 |` batia com a regeneracao e o `--check` aprovava.
  #
  # Nao e hipotese. Aconteceu nesta onda: `tests/unit/propriedades.sh` foi de 31/0 para 30/1
  # por uma colisao de nome de mutante que eu introduzi, a regeneracao assou o vermelho no
  # artefato, `--check` fechou exit 0, e so o passo dedicado da CI pegou. O portao final desta
  # mesma onda tinha nomeado a forma - "enforcement por comparacao de bytes de uma tabela e
  # lavavel" - e a instrucao publicada logo abaixo ("rode scripts/status.sh e commite") era o
  # mecanismo de lavagem: seguir a instrucao ao pe da letra grava o vermelho e devolve o verde.
  #
  # Rotulo nao-numerico ("variavel (sudo)", "passo dedicado no CI", "OK") e ambiente-dependente
  # por decisao ja registrada acima e NAO entra nesta checagem.
  _vermelhas="$(awk -F'|' '/^\| `/ {e=$(NF-1); gsub(/ /,"",e); if (e ~ /^[0-9]+$/ && e+0 != 0) {s=$2; gsub(/ |`/,"",s); print s" (exit="e")"}}' "$TMP")"
  if [ -n "$_vermelhas" ]; then
    echo 'SUITE VERMELHA - o artefato nao pode ser aceito com exit nao-zero:'
    printf '  %s\n' $_vermelhas
    echo 'Regenerar o documento NAO resolve: ele registra o exit, entao gravar o vermelho'
    echo 'devolveria este portao ao verde. Conserte a suite.'
    exit 1
  fi
  if cmp -s "$TMP" docs/status.generated.md; then
    echo 'status atualizado'
    exit 0
  fi
  echo 'docs/status.generated.md DESATUALIZADO - rode scripts/status.sh e commite'
  diff -u docs/status.generated.md "$TMP" | head -40
  exit 1
fi
mv "$TMP" "$OUT"
trap - EXIT
echo "gerado: $OUT"
