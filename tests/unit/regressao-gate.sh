#!/usr/bin/env bash
# Regressao do GATE DE CONCLUSAO. Cada caso reproduz um defeito MEDIDO, nao um sintoma.
#
# Regra do repositorio (docs/adr/0020): caso chamado "bug do throttle" nao vale nada se nao
# reproduzir o MECANISMO. Aqui cada caso monta o estado, executa o hook e exige o exit code.
#
# ESTADO ANTES DA CORRECAO (medido em 2026-08-03, claude-code 2.1.220):
#   G1 REPROVA - segunda parada com o mesmo codigo quebrado retornava 0
#   G2 REPROVA - stop_hook_active=true saia 0 em silencio (canal que nao chega ao modelo)
#   G3 REPROVA - bytes de arquivo untracked nao entravam na identidade
#   G4 REPROVA - monorepo verificava so o primeiro ecossistema que casava
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
REPO_ROOT="$PWD"          # os casos fazem cd; guarde a raiz antes
GATE="$PWD/evidence/hooks/verify-gate.sh"
export CLAUDE_ADAPTERS_DIR="$PWD/execution/adapters/code"
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

# HOME isolado: o ledger/stamp do gate mora em $HOME. Sem isolar, o estado do usuario decide
# o resultado do teste - ja aconteceu neste repo (tests/unit/run.sh, cabecalho).
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# LEDGER ISOLADO. `verify-gate.sh` grava em `${EVIDENCE_LEDGER_DIR:-$HOME/.claude/evidence}`, e
# nenhuma suite exportava a variavel: cada execucao desta suite injetava paradas SINTETICAS no
# ledger operacional do usuario, no mesmo diretorio que serve de evidencia sobre uso real.
# Medido em 2026-09-02: 1637 arquivos de ledger criados desde 2026-09-01, quase todos de teste, e
# a taxa de aprovacao daqueles dois dias ficou inutilizavel como medida de trabalho real.
# O ledger tambem e CACHE (so `pass` do mesmo snapshot curto-circuita), entao contaminar nos dois
# sentidos: teste podia herdar `pass` de outro teste com a mesma arvore.
export EVIDENCE_LEDGER_DIR="$TMP/ledger"
export HOME="$TMP/home"; mkdir -p "$HOME/.claude/logs"

# ARMADILHA JA PAGA: `R=$(novo_repo g3)` roda a funcao num SUBSHELL, e o `cd` morre com ele -
# os casos executavam no diretorio do caso anterior e reportavam PASS/FAIL por motivo errado.
# Por isso esta funcao muda o cwd do shell PRINCIPAL e nao ecoa nada.
novo_repo(){  # $1 = nome
  R="$TMP/$1"; rm -rf "$R"; mkdir -p "$R"; cd "$R" || exit 1
  git init -q .; git config user.email t@t; git config user.name t
  echo "x = 1" > base.py; git add -A; git commit -qm base
}
gate(){ printf '{"stop_hook_active":%s}' "${1:-false}" | bash "$GATE" >"$TMP/out" 2>"$TMP/err"; echo $?; }

echo "== G1. falha em cache NAO vira sucesso na segunda parada =="
novo_repo g1
printf 'def f():\n    return indefinido\n' > quebrado.py; git add -A
rc1=$(gate false)
chk "primeira parada BARRA codigo quebrado" "$rc1" 2
rc2=$(gate false)
chk "segunda parada, MESMO snapshot quebrado, CONTINUA barrando" "$rc2" 2

# ONDA 21c. A GARANTIA DA ONDA 21 NAO TINHA ORACULO, e o `refutador` mediu a consequencia: se
# `BASE_DEPENDENTE` fosse esvaziado e o artefato regenerado - que e literalmente a instrucao
# publicada em `scripts/status.sh` -, `verify-pr` PASSARIA, porque um PR por definicao difere da
# base, e so o `verify-push` pos-merge reprovaria. Foi assim que o defeito sobreviveu a SEIS
# merges. Mutacao de ambiente e demonstracao que ninguem reexecuta; nao e barreira de regressao.
#
# ESTE E O ORACULO, e ele custa menos de um segundo porque e estatico: toda suite enumerada pelo
# gerador ou FIXA a propria contagem (e ai o desvio ja fica vermelho nela mesma), ou tem de ser
# publicada como rotulo. Publicar numero de suite sem pino e o G22.
_SUITES_DO_GERADOR="$(sed -n '/^  for t in tests\/unit/,/done$/p' "$REPO_ROOT/scripts/status.sh" \
  | grep -oE 'tests/unit/[a-z-]+\.(sh|py)' | sort -u)"
chk "o gerador enumera pelo menos 15 suites (antivacuidade)" \
  "$([ "$(printf '%s\n' "$_SUITES_DO_GERADOR" | grep -c .)" -ge 15 ] && echo ok)" ok

_SEM_PINO_PUBLICANDO_NUMERO=""
for _s in $_SUITES_DO_GERADOR; do
  [ -f "$REPO_ROOT/$_s" ] || continue
  if grep -qE '^[[:space:]]*EXPECTED=[0-9]+' "$REPO_ROOT/$_s" || grep -qE 'EXPECTED=\$\(\(' "$REPO_ROOT/$_s"; then
    continue   # a suite se autofixa: o numero publicado nao pode variar em silencio
  fi
  _linha="$(grep -F "\`$_s\`" "$REPO_ROOT/docs/status.generated.md" 2>/dev/null | head -1)"
  case "$_linha" in
    *'variavel'*) : ;;
    '')           : ;;
    *)            _SEM_PINO_PUBLICANDO_NUMERO="$_SEM_PINO_PUBLICANDO_NUMERO $_s" ;;
  esac
done
chk "nenhuma suite SEM pino publica numero no artefato (G22: o numero dependeria do contexto)" \
  "$(printf '%s' "$_SEM_PINO_PUBLICANDO_NUMERO" | tr -d ' ')" ""

echo "== G2. stop_hook_active nao pode virar verde silencioso =="
novo_repo g2
printf 'def f():\n    return indefinido\n' > quebrado.py; git add -A
rc=$(gate true)
chk "nao bloqueia (anti-loop preservado)" "$rc" 0
# canal: stderr com exit 0 NAO chega ao modelo (docs/adr/0021). Exige additionalContext.
ctx=$(jq -r '.hookSpecificOutput.additionalContext // empty' "$TMP/out" 2>/dev/null)
chk "  entrega additionalContext (canal que chega)" "$([ -n "$ctx" ] && echo sim || echo nao)" "sim"
chk "  declara o estado NOT_VERIFIED" "$(printf '%s' "$ctx" | grep -q 'NOT_VERIFIED' && echo sim || echo nao)" "sim"

echo "== G3. identidade cobre BYTES de arquivo nao rastreado =="
novo_repo g3
printf 'y = 2\n' > solto.py           # untracked, limpo
rc=$(gate false)
chk "codigo limpo passa" "$rc" 0
printf 'def g():\n    return indefinido\n' > solto.py   # MESMO nome, agora quebrado
rc=$(gate false)
chk "mudar BYTES do mesmo untracked reprova" "$rc" 2

echo "== G4. monorepo: todo ecossistema aplicavel e verificado =="
novo_repo g4
echo '{}' > package.json; git add -A; git commit -qm pkg
printf 'const a = 1;\n' > servico.js                      # JS valido
printf 'def h():\n    return indefinido\n' > quebrado.py  # Python quebrado
git add -A
rc=$(gate false)
chk "JS valido nao mascara Python quebrado" "$rc" 2

echo "== G5. tabela de adaptadores ausente e FAIL-CLOSED, nao inercia silenciosa =="
# Caso adicionado porque o mutante M5 SOBREVIVEU: a suite passava com o fail-closed removido.
novo_repo g5
printf 'def f():\n    return indefinido\n' > quebrado.py; git add -A
VAZIO="$TMP/sem-adaptadores"; mkdir -p "$VAZIO"
SALVO="$CLAUDE_ADAPTERS_DIR"; export CLAUDE_ADAPTERS_DIR="$VAZIO"
rc=$(gate false)
chk "tabela vazia BARRA (gate desligado nao pode passar batido)" "$rc" 2
chk "  declara que nao verificou" "$(grep -q 'NAO VERIFICADO' "$TMP/err" && echo sim || echo nao)" "sim"
rc=$(gate true)
chk "  em continuacao forcada, avisa por additionalContext" \
    "$(jq -re '.hookSpecificOutput.additionalContext' "$TMP/out" >/dev/null 2>&1 && echo sim || echo nao)" "sim"
export CLAUDE_ADAPTERS_DIR="$SALVO"

echo "== G6. dependencia ESTRUTURAL ausente e lacuna, nao sucesso silencioso =="
# Ferramenta de adaptador ausente ja virava lacuna; a do proprio gate saia 0 calada.
novo_repo g6
printf 'def f():\n    return indefinido\n' > quebrado.py; git add -A
BIN="$TMP/bin-sem-jq"; mkdir -p "$BIN"
for b in cat git sha256sum grep sed sort awk cut date mkdir timeout readlink ruff bash; do
  p="$(command -v $b 2>/dev/null)" && ln -sf "$p" "$BIN/$b"
done
rc=$(PATH="$BIN" printf '{"stop_hook_active":false}' | PATH="$BIN" bash "$GATE" >"$TMP/out" 2>"$TMP/err"; echo $?)
chk "sem jq em repo git: BARRA em vez de sair 0" "$rc" 2
chk "  nomeia a dependencia ausente" "$(grep -q "jq" "$TMP/err" && echo sim || echo nao)" "sim"
rc=$(PATH="$BIN" printf '{"stop_hook_active":true}' | PATH="$BIN" bash "$GATE" >/dev/null 2>&1; echo $?)
chk "  em continuacao forcada, nao trava a sessao" "$rc" 0

echo "== G7. adaptador que EXECUTA codigo do repo nao roda em auto-deteccao =="
# A doc da Microsoft adverte que `dotnet format` compila e roda analisadores do projeto.
novo_repo g7
printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > App.csproj
printf 'class P { static void Main() {} }\n' > Program.cs; git add -A
rc=$(gate false)
chk "repo .NET nao passa em silencio" "$rc" 2
chk "  declara LACUNA (nao falha de codigo)" "$(grep -q 'LACUNA DE COBERTURA' "$TMP/err" && echo sim || echo nao)" "sim"
chk "  nomeia o ecossistema" "$(grep -q 'dotnet' "$TMP/err" && echo sim || echo nao)" "sim"
# Sem esta assercao o caso passa mesmo com a garantia removida: o adaptador entraria na
# execucao e a lacuna viria de 'dotnet nao esta no PATH', que e outro motivo. Achado por M7.
chk "  o motivo e EXECUTAR codigo do repo, nao binario ausente" \
    "$(grep -q 'declara executar codigo do repositorio' "$TMP/err" && echo sim || echo nao)" "sim"

echo "== G8. identidade do AMBIENTE cobre o binario, nao so o caminho =="
# Cache `pass` nao pode sobreviver a troca do verificador no mesmo path.
novo_repo g8
FAKEBIN="$TMP/fake"; mkdir -p "$FAKEBIN"
printf '#!/bin/sh\n[ "$1" = "--version" ] && { echo "fakelint 1.0"; exit 0; }\nexit 0\n' > "$FAKEBIN/fakelint"
chmod +x "$FAKEBIN/fakelint"
ADT="$TMP/adap"; mkdir -p "$ADT"
jq -n '{id:"fake",ecosystem:"fake",operation_class:"parse",extensions:[".fk"],
        exec:{command:"fakelint",args:["check"]},
        declared_effects:{executes_repository_code:false,writes_repository:false,network:false},
        rationale:"fixture", limits:{timeout_seconds:10}}' > "$ADT/fake.json"
echo "conteudo" > alvo.fk
# LINHA ORFA REMOVIDA: era `rm -f "$HOME/.claude/evidence"/*.jsonl`, e desde G76 o portao NAO
# escreve mais ali - apagava o ledger REAL do operador sem isolar nada deste caso.
SALVO2="$CLAUDE_ADAPTERS_DIR"; export CLAUDE_ADAPTERS_DIR="$ADT"; export PATH="$FAKEBIN:$PATH"
rc=$(gate false); chk "primeira execucao aprova" "$rc" 0
# G76: a suite passou a isolar o ledger (`EVIDENCE_LEDGER_DIR`), e este caso continuou lendo o
# ledger REAL do operador - lugar onde o portao ja nao escreve. Resultado: `ENV1 == ENV2` por
# ler dado velho, e a garantia G11 ("trocar o binario no MESMO path invalida o cache") passou a
# reprovar sem que nada em `verify-gate.sh` tivesse mudado. Isolar o instrumento sem reapontar
# quem o le e a mesma classe de defeito que a onda inteira persegue.
# O LEDGER E POR REPOSITORIO, e ler o glob inteiro era a causa da nao determinacao. O portao
# nomeia o arquivo por `sha256(ROOT) | cut -c1-32` (verify-gate.sh, bloco G1), e `cat *.jsonl |
# tail -1` devolvia a ultima linha do ULTIMO arquivo do glob - que so por acaso e o deste caso.
# Medido pelo refutador: passava em ~12,6% das execucoes, e reprovava nas outras sem que nada em
# `verify-gate.sh` tivesse mudado. Segunda metade do mesmo defeito de G76: isolei o instrumento e
# reapontei so um dos leitores.
LED="${EVIDENCE_LEDGER_DIR:-$HOME/.claude/evidence}"
ledger_deste_repo(){ printf '%s/%s.jsonl' "$LED" "$(printf '%s' "$PWD" | sha256sum | cut -c1-32)"; }
ENV1=$(tail -1 "$(ledger_deste_repo)" 2>/dev/null | jq -r '.env')
# mesmo caminho, binario DIFERENTE (versao nova)
printf '#!/bin/sh\n[ "$1" = "--version" ] && { echo "fakelint 2.0"; exit 0; }\nexit 1\n' > "$FAKEBIN/fakelint"
chmod +x "$FAKEBIN/fakelint"
rc=$(gate false)
ENV2=$(tail -1 "$(ledger_deste_repo)" 2>/dev/null | jq -r '.env')
chk "trocar o binario no MESMO path invalida o cache" "$([ "$ENV1" != "$ENV2" ] && echo sim || echo nao)" "sim"
chk "  e o veredito novo reprova" "$rc" 2
export CLAUDE_ADAPTERS_DIR="$SALVO2"

echo "== G9. dependencia estrutural: 'git' ausente com .git presente =="
# G6 cobria so `jq`. Sem este caso, `command -v git || exit 0` seguia fail-open silencioso.
novo_repo g9
printf 'def f():\n    return indefinido\n' > quebrado.py; git add -A
BIN2="$TMP/bin-sem-git"; mkdir -p "$BIN2"
for b in cat jq sha256sum grep sed sort awk cut date mkdir timeout readlink ruff bash dirname; do
  p="$(command -v $b 2>/dev/null)" && ln -sf "$p" "$BIN2/$b"
done
rc=$(printf '{"stop_hook_active":false}' | PATH="$BIN2" bash "$GATE" >"$TMP/out" 2>"$TMP/err"; echo $?)
chk "sem git, com .git presente: BARRA" "$rc" 2
chk "  nomeia a dependencia ausente" "$(grep -q "'git' nao esta no PATH" "$TMP/err" && echo sim || echo nao)" "sim"
FORA="$TMP/nao-e-repo"; mkdir -p "$FORA"; cd "$FORA"
rc=$(printf '{"stop_hook_active":false}' | PATH="$BIN2" bash "$GATE" >/dev/null 2>&1; echo $?)
chk "  fora de repositorio, inerte segue legitimo" "$rc" 0

echo "== G10. --dry-run do instalador NAO altera estado (byte a byte) =="
# Regressao MEDIDA: a etapa de convergencia rodava `rm -rf` antes de checar DRY, e o modo
# anunciado como inspecao segura apagou um componente.
DH="$TMP/dryhome/.claude"; mkdir -p "$DH"
( cd "$REPO_ROOT" && CLAUDE_HOME="$DH" bash install/apply.sh >/dev/null 2>&1 )
echo "orfao" > "$DH/hooks/saiu.sh"
printf 'hooks/saiu.sh\n' >> "$DH/tollens/managed-files.lock"
dig(){ find "$1" -type f ! -path '*/backups/*' -exec sha256sum {} + 2>/dev/null | sed "s|$1||" | LC_ALL=C sort -k2 | sha256sum | cut -c1-32; }
rm -rf "$DH/backups"      # o backup existente veio do apply que preparou o cenario
ANTES=$(dig "$DH")
# EXIT CODE E ASSERCAO: sem ele, um `cd` falho fazia o dry-run nunca rodar e o caso PASSAVA -
# "estado identico" e trivialmente verdadeiro quando a operacao nao aconteceu. Achado pela CI,
# que roda noutro caminho e expos o path absoluto que sobrara aqui.
( cd "$REPO_ROOT" && CLAUDE_HOME="$DH" bash install/apply.sh --dry-run >"$TMP/dry" 2>&1 ); DRC=$?
chk "o dry-run de fato executou (exit 0)" "$DRC" 0
DEPOIS=$(dig "$DH")
chk "estado identico apos --dry-run" "$([ "$ANTES" = "$DEPOIS" ] && echo sim || echo nao)" "sim"
chk "  o orfao continua no disco" "$([ -f "$DH/hooks/saiu.sh" ] && echo sim || echo nao)" "sim"
chk "  mas o plano ANUNCIA a remocao" "$(grep -q 'REMOVERIA' "$TMP/dry" && echo sim || echo nao)" "sim"
chk "  e nao cria backup" "$([ -d "$DH/backups" ] && echo nao || echo sim)" "sim"

echo "== G12. commit sem upstream NAO some do conjunto de mudancas =="
# NUMERACAO: os rotulos deste arquivo iam ate G10 e os do ADR 0022 ate G11 (identidade do
# ambiente, que aqui e G8) - as duas sequencias ja divergiam. G12 e livre nas duas; nao
# reaproveitar G11 evita compor a divergencia.
#
# DEFEITO REPRODUZIDO antes da correcao: sem `@{u}`, os commits nao publicados eram OMITIDOS do
# calculo. Como `git commit` tambem zera `diff HEAD` e a lista de untracked, CHANGED ficava
# vazio e o gate saia 0 EM SILENCIO - inerte justamente quando ha artefato pronto para
# atravessar. Medido: branch nova, `origin/main` publicado, commit com F821 -> exit 0.
#
# Os tres casos abaixo tem de andar juntos. Sozinho, o primeiro seria satisfeito por um gate
# que barra sempre; o segundo impede isso. E o terceiro fixa a fronteira semantica: sem remoto
# nao ha fronteira externa a atravessar, e inercia continua sendo a resposta certa - do
# contrario o gate viraria ruido em todo repositorio local e seria desligado.
REMOTO="$TMP/g12-remoto.git"; git init -q --bare "$REMOTO"
novo_repo g12
git remote add origin "$REMOTO"
git push -q origin HEAD:main 2>/dev/null
git fetch -q origin 2>/dev/null
git checkout -q -b sem-upstream
printf 'def g():\n    return indefinido_g12\n' > quebrado.py; git add -A; git commit -qm "quebrado"
chk "cenario montado: branch SEM upstream, com remoto publicado" \
    "$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1 && echo tem || echo nenhum)" "nenhum"
chk "  arvore limpa: o defeito so aparece com tudo committado" \
    "$( [ -z "$(git diff --name-only HEAD)$(git ls-files --others --exclude-standard)" ] && echo sim || echo nao)" "sim"
chk "  commit nao publicado com codigo quebrado BARRA (era exit 0 mudo)" "$(gate false)" 2
printf 'def g():\n    return 1\n' > quebrado.py; git add -A; git commit -qm "limpo"
chk "  e LIBERA quando o mesmo commit esta limpo (nao vira 'barra sempre')" "$(gate false)" 0
novo_repo g12b
printf 'def f():\n    return indefinido\n' > quebrado.py; git add -A; git commit -qm "quebrado"
chk "  SEM remoto: inerte segue legitimo (ausencia de fronteira, nao lacuna)" "$(gate false)" 0

echo "== G13. a aprovacao de verify.json exige SHA-256 COMPLETO, nao prefixo de 16 hex =="
# Ate 2026-08-04 o gate comparava `sha256sum ... | cut -c1-16` - 64 bits - para autorizar a
# EXECUCAO de um comando vindo do repositorio, enquanto a identidade do ambiente no mesmo arquivo
# ja documentava que truncar seria "outra propriedade". Achado da auditoria externa.
#
# COMO ISTO E TESTAVEL SEM ROOT: o caminho aprovado exige lista pertencente a root, e a suite nao
# tem sudo. Mesma tecnica do caso 5 de tests/unit/run.sh - um MUTANTE com a checagem de posse
# fixada em "root" torna o caminho alcancavel, e o que resta sob teste e o DIGESTO. O mutante e
# o instrumento aqui, nao o alvo.
MUT13="$TMP/gate-sem-posse.sh"
python3 - "$GATE" "$MUT13" <<'PYEOF'
import re, sys
s = open(sys.argv[1]).read()
s2 = re.sub(r'OWNER="\$\(stat[^\n]*\)"', 'OWNER="root"', s)
assert s2 != s, "ANCORA NAO CASOU - o mutante nao removeu a checagem de posse"
open(sys.argv[2], "w").write(s2)
PYEOF
chk "instrumento construido (checagem de posse fixada em root)" \
    "$(grep -c 'OWNER="root"' "$MUT13")" "1"

g13_repo(){  # monta repo com verify.json que marca um arquivo; $1 = json extra
  novo_repo "$1x"; mkdir -p .claude
  MARK13="$TMP/G13_EXECUTOU"; rm -f "$MARK13"
  jq -n --arg m "$MARK13" --argjson extra "$2" \
    '{exec:{command:"sh",args:["-c",("printf ok > "+$m)]}} + $extra' > .claude/verify.json
  printf 'def f():\n    return 1\n' > app.py; git add -A; git commit -qm b
  printf '# muda\n' >> app.py; git add -A
}
# NAO ECOA NADA, e por isso NAO pode ser chamada dentro de `$( )`. Publica em EXECUTOU13 e
# SAIDA13, que sao lidas depois. E a mesma armadilha que o cabecalho deste arquivo ja documenta
# para `novo_repo`: command substitution roda num SUBSHELL, e toda atribuicao morre com ele.
# Paguei-a de novo aqui - a primeira versao lia $SAIDA13 e explodia em 'unbound variable'.
EXECUTOU13=""; SAIDA13=""
g13_roda(){  # $1 = conteudo da lista de aprovacao
  # HOME NOVO A CADA CHAMADA: o ledger do gate vive sob $HOME, e um veredito `pass` do MESMO
  # snapshot faz a execucao seguinte sair no cache antes de qualquer analise.
  H13="$TMP/h13"; rm -rf "$H13"; mkdir -p "$H13/.claude/logs"
  printf '%s\n' "$1" > "$H13/.claude/verify-cmd-approved"
  rm -f "$MARK13"
  SAIDA13="$( printf '{}' | HOME="$H13" bash "$MUT13" 2>&1 )"
  EXECUTOU13="$([ -f "$MARK13" ] && echo sim || echo nao)"
}

CONTRATO='{"replaces":["python"],"coverage_justification":"fixture"}'
g13_repo g13 "$CONTRATO"
D13_PLENO="$(sha256sum .claude/verify.json | cut -d' ' -f1)"
D13_CURTO="$(printf '%s' "$D13_PLENO" | cut -c1-16)"
# CONTROLE POSITIVO PRIMEIRO: sem ele, um gate que nunca executasse nada passaria no negativo.
g13_roda "$D13_PLENO"
chk "  com o digest COMPLETO na lista, o comando do projeto executa" "$EXECUTOU13" "sim"
g13_roda "$D13_CURTO"
chk "  com o PREFIXO de 16 hex, NAO executa (o comprimento decide)" "$EXECUTOU13" "nao"

echo "== G14. aprovado sem CONTRATO DE SUBSTITUICAO nao substitui a cobertura generica =="
# `APLICAVEIS=("$REPO_VERIFY")` trocava TODOS os analisadores genericos pelo comando do projeto,
# em silencio. Num repo poliglota, um verify.json que so roda a suite de Python apagava a
# checagem de Node, Go e shell - e a perda de cobertura tinha a forma de uma aprovacao.
g13_repo g14 '{}'
D14="$(sha256sum .claude/verify.json | cut -d' ' -f1)"
g13_roda "$D14"
chk "sem 'replaces'/'coverage_justification', o comando NAO executa" "$EXECUTOU13" "nao"
chk "  e o gate DIZ o que falta (nao falha em silencio)" \
    "$(printf '%s' "$SAIDA13" | grep -c 'contrato de substituicao')" "1"

echo "== G15. ecossistema fora de 'replaces' continua coberto pelo analisador generico =="
# A propriedade que o contrato compra: o projeto assume o que declara, e SO isso.
novo_repo g15; mkdir -p .claude
MARK13="$TMP/G15_EXECUTOU"; rm -f "$MARK13"
jq -n --arg m "$MARK13" '{exec:{command:"sh",args:["-c",("printf ok > "+$m)]},
   replaces:["python"], coverage_justification:"o projeto assume so Python"}' > .claude/verify.json
printf 'def f():\n    return 1\n' > app.py
printf 'const x = 1;\n' > app.js
git add -A; git commit -qm b
# JS QUEBRADO: se o adaptador de Node ainda for aplicavel, o gate tem de BARRAR. Se o comando do
# projeto tivesse substituido tudo, o JS quebrado passaria batido e o gate sairia 0.
printf 'function f( {\n' > app.js; git add -A
D15="$(sha256sum .claude/verify.json | cut -d' ' -f1)"
H13="$TMP/h15"; rm -rf "$H13"; mkdir -p "$H13/.claude/logs"
printf '%s\n' "$D15" > "$H13/.claude/verify-cmd-approved"
RC15="$( printf '{}' | HOME="$H13" bash "$MUT13" >/dev/null 2>&1; echo $? )"
chk "o comando do projeto executou (ecossistema reivindicado)" \
    "$([ -f "$MARK13" ] && echo sim || echo nao)" "sim"
chk "  e o JS quebrado AINDA barra (cobertura nao reivindicada permanece)" "$RC15" "2"

echo "== G16. per_file com ZERO arquivos casados presentes vira LACUNA, nunca aprovacao =="
# DEFEITO REPRODUZIDO antes da correcao: o laco per_file so roda para arquivos de CHANGED que
# ainda existem (`[ -f "$ROOT/$f" ] || continue`). Se apagar o UNICO arquivo casado, o laco
# nunca roda, RC fica no valor de inicializacao (0), e o adaptador contava como APROVADO sem
# examinar nada. Medido: repo so com o .sh apagado -> exit 0, saida vazia.
novo_repo g16
printf 'echo ok\n' > script.sh; git add -A; git commit -qm base_sh
git rm -q script.sh
rc=$(gate false)
chk "apagar o UNICO .sh casado nao aprova em silencio" "$rc" 2
chk "  declara LACUNA, nao FALHA de codigo" \
    "$(grep -q 'LACUNA DE COBERTURA' "$TMP/err" && ! grep -q 'VERIFICACAO FALHOU' "$TMP/err" \
       && echo sim || echo nao)" "sim"
chk "  nomeia zero unidades examinadas" \
    "$(grep -q 'zero unidades examinadas' "$TMP/err" && echo sim || echo nao)" "sim"

echo "== G17. per_file com AO MENOS UM arquivo casado presente examina normalmente =="
# Sem este caso, a correcao de G16 poderia ter transformado toda delecao em lacuna - o defeito
# OPOSTO (um commit que so apaga arquivo, quando ha outro do mesmo tipo NO MESMO CHANGED, e
# legitimo e deve continuar sendo verificado pelo que sobrou). O per_file so examina o que esta
# em CHANGED (nao a arvore inteira) - por isso os DOIS arquivos precisam estar no diff: um
# MODIFICADO (presente) e um APAGADO (ausente), no mesmo turno.
novo_repo g17
printf 'echo ok\n' > fica.sh
printf 'echo also\n' > vai.sh
git add -A; git commit -qm base_sh2
printf 'echo ok2\n' >> fica.sh   # entra em CHANGED por modificacao, nao so por criacao
git add -A
git rm -q vai.sh                 # apagado, no MESMO turno de fica.sh modificado
rc=$(gate false)
chk "um .sh some, o outro MUDOU e esta no CHANGED: passa (nao vira lacuna a toa)" "$rc" 0

echo "== G18. renomear com conteudo divergente (derrota deteccao de similaridade) tambem vira LACUNA =="
# Segunda rota para zero-unidades-examinadas: git diff --name-only sem deteccao de rename lista
# o caminho ANTIGO como apagado quando o conteudo mudou o suficiente. O caminho antigo casa a
# extensao do adaptador e nao existe mais no disco - mesmo mecanismo de G16.
novo_repo g18
printf '#!/bin/sh\necho a\n' > mover.sh; git add -A; git commit -qm base_mv
git mv mover.sh mover.txt
python3 -c "import random; random.seed(2); print(''.join(chr(random.randint(65,90)) for _ in range(9000)))" > mover.txt
git add -A
rc=$(gate false)
chk "rename+reescrita deixa o caminho .sh antigo como apagado: vira LACUNA" "$rc" 2
chk "  ainda nomeia zero unidades examinadas" \
    "$(grep -q 'zero unidades examinadas' "$TMP/err" && echo sim || echo nao)" "sim"

echo "== G19. symlink quebrado casando a extensao tambem vira LACUNA (nao e regular file) =="
# Terceira rota: `[ -f ]` so aceita arquivo regular (segue o link). Um symlink cujo alvo nao
# existe casa a extensao em CHANGED mas nunca passa no teste `-f` - mesmo mecanismo de G16.
novo_repo g19
ln -s /alvo/que/nao/existe.sh quebrado-link.sh
git add -A
rc=$(gate false)
chk "symlink quebrado casando .sh vira LACUNA (zero unidades)" "$rc" 2
chk "  nao passa em silencio (ha saida)" \
    "$([ -s "$TMP/out" ] || [ -s "$TMP/err" ] && echo tem-saida || echo silencioso)" "tem-saida"

echo "== G20. adaptador de ARVORE INTEIRA (nao per_file) com ecossistema ausente da arvore vira LACUNA =="
# GENERALIZACAO (Correcao 2): o mesmo defeito tem uma segunda forma. Um adaptador nao-per_file
# roda sobre TODA a arvore (nao so CHANGED); normalmente apagar um arquivo nao esvazia o
# ecossistema inteiro, mas quando o apagado era o ULTIMO do ecossistema, a ferramenta roda sobre
# uma arvore vazia. Medido: `ruff check .` sem nenhum .py imprime "No Python files found" e sai
# 0 - aprovacao sobre nada, sem depender de RC (que a ferramenta zera por conta propria).
novo_repo g20
git rm -q base.py
rc=$(gate false)
chk "apagar o UNICO .py do repo nao aprova em silencio" "$rc" 2
chk "  declara LACUNA nomeando o ecossistema ausente" \
    "$(grep -q 'nenhum arquivo do ecossistema python existe mais na arvore' "$TMP/err" && echo sim || echo nao)" "sim"

echo "== G21. arvore inteira com OUTRO arquivo do ecossistema presente examina normalmente =="
novo_repo g21
printf 'y = 2\n' > outro.py; git add -A; git commit -qm outro
git rm -q base.py
rc=$(gate false)
chk "apagar um .py mas outro .py limpo permanece: passa (nao vira lacuna a toa)" "$rc" 0

echo "== G22 (SONDA DE ACAO-NULA). para CADA adaptador da tabela, a acao nula nao aprova em silencio =="
# A classe do defeito: um verificador que aprova sobre nada nao e oraculo de coisa alguma. Para
# cada adaptador declarado em execution/adapters/code, monta um repo minimo cujo UNICO arquivo
# casa a primeira extensao do adaptador, commita, e apaga esse arquivo como UNICA mudanca - a
# acao nula do ecossistema. Tres desfechos sao legitimos e distintos de aprovacao vacua:
#   1. LACUNA DE COBERTURA nomeando o adaptador (a correcao de G16/G20);
#   2. LACUNA DE COBERTURA por G10 - adaptador que executa codigo do repo nunca roda sozinho
#      (dotnet-analyzer cai aqui, por mecanismo DIFERENTE, ja coberto por G7);
#   3. bloqueio com saida nao vazia (a ferramenta reprovou de verdade sobre outra coisa).
# Binario ausente vira LACUNA DECLARADA nomeada, nunca pulo silencioso.
for AJ in "$CLAUDE_ADAPTERS_DIR"/*.json; do
  AID="$(jq -r '.id' "$AJ")"; AECO="$(jq -r '.ecosystem' "$AJ")"
  AEXT="$(jq -r '.extensions[0]' "$AJ")"; ACMD="$(jq -r '.exec.command' "$AJ")"
  AEXEC_REPO="$(jq -r '.declared_effects.executes_repository_code // false' "$AJ")"
  if [ "$AEXEC_REPO" != "true" ] && ! command -v "$ACMD" >/dev/null 2>&1; then
    echo "  LACUNA DECLARADA: $AID - '$ACMD' nao esta no PATH deste ambiente; sonda nao executada."
    continue
  fi
  novo_repo "sonda-$(basename "$AJ" .json)"
  git rm -q base.py; git commit -qm "remove semente"   # a sonda quer o ecossistema ISOLADO
  printf 'x\n' > "unidade${AEXT}"
  git add -A; git commit -qm "unidade $AECO"
  git rm -q "unidade${AEXT}"
  rc=$(gate false)
  VAZIO="nao"; [ ! -s "$TMP/out" ] && [ ! -s "$TMP/err" ] && VAZIO="sim"
  RESULTADO="nao-vacuo"; [ "$rc" = "0" ] && [ "$VAZIO" = "sim" ] && RESULTADO="vacuo"
  chk "  $AID: acao nula (apagar unico $AEXT) nao aprova em silencio (rc=$rc)" "$RESULTADO" "nao-vacuo"
done

cd /
echo
# ONDA 22. PARIDADE README EN/PT ERA INVARIANTE MANTIDA A MAO. Os dois arquivos tinham
# estrutura identica e NENHUMA suite conferia isso. Manter em passo por disciplina e o que a
# secao 6.3 do CLAUDE.md chama de hipotese, nao de garantia.
#
# ONDA 22b, TRES CORRECOES DO `revisor-codigo`, cada uma reproduzida por mutante que ele
# EXECUTOU contra a versao anterior deste bloco:
#
#   A1  esvaziar 12 subsecoes do PT (155 linhas -> `TODO`) passava nas tres assercoes. O bloco
#       fecha paridade ESTRUTURAL; o comentario anterior dizia que fechava paridade EN/PT, o que
#       e sobredeclaracao de escopo. Fechado pela razao de VOLUME por secao.
#   A2  truncar 67 de 88 secoes NOS DOIS arquivos passava verde, porque a antivacuidade usava
#       `>= 15` contra um valor real de 88 - 5,9x abaixo. E a mesma suite pina com `-eq` cinco
#       linhas abaixo. Fechado por igualdade.
#   A3  `grep -cE '^#{1,3} '` conta cabecalho dentro de cerca de codigo, e os dois README
#       publicam blocos `bash`. Reproduzido FAIL por ruido. Latente hoje (0 ocorrencias medidas),
#       e portao que reprova por ruido treina o operador a ignora-lo. Fechado filtrando cercas.
_EN="$REPO_ROOT/README.md"; _PT="$REPO_ROOT/README.pt-BR.md"

# CABECALHO FORA DE CERCA DE CODIGO. `awk` alterna o estado a cada ``` e so emite o que esta
# fora - o `grep` cru nao tem como saber disso.
_hdr(){ awk 'BEGIN{b=0} /^```/{b=!b; next} !b && /^#{1,3} /{print}' "$1"; }
_n_en="$(_hdr "$_EN" | wc -l)"; _n_pt="$(_hdr "$_PT" | wc -l)"
chk "README EN e PT tem a mesma contagem de cabecalhos (fora de cerca de codigo)" "$_n_en" "$_n_pt"

# A numeracao tem de casar POSICAO A POSICAO. Contagem igual com ordem diferente passaria pela
# checagem acima - foi por isso que ela nao basta sozinha, e o mutante 2 da onda 22 provou.
_secs(){ _hdr "$1" | grep -oE '^#{2,3} [0-9]+(\.[0-9]+)?' | grep -oE '[0-9]+(\.[0-9]+)?' | tr '\n' ' '; }
_sec_en="$(_secs "$_EN")"; _sec_pt="$(_secs "$_PT")"
chk "README EN e PT tem a MESMA sequencia de numeros de secao" "$_sec_en" "$_sec_pt"

# ANTIVACUIDADE POR IGUALDADE, nao por piso. O valor e determinado pelo arquivo VERSIONADO, entao
# nao ha razao de ambiente para tolerar desigualdade - e a desigualdade deixava passar a remocao
# de 76% do documento.
# ONDA 26: 88 -> 89. A secao 16.3 (cobertura universal de subagentes) foi acrescentada aos DOIS
# READMEs, e este valor e antivacuidade por IGUALDADE de proposito: ele so pode ser atualizado
# junto com uma mudanca real de estrutura, e nunca afrouxado para um piso - o comentario acima
# registra que a desigualdade deixava passar a remocao de 76% do documento.
_N_SECOES_README=89
chk "a varredura cobre o README inteiro (nao um prefixo truncado)" \
  "$(printf '%s' "$_sec_en" | wc -w)" "$_N_SECOES_README"

# VOLUME POR SECAO, que e o que fecha a traducao vazia. Estrutura identica com corpo esvaziado
# passava nas tres checagens acima. Medido na arvore atual: razao global PT/EN = 1.07, e a pior
# das 88 secoes = 0.95. O piso de 0.55 e folgado de proposito - ele existe para pegar `TODO` e
# secao apagada, nao para policiar estilo de traducao.
_RAZAO_MIN=55
_secs_magras="$(python3 - "$_EN" "$_PT" "$_RAZAO_MIN" <<'PYEOF'
import re, sys
def blocos(p):
    fora, b, atual, chave = {}, False, [], None
    for ln in open(p, encoding="utf-8"):
        if ln.startswith("```"): b = not b; continue
        m = None if b else re.match(r"^#{2,3} ([0-9]+(?:\.[0-9]+)?)", ln)
        if m:
            if chave: fora[chave] = len(" ".join(atual).split())
            chave, atual = m.group(1), []
        elif chave is not None:
            atual.append(ln)
    if chave: fora[chave] = len(" ".join(atual).split())
    return fora
en, pt, piso = blocos(sys.argv[1]), blocos(sys.argv[2]), int(sys.argv[3])
magras = [k for k in en if k in pt and en[k] >= 20 and pt[k] * 100 < en[k] * piso]
print(" ".join(sorted(magras)))
PYEOF
)"
chk "nenhuma secao do PT encolheu contra a irma EN (traducao vazia)" "$_secs_magras" ""

echo "================ PASS=$P  FAIL=$F ================"
# CONTAGEM E INVARIANTE, nao descricao. Sem isto, apagar cinco casos deixa PASS=15/FAIL=0 e a
# suite segue verde - o numero no relatorio viraria documentacao, nao garantia.
EXPECTED=65
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
[ "$F" -eq 0 ] && echo "regressao do gate verde ($P/$EXPECTED)" || echo "regressao do gate VERMELHA"
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
