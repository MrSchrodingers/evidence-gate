#!/usr/bin/env bash
# VALIDACAO POR MUTACAO - guarda dura do modelo Fable (control/hooks/fable-guard.sh, ADR 0012).
#
# Por que existe: fable-guard.sh e hook PreToolUse com matcher Agent|Task|Bash|Workflow que
# DECIDE AUTORIZACAO (nega o modelo Fable sem confirmacao explicita do usuario, e confere posse
# de root sobre um sentinela). Um levantamento de necessidade de teste mediu que este arquivo,
# apesar de 148 linhas de superficie de autorizacao, nao tinha UM UNICO mutante. Regra de metodo
# 2 (docs/adr/0020): toda garantia de seguranca e validada por MUTACAO - remove-se a garantia e
# EXIGE-SE que a regressao reprove. Um teste que sobrevive ao mutante nao testa a garantia.
#
# ORDEM DO TRABALHO (declarada, nao encenada): antes deste arquivo existir,
# `tests/unit/gate-e-guardas.sh` (entao chamado `tests/unit/run.sh`, renomeado na issue #55/
# G111 quando `run.sh` virou o agregador de suites) secao 8 cobria fable-guard.sh com TRES
# asercoes - nega sem sentinela, nega em subagente (mas
# SEM sentinela, o que nao discrimina a negacao INCONDICIONAL do consentimento valido - ver nota
# no proprio arquivo de regressao), e nega sentinela nao-root. Faltava regressao ANTES de faltar
# mutante: a secao 8 foi estendida com 13 casos novos (permite opus; ancora Bash reduz falso
# positivo; subagent_type; Workflow; as duas protecoes de escrita por Bash - ADR 0015/0016; o
# ataque de symlink do proprio ADR 0012; fail-closed sem jq; e os TRES casos que so sao
# observaveis com um sentinela genuinamente de root) antes de este arnes ser escrito.
#
# POSSE DE ROOT SEM SUDO NAO-INTERATIVO: tres garantias (permitir com sentinela de root valido;
# negar subagente MESMO com esse sentinela valido; negar sentinela de root expirado) so sao
# observaveis com um arquivo que `stat -c '%U'` relate como pertencente a "root". Este ambiente
# nao tem sudo nao-interativo. A REGRESSAO (tests/unit/gate-e-guardas.sh) resolve isso com
# `unshare --map-root-user --user`: um namespace de usuario NAO PRIVILEGIADO em que o kernel
# mapeia o UID real do processo para 0 - um arquivo criado ali E relatado como "root" por
# `stat -c '%U'`, inclusive por processos FORA daquele namespace especifico (mesmo UID real,
# mesmo mapeamento). Nao e mock da ferramenta: e o mesmo mecanismo de UID que o hook consulta em
# producao, apenas com uma raiz de confianca mais fraca (o namespace, nao o sistema inteiro). Se
# o kernel deste ambiente nao permitir isso, a regressao declara "NAO MEDIDO" para os tres casos
# em vez de fingir PASS - e os tres mutantes correspondentes (MFB1, MFB6, MFB8) tambem ficam sem
# poder de decisao aqui; ver o resumo final deste arquivo.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
# ARENA: muta uma COPIA da arvore, nunca a arvore candidata. Ver tests/lib/arena.sh para os
# seis incidentes medidos que motivaram isto.
. "$(dirname "$0")/../lib/arena.sh"
ORIG="control/hooks/fable-guard.sh"
REG="tests/unit/gate-e-guardas.sh"
TMP="$(mktemp -d)"; trap 'cp -f "$TMP/orig.sh" "$ORIG" 2>/dev/null || true; rm -rf "$TMP"' EXIT
cp -f "$ORIG" "$TMP/orig.sh"
P=0; F=0; BASELINE=nao; EXPECTED_MUTANTS=12
# SOBREVIVEU E NAO MEDIDO SAO OPOSTOS, E ESTE ARNES OS CONFUNDIA. Medido em 2026-08-12 (CI run
# 31607753782, reproduzido local com `unshare` neutralizado): sem user namespace nao
# privilegiado, MFB1/MFB6/MFB8 saiam "SOBREVIVEU - a suite passa sem a garantia", acusando o
# teste de nao proteger nada quando a verdade e que o experimento nao pode ser feito. O
# ubuntu-24.04 restringe userns por AppArmor, entao isto NAO e hipotetico - foi o que deixou a
# CI vermelha. Mesma classe ja registrada em tests/mutation/install.sh.
# Contrato: com a capacidade, 12 mutantes, exit 0/1. Sem ela, 9 medidos, 3 declarados NAO
# MEDIDO por nome, exit 2 (NAO VERIFICADO) - nunca 0, nunca 1. Garantia de autorizacao nao
# interrogada nao e verde, e tambem nao e acusacao contra o teste.
if unshare --map-root-user --user true 2>/dev/null; then USERNS=sim; else USERNS=nao; fi
DEPENDEM_DE_ROOT="MFB1 MFB6 MFB8"
NAO_MEDIDOS=0

echo "== baseline: a suite precisa passar ANTES de qualquer mutacao =="
if bash "$REG" >/dev/null 2>&1; then echo "  PASS  baseline verde"; BASELINE=ok
else echo "  FAIL  baseline VERMELHO - mutacao nao tem significado; abortando"; exit 1; fi
echo

# SUBSTITUICAO LITERAL, nao sed: os alvos tem aspas, colchetes e cifrao, e escrever isso como
# padrao de sed produziria regex ilegivel e fragil (mesma disciplina de conformidade.sh e
# capabilities.sh). `troca` falha alto se a ancora nao existir com contagem exatamente 1, para
# nunca contar um mutante nao aplicado como mutante morto.
troca(){ # $1=trecho original  $2=substituto
python3 - "$ORIG" "$1" "$2" <<'PY'
import sys
alvo, velho, novo = sys.argv[1:4]
s = open(alvo, encoding="utf-8").read()
if s.count(velho) != 1:
    sys.exit("ANCORA NAO CASOU (%d ocorrencias)" % s.count(velho))
open(alvo, "w", encoding="utf-8").write(s.replace(velho, novo))
PY
}

mutante(){ # $1=nome  $2=descricao  $3=caso-alvo que DEVE reprovar  $4..=comando (troca ...)
  local nome="$1" desc="$2" alvo="$3"; shift 3
  if [ "$USERNS" = nao ]; then
    case " $DEPENDEM_DE_ROOT " in *" $nome "*)
      echo "  NAO MEDIDO  $nome: exige user namespace nao privilegiado; a garantia \"$desc\" NAO foi interrogada - isto NAO e sobrevivencia"
      NAO_MEDIDOS=$((NAO_MEDIDOS+1)); return ;;
    esac
  fi
  cp -f "$TMP/orig.sh" "$ORIG"
  "$@"
  if cmp -s "$TMP/orig.sh" "$ORIG"; then
    echo "  FAIL  $nome NAO FOI APLICADO - o padrao nao casa com o codigo atual."
    F=$((F+1)); cp -f "$TMP/orig.sh" "$ORIG"; return
  fi
  if ! bash -n "$ORIG" 2>/dev/null; then
    echo "  FAIL  $nome nao compila apos a mutacao"; F=$((F+1)); cp -f "$TMP/orig.sh" "$ORIG"; return
  fi
  local out rc
  out="$(bash "$REG" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  FAIL  $nome SOBREVIVEU - a suite passa sem a garantia: $desc"; F=$((F+1))
  elif printf '%s' "$out" | grep -qF "FAIL  $alvo"; then
    echo "  PASS  $nome morto pelo caso certo ($alvo)"; P=$((P+1))
  else
    echo "  FAIL  $nome: suite reprovou, mas NAO em '$alvo' - kill nao atribuivel"; F=$((F+1))
  fi
  cp -f "$TMP/orig.sh" "$ORIG"
}

echo "== mutacao: cada garantia removida DEVE quebrar a regressao =="

# MFB1 - GARANTIA CENTRAL (ADR 0012, "Decisao" item 1): subagente nega INCONDICIONALMENTE, e a
# negacao sobrevive a um sentinela que, sozinho, seria aceito. O caso "nega em SUBAGENTE (sem
# excecao)" ja existente em tests/unit/gate-e-guardas.sh NAO discrimina esta mutacao (sem
# sentinela, ambos os caminhos - checagem de agent_id e fallback de "sem sentinela" - chegam no
# mesmo exit 2); so o caso novo com sentinela de root VALIDO isola a garantia.
mutante MFB1 "subagente nega mesmo com sentinela de root valido" \
  "NEGA subagente MESMO com sentinela de root valido" \
  troca '[ -n "$AGENT_ID" ]' '[ -n "" ]'

# MFB2 - GARANTIA CENTRAL (ADR 0012, "Limite honesto": o campo .model do Agent/Task e um dos
# DOIS caminhos deterministicos declarados como "a garantia"). Sem esta linha, um Agent/Task com
# model=fable passa INTEIRAMENTE sem checagem - RELEVANT nunca vira 1.
mutante MFB2 "campo .model do Agent/Task e examinado" \
  "nega modelo restrito sem sentinela" \
  troca "printf '%s' \"\$INPUT\" | jq -er '.tool_input.model // empty' 2>/dev/null | grep -qi 'fable' && RELEVANT=1" \
        "printf '%s' \"\$INPUT\" | jq -er '.tool_input.model // empty' 2>/dev/null | grep -qi 'fable' && RELEVANT=0"

# MFB3 - campo .tool_input.subagent_type do Agent/Task tambem seleciona o modelo Fable (um
# subagente nomeado com "fable" sem o campo .model). Sem esta linha, essa forma de invocacao
# passa sem checagem.
mutante MFB3 "campo .tool_input.subagent_type do Agent/Task e examinado" \
  "NEGA por subagent_type contendo fable" \
  troca "printf '%s' \"\$INPUT\" | jq -er '.tool_input.subagent_type // empty' 2>/dev/null | grep -qi 'fable' && RELEVANT=1" \
        "printf '%s' \"\$INPUT\" | jq -er '.tool_input.subagent_type // empty' 2>/dev/null | grep -qi 'fable' && RELEVANT=0"

# MFB4 - deteccao do tool_name Workflow (script/name com "model: 'fable'"). Sem isto um Workflow
# que dispara Fable passa sem checagem - terceira via de invocacao coberta pelo hook.
mutante MFB4 "Workflow com model: fable no script e examinado" \
  "NEGA Workflow com script model: fable" \
  troca '| grep -qiE "model:[[:space:]]*['"'"'\"]?fable" && RELEVANT=1' \
        '| grep -qiE "model:[[:space:]]*['"'"'\"]?fable" && RELEVANT=0'

# MFB5 - negacao PADRAO quando o sentinela nao existe (fail-closed de politica: ausencia de
# consentimento nunca autoriza).
mutante MFB5 "sem sentinela, a sessao principal nega por padrao" \
  "nega modelo restrito sem sentinela" \
  troca $'fi\n\ncat >&2 <<'"'"'MSG'"'"'' $'fi\n\nexit 0\ncat >&2 <<'"'"'MSG'"'"''

# MFB6 - GARANTIA CENTRAL (ADR 0012, "Decisao" item 2): sentinela de ROOT com epoch futuro
# PERMITE a sessao principal. Sem este ramo de aceite, o mecanismo de consentimento nunca
# autoriza nada - o requisito de "confirmacao explicita do usuario" ficaria sem via de exercicio.
mutante MFB6 "sentinela de root valido permite a sessao principal" \
  "PERMITE sessao principal com sentinela de ROOT valido" \
  troca 'AUTORIZADO pelo usuario (sentinela de root) ate $(date -d "@$EXP" 2>/dev/null || echo "epoch $EXP")." >&2
    exit 0
  fi' \
        'AUTORIZADO pelo usuario (sentinela de root) ate $(date -d "@$EXP" 2>/dev/null || echo "epoch $EXP")." >&2
    exit 2
  fi'

# MFB7 - posse de ROOT e EXIGIDA. Um sentinela que o proprio agente pode criar (dono != root)
# nao serve como consentimento do usuario - e a correcao central do ADR 0015 (consentimento
# forjavel).
mutante MFB7 "sentinela precisa pertencer a root, nao so existir" \
  "NEGA sentinela nao pertencente a root" \
  troca '[ "$OWNER" != "root" ]' '[ "$OWNER" = "impossivel-de-bater-isto-nao-e-root" ]'

# MFB8 - sentinela de root EXPIRADO nao autoriza. Sem a comparacao de epoch, qualquer sentinela
# de root - mesmo um criado uma unica vez e nunca renovado - autorizaria para sempre.
mutante MFB8 "sentinela de root expirado nao autoriza" \
  "NEGA sentinela de root EXPIRADO" \
  troca '[ "$EXP" -gt "$NOW" ]' '[ "$EXP" -ge 0 ]'

# MFB9 - ATAQUE DE SYMLINK (ADR 0012, "Ataque de symlink, tentado e bloqueado", tentado e
# bloqueado durante a verificacao original): `stat` SEM `-L` reporta o dono do link, nao do
# alvo. Com `-L` (ou `readlink -f`), um symlink para um arquivo de root com inteiro grande (ex.:
# /proc/sys/fs/file-max) autorizaria - a propria correcao que o comentario do codigo pede para
# NAO desfazer "por engano".
mutante MFB9 "posse do sentinela e a do LINK, nao do alvo (symlink)" \
  "NEGA symlink do sentinela para arquivo de root com inteiro grande" \
  troca "stat -c '%U' \"\$SENT\"" "stat -Lc '%U' \"\$SENT\""

# MFB10 - FAIL-CLOSED sem jq (ADR 0012, "Decisao" item 3: "Guarda de politica nunca falha
# liberando"). Sem este bloco, um ambiente sem jq faz TOOL/AGENT_ID ficarem vazios, RELEVANT
# nunca vira 1, e a mencao a Fable passa livre - fail-OPEN exatamente onde a politica promete
# fail-CLOSED.
mutante MFB10 "sem jq, a politica falha FECHADA (nega), nao aberta" \
  "FAIL-CLOSED sem jq disponivel" \
  troca 'if ! command -v jq >/dev/null 2>&1; then' 'if false; then'

# MFB11 - CAMADA 1 (ADR 0015): protege o proprio sentinela contra escrita via Bash. Sem isto, o
# modelo fabrica o proprio consentimento numa linha de Bash - o defeito ORIGINAL que deu origem a
# esta camada (repro registrado no cabecalho do arquivo: exit 0 numa escrita direta).
mutante MFB11 "escrita do sentinela por Bash e bloqueada" \
  "BLOQUEIA escrita Bash no sentinela .fable-allowed" \
  troca 'if printf '"'"'%s'"'"' "$CMD" | grep -qE '"'"'>[[:space:]]*[^|;&]*\.fable-allowed' \
        'if false && printf '"'"'%s'"'"' "$CMD" | grep -qE '"'"'>[[:space:]]*[^|;&]*\.fable-allowed'

# MFB12 - protege verify-cmd-approved (a lista de aprovacao do verify-cmd) contra escrita via
# Bash, pela MESMA mecanica e razao do sentinela (ADR 0016) - classe CVE-2025-59536: um repo
# hostil que conseguisse escrever essa lista aprovaria a propria execucao.
mutante MFB12 "escrita de verify-cmd-approved por Bash e bloqueada" \
  "BLOQUEIA escrita Bash em verify-cmd-approved" \
  troca 'if printf '"'"'%s'"'"' "$_C" | grep -qE '"'"'>[[:space:]]*[^|;&]*verify-cmd-approved' \
        'if false && printf '"'"'%s'"'"' "$_C" | grep -qE '"'"'>[[:space:]]*[^|;&]*verify-cmd-approved'

cp -f "$TMP/orig.sh" "$ORIG"
echo
printf 'baseline=%s  mutantes_esperados=%s  mortos=%s  invalidos_ou_sobreviventes=%s  nao_medidos=%s\n' \
       "$BASELINE" "$EXPECTED_MUTANTS" "$P" "$F" "$NAO_MEDIDOS"
echo "================================================================"
if [ "$F" -ne 0 ]; then echo "mutacao VERMELHA: ha garantia que a suite nao protege"; exit 1; fi
if [ "$NAO_MEDIDOS" -ne 0 ]; then
  echo "mutacao NAO VERIFICADA: $P mortos, $NAO_MEDIDOS nao medidos por falta de user namespace"
  echo "  habilite com: sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0"
  echo "  NAO diga verde nem vermelho - a garantia de posse de root nao foi interrogada."; exit 2; fi
if [ "$P" -ne "$EXPECTED_MUTANTS" ]; then
  echo "mutacao VERMELHA: $P mortos para $EXPECTED_MUTANTS mutantes - algum nao executou"; exit 1; fi
echo "mutacao verde: os $EXPECTED_MUTANTS mutantes morreram no caso-alvo correspondente"; exit 0
