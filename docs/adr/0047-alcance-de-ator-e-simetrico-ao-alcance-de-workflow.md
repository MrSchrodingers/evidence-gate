# ADR 0047 - Alcance de ator e simetrico ao alcance de workflow

Data: 2026-09-09
Estado: aceito
Sucede: ADR 0043 (risco declarado nao e risco selecionado)

## O defeito, medido (G110, issue #54)

ADR 0043 fechou cinco garantias da funcao `R: RiskClass -> WorkflowId`, verificadas por
`orchestration/render.py:_check_risk_policy`: totalidade do dominio, ausencia de classe orfa,
resolucao do workflow, ausencia declarada (nao inferida), e ALCANCE - todo workflow em disco e
alcancavel por alguma classe ou esta declarado em `not_risk_selected`. A garantia (v) para no ID
DE WORKFLOW. Um nivel abaixo - ALCANCE DE ATOR, isto e, a extensao composta
`RiskClass -> WorkflowId -> Actor` via `orchestration/schedule/<workflow>.json` - nao tinha
oraculo algum.

A consequencia medida, nao teorica: `control/hooks/risk-trigger.sh`, hook `PostToolUse` que roda
em toda escrita de toda sessao deste repositorio, prescreve dois agentes que a funcao canonica
nao alcanca por classe de risco alguma - `revisor-frontend` (categoria UI, por extensao de
arquivo) e `analista-otimalidade` (categoria ALGO, por custo assintotico detectado no conteudo do
diff) - e nenhum verificador acusava.

`execution/hooks/lentes.sh` (o lembrete `UserPromptSubmit` que cita "revisor-codigo" e
"refutador" na linha 3) estava compativel com a funcao canonica POR COINCIDENCIA, nao por
construcao: o proprio ADR 0043 registra a Opcao B (um workflow `normal-change` sem `review`/
`refute`, fiel a linha `normal` do kernel) como alternativa legitima e nao escolhida. Se essa
opcao fosse adotada depois, `lentes.sh` passaria a contradizer o kernel de fato, e nenhum oraculo
o acusaria - o mesmo modo de falha que este ADR fecha, um nivel abaixo.

## Errata sobre a premissa da issue #54

A issue #54 nomeava `execution/hooks/lentes.sh` como a superficie suspeita. A medicao (probe
executado sobre a arvore real, reproduzido em `tests/unit/guidance-projection.sh`) refuta essa
premissa: `lentes.sh` prescreve `revisor-codigo` e `refutador`, ambos alcancaveis pela funcao
canonica (atores de `standard-change` e `high-risk-change`). O defeito real estava em
`control/hooks/risk-trigger.sh`, que prescreve `revisor-frontend` e `analista-otimalidade` - dois
agentes fora do alcance.

Isto e registrado aqui como ERRATA, no mesmo padrao ja usado por este repositorio para admitir
diagnostico errado em vez de silencia-lo (ver a errata de 2026-08-12 em `execution/hooks/
lentes.sh:16-18`, que corrigiu uma citacao numerica falsa da mesma forma). O criterio nao e
proteger a hipotese inicial da issue; e corrigir a propriedade que ela realmente aponta -
"superficie de guidance que contradiz o kernel sem que nada acuse" - contra a superficie CERTA.

## A decisao

`orchestration/risk-policy.json` ganha o campo `not_risk_selected_actors`, simetrico a
`not_risk_selected` (que ja existia para workflow), declarando com motivo escrito os agentes que
sao acionados por SUPERFICIE TOCADA ou por TIPO da tarefa, nunca por classe de risco:

- `revisor-frontend` - acionado por extensao de arquivo de UI (`.vue`, `.tsx`, `.jsx`, `.svelte`,
  `.astro`, `.html`, `.css`, `.scss`, `.sass`, `.less`, `.styl`), categoria UI de
  `risk-trigger.sh`.
- `analista-otimalidade` - acionado por custo assintotico observado no CONTEUDO do diff (laco
  aninhado ou busca linear dentro de laco), categoria ALGO de `risk-trigger.sh`.
- `analista-fluxos` - acionado pelo TIPO da tarefa (fila, pipeline, automacao, funil,
  dimensionamento de workers/conexoes, diagnostico de latencia/throughput -
  `execution/agents/analista-fluxos.md`); nao e ator de no algum em
  `orchestration/schedule/*.json` hoje, e nenhum hook o prescreve nas entradas sinteticas
  exercitadas, mas fica declarado pela mesma doutrina de ausencia explicita.

`tests/unit/guidance-projection.sh` e o oraculo que verifica a propriedade simetrica: para toda
superficie de guidance REGISTRADA (hook listado na saida de `install/hooks-spec.sh`), todo papel
que ela emite em execucao tem de ser alcancavel pela funcao canonica ou estar declarado em
`not_risk_selected_actors`. Nenhum vocabulario e hard-coded no teste - classes vem do kernel,
funcao classe->ator vem de `risk-policy.json` + `orchestration/schedule/*.json`, nomes de agente
vem das chaves de `orchestration/registry.json`, e a lista de superficies vem da SAIDA de
`install/hooks-spec.sh`. O que cada superficie prescreve e OBSERVADO por execucao com entradas
sinteticas, nunca lido do codigo-fonte dela - um teste que procurasse a string `'refutador'` em
`lentes.sh` cometeria o mesmo erro que `methodology.py:31` cometia antes desta onda (verificar o
literal em vez da propriedade).

`tests/mutation/guidance-projection.sh` prova que o oraculo reprovaria amanha, nao so hoje: um
mutante por garantia (guarda de vacuidade do dominio; vocabulario de agente lido do registry, nao
hard-coded; `not_risk_selected_actors` somado ao alcance, nao ignorado).

## Por que o oraculo vive em `tests/`, nao em `orchestration/render.py`

Duas razoes, ambas medidas antes da escolha:

1. Estender `_check_risk_policy` para ler `orchestration/schedule/*.json` quebraria
   `tests/unit/risk-policy.sh`: o helper `escreve()` das fixtures (C0/C1) cria
   `execution/config`, `orchestration/workflows`, `.claude`, `.codex`, `registry.json`,
   `CLAUDE.md` e `AGENTS.md`, mas NAO cria `orchestration/schedule/`. As fixtures reprovariam com
   `FileNotFoundError`, e tolerar o diretorio ausente seria fail-open no lado errado.
2. `orchestration/render.py` esta em `evidence/cobertura.sh` como executavel EXCLUIDO da CAMADA
   1 (piso de cobertura de decisao), com motivo escrito: "nao avaliado nesta tarefa". Um
   executavel NOVO em `orchestration/` (RAIZES da camada 3 inclui `orchestration`) acionaria essa
   camada, exigindo piso medido ou entrada em EXCLUSOES com motivo - custo fora do escopo de
   G110. `tests/` nao esta em RAIZES: o oraculo fica la com custo zero nessa camada.

## Limite declarado

Este ADR nao move `analista-fluxos` para um no de schedule, nem cria um workflow novo para os
tres agentes declarados. Se algum deles passar a ser ator de um no real (mudanca de topologia),
isso exige reescrever `tests/unit/schedule.sh` (contagem `EXPECTED` e ondas exatas) e merece ADR
proprio - fora do escopo desta correcao pontual.

`execution/hooks/lentes.sh` e `control/hooks/risk-trigger.sh` nao foram reescritos: as
prescricoes de UI e de custo assintotico tem funcao operacional legitima (lembrete determinístico
por superficie tocada, ADR 0011), e o defeito que a issue #54 realmente aponta era a AUSENCIA DE
DECLARACAO, nao o texto do hook. Duas observacoes de redacao em `lentes.sh` ficam registradas
como pendencia separada, fora do escopo de G110: (a) o item 3 e gramaticalmente ambiguo - "Diff
que toca dado/autorizacao/entrada nao-confiavel sempre passa por revisor-codigo; portao final e o
refutador" admite ler o segundo membro como preso ao diff de alto risco, nao a "tarefa nao
trivial" da primeira frase; (b) "portao final" e retorico - em `standard-change` o no `refute`
PRECEDE `evidence` e `candidate` no grafo, entao nao e literalmente o ultimo no.

## Propagacao pendente, fora deste ADR

`docs/status.generated.md` e gerado por `scripts/status.sh`, ambos fora do escopo de edicao desta
correcao; a contagem de suites la diverge ate a proxima geracao regular. Fica registrado como
pendencia declarada, nao como omissao.

## Referencias

- Issue #54 / achado G110.
- ADR 0043 - a garantia simetrica no nivel de workflow, e a Opcao B (nao escolhida) que motiva
  este ADR: se adotada, `lentes.sh` deixaria de ser compativel por construcao.
- `orchestration/risk-policy.json` - campo `not_risk_selected_actors`.
- `tests/unit/guidance-projection.sh` - o oraculo (fixtures POS/NEG e quatro guardas de
  vacuidade).
- `tests/mutation/guidance-projection.sh` - um mutante por garantia do oraculo.
- `control/hooks/risk-trigger.sh`, `execution/hooks/lentes.sh` - as superficies de guidance
  confrontadas.
