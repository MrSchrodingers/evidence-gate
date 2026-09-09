#!/usr/bin/env bash
# Suite dos OITO HOOKS QUE NENHUM TESTE EXECUTAVA, mais a precisao de um nono.
#
# ONDA 15. A auditoria externa pediu que a divida de evidencia deixasse de ser um escalar de
# skills e virasse um VETOR POR DIMENSAO, com obrigacao de prova por tipo de capability. Aplicar
# a primeira dimensao - E_M, "faz o que diz fazer?" - ao inventario de hooks produziu um achado
# imediato, e a MEDICAO DELE precisou de tres tentativas, o que faz parte do achado:
#
#   1a  `grep -c "exit 2"` no fonte de cada hook. ERRADA: dois falsos positivos em catorze
#       (self-mod-audit.sh e risk-trigger.sh sao FAIL-OPEN; as ocorrencias estavam em
#       COMENTARIO, "troca exit 2 por exit 0"). Contar padrao no fonte nao observa comportamento.
#   2a  `grep -rlE "bash[^|;&]*<hook>.sh" tests/`. ERRADA por outro lado: as suites atribuem o
#       hook a uma variavel (`GATE="$PWD/evidence/hooks/verify-gate.sh"`) e so depois executam,
#       entao o padrao perdia quase todas as invocacoes reais.
#   3a  ocorrencia do basename em `tests/`, com inspecao linha a linha das poucas dezenas de
#       casos. Esta e a que sustenta o numero abaixo.
#
# RESULTADO (2026-08-19, arvore em d334174):
#   nenhuma mencao em tests/ .............. artifact-discipline, risk-trigger, self-mod-audit,
#                                           poka-yoke-lint
#   mencionados SO como membro de um conjunto de classificacao estatica em tests/unit/run.sh
#   (linhas 131-136), nunca executados .... lentes, graphify-scout-mode, subagent-probe,
#                                           ds4-notify
#   executados por alguma suite ........... verify-gate, subagent-contract, session-integrity,
#                                           read-budget, fable-guard, output-budget
#
# Oito de catorze hooks instalados na configuracao global do usuario - dois deles capazes de
# BLOQUEAR uma escrita - sem execucao em teste algum. Dois sao citados em CLAUDE.md como garantia
# ativa (secao 8, sobre emoji e lexico de bajulacao; secao 7, o poka-yoke de erro obvio). E o
# segundo grupo e o caso mais nitido: `run.sh` CLASSIFICA quatro hooks - sabe o nome deles, sabe
# em que categoria caem - e nunca roda nenhum. E a forma do ADR 0030 mais uma vez: o verificador
# observa a REPRESENTACAO da garantia, nao o fenomeno.
#
# TODA FIXTURE PROIBIDA E MONTADA EM TEMPO DE EXECUCAO. Nao e estilo: e obrigacao medida. O
# proprio artifact-discipline.sh, ativo nesta estacao, RECUSOU DUAS VEZES a criacao deste arquivo
# enquanto ele trazia os literais - primeiro "Bloqueado: emojis nao permitidos", depois
# "Bloqueado: lexico de hype/persona nao deve vazar". O portao e total o bastante para barrar a
# fixture do teste que o testa. A saida correta e sintetizar a fixture, nunca afrouxar o portao -
# e isso explica, sem misterio, por que ninguem havia escrito este teste antes.
#
# ANTIVACUIDADE: cada portao tem controle negativo (entrada limpa -> exit 0). Sem ele, um hook
# degenerado em `exit 2` incondicional passaria em todos os casos de bloqueio.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"

P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

command -v jq >/dev/null 2>&1 || { echo "  DEPENDENCIA AUSENTE: jq. Estado: NAO VERIFICADO - a suite nao rodou."; exit 2; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
# HOME PROPRIO. self-mod-audit.sh e risk-trigger.sh escrevem log e carimbo de throttle sob
# $HOME/.claude/logs. Sem este pino a suite sujaria a configuracao real do operador e, pior, um
# carimbo de throttle preexistente decidiria sozinho o resultado do caso RT2.
export HOME="$T/home"; mkdir -p "$HOME/.claude/logs"

AD="control/hooks/artifact-discipline.sh"
SM="control/hooks/self-mod-audit.sh"
RT="control/hooks/risk-trigger.sh"
PK="execution/hooks/poka-yoke-lint.sh"
FG="control/hooks/fable-guard.sh"

EMOJI="$(printf '\xF0\x9F\x8E\x89')"   # U+1F389, montado por codepoint
LEXICO="voce esta ""absolutamente certo"   # concatenacao: a frase nao existe contigua no fonte
SENTINELA="y.fable-allowed"                # ver FG2

rc_de(){ printf '%s' "$2" | bash "$1" >/dev/null 2>&1; echo "$?"; }

echo "== AD. artifact-discipline.sh - PORTAO (PreToolUse), bloqueia por exit 2 =="
# A afirmacao de CLAUDE.md secao 8 tem DUAS metades com escopos DIFERENTES, e AD2/AD4 sao o par
# que as separa: emoji vale em TODO arquivo (inclusive sob .claude/), lexico so FORA de .claude/.
chk "AD1 emoji fora de .claude bloqueia" \
  "$(rc_de "$AD" "{\"tool_input\":{\"file_path\":\"/x/a.md\",\"content\":\"ola $EMOJI\"}}")" 2
chk "AD2 emoji DENTRO de .claude tambem bloqueia (o escopo e 'todo arquivo')" \
  "$(rc_de "$AD" "{\"tool_input\":{\"file_path\":\"/h/.claude/a.md\",\"content\":\"ola $EMOJI\"}}")" 2
chk "AD3 lexico de bajulacao fora de .claude bloqueia" \
  "$(rc_de "$AD" "{\"tool_input\":{\"file_path\":\"/x/a.md\",\"content\":\"$LEXICO\"}}")" 2
chk "AD4 CONTROLE: o MESMO lexico dentro de .claude NAO bloqueia" \
  "$(rc_de "$AD" "{\"tool_input\":{\"file_path\":\"/h/.claude/a.md\",\"content\":\"$LEXICO\"}}")" 0
chk "AD5 CONTROLE NEGATIVO: conteudo neutro passa" \
  "$(rc_de "$AD" '{"tool_input":{"file_path":"/x/a.md","content":"texto neutro"}}')" 0
chk "AD6 sentinela de autorizacao do usuario nao pode ser escrito pelo modelo" \
  "$(rc_de "$AD" "{\"tool_input\":{\"file_path\":\"/x/$SENTINELA\",\"content\":\"ok\"}}")" 2
chk "AD7 emoji chega tambem por edits[].new_string, nao so por content" \
  "$(rc_de "$AD" "{\"tool_input\":{\"file_path\":\"/x/a.md\",\"edits\":[{\"new_string\":\"$EMOJI\"}]}}")" 2
chk "AD8 input que nao e JSON bloqueia (fail-closed)" "$(rc_de "$AD" 'nao-e-json')" 2

# AD9/AD10 - O DEFEITO QUE ESTE ARQUIVO ACHOU, PINADO. Medido na onda 15: sob `LC_ALL=C` o
# `grep -P` da classe de emoji ERRA ("character code point value in \x{} is too large", rc=2), e
# a linha original era `grep -P ... 2>&1 && { bloqueia; }`. Em `A && B`, rc=2 (erro) e
# indistinguivel de rc=1 (nao achou): o hook saia 0 e o emoji PASSAVA. `scripts/status.sh`
# exporta `LC_ALL=C`, entao a garantia estava desligada em todo processo que herdasse aquele
# ambiente - sem teste que pudesse acusar, porque ate esta onda nao havia teste nenhum.
#
# AD10 e o caso da CLASSE, e vale mais que AD9: com o `grep` inutilizavel, o portao tem de
# BLOQUEAR. Portao que nao consegue checar nao pode responder "limpo".
# `env`, NAO prefixo de atribuicao. `LC_ALL=C rc_de ...` define a variavel para a FUNCAO, e o
# `bash` filho que a funcao lanca so a enxerga se ela ja estiver exportada com esse valor - numa
# estacao com locale UTF-8 o caso passava sem nunca exercitar `LC_ALL=C`, e o mutante MHG17
# sobreviveu apontando isso.
_ad9(){ printf '%s' "$1" | env LC_ALL=C bash "$AD" >/dev/null 2>&1; echo "$?"; }
chk "AD9 emoji bloqueia TAMBEM sob LC_ALL=C (o locale nao desliga a garantia)" \
  "$(_ad9 "{\"tool_input\":{\"file_path\":\"/x/a.md\",\"content\":\"ola $EMOJI\"}}")" 2
_stub="$T/stub"; mkdir -p "$_stub"
printf '#!/bin/sh\nexit 2\n' > "$_stub/grep"; chmod +x "$_stub/grep"
# AD11 - O PAR DE AD9, e sem ele o locale pinado nao e observavel. Com o fail-closed no lugar,
# REMOVER o pino nao afrouxa nada: o grep erra e o portao bloqueia. O efeito real de perder o
# pino e o oposto - passa a bloquear TODO conteudo, inclusive limpo, sob locale C. E uma
# regressao de usabilidade que so um controle negativo sob o MESMO locale pode ver.
chk "AD11 CONTROLE sob LC_ALL=C: conteudo limpo continua passando (o pino nao vira bloqueio geral)" \
  "$(_ad9 '{"tool_input":{"file_path":"/x/a.md","content":"texto neutro"}}')" 0

_ad10(){ printf '%s' "$1" | env "PATH=$_stub:$PATH" bash "$AD" >/dev/null 2>&1; echo "$?"; }
chk "AD10 FAIL-CLOSED: com grep inutilizavel, o portao bloqueia em vez de aprovar" \
  "$(_ad10 '{"tool_input":{"file_path":"/x/a.md","content":"texto neutro"}}')" 2

echo "== PK. poka-yoke-lint.sh - PORTAO (PostToolUse), stop-the-line por exit 2 =="
printf 'def f(:\n' > "$T/quebrado.py"
printf 'def f():\n    return 1\n' > "$T/ok.py"
printf 'nao e codigo\n' > "$T/nota.txt"
chk "PK1 erro de sintaxe em .py para a linha" \
  "$(rc_de "$PK" "{\"tool_input\":{\"file_path\":\"$T/quebrado.py\"}}")" 2
chk "PK2 CONTROLE NEGATIVO: .py valido passa" \
  "$(rc_de "$PK" "{\"tool_input\":{\"file_path\":\"$T/ok.py\"}}")" 0
chk "PK3 extensao sem linter conhecido passa (fail-open declarado)" \
  "$(rc_de "$PK" "{\"tool_input\":{\"file_path\":\"$T/nota.txt\"}}")" 0
chk "PK4 arquivo inexistente passa (fail-open declarado)" \
  "$(rc_de "$PK" '{"tool_input":{"file_path":"/nao/existe.py"}}')" 0

echo "== SM. self-mod-audit.sh - INSTRUMENTO, fail-open: NUNCA bloqueia =="
# O cabecalho do proprio hook declara "ESTE HOOK NAO PREVINE - ELE DETECTA E REGISTRA". SM1
# exerce a trajetoria de DETECCAO - a que emite aviso - e exige exit 0 mesmo assim. E a diferenca
# entre detectar e prevenir, que o hook faz questao de nao confundir e que nada verificava.
LOG="$HOME/.claude/logs/self-mod-audit.log"
: > "$LOG"
SAIDA="$(printf '%s' "{\"tool_name\":\"Write\",\"session_id\":\"abcdef123\",\"tool_input\":{\"file_path\":\"$HOME/.claude/hooks/x.sh\"}}" | bash "$SM" 2>/dev/null)"; RC=$?
chk "SM1 escrita em hook proprio NAO bloqueia (deteccao, nao prevencao)" "$RC" 0
chk "SM1b e emite o aviso pelo canal que chega ao modelo (additionalContext)" \
  "$(printf '%s' "$SAIDA" | jq -r 'try (.hookSpecificOutput.additionalContext | length > 0) catch false')" true
chk "SM1c e deixa trilha duravel no log" "$(grep -c 'x.sh' "$LOG" 2>/dev/null)" 1
: > "$LOG"
SAIDA="$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/tmp/qualquer.md"}}' | bash "$SM" 2>/dev/null)"; RC=$?
chk "SM2 CONTROLE: arquivo fora do escopo de guarda nao gera aviso" "$RC" 0
chk "SM2b nem entrada no log" "$(wc -c < "$LOG" | tr -d ' ')" 0

echo "== RT. risk-trigger.sh - ROTEAMENTO, fail-open: NUNCA bloqueia =="
EV_DATA='{"tool_name":"Write","tool_input":{"file_path":"/x/v.py","content":"Pedido.objects.filter(id=x)"}}'
rm -f "$HOME"/.claude/logs/.risktrig-* 2>/dev/null || true
SAIDA="$(printf '%s' "$EV_DATA" | bash "$RT" 2>/dev/null)"; RC=$?
chk "RT1 superficie de DADO aciona roteamento sem bloquear" "$RC" 0
chk "RT1b e o aviso chega pelo canal do modelo" \
  "$(printf '%s' "$SAIDA" | jq -r 'try (.hookSpecificOutput.additionalContext | contains("revisor-codigo")) catch false')" true
SAIDA="$(printf '%s' "$EV_DATA" | bash "$RT" 2>/dev/null)"
chk "RT2 THROTTLE: a MESMA assinatura repetida em seguida fica silenciosa" \
  "$([ -z "$SAIDA" ] && echo vazio || echo repetiu)" vazio
chk "RT3 CONTROLE NEGATIVO: conteudo sem superficie de risco nao emite nada" \
  "$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/x/v.py","content":"def soma(a,b): return a+b"}}' | bash "$RT" 2>/dev/null | wc -c | tr -d ' ')" 0

echo "== FG. fable-guard.sh - PRECISAO MEDIDA do detector de escrita do sentinela =="
# Achado desta onda, custeado por dois round-trips bloqueados enquanto esta suite era escrita.
# O detector (fable-guard.sh:53) casa um padrao de redirecionamento seguido do token na LINHA
# inteira do comando. Uma linha que traga uma seta ASCII e o token em outro lugar - por exemplo
# um `echo` documentando o proprio caso de teste - satisfaz o padrao sem que haja escrita alguma.
#
# NAO ESTREITADO DE PROPOSITO. Afrouxar um detector fail-closed para conveniencia de quem escreve
# teste troca seguranca por ergonomia: o custo do falso positivo e um round-trip, o do falso
# negativo e o modelo fabricar a propria autorizacao. Os casos abaixo PINAM o comportamento real -
# se alguem estreitar o padrao, FG2 muda e o commit passa a ter de declarar isso.
_cmd(){ printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(jq -Rn --arg c "$1" '$c')"; }
_seta="$(printf '\x2D\x3E')"
chk "FG1 escrita real do sentinela e bloqueada" \
  "$(rc_de "$FG" "$(_cmd "touch ~/.claude/.$SENTINELA")")" 2
chk "FG2 FALSO POSITIVO MEDIDO: seta ASCII na mesma linha do token tambem bloqueia" \
  "$(rc_de "$FG" "$(_cmd "echo 'caso $_seta /x/.$SENTINELA'")")" 2
chk "FG3 CONTROLE: leitura pura do sentinela e permitida" \
  "$(rc_de "$FG" "$(_cmd "cat ~/.claude/.$SENTINELA")")" 0
chk "FG4 CONTROLE NEGATIVO: comando sem mencao alguma passa" \
  "$(rc_de "$FG" "$(_cmd 'ls -la /tmp')")" 0

echo "== LT. lentes.sh - GUIDANCE UNIVERSAL (UserPromptSubmit) =="
# A revisao externa aponta lentes.sh como o melhor candidato a A/B de custo procedural, e o
# argumento depende de uma propriedade que ninguem havia medido: a injecao e INCONDICIONAL. LT2
# e o caso que a estabelece - dois prompts diferentes produzem BYTE A BYTE a mesma saida, logo o
# custo e pago em toda sessao independentemente do que o usuario pediu.
LT_A="$(printf '%s' '{"prompt":"consertar o build"}' | bash execution/hooks/lentes.sh 2>/dev/null)"; LT_RC=$?
LT_B="$(printf '%s' '{"prompt":"qual a capital da Franca"}' | bash execution/hooks/lentes.sh 2>/dev/null)"
chk "LT1 emite o lembrete e nunca bloqueia" "$LT_RC" 0
chk "LT2 injecao INCONDICIONAL: prompts diferentes, saida identica" \
  "$([ "$LT_A" = "$LT_B" ] && [ -n "$LT_A" ] && echo identica || echo divergente)" identica
chk "LT3 o lembrete carrega as quatro regras que declara" \
  "$(printf '%s' "$LT_A" | grep -cE '^[1-4]\.')" 4

echo "== GS. graphify-scout-mode.sh - ROTEAMENTO CONDICIONADO =="
# Discriminador em dois sentidos: sem grafo e sem a skill instalada o hook TEM de calar (senao
# seria guidance universal disfarcada de condicional); com o grafo presente TEM de falar.
GS="execution/hooks/graphify-scout-mode.sh"
# `.git` de proposito: com is_repo=0 o hook calaria pelo segundo motivo, e o caso nao
# distinguiria qual guarda produziu o silencio. Com o diretorio parecendo repositorio, o
# UNICO responsavel pelo silencio e a guarda de topo - que e o que GS1 afirma.
mkdir -p "$T/semgrafo/.git" "$T/comgrafo/.git"
GS_SEM="$(CLAUDE_PROJECT_DIR="$T/semgrafo" PATH=/usr/bin:/bin bash "$GS" </dev/null 2>/dev/null | wc -c | tr -d ' ')"
mkdir -p "$T/comgrafo/graphify-out"
printf '{"built_at_commit":"0000000"}' > "$T/comgrafo/graphify-out/graph.json"
GS_COM="$(CLAUDE_PROJECT_DIR="$T/comgrafo" PATH=/usr/bin:/bin bash "$GS" </dev/null 2>/dev/null)"
# O guarda precisa enxergar EXATAMENTE o ambiente do hook. Na primeira versao ele consultava o
# PATH completo enquanto o hook rodava com PATH restrito, e o caso era pulado como NAO VERIFICADO
# numa estacao onde o ramo de silencio era, na verdade, perfeitamente alcancavel.
if env PATH=/usr/bin:/bin command -v graphify >/dev/null 2>&1 \
   || [ -f "$HOME/.claude/skills/graphify/SKILL.md" ]; then
  echo "  NAO VERIFICADO  GS1: graphify alcancavel no MESMO ambiente do hook - o ramo de"
  echo "                  silencio nao e exercitavel aqui."
else
  chk "GS1 sem grafo e sem a skill, o hook cala" "$GS_SEM" 0
fi
chk "GS2 com graph.json presente, o hook orienta" \
  "$(printf '%s' "$GS_COM" | grep -c 'GRAFO')" 1
chk "GS3 e o aviso vem com o guardrail de que grafo e batedor, nao oraculo" \
  "$(printf '%s' "$GS_COM" | grep -ci 'hipotese')" 1

# GS4/GS5/GS6 - PORTAO TOLLENS_ROUTING_NUDGES (G108/issue #52). O hook e um SEGUNDO canal de
# routing: stdout de UserPromptSubmit chega ao modelo como contexto (docs/method/CONHECIMENTO.md
# secao 4), em paralelo a description da skill. Sem um jeito mecanico de desligar SO este hook, o
# braco `without_skill` de um E_A nunca fica limpo - o nudge continua sugerindo `graphify extract`
# mesmo com a skill fora do prompt. Os tres casos rodam com um stub de `graphify` sintetizado em
# tempo de execucao (nunca instala o binario real), o que torna alcancavel em qualquer estacao o
# ramo `elif` da linha 39 do hook - responsavel por 4647 das 7248 emissoes reais e sem caso de
# teste algum ate esta onda.
mkdir -p "$T/comgraphify/bin"
printf '#!/bin/sh\nexit 0\n' > "$T/comgraphify/bin/graphify"; chmod +x "$T/comgraphify/bin/graphify"
export PATH="$T/comgraphify/bin:$PATH"
mkdir -p "$T/repo_semgrafo/.git" "$T/repo_comgrafo/.git" "$T/repo_comgrafo/graphify-out"
printf '{"built_at_commit":"0000000"}' > "$T/repo_comgrafo/graphify-out/graph.json"

N1=$(TOLLENS_ROUTING_NUDGES=off CLAUDE_PROJECT_DIR="$T/repo_semgrafo" bash "$GS" </dev/null 2>/dev/null | wc -c | tr -d ' ')
N2=$(TOLLENS_ROUTING_NUDGES=off CLAUDE_PROJECT_DIR="$T/repo_comgrafo" bash "$GS" </dev/null 2>/dev/null | wc -c | tr -d ' ')
chk "GS4 com TOLLENS_ROUTING_NUDGES=off o hook nao emite (braco A do E_A)" "$N1+$N2" "0+0"

SAIDA="$(CLAUDE_PROJECT_DIR="$T/repo_semgrafo" bash "$GS" </dev/null 2>/dev/null)"
M1=$(printf '%s' "$SAIDA" | wc -c | tr -d ' ')
M2=$(CLAUDE_PROJECT_DIR="$T/repo_comgrafo" bash "$GS" </dev/null 2>/dev/null | wc -c | tr -d ' ')
# ANTIVACUIDADE: se o portao virasse `exit 0` incondicional, GS4 passaria sozinho e apagaria a
# funcao operacional que o criterio 4 da issue manda preservar. GS5 prova que, SEM a variavel, o
# hook continua falando nas mesmas duas condicoes de GS4.
chk "GS5 sem o switch, o hook continua orientando (o portao nao virou mordaca)" \
  "$([ "$M1" -gt 0 ] && [ "$M2" -gt 0 ] && echo fala || echo mudo)" "fala"

# GS6 fecha o ponto cego que deixou G108 passar: o ramo `elif` (repo sem grafo, graphify
# alcancavel) nao tinha caso algum antes desta onda.
chk "GS6 repo sem grafo mas com graphify alcancavel: o hook FALA (ramo elif)" \
  "$(printf '%s' "$SAIDA" | grep -c 'Repo sem knowledge graph')" 1

echo "== CV. conformidade DECLARACAO-vs-COMPORTAMENTO: routing_covariates vs UserPromptSubmit real =="
# Dois lados independentes, nenhum contendo a string do outro. Lado A e DERIVADO da fonte unica de
# hooks (install/hooks-spec.sh), filtrando os classificados hook_instrument em
# orchestration/registry.json (ds4-notify.sh so registra, nao orienta). Lado B e DECLARADO em
# orchestration/evaluation-protocol.json#routing_covariates. Registrar hook novo em
# UserPromptSubmit sem declara-lo como co-variavel reprova; declarar co-variavel que ninguem
# registra tambem reprova.
CV_OUT="$(python3 - "$T/repo_comgrafo" <<'PY'
import json, os, re, subprocess, sys

repo_dir = sys.argv[1]
spec = subprocess.run(["bash", "install/hooks-spec.sh", "$HOME/.claude/hooks"],
                       capture_output=True, text=True, check=True).stdout
spec_json = json.loads(spec)
ups = spec_json.get("UserPromptSubmit", [])
brutos = set()
for bloco in ups:
    for h in bloco.get("hooks", []):
        m = re.search(r'([^/\s]+\.sh)\s*$', h.get("command", ""))
        if m:
            brutos.add(m.group(1))

registry = json.load(open("orchestration/registry.json", encoding="utf-8"))
caps = registry["capabilities"]
lado_a = {n for n in brutos if caps.get(n, {}).get("kind") != "hook_instrument"}

protocolo = json.load(open("orchestration/evaluation-protocol.json", encoding="utf-8"))
rc = protocolo.get("routing_covariates", {})
entradas = rc.get("hooks", [])
lado_b = {e["hook"] for e in entradas}

print("A1=" + ("ok" if lado_a == lado_b else f"fail derivado={sorted(lado_a)} declarado={sorted(lado_b)}"))

off_env = rc.get("off_switch_env")
a2 = "ok"
for e in entradas:
    if e.get("off_switch_required"):
        hook_path = caps.get(e["hook"], {}).get("source")
        if not hook_path or not off_env:
            a2 = f"fail sem source ou off_switch_env para {e['hook']}"
            break
        env = dict(os.environ)
        env[off_env] = "off"
        env["CLAUDE_PROJECT_DIR"] = repo_dir
        r = subprocess.run(["bash", hook_path], input="", capture_output=True, text=True, env=env)
        if len(r.stdout) != 0:
            a2 = f"fail {e['hook']} com {off_env}=off emitiu {len(r.stdout)} bytes"
            break
print("A2=" + a2)
PY
)"
chk "CV1 conjunto declarado em routing_covariates.hooks == UserPromptSubmit real (exclui hook_instrument)" \
  "$(printf '%s\n' "$CV_OUT" | grep '^A1=')" "A1=ok"
chk "CV2 cada hook com off_switch_required=true silencia sob o off_switch_env declarado no protocolo" \
  "$(printf '%s\n' "$CV_OUT" | grep '^A2=')" "A2=ok"

echo "== SP. subagent-probe.sh - INSTRUMENTO: so registra =="
SPLOG="$HOME/.claude/logs/subagent-probe.jsonl"
rm -f "$SPLOG"
printf '%s' '{"evento":"teste-sp"}' | bash evidence/hooks/subagent-probe.sh >/dev/null 2>&1
chk "SP1 registra o evento recebido" "$(grep -c 'teste-sp' "$SPLOG" 2>/dev/null)" 1
printf '%s' '{"evento":"teste-sp"}' | bash evidence/hooks/subagent-probe.sh >/dev/null 2>&1
chk "SP2 APPEND, nao truncamento: o registro anterior sobrevive" \
  "$(wc -l < "$SPLOG" | tr -d ' ')" 2
chk "SP3 nao emite nada pelo canal do modelo" \
  "$(printf '%s' '{"evento":"x"}' | bash evidence/hooks/subagent-probe.sh 2>/dev/null | wc -c | tr -d ' ')" 0

echo "== DS. ds4-notify.sh - FORWARDER: fail-open sem o helper =="
# EFEITO COLATERAL DECLARADO: este hook faz POST em 127.0.0.1:8791. Se o helper do operador
# estiver de pe, rodar o caso dispararia uma notificacao real na area de trabalho dele. Entao a
# porta e inspecionada ANTES: com helper vivo o caso vira NAO VERIFICADO, nunca um passe silencioso.
if (exec 3<>/dev/tcp/127.0.0.1/8791) 2>/dev/null; then
  exec 3<&- 2>/dev/null || true
  echo "  NAO VERIFICADO  DS1: helper local escutando em 8791 - o caso nao roda para nao"
  echo "                  disparar notificacao real na estacao do operador."
else
  DS_INI="$(date +%s)"
  DS_OUT="$(printf '%s' '{"evento":"teste"}' | bash execution/hooks/ds4-notify.sh 2>/dev/null)"; DS_RC=$?
  DS_DUR=$(( $(date +%s) - DS_INI ))
  chk "DS1 sem o helper de pe, nao bloqueia (fail-open)" "$DS_RC" 0
  chk "DS2 nem emite nada pelo canal do modelo" "$(printf '%s' "$DS_OUT" | wc -c | tr -d ' ')" 0
  chk "DS3 e respeita o proprio timeout de 2s" "$([ "$DS_DUR" -le 4 ] && echo ok || echo lento)" ok
fi

echo "== OB. output-budget.sh - CORTE DE SAIDA (PostToolUse em Bash) =="
# `tests/unit/run.sh` ja executava este hook, mas conferia UMA coisa: que a saida e um objeto
# JSON e nao uma string. O que ele faz - cortar acima do limite e dizer quanto cortou - nunca
# foi exercitado. Os casos abaixo fecham isso, e o par OB1/OB2 e o discriminador: sob o limite
# o hook tem de ficar INERTE, senao "corta o que passa do orcamento" viraria "reescreve tudo".
OB="execution/hooks/output-budget.sh"
OB_PEQ="$(printf 'linha curta\n%.0s' $(seq 1 20))"
OB_GRD="$(python3 -c "print(chr(10).join(f'linha de saida numero {i} com texto suficiente para encher' for i in range(500)))")"
_ob(){ jq -nc --arg s "$1" '{tool_name:"Bash",tool_response:{stdout:$s,stderr:"",interrupted:false}}' | bash "$OB" 2>/dev/null; }
OB_R1="$(_ob "$OB_PEQ")"; OB_RC1=$?
OB_R2="$(_ob "$OB_GRD")"; OB_RC2=$?
chk "OB1 saida sob o limite: hook INERTE, nao emite nada" \
  "$(printf '%s' "$OB_R1" | wc -c | tr -d ' ')" 0
chk "OB1b e nao bloqueia" "$OB_RC1" 0
chk "OB2 saida acima do limite: emite objeto de substituicao" \
  "$(printf '%s' "$OB_R2" | jq -r 'try (.hookSpecificOutput.updatedToolOutput | type) catch "ausente"')" object
chk "OB2b e o corte declara o tamanho original" \
  "$(printf '%s' "$OB_R2" | grep -c 'orcamento de saida')" 1
chk "OB2c e o resultado cabe no orcamento declarado" \
  "$(printf '%s' "$OB_R2" | jq -r '.hookSpecificOutput.updatedToolOutput.stdout | length | if . <= 14000 then "cabe" else "estourou" end')" cabe
chk "OB3 nem no caminho de corte ele bloqueia" "$OB_RC2" 0

# --------------------------------------------------------------------------------------------
echo "== AL. control/hooks/activation-log.sh: o registrador de ativacao =="
# E_M deste instrumento. Ele existe porque os tres registros que alimentam o log de ativacao
# viviam como programas `jq` escritos a mao em /etc/claude-code/managed-settings.json - fora de
# `install/hooks-spec.sh`, fora do manifesto, fora de todo backup. Um `--enforce` os apagou:
# 2 antes, 0 depois, log parado sem uma linha de erro. Sem estes casos, o registrador volta a ser
# um componente que roda e ninguem exercita.
AL="control/hooks/activation-log.sh"
ALOG="$(mktemp "${TMPDIR:-/tmp}/al.XXXXXX")"
al(){ printf '%s' "$1" | TOLLENS_ACTIVATION_LOG="$ALOG" bash "$AL"; }
: > "$ALOG"
AL_SO="$(al '{"hook_event_name":"InstructionsLoaded","file_path":"/etc/claude-code/CLAUDE.md","memory_type":"Managed","session_id":"s1"}')"
chk "AL1 InstructionsLoaded grava arquivo e tipo de memoria" \
    "$(jq -r 'select(.ev=="InstructionsLoaded") | "\(.t)|\(.f)"' "$ALOG")" "Managed|/etc/claude-code/CLAUDE.md"
chk "AL2 e NADA vai para stdout (em PreToolUse, stdout vira contexto)" "$AL_SO" ""
: > "$ALOG"; al '{"hook_event_name":"SubagentStart","agent_type":"refutador","session_id":"s1"}'
chk "AL3 SubagentStart grava o agente" "$(jq -r '.a' "$ALOG")" "refutador"
: > "$ALOG"; al '{"hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"forge"},"session_id":"s1"}'
chk "AL4 PreToolUse grava a skill invocada" "$(jq -r '.k' "$ALOG")" "forge"
# CONTROLE NEGATIVO: um registrador que grava com entrada vazia inventaria evento.
: > "$ALOG"; printf '' | TOLLENS_ACTIVATION_LOG="$ALOG" bash "$AL"
chk "AL5 entrada vazia NAO produz registro" "$(wc -l < "$ALOG" | tr -d ' ')" "0"
# E ele nunca barra a cadeia, nem com log inacessivel: instrumento que bloqueia a ferramenta que
# so deveria observar e pior que a ausencia dele.
TOLLENS_ACTIVATION_LOG=/proc/nao/existe/al.jsonl bash "$AL" <<< '{"hook_event_name":"PreToolUse","session_id":"s1"}' >/dev/null 2>&1
chk "AL6 log inacessivel nao quebra a cadeia (exit 0)" "$?" 0
rm -f "$ALOG"

echo
echo "TOTAL=$((P+F)) PASS=$P FAIL=$F"
[ "$F" -eq 0 ]
