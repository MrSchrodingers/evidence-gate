#!/usr/bin/env bash
# RAIZ DE CONFIANCA (fase 2) - `install/apply-managed.sh` e `install/hooks-spec.sh`.
#
# O QUE ESTA SUITE PODE E O QUE NAO PODE PROVAR. Ela exercita TODA a logica do instalador
# managed contra um prefixo temporario: copia, digest, geracao do JSON, deteccao de
# adulteracao, portao de ativacao e reversao. Ela NAO prova que o runtime honra
# `allowManagedHooksOnly`, porque isso exige escrever em `/etc/claude-code` com root - e a
# afirmacao correspondente so pode ser feita a partir de medicao com o binario, registrada em
# `evidence/observations/`. Confundir as duas seria dizer que o artefato esta verificado porque
# a fixture passou.
#
# MG6 e o caso mais importante. Ele existe porque a PRIMEIRA versao do instalador gravava o
# `managed-settings.json` - com `allowManagedHooksOnly: true` - ANTES de conferir se o deploy
# estava completo. Consequencia: deploy incompleto deixaria o sistema sem hooks managed E com
# os de usuario bloqueados; o mecanismo inteiro cairia, que e a armadilha nomeada no handoff.
# E a mesma classe do defeito do `--dry-run` do ADR 0022, adendo 2: garantia nova, correta,
# mal posicionada em relacao a escrita.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
REPO="$PWD"
AM="$REPO/install/apply-managed.sh"
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

command -v jq >/dev/null 2>&1 || { echo "NAO VERIFICADO: jq ausente." >&2; exit 2; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
# LEDGER ISOLADO (G76/CI11). Esta suite NAO executa o hook - ela manipula copias dele em fixture,
# e o guarda CI11 casa a mencao em posicao executavel por INCLUSAO EXCESSIVA, de proposito: o
# predicado textual nao separa `bash <caminho>/verify-gate.sh` executado de citado, e errar para o
# lado de exigir a variavel custa uma linha, enquanto errar para o outro devolve a suite ao ledger
# do operador. Se algum caso desta suite passar a executar uma copia, a isolacao ja esta aqui.
export EVIDENCE_LEDGER_DIR="$T/ledger"
FK="$T/raiz"; mkdir -p "$FK"

echo "== MG1. a especificacao de hooks tem FONTE UNICA =="
# Duas copias da mesma lista divergem em silencio: e o defeito que originou este repositorio.
A="$T/user.json"; B="$T/managed.json"
bash install/hooks-spec.sh '$HOME/.claude/hooks' > "$A"
bash install/hooks-spec.sh '/opt/tollens/hooks' > "$B"
chk "o spec e JSON valido nos dois escopos" \
    "$(jq -e . "$A" >/dev/null 2>&1 && jq -e . "$B" >/dev/null 2>&1 && echo sim || echo nao)" "sim"
est(){ jq -S '[paths(scalars) as $p | [$p|map(tostring)|join(".")]] | flatten | sort' "$1"; }
chk "  a ESTRUTURA e identica nos dois escopos" \
    "$(cmp -s <(est "$A") <(est "$B") && echo sim || echo nao)" "sim"
bn(){ jq -r '[..|objects|select(has("command"))|.command] | map(sub(".*/";"")) | sort | join(",")' "$1"; }
chk "  os scripts sao os mesmos, so muda o caminho" "$(bn "$A")" "$(bn "$B")"
# ONDA 22d. O ESPERADO E DERIVADO DO ESCOPO IRMAO, NAO PINADO EM LITERAL. Ate aqui o numero era
# `18`, escrito a mao, e ele nao descrevia nenhuma garantia: descrevia quantos hooks a spec tinha
# no dia em que a linha foi escrita. Registrar um hook novo - operacao esperada - reprovava esta
# assercao por CONTAGEM, e o unico conserto disponivel era subir o literal, o que a torna um
# carimbo. Medido: got=21 want=18 ao registrar o `activation-log.sh`. O que a assercao existe para
# provar e que `$HOME` sai LITERAL, e isso se verifica contra o escopo MANAGED, cuja base e um
# caminho absoluto: os dois tem de ter o MESMO numero de comandos com base, senao um dos dois teve
# a base expandida ou perdida.
chk "  o \$HOME sai LITERAL no escopo de usuario (quem expande e o runtime)" \
    "$(grep -c 'bash \$HOME/\.claude/hooks/' "$A" | tr -d ' ')" \
    "$(grep -c 'bash /opt/tollens/hooks/' "$B" | tr -d ' ')"
# ANTIVACUIDADE: derivar de zero contra zero passaria. A spec tem de ter comandos com base.
chk "  e a spec de fato registra comandos com base (a derivacao nao e vacua)" \
    "$([ "$(grep -c 'bash /opt/tollens/hooks/' "$B" | tr -d ' ')" -ge 14 ] && echo sim || echo nao)" "sim"
# Sem esta assercao, alguem poderia reintroduzir a lista dentro do apply.sh e a fonte unica
# viraria fonte dupla sem nenhum sinal.
chk "  apply.sh NAO reintroduziu copia embutida da lista" \
    "$(grep -c '"type":"command","command":"bash \$HOME' install/apply.sh | tr -d ' ')" "0"

echo "== MG2. --dry-run nao escreve nada =="
rm -rf "$FK"; mkdir -p "$FK"
rc=$(MANAGED_PREFIX="$FK" bash "$AM" --dry-run >/dev/null 2>&1; echo $?)
chk "o plano executa (exit 0)" "$rc" 0
chk "  e o disco continua vazio" "$([ -d "$FK/opt" ] || [ -d "$FK/etc" ] && echo escreveu || echo vazio)" "vazio"

echo "== MG3. deploy instala a POLITICA inteira, nao so os hooks =="
# Politica root-owned lendo tabela de adaptadores user-owned e raiz de confianca so no nome:
# o ator desligaria o gate pela tabela, sem tocar no hook.
rc=$(MANAGED_PREFIX="$FK" bash "$AM" >/dev/null 2>&1; echo $?)
chk "deploy executa (exit 0)" "$rc" 0
N=$(find "$FK/opt/tollens" -type f 2>/dev/null | wc -l | tr -d ' ')
# `lib` entrou na onda 25 e a lista aqui tem de casar com `tipos_politica` do worker: a POLITICA
# carrega as bibliotecas que seus hooks chamam. Sem `lib` nesta linha o esperado ficava em 31 e o
# caso reprovava com got=32 - e o defeito seria do TESTE, nao do deploy.
ESPERADO=$(awk -F'\t' '!/^#/ && ($1=="hook"||$1=="adapter"||$1=="doctool"||$1=="lib")' install/manifest.lock | wc -l | tr -d ' ')
chk "  todos os $ESPERADO componentes de politica no disco" "$N" "$ESPERADO"
chk "  ha hook, adaptador E doctool (nao so hook)" \
    "$([ -d "$FK/opt/tollens/hooks" ] && [ -d "$FK/opt/tollens/adapters" ] && [ -d "$FK/opt/tollens/document-tools" ] && echo sim || echo nao)" "sim"
rc=$(MANAGED_PREFIX="$FK" bash "$AM" --verify >/dev/null 2>&1; echo $?)
chk "  --verify aprova o estado recem-instalado" "$rc" 0
chk "  allowManagedHooksOnly nasce FALSE (deploy nao ativa)" \
    "$(jq -r '.allowManagedHooksOnly' "$FK/etc/claude-code/managed-settings.json")" "false"

echo "== MG4. todo hook DECLARADO na politica existe no disco =="
# Politica apontando para caminho vazio, com enforcement ligado, e o mecanismo desligado com
# aparencia de ligado.
MISS=0
while read -r cmd; do
  p="${cmd#bash }"; [ -f "$p" ] || MISS=$((MISS+1))
done < <(jq -r '[.hooks|..|objects|select(has("command"))|.command]|unique[]' "$FK/etc/claude-code/managed-settings.json")
chk "nenhum caminho declarado aponta para o vazio" "$MISS" "0"

echo "== MG5. adulteracao de UM byte reprova a conformidade =="
printf '\n# adulterado\n' >> "$FK/opt/tollens/hooks/verify-gate.sh"
rc=$(MANAGED_PREFIX="$FK" bash "$AM" --verify >/dev/null 2>&1; echo $?)
chk "--verify REPROVA politica adulterada" "$rc" 1
MANAGED_PREFIX="$FK" bash "$AM" >/dev/null 2>&1
rc=$(MANAGED_PREFIX="$FK" bash "$AM" --verify >/dev/null 2>&1; echo $?)
chk "  e reinstalar reconverge" "$rc" 0

echo "== MG6. --enforce RECUSA ativar sobre deploy incompleto =="
# O caso que impede derrubar o mecanismo inteiro. Manifesto sabotado via override, para nao
# mutar o arquivo real: se a suite morresse no meio, o repositorio ficaria quebrado.
MANSAB="$T/manifest-sabotado.lock"
awk -F'\t' 'BEGIN{OFS="\t"} $1=="hook" && ++c==1 {$2="control/hooks/NAO-EXISTE.sh"} {print}' \
    install/manifest.lock > "$MANSAB"
chk "o manifesto sabotado difere do real (senao o caso e vacuo)" \
    "$(cmp -s "$MANSAB" install/manifest.lock && echo igual || echo difere)" "difere"
FK2="$T/raiz2"; mkdir -p "$FK2/etc/claude-code"
printf '{"allowManagedHooksOnly":false}\n' > "$FK2/etc/claude-code/managed-settings.json"
rc=$(MANAGED_PREFIX="$FK2" MANAGED_MANIFEST="$MANSAB" bash "$AM" --enforce >/dev/null 2>&1; echo $?)
chk "--enforce reprova com deploy incompleto" "$rc" 1
chk "  e allowManagedHooksOnly NAO foi ativado" \
    "$(jq -r '.allowManagedHooksOnly' "$FK2/etc/claude-code/managed-settings.json")" "false"

echo "== MG7. --enforce ativa quando o deploy esta completo =="
rc=$(MANAGED_PREFIX="$FK" bash "$AM" --enforce >/dev/null 2>&1; echo $?)
chk "--enforce executa (exit 0)" "$rc" 0
chk "  allowManagedHooksOnly=true" \
    "$(jq -r '.allowManagedHooksOnly' "$FK/etc/claude-code/managed-settings.json")" "true"

echo "== MG8. --revert desfaz por completo =="
rc=$(MANAGED_PREFIX="$FK" bash "$AM" --revert >/dev/null 2>&1; echo $?)
chk "--revert executa (exit 0)" "$rc" 0
chk "  a politica saiu do disco" \
    "$([ -e "$FK/opt/tollens" ] || [ -e "$FK/etc/claude-code/managed-settings.json" ] && echo sobrou || echo limpo)" "limpo"
# DEFEITO ENCONTRADO POR ESTE CASO: o backup `pre-tollens` era criado mesmo quando o
# arquivo existente havia sido escrito pelo PROPRIO instalador (deploy seguido de --enforce).
# O --revert entao restaurava esse "backup" e RECRIAVA a politica. Reversao que nao reverte e
# pior que ausencia de reversao: o operador acredita ter voltado ao estado anterior.
chk "  e nao sobrou backup espurio do proprio instalador" \
    "$([ -e "$FK/etc/claude-code/managed-settings.json.pre-tollens" ] && echo sobrou || echo limpo)" "limpo"

echo "== MG9. manifesto com caminho hostil e REJEITADO, sem escrever nada =="
# ACHADO DE AUDITORIA, com PoC executada: o manifesto e arquivo do REPOSITORIO, isto e, esta no
# espaco de escrita do ator governado, e suas colunas eram usadas verbatim como caminho de
# `mkdir -p`, `cp -f` e `rm -rf` - com o script rodando como ROOT. Medido antes da correcao:
#   destino=../../../ZONA/vitima.conf  -> arquivo FORA do prefixo sobrescrito
#   destino=../../../ZONA (origem=dir) -> `rm -rf` destruiu o diretorio FORA do prefixo
# Sob sudo isso e escrita e remocao arbitrarias como root a partir de dado que o ator controla.
# A raiz de confianca seria instalada A PARTIR DE entrada nao confiavel - a inversao da tese.
ZONA="$T/zona-proibida"; mkdir -p "$ZONA"
printf 'intocavel\n' > "$ZONA/vitima.conf"
HOSTIL="$T/hostil.lock"
printf 'hook\tevidence/hooks/subagent-contract.sh\t../../../zona-proibida/vitima.conf\tdead\n' > "$HOSTIL"
FK3="$T/raiz3"; mkdir -p "$FK3"
rc=$(MANAGED_PREFIX="$FK3" MANAGED_MANIFEST="$HOSTIL" bash "$AM" >/dev/null 2>&1; echo $?)
chk "destino com '..' reprova" "$rc" 1
chk "  a vitima FORA do prefixo esta intacta" "$(cat "$ZONA/vitima.conf" 2>/dev/null)" "intocavel"
chk "  e nada foi escrito no prefixo" "$([ -e "$FK3/opt" ] && echo escreveu || echo vazio)" "vazio"
printf 'hook\t/etc/hostname\thooks/vazado.sh\tdead\n' > "$HOSTIL"
rc=$(MANAGED_PREFIX="$FK3" MANAGED_MANIFEST="$HOSTIL" bash "$AM" >/dev/null 2>&1; echo $?)
chk "origem ABSOLUTA reprova (copiaria arquivo de fora do repo)" "$rc" 1
# CONTROLE: sem ele, um instalador que reprovasse SEMPRE passaria nos quatro casos acima.
rc=$(MANAGED_PREFIX="$T/raiz4" bash "$AM" >/dev/null 2>&1; echo $?)
chk "  e o manifesto REAL continua sendo aceito" "$rc" 0

echo "== MG10. o gerador da politica nao aceita injecao de JSON =="
# O valor do caminho-base ia para `sed "s|@BASE@|$BASE|g"` sobre o texto do JSON. Um valor com
# aspas FECHA a string e ABRE OBJETO NOVO, e o resultado continua JSON VALIDO - o `jq -e .` do
# consumidor nao barra. E esse documento vira politica em /etc/claude-code/.
INJ='/x","timeout":1},{"type":"command","command":"id > /tmp/PWNED_MG10","z":"/y'
OUTJ="$T/inj.json"
bash install/hooks-spec.sh "$INJ" > "$OUTJ" 2>/dev/null
chk "o documento gerado continua sendo JSON valido" \
    "$(jq -e . "$OUTJ" >/dev/null 2>&1 && echo sim || echo nao)" "sim"
# A propriedade nao e "nao gera JSON": e o valor hostil virar UM ESCALAR, sem criar entradas
# de hook novas. Contamos a estrutura, nao o texto.
chk "  o numero de hooks NAO aumentou (valor virou escalar, nao estrutura)" \
    "$(jq '[..|objects|select(has("command"))|.command]|length' "$OUTJ")" \
    "$(bash install/hooks-spec.sh /base/inocente | jq '[..|objects|select(has("command"))|.command]|length')"
chk "  e nenhum comando e exatamente o payload injetado" \
    "$(jq -r '[..|objects|select(has("command"))|.command]|map(select(.=="id > /tmp/PWNED_MG10"))|length' "$OUTJ")" "0"
# `&` era expandido pelo sed como retrovisor, corrompendo o caminho em silencio.
chk "  '&' no caminho nao vira retrovisor" \
    "$(bash install/hooks-spec.sh '/tmp/&&&' | jq -r '.Stop[0].hooks[0].command')" \
    "bash /tmp/&&&/verify-gate.sh"

echo "== MG11. conjunto de politica VAZIO nao e conformidade =="
# ACHADO DE REVISAO INDEPENDENTE, com PoC executada. O portao contava DIVERGENCIA e nunca
# POPULACAO. Com o conjunto vazio: o laco de copia nao copia nada, a conformidade nao itera
# nada, "0 divergentes" era lido como aprovacao, e `--enforce` gravava
# allowManagedHooksOnly:true apontando para 14 caminhos INEXISTENTES - o mecanismo inteiro de
# hooks desligado com aparencia de ligado, que e a armadilha que este arquivo diz tratar.
# MG6 nao pegava: ele sabota UMA entrada (div=1); nao esvazia o conjunto.
# Ausencia de divergencia num conjunto vazio e vacuamente verdadeira.
VAZIO="$T/vazio.lock"
# `tr` nos separadores e o gatilho realista: qualquer normalizacao de whitespace, filtro de
# git ou renome de coluna produz o mesmo efeito.
tr '\t' ' ' < install/manifest.lock > "$VAZIO"
chk "o manifesto degradado de fato produz ZERO componentes" \
    "$(awk -F'\t' '!/^#/ && ($1=="hook"||$1=="adapter"||$1=="doctool")' "$VAZIO" | wc -l | tr -d ' ')" "0"
FK5="$T/raiz5"; mkdir -p "$FK5"
rc=$(MANAGED_PREFIX="$FK5" MANAGED_MANIFEST="$VAZIO" bash "$AM" --enforce >/dev/null 2>&1; echo $?)
chk "  --enforce REPROVA com conjunto vazio" "$rc" 1
chk "  e a politica nem chegou a ser criada" \
    "$([ -f "$FK5/etc/claude-code/managed-settings.json" ] && echo criada || echo ausente)" "ausente"
rc=$(MANAGED_PREFIX="$FK5" MANAGED_MANIFEST="$VAZIO" bash "$AM" --verify >/dev/null 2>&1; echo $?)
chk "  --verify tambem REPROVA (vazio nao e conforme)" "$rc" 1

echo "== MG12. --revert nao apaga politica que nao foi este instalador que escreveu =="
# O comentario do ramo de reversao ja prometia "Remove SOMENTE o que este script cria", e o
# codigo nao cumpria: apagava QUALQUER managed-settings.json, inclusive politica corporativa de
# outra ferramenta - que pode conter permissions.deny - sem backup, sem aviso, e sob sudo.
# Promessa em comentario que o codigo nao entrega, no caminho destrutivo.
FK6="$T/raiz6"; mkdir -p "$FK6/etc/claude-code"
printf '{"_managed_by":"OUTRA-FERRAMENTA","permissions":{"deny":["Bash"]}}\n' > "$FK6/etc/claude-code/managed-settings.json"
rc=$(MANAGED_PREFIX="$FK6" bash "$AM" --revert >/dev/null 2>&1; echo $?)
chk "--revert REPROVA diante de politica de terceiro" "$rc" 1
chk "  e a politica de terceiro continua no disco" \
    "$(jq -r '._managed_by' "$FK6/etc/claude-code/managed-settings.json" 2>/dev/null)" "OUTRA-FERRAMENTA"
# CONTROLE: sem ele, um --revert que reprovasse SEMPRE passaria nos dois casos acima.
FK7="$T/raiz7"
MANAGED_PREFIX="$FK7" bash "$AM" >/dev/null 2>&1
rc=$(MANAGED_PREFIX="$FK7" bash "$AM" --revert >/dev/null 2>&1; echo $?)
chk "  e a politica DESTE instalador continua sendo removida" "$rc" 0

echo "== MG13. sob prefixo de ensaio, posse e gravabilidade sao NAO VERIFICADAS =="
# SETIMA INSTANCIA do padrao vacuo, achada por revisao independente. As colunas de dono e de
# gravabilidade so sao AVALIADAS quando o prefixo e a raiz real; sob ensaio o laco nem entra
# nesse ramo. Imprimir "0 gravaveis pelo ator" ali era pos-condicao trivialmente verdadeira -
# e essa e a garantia CENTRAL da fase 2, lida pela suite como aprovada.
FK8="$T/raiz8"
MANAGED_PREFIX="$FK8" bash "$AM" >/dev/null 2>&1
SAIDA="$(MANAGED_PREFIX="$FK8" bash "$AM" --verify 2>&1)"
chk "o modo de ensaio declara NAO VERIFICADO em vez de 0" \
    "$(printf '%s' "$SAIDA" | grep -qc 'NAO VERIFICADO' >/dev/null && echo sim || echo nao)" "sim"
chk "  e NAO afirma 'fora do espaco de escrita do ator'" \
    "$(printf '%s' "$SAIDA" | grep -q 'ESTADO: politica fora do espaco' && echo afirma || echo nao-afirma)" "nao-afirma"
chk "  os arquivos sob ensaio sao mesmo gravaveis (a garantia NAO vale ali)" \
    "$([ -w "$FK8/opt/tollens/hooks/verify-gate.sh" ] && echo gravavel || echo protegido)" "gravavel"

echo "== MG14. politica que declara hook AUSENTE nao pode ser ativada =="
# PORTAO FINAL, 2026-08-04. O portao de populacao era TAUTOLOGICO: comparava `n` (conformes)
# com `tipos_politica | wc -l`, e `n` vinha do laco que itera a MESMA fonte. So podia falhar
# com o conjunto vazio - que e o que MG11 cobre. Remover UMA linha do manifesto passava.
# Medido: --enforce EXIT=0, allowManagedHooksOnly=true, e a politica declarando
# `bash .../hooks/verify-gate.sh` para um arquivo INEXISTENTE; --verify sobre esse estado
# imprimia "0 divergentes" e "conteudo conforme".
# O gatilho e o procedimento NORMAL: manifest.sh gera por glob, entao renomear ou mover um
# hook e regenerar produz esse estado sem nenhuma edicao manual.
# A politica vem de OUTRA fonte (hooks-spec.sh) e o produto nunca a confrontava com o disco -
# a propriedade existia so no oraculo de MG4, exercitada sobre o manifesto real, onde era
# vacuamente verdadeira. Garantia no TESTE e nao no ARTEFATO.
SEMHOOK="$T/sem-um-hook.lock"
grep -v "evidence/hooks/verify-gate.sh" install/manifest.lock > "$SEMHOOK"
chk "o manifesto degradado perdeu exatamente 1 linha (senao o caso e outro)" \
    "$(( $(wc -l < install/manifest.lock) - $(wc -l < "$SEMHOOK") ))" "1"
chk "  e ele ainda produz componentes (nao e o caso vazio de MG11)" \
    "$([ "$(awk -F'\t' '!/^#/ && ($1=="hook"||$1=="adapter"||$1=="doctool")' "$SEMHOOK" | wc -l)" -gt 0 ] && echo sim || echo nao)" "sim"
FK9="$T/raiz9"; mkdir -p "$FK9"
rc=$(MANAGED_PREFIX="$FK9" MANAGED_MANIFEST="$SEMHOOK" bash "$AM" --enforce >/dev/null 2>&1; echo $?)
chk "  --enforce REPROVA: a politica declara hook que nao esta no disco" "$rc" 1
chk "  e allowManagedHooksOnly nao foi ativado" \
    "$(jq -r '.allowManagedHooksOnly' "$FK9/etc/claude-code/managed-settings.json" 2>/dev/null || echo ausente)" "ausente"

echo "== MG15. deploy REPROVADO deixa a arvore ativa BYTE A BYTE inalterada =="
# ACHADO DA AUDITORIA EXTERNA (2026-08-04). O laco de copia escrevia DIRETO na arvore ativa e os
# portoes rodavam depois; o proprio script admitia a consequencia no caminho de falha:
# "ATENCAO: arquivos sob $OPT PODEM ter sido escritos antes desta checagem". Um deploy reprovado
# podia deixar a arvore com alguns componentes na versao nova e outros na antiga - e a politica
# velha continuava apontando para ela. A propriedade que faltava:
#
#     DeployFail  =>  ActiveState_depois == ActiveState_antes
#
# Este caso a exercita como PROPRIEDADE, comparando o digest da arvore inteira antes e depois -
# e nao conferindo um arquivo escolhido a dedo, que passaria mesmo com metade da arvore trocada.
arvore_digest(){ # $1 = raiz; "" se nao existe
  [ -d "$1" ] || { echo "AUSENTE"; return; }
  ( cd "$1" && find . -type f -exec sha256sum {} + 2>/dev/null | LC_ALL=C sort -k2 | sha256sum | cut -d' ' -f1 )
}
FK15="$T/raiz15"; mkdir -p "$FK15"
rc=$(MANAGED_PREFIX="$FK15" bash "$AM" >/dev/null 2>&1; echo $?)
chk "deploy inicial instala (o caso precisa de uma arvore ativa para proteger)" "$rc" 0
ATIVA15="$FK15/opt/tollens"
ANTES15="$(arvore_digest "$ATIVA15")"
chk "  a arvore ativa existe e tem digest (senao nao ha o que preservar)" \
    "$([ "$ANTES15" != "AUSENTE" ] && [ -n "$ANTES15" ] && echo sim || echo nao)" "sim"

# SEGUNDO DEPLOY QUE REPROVA NO ULTIMO PORTAO. O manifesto e valido e POPULOSO - a reprovacao vem
# do portao de hook ausente (mesmo mecanismo de MG14), que roda DEPOIS de toda a copia. E o pior
# caso possivel para a propriedade: se a copia fosse direto na ativa, a essa altura ela ja teria
# sido reescrita inteira.
rc=$(MANAGED_PREFIX="$FK15" MANAGED_MANIFEST="$SEMHOOK" bash "$AM" >/dev/null 2>&1; echo $?)
chk "  o segundo deploy REPROVA no portao (precondicao do caso)" "$rc" 1
DEPOIS15="$(arvore_digest "$ATIVA15")"
chk "  e a arvore ativa esta BYTE A BYTE identica a antes da tentativa" "$DEPOIS15" "$ANTES15"

# ANTIVACUIDADE: se o segundo deploy nao tivesse NADA de diferente a escrever, os digests seriam
# iguais mesmo com o codigo antigo, e o caso mediria zero. O manifesto degradado tem uma linha a
# menos - logo, um deploy bem-sucedido dele PRODUZIRIA uma arvore diferente.
FK15B="$T/raiz15b"; mkdir -p "$FK15B"
MANAGED_PREFIX="$FK15B" MANAGED_MANIFEST="$SEMHOOK" bash "$AM" --dry-run >/dev/null 2>&1
chk "  e o manifesto degradado descreve MESMO uma arvore diferente (nao vacuo)" \
    "$([ "$(awk -F'\t' '!/^#/ && ($1=="hook"||$1=="adapter"||$1=="doctool")' "$SEMHOOK" | wc -l)" \
       -ne "$(awk -F'\t' '!/^#/ && ($1=="hook"||$1=="adapter"||$1=="doctool")' install/manifest.lock | wc -l)" ] \
       && echo sim || echo nao)" "sim"

echo "== MG16. deploy reprovado nao deixa area de staging orfa =="
# Staging orfa sob /opt seria lixo root-owned acumulando a cada tentativa falha - e, pior, um
# diretorio com os hooks completos fora de qualquer inspecao do --verify.
chk "nenhum diretorio *.stage.* remanescente" \
    "$(find "$FK15/opt" -maxdepth 1 -name 'tollens.stage.*' 2>/dev/null | wc -l | tr -d ' ')" "0"
chk "  nem *.anterior.* (a troca limpa o que afastou)" \
    "$(find "$FK15/opt" -maxdepth 1 -name 'tollens.anterior.*' 2>/dev/null | wc -l | tr -d ' ')" "0"

echo "== MG17. falha APOS a publicacao devolve o estado ativo INTEIRO =="
# SEGUNDO ACHADO SOBRE ESTE MESMO CODIGO (revisao independente do PR #5). MG15 so provoca falha
# ANTES da publicacao, entao provava a propriedade estreita
#     GateFail_{pre-publicacao} => OptTree inalterada
# enquanto o commit, o PR e o README publicavam a propriedade larga
#     DeployFail => ActiveState inalterado.
# O dominio exercitado nao continha o contraexemplo: apos publicar a arvore, o script ainda
# gerava e instalava o `managed-settings.json` com `mktemp`, `jq`, `cp`, `chmod` e `chown`, todos
# APOS o ponto sem volta e nenhum com retorno verificado sob `set -uo pipefail` sem `set -e`.
#
# DUAS MUDANCAS DE ORACULO, e sao elas que dao poder de decisao a estes casos:
#   1. ESTADO ATIVO = (arvore, politica). MG15 olhava so a arvore; a metade que faltava era
#      justamente a que podia divergir.
#   2. O segundo deploy precisa produzir um estado DIFERENTE. Com o mesmo manifesto e o mesmo
#      modo, os digests coincidiriam mesmo com o rollback quebrado - caso vacuo. Aqui o segundo
#      deploy usa `--enforce` (muda allowManagedHooksOnly) sobre um manifesto com um adaptador a
#      menos (muda a arvore). As duas metades do estado mudariam se o rollback falhasse.
estado_ativo(){ # $1 = prefixo; ecoa "digest_arvore|digest_politica"
  local a p
  if [ -d "$1/opt/tollens" ]; then
    a="$(cd "$1/opt/tollens" && find . -type f -exec sha256sum {} + 2>/dev/null \
         | LC_ALL=C sort -k2 | sha256sum | cut -d' ' -f1)"
  else a="ARVORE_AUSENTE"; fi
  if [ -f "$1/etc/claude-code/managed-settings.json" ]; then
    p="$(sha256sum "$1/etc/claude-code/managed-settings.json" | cut -d' ' -f1)"
  else p="POLITICA_AUSENTE"; fi
  printf '%s|%s\n' "$a" "$p"
}
MENOS="$T/menos-um-adaptador.lock"
# ADAPTADOR, e nao hook: remover hook reprova no portao de populacao ANTES da publicacao (MG14),
# e o caso nunca chegaria a fase que precisa ser exercitada.
# `!seen++` e nao `seen++`: pos-incremento faz a primeira ocorrencia valer 0 (falso), entao
# `&& seen++` casaria a partir da SEGUNDA e removeria todas menos a primeira - o inverso do
# pretendido. Medido: 10 linhas a menos em vez de 1, e a assercao de precondicao pegou.
awk -F'\t' '!($1=="adapter" && !seen++)' install/manifest.lock > "$MENOS"
chk "o manifesto alternativo perdeu exatamente 1 adaptador" \
    "$(( $(wc -l < install/manifest.lock) - $(wc -l < "$MENOS") ))" "1"

FK17="$T/raiz17"; mkdir -p "$FK17"
rc=$(MANAGED_PREFIX="$FK17" bash "$AM" >/dev/null 2>&1; echo $?)
chk "  deploy inicial instala arvore e politica" "$rc" 0
ANTES17="$(estado_ativo "$FK17")"
chk "  o estado ativo tem as DUAS metades (senao o oraculo e cego)" \
    "$(case "$ANTES17" in *AUSENTE*) echo nao;; *) echo sim;; esac)" "sim"

# ANTIVACUIDADE: sem o failpoint, este mesmo comando SUCEDE e muda o estado. Se nao mudasse,
# os casos abaixo passariam mesmo com o rollback quebrado.
FK17V="$T/raiz17v"; mkdir -p "$FK17V"
MANAGED_PREFIX="$FK17V" bash "$AM" >/dev/null 2>&1
MANAGED_PREFIX="$FK17V" MANAGED_MANIFEST="$MENOS" bash "$AM" --enforce >/dev/null 2>&1
chk "  e o segundo deploy MUDARIA o estado se completasse (nao vacuo)" \
    "$([ "$(estado_ativo "$FK17V")" != "$ANTES17" ] && echo sim || echo nao)" "sim"

for FP in publicar-opt instalar-politica; do
  rc=$(MANAGED_PREFIX="$FK17" MANAGED_MANIFEST="$MENOS" MANAGED_FAILPOINT="$FP" \
       bash "$AM" --enforce >/dev/null 2>&1; echo $?)
  chk "  failpoint '$FP': o deploy REPROVA" "$rc" 1
  chk "    e o estado ativo INTEIRO volta ao anterior" "$(estado_ativo "$FK17")" "$ANTES17"
done

echo "== MG18. sucesso so e reportado quando arvore E politica convergem =="
# O contrapositivo de MG17: sem este caso, um instalador que reprovasse SEMPRE passaria em MG17.
rc=$(MANAGED_PREFIX="$FK17" MANAGED_MANIFEST="$MENOS" bash "$AM" --enforce >/dev/null 2>&1; echo $?)
chk "sem failpoint, o mesmo deploy SUCEDE" "$rc" 0
DEPOIS18="$(estado_ativo "$FK17")"
chk "  e o estado ativo mudou (as duas metades foram commitadas)" \
    "$([ "$DEPOIS18" != "$ANTES17" ] && echo sim || echo nao)" "sim"
chk "  a politica no disco reflete o modo pedido (--enforce)" \
    "$(jq -r '.allowManagedHooksOnly' "$FK17/etc/claude-code/managed-settings.json" 2>/dev/null)" "true"
chk "  e nao restou material de rollback" \
    "$(find "$FK17/etc/claude-code" "$FK17/opt" -maxdepth 1 \
       \( -name '.managed-settings.json.*' -o -name 'tollens.anterior.*' \
          -o -name 'tollens.stage.*' \) 2>/dev/null | wc -l | tr -d ' ')" "0"

echo
echo "================ PASS=$P  FAIL=$F ================"
EXPECTED=66
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
[ "$F" -eq 0 ] && echo "raiz de confianca verde ($P/$EXPECTED)" || echo "raiz de confianca VERMELHA"
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
