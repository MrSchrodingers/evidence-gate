#!/usr/bin/env bash
# MUTACAO DO EXECUTOR NO RAMO `scope: delta`.
#
# Esta suite existe porque o corpus AFIRMAVA que "os tres defeitos reintroduzidos como mutantes NO
# EXECUTOR morrem", e a afirmacao nao era reproduzivel: os mutantes foram rodados a mao e nunca
# versionados. O `refutador` mediu e achou TRES SOBREVIVENTES entre oito. E a mesma falta que a
# entrada vizinha do corpus condena na onda anterior - a acusacao foi corrigida um nivel abaixo e
# reproduzida um nivel acima.
#
# O alvo aqui e o SHELL entre o analisador e o nucleo. Foi ali que moraram TODOS os defeitos de
# aprovacao silenciosa desta onda: o nucleo tinha 35 casos e 99,2% de cobertura, e o executor,
# nenhum.
set -uo pipefail
. "$(dirname "$0")/../lib/lock.sh"
cd "$(dirname "$0")/../.." || exit 1
. "$(dirname "$0")/../lib/arena.sh"
ALVO="evidence/hooks/verify-gate.sh"
SUITE="tests/unit/delta-e2e.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/mut-vg.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
cp "$ALVO" "$TMP/orig.sh"
P=0; F=0

echo "== baseline: a suite ponta a ponta precisa passar ANTES de mutar =="
if bash "$SUITE" >/dev/null 2>&1; then echo "  PASS  baseline verde"; P=$((P+1))
else echo "  FAIL  baseline VERMELHO - todo veredito abaixo seria sem sentido"; exit 1; fi

# EXECUCAO FRACIONADA (`MVG_ONLY`). MOTIVO MEDIDO: esta suite executa a suite de regressao
# INTEIRA uma vez por mutante, mais o baseline - 15 execucoes que exercitam o portao mais de mil
# vezes. Numa maquina sob contencao de memoria ela foi morta por SIGKILL quatro vezes seguidas,
# sempre antes de concluir, e SIGKILL nao dispara o `trap` que restaura o arquivo mutado.
#
# `MVG_ONLY="MVG11 MVG12"` executa apenas os mutantes listados. ISTO NAO SUBSTITUI A EXECUCAO
# COMPLETA e o rodape declara a execucao como PARCIAL: a garantia deste arnes e que TODO defeito
# reintroduzido morre, e um subconjunto nao demonstra isso. Serve para (a) fechar o trabalho em
# blocos quando a maquina nao comporta a execucao inteira, e (b) reexecutar um mutante especifico
# apos reancora-lo, sem pagar os outros treze.
mutante(){  # $1=id  $2=defeito reintroduzido  $3=de  $4=para
  case "${MVG_ONLY:-}" in
    "") ;;                                  # sem filtro: executa todos
    *"$1"*) ;;                              # id listado: executa
    *) return 0 ;;                          # fora do filtro: pula sem contar
  esac
  cp "$TMP/orig.sh" "$ALVO"
  # SUBSTITUICAO POR PYTHON, nao por `sed`: os alvos contem `|`, `$`, `\` e aspas, e escapar isso
  # num `sed -i` produziu TRES mutantes que nao aplicaram - e mutante que nao aplica e teste
  # invalido, nao mutante morto. O mesmo motivo pelo qual `install/hooks-spec.sh` trocou `sed` por
  # `jq --arg` depois de uma auditoria.
  python3 - "$ALVO" "$3" "$4" <<'PYEOF' || { cp "$TMP/orig.sh" "$ALVO"; echo "  FAIL  $1 NAO FOI APLICADO - o padrao nao casa. Mutante nao aplicado e teste invalido."; F=$((F+1)); return; }
import sys, pathlib
alvo, de, para = sys.argv[1], sys.argv[2], sys.argv[3]
p = pathlib.Path(alvo); t = p.read_text(encoding="utf-8")
if t.count(de) != 1:
    sys.exit(1)
p.write_text(t.replace(de, para), encoding="utf-8")
PYEOF
  if ! bash -n "$ALVO" 2>/dev/null; then
    cp "$TMP/orig.sh" "$ALVO"; echo "  FAIL  $1 gerou sintaxe invalida - mutante inutil"; F=$((F+1)); return
  fi
  bash "$SUITE" >/dev/null 2>&1; rc=$?
  cp "$TMP/orig.sh" "$ALVO"
  if [ "$rc" -ne 0 ]; then echo "  PASS  $1 morto ($2)"; P=$((P+1))
  else echo "  FAIL  $1 SOBREVIVEU - a suite aprova o executor com: $2"; F=$((F+1)); fi
}

echo "== mutacao: cada defeito de aprovacao silenciosa, reintroduzido =="
mutante MVG1 "A1: catraca semeada do estado ATUAL, anistiando a quebra do turno" \
  'SEEDREF="$DIFFBASE"' 'SEEDREF=HEAD'
mutante MVG2 "A2: analisador morto vira zero diagnosticos, isto e, aprovacao" \
  "if ! printf '%s' \"\$RAW\" | jq -e 'type == \"array\"' >/dev/null 2>&1; then" 'if false; then'
mutante MVG3 "C1: raiz aninhada aceita entrada chamada .git, sem repositorio" \
  'git rev-parse --resolve-git-dir "$_d/.git" >/dev/null 2>&1' 'test -e "$_d/.git"'
# R1: sem este mutante, a exigencia de historia na raiz aninhada seria codigo sem prova de que
# discrimina. MVG3 continua vivo porque ataca o predicado ANTERIOR (`--resolve-git-dir`), e com
# `.git` invalido o `rev-parse --verify HEAD` SOBE para o repositorio pai e responde sucesso -
# que e justamente a razao de os dois predicados existirem, um guardando o outro.
mutante MVG7 "R1: raiz aninhada sem NENHUM commit conta como checkout" \
  'git -C "$_d" rev-parse --verify -q HEAD >/dev/null 2>&1' 'true'
# MVG4 REANCORADO na onda 25e. A ancora anterior era o pipeline literal
# `ls-files --others ... | sed 's|^|UNTRACKED |'`, que deixou de existir quando C2 trocou a fonte
# para `ls-files -z` e C1/C2 puseram a particao em lote. O mutante NAO FOI APLICADO na primeira
# execucao apos aquelas mudancas, e mutante nao aplicado e TESTE INVALIDO, nao mutante morto - o
# arnes acusou corretamente. A intencao permanece a mesma: zerar a lista de nao rastreados e
# verificar que a suite reprova.
mutante MVG4 "B1: arquivo nao rastreado sai dos hunks" \
  '_UL="$(git -c core.quotePath=false ls-files -z --others --exclude-standard 2>/dev/null \' \
  '_UL="$(true 2>/dev/null \'
mutante MVG5 "F4: deteccao de extensao volta ao pipe que toma SIGPIPE" \
  'if case "$_NL$CHANGED$_NL" in *"${ext}${_NL}"*) true ;; *) false ;; esac; then' \
  'if printf "%s\n" "$CHANGED" | grep -q -- "${ext}\$"; then'
mutante MVG6 "upstream aceito por ECO, sem validar o objeto" \
  'if [ -z "$UPSTREAM" ] || ! git -C "$ROOT" rev-parse --verify -q "${UPSTREAM}^{commit}" >/dev/null 2>&1; then' \
  'if false; then'
# G74 (A5 do revisor, ver tests/unit/delta-e2e.sh DE11): o parser de hunks decodificava UTF-8
# ESTRITO e morria no primeiro byte que nao fosse - o diff carrega conteudo de arquivo, entao
# fonte em latin-1 no mesmo diff derrubava o parser inteiro. `surrogateescape` preserva o byte
# cru sem decodificar (nome de arquivo e marcador de hunk sao ASCII). Medido: DE11 mata este
# mutante pela CAUSA (o F401 nomeado no veredito, e a ausencia da mensagem de mapa ilegivel),
# nao so pelo exit code - e o proprio caso documenta uma versao anterior que era tautologica
# medindo so RC==2.
mutante MVG8 "G74: parser de hunks volta a decodificar UTF-8 estrito e morre em byte nao-UTF-8" \
  'for l in sys.stdin.buffer.read().decode("utf-8", "surrogateescape").split("\n"):' \
  'for l in sys.stdin:'
# G77 (A5 do revisor, ver tests/unit/delta-e2e.sh DE12): a partir do limiar de tentativas
# identicas o portao passa a NOMEAR a repeticao ao operador, sem mudar o veredito. Subir o
# limiar para 999 faz a mensagem nunca aparecer dentro de qualquer numero de paradas que um
# teste pratico reproduz.
mutante MVG9 "G77: limiar de repeticao nunca dispara, o portao nunca nomeia o laco" \
  'if [ "$TENTATIVAS_IDENTICAS" -ge 3 ]; then' \
  'if [ "$TENTATIVAS_IDENTICAS" -ge 999 ]; then'
# C3 (A5 do revisor): a guarda que declara LACUNA quando `mktemp`/a escrita dos temporarios
# falha e o pior defeito da serie - sem ela, `HUNKF`/`RAWF` vazios caem no default mais
# PERMISSIVO do nucleo (mapa de hunks vazio), e uma falha TRANSITORIA de TMPDIR vira um `pass`
# PERMANENTE gravado no ledger para aquele estado de arvore.
# O MUTANTE PRECISA SER O REVERT EXATO, nao um substituto mais cru. Uma primeira tentativa
# trocou o if inteiro por `if false; then` - isso tambem apaga os DOIS `printf` que a propria
# condicao executa (o corpo do if nunca roda quando a condicao e `false`), entao o mutante
# morria SEMPRE, mesmo no caminho feliz (RAWF ficava vazio para TODO turno, nao so quando
# mktemp falha) - GATILHO ERRADO: DE1-DE12 discriminavam "nunca escreve nada", nao
# especificamente C3. `de`/`para` abaixo restauram o codigo ANTERIOR a correcao byte a byte
# (confirmado contra `git diff HEAD -- evidence/hooks/verify-gate.sh`): os dois `printf`
# continuam INCONDICIONAIS - o caminho feliz fica identico -, so a deteccao de falha some.
# MEDIDO com este mutante preciso: tests/unit/delta-e2e.sh sai 48/48 verde (EXIT=0) - SOBREVIVE.
# Nenhum caso ali forca `mktemp`/escrita a falhar (TMPDIR nao gravavel). Isto e o GAP real que
# A5 pediu para reportar, nao para forjar - tests/unit/delta-e2e.sh pertence a outro agente
# nesta tarefa e esta fora do escopo de edicao aqui.
mutante MVG10 "C3: guarda de mktemp/escrita falha removida - falha transitoria vira aprovacao" \
  'if [ -z "$HUNKF" ] || [ -z "$RAWF" ] \
       || ! printf '"'"'%s'"'"' "$HUNKS" > "$HUNKF" 2>/dev/null \
       || ! printf '"'"'%s'"'"' "$RAW" > "$RAWF" 2>/dev/null; then
      LACUNAS="$LACUNAS
  - $ID: nao foi possivel gravar os arquivos temporarios do analisador (TMPDIR=${TMPDIR:-/tmp} sem espaco ou sem permissao). NADA foi julgado neste turno - e nada foi gravado no ledger como aprovado."
      [ -n "${HUNKF:-}" ] && rm -f "$HUNKF"
      [ -n "${RAWF:-}" ] && rm -f "$RAWF"
      [ "$TMPERR" != /dev/null ] && rm -f "$TMPERR"
      continue
    fi
' \
  'printf '"'"'%s'"'"' "$HUNKS" > "$HUNKF" 2>/dev/null
    printf '"'"'%s'"'"' "$RAW" > "$RAWF" 2>/dev/null
'

# --- ONDA 25e: os quatro defeitos de aprovacao silenciosa achados pela revisao externa ---
# Cada um destes foi REPRODUZIDO ponta a ponta contra o hook em vigor antes de ser corrigido.
# Sem mutante, a correcao pode ser desfeita e a suite continua verde - foi assim que G74 voltou
# como G74b e G78. O mutante e o que torna a correcao IRREVERSIVEL EM SILENCIO.

mutante MVG11 "C1/C4: guarda de concordancia inerte - diff vazio volta a valer como arvore intocada" \
  'for cam, add in esperados.items():' 'for cam, add in {}.items():'

mutante MVG12 "C2: CHANGED sem -z - caminho citado pelo git deixa o adaptador fora" \
  '_gitz ls-files -z --others --exclude-standard' '_gitz ls-files --others --exclude-standard'

mutante MVG13 "C2: lista de untracked sem -z - a chave do mapa de hunks nunca casa o diagnostico" \
  'git -c core.quotePath=false ls-files -z --others --exclude-standard' 'git -c core.quotePath=false ls-files --others --exclude-standard'

mutante MVG14 "C3: contador da escotilha sem deduplicacao - forja por duplicacao volta a comprar exit 0" \
  '    | sort -u \' '    | cat \'

echo

# MVG15 fecha o ramo que o refutador achou aberto: sem ele, a cegueira a renomeacao pode voltar
# e a suite continua verde. `pend` e o unico estado que distingue o tripleto do `-z`.
mutante MVG15 "A1: renomeacao volta a ser invisivel para a guarda de concordancia" \
  'if c[2]=="": pend=2; pend_add=c[0].strip()' \
  'if c[2]=="": pass'

if [ -n "${MVG_ONLY:-}" ]; then
  echo "EXECUCAO PARCIAL (MVG_ONLY='$MVG_ONLY') - NAO substitui a execucao completa."
  echo "MUTANTES=$((P-1+F)) MORTOS=$((P-1)) SOBREVIVENTES=$F"
  [ "$F" -eq 0 ] && { echo "parcial verde: os mutantes SELECIONADOS morreram"; exit 0; }
  echo "parcial VERMELHA"; exit 1
fi
echo "MUTANTES=$((P-1+F)) MORTOS=$((P-1)) SOBREVIVENTES=$F"
if [ "$F" -eq 0 ]; then echo "mutacao do executor verde: todo defeito reintroduzido morreu"; exit 0; fi
echo "mutacao VERMELHA: ha defeito do executor que a suite nao protege"; exit 1
