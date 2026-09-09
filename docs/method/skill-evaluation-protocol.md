# Protocolo de avaliação de skills e scaffolds

## Objetivo

Este protocolo mede utilidade marginal; não presume que uma skill, subagente ou scaffold seja benéfico por existir. A unidade experimental é uma tarefa real em um snapshot fixo de repositório. O desfecho primário é satisfação executável dos requisitos.

## Unidade experimental

Cada execução é identificada pela tupla:

`(R, E, P, S, A, M, T)`

- `R`: repositório e commit fixo;
- `E`: ambiente reproduzível;
- `P`: requisito autocontido com critérios de aceitação;
- `S`: condição de skill (`without_skill` ou `with_skill`);
- `A`: scaffold/agente;
- `M`: modelo e configuração;
- `T`: repetição/trial.

Mudanças entre condições pareadas em `R`, `E`, `P`, `A` ou `M` invalidam o contraste causal da skill.

## Requisitos e oráculos

Cada critério de aceitação deve mapear para pelo menos um verificador determinístico. O verificador deve executar o artefato ou analisar estrutura/semântica parseada. São proibidos como evidência primária:

- busca de palavra-chave;
- presença isolada de arquivo;
- LLM-as-judge;
- asserção que um artefato trivialmente incorreto satisfaz;
- verificador escrito a partir da saída do agente avaliado.

Para cada suite deve existir um controle negativo conhecido que falhe pelo motivo correto. Sempre que possível, inclua mutante atribuível que viole uma única propriedade.

## Pareamento e repetição

O contraste mínimo é `without_skill` versus `with_skill`, no mesmo snapshot, ambiente, modelo e scaffold. Como agentes são estocásticos, uma observação única não é tratada como estimativa de eficácia. Trials repetidos devem registrar ordem, versão do runtime, modelo, configuração, budget e resultado bruto.

A análise deve preservar pares discordantes; médias agregadas não substituem a matriz por tarefa. Intervalos de confiança devem acompanhar estimativas. Resultados nulos e negativos são resultados, não falhas de experimento.

## Skill selection

Utilidade da skill e qualidade do seletor são problemas distintos. O protocolo mede separadamente:

- precisão de seleção;
- recall de seleção;
- taxa de injeção desnecessária;
- desempenho condicionado à seleção correta;
- desempenho quando nenhuma skill é injetada.

Enquanto não houver evidência de composição, o limite é uma skill por tarefa. Injeção blanket é proibida.

## Co-variáveis de routing

Um hook de `UserPromptSubmit` que escreve em stdout não é ambiente neutro: esse stdout é entregue ao modelo como contexto, no mesmo papel de canal de routing que a description da skill. Um hook nessa condição é co-variável do experimento, não parte fixa do ambiente `E`.

O braço `A_router_puro` (description-only, sem skill instalada) exige todo hook de routing desligado — mecanicamente, via `TOLLENS_ROUTING_NUDGES=off`, nunca por edição manual do hook a cada execução. O braço `B_sistema_deployado` (skill mais nudge ligados) é outro experimento: mede se skill e hook juntos produzem uso, não se a description sozinha roteia. Cada trial registra qual dos dois braços rodou (`orchestration/evaluation-protocol.json#design.arms`).

Dose medida do nudge de `graphify-scout-mode.sh` sobre a base de transcripts consultada: presente em 858 de 1107 transcripts, 7248 emissões, entregue duas vezes por prompt (escopo de usuário e escopo managed leem `UserPromptSubmit` cada um). O limite do desligamento mecânico: em uma imagem sem `graphify` instalado o hook já silencia sozinho pela guarda de topo, então a ausência de nudge nessas execuções não é intencional — é efeito colateral da imagem, não do desenho experimental. Por isso o desligamento do braço A precisa ser explícito (`TOLLENS_ROUTING_NUDGES=off`) e registrado, nunca inferido do silêncio observado.

## Compatibilidade e interferência contextual

Toda skill candidata declara proveniência, domínio, versões suportadas, precondições e referências. A avaliação inclui casos deliberadamente próximos mas incompatíveis para detectar anchoring, concept bleed e orientação version-mismatched.

Uma skill é depreciada ou volta à quarentena quando houver regressão de correção, incompatibilidade de versão, referência não resolvida, regressão de segurança ou invalidação do verificador.

## Métricas

Primárias:

- requirement pass rate;
- paired correctness delta.

Secundárias:

- tokens;
- latência de parede;
- chamadas de ferramenta;
- execuções de teste;
- arquivos alterados.

Segurança/escopo:

- regressões de segurança;
- violações de escopo;
- falhas atribuíveis a interferência contextual.

Não combine correção e custo em um único escalar sem também publicar os componentes originais.

## Generalização

Um único modelo não autoriza uma claim universal sobre skills. Um único scaffold não autoriza uma claim universal sobre orquestração. Resultados devem ser estratificados por `(modelo, scaffold, domínio, versão)` e só depois agregados com justificativa.

## Promoção

`quarantine -> candidate -> promoted` exige:

1. snapshot e ambiente identificados;
2. requisitos independentes do conteúdo da skill;
3. verificador determinístico com controle negativo;
4. baseline pareado sem skill;
5. repetição adequada à estocasticidade;
6. compatibilidade de versão demonstrada;
7. custo medido;
8. busca explícita por interferência contextual;
9. relatório de limitações e resultados negativos.

Nenhum agente autor da skill certifica a própria eficácia.

## Base de evidência

Este protocolo é informado por:

- Han et al., *SWE-Skills-Bench: Do Agent Skills Actually Help in Real-World Software Engineering?*, arXiv:2603.15401 (2026): tarefas em commits fixos, critérios explícitos, verificação determinística e contraste pareado; ganhos pequenos em média e regressões por interferência contextual.
- Li et al., *SkillsBench: Benchmarking How Well Agent Skills Work Across Diverse Tasks*, arXiv:2602.12670 (2026): heterogeneidade forte, deltas negativos em parte das tarefas e vantagem de skills focadas sobre documentação ampla.
- Yang et al., *SWE-agent: Agent-Computer Interfaces Enable Automated Software Engineering*, NeurIPS 2024: o desenho da interface/scaffold é variável experimental relevante.
- Ding et al., *Agent Skill Evaluation and Evolution: Frameworks and Benchmarks*, arXiv:2606.11435 (2026): evolução de skills deve ser evaluation-driven, com atenção a segurança, eficiência e generalização.
- Xu & Yan, *Agent Skills for Large Language Models: Architecture, Acquisition, Security, and the Path Forward*, arXiv:2602.12430 (2026): proveniência, ciclo de vida e permissões são parte do problema de segurança de skills.

As fontes motivam o desenho; não são prova de que este harness melhora qualidade. Essa claim requer corpus e experimento próprios.
