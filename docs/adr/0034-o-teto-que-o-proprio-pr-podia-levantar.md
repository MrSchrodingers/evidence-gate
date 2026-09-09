# ADR 0034 - O teto que o proprio PR podia levantar

Data: 2026-08-19
Estado: aceito
Sucede parcialmente: ADR 0033 (estado nao e nome de diretorio)

## Contexto

A onda 13 introduziu a divida de avaliacao como mecanismo para tornar verificavel o que todas
as auditorias vinham recomendando em prosa - congelar a expansao de capabilities enquanto
nenhuma tiver dossie. O ADR 0033 publicou isso como "o mecanismo que faltava".

Auditoria externa mediu duas fugas, e as duas passavam pela assercao de divida.

**Fuga 1 - o PR levanta o proprio teto.** `D_MAX = 8` era numero literal em
`tests/unit/capability-conformance.py`, isto e, DENTRO do objeto governado. Nada impedia o
mesmo diff de adicionar capability sem dossie e escrever `D_MAX = 9`:

```
PASS  divida de avaliacao D_E=9 nao excede o teto D_MAX=9
```

O cabecalho proibia levantar o teto por escrito. Proibicao em prosa dentro do arquivo que o PR
edita e `PolicyDeclared`, nao `PolicyEnforced` - a classe exata que a onda 13 fechou um nivel
abaixo, cometida um nivel acima pela propria correcao.

**Fuga 2 - a vaga livre.** Pagar um dossie derruba `D_E` de 8 para 7. O teto continua 8. Isso
abre uma vaga: adicionar capability nova sem dossie devolve `D_E` a 8 e o portao aprova:

```
PASS  divida de avaliacao D_E=8 nao excede o teto D_MAX=8
```

A frase do ADR 0033 dizia "cada dossie fechado o abaixa". O codigo nao abaixava nada - dependia
de alguem lembrar de editar a constante. Procedimento outra vez.

As duas foram reproduzidas em clone antes de serem aceitas.

## Decisao

**O teto constante e removido.** Nao ha `D_MAX`. A fronteira passa a ser RELACIONAL, medida
contra o SHA-base:

```
divida(head) SUBCONJUNTO DE divida(base)      e      |divida(head)| <= |divida(base)|
```

Um PR nao pode editar o proprio criterio, porque o criterio e o estado anterior do repositorio.
Levantar teto deixa de ser possivel: nao ha teto.

As duas regras sao necessarias e nenhuma e redundante:

- **Subconjunto** e o que pega a Fuga 2. Contagem mede TAMANHO, e trocar uma divida por outra
  mantem o tamanho. `8 -> 8` passa em qualquer regra de contagem.
- **Monotonicidade** e necessaria quando a divida ja e zero - senao o primeiro debito apos a
  quitacao entraria livre, porque o conjunto vazio nao tem subconjunto proprio a violar.

**A base e obrigatoria.** Sem `origin/main` ou `main`, a divida nao pode ser julgada e o portao
sai 2 = `NAO VERIFICADO`, nao 0. "Nao reprovou" seria indistinguivel de "nao foi medido", e o
`fetch-depth: 0` do workflow garante a base no CI.

**A validade do dossie e avaliada nos dois lados com o mesmo predicado.** O head le do disco; a
base le por `git show <ref>:<caminho>`. Comparar predicados diferentes nos dois lados produziria
diferenca sem significado.

## Validacao

`tests/mutation/capability-conformance.sh`, 11 mutantes, baseline verde exigido antes de
qualquer um. Os dois novos sao as fugas medidas:

```
MCAP10  capability nova + o PR levantando o proprio teto   -> exit 1
MCAP11  trocar uma divida por outra (tamanho constante)    -> exit 1
```

Discriminacao em tres direcoes, medida em clone:

```
paga um dossie, nao adiciona nada    -> exit 0   D_E 8 -> 7
qualquer capability nova sem dossie  -> exit 1
sem ref de base                      -> exit 2   NAO VERIFICADO
```

O primeiro caso e o que impede o portao de ser "reprova tudo": ele aprova reducao de divida.

## A correcao irma: `--dry-run` nao abre transacao

A mesma auditoria achou uma reincidencia de amplitude na onda 13b. Aquela onda corrigiu uma
mensagem falsa - `managed transaction committed` num ensaio - com um guard DEPOIS do snapshot,
que passou a imprimir `NENHUMA escrita foi feita`.

A frase era ampla demais. Antes do guard o script ja executava `mktemp -d` e, com destino
existente, `cp -a "$OPT" "$REC/opt"` - a arvore managed inteira copiada para o temporario. O
teste media `find "$MANAGED_PREFIX" -type f` = 0, entao o que estava demonstrado era **nenhum
destino managed foi alterado**, verdadeiro, e nao **nenhuma escrita ocorreu**.

Trocar uma claim falsa por outra ligeiramente ampla demais e a mesma classe, um grau menor.

A correcao nao foi estreitar a frase e sim torna-la desnecessaria:

```
DryRun NAO PERTENCE A Transaction
```

`--dry-run` sai no `exec` junto de `--verify|--revert`, antes de qualquer maquinaria
transacional. O discriminador que separa as duas versoes:

```
TMPDIR nao-gravavel, versao anterior  -> exit 1 (morre no mktemp)
TMPDIR nao-gravavel, versao atual     -> exit 0 (nao o alcanca)
```

E a antivacuidade correspondente, para que o caso nao passe por o mecanismo transacional ter
sumido para todos: o apply REAL continua declarando o commit e continua morrendo sem o
temporario.

## Limites, declarados

A regra de subconjunto usa NOMES de capability. Renomear uma capability em divida a faz parecer
nova e reprovar - correto por seguranca, inconveniente na pratica, e sem tratamento hoje.

A divida cobre apenas `kind: skill`. Os dez agentes nao tem dossie e nao entram na contagem; os
hooks de guidance tampouco. O numero 18 citado como "divida real" em
`evidence/observations/2026-08-18-*.md` e piso, nao total, e agente e skill sao intervencoes
diferentes que provavelmente exigem obrigacoes de prova distintas. Modelar isso e trabalho
proprio, nao extensao cega desta contagem.

`EvidenceValidity` continua ausente: um dossie legitimo em `t0` pode deixar de valer em `t1`
apos atualizacao de runtime ou modelo, e o schema nao expressa `evaluated_with` nem status
`stale`. Segue registrado como a proxima onda.

> **ERRATA (ver `docs/adr/0046-evidencia-envelhece-quando-o-ambiente-muda.md`).** Este paragrafo
> ficou desatualizado sem correcao. `evaluated_with` nao "continua ausente": entrou na onda 15
> (`docs/adr/0035-a-divida-era-de-uma-classe-so.md`) e ja era exigido por
> `tests/unit/capability-conformance.py` no momento em que esta linha foi escrita. O status
> `stale` como VALOR do vocabulario de `evidence.status`, esse sim ausente ate aqui, e entregue
> na onda 28 (ADR 0046), junto do envelope declarado `orchestration/environment.json` contra o
> qual `runtime`/`model` passam a ser comparados.
