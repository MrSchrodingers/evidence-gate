# ADR 0010 - Gate de conclusao ancorado em execucao (contra "declarou corrigido sem estar")

- Data: 2026-07-01
- Status: Aceito
- Escopo: configuracao global de usuario (~/.claude/)
- Relaciona-se com: 0005 (varredura C1-C10), 0009 (medicao), Diretrizes 2, 3, 13.1

## Contexto

Modo de falha #1 relatado pelo usuario e MEDIDO na literatura: o agente declara "corrigido/resolvido"
quando NAO esta - o defeito persiste, ou o fix introduz regressao, so descoberto quando o usuario
testa. Causa: conclusao de debug superficial/precipitada + declarar sucesso sem executar teste.

Base de evidencia (docs/research/referencias-pesquisa-agentes-llm.md, verificada):
- "False success" e dominante: 45-89% em benchmarks (arXiv:2606.09863).
- Auto-correcao SEM sinal externo DEGRADA (Kamoi, TACL 2024; Huang et al., ICLR 2024,
  arXiv:2310.01798) - peer-reviewed.
- Execucao AMPLIFICA (+12%); explicacao pura e fraca (+2-3%) (Chen et al., ICLR 2024) - peer-reviewed.
- Teste de reproducao F2P (falha antes, passa depois) como filtro DOBRA a precisao + regressao
  (SWT-Bench, NeurIPS 2024) - peer-reviewed.
- "Passar num teste fraco" engana: ~28-30% dos "resolvidos" divergem (Wang & Pradel, ICSE 2026).
- Pressao ("tem certeza?") degrada 17% (FlipFlop, arXiv:2311.08596) - sustenta a Diretriz 3.
- Critico INDEPENDENTE corrige +23-93pp vs auto-critica no mesmo fio (Self-Correction Illusion,
  arXiv:2606.05976) - sustenta cetico/revisor-critico e "o autor nao preside a propria banca".

## Decisao (3 camadas - todas atacam a MESMA raiz: o sinal de "pronto" nao pode vir do agente que fez o fix)

1. **DISCIPLINA (todo turno, entrega deterministica):** o hook `colegio-operating-mode` passa a
   LIDERAR o lembrete com o modo-de-falha-#1 - "pronto" vem de EXECUCAO EXTERNA (reproduzir-primeiro
   F2P + regressao + exit 0 colado), jamais de auto-avaliacao; provar a causa raiz declarando o que a
   REFUTARIA; nao parar na 1a hipotese plausivel.
2. **MECANISMO (Stop hook `pre-conclusion-verify.sh`):** ancorado em EXECUCAO, nao em pergunta. Ao
   encerrar o turno com CODIGO nao-commitado, se o projeto tem `.claude/verify-cmd`, o hook EXECUTA
   o comando e BARRA o encerramento (exit 2) se falhar, devolvendo a saida REAL ao modelo. NAO pergunta
   "voce testou?" (isso seria um LLM-judge do proprio fechamento, AUROC<=0.65). Opt-in por projeto
   (SEGURO por padrao: sem verify-cmd, inerte - nenhum teste-surpresa). Anti-loop (`stop_hook_active`),
   anti-state-pollution (processo real, exit code que o agente nao controla), throttle 300s, timeout
   180s, fail-open a favor do usuario.
3. **AGENTES:** `investigador` (enumerar >=2 hipoteses + nomear o teste EXECUTADO que as discrimina;
   nao parar na 1a) e `tdd` (reproduzir-primeiro F2P) reforcados; `revisor-critico` ja carrega o C3
   ("sucesso = hipotese ate evidencia executada; NUNCA correto sem teste executado").

## Como habilitar o modo FORTE (execucao) por projeto

Criar `<repo>/.claude/verify-cmd` com UMA linha - o comando de verde do projeto. Exemplos:
`pytest -q` | `npm test --silent` | `make test` | `go test ./... 2>&1`. O hook Stop o executa antes
de deixar o turno encerrar (havendo codigo nao-commitado); vermelho barra com a saida real.

## Limites honestos

- O Stop hook so e FORTE onde ha `verify-cmd` (opt-in). Onde nao ha, resta a camada 1 (disciplina) -
  entrega deterministica do lembrete, adesao soft (o teto inerente de sempre).
- O hook confia no EXIT CODE de um processo real, nunca num LLM que le a saida. Por isso o comando
  deve rodar num alvo FORA da superficie de escrita do agente (nao um arquivo de resultado que ele
  escreve - state-pollution).
- Nenhum hook FORCA a causa-raiz correta; ele forca o SINAL de execucao. A qualidade da hipotese
  segue disciplina + arguicao independente (cetico/revisor-critico).
- O `Stop` NAO dispara no fim de um SUBagente (isso e `SubagentStop`; o `Stop` pega a sessao
  principal). Ha relato de bug em versoes do Claude Code (anthropics/claude-code#33049) - verificar.

## Validacao

Stop hook testado (repo git temporario): verify FALHA -> exit 2 + saida real colada; verde -> exit 0;
sem `verify-cmd` -> inerte (exit 0); `stop_hook_active=true` -> exit 0 (anti-loop); sem codigo
nao-commitado -> exit 0; throttle 300s ativo. `colegio-operating-mode` re-priorizado (modo-de-falha-#1
no topo). Wired em settings.json e no hooks.json do plugin (5o hook). Gate antes do commit.
