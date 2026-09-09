# ADR 0024 — Núcleo canônico e projeções multirruntime

- Status: aceito
- Data: 2026-08-06

## Contexto

Copiar manualmente configuração para Claude Desktop, Claude CLI e Codex criaria três estados desejados independentes e sem convergência.

## Decisão

Manter fonte canônica em `execution/` e `orchestration/` e gerar projeções Claude e Codex, documentação e grafo executável. O renderizador possui modo de convergência e `--check`.

## Restrições

- leitura pode ser paralela; escrita é serial;
- `tdd` e `implementador` são escritores isolados;
- autor não certifica;
- correção limitada a duas rodadas;
- estado local máximo `CANDIDATE`;
- `verify-pr` continua certificação externa.

## Consequências

Portabilidade auditável e menor drift, com custo de tornar o renderizador crítico e exigir atualização quando runtimes mudarem. Equivalência sintática não prova equivalência comportamental.

## Errata 2026-09-08

**G105 -** a decisão dizia "O renderizador possui modo de convergência e `--check`." Medido:
`orchestration/render.py` nunca teve modo de convergência - era verificador puro desde o
commit inicial (2 commits no histórico do arquivo, e a versão inicial já comparava, nunca
escrevia), e `--check` era inerte: `argparse.ArgumentParser().parse_args()` tinha o retorno
descartado, `args.check` não aparecia em lugar nenhum do arquivo, e as invocações com e sem a
flag produziam a mesma saída e o mesmo exit code em qualquer estado de árvore testado. As dez
projeções em `.claude/agents/*.md` e `.codex/agents/*.toml` eram mantidas manualmente contra o
que este ADR e `docs/architecture/orquestracao-multirruntime.md` afirmavam.

A decisão passa a ler: `orchestration/render.py` lê `execution/agents/*.md` e
`orchestration/registry.json` (schema v2, com `codex_model`, `codex_reasoning_effort` e
`projection_profiles` por agente) e gera as duas projeções; `--check` gera em memória e compara
byte a byte com o que está em disco, sem escrever nada, e sai 1 na primeira divergência.

Isto fecha a classe de divergência entre canônico e projeção que este ADR registrava como
fechada e não estava: `description`, `tools`, `model` e os campos runtime-only
(`permissionMode`, `maxTurns`, `memory`, `isolation`, `sandbox_mode`, modelo e esforço de
raciocínio do Codex) passam a ter procedência única e verificável, em vez de duas cópias
mantidas por disciplina humana. `color` do canônico permanece deliberadamente fora da
projeção - é rótulo de UI do Claude Code sem contraparte documentada em nenhum dos dois
runtimes de projeção. Ver `evidence/corpus/agente-x-defeito.json` (`G105`) e
`tests/unit/runtime-ports.sh`.
