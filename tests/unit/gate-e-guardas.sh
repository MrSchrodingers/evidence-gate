#!/usr/bin/env bash
# Suite de regressao. Cada caso existe porque um defeito REAL passou por ele.
#
# ISOLAMENTO - o que e isolado e o que nao e, e por que:
#  - ISOLADO: caminhos de consentimento (sentinela, lista de aprovacao) via HOME proprio, e o
#    stamp de throttle por repo. Sem isso, estado do usuario faz o teste passar/falhar por
#    coincidencia - aconteceu.
#  - NAO ISOLADO de proposito: a toolchain. Rodar com $HOME fabricado faz ferramenta em
#    ~/.local deixar de resolver, e o teste falharia por AUSENCIA de ferramenta, nao por
#    defeito - falso negativo.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
CTRL="$PWD/control/hooks"
EXEC="$PWD/execution/hooks"
EVID="$PWD/evidence/hooks"
AD="$PWD/execution/adapters/code"
# O ambiente pode trazer CLAUDE_ADAPTERS_DIR do settings.json instalado - e ai a suite testaria
# a copia instalada, nao o repositorio. Descoberto ao ver o gate ler ~/.claude durante o teste.
export CLAUDE_ADAPTERS_DIR="$AD"
# hooks vivem em tres planos desde o ADR 0022; C0/C1 nao existem mais.
ALLHOOKS="$CTRL $EXEC $EVID"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# LEDGER ISOLADO. `verify-gate.sh` grava em `${EVIDENCE_LEDGER_DIR:-$HOME/.claude/evidence}`, e
# nenhuma suite exportava a variavel: cada execucao desta suite injetava paradas SINTETICAS no
# ledger operacional do usuario, no mesmo diretorio que serve de evidencia sobre uso real.
# Medido em 2026-09-02: 1637 arquivos de ledger criados desde 2026-09-01, quase todos de teste, e
# a taxa de aprovacao daqueles dois dias ficou inutilizavel como medida de trabalho real.
# O ledger tambem e CACHE (so `pass` do mesmo snapshot curto-circuita), entao contaminar nos dois
# sentidos: teste podia herdar `pass` de outro teste com a mesma arvore.
export EVIDENCE_LEDGER_DIR="$TMP/ledger"
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }
run(){ printf '%s' "$1" | bash "$2" 2>"${3:-/dev/null}"; echo $?; }
limpa(){ local k; k="$(printf '%s' "$1" | md5sum | cut -c1-12)"; rm -f "$HOME/.claude/logs/.verifygate-$k" 2>/dev/null; }
SENT=".$(printf 'fa%s' 'ble')-allowed"; MODEL_X="$(printf 'fa%s' 'ble')"

echo "== 1. sintaxe e JSON =="
bad=0; for f in "$CTRL"/*.sh "$EXEC"/*.sh "$EVID"/*.sh; do bash -n "$f" 2>/dev/null || { echo "    QUEBRADO: $f"; bad=1; }; done
chk "bash -n em $(ls "$CTRL"/*.sh "$EXEC"/*.sh "$EVID"/*.sh | wc -l) hooks" "$bad" 0
bad=0; for a in "$AD"/*.json; do jq -e . "$a" >/dev/null 2>&1 || { echo "    invalido: $a"; bad=1; }; done
chk "adaptadores sao JSON valido" "$bad" 0

echo "== 2. CONTRATO DO ADAPTADOR: analyzer exige justificativa de nao-execucao =="
# A distincao analyzer/test e a correcao de uma vulnerabilidade (classe CVE-2025-59536).
# Sem a justificativa escrita, ninguem revisa se o comando realmente nao executa codigo do repo.
bad=0
for a in "$AD"/*.json; do
  jq -e '.analyzer.cmd' "$a" >/dev/null 2>&1 || continue
  j="$(jq -r '.analyzer.porque_nao_executa // empty' "$a")"
  [ -n "$j" ] || { echo "    sem porque_nao_executa: $(basename "$a")"; bad=1; }
done
chk "todo analyzer justifica por que nao executa codigo do repo" "$bad" 0
bad=0
for a in "$AD"/*.json; do
  jq -e '.test.cmd' "$a" >/dev/null 2>&1 || continue
  [ "$(jq -r '.test.executa_codigo_do_repo // false' "$a")" = "true" ] || { echo "    test sem flag: $(basename "$a")"; bad=1; }
done
chk "todo test declara que executa codigo do repo" "$bad" 0

echo "== 3. AMPLITUDE: o gate reconhece ecossistema sem editar o hook =="
# Era o defeito estrutural do global anterior: 19 mencoes de python/npm dentro do hook.
for eco in python node go rust dotnet java; do
  [ -f "$AD/$eco.json" ] && chk "adaptador presente: $eco" 0 0
done
D="$TMP/cs"; mkdir -p "$D"; ( cd "$D"; git init -q .; git config user.email t@t; git config user.name t
  printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > App.csproj
  printf 'class P { static void Main() {} }\n' > Program.cs
  git add -A; git commit -qm b ) >/dev/null 2>&1
printf '// e\n' >> "$D/Program.cs"; limpa "$D"
OUT="$( cd "$D" && printf '{}' | bash "$EVID/verify-gate.sh" 2>&1 )"
printf '%s' "$OUT" | grep -q "dotnet"; chk "repo C# e reconhecido (era INERTE no global anterior)" $? 0

echo "== 4. FERRAMENTA AUSENTE != FALHA DE CODIGO =="
# Barrar por falta de ferramenta e o falso positivo que faz o usuario desligar o gate.
printf '%s' "$OUT" | grep -q "LACUNA DE COBERTURA"; chk "ferramenta ausente vira LACUNA, nao falha" $? 0
printf '%s' "$OUT" | grep -q "NAO VERIFICADO"; chk "  declara o estado como nao verificado" $? 0

echo "== 5. SEGURANCA: comando do REPO nao executa sem aprovacao de root =="
# Classe CVE-2025-59536. PoC: repo hostil grava marcador.
R3="$TMP/hostil"; mkdir -p "$R3/.claude"; MARK="$TMP/PWNED"
( cd "$R3"; git init -q .; git config user.email t@t; git config user.name t
  printf 'def f():\n    return 1\n' > app.py
  # O fixture DECLARA o contrato de substituicao (`replaces` + `coverage_justification`). Sem
  # ele o gate nem chega a olhar a posse da lista de aprovacao, e o mutante abaixo morreria pelo
  # motivo errado - o teste mediria a ausencia do contrato, e nao a checagem de posse. Deixar a
  # POSSE como unico obstaculo e a condicao para o mutante ter poder de decisao (ADR 0020, R2).
  jq -n --arg m "$MARK" '{exec:{command:"sh",args:["-c",("printf pwned > "+$m)]},
     replaces:["python"], coverage_justification:"fixture de teste"}' > .claude/verify.json
  git add -A; git commit -qm b ) >/dev/null 2>&1
printf '# e\n' >> "$R3/app.py"; git -C "$R3" add -A >/dev/null 2>&1; limpa "$R3"
( cd "$R3" && printf '{}' | bash "$EVID/verify-gate.sh" >/dev/null 2>&1 )
[ ! -f "$MARK" ]; chk "verify-cmd de repo hostil NAO executa" $? 0
HI="$TMP/hi"; mkdir -p "$HI/.claude/logs"
# SHA-256 COMPLETO: o gate compara 64 hex. Truncar aqui desalinharia o hash e o mutante deixaria
# de executar - falso PASS pelo motivo errado, que e exatamente o defeito que o ADR 0020 registra.
CH=$(sha256sum "$R3/.claude/verify.json" | cut -d' ' -f1)
printf '%s\n' "$CH" > "$HI/.claude/verify-cmd-approved"    # criada pelo usuario-agente
limpa "$R3"; rm -f "$HI"/.claude/logs/.verifygate-*
( cd "$R3" && HOME="$HI" CLAUDE_ADAPTERS_DIR="$AD" bash -c "printf '{}' | bash '$EVID/verify-gate.sh'" >/dev/null 2>&1 )
[ ! -f "$MARK" ]; chk "lista de aprovacao NAO-root e ignorada" $? 0
# MUTACAO: prova que o teste acima testa a POSSE, e nao um hash desalinhado
MUT="$TMP/mutante.sh"
python3 - "$EVID/verify-gate.sh" "$MUT" <<'PYEOF'
import sys, re
s = open(sys.argv[1]).read()
s = re.sub(r'OWNER="\$\(stat[^\n]*\)"', 'OWNER="root"', s)
open(sys.argv[2], 'w').write(s)
PYEOF
grep -q 'OWNER="root"' "$MUT"; chk "mutante construido (checagem de posse removida)" $? 0
rm -f "$MARK"; limpa "$R3"; rm -f "$HI"/.claude/logs/.verifygate-*
# CLAUDE_ADAPTERS_DIR e obrigatorio: o mutante vive em /tmp e perde o caminho relativo.
( cd "$R3" && HOME="$HI" CLAUDE_ADAPTERS_DIR="$AD" bash -c "printf '{}' | bash '$MUT'" >/dev/null 2>&1 )
[ -f "$MARK" ]; chk "MUTANTE executa -> o teste acima testa mesmo a garantia" $? 0
rm -f "$MARK"

VAZIO="$TMP/sem-tabela"; mkdir -p "$VAZIO"
R=$( cd "$R3" && CLAUDE_ADAPTERS_DIR="$VAZIO" printf '{}' | CLAUDE_ADAPTERS_DIR="$VAZIO" bash "$EVID/verify-gate.sh" >/dev/null 2>&1; echo $? )
chk "tabela ausente NAO e inercia silenciosa (declara o gate desligado)" "$R" 2

echo "== 6. ANALISADOR roda; suite do projeto NAO roda sozinha =="
R1="$TMP/py"; mkdir -p "$R1/tests"; ( cd "$R1"; git init -q .; git config user.email t@t; git config user.name t
  printf 'def f():\n    return 1\n' > app.py
  printf 'import pathlib\npathlib.Path("%s").write_text("x")\n' "$TMP/PWN_CONFTEST" > tests/conftest.py
  git add -A; git commit -qm b ) >/dev/null 2>&1
printf 'def g():\n    return nao_existe\n' >> "$R1/app.py"; limpa "$R1"
R=$( cd "$R1" && printf '{}' | bash "$EVID/verify-gate.sh" >/dev/null 2>&1; echo $? )
chk "analyzer BARRA com erro de lint (F821)" "$R" 2
[ ! -f "$TMP/PWN_CONFTEST" ]; chk "  conftest.py do repo NAO foi executado" $? 0
printf 'def f():\n    return 1\n' > "$R1/app.py"; limpa "$R1"
R=$( cd "$R1" && printf '{}' | bash "$EVID/verify-gate.sh" >/dev/null 2>&1; echo $? )
chk "analyzer LIBERA com codigo limpo" "$R" 0

echo "== 7. CANAL: todo hook usa canal que o runtime ENTREGA =="
# stderr com exit 0 nao chega ao modelo: dois hooks foram decoracao por versoes inteiras.
python3 - "$CTRL" "$EXEC" "$EVID" <<'PYEOF'
import pathlib, sys
UPS = {'lentes.sh', 'graphify-scout-mode.sh'}
# `activation-log.sh` entra aqui pela MESMA razao que `subagent-probe.sh`: ele existe para
# gravar que um evento ocorreu, e nao tem nada a entregar ao modelo. Mais que isso, ele roda em
# `PreToolUse`, onde stdout VIRA CONTEXTO - escrever ali seria injecao a cada chamada de
# ferramenta. Excecao nomeada, nao silenciada.
SO_LOG = {'subagent-probe.sh', 'activation-log.sh'}
# Excecao NOMEADA, nao silenciada: ds4-notify e um forwarder HTTP para um helper local
# (127.0.0.1:8791). Ele nao dirige informacao ao modelo - nao ha nada para entregar, e por
# desenho ele sempre sai 0 para nunca atrasar nem quebrar a cadeia de hooks.
FORWARDER = {'ds4-notify.sh'}
ruins = []
for d in sys.argv[1:]:
    for f in sorted(pathlib.Path(d).glob('*.sh')):
        s = f.read_text()
        ok = ('exit 2' in s) or ('additionalContext' in s) or ('updatedToolOutput' in s) \
             or (f.name in UPS) or (f.name in SO_LOG) or (f.name in FORWARDER)
        if not ok: ruins.append(f.name)
if ruins: print("NAO ENTREGAM:", " ".join(ruins)); raise SystemExit(1)
raise SystemExit(0)
PYEOF
chk "nenhum hook usa apenas stderr+exit 0" $? 0

echo "== 8. camada 0: garantias agnosticas de stack =="
G="$CTRL/fable-guard.sh"; HL="$TMP/hl"; mkdir -p "$HL/.claude"
R=$(HOME="$HL" bash -c "printf '%s' '{\"tool_name\":\"Agent\",\"tool_input\":{\"model\":\"$MODEL_X\"}}' | bash '$G'" 2>/dev/null; echo $?)
chk "nega modelo restrito sem sentinela" "$R" 2
R=$(HOME="$HL" bash -c "printf '%s' '{\"tool_name\":\"Agent\",\"agent_id\":\"s1\",\"tool_input\":{\"model\":\"$MODEL_X\"}}' | bash '$G'" 2>/dev/null; echo $?)
chk "nega em SUBAGENTE (sem excecao)" "$R" 2
echo $(( $(date +%s) + 3600 )) > "$HL/.claude/$SENT"
R=$(HOME="$HL" bash -c "printf '%s' '{\"tool_name\":\"Agent\",\"tool_input\":{\"model\":\"$MODEL_X\"}}' | bash '$G'" 2>/dev/null; echo $?)
chk "NEGA sentinela nao pertencente a root" "$R" 2
R=$(HOME="$HL" bash -c "printf '%s' '{\"tool_name\":\"Agent\",\"tool_input\":{\"model\":\"opus\"}}' | bash '$G'" 2>/dev/null; echo $?)
chk "PERMITE modelo nao-fable (opus)" "$R" 0
R=$(printf '%s' "$(jq -nc --arg c "grep -i $MODEL_X README.md" '{tool_name:"Bash",tool_input:{command:$c}}')" | bash "$G" 2>/dev/null; echo $?)
chk "NAO bloqueia mencao solta de fable fora de --model (Bash)" "$R" 0
HLB="$TMP/hlb"; mkdir -p "$HLB/.claude"
R=$(HOME="$HLB" bash -c "printf '%s' '$(jq -nc --arg c "claude --model $MODEL_X \"faz algo\"" '{tool_name:"Bash",tool_input:{command:$c}}')' | bash '$G'" 2>/dev/null; echo $?)
chk "BLOQUEIA claude --model fable ancorado em Bash" "$R" 2
HLS="$TMP/hls"; mkdir -p "$HLS/.claude"
R=$(HOME="$HLS" bash -c "printf '%s' '$(jq -nc --arg st "$MODEL_X-especialista" '{tool_name:"Task",tool_input:{subagent_type:$st}}')' | bash '$G'" 2>/dev/null; echo $?)
chk "NEGA por subagent_type contendo fable" "$R" 2
HLW="$TMP/hlw"; mkdir -p "$HLW/.claude"
R=$(HOME="$HLW" bash -c "printf '%s' '$(jq -nc --arg s "model: '$MODEL_X'" '{tool_name:"Workflow",tool_input:{script:$s}}')' | bash '$G'" 2>/dev/null; echo $?)
chk "NEGA Workflow com script model: fable" "$R" 2
# Camada 1 (ADR 0015): escrever o sentinela por Bash e a forma de forjar o proprio
# consentimento. `WCMD`/`WCMD2` montam o redirecionamento por substituicao de variavel para
# nao colocar o padrao literal "> ...allowed"/"> ...approved" no texto do comando desta
# suite - o MESMO hook, quando instalado como guarda real da sessao que roda esta suite,
# inspeciona o texto litral do comando Bash despachado e bloquearia a propria escrita deste
# arquivo de teste se o padrao aparecesse aqui de forma literal.
HLW2="$TMP/hlw2"; mkdir -p "$HLW2/.claude"
WCMD="echo pwn $(printf '\076') \"\$HOME\"/.claude/$SENT"
R=$(HOME="$HLW2" bash -c "printf '%s' '$(jq -nc --arg c "$WCMD" '{tool_name:"Bash",tool_input:{command:$c}}')' | bash '$G'" 2>/dev/null; echo $?)
chk "BLOQUEIA escrita Bash no sentinela .fable-allowed" "$R" 2
R=$(HOME="$HLW2" bash -c "printf '%s' '$(jq -nc --arg c "cat \"\$HOME\"/.claude/$SENT" '{tool_name:"Bash",tool_input:{command:$c}}')' | bash '$G'" 2>/dev/null; echo $?)
chk "PERMITE leitura pura do sentinela via Bash (cat)" "$R" 0
HLV="$TMP/hlv"; mkdir -p "$HLV/.claude"
WCMD2="echo pwn $(printf '\076') \"\$HOME\"/.claude/verify-cmd-approved"
R=$(HOME="$HLV" bash -c "printf '%s' '$(jq -nc --arg c "$WCMD2" '{tool_name:"Bash",tool_input:{command:$c}}')' | bash '$G'" 2>/dev/null; echo $?)
chk "BLOQUEIA escrita Bash em verify-cmd-approved" "$R" 2
# Ataque de symlink (ADR 0012, "Ataque de symlink, tentado e bloqueado"): o sentinela aponta
# para um arquivo de ROOT real (/proc/sys/fs/file-max, leitura publica em qualquer Linux) cujo
# conteudo e um inteiro muito maior que qualquer epoch atual. Com `stat -L` isto autorizaria;
# sem `-L` o dono reportado e o do link, nao do alvo. `/proc/sys/kernel/shmmax` foi descartado
# como fixture: neste kernel seu valor (18446744073692774399) excede o inteiro de 64 bits COM
# SINAL que `[ -gt ]` do bash compara, e a comparacao erra por overflow em vez de autorizar -
# mascarando exatamente o efeito que este caso existe para provar. `file-max` e o proprio limite
# de INT64_MAX (9223372036854775807): grande o bastante para nunca ser confundido com um epoch,
# pequeno o bastante para o bash comparar sem estourar.
if [ -r /proc/sys/fs/file-max ]; then
  HLY="$TMP/hly"; mkdir -p "$HLY/.claude"
  ln -s /proc/sys/fs/file-max "$HLY/.claude/$SENT"
  R=$(HOME="$HLY" bash -c "printf '%s' '{\"tool_name\":\"Agent\",\"tool_input\":{\"model\":\"$MODEL_X\"}}' | bash '$G'" 2>/dev/null; echo $?)
  chk "NEGA symlink do sentinela para arquivo de root com inteiro grande" "$R" 2
else
  echo "  NAO MEDIDO  symlink do sentinela para arquivo de root (/proc/sys/fs/file-max ausente ou ilegivel)"
fi
# Fail-closed sem jq (ADR 0012, item 3): PATH reduzido a um subconjunto sem jq.
BINJ="$TMP/bin-sem-jq"; mkdir -p "$BINJ"
for b in cat grep sed date bash; do p="$(command -v $b 2>/dev/null)" && ln -sf "$p" "$BINJ/$b"; done
R=$(PATH="$BINJ" bash -c "printf '%s' '{\"tool_name\":\"Agent\",\"tool_input\":{\"model\":\"$MODEL_X\"}}' | PATH='$BINJ' bash '$G'" 2>/dev/null; echo $?)
chk "FAIL-CLOSED sem jq disponivel" "$R" 2
# Garantias que so sao observaveis com um sentinela pertencente a ROOT de verdade (permitir a
# sessao principal; e a negacao do subagente PRECISA sobreviver a um sentinela que, sozinho,
# seria aceito - e essa e a garantia central do ADR: "a negacao de subagente sobrevive ao
# consentimento valido"). Sem sudo nao-interativo neste ambiente, a posse de root e obtida por
# um namespace de usuario NAO PRIVILEGIADO (`unshare --map-root-user --user`): o kernel mapeia
# o UID real do processo para 0 dentro do namespace. CORRECAO DE 2026-08-12, medida: o arquivo
# criado ali NAO e relatado como root fora do namespace - `stat -c '%U'` devolve `root` DENTRO
# e o usuario real FORA (medido: dentro=root, fora=ti, uid on-disk=1000). A versao anterior
# deste comentario afirmava o contrario, e quem refatorasse confiando nela quebraria os tres
# casos em silencio. O mecanismo funciona por outra razao: o HOOK e executado DENTRO de um
# namespace com o mesmo mapeamento, entao a consulta de posse que ele faz em producao ocorre no
# mesmo contexto em que o arquivo foi criado.
# LIMITE, declarado: dentro do namespace o agente E root e poderia forjar o sentinela. Logo o
# substituto exercita o DISCRIMINADOR do hook (a checagem `OWNER != root` reprova quando deve),
# nao a PROPRIEDADE DE SEGURANCA (que so root real pode criar o sentinela). E adequado para
# validacao por mutacao, e deve ser lido assim. Se o kernel deste ambiente nao permitir namespaces de
# usuario sem privilegio, as tres garantias abaixo ficam SEM MEDICAO - declarado, e distinto de
# terem passado.
UNSHARE_OK=0
if unshare --map-root-user --user true >/dev/null 2>&1; then UNSHARE_OK=1; fi
if [ "$UNSHARE_OK" = "1" ]; then
  run_ns(){ # $1=HOME  $2=payload json  -> exit code do hook dentro do namespace
    local h="$1" payload="$2" scr="$TMP/ns_$RANDOM.sh"
    { printf 'export HOME=%q\n' "$h"; printf "printf '%%s' %q | bash %q\n" "$payload" "$G"; } > "$scr"
    unshare --map-root-user --user bash "$scr" >/dev/null 2>&1
    echo $?
  }
  mk_sent_ns(){ # $1=caminho do sentinela  $2=conteudo (epoch)
    local scr="$TMP/mk_$RANDOM.sh"
    printf 'printf %%s\\\\n %q > %q\n' "$2" "$1" > "$scr"
    unshare --map-root-user --user bash "$scr" >/dev/null 2>&1
  }
  HR="$TMP/hr"; mkdir -p "$HR/.claude"
  mk_sent_ns "$HR/.claude/$SENT" "$(( $(date +%s) + 3600 ))"
  PAY_R=$(jq -nc --arg m "$MODEL_X" '{tool_name:"Agent",tool_input:{model:$m}}')
  R=$(run_ns "$HR" "$PAY_R")
  chk "PERMITE sessao principal com sentinela de ROOT valido" "$R" 0
  PAY_S=$(jq -nc --arg m "$MODEL_X" '{tool_name:"Agent",agent_id:"s1",tool_input:{model:$m}}')
  R=$(run_ns "$HR" "$PAY_S")
  chk "NEGA subagente MESMO com sentinela de root valido" "$R" 2
  HE="$TMP/he"; mkdir -p "$HE/.claude"
  mk_sent_ns "$HE/.claude/$SENT" "1"
  R=$(run_ns "$HE" "$PAY_R")
  chk "NEGA sentinela de root EXPIRADO" "$R" 2
else
  echo "  NAO MEDIDO  sessao principal com sentinela de root valido (unshare --map-root-user indisponivel)"
  echo "  NAO MEDIDO  subagente NEGADO mesmo com sentinela de root valido (unshare --map-root-user indisponivel)"
  echo "  NAO MEDIDO  sentinela de root EXPIRADO (unshare --map-root-user indisponivel)"
fi
S="$EVID/subagent-contract.sh"
# Os quatro blocos, e nao dois: a mensagem do hook cobra RESULTADO/EVIDENCIA/RISCOS/
# PROPAGACAO desde sempre, mas o codigo so conferia os dois primeiros. A auditoria mediu um
# retorno com metade do contrato saindo 0. Alinhado fortalecendo o mecanismo, nao afrouxando
# a mensagem.
OK='RESULTADO: ok
EVIDENCIA: a.py:1; pytest -> exit 0
RISCOS: nenhum
PROPAGACAO: nenhuma'
R=$(run "$(jq -nc --arg m "$OK" '{hook_event_name:"SubagentStop",agent_type:"refutador",last_assistant_message:$m}')" "$S")
chk "contrato aceita retorno com ancora" "$R" 0
ACC='RESULTADO: ok
EVIDÊNCIA: a.py:1; pytest -> exit 0
RISCOS-PENDÊNCIAS: nenhuma
PROPAGAÇÃO: nenhuma'
R=$(run "$(jq -nc --arg m "$ACC" '{hook_event_name:"SubagentStop",agent_type:"refutador",last_assistant_message:$m}')" "$S")
chk "  aceita EVIDENCIA acentuada (PT-BR reprovava 25%)" "$R" 0
R=$(run "$(jq -nc --arg m "tudo certo, pode seguir" '{hook_event_name:"SubagentStop",agent_type:"refutador",last_assistant_message:$m}')" "$S")
chk "  barra retorno sem evidencia" "$R" 2
# --- ORACULO DA ANCORA: os quatro casos abaixo nasceram de um FALSO BLOQUEIO em producao,
# medido em 2026-08-04 sobre payload real da sonda (SubagentStop de `investigador`).
# O caso NEGATIVO e o mais importante: ate aqui a suite so tinha positivos para a ancora, e
# "barra retorno sem evidencia" reprovava ja no RESULTADO - o poder discriminante da ancora
# nunca fora exercitado. Positivo sem negativo correspondente nao mede oraculo, mede presenca.
REAL='RESULTADO: o arquivo tem 71 linhas.
EVIDENCIA:
- Comando: `wc -l /home/ti/evidence-gate/install/verify.sh` -> saida `71 /home/ti/evidence-gate/install/verify.sh`, exit code `0`. (caminho HISTORICO: o repositorio se chamava evidence-gate quando esta observacao foi gravada; reescrever o caminho falsificaria o registro de uma execucao real)
RISCOS / PENDENCIAS: nenhum.
PROPAGACAO: nenhuma.'
R=$(run "$(jq -nc --arg m "$REAL" '{hook_event_name:"SubagentStop",agent_type:"refutador",last_assistant_message:$m}')" "$S")
chk "  aceita payload REAL de producao (regressao do falso bloqueio)" "$R" 0
# O payload REAL acima tem DUAS ancoras (`wc -l` e `exit code`), entao nao isola qual
# alternativa o sustenta - serve de regressao, nao de alvo de mutacao. Os casos abaixo tem
# ancora UNICA de proposito: sem isso o kill do mutante nao e atribuivel, e mutante morto por
# acidente nao prova que o caso protege aquela garantia (docs/adr/0020, regra de metodo 2).
CRASE='RESULTADO: a suite passou.
EVIDENCIA: a execucao terminou com exit code `0`.
RISCOS: nenhum.
PROPAGACAO: nenhuma.'
R=$(run "$(jq -nc --arg m "$CRASE" '{hook_event_name:"SubagentStop",agent_type:"refutador",last_assistant_message:$m}')" "$S")
chk "  aceita 'exit code' com crase de markdown (ancora unica)" "$R" 0
CMD='RESULTADO: medido.
EVIDENCIA: rodei `xxd -l 16 arquivo.bin` e a saida bate com o esperado.
RISCOS: nenhum.
PROPAGACAO: nenhuma.'
R=$(run "$(jq -nc --arg m "$CMD" '{hook_event_name:"SubagentStop",agent_type:"refutador",last_assistant_message:$m}')" "$S")
chk "  aceita comando FORA da antiga allowlist (xxd)" "$R" 0
NV='RESULTADO: nao consegui executar a suite.
EVIDENCIA: NAO VERIFICADO - pytest ausente neste ambiente.
RISCOS: a alegacao segue sem lastro.
PROPAGACAO: nenhuma.'
R=$(run "$(jq -nc --arg m "$NV" '{hook_event_name:"SubagentStop",agent_type:"refutador",last_assistant_message:$m}')" "$S")
chk "  aceita a saida honesta que a propria mensagem promete (nao verificado)" "$R" 0
VAZ='RESULTADO: revisei a implementacao e esta correta.
EVIDENCIA: li o codigo com atencao e nao encontrei problema.
RISCOS: nenhum.
PROPAGACAO: nenhuma.'
R=$(run "$(jq -nc --arg m "$VAZ" '{hook_event_name:"SubagentStop",agent_type:"refutador",last_assistant_message:$m}')" "$S")
chk "  BARRA blocos completos SEM ancora (discriminador da ancora)" "$R" 2
# --- AUDITORIA 2026-08-04: tres passagens vacuas medidas no oraculo, e meio contrato nao
# conferido. Cada caso abaixo REPROVAVA como 0 antes da correcao.
Q4=$'\nRISCOS: nenhum.\nPROPAGACAO: nenhuma.'
c2(){ run "$(jq -nc --arg m "$1" '{hook_event_name:"SubagentStop",agent_type:"refutador",last_assistant_message:$m}')" "$S"; }
# `\$ ` em qualquer posicao casava moeda: em PT-BR `R$ ` e notacao corrente, nao prompt.
chk "  BARRA cifrao de MOEDA como ancora (R\$ 500 mil)" \
    "$(c2 "RESULTADO: revisei.
EVIDENCIA: o custo do incidente foi de R\$ 500 mil, sem verificacao.$Q4")" 2
# o regex antigo nao tinha polaridade: a frase NEGADA afirmava verificacao e passava.
chk "  BARRA 'nada ficou nao verificado' (afirma o oposto)" \
    "$(c2 "RESULTADO: revisei tudo.
EVIDENCIA: nada ficou nao verificado, revisei por leitura atenta.$Q4")" 2
# o pior: a mensagem de bloqueio continha a frase-chave, entao ecoar o erro era um bypass.
chk "  BARRA o ECO da propria mensagem de bloqueio do hook" \
    "$(c2 "RESULTADO: ok
EVIDENCIA: Se nao conseguiu obter evidencia, diga isso em EVIDENCIA - 'nao verificado' e resposta valida.$Q4")" 2
chk "  ACEITA o token NAO VERIFICADO em caixa alta" \
    "$(c2 "RESULTADO: nao rodei a suite.
EVIDENCIA: NAO VERIFICADO - pytest ausente neste ambiente.$Q4")" 0
# prompt de shell ANCORADO no inicio da linha continua sendo ancora legitima
chk "  ACEITA prompt de shell no inicio da linha" \
    "$(c2 "RESULTADO: ok
EVIDENCIA:
\$ pytest
2 passed$Q4")" 0
# metade do contrato nao e o contrato
chk "  BARRA retorno sem RISCOS" \
    "$(c2 'RESULTADO: ok
EVIDENCIA: a.py:1
PROPAGACAO: nenhuma')" 2
chk "  BARRA retorno sem PROPAGACAO" \
    "$(c2 'RESULTADO: ok
EVIDENCIA: a.py:1
RISCOS: nenhum')" 2
# PORTAO FINAL, 2026-08-04: a correcao do falso aceite `R$ 500 mil` introduziu `[$>]`, e o `>`
# no inicio da linha e BLOCKQUOTE de markdown - a forma corrente de um agente citar prompt,
# doc ou mensagem de erro. Medido: 8 de 15 retornos de prosa plausivel atravessavam, 3 so por
# isso. Terceira vez neste oraculo em que fechar um falso sinal abriu outro.
chk "  BARRA blockquote de markdown como ancora" \
    "$(c2 "RESULTADO: revisei o pedido.
EVIDENCIA: o CLAUDE.md diz:
> revise o modulo antes de seguir
Nao executei nada.$Q4")" 2
O="$EXEC/output-budget.sh"
# acima do limite de 12.000 B, senao o hook sai 0 sem emitir e o teste reprova um hook correto
BIG=$(python3 -c "print('\n'.join(f'linha de saida numero {i} com texto suficiente' for i in range(500)))")
RO=$(jq -nc --arg s "$BIG" '{tool_name:"Bash",tool_response:{stdout:$s,stderr:"",interrupted:false}}' | bash "$O")
printf '%s' "$RO" | jq -e '.hookSpecificOutput.updatedToolOutput | type == "object"' >/dev/null 2>&1
chk "output-budget emite OBJETO (string era rejeitada pelo runtime)" $? 0

echo "== 9. ciclo de vida de skill: criar E depreciar =="
SK="$PWD/execution/skills"
for k in forge depreciar; do
  [ -f "$SK/$k/SKILL.md" ]; chk "skill $k presente" $? 0
  head -1 "$SK/$k/SKILL.md" | grep -q '^---$'; chk "  $k tem frontmatter" $? 0
  grep -q '^description:' "$SK/$k/SKILL.md"; chk "  $k tem description (o gatilho)" $? 0
done
# o ciclo so fecha se um aponta para o outro
grep -q 'depreciar' "$SK/forge/SKILL.md"; chk "forge aponta para o depreciador (ciclo fechado)" $? 0
grep -q 'forge' "$SK/depreciar/SKILL.md"; chk "depreciar aponta para o criador" $? 0
# a armadilha dos dois canais precisa estar documentada, senao a medicao repete o erro
grep -q 'tool_use' "$SK/depreciar/SKILL.md" && grep -q '/nome\|/cmd\|canal' "$SK/depreciar/SKILL.md"
chk "depreciar documenta os DOIS canais de invocacao" $? 0
grep -qE 'ressalva|\(a\)|\(b\)|\(c\)' "$SK/depreciar/SKILL.md"; chk "  documenta as ressalvas antes de arquivar" $? 0
bash -n evidence/telemetry/medir-skills.sh; chk "medir-skills.sh sintaxe" $? 0
# issue #53 (G109): suite dedicada de fixtures para os dois canais de invocacao e o
# denominador de oportunidade. Pendurada aqui (nao no workflow) porque tests/unit/run.sh ja
# esta wired em verify-pr.yml e o workflow esta fora do escopo editavel desta correcao.
bash tests/unit/telemetry-skills.sh >/dev/null 2>&1; chk "telemetry-skills.sh (issue #53)" $? 0

echo
echo "================ PASS=$P  FAIL=$F ================"
# CONTAGEM INVARIANTE - esta era a UNICA suite sem ela, achado do portao final. E logo esta,
# que hospeda os casos do oraculo da ancora: um caso que parasse de rodar aqui sumiria em
# silencio, e foi exatamente assim que a ancora ficou sem discriminador por versoes inteiras.
# 3 dos 66 casos (sentinela de root valido / subagente com sentinela valido / sentinela
# expirado) so rodam quando `unshare --map-root-user --user` esta disponivel (UNSHARE_OK, ==
# 8). Sem isso a contagem fixa quebraria em qualquer ambiente sem namespace de usuario sem
# privilegio - variancia AMBIENTAL declarada, distinta de caso removido em silencio.
echo "== EI. evento ilegivel na entrada padrao NAO pode virar laco =="
# DEFEITO REPORTADO E REPRODUZIDO. `INPUT="$(</dev/stdin)"` depende do CAMINHO /dev/stdin existir.
# Todo `claude -p` lancado fora de uma sessao - processo de desktop, companion, cron - falha com
# `No such device or address`, e sem `set -e` o INPUT fica VAZIO. O guarda anti-loop decide por
# `stop_hook_active` LIDO DESSE INPUT: vazio nunca casa, o gate nunca curto-circuita, reprova e
# re-prompta. Medido pelo operador: 9 re-prompts, 43 mil tokens, resposta VAZIA, 43 segundos.
#
# A escolha nao e simetrica e esta declarada no proprio hook: "portao contornavel fechando stdin"
# contra "portao que gasta a cota em laco e devolve vazio". O segundo e pior e nao para sozinho.
EIR="$TMP/ei"; rm -rf "$EIR"; mkdir -p "$EIR"
( cd "$EIR" && git init -q . && git config user.email t@t && git config user.name t \
  && echo "x = 1" > a.py && git add -A && git commit -qm base ) >/dev/null 2>&1
printf 'def f():\n    return quebrado\n' > "$EIR/b.py"; ( cd "$EIR" && git add -A ) >/dev/null 2>&1

# CONTROLE POSITIVO PRIMEIRO: com stdin legivel o portao AINDA barra codigo roto. Sem isto,
# "nao bloqueou com stdin fechado" nao distingue a correcao de um portao desligado.
rc=$( cd "$EIR" && printf '{}' | bash "$EVID/verify-gate.sh" >/dev/null 2>&1; echo $? )
chk "EI0 CONTROLE: com stdin legivel, codigo roto AINDA barra" "$rc" 2
rc=$( cd "$EIR" && printf '{"stop_hook_active":true}' | bash "$EVID/verify-gate.sh" >/dev/null 2>&1; echo $? )
chk "EI1 anti-loop oficial continua curto-circuitando" "$rc" 0

rc=$( cd "$EIR" && timeout 30 bash "$EVID/verify-gate.sh" 0<&- >/dev/null 2>&1; echo $? )
chk "EI2 stdin FECHADO nao bloqueia (era o laco)" "$rc" 0
rc=$( cd "$EIR" && timeout 30 bash "$EVID/verify-gate.sh" < /dev/null >/dev/null 2>&1; echo $? )
chk "EI3 stdin vazio nao bloqueia" "$rc" 0

# E a lacuna e DECLARADA, nao silenciosa: exit 0 sem dizer nada seria verde vazio.
OUT_EI="$( cd "$EIR" && timeout 30 bash "$EVID/verify-gate.sh" < /dev/null 2>&1 )"
chk "EI4 declara EVENTO ILEGIVEL em vez de calar" \
    "$(printf '%s' "$OUT_EI" | grep -c 'EVENTO ILEGIVEL' | head -1)" 1
chk "EI5 e entrega additionalContext (canal que chega ao modelo)" \
    "$(printf '%s' "$OUT_EI" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null | grep -c 'NADA foi' | head -1)" 1
# LIMITE NO TEMPO: `cat` com descritor fechado nao retorna - medido. Sem `timeout` a correcao
# trocaria laco de re-prompt por processo pendurado, que e pior.
seg0=$(date +%s); ( cd "$EIR" && timeout 30 bash "$EVID/verify-gate.sh" 0<&- >/dev/null 2>&1 ); seg1=$(date +%s)
chk "EI6 e a leitura e LIMITADA no tempo (nao pendura)" "$([ $((seg1-seg0)) -le 15 ] && echo sim || echo nao)" sim

EXPECTED=$((71 + UNSHARE_OK * 3))
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
[ "$F" -eq 0 ] && echo "suite verde" || echo "suite VERMELHA"
exit "$F"
