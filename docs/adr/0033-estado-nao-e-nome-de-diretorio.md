# ADR 0033 - Estado nao e nome de diretorio

Data: 2026-08-18
Estado: aceito
Sucede parcialmente: ADR 0025 (skills evidence-gated), ADR 0030 (o verificador instalado),
ADR 0032 (referencia publicada que nao resolve)

## Contexto

Seis auditorias externas leram este repositorio em rodadas sucessivas. As duas ultimas
convergiram num achado que nenhuma anterior tinha nomeado, e ele e estrutural:

```
PolicyDeclared  NAO IMPLICA  PolicyApplied
```

`orchestration/skill-policy.json` declara cinco estados de lifecycle e SETE condicoes de
promocao - avaliacao pareada, snapshot fixo, verificador deterministico, manifesto de
compatibilidade, controle negativo, medicao de custo, checagem de interferencia de contexto.

Medido em 2026-08-18, antes desta onda:

```
$ ls execution/skills/
deprecated  promoted
$ ls evidence/skills/ 2>&1
No such file or directory
$ rg '^(state|status|lifecycle):' execution/skills/promoted/*/SKILL.md
(nenhum resultado - nenhuma das oito declarava estado algum)
$ python3 tests/unit/methodology.py
TOTAL=53 FAIL=0
```

Oito capabilities ativas, zero declarando estado, zero dossies, portao verde. `promoted` nao
era uma alegacao inflacionada: era **inferido de um nome de diretorio**.

E a forma do ADR 0030 subindo mais um nivel. `tests/unit/methodology.py` afere que o JSON de
policy CONTEM as clausulas certas. Ele tambem abre artefatos de skill - resolve invocacoes
`/x`, confere comandos publicados - entao nao e verdade que ignore os artefatos, e uma versao
anterior desta ata dizia isso e estava errada. O que ninguem verificava era a proposicao que
importa:

```
Promoted(s)  =>  PARA TODO r em promotion_requires: Evidence(s, r)
```

O verificador observava a REPRESENTACAO da garantia, nao o fenomeno que ela pretende controlar.

## O que impediu a correcao obvia, e foi medido antes de ser aceito

A recomendacao inicial das auditorias era rebaixar as oito para `candidate` imediatamente.
Testado em clone antes de concordar:

```
mover as 8 para execution/skills/candidate/
  -> manifesto: 49 -> 41 componentes
  -> skills no manifesto: 0
  -> skills instaladas no destino: 0
```

`install/manifest.sh` materializava `execution/skills/promoted/*/`. **Rebaixar era desinstalar.**
O operador nao receberia um rotulo de "nao comprovada"; receberia a ausencia da ferramenta.

A causa e que tres conceitos distintos estavam colapsados num unico caminho:

```
lifecycle state  ~  filesystem location  ~  installation eligibility
```

Uma reclassificacao puramente epistemologica virava mudanca funcional. A ordem correta -
apontada pela sexta auditoria e aceita aqui - e schema antes de portao, portao antes de
migracao, migracao antes de reclassificacao. Um portao escrito antes do schema teria de inferir
estado do diretorio, isto e, nasceria codificando o defeito que existe para remover.

## Decisao

**1. O estado vira metadado declarado.** `orchestration/registry.json` ganha o bloco
`capabilities`, no mesmo arquivo e no mesmo padrao que ja hospeda `agents`:

```json
"graphify": {
  "kind": "skill",
  "source": "execution/skills/graphify",
  "state": "candidate",
  "installed": true,
  "activation": "contextual",
  "evidence": { "dossier": null, "status": "absent" }
}
```

`state` e `installed` sao INDEPENDENTES. `candidate` + `installed: true` e uma combinacao
valida e significa exatamente o que precisa significar: **disponivel experimentalmente, nao
certificada como capacidade benefica**.

**2. O diretorio volta a ser armazenamento.** `execution/skills/promoted/<n>/` passa a
`execution/skills/<n>/`. `install/manifest.sh` le o registry, nao o glob.

Controle de que o movimento preservou conteudo: imediatamente apos o `git mv`, os oito digests
permaneceram identicos byte a byte e o manifesto continuou em 49 componentes.

**Errata da primeira redacao desta ata**, apontada pela revisao: ela afirmava "os oito digests
permaneceram identicos" sem qualificador temporal, e no diff final da onda sao SEIS. `depreciar`
e `design-system-proposal` mudaram porque a mesma onda editou o conteudo deles - a politica de
`backups/skills-arquivadas-` saiu de um, `amaral-intern-hub` saiu do routing do outro, e ambos
constam da decisao 5 deste mesmo documento. A frase era verdadeira para o movimento isolado e
falsa como escrita. Registrada aqui em vez de corrigida em silencio: uma ata que se refuta na
propria pagina e o defeito que este repositorio persegue.

**3. O portao passa a aferir o ARTEFATO.** `tests/unit/capability-conformance.py` verifica
forma do schema, pertinencia do `state` aos estados da policy, existencia da fonte quando
`installed`, coincidencia entre disco e registry nas DUAS direcoes, e a proposicao central:
`promoted` sem dossie que cubra os sete `promotion_requires` REPROVA.

**4. As oito sao reclassificadas para `candidate`, sem desinstalar.** Nao porque tenham sido
demonstradas ruins - pelo motivo oposto: a hipotese nunca passou pelo experimento que a
propria arquitetura exige.

**5. `defesa-de-tese` sai da arvore ativa.** O `SKILL.md` executavel foi apagado; o registro da
decisao vira tombstone no registry (`state: deprecated`, `retired_at`, `superseded_by`,
`reason`). Git ja e o mecanismo de recuperacao; manter capability aposentada em disco e
cemiterio, e a politica de `backups/skills-arquivadas-<data>/` do `depreciar` foi removida pela
mesma razao.

## Divida de avaliacao, e por que ela e o mecanismo que faltava

Todas as auditorias recomendaram "congelar a expansao". Norma em prosa sem portao e exatamente
o defeito que este repositorio persegue - e a onda 12 fechou com essa observacao sobre si mesma.

A sexta auditoria propos torna-la verificavel, e a proposta e adotada:

```
D_E = |{ c : state(c) em {candidate, promoted} e nao Valid(dossier(c)) }|
```

ERRATA 2026-08-19: o teto descrito neste paragrafo foi REMOVIDO pela onda 14, que mediu duas
fugas nele (o PR podia elevar a propria constante; pagar um dossie abria vaga). A fronteira e
hoje relacional contra o SHA-base - ADR 0034 -, e a divida virou vetor por dimensao - ADR 0035.
O paragrafo fica como registro do que se acreditou em 2026-08-18.

Medido hoje: **D_E = 8**, e `D_MAX = 8`. O teto inicial e o valor corrente, o que congela sem
exigir quitar a divida inteira antes de qualquer trabalho. Cada dossie fechado o abaixa;
levantar o teto para acomodar capability nova e a forma de fingir que a divida nao existe, e
esta proibido no cabecalho do proprio portao.

**Errata: a primeira versao deste mecanismo nao congelava nada.** O portao final mediu que
`D_E` contava apenas `{candidate, promoted}` - e a policy declara `initial_state: quarantine`.
O estado em que TODA capability nasce ficava fora da contagem, e `CC3` nao proibia
`quarantine` + `installed`. Resultado medido: capability nova nascendo em `quarantine`
instalada passava com `D_E=8 de 10 capabilities`, rc=0. Entrada gratuita e ilimitada, sem
precisar levantar o teto - a proibicao do cabecalho fora escrita contra o ataque errado.

Corrigido nos dois lados: `quarantine` entra em `D_E`, e capability em `quarantine` nao pode
estar instalada. Quarentena se exercita por invocacao local explicita, nao por instalacao -
capability nao avaliada e carregavel em toda sessao e exatamente o risco que a quarentena
existe para conter. Nenhuma capability esta em `quarantine` hoje, entao a correcao nao move
`D_E` nem o teto.

A excecao declarada permanece a mesma de sempre: correcao de seguranca, de regressao e reparo
de verificacao nao sao capability nova.

## Validacao

`tests/mutation/capability-conformance.sh`, com baseline verde exigido antes de qualquer
mutante e nove casos que mutam o REGISTRY ou o MANIFESTO, nunca o portao:

```
MC1 promoted sem dossie                        -> exit 1
MC2 dossie cobrindo 2 dos 7                    -> exit 1
MC3 dossie cobrindo os 7                       -> exit 0   <- o portao sabe dizer SIM
MC4 dossie com os 7 nomes e valores vazios     -> exit 1
MC5 nova capability em candidate               -> exit 1
MC6 nova capability em QUARANTINE              -> exit 1
MC7 capability em quarantine INSTALADA         -> exit 1
MC8 manifesto sem uma skill do registry        -> exit 1
MC9 manifesto com a ORIGEM do layout antigo    -> exit 1
```

`MC3` e o que impede a assercao de ser um portao que so recusa. Sem ele, "reprova tudo" e
indistinguivel de "verifica corretamente".

**Errata de metodo, apontada pelo portao final.** A primeira redacao desta secao listava sete
mutantes rodados A MAO num clone descartado, e nenhum comando do repositorio os reexecutava.
Tabela honesta e irreproduzivel e afirmacao, nao evidencia. `MC9` inclusive SOBREVIVEU a
primeira versao do portao, que comparava apenas o nome de destino e nao a origem - o manifesto
estagnado desta propria migracao passava pelo caso escrito para pega-la.

O portao entrou tambem em `tests/unit/runtime-ports.sh`, que e passo dedicado de CI com
propagacao de exit. Antes ele so aparecia na tabela de `docs/status.generated.md`, e o portao
final mostrou que esse enforcement e lavavel: com o portao reprovando, a instrucao publicada
manda regenerar o artefato, o que grava a linha vermelha e devolve o `--check` ao verde.

## Limites, declarados

O portao verifica que o dossie EXISTE, e um dict, e declara os sete campos exigidos com valor
nao-vazio. **Nao verifica que o experimento nele descrito tenha sido executado**, nem que suas
conclusoes sejam validas. E oraculo de conformidade, nao de veracidade experimental - e essa
lacuna so fecha com o experimento pareado, que continua ausente.

`CC2` (promoted exige dossie) passa hoje com POPULACAO VAZIA: nenhuma capability esta em
`promoted`. A anti-vacuidade do arquivo guarda o numero de capabilities e de requisitos, nao a
populacao promovida. A discriminacao esta provada por `MC1` a `MC4`, nao pela execucao corrente.

`CC5` compara o par (nome, origem) entre registry e manifesto. **Nao compara digest**: um
manifesto cuja origem e destino conferem mas cujo sha256 esta velho passa por aqui, e so
`install/verify.sh` pega. A ancora de `source` sob `execution/skills/` e estreitamento
deliberado - proibe por construcao skill instalada vinda de plugin ou de outro caminho, o que
`install/apply.sh` ja recusaria por confinamento, mas que aqui vira regra explicita.

A eficacia externa do harness permanece `NOT_VERIFIED`, e ha um argumento estrutural para isso
que esta onda torna mais nitido: a literatura disponivel mede pass rate, falha funcional e
regressao de eficiencia.

ERRATA 2026-08-20 - A FRASE ABAIXO ERA FALSA, E O PROPRIO REPOSITORIO A CONTRADIZIA. O texto
original dizia "Nenhum trabalho conhecido mede P(agente declara sucesso | verificador reprova)".
Isso e falso: `evidence/literature/arxiv-2606.09863.yaml` esta neste repositorio, registra que
o estudo "mede diretamente o fenomeno que motiva a regra dura deste repositorio", e traz as tres
metricas - 45-48% em tau2 single-control, 3% em dual-control telecom, 75,8% em AppWorld. O ADR
0010 cita o mesmo paper. Um ADR e um ledger de literatura no mesmo repositorio afirmavam coisas
opostas, e nada os confrontava.

Pior: esta contradicao foi apontada por auditoria externa numa rodada anterior e REFUTADA por
engano, com uma busca truncada por `head -8` cujos acertos no ADR ficaram abaixo do corte -
concluir ausencia a partir de observacao truncada e a forma mais barata do defeito que este
repositorio persegue, e ela foi cometida ao negar o defeito.

A lacuna REAL, que sobrevive a correcao:

```
nao ha demonstracao causal, pareada contra baseline equivalente, de que este harness
REDUZA P(agente declara sucesso | verificador reprova)
```

O desfecho ja foi medido pela literatura; o efeito DESTE aparato sobre ele, nao. E a propriedade
que este harness alega comprar. Num benchmark que pontua "a tarefa passou",
um harness que se recusa a declarar pronto sem evidencia aparece como custo puro. Os trabalhos
existentes limitam bem o CUSTO do procedimento e sao estruturalmente silenciosos sobre o
BENEFICIO. Enquanto o experimento com esse desfecho como coprimario nao existir, nem a favor
nem contra ha evidencia possivel.

Uma quarta dimensao proposta na sexta auditoria fica registrada e NAO implementada:
`EvidenceValidity`. Um dossie legitimo em `t0` pode deixar de valer em `t1` apos atualizacao de
runtime ou modelo, e o schema atual nao expressa `evaluated_with` nem status `stale`. Isso e a
proxima onda, nao esta.

> **ERRATA (ver `docs/adr/0046-evidencia-envelhece-quando-o-ambiente-muda.md`).** O paragrafo
> acima ficou desatualizado e permaneceu publicado sem correcao por duas ondas. `evaluated_with`
> NAO ficou para "a proxima onda": entrou na onda 15 (`docs/adr/0035-a-divida-era-de-uma-classe-so.md`,
> secao "EvidenceValidity: o dossie tem data de validade") e `tests/unit/capability-conformance.py`
> ja o exige, com mutantes MCAP18/19/20 cobrindo a exigencia, desde entao. O status `stale` como
> VALOR do vocabulario de `evidence.status` e que era novidade genuina - e a onda 28 (ADR 0046) o
> entrega. Os tres documentos (este, `docs/adr/0034` e `docs/adr/0035`) afirmavam coisas
> diferentes sobre o mesmo campo ao mesmo tempo, e nada os confrontava ate agora - a mesma classe
> que a errata de `docs/adr/0033:213-224` ja registrou uma vez, cometida de novo aqui.
