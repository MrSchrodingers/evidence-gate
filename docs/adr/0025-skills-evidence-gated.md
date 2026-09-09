# ADR 0025 — Skills são capacidades evidence-gated, não contexto padrão

- Status: aceito
- Data: 2026-08-07

## Contexto

O projeto já separa produção de artefato e certificação externa, mas a projeção de skills ainda
podia ser interpretada como uma biblioteca a ser injetada indiscriminadamente. Evidência recente
não sustenta essa interpretação.

SWE-Skills-Bench avalia skills de software em condições pareadas sobre snapshots fixos e encontra
benefício marginal altamente heterogêneo, incluindo muitos resultados nulos, custo adicional sem
ganho e regressões por incompatibilidade/context interference. SkillsBench também mostra que
skills podem ajudar, ser redundantes ou prejudicar, dependendo de tarefa, conteúdo e agente.

O próprio efeito de uma skill não é separável do modelo e do scaffold sem controle experimental.
Logo, existência, popularidade, tamanho ou plausibilidade de uma skill não constituem evidência de
utilidade.

## Decisão

1. `default_activation = off`.
2. Seleção é `evidence-gated`, por gatilho observável e compatibilidade de repositório/versão.
3. Injeção blanket é proibida.
4. Composição multi-skill permanece desabilitada até avaliação específica; o limite inicial é uma
   skill por tarefa.
5. Toda skill nova ou auto-gerada começa em `quarantine`.
6. Promoção exige avaliação pareada `without_skill`/`with_skill`, snapshot fixo, requisito
   autocontido, verificador determinístico, controle negativo, compatibilidade, custo e busca por
   interferência contextual.
7. Skill não é autoridade, oráculo ou certificador.
8. Resultados nulos e negativos são preservados.
9. Utilidade da skill, qualidade do seletor e efeito do scaffold/modelo são estimandos distintos.
10. Regressão de correção, segurança, compatibilidade ou validade do verificador devolve a skill à
    quarentena ou a deprecia.

As regras de máquina vivem em `orchestration/skill-policy.json` e
`orchestration/evaluation-protocol.json`; o protocolo humano está em
`docs/method/skill-evaluation-protocol.md`.

## Consequências

### Positivas

- reduz context pollution e anchoring por templates incompatíveis;
- torna promoção falsificável e auditável;
- separa eficácia, custo, seleção e scaffold;
- impede que geração automática se torne autoridade por auto-publicação;
- permite depreciação baseada em evidência.

### Custos

- skills deixam de ser conveniência de ativação automática;
- promoção exige corpus e execução experimental;
- resultados dependem de modelo/scaffold e precisam ser reavaliados quando essas variáveis mudam;
- uma biblioteca grande pode permanecer em quarentena por tempo indefinido.

## Claims explicitamente não feitas

Este ADR não afirma que `tollens` melhora a qualidade de agentes, que uma skill promovida é
universalmente útil ou que subagentes são estatisticamente independentes. Tais afirmações exigem
experimentos próprios e permanecem hipóteses até medição.

## Errata 2026-09-08

**G102 -** a decisão 1 dizia apenas `default_activation = off`, um termo sem definição
operacional e sem consumidor: nenhum executável do repositório o lia para decidir coisa alguma,
e a única asserção que o citava (`tests/unit/methodology.py`) reabria o mesmo
`orchestration/skill-policy.json` e o comparava com o literal que ele próprio contém. Ao mesmo
tempo, `orchestration/registry.json` declarava `capabilities.*.activation` sem qualquer oráculo
que o conferisse contra o frontmatter real das Skills - divergiu em 3 das 8
(`depreciar`, `forge`, `prd-to-issues` diziam `contextual` enquanto cada `SKILL.md` tem
`disable-model-invocation: true`), sem que nada ficasse vermelho.

A decisão 1 passa a ler: `orchestration/skill-policy.json` declara um bloco `activation` com
`default: "manual"`, um vocabulário fechado (`manual`/`contextual`), o mecanismo (a chave de
frontmatter `disable-model-invocation`) e a lista `model_invocable_exceptions` das Skills que
permanecem elegíveis ao routing automático do modelo, cada uma com `reason`. `registry.json` foi
corrigido nas 3 entradas que contradiziam o próprio frontmatter, e
`tests/unit/skill-invocation-policy.sh` passou a comparar, por Skill, o valor declarado contra o
derivado do frontmatter, e a exigir vocabulário fechado e exceção declarada com motivo.

Isto fecha `PolicyDeclared != PolicyEnforced` na camada de ARTEFATO (os três registros
concordam entre si). Isto NÃO mede `E_A` - não observa se o runtime de fato roteia. Afirmar o
contrário repetiria o defeito do ADR 0036 (G6a). Ver
`docs/architecture/skill-invocation-policy.pt.md` e `evidence/corpus/agente-x-defeito.json`
(`G102`).

## Referências

- Han et al., *SWE-Skills-Bench: Do Agent Skills Actually Help in Real-World Software Engineering?*, arXiv:2603.15401, 2026.
- Li et al., *SkillsBench: Benchmarking How Well Agent Skills Work Across Diverse Tasks*, arXiv:2602.12670, 2026.
- Yang et al., *SWE-agent: Agent-Computer Interfaces Enable Automated Software Engineering*, NeurIPS 2024.
- Ding et al., *Agent Skill Evaluation and Evolution: Frameworks and Benchmarks*, arXiv:2606.11435, 2026.
- Xu & Yan, *Agent Skills for Large Language Models: Architecture, Acquisition, Security, and the Path Forward*, arXiv:2602.12430, 2026.
