#!/usr/bin/env bash
# SUITE DO NUCLEO QUE JULGA O DELTA (evidence/lint-delta.py).
#
# O valor desta suite esta nos casos que separam "o portao funciona" de "o portao aprova tudo".
# Um portao de delta tem um modo de falha proprio e silencioso: aprovar por nao ter olhado. Cada
# caso positivo aqui tem o negativo correspondente.
set -uo pipefail
. "$(dirname "$0")/../lib/lock.sh"
cd "$(dirname "$0")/../.." || exit 1
LD="evidence/lint-delta.py"
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }
rodar(){ python3 "$LD" --diagnostics "$1" --hunks "$2" --baseline "$3" --breakage-codes "$4" 2>/dev/null; }
rc_de(){ python3 "$LD" --diagnostics "$1" --hunks "$2" --baseline "$3" --breakage-codes "$4" >/dev/null 2>&1; echo $?; }

QUEBRA="F821,F811,F822,E999"
T_LD="$(mktemp -d "${TMPDIR:-/tmp}/ld.XXXXXX")"; trap 'rm -rf "$T_LD"' EXIT
HIG='[{"path":"a.py","line":8,"code":"F401","message":"`uuid` imported but unused"}]'
QBR='[{"path":"b.py","line":3,"code":"F821","message":"Undefined name `foo`"}]'

echo "== LD1. higiene FORA das linhas tocadas nao bloqueia =="
# E o caso dos 80 de 86 medidos em /var/www/amaral-intern-hub.
chk "higiene sem hunk naquele arquivo: exit 0" "$(rc_de "$HIG" '{}' '' "$QUEBRA")" 0
chk "  e ela e contada como IGNORADA, nao sumida" \
    "$(rodar "$HIG" '{}' '' "$QUEBRA" | python3 -c 'import json,sys;print(json.load(sys.stdin)["ignorados"])')" 1

echo "== LD2. higiene DENTRO das linhas tocadas bloqueia =="
# CONTROLE NEGATIVO de LD1: sem ele, "nao bloqueou" nao distingue "e alheia" de "nao olhei".
chk "higiene na linha tocada: exit 1" "$(rc_de "$HIG" '{"a.py":[[5,10]]}' '' "$QUEBRA")" 1
chk "  e a faixa e fechada nos dois lados (linha 8 em [8,8])" \
    "$(rc_de "$HIG" '{"a.py":[[8,8]]}' '' "$QUEBRA")" 1
chk "  hunk que NAO cobre a linha nao bloqueia (borda inferior)" \
    "$(rc_de "$HIG" '{"a.py":[[9,20]]}' '' "$QUEBRA")" 0

echo "== LD3. quebra bloqueia em arquivo NAO tocado =="
# A razao de `per_file` sozinho estar errado: remover uma funcao quebra quem a chama, e esse
# arquivo nao esta no diff.
chk "quebra sem hunk nenhum: exit 1" "$(rc_de "$QBR" '{}' '' "$QUEBRA")" 1

echo "== LD4. quebra no BASELINE e tolerada, nao ignorada =="
FP="$(python3 "$LD" --diagnostics "$QBR" --hunks '{}' --breakage-codes "$QUEBRA" --emit-baseline 2>/dev/null)"
chk "o baseline emitido tem 1 digital" "$(printf '%s' "$FP" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))')" 1
chk "quebra preexistente nao bloqueia" "$(rc_de "$QBR" '{}' "$FP" "$QUEBRA")" 0
chk "  e ela e REPORTADA em stderr (baseline nao cala)" \
    "$(python3 "$LD" --diagnostics "$QBR" --hunks '{}' --baseline "$FP" --breakage-codes "$QUEBRA" 2>&1 >/dev/null | grep -c 'QUEBRA PREEXISTENTE TOLERADA')" 1
chk "  e contabilizada como tolerada, nao como ignorada" \
    "$(rodar "$QBR" '{}' "$FP" "$QUEBRA" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(str(d["tolerados"])+"/"+str(d["ignorados"]))')" "1/0"

echo "== LD5. quebra NOVA bloqueia mesmo com baseline =="
# Sem este caso, um baseline que casasse tudo passaria por "catraca funcionando".
NOVA='[{"path":"c.py","line":1,"code":"F821","message":"Undefined name `outro`"}]'
chk "quebra fora do baseline: exit 1" "$(rc_de "$NOVA" '{}' "$FP" "$QUEBRA")" 1

echo "== LD6. A DIGITAL SOBREVIVE A DESLOCAMENTO DE LINHA =="
# O ponto sutil do desenho. Casar por (arquivo, linha) faria QUALQUER edicao acima gerar
# falso-novo em massa. Aqui o MESMO defeito aparece na linha 3 e depois na 47.
DESLOCADA='[{"path":"b.py","line":47,"code":"F821","message":"Undefined name `foo`"}]'
chk "mesmo defeito 44 linhas abaixo: continua tolerado" "$(rc_de "$DESLOCADA" '{}' "$FP" "$QUEBRA")" 0
chk "  CONTROLE: defeito de OUTRO simbolo no mesmo arquivo NAO e tolerado" \
    "$(rc_de '[{"path":"b.py","line":3,"code":"F821","message":"Undefined name `bar`"}]' '{}' "$FP" "$QUEBRA")" 1
chk "  CONTROLE: mesmo simbolo em OUTRO arquivo NAO e tolerado" \
    "$(rc_de '[{"path":"z.py","line":3,"code":"F821","message":"Undefined name `foo`"}]' '{}' "$FP" "$QUEBRA")" 1

echo "== LD7. mensagem com contador nao gera falso-novo =="
# `redefinition of unused 'x' from line 3` vira `line #`: senao a digital muda quando o alvo
# se move, que e o mesmo falso-novo pela porta dos fundos.
M1='[{"path":"d.py","line":9,"code":"F811","message":"Redefinition of unused `x` from line 3"}]'
M2='[{"path":"d.py","line":9,"code":"F811","message":"Redefinition of unused `x` from line 51"}]'
B2="$(python3 "$LD" --diagnostics "$M1" --hunks '{}' --breakage-codes "$QUEBRA" --emit-baseline 2>/dev/null)"
chk "numero na mensagem nao muda a digital" "$(rc_de "$M2" '{}' "$B2" "$QUEBRA")" 0

echo "== LD8. falhas de entrada sao NAO VERIFICADO, nunca aprovacao =="
# Um portao que aprova por nao entender a entrada e pior que a ausencia dele.
chk "diagnostics ilegivel -> exit 2" "$(rc_de 'nao e json' '{}' '' "$QUEBRA")" 2
chk "hunks ilegivel -> exit 2"       "$(rc_de "$HIG" 'nao e json' '' "$QUEBRA")" 2
chk "baseline ilegivel -> exit 2"    "$(rc_de "$HIG" '{}' 'nao e json' "$QUEBRA")" 2
chk "diagnostico sem campo -> exit 2" "$(rc_de '[{"path":"a.py","line":1}]' '{}' '' "$QUEBRA")" 2
chk "breakage-codes VAZIO -> exit 2 (senao a arvore deixa de ser olhada)" \
    "$(rc_de "$QBR" '{}' '' ",, ")" 2

echo "== LD9. ANTIVACUIDADE: entrada vazia nao e aprovacao com significado =="
chk "zero diagnosticos: exit 0" "$(rc_de '[]' '{}' '' "$QUEBRA")" 0
chk "  e o relatorio declara zero em TODAS as classes" \
    "$(rodar '[]' '{}' '' "$QUEBRA" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["bloqueiam"]+d["tolerados"]+d["ignorados"])')" 0

echo "== LD10. saida NATIVA do analisador via mapa declarativo =="
# O mapa vem do ADAPTADOR. Embutir os nomes de campo aqui faria cada ferramenta nova exigir
# edicao do nucleo - e e assim que um executor generico vira um executor de ruff.
RAW='[{"filename":"/abs/repo/a.py","location":{"row":8},"code":"F401","message":"`uuid` imported but unused"}]'
MAPA='{"path":"filename","line":"location.row","code":"code","message":"message"}'
nat(){ python3 "$LD" --raw "$1" --map "$2" --strip-prefix "${3:-}" --hunks "${4:-{\}}" --baseline "${5:-}" --breakage-codes "$QUEBRA" "${@:6}"; }
chk "traduz saida nativa e o prefixo absoluto some" \
    "$(nat "$RAW" "$MAPA" '/abs/repo/' '{"a.py":[[8,8]]}' 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["detalhe"][0]["path"])')" "a.py"
chk "  e o veredito usa o caminho JA traduzido (bloqueia no hunk)" \
    "$(python3 "$LD" --raw "$RAW" --map "$MAPA" --strip-prefix '/abs/repo/' --hunks '{"a.py":[[8,8]]}' --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 1
chk "  CONTROLE: sem --strip-prefix o caminho nao casa o hunk e NAO bloqueia" \
    "$(python3 "$LD" --raw "$RAW" --map "$MAPA" --hunks '{"a.py":[[8,8]]}' --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 0
chk "--raw sem --map e NAO VERIFICADO, nao aprovacao" \
    "$(python3 "$LD" --raw "$RAW" --hunks '{}' --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 2
chk "chave do mapa que nao existe na saida -> exit 2" \
    "$(python3 "$LD" --raw "$RAW" --map '{"path":"nao_existe","line":"location.row","code":"code","message":"message"}' --hunks '{}' --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 2

echo "== LD11. diagnostico em checkout ANINHADO nunca foi objeto do turno =="
# Medido: 87 de 173 em /var/www/amaral-intern-hub vinham de 4 worktrees dentro do repo. Nao e
# escopo semantico nem baseline - aquele codigo nao esta no HEAD do turno.
ANIN='[{"path":".worktrees/outra/x.py","line":3,"code":"F821","message":"Undefined name `z`"}]'
chk "quebra dentro de checkout aninhado NAO bloqueia" \
    "$(python3 "$LD" --diagnostics "$ANIN" --hunks '{}' --nested-roots '[".worktrees/outra"]' --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 0
chk "  e ela e contada como ALHEIA, nao como ignorada" \
    "$(python3 "$LD" --diagnostics "$ANIN" --hunks '{}' --nested-roots '[".worktrees/outra"]' --breakage-codes "$QUEBRA" 2>/dev/null | python3 -c 'import json,sys;d=json.load(sys.stdin);print(str(d["alheios"])+"/"+str(d["ignorados"]))')" "1/0"
chk "  CONTROLE: a MESMA quebra fora do checkout aninhado bloqueia" \
    "$(python3 "$LD" --diagnostics "$ANIN" --hunks '{}' --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 1
chk "  CONTROLE: prefixo parcial nao casa ('.worktrees/outra2' != '.worktrees/outra')" \
    "$(python3 "$LD" --diagnostics '[{"path":".worktrees/outra2/x.py","line":3,"code":"F821","message":"Undefined name `z`"}]' --hunks '{}' --nested-roots '[".worktrees/outra"]' --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 1
chk "o baseline NAO grava digital de checkout aninhado" \
    "$(python3 "$LD" --diagnostics "$ANIN" --hunks '{}' --nested-roots '[".worktrees/outra"]' --breakage-codes "$QUEBRA" --emit-baseline 2>/dev/null | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))')" 0

echo "== LD12. a SEMEADURA do baseline nao depende de hunks =="
# Regressao real: `--hunks` era obrigatorio e a semeadura nao os passa. O executor engolia o erro
# em `2>/dev/null`, seguia sem baseline, e reprovava por quebra preexistente para sempre. A
# suite unitaria nao via porque sempre passava `--hunks`; quem pegou foi o teste ponta a ponta.
chk "emit-baseline SEM --hunks: exit 0" \
    "$(python3 "$LD" --diagnostics "$QBR" --breakage-codes "$QUEBRA" --emit-baseline >/dev/null 2>&1; echo $?)" 0
chk "  e emite a digital mesmo assim" \
    "$(python3 "$LD" --diagnostics "$QBR" --breakage-codes "$QUEBRA" --emit-baseline 2>/dev/null | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))')" 1
chk "  julgar SEM --hunks trata como zero linhas tocadas (higiene nao bloqueia)" \
    "$(python3 "$LD" --diagnostics "$HIG" --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 0

echo "== LD13. --raw-file: entrada por ARQUIVO, sem limite de argv =="
# O Linux limita UM argv a MAX_ARG_STRLEN = 131.072 B, e a saida do analisador num repositorio
# real ja passa disso (medido: 147.920 B). Passar por argv fazia o hook morrer com `Argument list
# too long` e, como a semeadura exige RC==1, o repositorio ficava bloqueado PARA SEMPRE.
RF="$T_LD/raw.json"; mkdir -p "$T_LD" 2>/dev/null
MAPA_LD='{"path":"filename","line":"location.row","code":"code","message":"message"}'
printf '[{"filename":"/abs/x/a.py","location":{"row":8},"code":"F401","message":"`os` imported but unused"}]' > "$RF"
chk "LD13 le a saida nativa de um ARQUIVO" \
    "$(python3 "$LD" --raw-file "$RF" --map "$MAPA_LD" --strip-prefix '/abs/x/' --hunks '{"a.py":[[8,8]]}' --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 1
chk "  e o mesmo conteudo FORA do hunk nao bloqueia" \
    "$(python3 "$LD" --raw-file "$RF" --map "$MAPA_LD" --strip-prefix '/abs/x/' --hunks '{}' --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 0
# ARQUIVO VAZIO NAO E ARVORE LIMPA. Cair no `--diagnostics` default (`[]`) transformaria leitura
# que nao produziu nada em "nenhum diagnostico", que e aprovacao - a mesma classe que esta onda
# corrigiu no executor, aqui dentro do nucleo.
: > "$T_LD/vazio.json"
chk "  arquivo VAZIO e NAO VERIFICADO, nao aprovacao" \
    "$(python3 "$LD" --raw-file "$T_LD/vazio.json" --map "$MAPA_LD" --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 2
printf '[]' > "$T_LD/lista-vazia.json"
chk "  CONTROLE: lista vazia legitima do analisador passa" \
    "$(python3 "$LD" --raw-file "$T_LD/lista-vazia.json" --map "$MAPA_LD" --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 0
chk "  arquivo INEXISTENTE e NAO VERIFICADO" \
    "$(python3 "$LD" --raw-file "$T_LD/nao-existe.json" --map "$MAPA_LD" --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 2

echo "== LD14. codigo SEM NOME e quebra, pelo caminho que o hook realmente usa (G65/R6) =="
# G65 nasceu de um falso negativo MEDIDO pelo hook instalado: ruff 0.16.2 removeu `E999` e emite
# `invalid-syntax`, que nao estava em `breakage_codes`. O erro de sintaxe virava higiene, o teste
# de hunk o descartava (parse quebrado reporta na linha 202 um parentese aberto na linha 1) e o
# portao saia 0. A correcao no adaptador fecha o REPRO; esta fecha a CLASSE.
#
# R6 DO REFUTADOR: a primeira versao destes casos usava `--diagnostics`, que NENHUM adaptador e
# NENHUM caminho do hook exercita - o hook chama o nucleo so por `--raw-file` + `--map`. Nessa
# via `_cava` conflacionava chave AUSENTE com valor NULO e `normaliza_diagnosticos` levantava
# antes de `eh_quebra` ser alcancado: seis casos verdes sobre superficie morta. Agora e o caminho
# real, e os controles separam nulo (dado) de ausente (ilegivel).
LD_MAPA='{"path":"filename","line":"location.row","code":"code","message":"message"}'
printf '[{"filename":"/x/z.py","location":{"row":202},"code":null,"message":"unexpected EOF while parsing"}]' > "$T_LD/nulo.json"
rf(){ python3 "$LD" --raw-file "$1" --map "$LD_MAPA" --strip-prefix '/x/' --hunks "$2" --breakage-codes "$QUEBRA" "${@:3}"; }
chk "code null FORA de qualquer hunk bloqueia" \
    "$(rf "$T_LD/nulo.json" '{}' >/dev/null 2>&1; echo $?)" 1
chk "  e e classificado como QUEBRA, nao higiene" \
    "$(rf "$T_LD/nulo.json" '{}' 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["detalhe"][0]["classe"])')" quebra
# CONTROLE NEGATIVO: sem ele, "bloqueou" nao distingue a regra nova de "bloqueia tudo".
printf '[{"filename":"/x/z.py","location":{"row":202},"code":"F401","message":"`os` imported but unused"}]' > "$T_LD/hig.json"
chk "  CONTROLE: codigo NOMEADO de higiene fora do hunk segue passando" \
    "$(rf "$T_LD/hig.json" '{}' >/dev/null 2>&1; echo $?)" 0
# CHAVE AUSENTE nao e a mesma coisa que VALOR NULO: uma e leitura que falhou, a outra e dado.
printf '[{"filename":"/x/z.py","location":{"row":202},"message":"sem code"}]' > "$T_LD/ausente.json"
chk "  chave 'code' AUSENTE continua NAO VERIFICADO (nao vira quebra)" \
    "$(rf "$T_LD/ausente.json" '{}' >/dev/null 2>&1; echo $?)" 2
printf '[{"filename":"/x/z.py","location":{"row":202},"code":"F821","message":null}]' > "$T_LD/msgnula.json"
chk "  e nulo nos OUTROS campos segue ilegivel (so 'code' tem leitura util)" \
    "$(rf "$T_LD/msgnula.json" '{}' >/dev/null 2>&1; echo $?)" 2
# O baseline PRECISA usar o mesmo predicado: se `--emit-baseline` ignorasse code sem nome, a
# quebra preexistente nunca entraria na catraca e bloquearia para sempre, sem semeadura possivel.
BL_NULO="$(python3 "$LD" --raw-file "$T_LD/nulo.json" --map "$LD_MAPA" --strip-prefix '/x/' --breakage-codes "$QUEBRA" --emit-baseline)"
chk "  --emit-baseline inclui a digital do codigo sem nome" \
    "$(printf '%s' "$BL_NULO" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))')" 1
chk "  e semeada, ela e TOLERADA (nao bloqueia) na execucao seguinte" \
    "$(python3 "$LD" --raw-file "$T_LD/nulo.json" --map "$LD_MAPA" --strip-prefix '/x/' --hunks '{}' --baseline "$BL_NULO" --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 0

echo "== LD15. a exclusao por checkout aninhado e REPORTADA, por raiz (G68) =="
# R1 DO REFUTADOR: `git init <subdir>` tirava tudo debaixo dele do julgamento e o portao saia 0
# com stdout VAZIO. Exigir historia na raiz (feito no executor) mata a versao de um comando; o
# que impede a exclusao de voltar a ser bypass e ela ser DITA. Duas raizes de proposito: com uma
# so, o laco que agrupa por raiz nunca precisa avancar, e o caso nao mediria o agrupamento.
printf '[{"filename":"/x/wt-a/z.py","location":{"row":9},"code":"F821","message":"Undefined name `a`"},{"filename":"/x/wt-b/y.py","location":{"row":3},"code":"F401","message":"`os` imported but unused"},{"filename":"/x/wt-b/w.py","location":{"row":4},"code":"F401","message":"`sys` imported but unused"}]' > "$T_LD/alheios.json"
AL="$(python3 "$LD" --raw-file "$T_LD/alheios.json" --map "$LD_MAPA" --strip-prefix '/x/' \
       --nested-roots '["wt-a","wt-b"]' --breakage-codes "$QUEBRA" 2>"$T_LD/al.err")"
chk "tres diagnosticos em duas raizes: nenhum bloqueia" \
    "$(printf '%s' "$AL" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["bloqueiam"],d["alheios"])')" "0 3"
chk "  e a exclusao vai para stderr" \
    "$(grep -c 'EXCLUIDO POR CHECKOUT ANINHADO: 3 diagnostico(s)' "$T_LD/al.err")" 1
# O AGRUPAMENTO importa: 'quantos por raiz' e o que deixa o operador ver que UMA raiz concentra
# tudo. Sem isto, o caso mediria so que alguma linha foi impressa.
chk "  agrupada por raiz, a maior primeiro" \
    "$(grep -E '^  wt-[ab]/' "$T_LD/al.err" | head -1 | awk '{print $1, $2}')" "wt-b/ 2"
chk "  e a segunda raiz tambem aparece" \
    "$(grep -c '^  wt-a/  1 diagnostico' "$T_LD/al.err")" 1
# CONTROLE NEGATIVO: sem raiz declarada, os MESMOS diagnosticos sao julgados e o F821 bloqueia.
chk "  CONTROLE: sem raiz aninhada, os mesmos diagnosticos bloqueiam" \
    "$(python3 "$LD" --raw-file "$T_LD/alheios.json" --map "$LD_MAPA" --strip-prefix '/x/' --hunks '{}' --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 1
chk "  e ai NADA e reportado como excluido" \
    "$(python3 "$LD" --raw-file "$T_LD/alheios.json" --map "$LD_MAPA" --strip-prefix '/x/' --hunks '{}' --breakage-codes "$QUEBRA" 2>&1 >/dev/null | grep -c 'EXCLUIDO POR CHECKOUT')" 0

echo "== LD16. --hunks-file: arquivo vazio nao e mapa vazio (G74) =="
# SEGUNDA INSTANCIA DE F3, exposta pela correcao de G74: `--hunks` era argv e estourou
# MAX_ARG_STRLEN quando o mapa do amaral passou de {} para 2685 chaves (`Argument list too long`,
# exit 126). Nunca tinha estourado porque o parser morria antes - um defeito escondia o outro.
# A guarda que importa e a mesma de LD13: leitura que nao produziu nada NAO pode virar o default,
# porque `{}` faz TODA a higiene ser ignorada, que e o buraco que G74 fechou no executor.
printf '{"a.py": [[8,8]]}' > "$T_LD/hunks.json"
: > "$T_LD/hunks-vazio.json"
chk "--hunks-file com a linha tocada bloqueia a higiene" \
    "$(python3 "$LD" --raw-file "$T_LD/hig.json" --map "$LD_MAPA" --strip-prefix '/x/' --hunks-file "$T_LD/hunks.json" --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 0
printf '[{"filename":"/x/a.py","location":{"row":8},"code":"F401","message":"`os` imported but unused"}]' > "$T_LD/hig8.json"
chk "  o MESMO diagnostico dentro do hunk do arquivo bloqueia" \
    "$(python3 "$LD" --raw-file "$T_LD/hig8.json" --map "$LD_MAPA" --strip-prefix '/x/' --hunks-file "$T_LD/hunks.json" --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 1
chk "  arquivo de hunks VAZIO e NAO VERIFICADO, nao mapa vazio" \
    "$(python3 "$LD" --raw-file "$T_LD/hig8.json" --map "$LD_MAPA" --strip-prefix '/x/' --hunks-file "$T_LD/hunks-vazio.json" --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 2
chk "  arquivo de hunks INEXISTENTE e NAO VERIFICADO" \
    "$(python3 "$LD" --raw-file "$T_LD/hig8.json" --map "$LD_MAPA" --strip-prefix '/x/' --hunks-file "$T_LD/nao-existe.json" --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 2
# CONTROLE: `--hunks-file` VENCE `--hunks`, senao o executor poderia passar os dois e o mapa
# antigo (argv, truncado) decidiria em silencio.
chk "  --hunks-file vence --hunks quando os dois vem" \
    "$(python3 "$LD" --raw-file "$T_LD/hig8.json" --map "$LD_MAPA" --strip-prefix '/x/' --hunks '{}' --hunks-file "$T_LD/hunks.json" --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 1

echo "== LD17. caminho de arquivo VAZIO e NAO VERIFICADO, nao default permissivo (G78) =="
# G78 produzia exatamente isto: `mktemp` falho deixava a variavel vazia, o executor passava
# `--hunks-file ""`, o nucleo caia no default `--hunks {}` - o mapa vazio, o valor mais permissivo -
# e o turno era APROVADO. Um subagente "alinhou" os dois predicados na direcao ERRADA (vazio =
# nao forneceu = aprova), o que tornaria essa porta mais facil de alcancar; a simetria certa e
# pela SEVERIDADE. `default=None` separa "nao passou a flag" de "passou caminho vazio".
chk "--hunks-file com caminho vazio: NAO VERIFICADO" \
    "$(python3 "$LD" --raw-file "$T_LD/hig.json" --map "$LD_MAPA" --strip-prefix '/x/' --hunks-file '' --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 2
chk "  e so com espaco tambem" \
    "$(python3 "$LD" --raw-file "$T_LD/hig.json" --map "$LD_MAPA" --strip-prefix '/x/' --hunks-file ' ' --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 2
chk "--raw-file com caminho vazio: NAO VERIFICADO" \
    "$(python3 "$LD" --raw-file '' --map "$LD_MAPA" --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 2
chk "  e so com espaco tambem" \
    "$(python3 "$LD" --raw-file ' ' --map "$LD_MAPA" --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 2
# CONTROLE NEGATIVO: NAO passar a flag continua sendo legitimo, senao o caso mediria "reprova
# sempre" em vez de "reprova caminho vazio".
chk "  CONTROLE: sem a flag, o programa segue funcionando" \
    "$(python3 "$LD" --diagnostics '[]' --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 0
chk "  CONTROLE: com arquivo de verdade, julga normalmente" \
    "$(python3 "$LD" --raw-file "$T_LD/hig8.json" --map "$LD_MAPA" --strip-prefix '/x/' --hunks-file "$T_LD/hunks.json" --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 1

EXPECTED=64
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
echo
echo "================ PASS=$P  FAIL=$F ================"
[ "$F" -eq 0 ] && echo "lint-delta verde ($P/$EXPECTED)" || echo "lint-delta VERMELHO ($F falhas)"
exit "$F"
