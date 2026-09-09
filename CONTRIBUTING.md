# Contribuição

## Unidade de mudança

Cada pull request deve ter uma tese verificável e uma fronteira de escopo. Mudanças de
instalador privilegiado, autorização, supply chain, parser ou workflow de CI devem ser
separadas de refatorações editoriais sempre que a separação preservar o comportamento.

Prefira PRs pequenos o suficiente para revisão adversarial. Um PR grande deve justificar por
que a decomposição criaria estados intermediários inválidos ou destruiria a atribuição dos
testes.

## Contrato mínimo

Toda nova garantia deve incluir:

1. claim e limite explícitos;
2. reprodução ou observação que motive a mudança;
3. teste que falhe pelo motivo correto antes da correção;
4. caso de borda e controle negativo;
5. mutante atribuível quando a garantia for estrutural;
6. atualização do manifesto e das projeções geradas, quando aplicável;
7. execução local documentada e `verify-pr` verde no SHA final.

Use `NOT_VERIFIED` quando uma dependência, plataforma ou pré-condição impedir o experimento.
Não transforme ausência de tratamento em PASS.

## Skills e mudanças de scaffold

Adicionar um arquivo de skill não equivale a promover uma capacidade. Toda skill nova ou
substancialmente alterada começa em `quarantine` e deve obedecer a
`orchestration/skill-policy.json` e `docs/method/skill-evaluation-protocol.md`.

Para promoção, o PR deve incluir ou apontar para evidência de:

- baseline pareado `without_skill`/`with_skill` no mesmo snapshot;
- requisito autocontido e independente do conteúdo da skill;
- verificador determinístico com controle negativo;
- compatibilidade de versão e proveniência;
- custo e latência;
- busca explícita por interferência contextual;
- repetição suficiente quando o agente for estocástico.

Uma mudança de modelo, scaffold, seletor ou orçamento invalida a interpretação causal de um
contraste de skill se não for controlada. Resultados nulos ou negativos não podem ser omitidos.
Skills auto-geradas permanecem em quarentena até avaliação externa.

## Higiene do repositório

Fixtures pertencem à suíte que as utiliza; não devem ser deixadas soltas na raiz. Bootstrap,
artefatos de transporte e workflows temporários devem ser removidos no mesmo PR que os usa.
`tests/unit/repository-hygiene.sh` mantém esse contrato executável.

## Fluxo recomendado

```bash
python3 orchestration/render.py
bash install/manifest.sh install/manifest.lock
python3 orchestration/render.py --check
python3 tests/unit/methodology.py
bash tests/unit/repository-hygiene.sh
bash tests/unit/runtime-ports.sh
bash tests/unit/managed.sh
bash tests/mutation/install.sh
bash scripts/status.sh
```

A bateria completa de `tests/unit/` roda com `bash tests/unit/run.sh` (despacho por disco de
`tests/unit/*.sh` e `*.py`, com agregação de exit code por suíte). As suítes de mutação
continuam listadas individualmente em `.github/workflows/verify-pr.yml`.

## Commits e revisão

Use Conventional Commits em português do Brasil.

O implementador não certifica a própria mudança. Revisores devem examinar arquivos, comandos
e saídas reais. O estado final de uma sessão é `CANDIDATE`; merge depende do gate externo.
