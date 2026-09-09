# Orquestração multirruntime

## Modelo

A arquitetura separa um núcleo normativo das traduções específicas de runtime:

```math
\mathrm{Runtime}_r = \mathrm{Core} + \mathrm{Projection}(\mathrm{Core},r).
```

O núcleo vive em `execution/` e `orchestration/`. As projeções de agentes e configuração vivem em `.claude/`, `.codex/`, `CLAUDE.md` e `AGENTS.md`.

Essa igualdade é arquitetural: significa que cada runtime recebe uma representação declarada do mesmo núcleo. Ela **não** implica equivalência semântica ou estatística entre Claude Code e Codex.

## Invariantes

- agentes de leitura e avaliação podem ocorrer em paralelo;
- nenhum escritor participa de grupo paralelo;
- escrita é serializada;
- `tdd` precede `implementador` no fluxo de mudança;
- revisão e refutação ocorrem depois da escrita;
- o autor não certifica a própria alteração;
- há no máximo duas rodadas de correção no registry atual;
- o estado terminal local é `CANDIDATE`;
- certificação pertence ao gate externo `verify-pr`.

Para qualquer grupo paralelo `G`:

```math
\sum_{n\in G}\mathrm{writes}(n)=0.
```

## Agentes

As fontes canônicas dos agentes ficam em `execution/agents/*.md`.

- Claude Code recebe wrappers em `.claude/agents/*.md`.
- Codex recebe wrappers em `.codex/agents/*.toml`.
- `orchestration/render.py` gera as duas projeções a partir do canônico e do registry; `orchestration/render.py --check` compara byte a byte o que está em disco com o que a geração produziria, sem escrever nada.

A convergência verificada é estrutural: existência, inventário e configuração declarada. Sandboxing, permission modes, worktrees, tool semantics e comportamento do modelo permanecem propriedades de cada runtime.

## Skills

Skills canônicas vivem em `execution/skills/` e são governadas por `orchestration/skill-policy.json` e `orchestration/evaluation-protocol.json`.

Elas **não são blanket-projected para todos os runtimes**. A política atual (`activation.default = "manual"` em `orchestration/skill-policy.json`, corrigida em G102/issue #46) exige compatibilidade, gatilho observável e evidência pareada para promoção. Uma futura projeção ou mecanismo automático de seleção de skills deve ser tratado como nova superfície experimental e validado antes de ser incorporado ao registry.

No fluxo de instalação global do Claude, as skills promovidas presentes no manifesto podem ser instaladas no destino global correspondente; isso não equivale a afirmar que existe hoje uma projeção de projeto `.agents/skills/` para Codex.

## Workflows

`investigation-only`, `standard-change` e `high-risk-change` são definidos em JSON em `orchestration/workflows/`; `orchestration/render.py --check` compara o inventário desse diretório com `registry.json["workflows"]` e reprova a divergência.

A escolha de qual workflow um risco do kernel (`execution/config/CLAUDE.md`, seção 7) aciona é declarada em `orchestration/risk-policy.json` e verificada pelo mesmo `orchestration/render.py --check`: o domínio vem da tabela do kernel, o contradomínio vem do diretório de workflows, e a política nunca se autoconfirma (ver ADR 0043).

O fluxo padrão mantém a separação:

```text
classify
  -> investigate/map
  -> plan
  -> RED
  -> implement
  -> tests
  -> review/refutation
  -> evidence
  -> CANDIDATE
```

Mudanças de alto risco acrescentam escrutínio de segurança, threat model e mecanismos adicionais de falsificação.

## Fronteiras de autoridade

Hooks, subagentes e verificações locais produzem feedback e evidência intermediária. Eles não são a autoridade externa de integração.

A propriedade pretendida é:

```math
\mathrm{Mergeable}(x)
\iff
\mathrm{Candidate}(x)
\land
\mathrm{ValidEvidence}(x)
\land
\mathrm{FreshEvidence}(x)
\land
\mathrm{ExternalAuthorization}(x).
```

## Limites

- projeções são estruturalmente verificadas, não demonstradas como comportamentalmente equivalentes;
- worktree ou sandbox declarado não é prova de isolamento do sistema operacional;
- política de usuário continua participando da cadeia de confiança fora do modo managed;
- CI é auditável, mas não hermética;
- ainda não existe corpus comparativo suficientemente amplo para provar eficácia externa;
- utilidade de skills permanece uma hipótese a ser medida por condição, modelo, scaffold e tarefa.
