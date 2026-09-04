#!/usr/bin/env bash
# Hook SubagentStop - VALIDA O CONTRATO DE RETORNO do subagente. ADRs 0011, 0014 e 0018.
#
# INVARIANTES:
#  1. A fonte e `last_assistant_message`, com fallback `agent_transcript_path`. NUNCA
#     `transcript_path` - esse e o transcript do PAI, e usa-lo produzia veredito sobre a prosa
#     do orquestrador: falso positivo E falso negativo ao mesmo tempo. Ver ADR 0014.
#  2. O texto e NORMALIZADO antes de casar: os agentes escrevem em PT-BR e emitem EVIDENCIA
#     acentuada. Casar so o ASCII reprovava 25% dos retornos reais. Ver ADR 0018.
#  3. A filtragem por tipo de agente e feita AQUI, nao so pelo matcher: a maioria dos eventos
#     SubagentStop vem com agent_type vazio e e outra classe de evento.
# Anti-loop: respeita stop_hook_active. FAIL-OPEN.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT="$(cat)"
[ "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0

AT="$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null || true)"
# AUTORIDADE AMPLA (2026-09-04). Ate esta data o `case` era uma ALLOWLIST dos dez agentes
# definidos por este repositorio, e todo o resto caia no `*) exit 0`. MEDIDO no log de ativacao
# permanente (/var/log/tollens-activation.jsonl, 491 lancamentos de subagente registrados):
# 170 deles, 34%, ficavam FORA do contrato. A lista do que escapava e o problema inteiro -
# `general-purpose` 66, `workflow-subagent` 54, `fork` 19, `code-review` 17, `Explore` 5,
# `Plan` 1, mais quatro tipos `code-*`. Ou seja: o agente de proposito geral, o agente de
# WORKFLOW e o fork do proprio modelo entregavam relatorio sem nenhuma obrigacao de evidencia,
# enquanto o CLAUDE.md anuncia o contrato como universal. A allowlist tornava a regra falsa
# para um terco dos casos, e falsa exatamente nos casos que o operador nao consegue prever -
# um agente novo, de plugin ou de workflow, nasce FORA da regra por padrao.
#
# A forma correta e a inversa: cobrir TUDO e declarar a excecao. O `case` abaixo passou a ser
# uma DENYLIST curta e justificada, e qualquer tipo nao listado nela E cobrado.
case "$AT" in
  # EXCECOES DECLARADAS. Nao sao "agentes menos importantes": sao agentes que nao emitem
  # afirmacao tecnica sobre um artefato, e para os quais exigir ancora de evidencia produziria
  # ruido sem aumentar rigor. Qualquer acrescimo a esta lista precisa da razao junto.
  statusline-setup|output-style-setup) exit 0 ;;   # configuram a UI; nao afirmam nada sobre codigo
  "") exit 0 ;;                                     # evento sem tipo: outra classe de evento (ver cabecalho)
  # TUDO O MAIS E COBRADO - inclusive general-purpose, workflow-subagent, fork, Explore, Plan,
  # code-review e qualquer agente de plugin que ainda nao exista.
  *) ;;
  # implementador e tdd ENTRAM (4a arguicao, achado 8): o CLAUDE.md anuncia o contrato como
  # universal e eles ficavam de fora - o agente que ESCREVE CODIGO era o unico nao cobrado
  # por evidencia. Exige o matcher correspondente no settings.json e no hooks.json.
  #
  # NOTA HISTORICA SUPERADA (2a arguicao): registrava-se aqui que implementador|tdd eram
  # deadcode por constarem neste `case` sem constar no matcher. Isso deixou de ser verdade na
  # 4a arguicao, que acrescentou os dois ao matcher. O comentario permaneceu contradizendo o
  # codigo por duas versoes - prosa obsoleta apresentada como estado atual e exatamente a
  # classe de defeito que este repositorio existe para impedir. Verificado em 2026-08-04:
  # `jq '.hooks.SubagentStop[].matcher' ~/.claude/settings.json` contem ambos.
esac

# 1. campo dedicado com o texto final completo.
LAST="$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null || true)"

# 2. fallback: transcript DO SUBAGENTE (nunca o do pai).
if [ -z "$LAST" ]; then
  AP="$(printf '%s' "$INPUT" | jq -r '.agent_transcript_path // empty' 2>/dev/null || true)"
  if [ -n "$AP" ] && [ -f "$AP" ]; then
    LAST="$(tail -n 80 "$AP" 2>/dev/null | jq -r '
      select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' 2>/dev/null | tail -n 200)"
  fi
fi
[ -n "$LAST" ] || exit 0   # sem fonte confiavel: calar, nunca chutar.

# ===================== NORMALIZACAO DE ACENTO (ADR 0018) =====================
# DEFEITO GRAVE CORRIGIDO: o padrao era ASCII (`EVIDENCIA`), mas o CLAUDE.md manda os agentes
# raciocinarem em PT-BR e eles emitem `EVIDENCIA` COM acento. Medido sobre os eventos reais do
# log da sonda: 4 de 16 retornos nomeados (25%) foram REPROVADOS so por isso - entre eles uma
# revisao de 36.188 bytes com os quatro blocos presentes. O mecanismo criado para punir
# afirmacao sem lastro estava acusando de falta de lastro justamente quem o forneceu.
#
# O defeito e ANTERIOR a correcao da fonte do transcript (ADR 0014); era mascarado por ela.
# Ler o arquivo errado dava 0 blocos sempre, entao o acento nunca chegava a importar.
# Corrigir a fonte ATIVOU este.
#
# A correcao NAO e adicionar a variante acentuada de uma palavra - isso repetiria o erro na
# proxima (PROPAGACAO, RISCOS...). Normaliza-se o texto ANTES de casar, e todos os padroes
# passam a ser ASCII por construcao.
#
# SEGUNDA CORRECAO (2026-08-03): `y/.../.../` opera sobre CARACTERES, e sob LC_ALL=C o sed
# processa BYTES - a transliteracao multi-byte quebra e o texto sai intacto. Resultado: o hook
# voltava a reprovar retorno acentuado, agora dependendo do locale do ambiente. Reproduzido:
# `LC_ALL=C bash tests/unit/run.sh` reprovava 2 casos que passavam sem a variavel.
# Substituicao LITERAL por byte e insensivel a locale: cada `s///` casa uma sequencia fixa.
NORM="$(printf '%s' "$LAST" | sed \
  -e 's/Á/A/g' -e 's/À/A/g' -e 's/Â/A/g' -e 's/Ã/A/g' -e 's/Ä/A/g' \
  -e 's/É/E/g' -e 's/È/E/g' -e 's/Ê/E/g' -e 's/Ë/E/g' \
  -e 's/Í/I/g' -e 's/Ì/I/g' -e 's/Î/I/g' -e 's/Ï/I/g' \
  -e 's/Ó/O/g' -e 's/Ò/O/g' -e 's/Ô/O/g' -e 's/Õ/O/g' -e 's/Ö/O/g' \
  -e 's/Ú/U/g' -e 's/Ù/U/g' -e 's/Û/U/g' -e 's/Ü/U/g' -e 's/Ç/C/g' -e 's/Ñ/N/g' \
  -e 's/á/a/g' -e 's/à/a/g' -e 's/â/a/g' -e 's/ã/a/g' -e 's/ä/a/g' \
  -e 's/é/e/g' -e 's/è/e/g' -e 's/ê/e/g' -e 's/ë/e/g' \
  -e 's/í/i/g' -e 's/ì/i/g' -e 's/î/i/g' -e 's/ï/i/g' \
  -e 's/ó/o/g' -e 's/ò/o/g' -e 's/ô/o/g' -e 's/õ/o/g' -e 's/ö/o/g' \
  -e 's/ú/u/g' -e 's/ù/u/g' -e 's/û/u/g' -e 's/ü/u/g' -e 's/ç/c/g' -e 's/ñ/n/g')"
# =============================================================================

# ===================== ORACULO DA ANCORA (defeito de producao, 2026-08-04) ===================
# Medido sobre payload REAL capturado pela sonda (`~/.claude/logs/subagent-probe.jsonl`, evento
# SubagentStop de `investigador`): um retorno com TRES comandos, suas saidas coladas e
# `exit code `0`` foi BLOQUEADO. Duas causas independentes, ambas da mesma classe - o oraculo
# reconhecia evidencia por CONVENCAO LEXICAL, nao por estrutura:
#
#  (a) `exit[[:space:]]*(code)?[[:space:]]*[=:]?[[:space:]]*[0-9]` nao atravessa a crase de
#      markdown. Byte a byte: `exit code \x60 0` - o 0x60 entre "code " e "0" reprovava.
#      Escrever ``exit code `0` `` e a forma NORMAL de um agente formatar, nao uma excecao.
#  (b) a lista de comandos era FECHADA (git|npm|pytest|ruff|...). `wc`, `xxd`, `stat`, `make`,
#      `kubectl` e todo o resto caiam fora. Enumerar comandos nao e conjunto decidivel: a
#      allowlist so podia crescer por remendo, uma reincidencia por vez.
#
# A correcao e da CLASSE, nao da instancia (nao foi "adicionar wc a lista"): pontuacao de
# markdown tolerada, e FORMA de comando (token em posicao de comando seguido de flag) em vez
# de NOME de comando. Cada alternativa tem caso-alvo em `tests/unit/run.sh` e mutante
# correspondente em `tests/mutation/contrato.sh`.
#
# CORRECAO DE UMA AFIRMACAO FALSA (revisao independente, 2026-08-04): este comentario dizia
# "validado contra corpus de 15 casos - 9 positivos, 6 negativos". Esse corpus existiu no
# rascunho de quem escreveu a correcao e NUNCA ENTROU EM `tests/`. Afirmar cobertura que o
# repositorio nao tem e a classe de defeito que este projeto existe para impedir, aqui dentro
# do proprio mecanismo. A contagem real e a que `scripts/status.sh` publica por execucao.
#
# ================== LIMITE EPISTEMICO, e ele NAO e patchavel por regex ==================
# Este oraculo distingue TEXTO QUE TEM FORMA DE EVIDENCIA de texto que nao tem. Ele NAO
# distingue REPORTAR evidencia de MENCIONAR algo com a mesma forma. Dois contraexemplos
# medidos, que continuam atravessando e estao declarados em `evidence/claims/C-009.yaml`:
#
#   "a doc em exemplo.com:8080 descreve o comportamento"   -> casa `arquivo.ext:linha`
#   "pela leitura, o hook faz exit 2 quando falta bloco"   -> casa `exit <digito>`
#
# `host.tld:porta` e `arquivo.ext:linha` sao lexicalmente identicos; citar um exit code e
# reportar um exit code tambem. Nenhuma expressao regular separa os dois casos, e mais uma
# rodada de regex trocaria este falso aceite por outro falso bloqueio - foi assim que o
# defeito de producao de 2026-08-04 nasceu.
#
# O que o mecanismo entrega, entao, e ESTREITO e vale escrito: ele torna CARO devolver prosa
# sem nenhuma forma de evidencia, e torna a ausencia observavel. Ele nao verifica que a
# evidencia foi produzida, nem que e verdadeira. Quem cobra isso e o orquestrador que le o
# retorno. Fabricacao deliberada esta fora do alcance deste hook, por construcao.
# ========================================================================================
ANCORA='[A-Za-z0-9_./-]+\.[A-Za-z0-9]+:[0-9]+'
ANCORA="$ANCORA"'|exit[^0-9A-Za-z]{0,4}(code|status)?[^0-9A-Za-z]{0,4}[0-9]'
ANCORA="$ANCORA"'|(^|[`$(>|])[[:space:]]*[a-z][a-z0-9_.+-]*([[:space:]]+[a-z0-9_.+-]+){0,3}[[:space:]]+-{1,2}[A-Za-z0-9]'
# PROMPT DE SHELL, ANCORADO NO INICIO DA LINHA. Antes era `\$ ` em qualquer posicao, e isso
# tornava a alternativa VACUA em PT-BR: `R$ 500 mil` e `US$ 2 bilhoes` sao notacao corrente e
# satisfaziam a ancora sozinhas. Medido na auditoria de 2026-08-04: um retorno cuja unica
# "evidencia" era "o custo do incidente foi de R$ 500 mil" atravessava o portao.
# Prompt de shell de verdade abre a linha; cifrao de moeda vem no meio dela.
#
# O `>` FOI REMOVIDO (portao final, 2026-08-04). Ele entrou junto do cifrao sem mencao no
# comentario, e abriu uma classe que a declaracao de limite nao cobria: `> ` no inicio da linha
# e BLOCKQUOTE de markdown, a forma corrente de um agente citar prompt, doc ou mensagem de
# erro. Medido: 8 de 15 retornos de prosa plausivel atravessavam, 3 deles so pelo blockquote.
# Terceira rodada de regex neste oraculo, terceira vez em que fechar um falso sinal abriu
# outro - o registro dessa recorrencia esta no ADR 0023.
ANCORA="$ANCORA"'|^[[:space:]]*\$[[:space:]]'

# SAIDA HONESTA. `NAO VERIFICADO` e resposta valida - o CLAUDE.md declara isso na secao 4 e a
# mensagem de bloqueio deste proprio hook a promete por escrito. Ela era INEXEQUIVEL: medido,
# um retorno declarando nao-verificacao recebia exit 2 IDENTICO ao de prosa vazia. Consequencia
# estrutural: o unico caminho estavel para atravessar o portao era APRESENTAR uma ancora, isto
# e, o mecanismo criado para punir alegacao sem lastro pressionava na direcao de fabricar lastro.
#
# O TOKEN E MAIUSCULO, E ISSO NAO E ESTILO. A primeira versao casava
# `(nao|not)[[:space:]]+(verificad[oa]|verified)` sem distincao de caixa nem de polaridade, e a
# auditoria de 2026-08-04 mediu duas passagens vacuas:
#   "Nada ficou nao verificado, revisei por leitura"  -> AFIRMA verificacao e atravessava;
#   ecoar a mensagem de bloqueio deste hook           -> atravessava, e o hook ENSINA a frase
#                                                        ao bloquear.
# A segunda e a pior: um portao que publica a propria chave na mensagem de erro.
# Regex nao decide polaridade em linguagem natural. O que decide e um TOKEN deliberado, que nao
# aparece em prosa corrida: `NAO VERIFICADO` em caixa alta, o mesmo vocabulario que
# `verify-gate.sh` ja usa para estado. Declarar em caixa alta e barato de escrever e caro de
# escrever por acidente - e o orquestrador le o rotulo e cobra.
# NORM removeu os acentos preservando a caixa, entao `NAO` cobre `NAO` e `NÃO`.
NAO_VERIFICADO='NAO[[:space:]]+VERIFICADO'
# =============================================================================================

# OS QUATRO BLOCOS, e nao dois. A mensagem de bloqueio deste hook cobra RESULTADO, EVIDENCIA,
# RISCOS e PROPAGACAO "nesta ordem" desde que existe, mas o codigo so verificava os dois
# primeiros - a auditoria de 2026-08-04 mediu um retorno com apenas RESULTADO e EVIDENCIA
# saindo 0. Mensagem que cobra mais do que o mecanismo confere e a mesma classe de defeito que
# este repositorio persegue, agravada por estar no PROPRIO texto que ensina o contrato.
# Alinhado no sentido de fortalecer o mecanismo, nao de enfraquecer a mensagem: o contrato de
# quatro blocos e o que o CLAUDE.md publica, e RISCOS e PROPAGACAO sao justamente onde cabe o
# que o agente NAO conseguiu fechar. A ORDEM segue nao verificada - o texto promete "nesta
# ordem" e isso continua sendo mais forte do que o codigo cobra. Lacuna declarada, nao coberta.
MISS=""
grep -qiE '^[[:space:]]*[-*#]*[[:space:]]*RESULTADO' <<<"$NORM" || MISS="$MISS RESULTADO"

if grep -qiE '^[[:space:]]*[-*#]*[[:space:]]*EVIDENCIA' <<<"$NORM"; then
  # `NAO VERIFICADO` e alternativa a ancora, nao dispensa do bloco EVIDENCIA: a declaracao tem
  # de estar escrita, e nao apenas o bloco existir vazio.
  grep -qE "$ANCORA" <<<"$NORM" || grep -qE "$NAO_VERIFICADO" <<<"$NORM" \
    || MISS="$MISS ANCORA-DE-EVIDENCIA"
else
  MISS="$MISS EVIDENCIA"
fi

# RISCOS aceita sufixo (`RISCOS-PENDENCIAS`, `RISCOS / PENDENCIAS`) porque e como os agentes
# escrevem de fato - medido nos retornos reais capturados pela sonda.
grep -qiE '^[[:space:]]*[-*#]*[[:space:]]*RISCOS' <<<"$NORM"    || MISS="$MISS RISCOS"
grep -qiE '^[[:space:]]*[-*#]*[[:space:]]*PROPAGACAO' <<<"$NORM" || MISS="$MISS PROPAGACAO"

# REGISTRO INFORMAL (secao 9 do kernel, estendida a conversa em 2026-09-04). MOTIVO CONCRETO:
# o operador recebeu de um agente desta maquina um retorno que o tratava por "mano". O
# diagnostico deste harness e lido como evidencia, e evidencia em registro casual convida a ser
# lida como opiniao.
#
# LISTA DELIBERADAMENTE MINIMA E ANCORADA COMO VOCATIVO. Falso positivo aqui e caro - mais caro
# do que a literatura de analise estatica supoe, porque o consumidor e um agente: medido em
# arXiv:2310.12397 (controle "evil"), o modelo aplica a "correcao" pedida em 94% dos casos MESMO
# QUANDO A ACUSACAO E FALSA. Um detector de estilo agressivo faria agentes reescreverem relatorio
# correto. Por isso ficam de fora palavras com uso tecnico legitimo ("cara", "top", "massa") e
# so entram as inequivocamente coloquiais, cercadas por pontuacao ou limite de palavra.
# A3 DO REFUTADOR, e o erro foi de CLASSE, nao de item: eu testei a classe SUBSTRING
# (`humano`, `romano`, `germano` nao disparam) e nao testei a HOMOGRAFA - palavra inteira com uso
# formal legitimo. Medido: "valeu a pena" (preterito de VALER) e "beleza" como substantivo comum
# reprovavam um relatorio tecnico correto. Isso e o dano que este bloco diz evitar: acusacao falsa
# contra um consumidor que, por arxiv-2310.12397 (controle "evil"), obedece acusacao falsa na
# MESMA taxa da verdadeira.
# `valeu` e `beleza` SAIRAM da lista solta e so contam como VOCATIVO - seguidos de pontuacao
# terminal ou de fim de linha, que e como o coloquialismo aparece ("valeu!", "beleza?"). "valeu a
# pena" e "a beleza da solucao" deixam de casar.
INFORMAL='(^|[[:space:],;(])(mano|manos|blz|tipo assim|ta ligado|tao ligados)([[:space:],.!?:;)]|$)'
INFORMAL="$INFORMAL"'|(^|[[:space:],;(])(valeu|beleza)[[:space:]]*[!?.]|(^|[[:space:],;(])(valeu|beleza)[[:space:]]*$'
if grep -qiE "$INFORMAL" <<<"$NORM"; then
  MISS="$MISS REGISTRO-INFORMAL"
fi

[ -n "$MISS" ] || exit 0

{
  echo "CONTRATO DE RETORNO INCOMPLETO (agente: $AT). Faltou:$MISS"
  echo "Feche com os quatro blocos, nesta ordem:"
  echo "  RESULTADO   - o que foi feito ou encontrado."
  echo "  EVIDENCIA   - arquivo:linha, comando executado e sua saida. Sem ancora verificavel,"
  echo "                a conclusao e auto-avaliacao, e auto-avaliacao nao e sinal."
  echo "  RISCOS      - o que ficou em aberto ou precisa de decisao."
  echo "  PROPAGACAO  - pontos do grafo de dependencias afetados (ou 'nenhum', justificado)."
  case "$MISS" in *REGISTRO-INFORMAL*)
    echo "REGISTRO-INFORMAL: o retorno usa vocativo coloquial. Secao 9 do kernel: registro"
    echo "  tecnico e formal, sem giria e sem apelido para o operador - no artefato E na"
    echo "  conversa. Reescreva a frase; o conteudo tecnico nao precisa mudar." ;;
  esac
  echo "Se nao conseguiu obter evidencia, escreva em EVIDENCIA o token NAO VERIFICADO, em"
  echo "caixa alta, com o motivo ao lado. E resposta valida; afirmacao sem lastro nao e."
  echo "A caixa alta e exigida de proposito: em prosa corrida a frase aparece por acidente e"
  echo "ate negada ('nada ficou nao verificado'), e o portao passava a aceitar o oposto do que"
  echo "queria aceitar."
} >&2
exit 2
