#!/usr/bin/env bash
# CONTRATO DOS INSTALADORES E DA VARREDURA DE ARENA.
#
# POR QUE ESTE ARQUIVO EXISTE, e a razao e uma assimetria medida, nao uma preferencia de estilo.
#
# A onda 12 fechou tres defeitos de severidade alta ou critica, todos no caminho PRIVILEGIADO ou
# DESTRUTIVO, e todos verificados a mao uma vez cada:
#
#   1. `install/apply.sh --help` INSTALAVA. Medido: exit 0, 66 arquivos escritos no destino.
#      Qualquer argumento que nao fosse exatamente `--dry-run` caia no ramo de aplicar.
#   2. `install/apply-managed.sh --revert --dry-run` executava um revert REAL e privilegiado: o
#      ramo fazia `exec worker "$@"` antes de qualquer contagem, e o worker so inspeciona `$1`.
#   3. A varredura de arena usava glob terminado em BARRA, o que faz `-d`, `find` e `rm -rf`
#      ATRAVESSAREM symlink. Com /tmp 1777, qualquer usuario local plantava
#      `tollens-arena.pwn -> ~/.claude` e o proximo arnes apagava a politica. Reproduzido
#      executando o bloco literal do arquivo contra um symlink.
#
# Ao mesmo tempo, a classe de MENOR severidade da mesma onda - referencia publicada que nao
# resolve - ganhou tres portoes automatizados. O portao final nomeou a inversao: a classe
# destrutiva ficou com comentario citando medicao manual de uma vez so.
#
# Medicao manual nao regride sozinha; ela regride quando alguem edita o `case`. E esta onda existe
# porque as correcoes manualmente verificadas da onda 11 precisaram de correcao.
#
# ESCOPO: contrato de ARGUMENTO e recusa de caminho hostil. Nao testa o conteudo do que e
# instalado - disso cuidam install/verify.sh e tests/unit/managed.sh.
set -uo pipefail
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
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tollens-ci.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------------------------
echo "== CI1. apply.sh: so --dry-run e ausencia de argumento chegam a escrever =="

apply_escreveu(){ # $1..= argumentos; ecoa "<exit> <arquivos escritos>"
  local d rc n
  d="$(mktemp -d "$TMP/dest.XXXXXX")"
  CLAUDE_HOME="$d" bash install/apply.sh "$@" >/dev/null 2>&1; rc=$?
  n="$(find "$d" -type f 2>/dev/null | wc -l)"
  echo "$rc $n"
}

r="$(apply_escreveu --help)"
chk "--help NAO instala"                    "${r#* }" 0
chk "--help sai 0 (e ajuda, nao erro)"      "${r%% *}" 0

r="$(apply_escreveu --dryrun)"
chk "typo --dryrun e RECUSADO"              "${r%% *}" 2
chk "typo --dryrun nao escreve"             "${r#* }" 0

r="$(apply_escreveu --dry_run)"
chk "typo --dry_run e RECUSADO"             "${r%% *}" 2

r="$(apply_escreveu --dry-run)"
chk "--dry-run sai 0"                       "${r%% *}" 0
chk "--dry-run NAO escreve (portao, nao filtro)" "${r#* }" 0

r="$(apply_escreveu --dry-run extra)"
chk "argumento em excesso e RECUSADO"       "${r%% *}" 2

r="$(apply_escreveu)"
chk "sem argumento instala"                 "${r%% *}" 0
[ "${r#* }" -gt 40 ] && { echo "  PASS  sem argumento escreve o conjunto (${r#* } arquivos)"; P=$((P+1)); } \
                     || { echo "  FAIL  sem argumento deveria escrever muitos (got=${r#* })"; F=$((F+1)); }

# ---------------------------------------------------------------------------------------------
echo "== CI2. apply.sh: backup cobre edicao do operador antes de sobrescrever =="
# A semeadura byte-exata torna o PRIMEIRO apply um no-op. Ela nao protege o SEGUNDO, e o segundo
# e exatamente o caso descrito por escrito em install/manifest.sh. Sem este caso, a perda de
# politica escrita a mao passaria em silencio.
#
# ONDA 22b: O ESPECIME MUDOU, A GARANTIA NAO. Este caso usava `CLAUDE.md`, que saiu da projecao de
# usuario quando o kernel passou a viver so no escopo managed. A garantia testada - `apply.sh`
# preserva a edicao do operador antes de convergir - continua valendo para os 48 componentes que
# permaneceram, e apagar o caso junto com o especime teria removido cobertura real por um motivo
# que nao e o dela. O especime passou a ser um hook, que e componente de manifesto com destino
# ARQUIVO (nao diretorio), a mesma forma que `CLAUDE.md` tinha.
D="$(mktemp -d "$TMP/bk.XXXXXX")"
_ESPECIME="$(awk -F'\t' '$1=="hook"{print $3; exit}' install/manifest.lock)"
[ -n "$_ESPECIME" ] || { echo "  FAIL  CI2 sem especime: nenhum hook no manifesto"; F=$((F+1)); }
mkdir -p "$D/$(dirname "$_ESPECIME")"
printf 'EDICAO DIVERGENTE DO OPERADOR\n' > "$D/$_ESPECIME"
SHA_ORIG="$(sha256sum "$D/$_ESPECIME" | cut -d' ' -f1)"
CLAUDE_HOME="$D" bash install/apply.sh >/dev/null 2>&1
BK="$(find "$D/backups" -name "$(basename "$_ESPECIME")" 2>/dev/null | head -1)"
chk "existe backup do componente sobrescrito" "$([ -n "$BK" ] && echo sim || echo nao)" sim
chk "o backup preserva o conteudo ORIGINAL" \
    "$([ -n "$BK" ] && [ "$(sha256sum "$BK" | cut -d' ' -f1)" = "$SHA_ORIG" ] && echo sim || echo nao)" sim
chk "o destino foi de fato sobrescrito (o caso e real)" \
    "$([ "$(sha256sum "$D/$_ESPECIME" | cut -d' ' -f1)" != "$SHA_ORIG" ] && echo sim || echo nao)" sim

# ---------------------------------------------------------------------------------------------
echo "== CI3. apply-managed.sh: os quatro modos passam, o resto e recusado =="
# REGRESSAO REGISTRADA: a primeira versao do endurecimento listou so --verify|--revert e jogou
# --dry-run e --enforce em exit 2. Isso quebrou o unico passo publicado que liga
# allowManagedHooksOnly (docs/HANDOFF.md) e empurraria o operador a chamar o worker DIRETO,
# pulando snapshot, rollback e a checagem de raiz root-owned do ADR 0026. Endurecimento que
# empurra o operador para fora do mecanismo de seguranca e regressao de seguranca.
mg(){ MANAGED_PREFIX="$(mktemp -d "$TMP/mg.XXXXXX")" bash install/apply-managed.sh "$@" >/dev/null 2>&1; echo $?; }
for m in --dry-run --enforce --verify --revert --help; do
  rc="$(mg "$m")"
  [ "$rc" -ne 2 ] && { echo "  PASS  modo $m nao e recusado como desconhecido (exit=$rc)"; P=$((P+1)); } \
                  || { echo "  FAIL  modo $m foi RECUSADO (exit=2) - contrato quebrado"; F=$((F+1)); }
done
chk "argumento desconhecido e recusado"        "$(mg --typo)" 2
chk "--revert --dry-run e RECUSADO (era revert real)" "$(mg --revert --dry-run)" 2
chk "--verify extra e recusado ANTES do exec"  "$(mg --verify extra)" 2

echo "== CI3b. --dry-run nao abre transacao (nem a temporaria) =="
# HISTORICO EM DUAS CAMADAS, e a segunda e o motivo deste caso existir na forma atual.
#
# Onda 13: o ensaio terminava com "managed transaction committed". Mensagem verde declarando
# estado que nao existe, no caminho que roda como root. Corrigido com um guard DEPOIS do
# snapshot, que passou a imprimir "NENHUMA escrita foi feita".
#
# Onda 14, auditoria externa: essa frase era AMPLA DEMAIS. Antes do guard o script ja fazia
# `mktemp -d` e, com destino existente, `cp -a "$OPT" "$REC/opt"` - a arvore managed inteira
# copiada para o temporario. O teste media `find "$MANAGED_PREFIX" -type f` = 0, entao provava
# "nenhum destino managed foi alterado" e NAO "nenhuma escrita ocorreu". Trocar uma claim falsa
# por outra ligeiramente ampla demais e a mesma classe, um grau menor.
#
# A correcao foi arquitetural: `--dry-run` sai no `exec` junto de `--verify|--revert`, antes de
# qualquer maquinaria transacional. DISCRIMINADOR: com TMPDIR nao-gravavel, a versao antiga
# morria no `mktemp` (exit 1) e a atual nao o alcanca (exit 0). E o unico teste que distingue
# "nao escreveu no destino" de "nao escreveu em lugar nenhum".
_D="$(mktemp -d "$TMP/dry.XXXXXX")"
mkdir -p "$_D/opt/tollens"; echo marcador > "$_D/opt/tollens/preexistente"
_saida="$(MANAGED_PREFIX="$_D" bash install/apply-managed.sh --dry-run 2>&1)"
chk "--dry-run nao altera o destino managed" \
    "$(find "$_D" -type f | wc -l)" 1
chk "--dry-run NAO declara transacao commitada" \
    "$(printf '%s' "$_saida" | grep -c 'transaction committed')" 0

_RO="$(mktemp -d "$TMP/ro.XXXXXX")"; chmod 500 "$_RO"
TMPDIR="$_RO" MANAGED_PREFIX="$_D" bash install/apply-managed.sh --dry-run >/dev/null 2>&1
chk "--dry-run nao toca o temporario (TMPDIR nao-gravavel nao o quebra)" "$?" 0
chmod 700 "$_RO"

# ANTIVACUIDADE em dois eixos: o apply REAL tem de continuar declarando o commit, e tem de
# continuar DEPENDENDO do temporario - senao o caso acima passaria por o mecanismo
# transacional ter sumido para todos, e nao apenas para o ensaio.
_D2="$(mktemp -d "$TMP/real.XXXXXX")"
chk "o apply real AINDA declara a transacao" \
    "$(MANAGED_PREFIX="$_D2" bash install/apply-managed.sh 2>&1 | grep -c 'transaction committed')" 1
_RO2="$(mktemp -d "$TMP/ro2.XXXXXX")"; chmod 500 "$_RO2"
TMPDIR="$_RO2" MANAGED_PREFIX="$_D2" bash install/apply-managed.sh >/dev/null 2>&1
chk "o apply real AINDA depende do temporario (morre sem ele)" "$?" 1
chmod 700 "$_RO2"

echo "== CI4. o worker tem contagem propria (e invocavel direto) =="
mw(){ MANAGED_PREFIX="$(mktemp -d "$TMP/mw.XXXXXX")" bash install/apply-managed-worker.sh "$@" >/dev/null 2>&1; echo $?; }
chk "worker recusa argumento em excesso"       "$(mw --revert --dry-run)" 64

# ---------------------------------------------------------------------------------------------
echo "== CI5. manifest.sh nao deixa manifesto truncado quando a fonte some =="
# A cadeia medida: fonte ausente -> componente sai do manifesto -> apply.sh ve "removido" e a
# convergencia apaga o arquivo VIVO correspondente. O `exit 1` dentro de `{ } > "$OUT"` nao
# bastava: o redirecionamento ja truncara o destino ao ENTRAR no grupo.
CL="$TMP/clone"; mkdir -p "$CL"
tar -cf - --exclude=./.git --exclude='*/__pycache__' . 2>/dev/null | ( cd "$CL" && tar -xf - 2>/dev/null )
ANTES="$(wc -l < "$CL/install/manifest.lock")"
rm -f "$CL/execution/config/CLAUDE.md"
( cd "$CL" && bash install/manifest.sh install/manifest.lock >/dev/null 2>&1 ); rc=$?
DEPOIS="$(wc -l < "$CL/install/manifest.lock")"
# ONDA 22b. A GUARDA CONTINUA, O QUE ELA PROTEGE MUDOU. Ate aqui o kernel era projetado para
# `~/.claude/CLAUDE.md` e emitia linha `config` no manifesto; a terceira assercao conferia que
# essa linha sobrevivia. O kernel passou a viver so no escopo managed, entao nao ha mais linha
# `config` - e a guarda deixou de proteger a linha para proteger a FONTE CANONICA, que continua
# sendo `execution/config/CLAUDE.md` e continua sendo de onde o deploy managed copia. Se ela
# sumir, o deploy managed passa a copiar nada, e falhar alto continua sendo o certo.
chk "manifest.sh reprova quando a fonte canonica do kernel some" "$rc" 1
chk "e o manifesto NAO foi truncado"                             "$DEPOIS" "$ANTES"
chk "o manifesto do clone permanece integro"                     "$(awk -F'\t' 'NF>=4' "$CL/install/manifest.lock" | wc -l)" \
                                                                 "$(awk -F'\t' 'NF>=4' install/manifest.lock | wc -l)"

echo "== CI6. apply.sh aborta se uma origem do manifesto nao existe =="
# Antes, `cp -a` nao tinha retorno conferido e o contador somava assim mesmo: o instalador
# imprimia "componentes instalados: 49" com o componente AUSENTE no destino.
#
# ONDA 22b. O CASO PERDEU O ESTIMULO, NAO A GARANTIA. Ele reaproveitava o clone do CI5, onde
# `execution/config/CLAUDE.md` fora removido - e isso deixava uma origem do manifesto ausente.
# Com o kernel fora da projecao de usuario, remover aquele arquivo nao produz mais origem ausente
# nenhuma, entao `apply.sh` retornava 0 corretamente e o caso reprovava por ter deixado de
# exercitar a condicao. Um teste que passa a nao estimular o que testa e teste inerte, e a onda 20
# ja pagou por um mutante nessa situacao. O estimulo passou a ser explicito: remover a origem de
# um componente que ESTA no manifesto.
DD="$(mktemp -d "$TMP/miss.XXXXXX")"
_ORIG_AUSENTE="$(awk -F"\t" '/^#/{next} NF>=4{print $2; exit}' "$CL/install/manifest.lock")"
rm -rf "$CL/$_ORIG_AUSENTE"
chk "origem ausente aborta a instalacao" \
    "$( cd "$CL" && CLAUDE_HOME="$DD" bash install/apply.sh >/dev/null 2>&1; echo $? )" 1

# ---------------------------------------------------------------------------------------------
echo "== CI7. a varredura de arena nao atravessa symlink nem toca diretorio alheio =="
# CRITICO da onda 11, achado por auditoria: glob com barra final faz -d/find/rm -rf seguirem o
# link. Este caso extrai o laco REAL do arquivo em vez de reimplementa-lo - um teste contra copia
# do laco passaria mesmo se o original regredisse.
AT="$(mktemp -d "$TMP/arena.XXXXXX")"
VIT="$TMP/vitima"; mkdir -p "$VIT/sub"; echo dados > "$VIT/importante.txt"
ln -s "$VIT" "$AT/tollens-arena.pwn"
touch -d '3 days ago' "$VIT" 2>/dev/null
sed -n '/^  for _a in /,/^  done$/p' tests/lib/arena.sh > "$TMP/varredura.sh"
if [ ! -s "$TMP/varredura.sh" ]; then
  echo "  NAO VERIFICADO: nao consegui extrair o laco de varredura de tests/lib/arena.sh" >&2
  F=$((F+1))
else
  TMPDIR="$AT" bash "$TMP/varredura.sh" >/dev/null 2>&1
  chk "o alvo do symlink sobreviveu"  "$([ -f "$VIT/importante.txt" ] && echo sim || echo nao)" sim
  chk "o symlink em si foi ignorado"  "$([ -L "$AT/tollens-arena.pwn" ] && echo sim || echo nao)" sim
fi

# ANTIVACUIDADE: o caso acima so significa algo se o laco de fato varre. Uma arena PROPRIA, sem
# dono vivo e velha, tem de ser removida - senao "vitima sobreviveu" seria verdade por inacao.
MORTA="$AT/tollens-arena.morta"; mkdir -p "$MORTA"; echo 999999 > "$MORTA/.arena-pid"
TMPDIR="$AT" bash "$TMP/varredura.sh" >/dev/null 2>&1
chk "arena propria de dono morto E removida (o laco varre mesmo)" \
    "$([ -d "$MORTA" ] && echo nao || echo sim)" sim


# ---------------------------------------------------------------------------------------------
echo "== CI8. o instalador de usuario nao reprova por um escopo que nao instala =="
# REGRESSAO MEDIDA NA CI, d4fd41b, runs 33007234824 e 33007230205, ambos vermelhos. `apply.sh`
# termina chamando `install/verify.sh`, e quando este passou a auditar TAMBEM o escopo managed o
# exit dele virou o exit do instalador: em toda maquina sem a fase managed implantada - o caso
# comum, e um estado que exige root para corrigir (ADR 0026) - `apply.sh` imprimia "componentes
# instalados: 48" e saia 1.
#
# ESTE E O CASO QUE A MAQUINA LOCAL NAO EXERCITA. Aqui `/etc/claude-code` esta implantado, entao a
# suite ficou verde localmente enquanto reprovava na CI, e a verificacao local respondeu sobre um
# ambiente em que a condicao nao ocorre. `TOLLENS_MANAGED_DIR` desloca o escopo auditado, entao os
# dois estados passam a ser exercitados em QUALQUER maquina, sem depender do que ha em /etc.
_MGD_VAZIO="$(mktemp -d "$TMP/mgd0.XXXXXX")"
_MGD_ATOR="$(mktemp -d "$TMP/mgd1.XXXXXX")"
mkdir -p "$_MGD_ATOR/.claude/agents" "$_MGD_ATOR/.claude/skills"
# O CONTEUDO TEM DE CONFERIR PARA A FIXTURA ISOLAR A POSSE. Com o verificador conferindo digest do
# kernel (onda 22d), um `CLAUDE.md` vazio dispara DIVERGENTE (5) antes de chegar a GRAVAVEL (4), e
# o caso passaria a medir outra coisa. Medido: got=5 want=4.
cp -f execution/config/CLAUDE.md "$_MGD_ATOR/CLAUDE.md"; : > "$_MGD_ATOR/managed-settings.json"
# A FIXTURA TEM DE SER NAO-ROOT INDEPENDENTE DE QUEM RODA A SUITE. O criterio de `verify.sh` e a
# POSSE: root -> IMPOSTO, qualquer outro -> GRAVAVEL. Rodando como root - contentor, ou `sudo bash
# tests/...` - o diretorio que a suite acaba de criar nasce root-owned e e LEGITIMAMENTE imposto,
# entao o caso deixava de exercitar a condicao e reprovava por isso (medido: got=0 want=4 sob
# ubuntu:24.04 como root). Sob root, quem cria pode reatribuir; sob usuario comum ja esta certo.
[ "$(id -u)" -eq 0 ] && chown -R 65534:65534 "$_MGD_ATOR" 2>/dev/null
# CONTROLE POSITIVO DA FIXTURA: sem isto, um `chown` que falhasse em silencio faria a assercao
# seguinte medir o mesmo estado do caso AUSENTE e ainda assim parecer especifica.
chk "a fixtura GRAVAVEL nao pertence a root (a condicao ocorre)" \
    "$(stat -c '%U' "$_MGD_ATOR/CLAUDE.md" 2>/dev/null | grep -c '^root$')" 0

# A PROJECAO DE USUARIO E ISOLADA, e nao por preciosismo: sem `CLAUDE_HOME` proprio estas
# assercoes leem o `~/.claude` VIVO da maquina, entao qualquer divergencia pendente ali - um
# componente editado e ainda nao reaplicado, que e o estado normal durante uma onda - devolve exit
# 1 e o caso passa a medir a bancada em vez do escopo managed. Medido: as duas reprovaram com
# got=1 por essa razao antes deste isolamento.
_DA="$(mktemp -d "$TMP/ap0.XXXXXX")"
_OUTA="$(CLAUDE_HOME="$_DA" TOLLENS_MANAGED_DIR="$_MGD_VAZIO" bash install/apply.sh 2>&1)"
_RCA=$?
CLAUDE_HOME="$_DA" TOLLENS_MANAGED_DIR="$_MGD_VAZIO" bash install/verify.sh >/dev/null 2>&1
chk "verify: managed AUSENTE tem codigo proprio (3, nao 1)"        "$?" 3
CLAUDE_HOME="$_DA" TOLLENS_MANAGED_DIR="$_MGD_ATOR" bash install/verify.sh >/dev/null 2>&1
chk "verify: managed GRAVAVEL pelo ator tem codigo proprio (4)"    "$?" 4

# O instalador: exit 0 com a projecao de usuario integra, nos DOIS estados de managed. Nenhum dos
# dois e consertavel por ele, e nos dois os 48 componentes de usuario ficaram como o manifesto diz.
set -- "$_RCA"
chk "apply: instala com exit 0 mesmo sem a fase managed"           "$1" 0
chk "apply: e publica o passo acionavel em vez de calar" \
    "$(printf '%s' "$_OUTA" | grep -c 'apply-managed.sh --enforce')" 1
_DB="$(mktemp -d "$TMP/ap1.XXXXXX")"
CLAUDE_HOME="$_DB" TOLLENS_MANAGED_DIR="$_MGD_ATOR" bash install/apply.sh >/dev/null 2>&1
chk "apply: exit 0 tambem com managed gravavel (nao e dele consertar)" "$?" 0

# ANTIVACUIDADE: os casos acima so significam algo se o verificador AINDA reprovar o que e dele.
#
# JUSTIFICATIVA CORRIGIDA (F5 do refutador). A frase anterior dizia que sem esta assercao "trocar o
# corpo de `verify.sh` por `exit 0` passaria em todos eles". Medido numa copia com `verify.sh`
# reduzido a `exit 0`: TRES das outras assercoes ja reprovavam, entao o mutante trivial ja morria
# sem esta linha. O que ELA mata, e nenhuma outra, e o mutante de ORDEM: testar `M_AUSENTE` ANTES
# de `DRIFT` faz uma projecao de usuario divergente sair 3 em vez de 1, e a divergencia do escopo
# pelo qual o instalador E responsavel deixa de reprovar. Medido com a ordem invertida: got=3
# want=1, exit 1. A assercao fica; a razao publicada e esta.
_DC="$(mktemp -d "$TMP/ap2.XXXXXX")"
CLAUDE_HOME="$_DC" bash install/apply.sh >/dev/null 2>&1
printf 'DIVERGENCIA INTRODUZIDA PELO TESTE\n' >> "$_DC/$_ESPECIME"
TOLLENS_MANAGED_DIR="$_MGD_VAZIO" CLAUDE_HOME="$_DC" bash install/verify.sh >/dev/null 2>&1
chk "verify AINDA reprova (1) o que E do escopo de usuario"        "$?" 1

# F4 DO REFUTADOR: o ramo que a onda 22c EXISTE para criar nao tinha teste. Mutar `1) exit 1` para
# `1) exit 0` em `install/apply.sh` deixava esta suite VERDE - seis assercoes conferiam `exit 0` e
# nenhuma conferia que a divergencia de USUARIO ainda propaga. Antivacuidade sobre `verify.sh` nao
# cobre isso, porque a mudanca de 22c esta no `case` do instalador, um nivel acima.
# O estimulo usa o orfao de topo: `CLAUDE.md` saiu do manifesto e `apply.sh` so o remove com o
# `managed-files.lock` presente; sem o lock ele sobrevive, `verify.sh` o conta como ORFAO, e orfao
# e divergencia da projecao de usuario - exatamente o que este instalador tem de propagar.
_DD="$(mktemp -d "$TMP/ap3.XXXXXX")"
CLAUDE_HOME="$_DD" TOLLENS_MANAGED_DIR="$_MGD_VAZIO" bash install/apply.sh >/dev/null 2>&1
rm -f "$_DD/tollens/managed-files.lock"
printf 'KERNEL ORFAO DE VERSAO ANTERIOR\n' > "$_DD/CLAUDE.md"
CLAUDE_HOME="$_DD" TOLLENS_MANAGED_DIR="$_MGD_VAZIO" bash install/apply.sh >/dev/null 2>&1
chk "apply PROPAGA 1 quando a projecao de USUARIO diverge"        "$?" 1
# SEM PIPE PARA `grep -q`: sob `pipefail`, o `grep` sai cedo, o `verify.sh` leva SIGPIPE e o
# status vira 141. Medido: got=141 want=0. A saida e capturada antes de ser filtrada.
_OUTD="$(CLAUDE_HOME="$_DD" TOLLENS_MANAGED_DIR="$_MGD_VAZIO" bash install/verify.sh 2>&1)"
chk "e o orfao de TOPO e nomeado (nao so contado)" \
    "$(printf '%s' "$_OUTD" | grep -cE '^  ORFAO +CLAUDE\.md')" 1

# ---------------------------------------------------------------------------------------------
echo "== CI9. o hook de sessao le o verificador que existe, nao o que existia =="
# MESMA FAMILIA DO G45: a onda 22 renomeou a linha de resumo de `conformidade:` para
# `PROJECAO USUARIO:`, e o hook seguia procurando a etiqueta antiga. `grep` que nao casa devolve
# vazio, e vazio no campo `summary` do heartbeat le-se como "nada a relatar" - degradacao muda.
chk "o hook casa a etiqueta que o verificador emite HOJE" \
    "$(bash install/verify.sh 2>&1 | grep -cE '^(PROJECAO USUARIO|conformidade):')" 1
chk "e o casador do hook cobre as duas etiquetas" \
    "$(grep -c "grep -E '\^(PROJECAO USUARIO|conformidade):'" control/hooks/session-integrity.sh)" 2

# ---------------------------------------------------------------------------------------------
echo "== CI10. todo arquivo que um hook CHAMA esta no manifesto =="
# DEFEITO MEDIDO NO RUNTIME, onda 25. O ramo `scope: delta` do `verify-gate.sh` chama
# `$HERE/../lint-delta.py`, e esse arquivo nao estava em manifesto nenhum - logo nao chegava a
# NENHUMA das duas projecoes. O hook implantado passou a declarar `nucleo de delta ausente` a cada
# parada: nao reprovava, mas tambem NAO VERIFICAVA NADA. Quem reportou foi o proprio Stop-gate, na
# tela do operador.
#
# POR QUE NENHUM TESTE VIA: os casos ponta a ponta rodam o hook a partir do REPOSITORIO, onde
# `evidence/hooks/../lint-delta.py` resolve. A copia INSTALADA nunca era exercitada - a mesma
# classe do G46, verificar num ambiente em que a condicao de falha nao ocorre.
#
# A guarda e DERIVADA, nao lista: varre os hooks do manifesto procurando referencia a
# `$HERE/../<arquivo>` e exige que o alvo esteja declarado. Uma lista escrita a mao envelheceria
# no primeiro hook novo, que e o defeito que ela existe para impedir.
_FALTANDO=""
while IFS=$'\t' read -r _t _origem _destino _sha; do
  [ "$_t" = "hook" ] || continue
  [ -f "$_origem" ] || continue
  while IFS= read -r _ref; do
    [ -n "$_ref" ] || continue
    awk -F'\t' -v r="$_ref" '!/^#/ && $3==r {found=1} END{exit !found}' install/manifest.lock \
      || _FALTANDO="$_FALTANDO $(basename "$_origem")->$_ref"
  done < <(grep -oE '\$HERE/\.\./[A-Za-z0-9._-]+' "$_origem" 2>/dev/null | sed 's|.*/||' \
             | grep -vx '\.\.' | sort -u)   # `.` esta na classe: `$HERE/../../x` casaria e daria `..`
done < install/manifest.lock
chk "nenhum hook chama arquivo fora do manifesto" "${_FALTANDO:-nenhum}" "nenhum"

# ANTIVACUIDADE: a varredura so significa algo se de fato encontrar referencias. Zero referencias
# encontradas faria a assercao acima passar por nao ter olhado nada.
_REFS=0
while IFS=$'\t' read -r _t _origem _resto; do
  [ "$_t" = "hook" ] && [ -f "$_origem" ] || continue
  _n="$(grep -cE '\$HERE/\.\./[A-Za-z0-9._-]+' "$_origem" 2>/dev/null || true)"
  _REFS=$((_REFS + ${_n:-0}))   # `|| echo 0` emitiria DUAS linhas no caso zero (grep -c imprime 0 e sai 1)
done < install/manifest.lock
chk "  e a varredura ACHOU referencias (nao passou por vacuidade)" \
    "$([ "$_REFS" -ge 1 ] && echo sim || echo nao)" sim

# ONDA 21c. PINO DE CONTAGEM, exigido pelo oraculo novo em `tests/unit/regressao-gate.sh`: suite
# que NAO fixa a propria contagem nao pode ter o numero publicado em `docs/status.generated.md`,
# porque um caso pulado em silencio mudaria o artefato sem deixar a suite vermelha - que e o G22.
# Esta suite tem contagem estavel medida (47); o pino a torna verificavel em vez de presumida.
echo "== CI11. suite que invoca o Stop-gate isola o ledger =="
# G76. `verify-gate.sh` grava em `${EVIDENCE_LEDGER_DIR:-$HOME/.claude/evidence}` e NENHUMA suite
# exportava a variavel: toda execucao de teste injetava paradas SINTETICAS no ledger operacional,
# no mesmo diretorio que serve de evidencia sobre uso real. Medido em 2026-09-02, ao tentar medir
# a distribuicao de vereditos: 1637 arquivos de ledger criados desde 2026-09-01, quase todos de
# teste, tornando os dois dias inutilizaveis como medida.
# O dano tem SEGUNDA direcao, e ela e pior: o ledger tambem e CACHE - `pass` do mesmo
# `(snapshot, verifiers, env)` curto-circuita -, entao um teste podia herdar `pass` de OUTRO teste
# com a mesma arvore e nunca executar o verificador que ele afirma medir.
# DERIVADO, nao lista: varre tests/ atras de quem invoca o hook e exige a variavel no mesmo
# arquivo. Lista escrita a mao envelheceria na primeira suite nova. O predicado de INVOCACAO e
# TEXTUAL e por isso INCLUSIVO DEMAIS - `tests/unit/managed.sh` casa por uma string dentro de
# fixture, nao por execucao. Mantido assim de proposito: separar citado de executado exigiria
# parsear shell, e o custo de exigir a variavel a mais e uma linha, enquanto o custo de deixar
# passar e devolver a suite ao ledger do operador. Este repositorio ja declara esse tradeoff na
# CAMADA 2 de cobertura.
#
# A3 DO REVISOR: o predicado de ISOLAMENTO era `grep -q 'EVIDENCE_LEDGER_DIR'` - satisfeito por
# um COMENTARIO que so cita a variavel, sem nenhuma atribuicao. Demonstrado com uma suite
# sintetica que executa o gate e so MENCIONA a variavel: o predicado antigo APROVAVA (nada foi
# isolado). O predicado abaixo passa a exigir ATRIBUICAO (`EVIDENCE_LEDGER_DIR=`, com ou sem
# `export` na frente), no mesmo espirito textual do predicado de invocacao acima - ainda nao
# parseia shell, mas deixa de aceitar CITACAO como ISOLAMENTO.
_PADRAO_ISOLA_LEDGER='(^|[^A-Za-z0-9_])(export[[:space:]]+)?EVIDENCE_LEDGER_DIR='
# AUTO-REFERENCIA MEDIDA (a mesma classe do A3): este proprio arquivo CASA o predicado de
# INVOCACAO, porque o comentario duas linhas abaixo cita `bash "$GATE"` entre backticks para
# EXPLICAR o predicado - nao para executa-lo. O comentario anterior a este ja afirmava "a mencao
# em comentario nao conta, senao este proprio arquivo entraria na varredura", mas nada no CODIGO
# impedia isso: era afirmacao, nao guarda. Confirmado abaixo, e so entao pulado.
grep -qE '(bash|sh) +"?\$?\{?[A-Za-z_]*\}?[^"]*verify-gate\.sh|bash "\$GATE"' \
  "tests/unit/contrato-de-instalador.sh"
chk "  CI11: auto-referencia confirmada - este arquivo casa a deteccao de invocacao por comentario" $? 0
_SEM_LEDGER=""
for _t in tests/unit/*.sh tests/mutation/*.sh; do
  [ -f "$_t" ] || continue
  # PULA A SI MESMO. Sem isto, o predicado de isolamento abaixo tambem CASARIA neste arquivo
  # pela mesma razao estrutural: a linha que DEFINE `_PADRAO_ISOLA_LEDGER` contem o texto
  # `EVIDENCE_LEDGER_DIR=` (tem que conter, e o padrao que ela declara), entao sem o skip este
  # arquivo aprovaria de novo por auto-referencia - so que no predicado NOVO em vez do antigo.
  [ "$_t" = "tests/unit/contrato-de-instalador.sh" ] && continue
  grep -qE '(bash|sh) +"?\$?\{?[A-Za-z_]*\}?[^"]*verify-gate\.sh|bash "\$GATE"' "$_t" || continue
  # FALSO POSITIVO MEDIDO, e ele estava VIVO em `HEAD` antes desta correcao: o predicado e
  # TEXTUAL e nao segue `source`. `tests/unit/delta-e2e.sh` isola o ledger, mas recebe o
  # isolamento de `tests/lib/ambiente.sh` - a FONTE UNICA criada justamente para nao duplicar a
  # atribuicao em cada suite. O predicado acusava a suite que faz a coisa certa pelo caminho
  # certo. Reproduzido num worktree limpo de HEAD: `FAIL nenhuma suite escreve no ledger do
  # operador (got= tests/unit/delta-e2e.sh)`, PASS=52 esperado 53 - sem nenhuma alteracao local.
  #
  # A correcao NAO afrouxa: carregar `lib/ambiente.sh` so vale como isolamento se aquele arquivo
  # DE FATO atribuir a variavel, o que e conferido aqui, a cada volta. Se alguem esvaziar
  # `ambiente.sh`, toda suite que dependia dele volta a ser acusada - que e o comportamento
  # correto.
  if grep -qE "$_PADRAO_ISOLA_LEDGER" "$_t"; then
    :
  elif grep -qE '(^|[^A-Za-z0-9_])\.[[:space:]]+[^;]*lib/ambiente\.sh' "$_t" \
       && grep -qE "$_PADRAO_ISOLA_LEDGER" tests/lib/ambiente.sh; then
    :
  else
    _SEM_LEDGER="$_SEM_LEDGER $_t"
  fi
done
chk "nenhuma suite escreve no ledger do operador" "$_SEM_LEDGER" ""
# ANTIVACUIDADE: se o padrao de busca parar de casar, a varredura passa por nao achar ninguem.
_N_INVOCAM=0
for _t in tests/unit/*.sh tests/mutation/*.sh; do
  grep -qE '(bash|sh) +"?\$?\{?[A-Za-z_]*\}?[^"]*verify-gate\.sh|bash "\$GATE"' "$_t" 2>/dev/null && _N_INVOCAM=$((_N_INVOCAM+1))
done
chk "  e a varredura de fato encontra suites que invocam o hook" "$([ "$_N_INVOCAM" -ge 3 ] && echo sim || echo "nao($_N_INVOCAM)")" sim

echo
echo "== CI11a. o predicado de isolamento discrimina ATRIBUICAO de MENCAO (suites sinteticas, "
echo "nao a arvore real - a mesma classe de prova que o A3 do revisor mediu contra uma suite "
echo "que so cita a variavel e o predicado antigo aprovava) =="
_CI11D="$(mktemp -d "$TMP/ci11.XXXXXX")"
cat > "$_CI11D/so-menciona.sh" <<'FIX'
#!/usr/bin/env bash
# nota para quem ler: verify-gate.sh grava em EVIDENCE_LEDGER_DIR, mas esta suite nunca a
# exporta - o comentario CITA a variavel sem isolar nada.
bash "$GATE"
FIX
cat > "$_CI11D/atribui.sh" <<'FIX'
#!/usr/bin/env bash
export EVIDENCE_LEDGER_DIR="$TMP/ledger"
bash "$GATE"
FIX
grep -qE '(bash|sh) +"?\$?\{?[A-Za-z_]*\}?[^"]*verify-gate\.sh|bash "\$GATE"' "$_CI11D/so-menciona.sh"
chk "CI11a: a fixture sintetica de fato invoca o gate (candidata valida a isolamento)" $? 0
grep -qE "$_PADRAO_ISOLA_LEDGER" "$_CI11D/so-menciona.sh"
chk "  CI11a: o predicado novo RECUSA a suite que so MENCIONA a variavel (nada isolado)" $? 1
grep -qE "$_PADRAO_ISOLA_LEDGER" "$_CI11D/atribui.sh"
chk "  CI11a: o mesmo predicado ACEITA a suite que de fato ATRIBUI a variavel" $? 0

EXPECTED=53
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi

echo
echo "================ PASS=$P  FAIL=$F ================"
[ "$F" -eq 0 ] && echo "contrato de instalador verde" || echo "contrato de instalador VERMELHO"
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
