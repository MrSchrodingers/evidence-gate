#!/usr/bin/env bash
# PONTA A PONTA DO RAMO `scope: delta`, atraves do HOOK - nao do nucleo.
#
# POR QUE ESTA SUITE EXISTE. O `refutador` fez a pergunta de contramortem - "se isto estivesse
# errado do jeito mais plausivel, o que pegaria?" - e a resposta era NADA: o nucleo tinha 35 casos
# e cobertura de 99,2%, mas o EXECUTOR nao tinha nenhum. Quatro caminhos em que o portao APROVAVA
# EM SILENCIO sobreviveram a seis suites verdes e a CI completa, porque todos moravam no shell
# entre o analisador e o nucleo.
#
# Cada caso aqui e um desses quatro, mais os controles que os separam de "portao desligado".
set -uo pipefail
. "$(dirname "$0")/../lib/lock.sh"
cd "$(dirname "$0")/../.." || exit 1
GATE="$PWD/evidence/hooks/verify-gate.sh"
export CLAUDE_ADAPTERS_DIR="$PWD/execution/adapters/code"
command -v ruff >/dev/null 2>&1 || { echo "NAO VERIFICADO: ruff ausente do PATH." >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/d2e.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
# LEDGER ISOLADO. `verify-gate.sh` grava em `${EVIDENCE_LEDGER_DIR:-$HOME/.claude/evidence}`, e
# nenhuma suite exportava a variavel: cada execucao desta suite injetava paradas SINTETICAS no
# ledger operacional do usuario, no mesmo diretorio que serve de evidencia sobre uso real.
# Medido em 2026-09-02: 1637 arquivos de ledger criados desde 2026-09-01, quase todos de teste, e
# a taxa de aprovacao daqueles dois dias ficou inutilizavel como medida de trabalho real.
# O ledger tambem e CACHE (so `pass` do mesmo snapshot curto-circuita), entao contaminar nos dois
# sentidos: teste podia herdar `pass` de outro teste com a mesma arvore.
. "$(dirname "$0")/../lib/ambiente.sh"
ambiente_de_suite "$TMP"
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

repo(){  # $1=nome; cria repo com upstream real, para que DIFFBASE exista
  R="$TMP/$1"; rm -rf "$R"; mkdir -p "$R/rem" "$R/w"
  ( cd "$R/rem" && git init -q --bare . ) >/dev/null 2>&1
  cd "$R/w" || exit 1
  git init -q .; git config user.email t@t; git config user.name t
  echo "x = 1" > a.py; git add -A; git commit -qm base >/dev/null
  git remote add origin "$R/rem" >/dev/null 2>&1
  git push -q -u origin HEAD:refs/heads/main >/dev/null 2>&1
  git branch --set-upstream-to=origin/main >/dev/null 2>&1
  export TOLLENS_BASELINE_DIR="$R/bl"; rm -rf "$R/bl"
}
gate(){ printf '{}' | timeout 120 bash "$GATE" >"$TMP/o" 2>"$TMP/e"; echo $?; }

echo "== DE1. turno que COMMITA a propria quebra NAO e anistiado =="
# A1 do refutador. Semear de HEAD fechava so a variante arvore-suja: com o turno commitado, HEAD
# E o estado do turno e a catraca gravava a digital do defeito recem-criado.
repo d1
printf 'def f():\n    return jamais_definido\n' > q.py; git add -A; git commit -qm "turno commitou" >/dev/null
chk "1a parada barra" "$(gate)" 2
chk "  2a parada CONTINUA barrando (nao virou catraca)" "$(gate)" 2
chk "  e o baseline nao contem a quebra do turno" \
    "$(cat "$TMP/d1/bl"/*.json 2>/dev/null | head -1)" "[]"

echo "== DE2. divida PREEXISTENTE e tolerada, e a NOVA bloqueia =="
# O caso que a onda existe para resolver, e o discriminante que o separa de portao desligado.
repo d2
printf 'import os\n__all__ = ["nao_existe"]\n' > velho.py; git add -A; git commit -qm divida >/dev/null
git push -q origin HEAD:refs/heads/main >/dev/null 2>&1
printf 'def f():\n    return 1\n' > novo.py; git add -A
chk "1a parada cria a catraca e barra uma vez" "$(gate)" 2
# ANTITAUTOLOGIA. As tres asserces de codigo de saida acima e abaixo eram satisfeitas por um
# portao QUEBRADO: a limpeza de `$RAWF` acontecia ANTES do rejulgamento pos-semeadura, o nucleo
# respondia `NAO VERIFICADO: entrada ilegivel ([Errno 2] ...)` e o RC virava 2 - o mesmo 2 que o
# teste esperava. Medir so o codigo de saida nao distingue "barrou por ter julgado" de "barrou por
# nao ter conseguido ler". A causa precisa entrar na medicao.
chk "  e ela JULGOU: a causa nao e entrada ilegivel" \
    "$(grep -c 'entrada ilegivel' "$TMP/o" "$TMP/e" 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')" 0
chk "  2a parada com a divida preexistente PASSA" "$(gate)" 0
chk "  e a quebra tolerada e REPORTADA, nao calada" \
    "$(grep -c 'QUEBRA PREEXISTENTE TOLERADA' "$TMP/e" 2>/dev/null | head -1)" 1
printf 'def g():\n    return jamais\n' > q2.py; git add -A
chk "  quebra NOVA volta a barrar" "$(gate)" 2

echo "== DE3. analisador que FALHA e LACUNA, nunca aprovacao =="
# A2 do refutador, regressao do G16 dentro do ramo novo: `[ -n "$RAW" ] || RAW='[]'` transformava
# ferramenta morta em "nenhum diagnostico" - isto e, em aprovacao, com ledger `verdict: pass`.
repo d3
mkdir -p bin; printf '#!/bin/sh\nexit 2\n' > bin/ruff; chmod +x bin/ruff
printf 'def f():\n    return 1\n' > novo.py; git add -A
RC=$(PATH="$PWD/bin:$PATH" bash -c "printf '{}' | timeout 120 bash '$GATE' >'$TMP/o' 2>'$TMP/e'; echo \$?")
chk "ferramenta morta nao aprova" "$RC" 2
chk "  e a causa e nomeada (nao 'reprovou')" \
    "$(grep -c 'NAO produziu array JSON' "$TMP/o" "$TMP/e" 2>/dev/null | awk -F: '{s+=$2} END{print (s>0)?1:0}')" 1

echo "== DE4. arquivo NOVO nao rastreado tem a higiene julgada =="
# B1 do refutador: `git diff HEAD` nao ve untracked, mas o analisador o examina - e `Write`/`Edit`
# nao indexam, entao esse e o caso PADRAO de arquivo novo.
repo d4
printf 'import os\n' > untracked.py
chk "untracked com F401 barra" "$(gate)" 2
chk "  CONTROLE: arquivo limpo untracked NAO barra" \
    "$(rm -f untracked.py; printf 'y = 2\n' > limpo.py; gate)" 0

echo "== DE5. '.git' FALSO nao esconde codigo rastreado =="
# C1 do refutador: `find -name .git` casava ARQUIVO vazio - um comando escondia codigo do
# analisador. A derivacao declarada era "diretorio com repositorio proprio".
repo d5
mkdir -p sub; printf 'def f():\n    return jamais\n' > sub/mal.py; git add -A
chk "sem o .git falso: barra" "$(gate)" 2
: > sub/.git
chk "  COM o .git falso (ARQUIVO): CONTINUA barrando" "$(gate)" 2
# O `.git` DIRETORIO vazio e um caso DIFERENTE do arquivo, e a diferenca decide um mutante.
# Medido: `git rev-parse --resolve-git-dir sub/.git` falha nos dois, mas `git -C sub rev-parse
# --verify HEAD` responde rc=0 no diretorio (SOBE para o repositorio pai) e rc=128 no arquivo.
# Sem este caso, a exigencia de historia adicionada por G68 MASCARA o mutante MVG3: com
# `test -e` no lugar de `--resolve-git-dir`, o arquivo vazio ainda seria barrado pela segunda
# guarda e o mutante sobreviveria. Foi o que aconteceu - MVG3 sobreviveu ate este caso existir.
rm -f sub/.git; mkdir -p sub/.git
chk "  COM o .git falso (DIRETORIO vazio): CONTINUA barrando" "$(gate)" 2
rm -rf sub/.git; : > sub/.git
# R1 DO REFUTADOR: `--resolve-git-dir` fechou o `.git` FALSO e deixou aberto o VERDADEIRO vazio.
# `git init sub` cria diretorio de repositorio valido, e tudo debaixo dele sumia do julgamento -
# medido `antes EXIT=2, depois EXIT=0`. Este caso nao existia: o CONTROLE abaixo sempre commitou,
# entao a suite nunca exercitou a raiz SEM historia. Nao era teste que consagrava o buraco - era
# buraco que teste nenhum visitava.
rm -f sub/.git
( cd sub && git init -q . && git add -A 2>/dev/null ) >/dev/null 2>&1
chk "  'git init' SEM commit nao e checkout: continua barrando" "$(gate)" 2
chk "  CONTROLE: checkout de verdade (com historia) e ignorado" \
    "$(( cd sub && git -c user.email=t@t -c user.name=t commit -qm x >/dev/null 2>&1 ); gate)" 0
# E A EXCLUSAO E DECLARADA. Aprovar calado sobre N arquivos que se deixou de olhar e o que
# transformava a exclusao legitima em bypass: o operador nao tinha como saber que ela agiu.
chk "  e ela e REPORTADA, nao silenciosa" \
    "$(grep -c 'EXCLUIDO POR CHECKOUT ANINHADO' "$TMP/o" "$TMP/e" 2>/dev/null | awk -F: '{s+=$2} END{print (s>0)?1:0}')" 1

echo "== DE6. CHANGED grande nao desliga o adaptador (SIGPIPE) =="
# F4 do refutador, e o mutante MV5 sobreviveu ate este caso existir. `printf | grep -q` sob
# `pipefail` devolve 141 quando o grep casa CEDO e sai antes de o printf terminar: o adaptador e
# DESCARTADO EM SILENCIO e o portao sai 0. Depende do DADO - casamento no fim devolve 0, no inicio
# devolve 141 - entao um repo de teste com CHANGED pequeno nunca ve. Em /var/www/amaral-intern-hub
# o CHANGED tem 161 KB, e e de la que vem a maior parte dos registros que abrem esta onda.
repo de6
# O que precisa exceder o buffer do pipe (~65536 B) e o TAMANHO de `git status --porcelain`, nao
# a contagem de arquivos. 400 nomes longos dao 76,8 KB em 108 ms; 9000 nomes curtos dao 126 KB em
# 487 ms - e o arnes de mutacao roda esta suite uma vez por mutante, entao o custo multiplica.
python3 -c "
import pathlib
n = 'n' * 180
for i in range(400): pathlib.Path('%s%04d.txt' % (n, i)).write_text('x')
" 2>/dev/null
printf 'def f():\n    return jamais_definido\n' > aaa.py   # `.py` cedo na ordenacao: dispara o SIGPIPE
chk "CHANGED grande ainda barra quebra (adaptador NAO descartado)" "$(gate)" 2
# O buffer do pipe e ~65536 B: abaixo disso o `printf` cabe inteiro e o SIGPIPE NAO ocorre, entao
# o caso passaria sem exercitar nada. Medido: 4000 arquivos dao 56 KB (insuficiente), 9000 dao
# 126 KB.
chk "  e o CHANGED excede o buffer do pipe (o caso nao e vacuo)" \
    "$([ "$(git status --porcelain | wc -c)" -gt 70000 ] && echo sim || echo nao)" sim

echo "== DE7. upstream inexistente nao vira base por ECO =="
# `git rev-parse --abbrev-ref '@{u}'` ECOA `@{u}` quando nao ha upstream: sai nao-zero, mas o
# `|| true` engolia e a string literal virava BASE, DIFFBASE e SEEDREF. `git archive '@{u}'`
# falhava e a catraca nunca era semeada - silenciosamente. Medido em amaral-intern-hub.
repo de7
git branch --unset-upstream >/dev/null 2>&1
git remote remove origin >/dev/null 2>&1
printf 'def f():\n    return jamais\n' > q.py; git add -A; git commit -qm turno >/dev/null
printf 'y = 2\n' > untracked.py
chk "sem upstream nem remoto: barra e NAO semeia" "$(gate)" 2
chk "  2a parada continua barrando (nao anistiou por base falsa)" "$(gate)" 2
chk "  e nenhum baseline foi gravado" \
    "$(ls "$TMP/de7/bl"/*.json 2>/dev/null | wc -l | tr -d ' ')" 0

echo "== DE8. remoto SEM upstream: base derivada, nao a string ecoada =="
# O caso de /var/www/amaral-intern-hub, e o mutante MV6 sobreviveu ate ele existir. DE7 remove o
# remoto, e ali o eco de `@{u}` nao muda nada. Com remoto presente e branch sem upstream,
# `git rev-parse --abbrev-ref '@{u}'` imprime `@{u}` em stdout e sai nao-zero; o `|| true` engolia
# o codigo e a string LITERAL virava BASE, DIFFBASE e SEEDREF. `git archive '@{u}'` falhava e a
# catraca nunca era semeada - em silencio. E o nome do remoto tambem nao pode ser presumido:
# naquele repositorio chamam-se `debt-hub` e `debthub`, e a lista fixa em `origin/*` nao casava.
repo de8
# A CONDICAO DO ECO E ESPECIFICA, e a primeira versao deste caso nao a reproduzia. `git rev-parse
# --abbrev-ref '@{u}'` so ECOA a entrada quando o upstream esta CONFIGURADO e a ref NAO EXISTE -
# "ambiguous argument". Com upstream simplesmente ausente ele imprime vazio, e o mutante
# sobrevivia. Medido: com a ref presente sai `origin/main`; apagada, sai `@{u}` com rc=128.
git remote rename origin outro-nome >/dev/null 2>&1
printf 'import os\n__all__ = ["nao_existe"]\n' > velho.py; git add -A; git commit -qm divida >/dev/null
git push -q outro-nome HEAD:refs/heads/main >/dev/null 2>&1
# A REF E APAGADA POR ULTIMO: o `push` acima RECRIA `refs/remotes/<remoto>/main`, e com a ref
# presente o `@{u}` resolve e o eco nunca ocorre - foi assim que a primeira versao deste caso
# deixou o mutante MV6 sobreviver. O estado a reproduzir e upstream CONFIGURADO com ref AUSENTE.
git update-ref -d refs/remotes/outro-nome/main >/dev/null 2>&1
printf 'def f():\n    return 1\n' > novo.py; git add -A
chk "upstream configurado com ref AUSENTE: barra" "$(gate)" 2
# Sem base real - upstream aponta para ref que nao existe e nenhum candidato de remoto resolve -
# a resposta honesta e RECUSAR semear. Semear da arvore vazia gravaria um baseline que tolera nada
# e, pelo `[ ! -f ]`, impediria a re-semeadura quando uma base real aparecesse.
chk "  e NAO semeia catraca de uma base falsa" \
    "$(ls "$TMP/de8/bl"/*.json 2>/dev/null | wc -l | tr -d ' ')" 0
chk "  2a parada CONTINUA barrando (nao anistiou por eco)" "$(gate)" 2
# O DISCRIMINANTE E A CAUSA NOMEADA, nao o codigo de saida: com o eco aceito, `SEEDREF` vira a
# string `@{u}`, `git archive` falha e o portao relata "NAO foi possivel semear" - diagnostico
# ERRADO, que manda o operador procurar defeito na semeadura em vez de na base. Com a validacao,
# ele relata "sem base anterior ao turno", que e a causa real. Portao que erra a causa ensina a
# procurar no lugar errado.
chk "  e a causa nomeada e a BASE, nao a semeadura" \
    "$(grep -c 'sem base anterior ao turno' "$TMP/o" "$TMP/e" 2>/dev/null | awk -F: '{s+=$2} END{print (s>0)?1:0}')" 1

echo "== DE9. erro de sintaxe distante do hunk bloqueia (G65) =="
# FALSO NEGATIVO MEDIDO no hook INSTALADO antes da correcao: ruff 0.16.2 removeu `E999` (fonte
# primaria: `ruff rule E999` -> "This rule has been removed") e emite `invalid-syntax`, que nao
# estava em `breakage_codes`. Erro de sintaxe virava HIGIENE e passava pelo teste de hunk, porque
# a posicao que um parser reporta nao e a posicao do erro: parentese aberto na linha 1, reportado
# na 202. Resultado medido: rc=0, stdout VAZIO, arvore que nao parseia aprovada em silencio.
repo d9
{ echo "VALORES = ["; for i in $(seq 1 200); do echo "    $i,"; done; echo "]"; } > grande.py
git add -A; git commit -qm "arquivo grande valido" >/dev/null
git push -q origin HEAD:refs/heads/main >/dev/null 2>&1
# o turno toca SO a linha 1, e o parse quebra la no fim
sed -i '1s/.*/VALORES = [ (/' grande.py
LINHA_HUNK="$(git diff --unified=0 -- grande.py | grep -c '^@@ -1 ')"
chk "o hunk do turno e a linha 1" "$LINHA_HUNK" 1
LINHA_RUFF="$(ruff check --isolated --no-cache --select F,E9 --output-format json grande.py 2>/dev/null | python3 -c 'import json,sys;d=json.load(sys.stdin);print(min(x["location"]["row"] for x in d))')"
chk "  e o analisador reporta LONGE dela (>100)" "$([ "${LINHA_RUFF:-0}" -gt 100 ] && echo sim || echo "nao($LINHA_RUFF)")" sim
chk "  ainda assim o portao BARRA" "$(gate)" 2
chk "  e nomeia o arquivo que nao parseia" \
    "$(grep -c 'grande.py' "$TMP/o" "$TMP/e" 2>/dev/null | awk -F: '{s+=$2} END{print (s>0)?1:0}')" 1
# CONTROLE NEGATIVO: sem ele, "barrou" nao distingue a correcao de "barra qualquer edicao".
git checkout -q -- grande.py
sed -i '1s/.*/VALORES = [  # comentario/' grande.py
chk "  CONTROLE: a MESMA linha 1 editada sem quebrar o parse passa" "$(gate)" 0

echo "== DE10. a lista de quebra e conferida contra a FERRAMENTA, nao contra si mesma (G65) =="
# A correcao de G65 fecha o buraco de HOJE. Esta suite fecha o de AMANHA: le o comando EXATO
# declarado no adaptador, roda-o sobre um arquivo que nao parseia, e exige que todo codigo
# devolvido esteja em `breakage_codes`. Conferir a lista contra `ruff rule <codigo>` nao serviria -
# `ruff rule E999` sai 0 e imprime a regra, so marcada como removida, e manter E999 para versoes
# antigas e deliberado. O que decide e o que a ferramenta EMITE.
printf 'VALORES = [ (\n' > "$TMP/naoparseia.py"
FALTANDO="$(python3 - "$CLAUDE_ADAPTERS_DIR/python.json" "$TMP/naoparseia.py" <<'PYEOF'
import json, subprocess, sys
ad = json.load(open(sys.argv[1]))
cmd = [ad["exec"]["command"]] + [a for a in ad["exec"]["args"] if a != "."] + [sys.argv[2]]
saida = subprocess.run(cmd, capture_output=True, text=True).stdout
try:
    diags = json.loads(saida)
except json.JSONDecodeError:
    print("NAO_VERIFICADO_saida_nao_json"); raise SystemExit(0)
if not diags:
    print("NAO_VERIFICADO_zero_diagnosticos_em_arquivo_que_nao_parseia"); raise SystemExit(0)
declarados = set(ad.get("breakage_codes") or [])
# codigo NULO/VAZIO nao precisa estar declarado: `eh_quebra()` no nucleo ja o trata como quebra
# por construcao. Exigi-lo aqui seria reprovar por uma protecao que existe.
emitidos = {d.get("code") for d in diags}
faltando = sorted(c for c in emitidos if c not in declarados and c not in (None, ""))
print(",".join(faltando))
PYEOF
)"
chk "todo codigo emitido em arquivo que nao parseia esta em breakage_codes" "$FALTANDO" ""

echo "== DE11. byte nao-UTF-8 no diff nao apaga o mapa de hunks (G74) =="
# O DEFEITO MAIS CARO DESTA ONDA: `for l in sys.stdin` decodifica UTF-8 e MORRE em outro byte.
# Com `2>/dev/null` no executor e `|| HUNKS='{}'` logo abaixo, parser morto virava mapa VAZIO -
# que nao e "nada foi tocado", e sim o valor que faz TODA a higiene ser ignorada.
#
# C2 DO REVISOR, e a primeira versao deste caso era TAUTOLOGICA: a fixture punha o byte DENTRO do
# .py, entao `ruff` nao o decodificava e emitia `E902` - que esta em `breakage_codes` e bloqueia
# INDEPENDENTEMENTE do mapa de hunks. Medido: com o parser revertido ao defeito, a suite seguia
# 45/45 verde. O caso afirmava "bloqueia", e era verdade pelo motivo errado.
#
# A fixture que DISCRIMINA separa as duas coisas: o `.py` e ASCII PURO e carrega um F401 na linha
# tocada (higiene, que so bloqueia se o mapa existir), e o byte problematico mora num arquivo
# NAO-Python do mesmo diff - onde ele quebra o parser sem virar diagnostico do analisador.
repo d11
printf 'import os\n\nVALOR = 1\n' > limpo.py
printf 'campo;valor\nacentua\xe3\xe7ao;1\n' > dados.csv
git add -A
chk "o diff carrega byte nao-UTF-8 (o caso nao e vacuo)" \
    "$(git diff --cached | python3 -c 'import sys; b=sys.stdin.buffer.read(); print(0 if b.decode("utf-8","ignore").encode()==b else 1)')" 1
chk "  e o analisador NAO reporta nada sobre o arquivo do byte" \
    "$(ruff check --isolated --no-cache --select F,E9 --output-format json . 2>/dev/null | python3 -c 'import json,sys; print(sum(1 for x in json.load(sys.stdin) if x["code"]=="E902"))')" 0
chk "  o unico diagnostico e higiene (F401), que depende do mapa de hunks" \
    "$(ruff check --isolated --no-cache --select F,E9 --output-format json . 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d), d[0]["code"] if d else "-")')" "1 F401"
chk "  o portao BARRA" "$(gate)" 2
# E AQUI ESTA O DISCRIMINANTE. Com o parser morto o portao TAMBEM sai 2 - mas como LACUNA
# ("o mapa de linhas tocadas NAO pode ser lido"), nao por julgar o F401. Medir so o exit code
# deixava o mutante VIVO, que foi o que o revisor mediu: suite 45/45 verde com a correcao
# revertida. E a regra que este repositorio escreveu depois de G66 e nao aplicou aqui.
chk "  e a causa e o DIAGNOSTICO, nao lacuna de leitura do mapa" \
    "$(cat "$TMP/o" "$TMP/e" 2>/dev/null | grep -c 'mapa de linhas tocadas NAO pode ser lido')" 0
chk "  e o F401 e nomeado no veredito" \
    "$(cat "$TMP/o" "$TMP/e" 2>/dev/null | grep -c 'F401')" 1
# CONTROLE NEGATIVO: sem o arquivo do byte, o mesmo F401 barra igual. Sem isto, o caso nao
# separaria "sobreviveu ao byte" de "barra qualquer coisa".
repo d11b
printf 'import os\n\nVALOR = 1\n' > limpo.py; git add -A
chk "  CONTROLE: o mesmo F401 sem byte nenhum barra igual" "$(gate)" 2

echo "== DE12. negativa repetida muda a MENSAGEM, nao o veredito (G77) =="
# MEDIDO NO LEDGER em 2026-09-02: 1.992 de 8.600 paradas (23,2%) sao reexecucoes estritamente
# redundantes - mesmo snapshot, mesmos verificadores, mesmo ambiente, veredito anterior ja `fail`.
# Um snapshot em /home/ti/debthub-wt-phone3 foi julgado 336 vezes, todas fail, em dois dias.
# A resposta NAO e cachear o fail (consequencia assimetrica: bloquearia ate a arvore mudar, e ela
# so muda se o ator agir - que e o que ele nao esta conseguindo). E parar de repetir a mensagem.
repo d12
printf 'def f():\n    return jamais_definido\n' > q.py; git add -A
chk "1a parada barra" "$(gate)" 2
chk "  e NAO fala em laco ainda" \
    "$(grep -c 'MESMO ESTADO DE ARVORE' "$TMP/o" "$TMP/e" 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')" 0
chk "  2a parada barra" "$(gate)" 2
chk "  3a parada barra" "$(gate)" 2
chk "  e a 4a AINDA barra (o veredito nao muda)" "$(gate)" 2
chk "  mas agora a mensagem NOMEIA a repeticao" \
    "$(grep -c 'MESMO ESTADO DE ARVORE' "$TMP/o" "$TMP/e" 2>/dev/null | awk -F: '{s+=$2} END{print (s>0)?1:0}')" 1
# `grep -o` sobre DOIS arquivos prefixa cada casamento com o caminho, entao extrair "o numero" da
# linha inteira pegava digito do path. `cat` primeiro, extrai depois.
chk "  e conta as tentativas identicas" \
    "$(cat "$TMP/o" "$TMP/e" 2>/dev/null | grep -o 'ESTA E A [0-9]*a PARADA' | head -1 | grep -oE '[0-9]+')" 4
# CONTROLE NEGATIVO: mudar o arquivo muda o snapshot, e o contador reinicia - senao o caso mediria
# "o gate fala de laco depois de 3 paradas", e nao "depois de 3 paradas IGUAIS".
printf 'def f():\n    return outro_jamais\n' > q.py; git add -A
gate >/dev/null
chk "  CONTROLE: arvore diferente barra SEM falar em laco" \
    "$(cat "$TMP/o" "$TMP/e" 2>/dev/null | grep -c 'MESMO ESTADO DE ARVORE')" 0

echo "== DE13. falha de temporario NAO vira aprovacao nem aprovacao no ledger (G78/C3) =="
# O DEFEITO MAIS GRAVE DESTA SERIE, e estava VIVO em producao quando foi achado. `mktemp` que
# falha deixava `$RAWF`/`$HUNKF` vazios; o nucleo recebia `--hunks-file ""`, caia no default
# `--hunks {}` - o mapa vazio, o valor mais permissivo - e o turno era APROVADO e gravado como
# `pass`. Medido contra o hook em vigor, com TMPDIR nao gravavel: rc=0, stdout VAZIO, ledger
# `pass`; e o `pass` e PERMANENTE para aquele estado, porque curto-circuita as paradas futuras.
# Falha TRANSITORIA virando aprovacao PERMANENTE.
# Sem este caso o mutante MVG10 sobrevive - foi o que o arnes de mutacao mediu.
repo d13
printf 'import os\n' > sujo.py; git add -A
chk "com TMPDIR normal: barra" "$(gate)" 2
mkdir -p "$TMP/tmp-sem-permissao"; chmod 500 "$TMP/tmp-sem-permissao"
# ledger zerado ANTES da parada com falha, para que a assercao seguinte fale so sobre ela
rm -rf "$EVIDENCE_LEDGER_DIR"
gate_tmp(){ printf '{}' | TMPDIR="$TMP/tmp-sem-permissao" timeout 120 bash "$GATE" >"$TMP/o" 2>"$TMP/e"; echo $?; }
chk "  com TMPDIR NAO gravavel: NAO aprova" "$(gate_tmp)" 2
chk "  e a causa e nomeada (nao silencio)" \
    "$(cat "$TMP/o" "$TMP/e" 2>/dev/null | grep -c 'nao foi possivel gravar os arquivos temporarios')" 1
# O SEGUNDO DANO E O PIOR: o veredito gravado nao pode ser `pass`, senao a falha transitoria
# envenena o cache daquele snapshot para sempre.
chk "  e o ledger NAO registra pass" \
    "$(cat "$EVIDENCE_LEDGER_DIR"/*.jsonl 2>/dev/null | grep -c '"verdict":"pass"')" 0
# CONTROLE: com o TMPDIR sao de novo, o MESMO snapshot continua sendo barrado - prova que nada
# ficou envenenado no cache.
chk "  CONTROLE: mesmo snapshot com TMPDIR sao volta a barrar" "$(gate)" 2

echo "== DE14. untracked ANTIGO nao e trabalho do turno (G82) =="
# MEDIDO em /var/www/amaral-intern-hub, 2026-09-03: 400 arquivos untracked em `spokes/jusgrok/`
# com mtime de 2026-07-17 - 48 dias - e o portao acusava 79 achados de higiene deles como sendo
# do turno. A regra B1 dava a todo arquivo nao rastreado a faixa `[1, 10^9]`, com a premissa de
# que `Write`/`Edit` nao indexam. A premissa cobre o caso comum e e FALSA no geral.
# O discriminante e a hora da parada ANTERIOR, que o portao ja tem no ledger.
repo d14
mkdir -p "$EVIDENCE_LEDGER_DIR"
_k="$(printf '%s' "$PWD" | sha256sum | cut -c1-32)"
printf '{"ts":"%s","snapshot":"x","verifiers":"y","env":"z","verdict":"fail","detail":"parada anterior simulada"}\n' \
  "$(date -u -d "@$(( $(date +%s) - 3600 ))" '+%Y-%m-%dT%H:%M:%SZ')" > "$EVIDENCE_LEDGER_DIR/$_k.jsonl"
printf 'import os\n' > antigo.py; touch -d '2026-07-17 18:16' antigo.py
chk "untracked ANTIGO sozinho: NAO bloqueia" "$(gate)" 0
chk "  e a exclusao e DECLARADA, nao silenciosa" \
    "$(cat "$TMP/o" "$TMP/e" 2>/dev/null | grep -c 'NAO RASTREADO E ANTERIOR AO TURNO')" 1
# CONTROLE NEGATIVO, e ele e o que separa correcao de afrouxamento: arquivo untracked escrito
# AGORA continua sendo do turno e continua bloqueando.
printf 'import sys\n' > agora.py
chk "  CONTROLE: untracked escrito AGORA bloqueia" "$(gate)" 2
chk "  e quem bloqueia e o NOVO, nao o antigo" \
    "$(cat "$TMP/o" "$TMP/e" 2>/dev/null | grep -c 'agora\.py')" 1
# E a QUEBRA de arquivo antigo continua julgada - a exclusao e so de higiene.
rm -f agora.py
printf 'def f(:\n' > quebrado_antigo.py; touch -d '2026-07-17 18:16' quebrado_antigo.py
chk "  CONTROLE: QUEBRA em untracked antigo AINDA bloqueia" "$(gate)" 2

EXPECTED=58
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
echo
echo "================ PASS=$P  FAIL=$F ================"
[ "$F" -eq 0 ] && echo "delta ponta a ponta verde ($P/$EXPECTED)" || echo "delta ponta a ponta VERMELHO ($F falhas)"
exit "$F"
