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
