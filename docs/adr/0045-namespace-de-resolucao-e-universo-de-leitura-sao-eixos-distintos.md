# ADR 0045 - Namespace de resolucao e universo de leitura sao eixos distintos

Data: 2026-09-09
Estado: aceito
Sucede: ADR 0032 (referencia publicada que nao resolve)

## Contexto

`tests/unit/methodology.py` ja tinha, desde a onda 10, um resolvedor de invocacao `/x` publicada
em `SKILL.md`. O ADR 0032 corrigiu esse resolvedor duas vezes na mesma onda: primeiro ampliando a
leitura de um unico arquivo por skill para todo `.md` sob o diretorio (achado
`/direcao-de-arte`), depois descobrindo que `references/` ficara fora mesmo com `rglob`
declarado. As duas correcoes alargaram o UNIVERSO DE LEITURA - que arquivos o portao abre - sem
nunca questionar o UNIVERSO DE RESOLUCAO - que namespaces o portao aceita como resposta valida
para um token com barra.

G107 (issue #51) e a terceira iteracao da mesma classe de cegueira, um nivel acima da onda 10/12:
nove skills publicadas invocavam `/tdd` (`prd-to-issues` x5, `prd-to-plan` x2, `write-a-prd` x2).
`tdd` nao e skill: e agente, registrado em `execution/agents/tdd.md` e em
`orchestration/registry.json`. `/x` no Claude Code e superficie exclusiva de skill/comando;
agente se aciona por linguagem natural ou `@agent-<nome>`, nunca por barra.

## Dois mecanismos independentes, mesmo sintoma

**Mecanismo 1 - colapso de namespace.** A linha do resolvedor que decidia se um token resolvia
tratava skill e agente como um UNICO conjunto de resolucao valido para `/x`:

```python
if _tok in governadas or _tok in agentes or _tok == _sk: continue
```

`tdd` estar em `agentes` era lido como prova de que `/tdd` estava correto - exatamente o
inverso: `tdd` ser agente de fato e a prova de que `/tdd` esta ERRADO, porque agente nao e
membro do namespace que `/x` pode nomear. O grafo de capabilities tinha os nos certos; a aresta
publicada apontava para uma interface que nao existe, e o portao que deveria pegar isso foi
escrito com o mesmo colapso conceitual do texto que deveria julgar.

**Mecanismo 2 - sombra do lookahead (causa somada, independente).** O lookahead negativo da
regex de invocacao, `(?![\w/.-])`, incluia o ponto final como caractere de continuacao do token.
Isso tornava invisivel a portao QUALQUER invocacao em fim de frase - "...skill seguinte /tdd." -
que e onde a convencao do repositorio poe a referencia a proxima etapa do pipeline, na linha
`description:` do frontmatter. Das nove ocorrencias, oito eram visiveis so pelo Mecanismo 1;
`prd-to-issues/SKILL.md:3` so ficou visivel depois de relaxar o lookahead para `(?![\w/-])`.
Controle executado: relaxar o lookahead rendeu 4 tokens novos no corpus real e 0 falso positivo.

Os dois mecanismos foram discriminados por experimento, nao por inspecao: removendo so a
clausula `agentes`, 8 das 9 ocorrencias aparecem e a terceira (linha 3) sobrevive; o portao so
fecha com as duas correcoes juntas.

## Por que nenhuma das duas correcoes anteriores do ADR 0032 pegou isto

As correcoes de onda 10 e onda 12 alargaram QUEM le (`_f = SKILL.md` -> `rglob("*.md")` da
skill inteira -> `references/` incluso). Nunca alteraram O QUE conta como resolucao valida para
um token encontrado. G107 e o mesmo tipo de lacuna, deslocado: "que arquivos eu abro" versus "que
namespaces eu confundo". Sem esse deslocamento nomeado, a proxima aresta pendurada seria so outro
nome resolvendo para o namespace errado - e nenhuma das correcoes anteriores teria pego.

## Decisao

O resolvedor de `tests/unit/methodology.py` passa a distinguir TRES namespaces para `/x`, mais a
direcao inversa:

1. **Skill** - `registry.capabilities` com `source` sob `execution/skills/` (`governadas`),
   inalterado.
2. **Comando nativo do harness** - `_COMANDOS_NATIVOS` (novo): `clear`, `compact`, `context`,
   `agents`, `help`, `init`, `review`, `model`, `cost`, `hooks`, `mcp`, `memory`, `resume`,
   `rewind`, `usage`, `status`, `config`, `permissions`, `export`, `todos`, `doctor`, `login`,
   `logout`, `bug`, `upgrade`, `add-dir`, `plugin`. `plugin` sai de `_PLACEHOLDERS` (onde vivia
   como escape generico de prosa) porque o nome certo do que ele resolve e "comando nativo"
   (`/plugin install ...`, usado em `forge/SKILL.md`), nao "prosa sem referente".
3. **Arquivo local** (`references/x.md` etc. dentro da propria skill) - inalterado.

**Agente NAO ENTRA no conjunto que resolve `/x`.** Um token que resolve para
`execution/agents/*.md` agora produz violacao com mensagem propria (`E AGENTE, NAO SKILL`), em
vez de ser absolvido.

**Direcao inversa, nova**: referencia em prosa na forma `` agente `x` `` tem de resolver para
`execution/agents/` OU para o conjunto de agentes nativos do runtime
(`_AGENTES_NATIVOS = {"Explore", "Plan", "Task", "general-purpose"}`). Sem esse terceiro
subconjunto, uma implementacao ingenua da direcao inversa reprova
`execution/skills/design-system-proposal/SKILL.md:34` ("agente `Explore`"), que e referencia
CORRETA - falso positivo medido ao preparar esta correcao.

O texto da assercao, que dizia "resolve para skill, agente ou arquivo local", passou a mentir no
instante em que agente saiu do conjunto valido; foi reescrito para "resolve para skill, comando
nativo ou arquivo local, e toda referencia a agente resolve para agente existente".

## Criterio de aceite 4 da issue: e classe, nao string

O controle que sustenta isto foi executado, nao suposto: injetando `"Rodar /refutador ao
final."` numa skill limpa, o portao acusa `/refutador` como agente-nao-skill pelo MESMO
mecanismo que pegou `/tdd`, com outro nome de agente. Trocar o nome nao burla o portao porque a
regra e sobre PERTENCER A `execution/agents/`, nao sobre a string `tdd`.

Sete controles no total, positivos e negativos, confirmam que o instrumento acha o caso
positivo conhecido sem acusar caso negativo conhecido:

| entrada injetada | classe | resultado esperado |
|---|---|---|
| `Rodar /refutador ao final.` | `/x` de agente, outro nome | acusado (E AGENTE, NAO SKILL) |
| `Depois use /skill-fantasma para isso.` | `/x` inexistente | acusado (INEXISTENTE) |
| `` Delegue ao agente `nao-existe` agora. `` | prosa de agente inexistente | acusado (NAO EXISTE) |
| `Use /compact para reduzir o contexto.` | comando nativo | silencio |
| `` Delegue ao agente `Explore` primeiro. `` | agente nativo do runtime | silencio |
| `Depois rode /write-a-prd normalmente.` | skill irma | silencio |
| `Ver em src/auth/session.py o exemplo.` | caminho, nao invocacao | silencio |

## O que NAO foi feito, por desenho (criterio de aceite 2 da issue)

Nao foi criada skill `/tdd`, alias ou comando para a documentacao virar verdade. Isso
acrescentaria superficie de routing para corrigir uma referencia errada - o defeito era na
referencia, nao na ausencia de interface. As nove ocorrencias foram reescritas para nomear a
interface real: "agente `tdd`" (com crase, em prosa) ou "agente tdd" (sem crase, em frontmatter
YAML de linha unica e em diagrama ASCII), nunca `/tdd`.

## Mutacao

`tests/mutation/methodology.py` ganhou um caso de mutacao por CONTEUDO, nao por escalar de JSON,
porque o defeito vive em prosa sob `execution/skills`, fora do par `skill-policy.json` /
`evaluation-protocol.json` que os 16 mutantes anteriores cobrem. `monta_raiz` simlinka
`execution` inteiro como leitura; para reintroduzir `/tdd` sem escrever no repositorio real, o
arnes isola `execution/skills` como copia gravavel num clone, com as demais fontes
(`execution/agents`, `docs`, `orchestration`) permanecendo simlink/copia read-only da arvore
real. O mutante reverte uma das nove correcoes (`` agente `tdd` `` -> `/tdd`) em
`prd-to-issues/SKILL.md` dentro do clone; a assercao nova reprova, o clone limpo (baseline) fica
verde. Controle negativo executado fora da suite: o tester PRE-G107 (commit anterior, com a
clausula `agentes` no resolvedor) roda sobre o MESMO clone mutado e SOBREVIVE (exit 0) - prova de
que o mutante exercita especificamente a assercao nova, nao um portao pre-existente.

Segue o precedente do ADR 0032: "reintroduzido o defeito num clone via `TOLLENS_ROOT`, a
assercao reprova; o clone limpo fica verde."

## Prova de que o portao anterior nao media isto (modus tollens)

Executado sobre as nove ocorrencias reais (pre-correcao, recuperadas do commit anterior a este):

```
tester PRE-G107 sobre skills COM /tdd  -> EXIT=0 (TOTAL=54 FAIL=0)
tester G107      sobre skills COM /tdd  -> EXIT=1 (TOTAL=54 FAIL=1, 9 ocorrencias, granularidade de linha)
tester G107      sobre skills SEM /tdd  -> EXIT=0 (TOTAL=54 FAIL=0)
```

O portao anterior saia verde nos dois estados do mundo - com e sem o defeito. TOTAL permanece 54
nos tres casos: a mudanca APERTA uma assercao existente, nao soma outra; nenhuma contagem
publicada em outra suite deriva por causa desta correcao.

## Limite declarado, e pendencia explicita

Editar `SKILL.md` invalida o digest de diretorio que `install/manifest.lock` guarda para
`prd-to-issues`, `prd-to-plan` e `write-a-prd` (calculado pelo mesmo `install/manifest.sh` que
`contrato-de-instalador.sh` invoca), e `tests/unit/reprodutibilidade.sh` (secao R3, "manifest.lock
esta atualizado") fica VERMELHA ate o lock ser regenerado e commitado. Este arquivo esta fora do
escopo de edicao autorizado desta sessao. Medido nesta onda: `bash
tests/unit/reprodutibilidade.sh` sai com `PASS=10 FAIL=1` (R3 reprovando), o resto da suite
(R1, R2, R4) inalterado e verde. A regeneracao (`bash install/manifest.sh install/manifest.lock`)
e identica ao que o instalador real executaria e nao envolve decisao de conteudo - so a
autorizacao para tocar num arquivo protegido cabe a quem administra o repositorio, nao a esta
implementacao.

## Referencias

- `tests/unit/methodology.py` - resolvedor, secao G107.
- `tests/mutation/methodology.py` - mutante `reintroduz-barra-tdd`.
- `execution/skills/prd-to-issues/SKILL.md`, `execution/skills/prd-to-plan/SKILL.md`,
  `execution/skills/write-a-prd/SKILL.md` - as nove ocorrencias reescritas.
- ADR 0032 (referencia publicada que nao resolve) - onda 10/12, o mesmo defeito no universo de
  leitura.
- `tests/unit/reprodutibilidade.sh` - secao R3, pendencia de `install/manifest.lock`.
