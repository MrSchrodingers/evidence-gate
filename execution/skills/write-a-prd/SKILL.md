---
name: write-a-prd
description: Cria um PRD (Product Requirements Document) completo atraves de entrevista com o usuario, exploracao do codebase e design de modulos. Usar quando o usuario quiser escrever um PRD, criar documento de requisitos, planejar uma feature nova, ou mencionar "PRD". Apos o PRD, sugerir /prd-to-plan e /prd-to-issues.
---

# Escrever um PRD

Skill para criar PRDs completos e acionaveis. O PRD eh o ponto de partida do pipeline de desenvolvimento — dele derivam planos, issues e implementacao.

## Pipeline Completo (Skills Relacionadas)

```
/write-a-prd → /prd-to-plan → /prd-to-issues → agente tdd (implementacao)
       ↑                                              ↑
  /grill-me (stress-test)                    a triagem de issue (bugs)
```

Apos criar o PRD, sugira ao usuario:
- `/prd-to-plan` para quebrar em fases de implementacao
- `/prd-to-issues` para criar issues independentes no GitHub

---

## Processo (TODOS os passos sao OBRIGATORIOS)

### 1. Capturar o Problema

Peca ao usuario uma descricao LONGA e detalhada contendo:

- **Dor atual**: Qual problema existe hoje? Quem sofre com ele?
- **Impacto**: Qual o custo de nao resolver? (tempo perdido, erros, receita perdida, risco operacional)
- **Ideias de solucao**: Qualquer rascunho mental que o usuario ja tenha
- **Restricoes conhecidas**: Limitacoes tecnicas, de prazo, de budget, regulatorias
- **Usuarios afetados**: Quem sao os atores? (admin, operador, cliente final, sistema externo, job automatizado)
- **Volume esperado**: Quantos registros, requests/segundo, usuarios simultaneos?

NAO prossiga ate ter uma descricao substancial. Se o usuario for vago, faca perguntas direcionadas:
- "Quantas vezes por dia esse problema ocorre?"
- "Quem eh o primeiro a perceber quando da errado?"
- "Existe algum workaround manual hoje?"

### 2. Explorar o Codebase

Antes de qualquer decisao, explore o repositorio para entender o estado atual:

- [ ] Identificar o padrao arquitetural vigente (MVC, Event-Driven, Microservices, etc.)
- [ ] Verificar dependencias relevantes (`requirements.txt`, `package.json`, `pyproject.toml`)
- [ ] Mapear modulos existentes que serao afetados ou reutilizados
- [ ] Verificar se ja existe codigo parcial, branches abandonadas ou tentativas anteriores
- [ ] Checar testes existentes na area afetada (cobertura, tipo, qualidade)
- [ ] Revisar commits recentes nos arquivos relevantes (`git log --oneline -20`)
- [ ] Identificar padroes e convencoes do projeto (naming, estrutura de pastas, estilo de API)
- [ ] Verificar se ha ADRs (Architecture Decision Records) relevantes em `docs/adr/`

Use o Agent tool com subagent_type=Explore para investigacao profunda. NAO confie apenas nas afirmacoes do usuario — verifique no codigo.

### 3. Entrevista Implacavel

Entreviste o usuario sobre CADA aspecto do plano ate atingir entendimento compartilhado. Percorra cada galho da arvore de decisao, resolvendo dependencias uma a uma.

**Esta etapa eh equivalente a invocar `/grill-me` (chamado de entrevistador no contexto do projeto).**

**Tecnicas de entrevista:**

- **Descida em profundidade**: Para cada decisao, pergunte "E se X acontecer?" e "Qual o comportamento esperado quando Y?"
- **Cenarios limite**: "O que acontece com 0 itens? Com 10.000? Com dados invalidos? Com campos nulos?"
- **Integracao**: "Como isso interage com [modulo existente]? Quem consome essa saida? Quem produz essa entrada?"
- **Falha e resiliencia**: "O que acontece se o servico externo cair? Se a rede falhar no meio? Se o worker morrer?"
- **Concorrencia**: "O que acontece se dois usuarios fizerem isso ao mesmo tempo? Race conditions?"
- **Migracao**: "Como os dados existentes serao tratados? Precisa de migracao? Backfill?"
- **Rollback**: "Se der errado em producao, como revertemos? Feature flag? Blue-green?"
- **Observabilidade**: "Como vamos saber se esta funcionando? Metricas? Alertas? Dashboard?"
- **Seguranca**: "Quem pode acessar? Precisa de autorizacao? Auditoria?"

**Regra**: Se uma pergunta pode ser respondida explorando o codebase, explore o codebase em vez de perguntar ao usuario.

**Quando parar**: Quando ambos concordarem que todas as ramificacoes foram resolvidas e nao ha ambiguidades restantes.

### 4. Design de Modulos

Esboce os modulos principais que precisam ser construidos ou modificados:

- [ ] Identifique **modulos profundos** (deep modules) — interface simples, implementacao rica
- [ ] Para cada modulo, defina: responsabilidade unica, interface publica, dependencias
- [ ] Busque oportunidades de extrair modulos testaveis em isolamento
- [ ] Identifique modulos rasos (shallow) existentes que podem ser aprofundados
- [ ] Mapeie dependencias entre modulos (grafo de dependencia)

**Modulo Profundo vs Raso (John Ousterhout, "A Philosophy of Software Design"):**

```
PROFUNDO (bom):              RASO (evitar):
+------------------+         +--------------------------------+
|  Interface Simples|         |    Interface Grande            |
+------------------+         +--------------------------------+
|                  |         | Implementacao Fina             |
| Implementacao    |         +--------------------------------+
| Rica e Complexa  |
|                  |
+------------------+
```

Apresente os modulos ao usuario e confirme:
- Os modulos correspondem as expectativas?
- Quais modulos precisam de testes?
- Algum modulo esta faltando ou sobrando?
- A granularidade esta adequada?

Se o design de interface for complexo, sugira um passo dedicado de design de interface (nao ha comando instalado para isso) para explorar alternativas em paralelo.

### 5. Definir Criterios de Aceitacao

Para cada user story ou grupo de stories, defina criterios verificaveis:

- Cada criterio deve ser testavel (sim/nao, sem ambiguidade)
- Inclua criterios de **performance** quando relevante (latencia P95, throughput)
- Inclua criterios de **observabilidade** (logs estruturados, metricas Prometheus, traces OTEL)
- Inclua criterios de **resiliencia** (circuit breaker, retry com backoff, DLQ)
- Inclua criterios de **idempotencia** para operacoes de escrita

### 6. Avaliar Riscos e Dependencias

Antes de finalizar, avalie:

- [ ] **Riscos tecnicos**: Integracao com APIs externas, migracao de dados, performance sob carga
- [ ] **Dependencias bloqueantes**: Outras features/PRDs que precisam estar prontas antes
- [ ] **Impacto em features existentes**: Regressoes potenciais, breaking changes
- [ ] **Necessidade de feature flags**: Rollout gradual? Canary deploy?
- [ ] **Estimativa de complexidade**: P (1-2 dias) / M (3-5 dias) / G (1-2 semanas) / XG (>2 semanas)
- [ ] **Necessidade de ADR**: Decisao arquitetural significativa? Documentar em `docs/adr/`

### 7. Redigir o PRD

Uma vez com entendimento completo, use o template abaixo e grave o resultado como arquivo
Markdown em `./prds/<slug>.md` (slug derivado do titulo do problema, minusculo, hifenizado),
espelhando o padrao de saida local de `/prd-to-plan`. Este arquivo eh o artefato final desta
skill; publicacao como issue remota nao faz parte deste passo e fica a cargo de `/prd-to-issues`,
quando o operador decidir acionar essa etapa.

<prd-template>

## Declaracao do Problema

Descricao do problema na perspectiva do usuario. Inclua:
- Quem sofre com o problema (atores envolvidos)
- Qual o impacto atual (quantificado se possivel: tempo, dinheiro, erros)
- Contexto que levou a essa necessidade
- Volume/frequencia do problema

## Solucao Proposta

Descricao da solucao na perspectiva do usuario. Inclua:
- Visao geral da solucao (1-2 paragrafos)
- Beneficios esperados (quantificados)
- Como o usuario final vai interagir com a solucao
- Diagrama de fluxo simplificado (Mermaid se aplicavel)

## User Stories

Lista LONGA e numerada de user stories. Cada uma no formato:

1. Como um(a) <ator>, eu quero <funcionalidade>, para que <beneficio>

<exemplo>
1. Como um operador de cobranca, eu quero visualizar o saldo atualizado de cada pasta, para tomar decisoes informadas sobre negociacao
2. Como um administrador, eu quero receber alertas quando o circuit breaker abrir, para agir antes que afete os clientes
3. Como o sistema de processamento batch, eu quero reprocessar itens da DLQ automaticamente, para reduzir intervencao manual
</exemplo>

A lista deve ser EXTENSIVA e cobrir:
- Fluxo principal (happy path)
- Fluxos alternativos e edge cases
- Tratamento de erros e falhas
- Permissoes, autorizacao e multi-tenancy
- Observabilidade, monitoramento e alertas
- Auditoria e rastreabilidade
- Performance e limites operacionais

## Criterios de Aceitacao

Para cada user story ou grupo, criterios verificaveis:

### Funcionalidade
- [ ] Criterio 1 (testavel: sim/nao)
- [ ] Criterio 2

### Performance
- [ ] Latencia P95 < X ms
- [ ] Throughput > Y items/minuto

### Resiliencia
- [ ] Comportamento X quando servico externo cair
- [ ] Retry com backoff exponencial + jitter
- [ ] Itens com erro permanente vao para DLQ

### Observabilidade
- [ ] Logs estruturados com trace_id
- [ ] Metricas Prometheus para contadores e histogramas
- [ ] Spans OTEL com atributos de negocio

## Decisoes de Implementacao

Lista de decisoes tecnicas tomadas durante a elaboracao:

- Modulos que serao construidos/modificados (sem caminhos de arquivo)
- Interfaces publicas desses modulos
- Clarificacoes tecnicas do desenvolvedor
- Decisoes arquiteturais (com justificativa e alternativas rejeitadas)
- Mudancas de schema / migrations
- Contratos de API (endpoints, payloads, status codes)
- Interacoes entre componentes (sync vs async, filas, eventos)
- Estrategia de migracao de dados (se aplicavel)
- Estrategia de deploy (feature flag, canary, blue-green)

NAO inclua caminhos de arquivo especificos ou snippets de codigo.

## Decisoes de Teste

- Filosofia: testar comportamento externo, nao detalhes de implementacao
- Quais modulos serao testados e com que tipo de teste (unitario, integracao, e2e)
- Estrategia de mocking: apenas em fronteiras de sistema (APIs externas, tempo, randomness)
- Testes existentes similares no codebase (prior art)
- Infraestrutura necessaria para testes (test DB, fixtures, factories)

## Analise de Riscos

| Risco | Probabilidade | Impacto | Mitigacao |
|-------|---------------|---------|-----------|
| ... | Alta/Media/Baixa | Alto/Medio/Baixo | ... |

## Fora de Escopo

Descricao explicita do que NAO faz parte deste PRD:
- Features relacionadas mas nao incluidas
- Otimizacoes futuras identificadas mas adiadas
- Integracoes que serao tratadas em PRDs separados

## Proximos Passos

Apos aprovacao deste PRD:
1. `/prd-to-plan` — criar plano de implementacao por fases (tracer bullets)
2. `/prd-to-issues` — quebrar em issues independentes no GitHub
3. o agente `tdd` — implementar cada issue via ciclos red-green-refactor
4. o agente `revisor-codigo` — revisar antes de merge

## Notas Adicionais

Quaisquer notas extras, referencias, links para docs externos, ou decisoes pendentes.

</prd-template>

---

## Dicas para PRDs de Alta Qualidade

1. **Seja especifico**: "O sistema deve ser rapido" eh ruim. "A API deve responder em < 200ms no P95" eh bom.
2. **Pense em falha**: Todo sistema falha. Documente o que acontece quando falha.
3. **Quantifique**: Numeros concretos vencem adjetivos vagos.
4. **Teste mental**: Para cada user story, imagine-se implementando e testando. Se ficou ambiguo, reescreva.
5. **Evite solucoes no problema**: A declaracao do problema nao deve prescrever a solucao.
6. **Pense em observabilidade**: Se voce nao consegue medir, nao consegue gerenciar.
7. **Idempotencia**: Toda operacao de escrita deve ser segura para re-execucao.
