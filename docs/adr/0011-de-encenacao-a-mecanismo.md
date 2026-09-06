# ADR 0011 - De encenacao a mecanismo: reforma v2 do Colegio Analitico

- Data: 2026-07-31
- Status: aceito
- Substitui parcialmente: 0002 (persona), 0004 (colegiado visivel por default), 0008 (voz nos agentes)
- Preserva e amplia: 0010 (gate de conclusao ancorado em execucao)

## Contexto

A config v1.7.0 pedia que toda resposta tecnica fosse escrita como um colegiado de vozes
rotuladas (`[Arquiteto]`, `[Auditor]`, ...), com contraditorio visivel por default, e cobrava
por disciplina um pipeline de 14 agentes e um gate de 10 itens. O custo era pago em toda
sessao e em todo prompt. Este ADR revisa esse desenho contra medicao e contra fonte primaria.

## O achado que forcou a revisao: o gate C7 nunca se aplicou ao proprio autor

A Diretriz 13.1 exige (item C7) que todo numero, autor, ano e URL seja conferido na fonte
primaria. Auditamos 5 citacoes load-bearing da propria config contra a fonte:

| Citacao | Verificacao |
|---|---|
| `arXiv:2606.09863` -> "false success 45-89%", no hook de TODO prompt | FALSO. O paper reporta 45-48% (tau2-bench single-control), 3% (dual-control telecom), 75.8% (AppWorld). Nao existe a faixa 45-89%. |
| `Wang&Pradel ICSE'26` -> "~28-30% diverge" | NAO LOCALIZADO. |
| `arXiv:2604.02460` -> "SE-Agent 54% vs AgentOrchestra 3%, custo 22x" | MISATRIBUIDO. O identificador corresponde a "Single-Agent LLMs Outperform Multi-Agent Systems on Multi-Hop Reasoning Under Equal Thinking Token Budgets" (Tran e Kiela). Direcao compativel, numeros inexistentes. |
| `arXiv:2603.05744` -> degradacao por auto-augmentacao em SWE-bench Verified | NAO CONSTA no paper. |
| `arXiv:2603.29919` (SkillReducer) | CONFIRMADO verbatim: 55.315 skills, 48%/39% de compressao, +2.8%. |

Quatro de cinco falharam, sob vigilancia nominal e continua da regra que as proibia. Isto e o
falso rigor que a Diretriz 3.1 define como pior que a ausencia de rigor - cometido pelo
documento que o define. Conclusao operacional: **enunciar uma regra de verificacao nao a
executa.** Regra que precisa valer sempre tem de ser mecanismo, nao texto.

## Por que a voz rotulada nao e contraditorio

Uma "voz critica" escrita dentro da mesma resposta que propos a solucao compartilha pesos,
contexto e amostragem com ela. Nao ha independencia: a objecao do `[Auditor]` e amostrada
condicionada a tese do `[Arquiteto]` ja presente no contexto. Ganho de ensemble exige
descorrelacao de erro; aqui a correlacao e 1 por construcao.

> **ERRATA, 2026-08-12 (onda 10).** A frase acima permanece como foi escrita, porque este
> documento e registro datado - mas a ultima clausula esta ERRADA e nao deve ser citada.
> `correlacao 1` e afirmacao quantitativa forte, e compartilhar pesos, contexto e amostragem
> NAO implica correlacao perfeita de erros. Nenhuma medicao deste repositorio estimou essa
> quantidade. A formulacao correta: revisores derivados do mesmo modelo e do mesmo contexto
> exibem erro em MODO COMUM e dependencia substancial, de magnitude NAO MEDIDA aqui; separacao
> de contexto compra independencia PROCEDIMENTAL parcial, nao independencia estatistica.
>
> A decisao que este ADR tomou continua valendo, e por argumento mais fraco e suficiente: sem
> sinal externo nao ha o que descorrelacione, e a evidencia de Huang et al. citada logo abaixo
> sustenta a conclusao sem precisar de nenhum coeficiente. O defeito foi usar um numero como
> selo de forca onde o argumento ja se sustentava sem ele - o que a §2 da config global proibe,
> e que esta serie de ADRs documenta ter cometido varias vezes.
>
> Apontado por auditoria externa em 2026-08-12. Estimar a quantidade de verdade exigiria medir
> `P(R_i=1, R_j=1 | defeito)` contra `P(R_i=1|defeito) P(R_j=1|defeito)` sobre um corpus de
> defeitos conhecidos - trabalho registrado como pendente, nao realizado. Correcoes irmas em
> `execution/agents/refutador.md` e na §3 da config global do operador.

Isso tem nome na literatura: e **auto-correcao intrinseca**, definida por Huang et al.,
"Large Language Models Cannot Self-Correct Reasoning Yet" (ICLR 2024, arXiv:2310.01798) como "an LLM attempts to
correct its initial responses based solely on its inherent capabilities, without the crutch of
external feedback", com o resultado de que "LLMs struggle to self-correct their responses
without external feedback, and at times, their performance even degrades after self-correction".
A config ja citava esse paper - para justificar o gate de execucao - sem notar que ele tambem
indicta as vozes.

Criterio organizador adotado, de Li, *AI Agents in Depth* (Tabela 10-2): **a colaboracao
introduz informacao nova que um agente sozinho nao obteria durante a geracao?**

| Modo | Informacao nova? | Efeito |
|---|---|---|
| Reler a propria saida em outro papel | Nao | Geralmente inutil ou prejudicial |
| Agentes debatendo o mesmo texto | Nao | Equivale a um agente com o mesmo orcamento |
| Revisor usando resultado de EXECUCAO | Sim | Melhora significativa |
| Revisor usando SCREENSHOT renderizado | Sim | Melhora significativa |
| Revisor usando FERRAMENTA externa | Sim | Melhora significativa |

Lastro das duas ultimas linhas, conferido na fonte: RLEF (Gehring et al., arXiv:2410.02089)
mostra que feedback de execucao reduz em uma ordem de grandeza as amostras necessarias;
WebGen-Agent (Lu et al., arXiv:2509.22644) eleva o Claude 3.5 Sonnet de **26.4% para 51.9%** no
WebGen-Bench com feedback visual multi-nivel.

Ressalva honesta que enfraquece um argumento anterior: Zheng et al. (EMNLP Findings 2024,
"When 'A Helpful Assistant' Is Not Really Helpful") mediu 162 personas sobre 2.410 questoes
**fatuais**. Nao cobre raciocinio nem geracao de codigo. Logo esse paper NAO sustenta "persona
nao ajuda em revisao de codigo" - sustenta apenas que nao ajuda em recall fatual. O argumento
que sustenta esta decisao e o de Huang et al. e o de informacao nova, nao o de Zheng et al.

## Correcao de um numero deste proprio trabalho

Afirmou-se no diagnostico inicial que o hook por prompt gastava "~36,6k tokens numa sessao de
40 turnos". Isso superestima o custo de FATURAMENTO. A saida de um hook UserPromptSubmit e
anexada ao FIM do contexto, nao ao prefixo; o prefixo permanece byte-a-byte estavel e continua
elegivel a cache. As copias anteriores sao lidas do cache, nao recomputadas (Li, *AI Agents in
Depth*, secao 2.3: alterar o prefixo invalida o cache e multiplica latencia e custo; anexar ao
fim, nao).

O custo real da injecao repetida e **ocupacao de janela de contexto e diluicao de atencao**,
nao dinheiro. Isso nao enfraquece a decisao - a fundamenta melhor: o motivo de encolher e
qualidade de adesao (densidade de instrucao degrada a adesao; omissao e a falha dominante),
nao economia. Corolario de desenho que passa a valer: conteudo estavel vai para o prefixo
(CLAUDE.md, carregado uma vez, cacheavel); conteudo variavel vai para o fim (hook), e por isso
mesmo precisa ser pequeno.

## Decisao

1. **Remover o colegiado por default.** Sem vozes rotuladas obrigatorias. As lentes viram
   checklist de PERGUNTAS no CLAUDE.md (a coluna que sempre carregou o valor).
2. **Criar o agente `refutador`** (funde `cetico`, `insight`, `revisor-critico`): contexto
   separado, le o `git diff` CRU antes de qualquer resumo, prompt de refutacao, veredito
   calibrado. E a unica forma de contraditorio com descorrelacao real.
3. **Lastrear em ferramenta os agentes que a comportam.** `auditor-seguranca` executa
   `ruff --select S` (flake8-bandit), `pip-audit`, `npm audit` e busca de segredo no historico
   antes de opinar, e prioriza por KEV/EPSS/alcancabilidade, nao por CVSS nominal.
   `revisor-frontend` renderiza a tela, roda `axe`, e audita a lacuna semantica que passa na
   checagem automatica. `analista-otimalidade` compara com o limite inferior do problema e mede
   com `cProfile`/`timeit`/`EXPLAIN ANALYZE`.
4. **Agentes: 14 -> 10.** Removidos por redundancia de fonte de descorrelacao: `cetico`,
   `insight`, `revisor-critico` (funde em `refutador`); `continuidade` e `revisor-consistencia`
   (convencao cabe no `revisor-codigo`).
   CORRECAO (ADR 0015, achado 7): a justificativa original dizia que deadcode e "mecanizavel
   por hook", e ISSO ERA FALSO como estava - `ruff` nao resolve nomes entre modulos, entao a
   cobertura de `continuidade` (referencia pendente entre arquivos) foi removida sem
   substituto. A lacuna foi fechada depois, com `mypy` no `poka-yoke-lint.sh`, restrito a
   classe "has no attribute / is not defined". Antes desse conserto, a remocao era regressao.
5. **Mover regra de texto para hook** sempre que a regra for verificavel:
   - `risk-trigger.sh` (PostToolUse): classifica a superficie tocada pelo CONTEUDO escrito e
     entrega o gatilho de revisao. O gating deixa de depender de a sessao classificar de cabeca.
   - `subagent-contract.sh` (SubagentStop): exige RESULTADO e EVIDENCIA com ancora real
     (arquivo:linha, comando, exit code). Antes era disciplina pura.
   - `verify-gate.sh` (Stop): auto-detecta o comando de verificacao. Antes exigia
     `.claude/verify-cmd` e ficava inerte na maioria dos repos - o melhor mecanismo era o menos
     acionado.
6. **CLAUDE.md: 46.357 -> 10.288 bytes.** So fato e regra invariante; procedimento vira skill.
7. **Skills: 25 -> 2 ativas** (+ `/forge`), arquivadas de forma reversivel. Base: SWE-Skills-Bench
   (arXiv:2603.15401) - 39 de 49 skills sem ganho, media +1.2%, 3 degradaram. Skill nova passa a
   exigir benchmark (`skill-creator`) antes de virar permanente.
8. **Desligar plugins redundantes**: `superpowers`, `plugin-dev`, `claude-md-management`,
   `claude-code-setup`, `greptile`, `stripe`.

## Resultado medido

| Eixo | Antes | Depois | Delta |
|---|---|---|---|
| Fixo por sessao (escopo comparavel) | 57.599 B (~14.400 tok) | 14.857 B (~3.714 tok) | **-74%** |
| Fora do escopo comparavel | superpowers 3.063 B + descricoes de skills de PLUGIN 8.543 B | plugins redundantes desligados | medir a parte |
| Por prompt (hook) | 3.660 B (~915 tok) | 767 B (~191 tok) | -79% |
| Agentes | 14 | 10 | -29% |
| Skills ativas | 25 | 3 | -88% |
| Hooks | 6 | 10 | +67% (mecanismo substitui texto) |

Hooks testados: 15/15 no `fable-guard` e 8/8 na bateria de `read-budget`, `risk-trigger`,
`subagent-contract` e integridade do `settings.json`, com `bash -n` limpo nos 10.

## Auditoria pos-publicacao (mesmo dia, apos o commit b553651)

O relatorio da v2.0.0 afirmou que a auto-deteccao do `verify-gate.sh` tornava o gate ativo em
todo repo. **Isso era falso, e so foi descoberto ao executar o hook contra um repo real** - a
propria falha que este ADR existe para combater: afirmacao de funcionamento sem execucao.

Defeito 1 - `verify-gate.sh` nao disparava (CORRIGIDO). Duas causas, ambas provadas por E2E:
- a deteccao de Python exigia manifesto (`pyproject.toml`, `requirements.txt`, `manage.py`);
  um repo com apenas `tests/` caia fora e o gate ficava inerte exatamente onde havia suite.
- o binario `pytest` nao insere o diretorio atual em `sys.path`; o `python3 -m pytest` insere.
  Num repo sem packaging o binario falhava na COLETA, e um erro de coleta seria lido como
  teste vermelho - barrando pelo motivo errado. O primeiro teste "passou" por esse motivo
  errado, e so a checagem de que a saida continha assercao (e nao "error collecting")
  revelou o engano.

Registro de uma hipotese minha que estava ERRADA: afirmei, antes de conferir, que `pytest` nao
estava no PATH. Estava (`/home/ti/.local/bin/pytest`). A causa era unica, nao dupla.

Defeito 2 - referencias mortas (CORRIGIDO): `graphify-scout-mode.sh` apontava para
`CLAUDE.md I.3.1`, `poka-yoke-lint.sh` para a `Diretriz 13.1`, e `scripts/colegio-metrics.sh`
para o agente `revisor-critico` - tres secoes e um agente que a propria v2 removeu. Havia ainda
deadcode meu (`DIRTY`) no `verify-gate.sh`, e `graphify-scout-mode.sh` sugeria um comando de uma
ferramenta que o plugin nao redistribui.

Correcao de outra afirmacao do relatorio: eu disse que era preciso reiniciar a sessao para os
hooks entrarem. Falso para hooks - o transcript da sessao mostra o hook novo (`lentes.sh`)
disparando 2 vezes ainda na sessao em curso. O restart continua valendo para o desligamento de
plugins.

### Estado de verificacao, item a item

VERIFICADO POR EXECUCAO (16/16 na suite de regressao):
- `fable-guard.sh`: nega na sessao principal sem sentinela; **nega em subagente mesmo com
  sentinela valido**; permite autorizado; nega expirado; sem falso positivo em prosa/grep;
  `artifact-discipline.sh` impede o modelo de escrever o sentinela.
- `verify-gate.sh`: barra suite vermelha por ASSERCAO (nao por coleta), libera suite verde,
  volta a barrar na regressao, funciona em Python com e sem manifesto e em Node, e fica inerte
  onde nao ha o que verificar. Precedencia do `.claude/verify-cmd` e anti-loop confirmados.
- `read-budget.sh`, `risk-trigger.sh`, `subagent-contract.sh`, sintaxe dos 10 hooks,
  integridade do `settings.json`.

NAO VERIFICADO (declarado, nao afirmado):
- `subagent-contract.sh` **nunca rodou contra um subagente real**. O formato da query foi
  validado contra um transcript real (1.898 bytes extraidos), mas o acionamento do evento
  `SubagentStop` com o matcher por tipo de agente nao foi exercitado de ponta a ponta.
- Os agentes lastreados em ferramenta (`auditor-seguranca`, `revisor-frontend`,
  `analista-otimalidade`) tem os comandos verificados isoladamente (`ruff --select S` pegou
  `shell=True`/`md5`/`pickle`; `npx @axe-core/cli` 4.12.1 alcancavel), mas **nenhum agente foi
  executado num diff real**.
- `poka-yoke-lint.sh` e herdado da v1 e nao foi reexercitado.
- **Nao ha medicao de que a qualidade das respostas melhorou.** Permanece hipotese.

### Correcao do numero publicado (achado 6 do refutador)

O ADR publicou "-79% (71.410 -> 14.402 B)" **sem script que derivasse o numero**, o que e
violacao do proprio C7 dentro do ADR cuja tese e que o C7 nunca foi aplicado ao autor.

Reauditado com `scripts/medir-contexto.sh` (agora commitado e re-executavel) contra o backup
real `backups/reforma-v2-20260731-113906`:

```
componente                             baseline        atual
CLAUDE.md (integral)                      46357        10756
agentes (so description)                   3347         2874
skills LOCAIS (description)                7895         1227
TOTAL comparavel                          57599        14857   ->  -74%
```

O defeito do numero antigo foi **misturar escopos**: o baseline somava as descricoes de skills
de PLUGIN (8.543 B) e a injecao do superpowers (3.063 B), e o endpoint nao somava - os dois
desvios empurrando na mesma direcao. O correto e reportar o escopo comparavel (-74%) e o
componente dependente de plugin separado. O `-79%` do hook por prompt, esse, confere exato:
3.660 -> 767 B, ambos verificaveis executando os dois scripts.


## Limites honestos

- Nenhum hook forca o spawn de um subagente. `risk-trigger.sh` torna a omissao impossivel de
  ser silenciosa, nao impossivel.
- `subagent-contract.sh` verifica a EXISTENCIA de ancora, nao a qualidade dela. Uma ancora
  irrelevante passa.
- A auto-deteccao do `verify-gate.sh` pode bater em ruido pre-existente do repo; nesse caso ela
  informa em vez de travar, o que preserva a usabilidade e enfraquece a garantia.
- A reducao de -74% (escopo comparavel) e de custo e de densidade. **Nao ha, aqui, medicao de que a qualidade das
  respostas melhorou.** Afirmar isso exigiria o mesmo tipo de benchmark que este ADR passou a
  exigir das skills. Enquanto nao existir, a melhora de qualidade e HIPOTESE, nao resultado.
