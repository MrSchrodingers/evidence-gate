# ADR 0042 - O portao julga o delta, nao a arvore

Estado: aceito. Onda 25.

## O defeito, medido

O log do proprio portao (`~/.claude/evidence/*.jsonl`, 5054 registros; registro de procedencia
em `evidence/literature/local-2026-08-31-portao-por-delta.yaml`) mostra **2942 `fail` contra
2110 `pass`** - 42% de aprovacao. Agregando o campo `detail` das 2942 reprovacoes: **um unico
motivo**, `falharam: python-analyzer`, o mais recente no mesmo dia da medicao.

A causa nao e o modelo reprovando em verificacao. E o adaptador rodando `ruff` sobre a **arvore
inteira**, entao qualquer turno num repositorio com divida preexistente reprova por trabalho que
nao e o do turno. Em `/var/www/amaral-intern-hub`, onde a telemetria mostra a maior parte da
atividade:

    173 diagnosticos na arvore
     87 dentro de checkout ANINHADO      codigo de outra branch, fora do HEAD do turno
                                          (todos de UM checkout; ha 5 raizes, 4 sem diagnostico)
     86 no codigo do repositorio
        80 higiene    F401 73, F841 7
         6 quebra     F822 5, F811 1      defeitos REAIS, preexistentes

Contra 4 arquivos `.py` no ultimo commit.

Um portao que reprova 58% das vezes por motivo alheio ensina o operador a ignora-lo, e ai deixa de
ser portao. E a armadilha do "bug preexistente" que a onda 22 removeu das REGRAS e que seguiu viva
na CONFIGURACAO.

## A decisao

A pergunta muda. De `f(D(head))` - "esta arvore esta limpa?", cuja resposta nao depende do trabalho
feito - para `f(D(head) \ D(base))` - "este turno piorou alguma coisa?".

**Nao e um meio-termo entre `per_file` e arvore inteira.** A onda 24 tentou escolher um lado e
falhou nos dois: `per_file` elimina a divida alheia mas perde a quebra CRUZADA (remover uma funcao
quebra quem a chama, e esse arquivo nao esta no diff) e, medido, faz apagar um `.py` virar LACUNA e
bloquear. Sao DUAS CLASSES com escopos diferentes:

| Classe | Escopo | Por que |
|---|---|---|
| HIGIENE | so as LINHAS TOCADAS | divida de higiene alheia nao e do seu turno |
| QUEBRA | ARVORE INTEIRA, contra catraca | sua mudanca pode quebrar arquivo que voce nao tocou |

E uma terceira exclusao que nao tem trade-off: diagnostico dentro de **checkout aninhado** nunca
foi objeto do turno. As raizes sao DERIVADAS (diretorio com `.git` proprio), nunca lista de nomes -
`.worktrees` e convencao de quem criou, nao contrato.

## Identidade do diagnostico

Casar a catraca por `(arquivo, linha)` faz QUALQUER edicao acima deslocar tudo e gerar falso-novo
em massa: o baseline viraria ruido na primeira edicao. A chave e
`(caminho relativo, codigo, mensagem normalizada)`, com numeros da mensagem reduzidos a `#` - senao
`redefinition of unused 'x' from line 3` muda de digital quando o alvo se move, que e o mesmo
falso-novo pela porta dos fundos.

Isso nao e afirmado: `tests/unit/lint-delta.sh` LD6 e LD7 exercitam o mesmo defeito 44 linhas
abaixo (continua tolerado), outro simbolo no mesmo arquivo (bloqueia) e o mesmo simbolo em outro
arquivo (bloqueia).

## Onde a decisao mora

Em `evidence/lint-delta.py`, FORA do executor. A logica que decide bloqueio nao pode viver dentro
de um script de 400 linhas de shell que ninguem consegue exercitar isoladamente. O nucleo nao
executa analisador nem le repositorio: recebe diagnosticos, hunks e baseline, devolve veredito.
35 casos em `tests/unit/lint-delta.sh`, e `tests/mutation/lint-delta.sh` mata mutantes sobre as
decisoes centrais - classificacao, catraca, escopo por hunk e exclusao de checkout aninhado.

O adaptador declara `scope: "delta"`, o mapa de campos da saida nativa e os `breakage_codes`.
Embutir os nomes de campo no nucleo faria cada ferramenta nova exigir edicao dele - e e assim que
um executor generico vira um executor de uma ferramenta so.

## O que o desenho errou, e quem pegou

Quatro defeitos apareceram por EXECUCAO, nenhum por leitura, e tres deles foram pegos pelos
proprios portoes deste repositorio:

1. `--hunks` obrigatorio matava a semeadura; o executor engolia o erro e seguia sem catraca.
   Pego pelo teste PONTA A PONTA - a suite unitaria nao via, porque sempre passava o argumento.
2. `> "$BLPATH"` criava o arquivo ANTES do programa rodar: emissao falha deixava baseline VAZIO,
   que bloqueava a re-semeadura e, se lido, toleraria nada. Escrita atomica.
3. **A catraca era semeada do estado ATUAL, anistiando a quebra do proprio turno.** Pego por
   `regressao-gate.sh` G1 ("falha em cache NAO vira sucesso na segunda parada"). O baseline passou
   a vir de `git archive HEAD` - leitura pura, sem registrar worktree nem tocar o indice.
4. Apos semear, o codigo forcava `RC=0` sem REJULGAR. A primeira parada passava sempre, inclusive
   para quebra recem-introduzida. Pego por G2 (anti-loop). Passou a rejulgar contra o baseline novo.

Nenhum caso do portao de regressao foi reespecificado. As 65 garantias antigas valem palavra por
palavra, e a guarda G_VAZIO ("acao nula nao aprova em silencio") foi replicada no ramo novo -
lista vazia de diagnosticos atravessaria o nucleo inteiro como "nada a bloquear".

## Custo declarado

A catraca BLOQUEIA UMA VEZ por repositorio, na criacao. A lacuna declarada nao e o julgamento -
esse acontece - e a TOLERANCIA recem-concedida, que nenhum humano revisou. O caminho do arquivo e
publicado para revisao ou remocao.

E o baseline e gravavel pelo ator governado, como o log de ativacao (G39). Indicio, nao prova.

## O que NAO se afirma

Que isto melhora a qualidade do trabalho. O que se afirma e o que foi medido: 2942 reprovacoes de
uma unica causa alheia ao turno deixam de ocorrer, quebra nova continua bloqueando, e quebra
preexistente e reportada a cada execucao em vez de bloquear. Se isso melhora o resultado do
operador e pergunta de experimento pareado, e esse continua nao executado.

## Adendo pos-deploy: o nome da regra e uma dependencia externa (G65)

A separacao QUEBRA/HIGIENE e feita por uma LISTA DE CODIGOS declarada no adaptador. Isso amarra a
solidez do portao ao vocabulario de uma ferramenta de terceiro - e vocabulario envelhece.

Medido depois do deploy, executando o hook INSTALADO (nao o do repositorio) contra um repositorio
construido para isso: `ruff` REMOVEU `E999`. Fonte primaria na maquina, ruff 0.16.2:

    $ ruff rule E999
    # syntax-error (E999)
    ## Removed
    This rule has been removed. Syntax errors will always be shown regardless of whether this
    rule is selected or not.

O codigo emitido hoje e `invalid-syntax`, que nao estava em `breakage_codes`. Erro de sintaxe
passou entao a ser classificado como HIGIENE - e higiene e submetida ao teste de hunk.

O que torna isso um FALSO NEGATIVO, e nao ruido, e uma premissa oculta sobre analisadores: que a
linha reportada fica perto do erro. Para um erro de PARSE isso e falso por construcao - o parser
reporta onde a expectativa falhou, nao onde a causa esta. Repro medido: arquivo de 203 linhas, o
turno edita SO a linha 1 abrindo um parentese que nao fecha; `ruff` reporta nas linhas 202-203; o
hunk e `@@ -1 +1 @@`. Antes da correcao o portao saia `rc=0`, stdout VAZIO, stderr vazio: arvore
que nao parseia, aprovada em silencio.

Corrigido em DUAS camadas de proposito, porque so a primeira fecharia o repro:

- `invalid-syntax` entra em `breakage_codes` (o repro). `E999` FICA, porque repositorios com ruff
  anterior a remocao ainda o emitem - nao e config morta, e config para outra versao.
- `eh_quebra()` no nucleo: diagnostico com codigo NULO ou VAZIO e quebra por construcao (a
  classe). Um analisador nomeia a regra que aplicou; diagnostico sem nome e o analisador dizendo
  que nao aplicou regra nenhuma. O mesmo predicado governa `--emit-baseline`, senao a quebra
  preexistente nunca entraria na catraca e bloquearia para sempre, sem caminho de semeadura.

Regressoes: DE9 (`tests/unit/delta-e2e.sh`, o repro pelo hook, com o controle negativo de que a
MESMA linha 1 editada sem quebrar o parse passa) e LD14 (`tests/unit/lint-delta.sh`, codigo nulo e
vazio, mais o acordo com o baseline).

E a terceira camada, que e a que impede a proxima aposentadoria de repetir isto: DE10 nao le a
lista, LE A FERRAMENTA. Escreve um arquivo que nao parseia, roda o comando EXATO declarado no
adaptador e exige que TODO codigo devolvido esteja em `breakage_codes`. Um `ruff` futuro que
renomeie `invalid-syntax` reprova essa suite no dia da atualizacao, com o nome novo na mensagem -
em vez de degradar em silencio para higiene. Conferir a lista contra `ruff rule <codigo>` NAO
serviria: `ruff rule E999` sai 0 e imprime a regra, apenas marcada como removida, e manter `E999`
para versoes antigas e deliberado. O que decide e o que a ferramenta EMITE, nao o que ela conhece.

## Adendo pos-deploy: o portao fail-closed esconde a diferenca entre veredito e lacuna (G66)

O segundo defeito achado na mesma validacao de deploy nao veio de dependencia externa - veio desta
onda. A correcao F3 trocou `--raw` (argumento) por `--raw-file` (arquivo), porque a saida do ruff
estourava MAX_ARG_STRLEN. O argumento virou arquivo; a LIMPEZA ficou onde estava:

    492:  rm -f "$RAWF"            # limpeza
    ...
    578:  python3 "$LD" --raw-file "$RAWF" ...   # rejulgamento pos-semeadura

Resultado medido: `exit=2`, `NAO VERIFICADO: entrada ilegivel ([Errno 2] No such file or
directory: ...)`. A PRIMEIRA parada de todo repositorio que cria catraca terminava em LACUNA em
vez de julgamento, e a mensagem mandava o operador procurar defeito na leitura em vez de mostrar o
diagnostico.

O que importa aqui nao e o `rm` fora de lugar - e POR QUE ele sobreviveu a seis suites verdes, a
CI completa e a duas passadas do `refutador`. DE1 e DE2 mediam so o CODIGO DE SAIDA:

    barrou porque julgou e reprovou   -> 2
    barrou porque nao conseguiu ler   -> 2

Num portao fail-closed por projeto, esses dois estados sao indistinguiveis pelo canal que os
testes estavam medindo. Quem pegou foi uma assercao de CONTEUDO escrita para OUTRO defeito - DE9,
"e nomeia o arquivo que nao parseia", `got=0 want=1`.

REGRA QUE FICA: neste portao, todo caso que espera bloqueio mede tambem a CAUSA. `exit 2` e
condicao necessaria e nao suficiente; sem a causa, o teste nao separa "o portao funcionou" de "o
portao quebrou de um jeito que tambem bloqueia".

## Adendo: o lastro externo desta decisao, e o que ele NAO cobre

Ate 2026-09-04 a decisao de julgar `f(D(head) \ D(base))` em vez de `f(D(head))` era sustentada
apenas por medicao local. A busca delimitada `[busca:BL-0002]`
(`evidence/literature/searches/BL-0002-portao-por-delta.yaml`) levantou o que existe fora.

**A fonte que sustenta o desenho.** Distefano, Fahndrich, Logozzo e O'Hearn, *Scaling static
analyses at Facebook* (CACM 62(8), 2019 - ledger em
`evidence/literature/cacm-2019-scaling-static-analyses-facebook.yaml`) relatam um experimento
natural que troca **so o escopo**, mantendo a mesma analise e a mesma taxa de falso positivo:

> "We assigned 20-30 issues to developers, and almost none of them were acted on. We had worked
> hard to get the false positive rate down to what we thought was less than 20%, and yet the fix
> rate - the proportion of reported issues that developers resolved - was near zero. Next, we
> switched Infer on at diff time. [...] the fix rate rocketed to over 70%. The same program
> analysis, with same false positive rate, had much greater impact when deployed at diff time."

E a chave de identidade que a secao "Identidade do diagnostico" adotou aqui - `(caminho, codigo,
mensagem normalizada)`, com numeros substituidos - converge de forma independente com a do Infer:
"a hash involving the bug type and location-independent information about the error message [...]
the aim is to avoid presenting warnings that developers might regard as pre-existing". Duas
equipes sem contato chegando a mesma chave pela mesma razao e o apoio mais forte que um desenho
recebe da literatura.

Sadowski et al., *Tricorder* (ICSE 2015 - `evidence/literature/icse-2015-tricorder.yaml`) declara
a politica em uma frase - "we only display results for most analyses on changed lines by default"
- e, no rodape 2, ja documentava a EXCECAO que este repositorio redescobriu por medicao e chamou
de classe QUEBRA: aviso de variavel nao usada pode cair em linha nao alterada quando o bloco que
a usava foi deletado. A tabela HIGIENE/QUEBRA generaliza o que la era excecao pontual.

**O que a literatura diz sobre o custo do ruido.** Bessey et al. (CACM 53(2), 2010 -
`evidence/literature/cacm-2010-billion-lines-of-code-later.yaml`) descrevem o ciclo que esta
sessao observou em producao: "a vicious cycle starts where low trust causes complex bugs to be
labeled false positives, leading to yet lower trust". Christakis e Bird (ASE 2016 -
`evidence/literature/ase-2016-what-developers-want-program-analysis.yaml`) dao a unica
distribuicao quantitativa localizada: 90% dos respondentes aceitam ate 5% de falso positivo, e
apenas 24% toleram 20%. E a irritacao numero UM da lista deles nao e falso positivo, e sim
"irrelevant checks are turned on by default" - que e exatamente a forma dos 79 achados de higiene
alheios ao turno que motivaram o G82.

**O achado que muda o calculo aqui, e que nenhuma dessas fontes cobre.** Todos esses limiares
foram calibrados para um consumidor HUMANO, que pode olhar um achado e dizer "nao". O consumidor
deste portao e um agente. Stechly, Marquez e Kambhampati (arXiv:2310.12397 -
`evidence/literature/arxiv-2310.12397.yaml`) mediram o controle "evil", em que a critica aponta um
erro FALSO: o modelo aplica a "correcao" em 94% dos casos, praticamente a mesma taxa do
backprompt legitimo, e os autores registram que ele "didn't discriminate between real errors or
the evil case's false ones, blindly applying local 'fixes' without regard for overall
correctness".

CONSEQUENCIA DIRETA PARA ESTE PORTAO, e ela e assimetrica em relacao ao que a literatura de
analise estatica supoe: um achado espurio nao produz apenas ruido e laco - produz EDICAO DE
CODIGO CORRETO. O custo de um falso positivo aqui e maior que em qualquer contexto medido pelas
fontes acima, e por isso toda correcao de escopo desta onda veio acompanhada de controles
negativos explicitos, e nao apenas do caso positivo.

**O que continua sem apoio externo** (registrado em `[busca:BL-0002]`, secao `limits`):

- [busca:BL-0002] Nenhum estudo revisado compara gate-sobre-novo contra gate-sobre-arvore
  medindo desfecho. O
  que existe e relato industrial convergente e material de fornecedor. A eficacia da catraca
  segue sem demonstracao; a evidencia empirica disponivel e do lado do RISCO (Hu et al., FSE
  2025: supressoes crescem com o tempo e 50,8% delas nao afetam warning nenhum).
- Nenhuma fonte mede um gate BLOQUEANTE [busca:BL-0002], nem um gate cujo consumidor seja o
  proprio modelo que escreveu o codigo.
- Nenhuma fonte trata de repositorio com divida em massa NAO RASTREADA [busca:BL-0002], que e o caso concreto
  medido aqui (2691 arquivos untracked em /var/www/amaral-intern-hub).
- [busca:BL-0002] Nenhuma fonte mede estabilidade de identificador de regra entre versoes de
  analisador - a
  classe do G65, em que a remocao do `E999` pelo ruff quebrou a classificacao deste portao.

O experimento pareado que esta e outras ADRs declaram em aberto continua em aberto. A literatura
sustenta a EXISTENCIA deste portao; ela nao substitui a medicao do efeito dele aqui.
