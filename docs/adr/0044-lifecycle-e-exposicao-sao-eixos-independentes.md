# ADR 0044 - Lifecycle e exposicao ao router sao eixos independentes

Data: 2026-09-09
Estado: aceito
Sucede: ADR 0043 (risco declarado nao e risco selecionado)

## Contexto

`orchestration/skill-policy.json:lifecycle.states` declara cinco estados
(`quarantine`, `candidate`, `promoted`, `deprecated`, `rejected`). Populacao real no registry
medida nesta onda: 34 `candidate` + 1 `deprecated`, sobre 35 capabilities - `quarantine`,
`promoted` e `rejected` tem populacao ZERO.

`state` responde em que fase de avaliacao uma capability esta. Nenhum campo do artefato
respondia uma pergunta diferente e igualmente necessaria: o que a GOVERNANCA autoriza o router a
fazer com ela. `activation` parecia responder isso e nao responde - e o campo e POLIMORFICO por
`kind` (skill: `manual`/`contextual`; agente: `delegated`; hook: nome do evento) e AMARRADO ao
mecanismo (`tests/unit/skill-invocation-policy.sh` deriva o esperado da presenca de
`disable-model-invocation` no frontmatter). `activation` responde "qual e o mecanismo de
disparo"; a pergunta de governanca e outra.

O conceito ja estava publicado em prosa, sem artefato: `README.md` (secao "Canonical skill
location and runtime exposure") afirma que "runtime skill exposure is itself an intervention".
Nenhum vocabulario, nenhum portao, nenhuma expiracao. `grep -rni
"exposure|experimental_auto|runtime_exposure"` na arvore anterior a esta onda so retornava essas
duas linhas de prosa.

## O que ja era mecanico, e o que e genuinamente novo

Tres das cinco invariantes que este ADR fecha ja existiam - so que na projecao de INSTALACAO, nao
na de exposicao. `tests/unit/capability-conformance.py` (CC3) ja reprovava `deprecated`/`rejected`
instalada e `quarantine` instalada. Definindo `off` como "nao exposta ao router" pela equivalencia
honesta `off <=> installed == false`, as tres invariantes

- `quarantine => off`
- `deprecated => off`
- `rejected => off`

ja tinham metade do corpo escrito: bastava amarrar o vocabulario novo ao fato que CC3 ja media.
As DUAS invariantes genuinamente novas, sem precedente mecanico anterior, sao:

- `candidate` nao pode ser `auto` (so `off`, `manual` ou `experimental_auto`)
- `promoted` nao pode ser `experimental_auto` (so `off`, `manual` ou `auto`)

`experimental_auto` e a peca nova de vocabulario: autoriza selecao automatica pelo router POR
PRAZO, para uma capability ainda em avaliacao (`candidate`), distinguindo "usuario pediu" de
"modelo escolheu" no vocabulario de governanca - distincao que antes desta onda nao existia em
lugar nenhum (as cinco skills `contextual` eram, ate aqui, `candidate` tratada como capability
normal, sem prazo nem instrumento de medicao associado).

## Desenho: eixo novo no mesmo padrao dos eixos existentes

Desacoplar eixos e a forma canonica deste repositorio, nao uma decisao inaugurada aqui: `state` x
`installed` (ADR 0033) e `projection` (onda 22b, `capability-conformance.py` CC5) ja sao exemplos
do mesmo padrao. `exposure` entra como o quarto eixo, com o mesmo cuidado: reclassificar `state`
ou `installed` nao deve mudar `exposure` por acidente, e vice-versa.

`orchestration/evidence-policy.json` recebe o bloco `runtime_exposure` (vocabulario, mapa
`allowed_by_lifecycle`, campos exigidos de `experimental_auto`, pastas onde `eval_id` resolve).
NAO foi colocado em `orchestration/skill-policy.json`, que seria o lugar natural ao lado de
`lifecycle`, por tres razoes: (a) esse arquivo esta detido por outro trilho de trabalho na mesma
branch nesta sessao; (b) a dimensao candidata `E_A`, a que `exposure` se liga, ja mora em
`evidence-policy.json`; (c) esse arquivo ja entra em `_digest_da_policy`
(`capability-conformance.py:241`), entao um dossie avaliado sob politica de exposicao antiga fica
STALE de graca. Se o outro trilho liberar `skill-policy.json`, mover o bloco para junto de
`lifecycle` e defensavel; nao vale bloquear esta reforma por isso. `proof_obligations` nao foi
tocado nesta onda - qualquer mudanca ali alteraria D_E e reprovaria
`tests/unit/governance-links.py` contra o D_E publicado no ADR 0035; medido apos a migracao:
`D_E(head)=89` sobre `28` capabilities endividadas, identico ao estado anterior.

`orchestration/registry.json` recebe `exposure` nas nove capabilities `kind: skill` (as unicas
existentes deste tipo), derivado do frontmatter medido:

| skill | `disable-model-invocation` | `exposure.level` |
|---|---|---|
| depreciar, forge, prd-to-issues | `true` | `manual` |
| design-system-proposal, graphify, grill-me, prd-to-plan, write-a-prd | ausente | `experimental_auto` |
| defesa-de-tese (tombstone, `deprecated`, `installed: false`) | n/a | `off` |

As cinco `experimental_auto` compartilham `eval_id: EA-0001`, apontando para
`evidence/experiments/EA-0001-exposicao-experimental-auto.md` (criado nesta onda: sem ele
`eval_id` seria string decorativa - nenhum registro do repositorio resolvia para esse
identificador antes desta onda). Janela: `started_at: 2026-09-09`, `expires_at: 2026-12-08`.

`tests/unit/capability-conformance.py` recebe a secao CC8: le vocabulario e mapa da policy (nunca
hardcoded, precedente F1/onda 15), aplica as cinco invariantes, confere `off <=> installed`,
confere coerencia com o MECANISMO na direcao OPOSTA da onda 27 (`disable-model-invocation: true`
proibe `auto`/`experimental_auto`; ausencia proibe `manual`, lendo o SKILL.md de cada skill) e, em
`experimental_auto`, exige os cinco campos declarados, `expires_at` ISO no futuro e `eval_id`
resolvido sob `evidence/experiments/` ou `evidence/claims/`.

## Escopo restrito a `kind: skill`

`runtime_exposure.scope` declara `"skill"` explicitamente. Agente e delegado pelo orquestrador
(mecanismo diferente de selecao) e hook dispara por evento (nem "modelo escolheu" nem "usuario
pediu" se aplicam da mesma forma) - modelar exposicao para eles seria desenho proprio, nao
extensao trivial. Mesma postura que o ADR 0036 tomou com G7 (hook_gate mistura prevenir com
rejeitar depois, e continua ABERTO sem que este ADR o feche). Ampliar o escopo depois e
monotonico; nao ha decisao aqui que precise ser desfeita para isso.

## Vacuidade de tres estados, e a fixture que compensa

`quarantine`, `promoted` e `rejected` tem populacao ZERO no registry real. Sem fixture, tres das
cinco linhas de `allowed_by_lifecycle` nunca seriam exercitadas por dado real, e "verde" nao
distinguiria "conforme" de "nao ha o que conferir" - a mesma classe que este repositorio ja pagou
em CC6 e CC7. CC8 aplica o MESMO comparador (`_exposure_falhas`, funcao pura sobre um dict) a dois
fragmentos sinteticos em memoria: um fragmento `{"state": "quarantine", "exposure": {"level":
"auto"}}`, que tem de ser acusado, e um fragmento `{"state": "candidate", "exposure": {"level":
"manual"}, ...}` conforme, que tem de passar limpo. Os dois sao verificados a cada execucao da
suite, junto das nove skills reais.

## O limite que impede repetir G6a

`exposure` e DECLARACAO DE GOVERNANCA - o que a politica AUTORIZA o router a fazer -, nunca
OBSERVACAO de que o router de fato selecionou a capability. Nada nesta onda mede ativacao. A
dimensao candidata `E_A` (`orchestration/evidence-policy.json:dimensions_candidatas.E_A`)
permanece `NAO IMPLEMENTADA`, com o mesmo `blocked_by` de antes: falta oraculo de runtime. `runtime`
e `model`, dentro do bloco `exposure` de `experimental_auto`, sao campos DECLARADOS E NAO
CONFERIDOS - o mesmo limite que `evidence-policy.json:staleness.limit` ja assume para dossie de
skill, reaproveitado aqui em vez de inventado. Ler a existencia de `experimental_auto` como prova
de que o router selecionou alguma das cinco skills repetiria exatamente o defeito que o ADR 0036
(G6a) corrigiu, um eixo adiante.

`expires_at` vencido reprova a suite por PASSAGEM DE TEMPO, sem mudanca de codigo alguma - efeito
pretendido (a autorizacao tem prazo), nao falha de manutencao. Quem define `expires_at` esta
agendando uma reprovacao futura, e precisa saber disso.

## Numeros medidos que motivam a onda (2026-09-09, nesta sessao)

- `evidence/telemetry/medir-skills.sh`: 2506 transcripts (1107 principais + 1399 de subagente).
  As 8 skills instaladas aparecem com `modelo=0`, `modelo(sub)=0`, `cmd=0`, `mencao=0` - zero nos
  quatro canais, para as 8.
- `control/hooks/activation-log.sh` -> `/var/log/tollens-activation.jsonl` (1448 linhas no
  momento da medicao): 3 eventos `Skill`, 2 nomes distintos (`artifact-design`,
  `release-engineering`), NENHUM dos 8 do repositorio. Canal independente do transcript, e mostra
  que o router deste ambiente seleciona skill - so nao seleciona as deste repositorio. (A
  investigacao que precedeu esta implementacao mediu, em janela anterior do mesmo log, 36
  eventos e 8 nomes distintos, tambem nenhum dos 8 do repositorio - a contagem absoluta muda com
  a janela observada; a conclusao qualitativa, nao.)

## O que NAO foi feito nesta onda, e por que

- **Mutantes de `tests/mutation/capability-conformance.sh` (MCAP30-36)**: NAO adicionados.
  Acrescentar mutante muda `docs/status.generated.md:48` (a coluna de contagem de
  `capability-conformance` la registrada) e `scripts/status.sh --check` compara esse artefato
  BYTE A BYTE. Os dois arquivos estao fora do escopo de edicao desta sessao. A forca probatoria
  das cinco invariantes vem inteira da secao CC8 em execucao real (demonstrada abaixo) mais a
  fixture sintetica - nao da mutacao formal. Pendencia explicita para uma onda que possa
  regenerar `docs/status.generated.md`.
- **`execution/skills/depreciar/SKILL.md`**: a receita do tombstone (linhas 79-84, "APAGAR o
  diretorio... e registrar o tombstone... `state: deprecated`, `retired_at`, `superseded_by`,
  `reason`") fica INCOMPLETA - falta `exposure: off`. O arquivo esta sob outro trilho de trabalho
  nesta mesma branch e nao foi editado. O portao aplica a regra de qualquer forma (CC8 exige
  `off` para `deprecated`); e defeito de documentacao, nao de mecanismo.
- **Escopo para `agent`/`hook_*`**: declarado como fora do escopo desta onda (`runtime_exposure`
  aponta expressamente `scope: skill`), nao como omissao.

## Referencias

- `orchestration/evidence-policy.json` - bloco `runtime_exposure` e `dimensions_candidatas.E_A`.
- `orchestration/registry.json` - `exposure` nas nove capabilities `kind: skill`.
- `evidence/experiments/EA-0001-exposicao-experimental-auto.md` - o registro que `eval_id`
  resolve.
- `tests/unit/capability-conformance.py` - secao CC8.
- ADR 0033 (estado nao e nome de diretorio) - precedente do desacoplamento de eixos.
- ADR 0036 (instalar nao e ativar) - G6a (corrigida) e G6b (aberta), e o limite que este ADR
  reaproveita.
- ADR 0038 (referencia que resolve) - precedente de `eval_id` resolvendo contra artefato real.
- ADR 0035 - D_E publicado, reconferido inalterado apos esta onda.
