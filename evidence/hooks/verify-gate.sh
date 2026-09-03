#!/usr/bin/env bash
# PLANO DE EVIDENCIA - verifica o snapshot e registra o veredito no ledger.  Hook: Stop.
#
# O QUE ESTE HOOK NAO E, e por que a reescrita:
# Ele NAO e o portao de conclusao. `Stop` nao pode ser fronteira de confianca, por quatro
# razoes independentes, todas verificadas:
#   - `stop_hook_active=true` na parada seguinte a um bloqueio (semantica anti-loop oficial);
#   - o runtime SOBREPOE o hook apos N bloqueios consecutivos (default 8);
#   - esse N vive em CLAUDE_CODE_STOP_HOOK_BLOCK_CAP, dentro do settings.json que o proprio
#     ator governado pode escrever - politica no espaco de escrita do governado nao e politica;
#   - `Stop` nao dispara quando o usuario interrompe a sessao nem em falha de API.
# Logo este hook produz no maximo um CANDIDATO e um registro auditavel. Quem certifica e a CI
# sobre o SHA exato, sob politica que o ator nao pode alterar.  Ver docs/adr/0022.
#
# INVARIANTES (cada um pago com defeito REPRODUZIDO - tests/unit/regressao-gate.sh):
#  G1. O cache guarda VEREDITO, nao carimbo. `pass` do mesmo snapshot e reutilizavel; `fail`
#      jamais vira verde. A versao anterior gravava (timestamp, assinatura) ANTES de executar:
#      a segunda parada dentro de 5 min achava a assinatura e saia 0 com o codigo quebrado.
#  G2. `stop_hook_active` nao pode ser verde silencioso. stderr com exit 0 NAO chega ao modelo
#      (docs/adr/0021); quem avisa sem bloquear usa additionalContext.
#  G3. A identidade e sobre BYTES. Nome nao identifica estado: a versao anterior hasheava
#      nomes + `git diff HEAD`, e `git diff` nao enxerga conteudo de arquivo untracked.
#  G4. Conjuncao sobre TODOS os adaptadores aplicaveis: Ready(x) = AND Pass(a,x). A anterior
#      parava no primeiro que casava - monorepo com JS valido e Python quebrado passava verde.
#  G5. Sem `sh -c`. O adaptador declara exec.command + exec.args[]; o executor decide o que
#      roda. String interpretada por shell permite redirecao, substituicao e composicao.
#  G6. Ferramenta ausente e LACUNA declarada, nao falha de codigo. Falso bloqueio e o que faz
#      o operador desligar o gate - e gate desligado protege zero.
#  G7. Tabela ausente e FAIL-CLOSED com aviso. Inercia silenciosa e o modo de falha que este
#      projeto inteiro combate.
#  G16. Zero unidades examinadas NAO e aprovacao. Um adaptador considerado APLICAVEL que examina
#      NADA (arquivo apagado, renomeado com conteudo divergente, symlink quebrado, ou ecossistema
#      inteiro ausente de uma arvore que uma ferramenta nao-per_file escaneia) caia no ramo de
#      APROVADO - RC nunca saia do valor de inicializacao, ou a ferramenta (ex.: ruff numa arvore
#      sem .py) saia 0 por conta propria sem examinar nada. Vira LACUNA, nunca FALHA nem PASS:
#      "nao verifiquei isto" e verdade, "reprovou" mentiria, "passou" seria o verde vazio.
set -uo pipefail

# LEITURA DO EVENTO. `$(</dev/stdin)` depende do CAMINHO `/dev/stdin` existir e ser abrivel, e
# ha processos em que ele nao e: `claude -p` lancado fora de uma sessao - um processo de desktop,
# um companion, um cron - falha com `/dev/stdin: No such device or address`. Sem `set -e`, a
# atribuicao falha em silencio e `INPUT` fica VAZIO.
#
# E ai vem o dano, que e maior que o erro: o guarda anti-loop deste hook decide por
# `stop_hook_active` LIDO DE `$INPUT`. Com `$INPUT` vazio ele nunca casa, o gate nunca
# curto-circuita, roda o verificador, reprova, re-prompta - e repete. MEDIDO PELO OPERADOR:
# 9 re-prompts, 43 mil tokens, resposta VAZIA, 43 segundos. Reproduzido aqui com `0<&-`:
# `stop_hook_active=true` com stdin normal sai 0; com stdin fechado sai 2 e bloqueia.
#
# `cat` le o DESCRITOR 0, nao um caminho, e por isso funciona onde `/dev/stdin` nao existe. O
# `[ ! -t 0 ]` evita travar quando alguem roda o hook a mao num terminal - ali nao ha evento para
# ler e esperar seria pendurar o processo.
INPUT=""
# `timeout` E OBRIGATORIO, nao zelo: medido aqui, `cat` com o descritor 0 FECHADO nao retorna -
# o hook fica pendurado no caminho critico de toda parada, que e uma forma pior do mesmo dano que
# esta correcao existe para remover. Em operacao normal o runtime fecha o cano e `cat` volta na
# hora; o limite so age no caso degenerado.
if [ ! -t 0 ]; then INPUT="$(timeout 5 cat 2>/dev/null || true)"; fi

# EVENTO ILEGIVEL NAO PODE BLOQUEAR. Se nao da para ler o evento, nao da para saber se esta parada
# JA e a continuacao de um bloqueio anterior - e bloquear sem poder ver isso e exatamente o laco
# sem fim acima. A escolha entre "portao que pode ser contornado fechando stdin" e "portao que
# gasta a cota do operador em laco e devolve vazio" nao e simetrica: o segundo e pior, e nao tem
# como parar sozinho. Declara a lacuna e libera a parada.
if [ -z "$INPUT" ]; then
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg c "GATE - EVENTO ILEGIVEL. O hook nao conseguiu ler o evento de Stop na entrada
padrao (processo sem /dev/stdin abrivel, ou stdin fechado). Sem o evento nao da para saber se esta
parada ja e continuacao de um bloqueio, entao bloquear aqui seria laco sem fim. NADA foi
verificado neste turno - nao diga verde nem vermelho." \
      '{hookSpecificOutput:{hookEventName:"Stop",additionalContext:$c}}'
  fi
  echo "GATE - evento ilegivel na entrada padrao; nada foi verificado. Parada liberada para nao entrar em laco." >&2
  exit 0
fi
# G9: DEPENDENCIA ESTRUTURAL ausente e LACUNA, nao sucesso. Ferramenta de adaptador ausente ja
# virava lacuna (G6); ferramenta do proprio gate saia 0 em silencio - a mesma inercia que G7
# combate, no lugar mais critico. Fora de repositorio git, inerte e legitimo: nao ha o que verificar.
if ! command -v jq >/dev/null 2>&1; then
  if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # sem jq nao ha como emitir additionalContext; em continuacao forcada resta sair.
    printf '%s' "$INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && exit 0
    { echo "GATE - dependencia estrutural ausente: 'jq' nao esta no PATH."
      echo "O verificador nao pode ler o evento nem emitir contexto. Nada foi verificado."
      echo "Estado: NAO VERIFICADO / NOT_VERIFIED."; } >&2
    exit 2
  fi
  exit 0
fi
ACTIVE="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
ADAPTERS="${CLAUDE_ADAPTERS_DIR:-$(cd "$HERE/../../execution/adapters/code" 2>/dev/null && pwd)}"
LEDGER_DIR="${EVIDENCE_LEDGER_DIR:-$HOME/.claude/evidence}"

# CANAIS (docs/adr/0021): exit 2 bloqueia e entrega; additionalContext avisa e nao bloqueia;
# stderr com exit 0 e inerte - nunca usar para informacao que precisa chegar.
aviso(){ jq -cn --arg c "$1" '{hookSpecificOutput:{hookEventName:"Stop",additionalContext:$c}}' 2>/dev/null; exit 0; }
barra(){ printf '%s\n' "$1" >&2; exit 2; }
# Quando o runtime ja esta em continuacao forcada, bloquear nao e opcao: avisa.
reporta(){ if [ "$ACTIVE" = "true" ]; then aviso "$1"; else barra "$1"; fi; }

# G9b: `git` ausente tambem e dependencia estrutural. Sem git nao da para usar `rev-parse`,
# entao a deteccao de "estou num repositorio" e feita subindo a arvore atras de .git (que pode
# ser diretorio ou arquivo, no caso de worktree/submodulo). Havia .git e nao havia git: sair 0
# seria dizer verde sobre um repositorio que nunca foi olhado.
if ! command -v git >/dev/null 2>&1; then
  _d="$PWD"
  while [ "$_d" != "/" ] && [ -n "$_d" ]; do
    if [ -e "$_d/.git" ]; then
      reporta "GATE - dependencia estrutural ausente: 'git' nao esta no PATH, mas '$_d/.git' existe.
Nao foi possivel determinar o que mudou. Nenhuma verificacao rodou.
Estado: NAO VERIFICADO / NOT_VERIFIED."
    fi
    _d="$(dirname "$_d")"
  done
  exit 0   # fora de repositorio: inerte e legitimo
fi
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -n "$ROOT" ] || exit 0

# --- o que mudou: nao-commitado + untracked + commits nao publicados ---
#
# G12 - BASE DE COMPARACAO SEM UPSTREAM. Defeito reproduzido antes de corrigir: numa branch
# sem `@{u}`, o conjunto de commits nao publicados era simplesmente OMITIDO do calculo. Como
# `git commit` tambem zera `diff HEAD` e a lista de untracked, o resultado era CHANGED vazio e
# `exit 0` - o gate ficava INERTE exatamente no instante em que existe artefato pronto para
# atravessar a fronteira. Medido: branch nova com `origin/main` publicado e um commit contendo
# F821, gate saia 0 e mudo.
#
# A base honesta depende de existir fronteira a atravessar:
#   1. ha `@{u}`            -> a base e o upstream (comportamento anterior, preservado);
#   2. nao ha `@{u}` mas HA remoto -> commit local PODE ser publicado, logo precisa de base:
#      usa-se o ponto de divergencia em relacao ao alvo de publicacao (origin/HEAD, main,
#      master). Se o remoto existe mas nenhum ref dele e conhecido (remoto vazio ou sem fetch),
#      entao NENHUM commit desta arvore foi publicado e a base correta e a ARVORE VAZIA;
#   3. nao ha remoto nenhum -> nao existe fronteira externa a atravessar. Inerte segue
#      legitimo, pela mesma razao que "fora de repositorio git" e inerte: e AUSENCIA DE
#      FRONTEIRA, nao lacuna de verificacao. Declarar NOT_VERIFIED aqui seria ruido em todo
#      repositorio local, e ruido e o que faz o operador desligar o gate.
# `git rev-parse --abbrev-ref --symbolic-full-name '@{u}'` ECOA A PROPRIA ENTRADA quando nao ha
# upstream: imprime `@{u}` em stdout, manda o erro para stderr e sai nao-zero - e o `|| true`
# engolia o codigo. Medido em /var/www/amaral-intern-hub: `BASE='@{u}'`, `DIFFBASE='@{u}'`,
# `SEEDREF='@{u}'`, `git archive '@{u}'` falha, e a catraca nunca era semeada. Pior, `CHANGED`
# tambem usava essa string.
#
# E a familia da sonda que devolve lixo por nao casar - aqui na forma mais traicoeira: o comando
# nao devolve vazio, devolve O ARGUMENTO DE VOLTA, e isso passa por resposta. So `rev-parse
# --verify` sobre o objeto resolve.
_NL=$'\n'
UPSTREAM="$(git -C "$ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
if [ -z "$UPSTREAM" ] || ! git -C "$ROOT" rev-parse --verify -q "${UPSTREAM}^{commit}" >/dev/null 2>&1; then
  UPSTREAM=""
fi
BASE=""
if [ -n "$UPSTREAM" ]; then
  BASE="$UPSTREAM"
elif [ -n "$(git -C "$ROOT" remote 2>/dev/null)" ]; then
  # A LISTA DE CANDIDATOS E DERIVADA DOS REMOTOS QUE EXISTEM, nao fixada em `origin`. Medido em
  # /var/www/amaral-intern-hub - o repositorio de onde vem a maior parte dos registros que abrem a
  # onda 25: os remotos chamam-se `debt-hub` e `debthub`, nenhum candidato `origin/*` casava, e
  # `BASE` caia na ARVORE VAZIA. Com a catraca recusando semear sem base (F1), isso passaria a
  # bloquear o repositorio principal do operador por 6 defeitos preexistentes - trocando anistia
  # por travamento. `origin` e convencao, nao contrato: o mesmo erro de medir por nome que
  # `.worktrees` ja custou nesta onda.
  for _r in $(git -C "$ROOT" remote 2>/dev/null); do
    for _s in HEAD main master; do
      if git -C "$ROOT" rev-parse --verify -q "refs/remotes/$_r/$_s" >/dev/null 2>&1; then
        BASE="refs/remotes/$_r/$_s"; break 2
      fi
    done
  done
  [ -n "$BASE" ] || BASE="$(git -C "$ROOT" hash-object -t tree /dev/null 2>/dev/null || true)"
fi
# Normaliza para um unico objeto de comparacao. `merge-base` da o ponto de divergencia (evita
# atribuir a esta branch o que veio do outro lado); quando nao ha ancestral comum - caso da
# arvore vazia - o proprio BASE serve, e `git diff <arvore> HEAD` lista tudo.
DIFFBASE=""
if [ -n "$BASE" ]; then
  DIFFBASE="$(git -C "$ROOT" merge-base "$BASE" HEAD 2>/dev/null || true)"
  [ -n "$DIFFBASE" ] || DIFFBASE="$BASE"
fi
# R3 DO REFUTADOR, mesma raiz que a de HUNKS: sem `core.quotePath=false` o git devolve caminho
# nao-ASCII como `"acentua\303\247.py"` - com aspas e escapes. Aqui o dano e outro e maior: o
# casamento de extensao logo abaixo compara o fim da string, e `"...\303\247.py"` nao casa
# `.py` do jeito que o arquivo real casaria, entao o ADAPTADOR INTEIRO pode nao ser selecionado.
# Nao e um diagnostico perdido: e nenhum diagnostico produzido.
CHANGED="$( { git -C "$ROOT" -c core.quotePath=false diff --name-only HEAD 2>/dev/null
              git -C "$ROOT" -c core.quotePath=false ls-files --others --exclude-standard 2>/dev/null
              [ -n "$DIFFBASE" ] && git -C "$ROOT" -c core.quotePath=false diff --name-only "$DIFFBASE" HEAD 2>/dev/null
            } | sed '/^$/d' | sort -u )"
[ -n "$CHANGED" ] || exit 0

# --- G7: tabela ausente e fail-closed ---
if [ ! -d "$ADAPTERS" ] || ! ls "$ADAPTERS"/*.json >/dev/null 2>&1; then
  reporta "GATE - tabela de adaptadores nao encontrada em '${ADAPTERS:-<vazio>}'.
O verificador esta DESLIGADO neste turno. Estado: NAO VERIFICADO.
Defina CLAUDE_ADAPTERS_DIR ou rode install/apply.sh."
fi

# --- G4: TODO adaptador cuja extensao foi tocada e aplicavel (nao so o primeiro) ---
APLICAVEIS=(); ECOS=""; EXECUTORES=""
for a in "$ADAPTERS"/*.json; do
  [ -f "$a" ] || continue
  while IFS= read -r ext; do
    [ -z "$ext" ] && continue
    # F4 DO REFUTADOR. `printf | grep -q` sob `pipefail` devolve 141 quando o `grep` casa CEDO e
    # sai antes de o `printf` terminar de escrever: o `printf` toma SIGPIPE e o `pipefail` propaga.
    # O `if` fica falso e o adaptador e DESCARTADO EM SILENCIO - portao inerte, exit 0, `verdict:
    # pass`. Depende do dado: casamento no fim devolve 0, no inicio devolve 141. Medido em bash:
    # 220 KB de CHANGED com `a.py` na primeira linha -> exit=141; com CHANGED pequeno -> 0.
    #
    # Em /var/www/amaral-intern-hub o CHANGED tem 161 KB, e e o repositorio de onde vem a maior
    # parte dos 5054 registros que abrem esta onda: nao se sabe quantos dos `pass` sao 141 mudo.
    # Defeito de 2026-08-03, anterior a esta onda, corrigido aqui porque a PREMISSA dela depende.
    #
    # `case` nao usa pipe e nao tem essa classe de falha. `$'\n'` delimita para nao casar
    # `x.python` quando a extensao e `.py`.
    # `$'\n'` DENTRO DE ASPAS DUPLAS nao e citacao ANSI-C: vira a string literal `$'\n'`, o
    # `case` nunca casa e o adaptador para de rodar - medido, a suite ponta a ponta caiu de 14
    # para 4. A nova linha precisa vir de uma variavel expandida fora das aspas.
    if case "$_NL$CHANGED$_NL" in *"${ext}${_NL}"*) true ;; *) false ;; esac; then
      # G10: adaptador que DECLARA executar codigo do repositorio nunca roda automaticamente.
      # Pago com um defeito proprio: o adaptador .NET declarava executes_repository_code=false
      # sobre `dotnet format`, e a documentacao da Microsoft adverte que ele "may restore,
      # compile, and run analyzers... Only invoke the tool against trusted code."
      if [ "$(jq -r '.declared_effects.executes_repository_code // false' "$a")" = "true" ]; then
        EXECUTORES="$EXECUTORES
  - $(jq -r '.id' "$a") ($(jq -r '.ecosystem' "$a")): declara executar codigo do repositorio; exige aprovacao"
      else
        APLICAVEIS+=("$a"); ECOS="$ECOS $(jq -r '.ecosystem // "?"' "$a")"
      fi
      break
    fi
  done < <(jq -r '.extensions[]? // empty' "$a" 2>/dev/null)
done
if [ "${#APLICAVEIS[@]}" -eq 0 ]; then
  [ -n "$EXECUTORES" ] && reporta "GATE - LACUNA DE COBERTURA: nenhum analisador seguro para o que mudou.$EXECUTORES
Nenhuma verificacao rodou. Estado: NAO VERIFICADO / NOT_VERIFIED.
Adaptador que executa codigo do repositorio so roda sob aprovacao explicita."
  exit 0
fi

# --- G8: comando do REPOSITORIO so executa com aprovacao que PERTENCE A ROOT ---
# Classe CVE-2025-59536. `.claude/verify.json` vem do repositorio clonado: sem esta trava,
# abrir um repo hostil daria execucao de comando. A lista de aprovacao vive fora de qualquer
# repo E precisa ser de root - dono != root significa que o proprio ator pode se auto-aprovar,
# e ai a aprovacao nao e autoridade, e formalidade. Mutante em tests/unit/run.sh caso 5.
AVISO_REPO=""
REPO_VERIFY="$ROOT/.claude/verify.json"
if [ -f "$REPO_VERIFY" ] && jq -e '.exec.command' "$REPO_VERIFY" >/dev/null 2>&1; then
  # SHA-256 COMPLETO, 64 hex. Ate 2026-08-04 este era o unico lugar do arquivo que truncava em
  # 16 hex - 64 bits - enquanto a identidade do ambiente logo abaixo (G11, linha ~206) ja
  # documentava que "truncar em 16 hex daria 64 bits, o que e outra propriedade". A mesma regra
  # com dois tratamentos, e o truncado era justamente o que AUTORIZA EXECUCAO de um comando
  # vindo do repositorio. Achado da auditoria externa, e a incoerencia era interna ao arquivo.
  CH="$(sha256sum "$REPO_VERIFY" 2>/dev/null | cut -d' ' -f1)"
  APPROVED="$HOME/.claude/verify-cmd-approved"
  OWNER="$(stat -c '%U' "$APPROVED" 2>/dev/null || echo '')"
  if [ -n "$CH" ] && [ -f "$APPROVED" ] && [ "$OWNER" = "root" ] \
     && grep -qE "(^|[[:space:]])${CH}([[:space:]]|$)" "$APPROVED" 2>/dev/null; then
    # --- CONTRATO EXPLICITO DE SUBSTITUICAO ---
    # Antes: `APLICAVEIS=("$REPO_VERIFY")`. O comando do projeto SUBSTITUIA todos os analisadores
    # genericos, em silencio. Um repositorio poliglota cujo verify.json so roda a suite de Python
    # perdia a checagem de Node, Go e shell sem nenhum sinal - e a perda de cobertura tinha a
    # forma de uma aprovacao. Agora a substituicao e DECLARADA e ESCOPADA: o projeto diz quais
    # ecossistemas assume, e justifica por escrito. O que ele nao reivindica continua coberto.
    SUBST="$(jq -r '.replaces[]? // empty' "$REPO_VERIFY" 2>/dev/null | tr '\n' ' ')"
    JUST="$(jq -r '.coverage_justification // ""' "$REPO_VERIFY" 2>/dev/null)"
    if [ -z "$SUBST" ] || [ -z "$JUST" ]; then
      AVISO_REPO="
NOTA: $ROOT/.claude/verify.json esta APROVADO, mas nao declara o contrato de substituicao.
NAO foi executado, e os analisadores genericos seguem valendo.
Um comando de projeto que substitui a cobertura generica precisa dizer o que assume:
  \"replaces\": [\"python\", \"node\"]         # ecossistemas que ele passa a cobrir
  \"coverage_justification\": \"...\"          # por que a cobertura dele basta para esses
Ecossistemas fora de 'replaces' continuam sendo verificados pelos adaptadores genericos."
    else
      MANTIDOS=()
      for a in "${APLICAVEIS[@]}"; do
        eco="$(jq -r '.ecosystem // "?"' "$a" 2>/dev/null)"
        case " $SUBST " in
          *" $eco "*) : ;;                    # o projeto reivindicou este ecossistema
          *) MANTIDOS+=("$a") ;;              # nao reivindicado: cobertura generica permanece
        esac
      done
      APLICAVEIS=("$REPO_VERIFY" ${MANTIDOS[@]+"${MANTIDOS[@]}"})
    fi
  else
    MOTIVO="nao esta aprovado"
    [ -z "$CH" ] && MOTIVO="nao pode ser conferido (sha256sum indisponivel) - fail-closed"
    [ -f "$APPROVED" ] && [ "$OWNER" != "root" ] && [ -n "$CH" ] \
      && MOTIVO="tem lista de aprovacao pertencente a '$OWNER', nao a root - IGNORADA"
    AVISO_REPO="
NOTA: $ROOT/.claude/verify.json existe e $MOTIVO. NAO foi executado.
Digest: ${CH:-<indisponivel>}
Se voce LEU o comando e ele e legitimo, o USUARIO aprova (caminho ABSOLUTO: dentro de sudo o
\$HOME e o de root; apague o arquivo antes se existir com dono errado, porque append nao troca dono):
  sudo sh -c 'echo \"${CH}  # $(basename "$ROOT")\" >> $HOME/.claude/verify-cmd-approved && chown root:root $HOME/.claude/verify-cmd-approved'

LIMITE DECLARADO: o digest cobre os BYTES de verify.json, nao os bytes que ele manda executar.
Um verify.json que roda \`bash scripts/verify.sh\` permanece aprovado enquanto esse script muda.
Fechar isso exige digest transitivo ou sandbox - nao esta implementado (ver README, roadmap)."
  fi
fi

# --- G3: identidade sobre BYTES do estado avaliado ---
sha(){ sha256sum 2>/dev/null | cut -c1-32; }
SNAPSHOT="$( {
    printf 'head %s\n' "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo none)"
    [ -n "$UPSTREAM" ] && git -C "$ROOT" rev-list "${UPSTREAM}..HEAD" 2>/dev/null
    printf '%s\n' "$CHANGED" | while IFS= read -r f; do
      if [ -f "$ROOT/$f" ]; then printf '%s %s\n' "$f" "$(sha256sum "$ROOT/$f" 2>/dev/null | cut -d' ' -f1)"
      else printf '%s absent\n' "$f"; fi
    done
  } | sha )"
VERIFIERS="$(for a in "${APLICAVEIS[@]}"; do cat "$a"; done | sha)"
# G11: identidade do AMBIENTE, nao do caminho. Hash so do path nao muda quando o binario e
# atualizado ou substituido no mesmo lugar - e ai um `pass` em cache sobrevive a troca do
# verificador. Inclui realpath, digest do executavel e a string de versao.
ENVD="$(for a in "${APLICAVEIS[@]}"; do
          c="$(jq -r '.exec.command' "$a")"
          pth="$(command -v "$c" 2>/dev/null || echo absent)"
          if [ "$pth" != "absent" ]; then
            rp="$(readlink -f "$pth" 2>/dev/null || printf '%s' "$pth")"
            # SHA-256 COMPLETO: truncar em 16 hex daria 64 bits, o que e outra propriedade.
            # Numa identidade de evidencia nao ha ganho em truncar.
            bh="$(sha256sum "$rp" 2>/dev/null | cut -d' ' -f1 || echo '?')"
            vs="$(timeout 5 "$c" --version 2>&1 | head -1 || echo '?')"
            printf '%s|%s|%s|%s\n' "$c" "$rp" "$bh" "$vs"
          else printf '%s|absent\n' "$c"; fi
        done | sha)"
# G3/G1: sem sha256sum a identidade e vazia e casaria com tudo -> fail-closed.
if [ -z "$SNAPSHOT" ] || [ -z "$VERIFIERS" ]; then
  reporta "GATE - sha256sum indisponivel; a identidade do snapshot nao pode ser calculada.
Estado: NAO VERIFICADO (fail-closed)."
fi

# --- G1: ledger append-only; so `pass` do MESMO snapshot e reutilizavel ---
KEY="$(printf '%s' "$ROOT" | sha)"
LEDGER="$LEDGER_DIR/${KEY}.jsonl"
mkdir -p "$LEDGER_DIR" 2>/dev/null || true
IDENTICAS="$(grep -F "\"snapshot\":\"$SNAPSHOT\"" "$LEDGER" 2>/dev/null \
         | grep -F "\"verifiers\":\"$VERIFIERS\"" | grep -F "\"env\":\"$ENVD\"")"
PRIOR="$(printf '%s' "$IDENTICAS" | tail -1)"
if [ -n "$PRIOR" ] && [ "$(printf '%s' "$PRIOR" | jq -r '.verdict' 2>/dev/null)" = "pass" ]; then
  exit 0   # mesmo snapshot, mesmos verificadores, mesmo ambiente, veredito aprovado
fi

# --- G77: NEGATIVA REPETIDA E SINAL, NAO ROTINA ---
#
# Medido no ledger em 2026-09-02, sobre 8.600 paradas com veredito: 1.992 (23,2%) sao reexecucoes
# ESTRITAMENTE redundantes - mesmo snapshot, mesmos verificadores, mesmo ambiente, e o veredito
# anterior ja era `fail`. Um unico snapshot em /home/ti/debthub-wt-phone3 foi julgado 336 vezes,
# todas `fail`, em dois dias.
#
# A leitura barata desse numero e "cache o `fail`". Ela esta errada por consequencia assimetrica:
# `pass` cacheado que estivesse errado libera UM turno; `fail` cacheado que estivesse errado
# bloqueia o repositorio ATE a arvore mudar, e a arvore so muda se o ator agir - que e exatamente
# o que ele nao esta conseguindo fazer. Cachear ali fecharia o laco POR FORA, mantendo a causa.
#
# A causa e outra: o ator recebe a MESMA negativa e nao consegue agir sobre ela. Repetir a
# mensagem pela 336a vez nao e verificacao, e ruido com custo. Entao a partir do limiar o gate
# muda o QUE DIZ - nomeia a repeticao, o numero de tentativas e as unicas saidas reais - em vez de
# repetir. O veredito NAO muda: continua bloqueando, porque o defeito continua la.
#
# O limiar e 3 e a escolha e declarada: 1 seria a primeira parada legitima (o ator ainda nao viu a
# mensagem), 2 e a tentativa honesta de corrigir, e a partir da 3a a evidencia e de que a mensagem
# nao esta bastando. Nao ha experimento por tras deste numero - e um piso conservador, e trocar
# por outro exige medir, nao opinar.
# A2 DO REVISOR: `grep -c '"verdict":"fail"'` contava so `fail`, mas a mensagem abaixo afirma
# "ESTA E A Na PARADA COM ESTE MESMO ESTADO DE ARVORE" - sobre o ESTADO (snapshot+verifiers+env),
# nao sobre qual foi o veredito. Medido com ledger sintetico de 2 `gap` + 3 `fail` identicos:
# paradas reais = 5, contagem antiga = 3, a mensagem diria "4a parada" quando a real seria a 6a.
# ESCOLHA: a contagem passa a refletir a frase (conta `fail` E `gap`; `pass` do mesmo estado nunca
# chega aqui - sai por cache na linha ~347), em vez de estreitar a frase para "so fail". Motivo:
# `gap` e parada tao repetida quanto `fail` quando nada muda entre uma parada e a seguinte (mesmo
# snapshot, mesmos verificadores, mesmo ambiente) - a causa de G77 (ator recebe a mesma resposta e
# nao consegue agir) vale para as duas; estreitar a frase esconderia do ator paradas que ele de fato
# ja sofreu, so que com o motivo diferente.
# O predicado exige REGISTRO JSON VALIDO, nao `grep`: `grep -F`, usado para montar $IDENTICAS
# acima, casa SUBSTRING - uma linha TRUNCADA por escrita concorrente (o ledger e `>>` sem lock
# entre processos) pode conter o trecho procurado sem ser um JSON valido, e entrava na contagem
# como parada real. `jq -R 'fromjson?'` descarta em silencio o que nao parseia como objeto.
TENTATIVAS_IDENTICAS=0
if [ -n "$IDENTICAS" ]; then
  TENTATIVAS_IDENTICAS="$(printf '%s\n' "$IDENTICAS" \
    | jq -Rc 'fromjson? | select(type=="object") | select(.verdict=="fail" or .verdict=="gap") | 1' 2>/dev/null \
    | wc -l | tr -d ' ')"
fi
case "$TENTATIVAS_IDENTICAS" in ''|*[!0-9]*) TENTATIVAS_IDENTICAS=0 ;; esac
# veredito anterior `fail` ou `gap` NAO e reutilizado: reexecuta. Nunca vira verde por cache.

registra(){  # $1=verdict $2=detalhe
  jq -cn --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" --arg s "$SNAPSHOT" \
         --arg v "$VERIFIERS" --arg e "$ENVD" --arg d "$1" --arg m "$2" \
         '{ts:$t,snapshot:$s,verifiers:$v,env:$e,verdict:$d,detail:$m}' >> "$LEDGER" 2>/dev/null || true
}

# --- G5: execucao por command + args, sem shell ---
FALHAS=""; LACUNAS=""; SAIDA=""
for a in "${APLICAVEIS[@]}"; do
  ID="$(jq -r '.id // "?"' "$a")"; ECO="$(jq -r '.ecosystem // "?"' "$a")"
  CMD="$(jq -r '.exec.command' "$a")"
  TMO="$(jq -r '.limits.timeout_seconds // 120' "$a")"
  if ! command -v "$CMD" >/dev/null 2>&1; then
    LACUNAS="$LACUNAS
  - $ID: '$CMD' nao esta no PATH (ecossistema $ECO)"; continue
  fi
  mapfile -t ARGS < <(jq -r '.exec.args[]? // empty' "$a" 2>/dev/null)
  # ===================== ESCOPO DELTA (onda 25) =====================
  # A PERGUNTA QUE O PORTAO FAZ MUDA. Ate aqui ele perguntava "esta arvore esta limpa?", cuja
  # resposta nao depende do trabalho do turno. Medido no log deste proprio portao
  # (~/.claude/evidence/*.jsonl): 2942 `fail` contra 2110 `pass` em 5054 registros, e a causa de
  # TODAS as 2942 e a mesma linha - `falharam: python-analyzer`. Um portao que reprova 58% das
  # vezes por divida alheia ensina o operador a ignora-lo, e ai deixa de ser portao.
  #
  # `delta` nao e um meio-termo entre `per_file` e arvore inteira - a onda 24 tentou escolher um
  # lado e falhou nos dois. Sao DUAS CLASSES com escopos diferentes, e a decisao mora em
  # `evidence/lint-delta.py`, fora deste executor, para poder ser exercitada sem repo e sem hook.
  if [ "$(jq -r '.scope // ""' "$a")" = "delta" ]; then
    LD="$HERE/../lint-delta.py"
    if [ ! -f "$LD" ] || ! command -v python3 >/dev/null 2>&1; then
      LACUNAS="$LACUNAS
  - $ID: nucleo de delta ausente ($LD) ou python3 fora do PATH"; continue
    fi
    # RAIZES DERIVADAS, nunca lista de nomes: checkout aninhado e diretorio com `.git` proprio.
    # `.worktrees` e convencao de quem criou, nao contrato - medir por convencao erraria em todo
    # repositorio que use outro nome.
    # C1/C2 DO REFUTADOR. `find -name .git` casa ARQUIVO VAZIO: `: > sub/.git` escondia codigo
    # RASTREADO E MODIFICADO do analisador, com um comando disponivel ao ator governado (medido:
    # exit 2 sem o arquivo, exit 0 com ele). A derivacao DECLARADA era "diretorio com repositorio
    # proprio"; o que era verificado era "existe entrada chamada .git". `rev-parse --git-dir`
    # discrimina. E `maxdepth 4` errava para o outro lado: checkout real em `a/b/c/d/wt` nao era
    # detectado e bloqueava nas duas paradas, porque `git archive` nunca contem untracked e a
    # digital jamais entrava na catraca.
    NESTED="$(cd "$ROOT" && find . -mindepth 2 -maxdepth 8 -name .git -printf '%h\n' 2>/dev/null \
              | sed 's|^\./||' | while IFS= read -r _d; do
                  # F2 DO REFUTADOR, e a correcao anterior estava errada pelo predicado.
                  # `git -C <d> rev-parse --git-dir` SOBE para o repositorio pai quando o `.git`
                  # local e invalido: com `mkdir sub/.git` ele devolvia o `.git` do PAI e a
                  # resposta era sucesso. Medido: exit 2 sem o diretorio falso, exit 0 com ele, e
                  # `git status` IDENTICO nos dois - git nao ve diretorio vazio, entao o bypass era
                  # invisivel. `--resolve-git-dir <caminho>` pergunta o que realmente importa:
                  # ESTE caminho e um diretorio de repositorio? Falso -> 128.
                  # R1 DO REFUTADOR: `--resolve-git-dir` fechou `mkdir sub/.git` e deixou aberta
                  # a porta MAIS BARATA - `git init sub` cria um diretorio de repositorio VALIDO,
                  # e a partir dai tudo debaixo de `sub/` some do julgamento. Medido: `antes
                  # EXIT=2, depois EXIT=0`, com `src/mal.py` staged no repo externo e F821 vivo.
                  # Portao que o ator governado desliga com UM comando nao e portao.
                  #
                  # O discriminante e HISTORIA. Um checkout de verdade tem commits; `git init`
                  # tem zero. Medido nas 5 raizes reais de /var/www/amaral-intern-hub - a origem
                  # desta exclusao: 204, 75, 197, 57 e 310 commits. `git init` recem-criado: 0.
                  # Isto NAO fecha a classe: `git commit` a mais e o bypass volta. Quem fecha e
                  # a declaracao da exclusao (LACUNA logo abaixo) - silencio e que era o defeito.
                  git rev-parse --resolve-git-dir "$_d/.git" >/dev/null 2>&1 \
                    && git -C "$_d" rev-parse --verify -q HEAD >/dev/null 2>&1 \
                    && printf '%s\n' "$_d"
                done | jq -R . | jq -sc .)"
    printf '%s' "$NESTED" | jq -e 'type == "array"' >/dev/null 2>&1 || NESTED='[]'
    # A5/B1/B2 DO REFUTADOR, tres defeitos na mesma extracao.
    #   A5: `... || echo '{}'` sob `pipefail` emitia DUAS saidas quando `git diff` falhava (repo
    #       sem commit): `{}\n{}` chegava ao nucleo, que saia 2, e o hook rotulava como FALHA -
    #       com a mesma linha `falharam: python-analyzer` cujo excesso justifica esta onda.
    #   B1: `git diff HEAD` NAO ve arquivo nao rastreado, mas o analisador o examina. Como `Write`
    #       e `Edit` nao indexam, esse e o caso PADRAO de arquivo novo: toda a higiene introduzida
    #       pelo turno passava em silencio. Medido: untracked exit 0, staged exit 2.
    #   B2: com `core.quotePath` padrao, caminho nao-ASCII sai como `+++ "b/zzz\303\251.py"`, o
    #       parser ignora a linha e mantem o arquivo ANTERIOR - hunk atribuido ao arquivo ERRADO,
    #       falso negativo e falso positivo na mesma execucao.
    #   R2 DO REFUTADOR: o parser decidia o arquivo corrente por `+++ b/`, e sob `-U0` uma LINHA
    #       DE CONTEUDO `++ b/outro.py` sai do diff como `+++ b/outro.py` - indistinguivel do
    #       cabecalho. Medido: `HUNKS = {"alvo.py":[[1,3]], "outro.py":[[104,104]]}` e `EXIT=0`
    #       com F401 vivo. O conteudo do arquivo redirecionava o julgamento do proprio arquivo.
    #       `--output-indicator-new` e a resposta EXATA do git: troca o marcador das linhas de
    #       CONTEUDO sem tocar no cabecalho, entao `+++ b/` volta a ser inforjavel. Medido com
    #       git 2.55.0: conteudo vira `\001++ b/outro.py`, cabecalho segue `+++ b/alvo.py`.
    #   R3 DO REFUTADOR: `core.quotePath=false` estava so no `git diff`. O `ls-files` da MESMA
    #       pipeline (ramo B1, desta onda) nao tinha, entao arquivo novo com nome nao-ASCII
    #       entrava como `"acentua\303\247.py"` e a chave do hunk nunca casava o diagnostico.
    #       Medido: nome acentuado EXIT=0, o mesmo arquivo em ASCII EXIT=2.
    # G82: `untracked` NAO E "criado neste turno". A regra B1 dava a todo arquivo nao rastreado a
    # faixa `[1, 10^9]` - o arquivo inteiro como trabalho do turno - com a premissa de que `Write`
    # e `Edit` nao indexam, entao arquivo novo aparece assim. A premissa cobre o caso comum e e
    # FALSA no geral: `untracked` significa "o git nao rastreia", e nada mais.
    #
    # MEDIDO em /var/www/amaral-intern-hub, 2026-09-03: 400 arquivos untracked em
    # `spokes/jusgrok/`, TODOS com mtime de 2026-07-17 - 48 dias. O portao acusava 79 achados de
    # higiene deles como sendo do turno, num turno cujo trabalho real (PR #150) estava noutros 8
    # arquivos que passavam limpo. O ator escalou corretamente e o portao seguiu barrando.
    #
    # DISCRIMINANTE, e ele usa dado que o portao JA TEM: a hora da parada anterior neste
    # repositorio, gravada no ledger. Arquivo cujo mtime e ANTERIOR a ela nao pode ter sido
    # escrito neste turno. Nao e heuristica de nome nem de diretorio - e ordem temporal.
    #
    # LIMITE DECLARADO: na PRIMEIRA parada de um repositorio nao ha referencia, e ai o
    # comportamento antigo vale (tudo untracked conta como do turno). Fail-closed: erra para o
    # lado de julgar demais, que e ruido, e nao para o de aprovar em silencio.
    # SEGUNDO LIMITE: `mtime` e falsificavel pelo ator governado (`touch`). Isto NAO e controle de
    # seguranca - e correcao de ATRIBUICAO. Quebra por codigo declarado continua sendo julgada na
    # arvore inteira contra a catraca, sem depender de hunk nenhum, entao um arquivo antigo que
    # NAO PARSEIA segue bloqueando.
    REF_EPOCH=""
    _ref_ts="$(tail -1 "$LEDGER" 2>/dev/null | jq -r '.ts // empty' 2>/dev/null || true)"
    [ -n "$_ref_ts" ] && REF_EPOCH="$(date -d "$_ref_ts" +%s 2>/dev/null || true)"
    UNTRACKED_LISTA="$(cd "$ROOT" && git -c core.quotePath=false ls-files --others --exclude-standard 2>/dev/null \
      | while IFS= read -r _f; do
          [ -n "$_f" ] || continue
          if [ -n "$REF_EPOCH" ] && [ -f "$ROOT/$_f" ] \
             && [ "$(stat -c %Y "$ROOT/$_f" 2>/dev/null || echo 0)" -lt "$REF_EPOCH" ]; then
            printf 'PREEXISTENTE %s\n' "$_f"
          else
            printf 'UNTRACKED %s\n' "$_f"
          fi
        done)"
    N_PREEXISTENTE="$(printf '%s\n' "$UNTRACKED_LISTA" | grep -c '^PREEXISTENTE ' || true)"
    case "$N_PREEXISTENTE" in ''|*[!0-9]*) N_PREEXISTENTE=0 ;; esac
    HUNKS="$(cd "$ROOT" && { git -c core.quotePath=false diff -U0 \
               --output-indicator-new="$(printf '\001')" \
               --output-indicator-old="$(printf '\002')" \
               --output-indicator-context="$(printf '\003')" HEAD 2>/dev/null; \
             printf '%s\n' "$UNTRACKED_LISTA"; } | python3 -c '
import sys,re,json,collections
h=collections.defaultdict(list); f=None
# G74. `for l in sys.stdin` decodifica UTF-8 e MORRE em byte que nao seja - e diff carrega o
# conteudo do arquivo, entao qualquer fonte em latin-1 derruba o parser. O executor engolia o
# erro (`2>/dev/null`) e caia em `HUNKS={}`, que nao e "nada foi tocado": e o valor MAIS
# PERMISSIVO possivel, porque nenhum diagnostico cai em hunk nenhum e TODA a higiene e ignorada.
# Medido em /var/www/amaral-intern-hub, o repositorio que justificou esta onda: byte 0xe3,
# `UnicodeDecodeError`, HUNKS com ZERO chaves, `ignorados 80`. O numero que a onda publicou como
# "higiene fora das linhas tocadas" era, naquele repositorio, o portao sem mapa nenhum.
# `surrogateescape` preserva o byte cru sem decodificar: nome de arquivo e marcador de hunk sao
# ASCII, e o conteudo da linha nao e lido por este parser.
for l in sys.stdin.buffer.read().decode("utf-8", "surrogateescape").split("\n"):
    if l.startswith("UNTRACKED "):
        # arquivo nao rastreado ESCRITO NESTE TURNO: todas as linhas sao do turno, faixa total.
        h[l[10:].strip()].append([1, 10**9])
    elif l.startswith("PREEXISTENTE "):
        # G82: nao rastreado, mas com mtime ANTERIOR a parada anterior deste repositorio. NAO
        # recebe faixa: a higiene dele fica fora de hunk, como a de qualquer arquivo que o turno
        # nao tocou. Quebra continua julgada na arvore contra a catraca, sem depender de hunk.
        pass
    elif l.startswith("+++ b/"): f=l[6:].strip()
    elif l.startswith("+++ "): f=None   # forma citada nao reconhecida: melhor nenhum arquivo que o ANTERIOR
    elif l.startswith("@@") and f:
        m=re.search(r"\+(\d+)(?:,(\d+))?", l)
        if m:
            i=int(m.group(1)); n=int(m.group(2) or 1)
            if n: h[f].append([i,i+n-1])
print(json.dumps(dict(h)))' 2>/dev/null)"
    # PARSER MORTO NAO E ARVORE INTOCADA. `|| HUNKS='{}'` tratava falha de leitura como "nenhuma
    # linha foi tocada", que e o valor que faz TODA higiene ser ignorada - aprovacao silenciosa
    # pelo caminho mais largo do portao. Agora a falha e declarada: o turno segue julgado (quebra
    # continua bloqueando contra a catraca), mas o operador ve que o escopo de higiene foi perdido.
    if ! printf '%s' "$HUNKS" | jq -e 'type == "object"' >/dev/null 2>&1; then
      HUNKS='{}'
      LACUNAS="$LACUNAS
  - $ID: o mapa de linhas tocadas NAO pode ser lido (parser de diff falhou). Higiene NAO foi julgada neste turno - so quebra. Escopo de delta perdido, nao vazio."
    fi
    # G82: A EXCLUSAO POR IDADE NUNCA CALA. A licao de G68 vale igual aqui: exclusao que o
    # operador nao ve e indistinguivel de buraco. Vai para stderr em toda execucao em que agir,
    # com o numero e a referencia temporal usada.
    if [ "$N_PREEXISTENTE" -gt 0 ]; then
      { printf 'NAO RASTREADO E ANTERIOR AO TURNO: %s arquivo(s) tiveram a higiene EXCLUIDA do julgamento.\n' "$N_PREEXISTENTE"
        printf '  Referencia: a parada anterior deste repositorio, %s.\n' "$_ref_ts"
        printf '  mtime anterior a ela = nao pode ter sido escrito neste turno. Quebra desses arquivos CONTINUA sendo julgada.\n'
      } >&2
    fi
    # G_VAZIO NO ESCOPO DELTA. A mesma armadilha das outras duas formas, e ela e PIOR aqui:
    # um analisador sobre arvore sem nenhum arquivo do ecossistema devolve LISTA VAZIA, e lista
    # vazia atravessa o nucleo inteiro como "nada a bloquear" - aprovacao sobre nada, com todos os
    # contadores em zero e nenhum sinal. Zero diagnosticos NAO e observacao de limpeza quando nao
    # havia o que observar. `tests/unit/regressao-gate.sh` G20 mede exatamente isto, e reprovou
    # este ramo enquanto a guarda faltava.
    NEXT="$(jq -r '.extensions // [] | length' "$a" 2>/dev/null || echo 0)"
    if [ "${NEXT:-0}" -gt 0 ]; then
      PRESENTES=0
      while IFS= read -r ext; do
        [ -z "$ext" ] && continue
        n="$(git -C "$ROOT" ls-files --cached --others --exclude-standard -- "*${ext}" 2>/dev/null | wc -l)"
        PRESENTES=$((PRESENTES + n))
      done < <(jq -r '.extensions[]? // empty' "$a")
      if [ "$PRESENTES" -eq 0 ]; then
        LACUNAS="$LACUNAS
  - $ID: nenhum arquivo do ecossistema $ECO existe mais na arvore - nada para '$CMD' examinar"
        continue
      fi
    fi
    RAW="$(cd "$ROOT" && timeout "$TMO" "$CMD" "${ARGS[@]}" 2>/dev/null)"; RCTOOL=$?
    if [ "$RCTOOL" -eq 127 ]; then
      LACUNAS="$LACUNAS
  - $ID: binario interno ausente (exit 127)"; continue
    fi
    # A2 DO REFUTADOR, e e regressao direta do G16 ("zero unidades examinadas NAO e aprovacao")
    # dentro do ramo novo. `RCTOOL` so era comparado com 127, e `[ -n "$RAW" ] || RAW='[]'`
    # transformava ferramenta QUE FALHOU em "nenhum diagnostico" - isto e, em APROVACAO. Medido
    # com um shim que sai 2 e nao escreve nada: `GATE exit=0`, saida vazia, ledger `verdict: pass`.
    # O ramo antigo propagava `RC=$?` e reprovava.
    #
    # O criterio e TOLERANTE A FERRAMENTA e nao a codigo de saida: exigir que a saida seja um
    # ARRAY JSON. Arvore limpa devolve `[]`, que passa; ferramenta que morre devolve vazio ou
    # texto de erro, que nao passa. Nao ha lista de codigos por ferramenta para envelhecer.
    if ! printf '%s' "$RAW" | jq -e 'type == "array"' >/dev/null 2>&1; then
      LACUNAS="$LACUNAS
  - $ID: '$CMD' saiu $RCTOOL e NAO produziu array JSON - nada foi analisado. Saida vazia ou ilegivel nao e arvore limpa."
      continue
    fi
    BLPATH="${TOLLENS_BASELINE_DIR:-$HOME/.claude/tollens/baselines}/$(printf '%s' "$ROOT" | sha256sum | cut -c1-16).$ID.json"
    BL=""; [ -f "$BLPATH" ] && BL="$(cat "$BLPATH")"
    MAPA="$(jq -c '.diagnostics.map' "$a")"
    BRK="$(jq -r '.breakage_codes // [] | join(",")' "$a")"
    TMPERR="$(mktemp "${TMPDIR:-/tmp}/tollens-delta.XXXXXX")" || TMPERR=/dev/null
    # F3 DO REFUTADOR, defeito INTRODUZIDO por esta onda. O Linux limita UM argv a
    # MAX_ARG_STRLEN = 131.072 B; a saida do ruff em /var/www/amaral-intern-hub tem 147.920 B e JA
    # estourava. O hook morria com `Argument list too long` (exit 126) e, como a semeadura exige
    # RC==1, o repositorio ficava bloqueado PARA SEMPRE - gravando no ledger a mesma linha
    # `falharam: python-analyzer` cujo excesso justifica a onda. Arquivo nao tem esse limite.
    # G74: `--hunks` tambem estoura MAX_ARG_STRLEN, e nunca tinha estourado so porque o parser
    # de diff morria antes em repositorio grande. Corrigido o parser, o mapa do amaral passou a
    # ter 2685 chaves e o hook morreu com `Argument list too long` (exit 126). Mesmo remedio.
    HUNKF="$(mktemp "${TMPDIR:-/tmp}/tollens-hunks.XXXXXX" 2>/dev/null)" || HUNKF=""
    RAWF="$(mktemp "${TMPDIR:-/tmp}/tollens-raw.XXXXXX" 2>/dev/null)" || RAWF=""
    # C3 DO REVISOR, e e o pior defeito desta serie: `mktemp` que falha nao pode virar aprovacao.
    # Com `HUNKF=""` o nucleo recebia `--hunks-file ""`, que e FALSY, caia no default `--hunks {}`
    # - o mapa vazio, o valor mais permissivo - e o turno passava. Medido ponta a ponta contra o
    # hook EM VIGOR, com TMPDIR nao gravavel:
    #     A) TMPDIR normal ............ rc=2   (bloqueia, correto)
    #     B) TMPDIR nao gravavel ...... rc=0, stdout VAZIO, ledger grava `pass`
    #     D) mesmo snapshot, TMPDIR sao  rc=0  (o `pass` envenenado curto-circuita)
    # O segundo dano e pior que o primeiro: a falha e TRANSITORIA e o `pass` e PERMANENTE para
    # aquele estado de arvore. A raiz e preexistente - `RAWF` faz isto desde F3 -, e esta onda a
    # replicou numa segunda variavel dentro do comentario que dizia estar fechando a classe.
    # Falha de escrita e LACUNA declarada, como ja e para o mapa ilegivel 70 linhas acima.
    if [ -z "$HUNKF" ] || [ -z "$RAWF" ] \
       || ! printf '%s' "$HUNKS" > "$HUNKF" 2>/dev/null \
       || ! printf '%s' "$RAW" > "$RAWF" 2>/dev/null; then
      LACUNAS="$LACUNAS
  - $ID: nao foi possivel gravar os arquivos temporarios do analisador (TMPDIR=${TMPDIR:-/tmp} sem espaco ou sem permissao). NADA foi julgado neste turno - e nada foi gravado no ledger como aprovado."
      [ -n "${HUNKF:-}" ] && rm -f "$HUNKF"
      [ -n "${RAWF:-}" ] && rm -f "$RAWF"
      [ "$TMPERR" != /dev/null ] && rm -f "$TMPERR"
      continue
    fi
    VER="$(python3 "$LD" --raw-file "$RAWF" --map "$MAPA" --strip-prefix "$ROOT/" \
             --hunks-file "$HUNKF" --baseline "$BL" --nested-roots "$NESTED" \
             --breakage-codes "$BRK" 2>"$TMPERR")"; RC=$?
    OUT="$VER
$(cat "$TMPERR" 2>/dev/null)"
    # "O BASELINE NUNCA CALA" era falso ATRAVES DO HOOK: o `OUT` so e impresso quando `RC != 0`,
    # entao na parada em que a tolerancia de fato agia - a que passa - a lista de quebras
    # toleradas ia para lugar nenhum. O nucleo cumpria a invariante; o executor a anulava. O
    # operador precisa ver a divida TODA vez, senao a catraca vira anistia silenciosa.
    # R1: era `grep -q 'QUEBRA PREEXISTENTE TOLERADA'` - uma lista de marcadores conhecidos, que
    # calava tudo que o nucleo passasse a reportar depois. A exclusao por checkout aninhado nasceu
    # muda exatamente por isso. O predicado passou a ser "o nucleo escreveu alguma coisa": quem
    # decide o que o operador precisa ver e o nucleo, nao um grep no executor.
    if [ "$RC" -eq 0 ] && [ -s "$TMPERR" ]; then
      cat "$TMPERR" >&2
    fi
    [ "$TMPERR" != /dev/null ] && rm -f "$TMPERR"
    # `$RAWF` NAO E APAGADO AQUI. Ele era, e o defeito ficou invisivel porque o teste media so o
    # CODIGO DE SAIDA: a semeadura logo abaixo REJULGA com `--raw-file "$RAWF"`, e o arquivo ja
    # nao existia. O nucleo respondia `NAO VERIFICADO: entrada ilegivel ([Errno 2] ...)` e o RC
    # virava 2 - a PRIMEIRA parada de TODO repositorio que semeia catraca terminava em LACUNA em
    # vez de julgamento, com a causa errada na mensagem. Fail-closed, entao nao e falso negativo;
    # e o ramo de delta INERTE exatamente na parada que ele existe para julgar. A limpeza foi para
    # depois do bloco de semeadura, que e o ultimo leitor.
    # SEMEADURA DO BASELINE, e ela e explicita e visivel. Sem baseline o portao reprovaria por
    # quebra preexistente para sempre; semear em silencio seria anistia. Semeia UMA vez, avisa, e
    # a partir dai a catraca so aceita o que ja estava la.
    if [ "$RC" -eq 1 ] && [ ! -f "$BLPATH" ] && [ "${TOLLENS_BASELINE_SEED:-1}" = "1" ]; then
      mkdir -p "$(dirname "$BLPATH")" 2>/dev/null
      # ESCRITA ATOMICA, e ela e obrigatoria aqui. `> "$BLPATH"` cria o arquivo ANTES de o
      # programa rodar: uma emissao que falha deixa um baseline VAZIO que (a) bloqueia a
      # re-semeadura pelo `[ ! -f ]` seguinte e (b) se lido, tolera NADA - o portao volta a
      # reprovar por quebra preexistente para sempre, agora com um arquivo no disco sugerindo que
      # ha catraca. Medido: foi exatamente o que aconteceu na primeira execucao ponta a ponta.
      # O BASELINE VEM DO ESTADO ANTERIOR AO TURNO, NUNCA DO ATUAL. Semear a partir da arvore
      # como ela esta agora ANISTIA a quebra que o proprio turno acabou de introduzir: a primeira
      # parada gravaria a digital do defeito recem-criado e o toleraria para sempre. Isso nao e
      # hipotese - `tests/unit/regressao-gate.sh` G1 mede exatamente essa garantia ("falha em cache
      # NAO vira sucesso na segunda parada") e reprovou com got=0 want=2 na primeira versao deste
      # ramo. O portao de regressao pegou o defeito de desenho antes de qualquer humano.
      #
      # `git archive HEAD` e LEITURA PURA: extrai o commit sem registrar worktree, sem escrever no
      # `.git` do repositorio analisado e sem tocar no indice. `git worktree add` faria as tres.
      # A1 DO REFUTADOR. Semear de `HEAD` fecha so a variante ARVORE SUJA: se o turno COMMITOU a
      # propria quebra - padrao neste repositorio - HEAD E o estado do turno, e a catraca gravava
      # a digital do defeito recem-criado. Medido: baseline com a digital da quebra do proprio
      # turno, 2a e 3a paradas exit 0. Isso refutava, literalmente, o comentario abaixo.
      #
      # `DIFFBASE` ja e calculado na linha 157 como merge-base com o upstream, e e a base que o
      # proprio hook usa para decidir `CHANGED`. Usar outra base para a catraca era incoerencia
      # interna: o turno era medido contra uma base e perdoado contra outra.
      # F1 DO REFUTADOR, e a correcao anterior fechou o REPRO e nao a CLASSE. `${DIFFBASE:-HEAD}`
      # devolvia HEAD sempre que nao ha upstream NEM remoto - o estado normal de qualquer projeto
      # antes do primeiro `git remote add`. Ali HEAD E o estado do turno, e a catraca voltava a
      # gravar a digital da quebra recem-criada: medido, mesma digital que o mutante `SEEDREF=HEAD`
      # produz. Fallback silencioso para uma base que se sabe errada e pior que recusar.
      # ARVORE VAZIA NAO E UMA BASE, e sim a AUSENCIA de uma. `BASE` cai no hash da arvore vazia
      # quando nenhum candidato de remoto resolve (linha ~150), e isso e legitimo para `CHANGED` -
      # `git diff <arvore-vazia> HEAD` lista tudo. Para a CATRACA seria destrutivo: semear dali
      # grava um baseline que tolera NADA e, pelo `[ ! -f "$BLPATH" ]`, IMPEDE a re-semeadura
      # quando uma base real aparecer. E a armadilha A4 por outra porta - catraca inutil que nao
      # se recria. Sem base real, recusar e a unica resposta honesta.
      _VAZIA="$(git -C "$ROOT" hash-object -t tree /dev/null 2>/dev/null || true)"
      SEEDREF="$DIFFBASE"
      [ -n "$_VAZIA" ] && [ "$SEEDREF" = "$_VAZIA" ] && SEEDREF=""
      SEEDDIR=""; RAWBASE=""
      if [ -z "$SEEDREF" ]; then
        # F8 DO REFUTADOR: esta mensagem so ia para `LACUNAS`, e `LACUNAS` e reportado DEPOIS de
        # `FALHAS` - com `reporta` saindo antes. Como a semeadura so e tentada quando o julgamento
        # BLOQUEOU, havia sempre falha, e a lacuna era codigo morto: o operador via "VERIFICACAO
        # FALHOU" e nenhuma pista de que o bloqueio nao passaria sozinho. A razao da recusa vai
        # tambem para a SAIDA da falha, porque e ela que explica por que o portao nao destrava.
        _MSG="sem base anterior ao turno (upstream ausente ou apontando para ref inexistente, e nenhum candidato de remoto resolve). A catraca NAO foi semeada: semear da arvore vazia toleraria NADA e impediria a re-semeadura. Configure o upstream, ou semeie a mao com \`--emit-baseline\`."
        SAIDA="$SAIDA
--- $ID: $_MSG ---"
        LACUNAS="$LACUNAS
  - $ID: $_MSG"
      else
        SEEDDIR="$(mktemp -d "${TMPDIR:-/tmp}/tollens-seed.XXXXXX")" || SEEDDIR=""
      fi
      if [ -n "$SEEDDIR" ] && git -C "$ROOT" archive "$SEEDREF" 2>/dev/null | tar -x -C "$SEEDDIR" 2>/dev/null; then
        RAWBASE="$(cd "$SEEDDIR" && timeout "$TMO" "$CMD" "${ARGS[@]}" 2>/dev/null)"
        # A4 DO REFUTADOR: `|| RAWBASE='[]'` fazia analisador que MORRE na semeadura gravar catraca
        # VAZIA - e o `[ ! -f "$BLPATH" ]` seguinte impedia recriar, entao a quebra preexistente
        # bloqueava PARA SEMPRE. Saida ilegivel deixa `RAWBASE` vazio e a semeadura nao acontece.
        printf '%s' "$RAWBASE" | jq -e 'type == "array"' >/dev/null 2>&1 || RAWBASE=""
      fi
      BLTMP="$(mktemp "${BLPATH}.XXXXXX")" || BLTMP=""
      RAWBF="$(mktemp "${TMPDIR:-/tmp}/tollens-rawb.XXXXXX")" || RAWBF=""
      [ -n "$RAWBASE" ] && printf '%s' "$RAWBASE" > "$RAWBF" 2>/dev/null
      if [ -n "$BLTMP" ] && [ -n "$RAWBASE" ] && python3 "$LD" --raw-file "$RAWBF" --map "$MAPA" \
           --strip-prefix "$SEEDDIR/" \
           --nested-roots "$NESTED" --breakage-codes "$BRK" --emit-baseline > "$BLTMP" 2>/dev/null \
         && [ -s "$BLTMP" ] && jq -e 'type == "array"' "$BLTMP" >/dev/null 2>&1 \
         && mv -f "$BLTMP" "$BLPATH"; then
        LACUNAS="$LACUNAS
  - $ID: catraca CRIADA agora ($(jq -r 'length' "$BLPATH" 2>/dev/null) defeito(s) preexistente(s) da base anterior ao turno passam a ser TOLERADOS, e sao reportados a cada execucao). Este turno FOI julgado contra ela. A lacuna declarada nao e o julgamento: e a TOLERANCIA recem-concedida, que nenhum humano revisou. Revise $BLPATH, ou apague-o para recriar."
        # REJULGA CONTRA O BASELINE RECEM-CRIADO, nunca `RC=0` por decreto. Forcar zero aqui
        # fazia a PRIMEIRA parada passar sempre - inclusive quando a quebra era do proprio turno,
        # que e o oposto do que a catraca existe para fazer. O baseline vem do estado ANTERIOR;
        # se o defeito nao esta nele, ele e novo e continua bloqueando.
        BL="$(cat "$BLPATH" 2>/dev/null)"
        TMPERR2="$(mktemp "${TMPDIR:-/tmp}/tollens-delta.XXXXXX")" || TMPERR2=/dev/null
        VER="$(python3 "$LD" --raw-file "$RAWF" --map "$MAPA" --strip-prefix "$ROOT/" \
                 --hunks-file "$HUNKF" --baseline "$BL" --nested-roots "$NESTED" \
                 --breakage-codes "$BRK" 2>"$TMPERR2")"; RC=$?
        OUT="$VER
$(cat "$TMPERR2" 2>/dev/null)"
        [ "$TMPERR2" != /dev/null ] && rm -f "$TMPERR2"
        [ -n "${SEEDDIR:-}" ] && rm -rf "$SEEDDIR"
      else
        [ -n "${BLTMP:-}" ] && rm -f "$BLTMP"
        [ -n "${SEEDDIR:-}" ] && rm -rf "$SEEDDIR"
        LACUNAS="$LACUNAS
  - $ID: NAO foi possivel semear o baseline de quebra - o turno segue julgado SEM catraca, e quebra preexistente continua bloqueando. Nada foi gravado."
      fi
    fi
    # ultimo leitor de $RAWF ja passou (o rejulgamento pos-semeadura).
    [ -n "${RAWF:-}" ] && rm -f "$RAWF"
    [ -n "${RAWBF:-}" ] && rm -f "$RAWBF"
    [ -n "${HUNKF:-}" ] && rm -f "$HUNKF"
  elif [ "$(jq -r '.per_file // false' "$a")" = "true" ]; then
    # G_VAZIO (per_file): um adaptador per_file so examina os arquivos de CHANGED que ainda
    # existem no disco (`[ -f "$ROOT/$f" ] || continue`). Se apagar, renomear-com-conteudo-
    # divergente ou deixar um symlink quebrado faz TODOS os arquivos casados desaparecerem, o
    # laco nunca roda, RC fica no valor inicial 0, e o adaptador caia no ramo de APROVADO sem
    # examinar nada. Um laco que nao roda nao e observacao de sucesso - e ausencia de
    # observacao. EXAMINADOS conta unidades REALMENTE processadas; zero decide o veredito,
    # nao o RC (que nunca saiu do valor de inicializacao).
    RC=0; OUT=""; EXAMINADOS=0
    while IFS= read -r ext; do
      [ -z "$ext" ] && continue
      while IFS= read -r f; do
        [ -f "$ROOT/$f" ] || continue
        EXAMINADOS=$((EXAMINADOS + 1))
        O="$(cd "$ROOT" && timeout "$TMO" "$CMD" "${ARGS[@]}" "$f" 2>&1)" || { RC=1; OUT="$OUT
$O"; }
      done < <(printf '%s\n' "$CHANGED" | grep -- "${ext}\$" || true)
    done < <(jq -r '.extensions[]? // empty' "$a")
    if [ "$EXAMINADOS" -eq 0 ]; then
      # NAO e FALHA: um commit que so apaga arquivo e legitimo, e "reprovado" mentiria sobre a
      # causa. E LACUNA: o estado correto e "nao verifiquei isto", nomeando a razao.
      LACUNAS="$LACUNAS
  - $ID: nenhum arquivo casado com as extensoes de $ECO segue presente no disco (apagado, renomeado ou symlink quebrado) - zero unidades examinadas"
      continue
    fi
  else
    # G_VAZIO (repositorio inteiro): o mesmo defeito tem uma segunda forma. Um adaptador NAO
    # per_file roda sobre a ARVORE (o `.` de `exec.args`), nao sobre CHANGED - por isso apagar
    # UM arquivo normalmente nao esvazia o ecossistema inteiro. Mas quando o arquivo apagado
    # era o ULTIMO do ecossistema, a ferramenta roda sobre uma arvore vazia daquela linguagem.
    # Medido: `ruff check .` numa arvore sem nenhum `.py` imprime "No Python files found" e
    # sai 0 - aprovacao sobre nada. A deteccao NAO depende do texto de cada ferramenta (por
    # ferramenta seria fragil: `go vet`/`cargo fmt` erram com RC!=0 no mesmo cenario, ruff nao) -
    # conta arquivos do ecossistema presentes na ARVORE ATUAL (rastreados + untracked nao
    # ignorados), a mesma fonte que decide o que este gate considera "existir". So se aplica a
    # adaptador que DECLARA extensoes: o comando aprovado de `.claude/verify.json` (G8/G13-G15)
    # nao declara `extensions` - e um comando de repositorio inteiro sem escopo por tipo de
    # arquivo, e tratar "sem extensoes declaradas" como "zero unidades" o desligaria sempre.
    NEXT="$(jq -r '.extensions // [] | length' "$a" 2>/dev/null || echo 0)"
    if [ "${NEXT:-0}" -gt 0 ]; then
      PRESENTES=0
      while IFS= read -r ext; do
        [ -z "$ext" ] && continue
        n="$(git -C "$ROOT" ls-files --cached --others --exclude-standard -- "*${ext}" 2>/dev/null | wc -l)"
        PRESENTES=$((PRESENTES + n))
      done < <(jq -r '.extensions[]? // empty' "$a")
      if [ "$PRESENTES" -eq 0 ]; then
        LACUNAS="$LACUNAS
  - $ID: nenhum arquivo do ecossistema $ECO existe mais na arvore - nada para '$CMD' examinar"
        continue
      fi
    fi
    OUT="$(cd "$ROOT" && timeout "$TMO" "$CMD" "${ARGS[@]}" 2>&1)"; RC=$?
  fi
  if [ "$RC" -eq 127 ]; then
    LACUNAS="$LACUNAS
  - $ID: binario interno ausente (exit 127)"; continue
  fi
  if [ "$RC" -ne 0 ]; then
    FALHAS="$FALHAS $ID"
    SAIDA="$SAIDA
--- $ID ($ECO) exit=$RC ---
$(printf '%s\n' "$OUT" | tail -12)"
  fi
done

# --- veredito conjuntivo ---
if [ -n "$FALHAS" ]; then
  registra "fail" "falharam:$FALHAS"
  # G77: a partir do limiar, a mensagem PARA de se repetir e passa a nomear a repeticao. O
  # veredito nao muda - o defeito continua la -, mas dizer a mesma coisa pela N-esima vez e o
  # comportamento que produziu 336 negativas identicas sobre uma arvore que nunca mudou.
  LACO=""
  if [ "$TENTATIVAS_IDENTICAS" -ge 3 ]; then
    LACO="

*** ESTA E A $((TENTATIVAS_IDENTICAS + 1))a PARADA COM ESTE MESMO ESTADO DE ARVORE. ***
Snapshot, verificadores e ambiente sao IDENTICOS aos das $TENTATIVAS_IDENTICAS anteriores: nada do
que voce fez desde entao mudou o que este portao mede. Repetir a correcao nao vai mudar o
resultado. As saidas REAIS, e sao estas:
  1. Mudar de fato um dos arquivos que o verificador aponta acima - o snapshot e digest de HEAD
     mais o de cada arquivo alterado, entao edicao que nao toca esses arquivos nao muda nada aqui.
  2. Se o defeito e PREEXISTENTE e nao do seu turno, dizer isso ao operador com o nome do arquivo
     e a linha, em vez de tentar de novo. O portao nao distingue sozinho divida herdada de
     regressao fora dos codigos declarados em \`breakage_codes\`.
  3. Se o verificador esta errado sobre este codigo, isso e um defeito do adaptador e precisa ser
     reportado ao operador - nao contornado.
NAO tente uma quarta variacao da mesma correcao sem antes dizer ao operador o que esta travando."
  fi
  # G81: DEPOIS DE ESCALAR, BLOQUEAR DE NOVO E DEADLOCK, NAO PORTAO.
  #
  # O bloco $LACO acima manda o ator PARAR de tentar variacoes e dizer ao operador o que trava.
  # Um ator que obedece nao tem mais nada a fazer no turno - e o portao bloqueava a parada dele
  # assim mesmo. A mensagem exigia uma acao que ela propria punia.
  #
  # MEDIDO em /var/www/amaral-intern-hub, 2026-09-03: 107 paradas no dia, 3 estados distintos,
  # 91 no MESMO estado. O ator tinha escalado corretamente (os 79 achados sao higiene de WIP
  # untracked de OUTRO desenvolvedor, com mtime de 2026-07-17 - 48 dias) e se recusava, tambem
  # corretamente, a editar trabalho alheio. O runtime precisou intervir com o proprio teto
  # ("A hook blocked the turn from ending 9 consecutive times - overriding").
  #
  # A partir do LIMITE DE ESCALADA o veredito continua NEGATIVO e o diagnostico continua inteiro,
  # mas deixa de BLOQUEAR: vira additionalContext. O que o portao existe para impedir e o ator
  # declarar sucesso falso - e isso o texto continua impedindo, porque ele chega igual. O que ele
  # nao pode fazer e impedir o ator de ENTREGAR A DECISAO ao humano.
  #
  # O limite e 6, o dobro do limiar de laco (3), e a escolha e declarada: 3 paradas para o ator
  # perceber, mais 3 para escalar. Nao ha experimento por tras do numero; e piso conservador, e
  # trocar exige medir.
  LIMITE_ESCALADA=6
  if [ "$TENTATIVAS_IDENTICAS" -ge "$LIMITE_ESCALADA" ]; then
    aviso "GATE - VERIFICACAO FALHOU (nao bloqueante: $TENTATIVAS_IDENTICAS paradas identicas).
Verificadores aplicados:$ECOS
Reprovaram:$FALHAS
$SAIDA
---
Estado: NOT_VERIFIED. O veredito continua NEGATIVO - NAO declare corrigido, resolvido nem verde.
O portao parou de BLOQUEAR porque este e o estado identico numero $TENTATIVAS_IDENTICAS: continuar
barrando nao adiciona informacao e impede voce de entregar a decisao ao operador, que e o que a
mensagem anterior mandou fazer. Entregue o diagnostico acima e PARE.$AVISO_REPO$LACO"
  fi
  reporta "GATE - VERIFICACAO FALHOU. O snapshot NAO e um candidato valido.
Verificadores aplicados:$ECOS
Reprovaram:$FALHAS
$SAIDA
---
Estado: NOT_VERIFIED. O sinal e externo - nao declare corrigido por auto-avaliacao.
Este hook nao certifica nada: mesmo passando, o veredito final e da CI sobre o SHA.$AVISO_REPO$LACO"
fi
if [ -n "$LACUNAS" ]; then
  registra "gap" "lacunas:$LACUNAS"
  reporta "GATE - LACUNA DE COBERTURA, nao falha de codigo.$LACUNAS
Nenhuma verificacao externa cobriu esses caminhos neste turno.
Estado: NAO VERIFICADO - declare a lacuna ao usuario. Nao diga verde nem vermelho.$AVISO_REPO"
fi
registra "pass" "verificadores:$ECOS"
# passou, mas ha comando do repo nao aprovado: avisar sem bloquear
[ -n "$AVISO_REPO" ] && aviso "GATE - verificadores genericos passaram.$AVISO_REPO"
exit 0
