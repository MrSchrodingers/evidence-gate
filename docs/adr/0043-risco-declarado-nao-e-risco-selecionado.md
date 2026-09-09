# ADR 0043 - Risco declarado nao e risco selecionado

Data: 2026-09-08
Estado: aceito
Sucede: ADR 0042 (o portao julga o delta, nao a arvore)

## O defeito, medido (G103, issue #47)

**G103 -** o kernel governa por CLASSE DE RISCO (4 classes) e a orquestracao por ID DE
WORKFLOW (3 ids), e nao existia artefato versionado ligando os dois vocabularios: a funcao
R: RiskClass -> WorkflowId nao era total, nao era resolvivel e nao era refutavel por oraculo
algum. A ligacao vivia so em prosa.

O kernel (`execution/config/CLAUDE.md`, secao 7, "Delegacao por risco, nao por ritual") governa
por CLASSE DE RISCO - quatro linhas: `trivial`, `normal`, `medio`, `alto`. A orquestracao
(`orchestration/registry.json`, `orchestration/workflows/*.json`) governa por ID DE WORKFLOW -
tres arquivos: `investigation-only`, `standard-change`, `high-risk-change`.

Ate esta correcao, nenhum artefato versionado ligava os dois vocabularios. A ligacao vivia em
DUAS formulacoes de prosa, independentes e nao verificaveis por oraculo algum:

- `CLAUDE.md:3` (raiz do repositorio): "Use `standard-change` para mudancas comuns e
  `high-risk-change` para autorizacao, parser, dependencia, instalacao ou CI." - mapeia por
  DOMINIO da tarefa, nao por classe de risco.
- `docs/method/orquestracao-e-avaliacao.md:7`: "o classificador escolhe" - nao diz o que.

Nenhum executavel deste repositorio verificava que as quatro classes do kernel tinham destino, que
os tres workflows eram alcancaveis, ou que uma mudanca em um lado (kernel ou diretorio de
workflows) fosse detectada pelo outro. A funcao `R: RiskClass -> WorkflowId` nao era total, nao
era resolvivel e nao era refutavel.

## A decisao: declarar a funcao como artefato, e qual funcao declarar

`orchestration/risk-policy.json` passa a existir como o artefato que declara `R`, e
`orchestration/render.py --check` passa a verifica-lo contra DUAS fontes que ele nao controla:
o DOMINIO (a tabela do kernel, lida em tempo de verificacao, nunca copiada) e o CONTRADOMINIO
(o diretorio `orchestration/workflows/`, listado em disco). A politica nunca se autoconfirma -
mudar o kernel ou o diretorio, com a politica intacta, reprova (fixtures N6/N7 de
`tests/unit/risk-policy.sh`).

A parte que exigia decisao, e nao medicao, era o CONTEUDO da politica para as classes `normal` e
`medio`. O kernel, na linha imediatamente abaixo da tabela (secao 7), diz:

> "Mas revisor nao e imposto: se ha teste que falhava e agora passa mais suite verde, um terceiro
> modelo pode custar mais do que rende."

`standard-change` impoe `review` E `refute` como nos do grafo, incondicionalmente. Mapear
`normal` (que o kernel descreve como "escrever, testar", sem revisao) para `standard-change`
colide de frente com essa frase. Duas saidas eram igualmente legitimas pelo criterio 2 da issue
#47 (ausencia ou correspondencia tem de ser DECLARADA, nunca inferida):

- **Opcao A** - convergir `normal` e `medio` para `standard-change`, declarando no campo
  `rationale` de `normal` que isso e superprovisionamento deliberado, e citando a linha do kernel
  acima como o custo aceito.
- **Opcao B** - criar um workflow novo, `normal-change`, fiel a linha `normal` do kernel
  (`plan/red/implement/test`, sem `review`/`refute`).

**Este ADR adota a Opcao A.** Razoes, em ordem de peso:

1. **Custo medido.** A Opcao B exige um workflow novo com par em `orchestration/schedule/`, e
   `tests/unit/schedule.sh` reprova imediatamente: a suite conta `3` workflows reais no
   nivelamento de ondas (`emite ondas para os 3 workflows`) e teria de ser reescrita (contagem
   `EXPECTED`, ondas exatas de `standard-change`) para acomodar um 4º. A Opcao A tem custo ZERO
   nesse arquivo - nenhum workflow novo, nenhum arquivo de escalonamento novo.
2. **`evidence/cobertura.sh` (CAMADA 1).** O piso de cobertura de `orchestration/schedule.py` e
   comparado por IGUALDADE exata (`medido == piso`, nao `>=`) contra 35 isencoes de linha/ramo
   ancoradas nesse arquivo especifico. Qualquer mudanca de codigo ali desloca o denominador e
   reprova a camada inteira ate o piso ser reapertado a mao. A Opcao A nao toca
   `orchestration/schedule.py`.
3. **Escopo restrito ao achado.** G103 pede que a funcao risco->workflow seja total, resolvivel e
   refutavel - nao pede um workflow novo. Introduzir `normal-change` seria resolver um problema
   adjacente (o kernel pede menos rigor que `standard-change` impoe) que a issue nao levantou.

O custo aceito da Opcao A e real e esta registrado no proprio `rationale` da entrada `normal` em
`orchestration/risk-policy.json`: mudancas classificadas como risco `normal` recebem
`review`/`refute` que o kernel, lido literalmente, nao exige. Se a experiencia mostrar que esse
superprovisionamento pesa (revisao consistentemente descartada, ciclo mais lento sem ganho
observado), a Opcao B fica registrada aqui como a alternativa nao escolhida, com o preco dela ja
medido.

`trivial` mapeia para `workflow: null` com `rationale` obrigatoria (nenhum grafo multi-no e
escalonado para o caminho "direto" do kernel) - ausencia DECLARADA, nao ausencia por omissao.
`alto` mapeia para `high-risk-change`, sem tensao com o kernel (que pede exatamente
"investigar, escrever, testar, revisar, refutar" para essa classe).

## `investigation-only` nao e selecionado por risco

`investigation-only` nao aparece na imagem de `R` porque ele nao e escolhido por classe de risco:
e escolhido pelo TIPO da tarefa (investigar sem mutar o codigo). `orchestration/risk-policy.json`
declara isso explicitamente no campo `not_risk_selected`, com motivo escrito - sem essa
declaracao, o workflow ficaria fora do alcance da funcao por acidente de desenho, nao por
decisao, e `orchestration/render.py --check` o acusaria como orfao (garantia (v), "ALCANCE").

## Limite declarado: auditavel, nao executado

`orchestration/risk-policy.json` e `orchestration/render.py --check` entregam uma funcao
VERIFICAVEL, nao um escalonador. Nenhum runtime deste repositorio le um id de classe de risco
para decidir workflow em tempo de execucao (conferido por busca em `.claude/`, `.codex/`,
`control/`, `execution/skills/`: nenhum leitor). `orchestration/classify` continua sendo um NO DE
ENTRADA dos workflows `standard-change` e `high-risk-change` - a classificacao de risco roda
DEPOIS que o workflow ja foi escolhido por outra via (tipicamente, a leitura humana do pedido).
Essa inversao estrutural preexiste a este ADR, o `risk-policy.json` a torna visivel (o campo
`limits` do proprio arquivo a registra), e este ADR nao a resolve - resolve-la exigiria mover
`classify` para antes da selecao de workflow em toda invocacao real, fora do escopo de G103.

## Propagacao pendente, fora deste ADR

`CLAUDE.md:3` (raiz) foi reescrito para apontar para `orchestration/risk-policy.json` como fonte
unica, em vez de reformular a mesma funcao por dominio da tarefa.
`docs/method/orquestracao-e-avaliacao.md:7` continua com a formulacao antiga ("o classificador
escolhe") - e uma TERCEIRA formulacao em prosa da mesma funcao, fora do alcance de qualquer
teste, e nao foi alterada nesta correcao porque o plano que originou este ADR nao a incluiu na
lista de arquivos a editar. Fica registrada aqui como pendencia, nao como decisao de manter.

## Referencias

- Issue #47 / achado G103.
- `orchestration/risk-policy.json` - o artefato.
- `orchestration/render.py` - `_check_risk_policy`, `_classes_do_kernel`, `_norm_risco`.
- `tests/unit/risk-policy.sh` - fixtures C0/C1 (positivas) e N1-N8 (negativas, uma por
  garantia, mais a divergencia `registry["workflows"]` x disco).
- `tests/mutation/risk-policy.sh` - um mutante por garantia do validador.
- `docs/architecture/orquestracao-multirruntime.md` - secao "Workflows".
