# Política de invocação de Skills

Estado: **CANDIDATO — depende de CI/merge**  
Data: 2026-08-25  
Relacionado: #33

## Princípio

O objetivo não é maximizar o número de Skills usadas. É maximizar seleção correta e utilidade marginal.

```text
INSTALLED != TRIGGERED != USEFUL
```

Uma Skill rara pode estar correta se raramente houver tarefa elegível. Forçar uso transforma routing em ritual.

## Side effects

Workflows que alteram estado externo e cujo timing deve permanecer sob controle do usuário são manual-only. No Claude Code isso é representado por:

```yaml
disable-model-invocation: true
```

A flag também retira a descrição da Skill do contexto automático. Portanto reduz simultaneamente risco de acionamento e custo de contexto para workflows manuais.

### Decisão atual

`prd-to-issues` contém `gh issue create` e cria estado remoto no GitHub. Ela passa a ser manual-only.

A decisão **não** é aplicada por analogia às demais Skills. `graphify`, por exemplo, continua elegível ao routing automático enquanto sua utilidade/routing são medidos.

### G102 (issue #46) — a exceção do graphify passa a viver no artefato de política

Até esta correção, `orchestration/skill-policy.json` tinha um campo `default_activation` sem
definição operacional e sem consumidor: nenhum executável do repositório o lia para decidir
coisa alguma, e a única asserção que o citava reabria o mesmo JSON e o comparava com o literal
que ele contém. `orchestration/registry.json` declarava `capabilities.*.activation` sem que
nada o conferisse contra o frontmatter real das Skills — chegou a divergir em 3 das 8
(`depreciar`, `forge`, `prd-to-issues` diziam `contextual` enquanto o `SKILL.md` de cada uma
tem `disable-model-invocation: true`), sem que nada ficasse vermelho.

A correção:

1. `skill-policy.json` ganha um bloco `activation` com `default`, `vocabulary` (enum fechado
   `["manual", "contextual"]`), `mechanism` (a chave de frontmatter que produz cada valor) e
   `model_invocable_exceptions` — a lista, com `reason` por item, das Skills que permanecem
   elegíveis ao routing automático. A exceção do `graphify` deixa de viver só no controle
   negativo do teste e passa a ser declarada aqui.
2. `registry.json` corrigido nas 3 entradas que contradiziam o próprio frontmatter.
3. `tests/unit/skill-invocation-policy.sh` compara, para cada Skill, o valor declarado em
   `registry.json` contra o derivado do frontmatter, exige que toda Skill contextual tenha
   entrada em `model_invocable_exceptions` com `reason` não vazio, e recusa qualquer valor de
   `activation` fora do vocabulário fechado.

LIMITE DECLARADO, e ele é o que impede sobre-reivindicação: isto fecha `PolicyDeclared !=
PolicyEnforced` na camada de ARTEFATO — os três registros (policy, registry, frontmatter)
passam a concordar entre si. Isto **não mede E_A**: não observa se o runtime de fato roteou ou
deixou de rotear uma Skill. Ler isto como prova de ativação repetiria o defeito do ADR 0036
(G6a) — representação do mecanismo não é o fenômeno.

### G106 (issue #50) — efeito é dimensão independente de ativação, e passa a ser declarada

A correção do G102 fechou `activation.registry != frontmatter`, mas não dizia nada sobre O QUE
uma Skill faz. `write-a-prd` publicava `gh issue create` no corpo — escrita remota — enquanto
`activation.model_invocable_exceptions` a justificava com a frase "efeito local e reversível",
nunca conferida por executável algum. A mesma configuração (activation consistente,
`model_invocable_exceptions` com `reason` não vazio) era satisfeita por qualquer par
"contextual + qualquer corpo", inclusive um com `gh issue create`: `PolicyDeclared` sem
`PolicyEnforced`, agora na dimensão de EFEITO em vez da de ativação.

A correção:

1. `skill-policy.json` ganha um bloco `effects` — sibling de `activation`, porque é uma
   dimensão diferente — com `vocabulary` (enum fechado `["pure", "local-write", "remote-write",
   "destructive"]`) e `by_skill` (mapa skill → efeito, uma entrada por diretório de
   `execution/skills/`).
2. A invariante nova: `effect in {remote-write, destructive} => activation != contextual`,
   verificada com o lado de ativação vindo do FRONTMATTER em disco (não da policy) — dois
   arquivos independentes, o mesmo padrão que a asserção de G102 já usa.
3. Detectores sintáticos (`gh issue create`, `gh pr create`, `gh api`, `git push`, `curl -X
   POST|PUT|PATCH|DELETE`, `http(x).post|put|patch|delete(`, `aws s3 cp`) entram como CONTROLE
   DE INCONSISTÊNCIA, nunca como definição de classe: casar um padrão com efeito declarado
   ABAIXO de `remote-write` reprova. A leitura precisa do critério é "abaixo de `remote-write`",
   não "declarada `pure`" — `gh issue create` numa skill `local-write` é igualmente uma escrita
   remota que o efeito local não cobre.
4. A ASSIMETRIA, que tem de sobreviver a qualquer extensão futura: a AUSÊNCIA de qualquer
   padrão sintático NUNCA promove uma skill a `pure`. Ausência de string é ausência de
   evidência sintática, não evidência de ausência de efeito. Só a declaração humana em
   `by_skill` define a classe; o detector só pode agravá-la.
5. `write-a-prd` foi corrigida pela via preferida pela issue: a redação do PRD passou a ser
   gravada localmente (`./prds/<slug>.md`, espelhando `/prd-to-plan`), e a publicação remota
   (`gh issue create`) foi movida para `/prd-to-issues` (que já era manual-only). `write-a-prd`
   permanece `contextual` — deixou de ser falso porque o efeito deixou de ser remoto, não porque
   a checagem foi enfraquecida.

LIMITE DECLARADO, e é o que a issue #50 já nomeava: um mutante que só more por causa do NOME
("write-a-prd") ou do LITERAL ("gh issue create") provaria o repro, não o predicado. O arnês de
mutação registra uma skill fictícia com outro nome e outra forma de escrita remota
(`publicar-relatorio`, `curl -X POST`) consistente em toda outra dimensão, e confere que a
morte ocorre pela MENSAGEM do bloco de inconsistência — não apenas pelo código de saída.

## E_A — avaliação de ativação

Para Skills auto-invocáveis, medir separadamente:

```text
TriggerRecall    = TP / (TP + FN)
TriggerPrecision = TP / (TP + FP)
UtilityDelta     = Q_with - Q_without
CostDelta        = tokens/latency_with - baseline
```

Conjuntos de prompts de desenvolvimento e held-out devem ser distintos. Ajustar a `description` até passar nos próprios exemplos e chamá-lo de routing melhor é overfit.

## O que este PR prova

O oráculo estreito verifica apenas duas decisões atuais:

1. a Skill conhecida por executar `gh issue create` está manual-only;
2. `graphify` não foi desabilitada como consequência colateral.

Ele não tenta inferir semanticamente todos os side effects possíveis por regex.

## Limites

- manual-only não prova segurança da implementação interna;
- manual-only não prova utilidade;
- routing automático de outras Skills continua NOT_VERIFIED até o experimento de #33;
- side effect local/temporário não é automaticamente equivalente a side effect remoto irreversível.
