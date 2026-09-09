---
name: prd-to-plan
description: Transforma um PRD em plano de implementacao multi-fase usando tracer bullets (fatias verticais). Salva como arquivo Markdown em ./plans/. Usar quando o usuario quiser quebrar um PRD em fases, criar plano de implementacao, ou mencionar "tracer bullets". Skill anterior /write-a-prd, skill seguinte /prd-to-issues.
---

# PRD para Plano de Implementacao

Transforma um PRD em plano de implementacao por fases usando fatias verticais (tracer bullets). Saida: arquivo Markdown em `./plans/`.

## Pipeline (Skills Relacionadas)

```
/write-a-prd → [VOCE ESTA AQUI] → /prd-to-issues → agente tdd
```

- **Skill anterior**: `/write-a-prd` (o PRD deve existir antes)
- **Skill seguinte**: `/prd-to-issues` (quebrar fases em issues GitHub)

---

## Processo

### 1. Confirmar o PRD no Contexto

O PRD deve estar na conversa. Se nao estiver:
- Peca o numero da issue GitHub e busque com `gh issue view <number>`
- Ou peca ao usuario para colar/apontar o arquivo

Valide que o PRD tem no minimo:
- [ ] Declaracao do problema
- [ ] User stories
- [ ] Decisoes de implementacao

Se faltar algo critico, sugira ao usuario voltar ao `/write-a-prd`.

### 2. Explorar o Codebase

Se ainda nao explorou o codebase nesta sessao, faca agora:

- [ ] Arquitetura atual e camadas de integracao (API, servicos, modelos, filas, frontend)
- [ ] Padroes existentes que as novas fases devem seguir
- [ ] Pontos de integracao entre backend e frontend
- [ ] Infraestrutura de testes existente (frameworks, fixtures, factories)
- [ ] Estado atual do schema de banco (migrations recentes)

### 3. Identificar Decisoes Arquiteturais Duraveis

Antes de fatiar, identifique decisoes de alto nivel que NAO mudam entre fases:

- **Rotas / URL patterns**: Estrutura de endpoints REST
- **Schema de banco**: Forma das tabelas, indices, constraints
- **Modelos-chave**: Entidades de dominio e seus relacionamentos
- **Autenticacao / autorizacao**: Abordagem e permissoes
- **Fronteiras de servicos externos**: APIs, filas, webhooks
- **Estrategia de observabilidade**: Metricas, traces, logs
- **Convencoes de naming**: Patterns para tasks, queues, signals

Estas decisoes vao no cabecalho do plano para que toda fase possa referencia-las.

### 4. Criar Fatias Verticais (Tracer Bullets)

Quebre o PRD em fases. Cada fase eh uma fatia vertical FINA que corta TODAS as camadas de integracao de ponta a ponta.

<regras-fatia-vertical>
- Cada fatia entrega um caminho ESTREITO mas COMPLETO por todas as camadas (schema, API, servico, UI, testes)
- Uma fatia completa eh demostravel ou verificavel por si so
- Prefira MUITAS fatias finas a poucas fatias grossas
- NAO inclua nomes de arquivo, funcoes ou detalhes de implementacao que mudam entre fases
- INCLUA decisoes duraveis: rotas, formas de schema, nomes de modelos
- A Fase 1 SEMPRE deve ser o "tracer bullet" — o caminho mais fino possivel ponta-a-ponta que prove que a arquitetura funciona
- Fases posteriores adicionam largura (mais casos, mais features) sobre o esqueleto da Fase 1
</regras-fatia-vertical>

**Anti-pattern — Fatias Horizontais (NUNCA faca isso):**
```
ERRADO (horizontal):
  Fase 1: Todas as migrations
  Fase 2: Toda a API
  Fase 3: Todo o frontend
  Fase 4: Todos os testes

CORRETO (vertical):
  Fase 1: 1 migration + 1 endpoint + 1 tela + 1 teste (tracer bullet)
  Fase 2: Proximo caso de uso ponta-a-ponta
  Fase 3: Proximo caso de uso ponta-a-ponta
```

### 5. Validar com o Usuario

Apresente a quebra proposta como lista numerada. Para cada fase mostre:

- **Titulo**: Nome curto e descritivo
- **User stories cobertas**: Quais user stories do PRD esta fase resolve
- **Camadas tocadas**: Quais camadas de integracao sao atravessadas
- **Estimativa**: P / M / G (esforco relativo)
- **Dependencias**: Quais fases devem estar prontas antes

Pergunte ao usuario:
- A granularidade esta adequada? (grosso demais / fino demais)
- Alguma fase deve ser unida ou dividida?
- A ordem de prioridade faz sentido?
- O tracer bullet (Fase 1) eh realmente o caminho minimo?

Itere ate o usuario aprovar.

### 6. Escrever o Arquivo do Plano

Crie `./plans/` se nao existir. Escreva o plano como Markdown nomeado pela feature (ex: `./plans/sincronizacao-hdi.md`).

<template-plano>
# Plano: <Nome da Feature>

> PRD de origem: <identificador ou link para a issue>
> Data: <data de criacao>
> Status: Pendente

## Decisoes Arquiteturais

Decisoes duraveis que se aplicam a TODAS as fases:

- **Rotas**: ...
- **Schema**: ...
- **Modelos-chave**: ...
- **Autenticacao**: ...
- **Observabilidade**: ...
- **Filas/Workers**: ...
- (adicione/remova secoes conforme necessario)

---

## Fase 1: <Titulo> (Tracer Bullet)

**User stories**: #1, #3, #7 (do PRD)
**Estimativa**: P / M / G
**Depende de**: Nenhuma (primeira fase)

### O que construir

Descricao concisa desta fatia vertical. Descreva o comportamento ponta-a-ponta, NAO implementacao camada por camada. Esta fase deve ser o caminho MAIS FINO possivel que prova que a arquitetura funciona.

### Criterios de aceitacao

- [ ] Criterio 1
- [ ] Criterio 2
- [ ] Criterio 3
- [ ] Testes passando para esta fatia

### Notas de implementacao

Orientacoes duraveis (sem caminhos de arquivo):
- Padrao X deve ser seguido para Y
- Decisao Z foi tomada por motivo W

---

## Fase 2: <Titulo>

**User stories**: #2, #5 (do PRD)
**Estimativa**: P / M / G
**Depende de**: Fase 1

### O que construir

...

### Criterios de aceitacao

- [ ] ...

### Notas de implementacao

...

---

<!-- Repetir para cada fase -->

## Resumo

| Fase | Titulo | Stories | Estimativa | Depende de |
|------|--------|---------|------------|------------|
| 1 | ... | #1,#3 | P | - |
| 2 | ... | #2,#5 | M | Fase 1 |
| 3 | ... | #4,#6 | G | Fase 2 |

## Proximos Passos

1. Aprovar este plano
2. Invocar `/prd-to-issues` para criar issues no GitHub a partir destas fases
3. Implementar cada issue via o agente `tdd` (ciclos red-green-refactor)
</template-plano>
