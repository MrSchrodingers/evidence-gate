# O numero que motivou a onda 25 foi atribuido errado tres vezes

Data: 2026-09-02. Maquina: estacao `ti`, Fedora 43. Instrumento: o ledger do proprio portao em
`~/.claude/evidence/*.jsonl`, 5.126 arquivos, 8.600 registros com veredito.

Este documento nao propoe nada antes da secao final. Ele mede.

## 1. O que a onda 25 afirmou

Que o Stop-gate reprovava 2.942 vezes em 5.054 registros, que TODAS as reprovacoes tinham a mesma
causa (`falharam: python-analyzer`), e que a causa era o analisador rodar sobre a ARVORE INTEIRA e
reprovar por divida preexistente alheia ao turno - com `/var/www/amaral-intern-hub` como o caso
que concentrava o problema.

## 2. O que o ledger mede hoje

    paradas com veredito ........ 8.600
    fail ........................ 5.256   (56,9% de 9.236 registros totais)
    pass ........................ 2.963   (32,1%)
    gap .........................    381   ( 4,1%)
    sem campo `verdict` .........    636   ( 6,9%)

    snapshots distintos ......... 6.040
    ambientes distintos .........   203
    conjuntos de verificador ....    17

A agregacao de `detail` continua sustentando a PRIMEIRA afirmacao: 5.256 de 5.256 reprovacoes
dizem `falharam: python-analyzer`. Uma causa, nao muitas.

## 3. A atribuicao por repositorio, que ninguem tinha feito

O ledger nao tem campo de repositorio. Tem, porem, identidade: `LEDGER="$LEDGER_DIR/$(sha $ROOT).jsonl"`
(`evidence/hooks/verify-gate.sh`), com `sha(){ sha256sum | cut -c1-32; }`. E hash de mao unica, entao
a atribuicao exigiu varrer 334 raizes candidatas da maquina e casar os digests.

    repositorio                          fail    pass    gap
    /home/ti/debthub-wt-phone3           1116      28      0
    /home/ti/claude-usage-widget           97      39     43
    /home/ti/debthub-wt-schema-perm        17       0      0
    /var/www/amaral-intern-hub             14       4      0
    /home/ti/evidence-gate                  0     182     22
    /home/ti/chatwoot-kanban                0     108      0
    /var/www/DEBTHUB-2.1                   11      78      0

A SEGUNDA afirmacao cai aqui. `amaral-intern-hub` responde por 14 reprovacoes, nao pelo grosso. O
repositorio dominante e uma worktree do DEBTHUB que a onda 25 nunca examinou.

## 4. A forma das 1.116 reprovacoes dominantes

    2026-08-11   fail=769  pass=0
    2026-08-12   fail=343  pass=0
    2026-08-13   fail=  0  pass=5
    (a partir dai o repositorio passa)

    snapshots distintos nesse ledger ....... 66
    paradas no snapshot mais repetido ...... 336   (todas `fail`)

Mil cento e doze das 1.116 reprovacoes cairam em DOIS DIAS, sobre 66 estados de arvore, com UM
estado julgado 336 vezes. Isso nao e "o portao reprova por divida preexistente espalhada pela
frota". E um agente parado em laco, num repositorio, por dois dias.

Hoje aquele repositorio esta limpo: `git status` vazio, upstream configurado, e
`ruff check --isolated --select F,E9 .` devolve ZERO diagnosticos.

## 5. O custo estrutural que isso expoe

O cache do portao e ASSIMETRICO POR DESENHO: so `pass` do mesmo `(snapshot, verifiers, env)`
curto-circuita (`evidence/hooks/verify-gate.sh`, guarda G1). `fail` reexecuta tudo.

    reexecucoes estritamente redundantes ... 1.992  (23,2% das 8.600 paradas)
      = mesmo snapshot, mesmos verificadores, mesmo ambiente, veredito anterior ja era `fail`

      1.070  /home/ti/debthub-wt-phone3
         92  /home/ti/claude-usage-widget
         13  /home/ti/debthub-wt-schema-perm
         12  /var/www/amaral-intern-hub

A soundness de cachear `fail` e EXATAMENTE a mesma de cachear `pass`: as tres chaves cobrem a
arvore (digest de HEAD + digest de cada arquivo em CHANGED), o conteudo dos adaptadores e a
identidade do binario com versao. Se qualquer um muda, a chave muda. Nao ha assimetria epistemica
que justifique a assimetria de implementacao - o que existe e uma assimetria de CONSEQUENCIA, e
ela e discutida na secao 7.

## 6. Ameacas a validade deste proprio instrumento

**T1. As suites de teste escrevem no ledger REAL do operador.** `LEDGER_DIR` cai em
`$HOME/.claude/evidence` por padrao e nenhuma suite exporta `EVIDENCE_LEDGER_DIR`
(`grep -rn 'EVIDENCE_LEDGER_DIR' tests/` nao devolve nada). Cada execucao de `delta-e2e.sh`
injeta paradas sinteticas no mesmo arquivo que serve de evidencia operacional. Os numeros de
2026-09-01 e 2026-09-02 estao contaminados por isso e NAO foram usados nas secoes 3 e 4.

**T2. 636 registros (6,9%) nao tem campo `verdict`.** Sao eventos de outra forma (`session_integrity`)
gravados no mesmo diretorio. Nao invalidam as contagens - foram excluidos -, mas mostram que o
diretorio mistura dois esquemas sem discriminante declarado.

**T3. A identidade de repositorio e recuperavel por forca bruta, nao por projeto.** Refazer a
secao 3 exige varrer o sistema de arquivos. Uma analise que so e possivel por acidente nao e uma
capacidade do instrumento.

**T4. Nao ha contrafactual.** Nada aqui mede o que teria acontecido sem o portao. As secoes 3 a 5
descrevem a distribuicao das reprovacoes, nao o efeito delas sobre a qualidade do trabalho.

## 7. O que se conclui, e o que explicitamente NAO se conclui

CONCLUI-SE que a justificativa empirica publicada da onda 25 estava errada na ATRIBUICAO (nao era
amaral) e na FORMA (nao era divida espalhada, era laco concentrado), e que o custo dominante
medido hoje - 23,2% de reexecucoes identicas - nao e endereçado por `scope: delta`.

NAO SE CONCLUI que `scope: delta` esteja errado. O desenho separa divida preexistente de regressao
nova, e isso e verificado por `tests/unit/delta-e2e.sh` DE2 e pelos arneses de mutacao. O que cai e
a PROMESSA OPERACIONAL de que ele zeraria aquelas reprovacoes.

NAO SE CONCLUI que cachear `fail` seja seguro sem mais analise. A assimetria de consequencia e
real: um `pass` em cache que estivesse errado deixa passar UM turno; um `fail` em cache que
estivesse errado bloqueia o repositorio ATE que a arvore mude, e o operador nao tem como saber que
o veredito veio de cache. Antes de implementar, tres coisas precisam ser resolvidas: (a) o cache
tem de DIZER que e cache, (b) precisa haver escape explicito, (c) a interacao com a semeadura da
catraca - que exige `RC==1` - precisa ser verificada, porque semear a partir de um `fail` cacheado
nunca aconteceria.

## 8. Onde agir, por ganho de informacao sobre custo

1. **Deteccao de progresso, nao cache.** O achado da secao 4 nao e desperdicio de CPU - e um
   agente que recebe a mesma negativa 336 vezes e nao consegue agir sobre ela. O portao ja tem a
   informacao para detectar isso (`PRIOR` casa o snapshot). Um portao que, na N-esima negativa
   identica, MUDA A MENSAGEM em vez de repeti-la ataca a causa; o cache ataca o sintoma.
2. **Isolar o ledger nas suites** (T1). Uma linha por suite. Sem isso, todo numero futuro sobre
   comportamento operacional nasce contaminado.
3. **Tornar a atribuicao uma capacidade** (T3), publicando o resolvedor de digest->raiz como probe.
4. **O experimento pareado** (`harness_condition x task_initial_state`), que segue nao executado e
   e o unico desenho registrado capaz de falar sobre EFEITO, e nao sobre distribuicao.

## Procedencia

Todos os numeros desta pagina vieram de `~/.claude/evidence/*.jsonl` lidos em 2026-09-02, do
codigo em `evidence/hooks/verify-gate.sh` no commit da onda 25d, e de `ruff 0.16.2` na mesma
maquina. Nenhum foi citado de memoria ou de documento anterior.
