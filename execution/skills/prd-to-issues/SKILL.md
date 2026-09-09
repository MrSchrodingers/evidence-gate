---
name: prd-to-issues
description: Quebra um PRD em issues GitHub independentes usando fatias verticais (tracer bullets). Cada issue eh pegavel por qualquer dev. Usar quando o usuario quiser converter PRD em issues, criar tickets de implementacao, ou quebrar PRD em work items. Skill anterior /prd-to-plan; em seguida, delegar ao agente tdd.
disable-model-invocation: true
---

# PRD para Issues GitHub

Quebra um PRD em issues GitHub independentes e pegiveis usando fatias verticais (tracer bullets).

> INVOCACAO MANUAL. Esta skill cria estado remoto com `gh issue create`. A documentacao oficial
> do Claude Code recomenda `disable-model-invocation: true` para workflows com side effects cuja
> temporizacao deve permanecer sob controle do usuario. A flag tambem remove a description do
> contexto automatico, reduzindo custo quando este workflow nao foi pedido explicitamente.

## Pipeline (Skills Relacionadas)

```
/write-a-prd → /prd-to-plan → [VOCE ESTA AQUI] → agente tdd
```

- **Skill anterior**: `/prd-to-plan` (plano de fases deve existir, ou o PRD diretamente)
- **Passo seguinte**: o agente `tdd` (implementar cada issue com red-green-refactor)

---

## Processo

### 1. Localizar o PRD

O PRD chega aqui em uma de duas formas, porque `/write-a-prd` grava localmente e nao publica
(G106, issue #50):

- **Ja existe como issue GitHub.** Peca ao usuario o numero da issue do PRD (ou URL). Se o PRD
  nao esta no contexto, busque com `gh issue view <number>` (com comentarios).
- **Existe apenas como arquivo local**, tipicamente `./prds/<slug>.md`. Publique-o ANTES de
  fatiar em issues: crie a issue do PRD a partir do conteudo do arquivo e use o numero devolvido
  como PRD pai no restante deste processo. A escrita remota continua sob decisao do operador,
  porque esta skill ja e `disable-model-invocation: true`.

Se existe um plano em `./plans/`, leia-o tambem — ele contem decisoes arquiteturais e fases ja validadas.

### 2. Explorar o Codebase (se necessario)

Se ainda nao explorou o codebase nesta sessao:
- [ ] Entender camadas de integracao existentes
- [ ] Verificar padroes de issues/PRs existentes no repo
- [ ] Checar labels e milestones disponiveis no GitHub

### 3. Criar Fatias Verticais

Se ja existe um plano (`./plans/`), use as fases como base para as issues. Caso contrario, quebre o PRD diretamente.

Cada issue eh uma fatia vertical FINA que corta TODAS as camadas de integracao de ponta a ponta.

As fatias podem ser classificadas como:
- **AFK** (Away From Keyboard): Implementavel e mergeavel sem interacao humana. Um agente AI ou dev pode pegar e entregar sozinho. **Prefira AFK sempre que possivel.**
- **HITL** (Human In The Loop): Requer decisao humana, revisao de design, ou aprovacao. Exemplos: decisao arquitetural, revisao de UX, aprovacao de stakeholder.

<regras-fatia-vertical>
- Cada fatia entrega um caminho ESTREITO mas COMPLETO por todas as camadas (schema, API, servico, UI, testes)
- Uma fatia completa eh demonstravel ou verificavel sozinha
- Prefira MUITAS fatias finas a poucas grossas
- Cada issue deve ser auto-contida: quem pegar deve conseguir implementar sem contexto extra
</regras-fatia-vertical>

### 4. Validar com o Usuario

Apresente a quebra proposta como lista numerada. Para cada fatia mostre:

- **Titulo**: Nome curto e descritivo
- **Tipo**: AFK / HITL
- **Bloqueada por**: Quais outras fatias (se alguma) devem ser concluidas antes
- **User stories cobertas**: Quais user stories do PRD esta fatia resolve
- **Estimativa**: P / M / G

Pergunte ao usuario:
- A granularidade esta adequada? (grosso demais / fino demais)
- As relacoes de dependencia estao corretas?
- Alguma fatia deve ser unida ou dividida?
- As classificacoes AFK/HITL estao corretas?
- Labels e milestone a usar?

Itere ate o usuario aprovar.

### 5. Criar as Issues no GitHub

Para cada fatia aprovada, crie uma issue usando `gh issue create`. Use o template abaixo.

Crie issues na ORDEM DE DEPENDENCIA (bloqueadores primeiro) para poder referenciar numeros reais no campo "Bloqueada por".

<template-issue>
## PRD Pai

#<numero-da-issue-do-prd>

## Tipo

AFK / HITL

## O que Construir

Descricao concisa desta fatia vertical. Descreva o comportamento ponta-a-ponta, NAO implementacao camada por camada. Referencie secoes especificas do PRD pai ao inves de duplicar conteudo.

### Contexto Tecnico

Decisoes arquiteturais relevantes (do PRD/plano):
- Padrao X se aplica a este modulo
- Schema segue a forma Y
- Fila Z eh usada para processamento async

## Criterios de Aceitacao

- [ ] Criterio 1
- [ ] Criterio 2
- [ ] Criterio 3
- [ ] Testes escritos e passando
- [ ] Code review aprovado (o agente `revisor-codigo`)

## Bloqueada por

- Bloqueada por #<numero-da-issue> (se alguma)

Ou "Nenhuma — pode comecar imediatamente" se sem bloqueadores.

## User Stories Atendidas

Referencia por numero do PRD pai:

- User story 3
- User story 7

## Guia de Implementacao

Sugestao de abordagem (sem caminhos de arquivo):
1. Implementar com o agente `tdd` (red-green-refactor)
2. Seguir padroes existentes do modulo X
3. Adicionar observabilidade (metricas, logs, traces)
4. Revisar com o agente `revisor-codigo` antes de merge

## Estimativa

P / M / G

</template-issue>

NAO feche ou modifique a issue do PRD pai.

Apos criar todas as issues, apresente um resumo:

```
Issues criadas:
#101 - [AFK] Criar modelo e migration (P) — sem bloqueio
#102 - [AFK] Endpoint REST basico (P) — bloqueada por #101
#103 - [AFK] Worker de processamento (M) — bloqueada por #101
#104 - [HITL] Tela de listagem (M) — bloqueada por #102
#105 - [AFK] Testes de integracao (P) — bloqueada por #102, #103
```

### 6. Proximos Passos

Sugira ao usuario:
- Priorizar as issues sem bloqueio para comecar imediatamente
- Usar o agente `tdd` para implementar cada issue
- Usar o agente `revisor-codigo` antes de cada merge