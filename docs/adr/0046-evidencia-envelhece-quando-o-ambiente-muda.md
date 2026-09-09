# ADR 0046 - Evidencia envelhece quando o ambiente muda

Data: 2026-09-09
Estado: aceito
Sucede: ADR 0044 (lifecycle e exposicao ao router sao eixos independentes)

## Contexto

`evaluated_with` NAO E NOVIDADE DESTA ONDA. Ele entrou na onda 15 (ver `docs/adr/0035-a-divida-era-de-uma-classe-so.md`, secao "EvidenceValidity: o dossie tem data de validade") e ja esta em producao desde entao: `tests/unit/capability-conformance.py` exige, dentro de `dossie_valido()`, que o dossie declare `evaluated_with` como dicionario com `runtime` e `model` nao-vazios, mais `artifact_digest` e `policy_digest` que batem com o computado. Os mutantes MCAP18/MCAP19/MCAP20 ja cobriam essa exigencia antes desta onda.

O que faltava, medido e reproduzido nesta onda antes de qualquer edicao:

```
arena isolada, baseline verde (TOTAL=38 FAIL=0)

dossie 7/7, digests casados, runtime={"claude_code":"0.0.1-inexistente"},
model={"name":"modelo-que-nunca-existiu"}

MEDIDO: exit=0, TOTAL=38 FAIL=0
```

Um dossie que declara um runtime e um modelo que nao existem em lugar nenhum era APROVADO. A razao e estrutural, nao um descuido pontual: `evaluated_with.runtime`/`.model` eram campos OBRIGATORIOS mas DECLARADOS SEM SEGUNDO LADO - a policy exigia que existissem, nunca contra o que comparar. `orchestration/evidence-policy.json:staleness.limit` dizia isso explicitamente ("nao conferidos contra nada"), depois de uma correcao anterior que removeu a alegacao falsa de que eles eram "conferidos contra `orchestration/environment.json` - arquivo que nunca existiu".

## Decisao

`orchestration/environment.json` passa a EXISTIR. Ele declara o envelope `supported` de `runtime`/`runtime_version`/`model` que a governanca aceita como ambiente de avaliacao valido. Fica em arquivo SEPARADO de `orchestration/evidence-policy.json` por uma razao mecanica, nao estetica: `tests/unit/capability-conformance.py:_digest_da_policy` hasheia `skill-policy.json` + `evidence-policy.json` para decidir `policy_digest`. Se o envelope morasse dentro da policy, toda subida de versao de runtime aceita invalidaria TODOS os dossies por `policy_digest` - colapsando exatamente a distincao que `staleness.invalidated_by` existe para manter (artifact_digest / policy_digest / runtime / model sao QUATRO causas distintas de envelhecimento, nao uma).

`orchestration/evidence-policy.json:staleness` ganha, sem criar bloco novo:

- `evidence_status_vocabulary: ["fresh", "stale", "absent"]` - vocabulario FECHADO de `evidence.status`, lido pelo portao (nunca hardcoded nele);
- `evaluated_with_required_keys` - os dois digests ja exigidos mais `runtime`, `runtime_version`, `model` e `skill_version`;
- `reevaluation_triggers.upstream_supersession` - gatilho de REAVALIACAO, nunca de depreciacao automatica: o runtime nativo (ou o modelo) pode ter absorvido a funcao de uma capability sem que ela deixe de estar correta;
- `stale_is_not_deprecated: true`, com a razao escrita: `stale` e propriedade da PROVA, `deprecated` e propriedade do CICLO DE VIDA.

`tests/unit/capability-conformance.py` ganha `_status_derivado()`, que calcula o status MECANICO do dossie (`absent`/`stale`/`fresh`) a partir de quatro checagens - dois digests computados (ja existiam) e, agora, `runtime`/`runtime_version`/`model` declarados comparados contra o envelope de `orchestration/environment.json`, lido PELO LEITOR passado (nunca por `_le_do_disco` direto - o mesmo achado C5/F2 que ja tinha corrigido `_digest_de`: usar o disco do processo para julgar a arvore-base e fail-open). `dossie_valido()` passa a exigir DUAS coisas: a governanca declarou `evidence.status == "fresh"` E a derivacao mecanica confirma `fresh`. A secao nova CC9 confere, para TODA capability (nao so as promovidas), que o status declarado bate com o derivado, que o vocabulario e fechado, e que `upstream_supersession` aberto bloqueia `fresh` sem mover `state` nem `installed`.

`tests/mutation/capability-conformance.sh` ganha quatro mutantes (`EXPECTED_MUTANTS` 29 -> 33) e renomeia os sete usos do literal `"status":"valid"` para `"status":"fresh"`:

- MCAP30 (o F2P desta onda): dossie 7/7 com `evaluated_with` declarando runtime/modelo fora do envelope - `want=1`. Reproduzido ANTES do fix contra a arvore original: `want=1` recebia `0`.
- MCAP31: `evidence.status` fora do vocabulario fechado - `want=1`.
- MCAP32 (controle positivo do criterio "stale nao implica deprecated"): capability `candidate`+`installed=true` com `evidence.status: "stale"` - `want=0`, e a capability permanece em `install/manifest.lock`.
- MCAP33 (controle negativo que da sentido ao par): a MESMA capability com `state: "deprecated"` - `want=1`, porque `CC3` ja reprova instalacao indevida. Sem o par, MCAP32 nao discriminaria "stale continua instalada" de "o portao nao olha instalacao".

Achado colateral, corrigido no mesmo arquivo por compartilhar a causa raiz que bloqueava a prova de MCAP32: `execution/skills/nova/` era criado no disco por MCAP10/MCAP11 e so era limpo no FIM do arnes; `_rst` restaura `registry.json`/`manifest.lock`, nao o diretorio. Todo mutante `want=0` posterior a MCAP10/11 herdava uma reprovacao de `CC3` (bijecao disco-registry) que nada tinha a ver com a propria mutacao - mascarada ate agora porque nenhum mutante `want=0` existia depois de MCAP11. Corrigido com limpeza imediata apos MCAP11, em vez de so no fim.

## Limite declarado

A comparacao introduzida e DECLARADO contra DECLARADO. O dossie declara um `evaluated_with`; `orchestration/environment.json` declara um `supported`; o mesmo PR pode escrever os dois lados. Isto e ESTRITAMENTE MAIS que a ausencia total de comparacao que valia ate esta onda - um dossie que declarasse um runtime inexistente deixa de ser aprovado -, e NAO E observacao do runtime real que executa a sessao. Por isso `runtime`/`runtime_version`/`model` continuam classificados em `staleness.declared_only`, nao em `mechanically_checked`: essa segunda categoria fica reservada a comparacao contra DIGEST computado sobre bytes reais (`artifact_digest`, `policy_digest`), que nenhum PR sozinho pode forjar sem mudar o artefato que o digest mede.

`skill_version` e exigido (presenca, nao vazio) e NAO comparado contra nada: nao ha, neste repositorio, um oraculo do "skill_version atualmente vigente" contra o qual compara-lo. Exigir o campo torna a dependencia visivel no artefato; nao a torna medida - o mesmo principio ja aplicado a `runtime`/`model` desde a onda 15.

## Tensao nao resolvida, declarada em vez de silenciada

`orchestration/skill-policy.json:lifecycle.deprecate_on` contem `version_mismatch`, e `tests/unit/methodology.py:51` fixa esse item por assercao. Isso aponta na direcao OPOSTA do que esta onda decide: aqui, mudanca de runtime/versao produz `stale`, nunca `deprecated` automaticamente. `orchestration/skill-policy.json` esta fora do escopo desta onda por dois motivos independentes - esta sob posse de outro trilho em execucao na mesma branch, e `tests/unit/methodology.py:51` amarra `version_mismatch` a `deprecate_on` por assercao propria. Resolver a tensao exigiria decidir se `version_mismatch` em `deprecate_on` significa algo mais estreito que "toda mudanca de versao" (por exemplo, incompatibilidade de major version declarada, distinta de uma capability ficar `stale` por sair do envelope de `orchestration/environment.json`) ou se as duas policies precisam ser reconciliadas. Nenhuma das duas coisas foi feita aqui. O mecanismo novo entra em `orchestration/evidence-policy.json` e NAO edita nem contradiz o campo antigo em bytes - convive com ele, com a tensao semantica registrada, nao resolvida.

## Errata

`docs/adr/0033-estado-nao-e-nome-de-diretorio.md:242-243` e `docs/adr/0034-o-teto-que-o-proprio-pr-podia-levantar.md:128-130` ainda afirmam, no texto publicado, que "o schema atual nao expressa `evaluated_with` nem status `stale`" e que isso "e a proxima onda, nao esta". Essa afirmacao ficou desatualizada a partir da onda 15 (`evaluated_with` ja existia e era exigido) e mais ainda a partir desta onda (`stale` agora existe como valor do vocabulario). `docs/adr/0035-a-divida-era-de-uma-classe-so.md:145-156` ja documentava `evaluated_with` como entregue; os tres documentos conviviam sem que nada os confrontasse - a mesma classe de defeito que `docs/adr/0033-estado-nao-e-nome-de-diretorio.md:213-224` registra como errata de si mesmo. As duas linhas foram marcadas com nota de errata apontando para este ADR, no mesmo padrao ja usado nesses tres documentos para claims que o proprio codigo ultrapassou; o texto original de 2026 permanece legivel, como historico.

## O que fica de fora desta onda, e por que

Os dois artigos `arxiv-2602.11988` e `arxiv-2608.14036` (criterio de aceite 5 da delegacao) NAO entraram em `evidence/literature/`. A delegacao especifica o CONTRATO de formato (`evidence/validate-literature.py`) mas nao traz citacao, autores, metodologia nem achados numericos desses dois papers - dados que este trabalho nao tem como obter (sem acesso a rede nesta sessao) nem como inferir sem fabricar. `evidence/validate-literature.py` exige, para todo numero fora de `findings`, um marcador de fonte no proprio texto; forjar citacao, `study_quality` ou `findings` para passar no validador seria produzir FORMA sem CONTEUDO verificavel - a mesma classe de defeito que este repositorio inteiro existe para tornar cara. Pela mesma razao, a adicao de um finding de magnitude "-10pp" a `evidence/literature/arxiv-2603.15401.yaml` tambem nao foi feita: a delegacao condiciona a adicao a "se a fonte primaria sustentar", e nao ha, nesta sessao, acesso para conferir isso contra a fonte primaria. `evidence/literature/arxiv-2603.15401.yaml` permanece exatamente como estava. Fica registrado como pendencia que exige acesso a fonte primaria, nao como trabalho recusado.
