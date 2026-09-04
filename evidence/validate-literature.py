#!/usr/bin/env python3
"""Validador da camada de qualidade de evidencia para LITERATURA EXTERNA (evidence/literature/*.yaml).

POR QUE ESTE ARQUIVO EXISTE
----------------------------
`evidence/claims/` (validate-claims.py) ancora uma AFIRMACAO DESTE REPOSITORIO em evidencia
DESTE REPOSITORIO (suite, blob, execucao de CI). Isso nao cobre um tipo diferente de citacao:
quando um documento do projeto (README, ADR, prompt de agente) invoca um PAPER EXTERNO para
justificar uma decisao. Para esse caso a pergunta nao e "essa evidencia existe" - ela existe,
o paper foi publicado - e sim "essa evidencia SE APLICA a este harness, e com que forca".

O defeito que motivou este arquivo: a secao 6.1 do README citava SWE-Skills-Bench como "39 de
49 skills sem melhoria de pass rate, ganho medio de +1,2 ponto percentual" sem o baseline
(89,8% sem skill), sem o teto de melhoria que esse baseline implica (no maximo +10,2pp), sem
declarar que o experimento usa um UNICO modelo e UNICO scaffold (avaliar outros frameworks de
agente consta no artigo como trabalho FUTURO, nao como algo que ele realiza) e sem o status de
pre-print com resultados
preliminares. Cada numero isolado era verdadeiro; a citacao, no conjunto, selecionava o dado
mais favoravel ao argumento e descartava o contexto que o qualifica - recall bias, nao
fabricacao, e por isso resiste a checagem numero-a-numero.

Precedente proprio, ja registrado neste repositorio antes deste arquivo existir: `docs/adr/0011`
audita a mesma classe de defeito contra `arXiv:2606.09863` - a config citava "false success
45-89%" quando o paper reporta 45-48% / 3% / 75.8% em tres condicoes distintas. Nao existe a
faixa 45-89%. Quatro de cinco citacoes auditadas naquele ADR falharam sob a mesma regra que as
proibia. Este validador nao substitui a leitura humana da fonte primaria - nenhum programa faz
isso sem acesso ao PDF - mas impede que um numero fique na prosa argumentativa sem o contexto
que o qualifica, que foi o mecanismo concreto dos dois defeitos acima.

TRES DIMENSOES, SEPARADAS DE PROPOSITO
---------------------------------------
  provenance     : ONDE o resultado foi publicado (peer_reviewed, preprint, vendor_primary,
                   local_experiment). Nao diz nada sobre desenho metodologico.
  study_quality  : COMO o estudo foi desenhado (benchmark, n, modelos, scaffold, oraculo,
                   baseline, trials repetidos, incerteza reportada, disponibilidade de
                   codigo/dados, replicacao).
  applicability  : O QUANTO o dominio, o scaffold e o oraculo do estudo se parecem com os
                   deste repositorio.

Um estudo pode ser peer-reviewed, ter n grande e ainda ser apenas EXTRAPOLATED para este
repositorio, se foi medido num scaffold e dominio diferentes - caso de SWE-Skills-Bench
(Claude Code + Claude Haiku 4.5 unicos) contra um harness que roda Claude Code E Codex. E o
inverso tambem vale: um pre-print pode ter applicability alta quando mede exatamente a classe
de artefato que uma politica deste repositorio trata - caso dos dois estudos de seguranca de
marketplace de skill (`arxiv-2601.10338`, `arxiv-2602.06547`): nao avaliam `tollens`, mas
medem risco na MESMA classe de artefato (skills) que a politica de quarentena deste
repositorio governa.

`inference_strength` - A ESCALA FECHADA, E POR QUE ELA E O CAMPO MAIS IMPORTANTE
-----------------------------------------------------------------------------------
  DIRECT       : mede o proprio artefato/mecanismo deste repositorio.
  SUPPORTED    : mede o mesmo fenomeno, em populacao/dominio proximo, com metodologia solida.
  SUGGESTIVE   : aponta na mesma direcao, mas com heterogeneidade ou lacuna metodologica
                 relevante o bastante para pesar na leitura.
  EXTRAPOLATED : modelo/scaffold/dominio unicos e distintos deste repositorio; aplicar aqui
                 exige assumir uma generalizacao que o estudo, sozinho, nao demonstra.
  SPECULATIVE  : nenhuma medicao direta; a citacao vale como plausibilidade teorica, nao como
                 evidencia de efeito.

O QUE O VALIDADOR IMPOE
-------------------------
  1. Campos obrigatorios presentes (raiz, `study_quality`, `applicability`, `findings[]`).
  2. `inference_strength` e `provenance` dentro dos vocabularios fechados.
  3. Toda afirmacao numerica tem fonte declarada, por DOIS mecanismos que se cobrem:
     a) `findings[]` e o lugar estrutural para um numero: cada item exige `metric`, `value` E
        `source` (nao vazios) - o campo `source` E a fonte declarada.
     b) qualquer OUTRA string do documento (`study_quality`, `applicability`,
        `inference_rationale`, `limitations`) que contenha um digito precisa conter, ela
        mesma, a palavra `fonte` ou `verificad` (cobre verificado/nao verificado/verificacao).
        Sem isso um numero poderia entrar pela prosa argumentativa - `inference_rationale` ou
        `applicability` - sem nunca passar pelo mecanismo de sourcing, que foi exatamente a
        rota do defeito de 6.1: um numero solto dentro de um paragrafo de argumento, sem o
        contexto que o qualifica.
     Campos bibliograficos (`literature_id`, `identifier`, `url`, `citation`, `cited_in`) ficam
     de fora da varredura (b): sao METADADOS de endereco (onde o paper esta, onde ele e citado
     no repositorio), nao afirmacoes empiricas sobre o que o paper mediu.
  4. Nome do arquivo == `literature_id` + `.yaml`, mesma disciplina de `evidence/claims`.
  5. Contradicao interna ESTRITA: se um trecho entre aspas retas (`"..."`, 8+ caracteres) esta a
     ATE `JANELA_RETRATACAO` (100) caracteres de um marcador de retratacao ANCORADO (formas de
     palavra especificas - `inventada/inventado/inventadas/inventados/inventou/inventaram`,
     `fabricada/fabricado/fabricadas/fabricados`, `nao existe no`/`nao existe na` com fronteira
     de palavra), esse MESMO trecho, palavra por palavra, nao pode reaparecer em NENHUM outro
     campo do documento sem o mesmo tipo de marcador por perto NESSE outro campo. "Por perto" e
     literal: uma janela de caracteres ao redor do marcador, nao o campo inteiro - um campo pode
     legitimamente conter, na mesma citacao bibliografica, o titulo CORRETO (longe do marcador,
     citado por si) e o titulo INCORRETO retratado (perto do marcador, "... nao existe na
     fonte"), e so o segundo conta como retratado. Ver a secao de LIMITES abaixo: isto so cobre
     reaparicao VERBATIM, nao paráfrase, e a janela e um heuristico de caractere, nao de
     sentenca - a distincao importa e esta documentada, nao e um detalhe de implementacao.

O QUE ESTE VALIDADOR NAO FAZ - limites declarados
---------------------------------------------------
  - REGRA 5 (contradicao interna) SO detecta reaparicao VERBATIM da citacao retratada. NAO
    detecta uma afirmacao retratada que reaparece como PARAFRASE em outro campo - que foi o
    defeito real corrigido em arxiv-2603.15401.yaml nesta mesma onda: a citacao inventada em
    ingles ("does not evaluate alternative agent frameworks") foi retratada em `scaffold`, mas
    a MESMA alegacao, reescrita em portugues ("declara explicitamente nao avaliar outros
    frameworks"), sobreviveu como fato em `applicability.scaffold_similarity` e em
    `limitations` - sem repetir a string retratada, portanto invisivel a um comparador de
    substring. Detectar isso exigiria reconhecer que duas sentencas com palavras DIFERENTES
    afirmam a MESMA proposicao (entailment/parafrase), o que este programa - varredura de
    string e vocabulario fechado, sem compreensao de linguagem - nao pode fazer honestamente.
    Uma aproximacao por sobreposicao de palavras-chave foi avaliada e descartada: o termo
    partilhado entre a citacao retratada e a parafrase e "frameworks", que tambem aparece em
    diversas outras frases legitimas e nao-contraditorias deste mesmo documento (ex.:
    `study_quality.scaffold`, corretamente reescrita apos a correcao) - qualquer regra ligada a
    esse termo teria ALTO falso-positivo, calibrado a um unico caso passado, nao um detector
    geral. Regra 5 fica, deliberadamente, restrita ao subconjunto que PODE ser verificado sem
    ambiguidade: string identica reaparecendo sem a marca de retratacao. A defesa real contra o
    caso de parafrase continua sendo leitura humana da fonte primaria, nao este validador.
  - REGRA 5 teve, ela mesma, um falso positivo e um falso negativo medidos por revisao
    independente antes desta correcao - registrados aqui porque uma garantia que falha sob o
    proprio criterio que impoe merece o mesmo tratamento que exige dos outros:
    FALSO POSITIVO: a varredura de "reaparicao verbatim" comparava o CAMPO INTEIRO (nao uma
    janela ao redor do marcador). Em arxiv-2602.06547.yaml o campo `citation` contem, na MESMA
    frase, o marcador de retratacao ("... nao existe na fonte") e, numa frase ANTERIOR do mesmo
    campo, o titulo CORRETO entre aspas ("Do Not Mention This to the User") - citado
    legitimamente, nao retratado. Ao comparar o campo inteiro, QUALQUER aspa do campo virava
    "retratada", inclusive o titulo correto; reusar esse titulo em `limitations` (uso legitimo)
    disparava "contradicao interna" sobre uma retratacao que o documento nunca fez. Corrigido
    com `JANELA_RETRATACAO`: so a aspa PROXIMA do marcador (100 caracteres) conta como retratada
    (medido: a citacao fabricada real fica a 2 caracteres do marcador; o titulo correto, a ~306).
    FALSO NEGATIVO: o marcador de retratacao anterior (substring desancorada, sem fronteira de
    palavra no fim) casava qualquer palavra comecando por "invent-", inclusive "inventario" (sem
    relacao com fabricacao). Um campo que reafirma uma citacao fabricada como fato, mas que por
    acaso contem a palavra "inventario" (ex.: "Ver o inventario deste estudo, '<titulo
    fabricado>', para a metodologia"), casava RE_RETRATACAO por acidente e o codigo tratava esse
    campo como se TAMBEM estivesse retratando - a reafirmacao passava sem violacao (par
    controlado: a mesma frase com "resumo" no lugar de "inventario" era corretamente pega).
    Corrigido ancorando RE_RETRATACAO a formas de palavra especificas (inventada/inventado/
    .../fabricada/fabricado/...), que nao casam "inventario".
    Ambos os casos tem teste de regressao dedicado em `tests/unit/literatura.sh` (par controlado
    idioma-honesto-passa / fabricacao-real-e-pega).
  - REGRA 5 teve um TERCEIRO falso negativo, estrutural, medido em 2026-08-11 (onda 5, D8): a
    janela de proximidade exigia que o trecho ENTRE ASPAS INTEIRO coubesse dentro dos
    JANELA_RETRATACAO (100) caracteres de cada lado do marcador (`RE_ASPAS.finditer(texto, ini,
    fim)` tratava o texto como se terminasse em `fim` - o casamento tinha de comecar E terminar
    dentro da fatia). RE_ASPAS aceita aspas de ate 300 caracteres; toda aspa entre ~97 e 300
    caracteres colada ao marcador (gap de poucos caracteres) ESCAPAVA, porque o span INTEIRO nao
    cabia na janela de 200 caracteres (100 para cada lado) - o oposto do falso positivo que
    motivou a janela: aqui uma citacao LONGA e PROXIMA nao contava como retratada por nao COUBER,
    nao por estar longe. Medido: aspa de 96 caracteres coladas ao marcador DETECTAVA, 97+
    ESCAPAVA; alcancavel no corpus real (`arxiv-2603.15401.yaml`, `study_quality.scaffold`, aspa
    de 223 caracteres a 113 do marcador mais proximo - hoje classificada corretamente como NAO
    retratada porque e o texto genuino do artigo, mas pelo motivo ERRADO: o escape veio do
    comprimento, nao da distancia semantica, e uma fabricacao do mesmo tamanho na mesma posicao
    teria escapado igual). Corrigido trocando o CRITERIO de proximidade: em vez de "o span
    inteiro cabe numa janela fixa ao redor do marcador", agora e "a distancia entre o marcador e
    a BORDA MAIS PROXIMA da aspa e <= JANELA_RETRATACAO" (`_distancia_span`), o mesmo principio
    de "por perto" que a mensagem de violacao sempre alegou, so que sem o teto artificial de
    RE_ASPAS entrar na conta - o comprimento da aspa deixa de decidir deteccao. As duas
    referencias reais continuam discriminando com a MESMA margem: a citacao fabricada de
    arxiv-2602.06547 fica a 2 caracteres do marcador mais proximo (detecta), o titulo correto do
    mesmo campo a ~306 (nao detecta) - a alternativa descartada foi so alargar JANELA_RETRATACAO
    ate cobrir o teto de RE_ASPAS (300): isso reabriria o falso positivo original com uma janela
    ainda maior, porque duas aspas curtas DENTRO de ~300 caracteres do MESMO marcador (comum em
    paragrafo de citacao bibliografica) voltariam a colidir independente do proprio comprimento
    delas.
  - A JANELA_RETRATACAO (100 caracteres) e um heuristico de CARACTERE, nao de SENTENCA: nao ha
    parser de fronteira de frase (citacoes academicas tem pontos apos iniciais de autor - "Zhang,
    L. Y." - que quebrariam uma divisao ingenua por ".") . Residual conhecido: se o titulo
    INCORRETO e o titulo CORRETO aparecerem os DOIS dentro de 100 caracteres do MESMO marcador
    (frase muito curta, ex.: "'Y' substitui 'X', que nao existe na fonte."), o titulo correto
    tambem seria classificado como retratado por estar perto - o mesmo residual que motivou esta
    correcao, so que numa janela bem mais estreita que "o campo inteiro". Nao ha caso assim no
    corpus atual (conferido nesta sessao); se aparecer, a citacao correta ficaria impedida de
    reaparecer alhures ate o texto ser reescrito com mais distancia do marcador.
  - Nao contata a rede, nao baixa o PDF, nao confere se o numero, o titulo, os autores ou uma
    citacao verbatim batem com o artigo. VERDE AQUI E CONFORMIDADE DE FORMA (campos presentes,
    vocabulario fechado, todo numero com um marcador de fonte declarado), NUNCA FIDELIDADE DE
    CONTEUDO A FONTE PRIMARIA. Essa conferencia so pode ser humana, com acesso a fonte, numero a
    numero e citacao a citacao.
  - PROVA CONCRETA, nao hipotetica: uma rodada anterior desta mesma camada (onda 1) declarou os
    27 casos de `tests/unit/literatura.sh` verdes e os 6 arquivos de `evidence/literature/*.yaml`
    validos com (a) o TITULO de arxiv-2602.06547 fabricado - "Malicious Agent Skills in the
    Wild: A Large-Scale Security Empirical Study", que nao existe; o titulo real e "Do Not
    Mention This to the User": Detecting and Understanding Malicious Agent Skills in the Wild
    -, (b) uma citacao verbatim INVENTADA em arxiv-2603.15401.yaml ("does not evaluate
    alternative agent frameworks", marcada como "verificado no texto completo" mas ausente da
    fonte), e (c) iniciais de autor trocadas no mesmo arquivo. Nenhuma dessas tres violacoes e
    detectavel pelos mecanismos deste programa - `citation` e campo bibliografico (fora da
    varredura de marcador de fonte, ver CAMPOS_BIBLIOGRAFICOS) e o parser YAML nao sabe o que um
    arXiv realmente diz. As tres so foram encontradas quando um agente leu a fonte primaria de
    novo, fora deste validador. Este historico e o motivo desta secao, nao um hipotetico.
  - Nao decide SE a forca de inferencia declarada esta CORRETA - confere so que o valor esta no
    vocabulario fechado. A calibracao entre o estudo e a forca de inferencia e argumento
    humano, exatamente como a ligacao entre evidencia e tese em `evidence/claims`
    (validate-claims.py, mesma limitacao declarada la).
  - Nao impede que o mesmo numero apareca com valores diferentes em dois arquivos distintos.
  - A varredura de "numero sem marcador de fonte" e um heuristico textual (regex), nao um
    parser semantico: uma string que contenha um digito por acidente (ex.: um identificador
    interno) e tratada como afirmacao numerica do mesmo jeito. O custo dessa simplicidade e
    falso positivo ocasional, corrigivel adicionando o marcador; a alternativa - permitir
    numeros soltos por padrao - e o defeito que este arquivo existe para fechar. O mesmo
    heuristico tambem e CEGO ao CONTEUDO do marcador: uma string pode conter a palavra "fonte"
    e ainda assim carregar um numero, titulo ou quote que a fonte declarada nao sustenta - o
    marcador prova que uma fonte foi APONTADA, nao que ela foi CONFERIDA.
"""
import os
import re
import sys

EXIT_OK, EXIT_VIOLACAO, EXIT_NAO_VERIFICADO = 0, 1, 2

try:
    import yaml
except ImportError:
    # DEPENDENCIA DE ORACULO ausente, nao variacao de ambiente: sem parser nao ha como decidir
    # se a camada de literatura e valida, e "nao reprovou" seria indistinguivel de "nao foi
    # verificado" (mesma razao documentada em validate-claims.py).
    sys.stderr.write(
        "NAO VERIFICADO: pyyaml ausente. A camada de literatura nao pode ser validada neste "
        "ambiente. Instale a versao pinada (ver .github/workflows/verify-pr.yml).\n")
    sys.exit(EXIT_NAO_VERIFICADO)

PROVENIENCIA = {"peer_reviewed", "preprint", "vendor_primary", "local_experiment"}
FORCA_INFERENCIA = {"DIRECT", "SUPPORTED", "SUGGESTIVE", "EXTRAPOLATED", "SPECULATIVE"}

OBRIGATORIOS = ("literature_id", "citation", "identifier", "url", "provenance",
                "study_quality", "applicability", "inference_strength",
                "inference_rationale", "findings", "limitations")

# Os DEZ subcampos de study_quality pedidos pela delegacao, verbatim: "benchmark, n, modelos,
# scaffold, oraculo, baseline, trials repetidos, incerteza reportada, codigo/dados
# disponiveis, replicado".
CAMPOS_STUDY_QUALITY = ("benchmark", "n", "models", "scaffold", "oracle", "baseline",
                        "trials_repeated", "uncertainty_reported", "code_data_available",
                        "replicated")
# Os TRES subcampos de applicability: "domain_similarity, scaffold_similarity, oracle_similarity".
CAMPOS_APPLICABILITY = ("domain_similarity", "scaffold_similarity", "oracle_similarity")

# Campos de ENDERECO (onde o paper esta, onde ele e citado) - nao sao afirmacoes empiricas e
# por isso ficam fora da varredura de "numero precisa de marcador de fonte".
CAMPOS_BIBLIOGRAFICOS = {"literature_id", "identifier", "url", "citation", "cited_in"}

RE_LITERATURE_ID = re.compile(r"^[a-z][a-z0-9]*(?:[.\-][a-z0-9]+)*$")
RE_METRIC = re.compile(r"^[a-z][a-z0-9_]*$")
RE_DIGIT = re.compile(r"\d")
# "fonte" ou "verificad" (verificado / nao verificado / verificacao) - o marcador minimo que
# obriga quem escreve a declarar, no proprio texto, de onde o numero vem ou que ele nao foi
# conferido. Case-insensitive: nao ha ganho em discriminar maiusculas aqui.
RE_MARCADOR_FONTE = re.compile(r"fonte|verificad", re.IGNORECASE)

# REGRA 5 (contradicao interna, verbatim apenas - ver docstring, secao de LIMITES, para o que
# isto NAO cobre). RE_RETRATACAO reconhece o vocabulario ja usado neste repositorio para marcar
# uma afirmacao retratada (ver arxiv-2602.06547.yaml e arxiv-2603.15401.yaml apos a correcao
# desta onda). ANCORADO em formas de palavra especificas do vocabulario de retratacao, nao em
# substring solta: a versao anterior usava `\binvent\w*`, que casa "inventario" (inventory, sem
# relacao com fabricacao) e qualquer outra palavra que comece por "invent-"; a forma atual so
# casa as conjugacoes que este repositorio de fato usa para marcar retratacao (inventada/
# inventado/inventadas/inventados/inventou/inventaram). Mesma logica para "nao existe (no|na)":
# o `\b` ao final impede que a substring case dentro de uma palavra maior nao relacionada (ex.:
# "nao existe nada de errado" tem "nao existe na" como substring, mas "na" ali nao termina em
# fronteira de palavra - "nada" continua). RE_ASPAS extrai trechos entre aspas retas de 8+
# caracteres - abaixo disso o risco de casar um fragmento generico (nome de metrica, sigla) sobe
# sem ganho de deteccao real.
RE_RETRATACAO = re.compile(
    r"nao existe (no|na)\b|\binvent(ada|ado|adas|ados|ou|aram)\b|\bfabricad(a|o|as|os)\b",
    re.IGNORECASE)
RE_ASPAS = re.compile(r'"([^"]{8,300})"')

# JANELA_RETRATACAO: quantos caracteres, para cada lado de um marcador de retratacao, contam
# como "por perto" (a mensagem de violacao sempre disse "por perto" - antes desta correcao o
# codigo comparava o CAMPO INTEIRO, entao a mensagem prometia proximidade que a implementacao
# nao entregava). Medido no proprio corpus desta camada: em arxiv-2602.06547.yaml a citacao
# FABRICADA fica a 2 caracteres do marcador de retratacao ("... nao existe na fonte."), enquanto
# o TITULO CORRETO do mesmo campo (citado legitimamente no inicio da mesma frase de citacao) fica
# a ~306 caracteres do marcador. 100 caracteres fica confortavelmente entre os dois casos reais:
# cobre a citacao retratada de verdade, exclui o titulo correto reaproveitado alhures. E um
# heuristico de caractere, nao de sentenca - ver LIMITES na docstring do modulo para o residual
# que isso deixa em aberto.
JANELA_RETRATACAO = 100


def _varre_fonte(valor, caminho, violacoes):
    """Percorre recursivamente o documento (exceto o que o chamador ja excluiu) e reprova toda
    STRING que contem digito sem conter, ela mesma, um marcador de fonte declarada."""
    if isinstance(valor, dict):
        for k, v in valor.items():
            _varre_fonte(v, f"{caminho}.{k}" if caminho else str(k), violacoes)
    elif isinstance(valor, list):
        for i, v in enumerate(valor):
            _varre_fonte(v, f"{caminho}[{i}]", violacoes)
    elif isinstance(valor, str):
        if RE_DIGIT.search(valor) and not RE_MARCADOR_FONTE.search(valor):
            violacoes.append(
                f"{caminho}: contem numero sem marcador de fonte declarada "
                f"('fonte'/'verificad' ausente do proprio texto): {valor!r}")


def _coleta_folhas(valor, caminho, folhas):
    """Coleta todo par (caminho, texto) de string do documento, achatando dict/list. Usado pela
    REGRA 5 (contradicao interna) - diferente de _varre_fonte, aqui NAO ha exclusao de campo
    bibliografico: uma citacao ou titulo fabricado (campo `citation`) e exatamente o tipo de
    string que pode reaparecer, verbatim, em outro campo como se fosse fato nao-retratado."""
    if isinstance(valor, dict):
        for k, v in valor.items():
            _coleta_folhas(v, f"{caminho}.{k}" if caminho else str(k), folhas)
    elif isinstance(valor, list):
        for i, v in enumerate(valor):
            _coleta_folhas(v, f"{caminho}[{i}]", folhas)
    elif isinstance(valor, str):
        folhas.append((caminho, valor))


def _distancia_span(a, b):
    """Distancia em caracteres entre dois intervalos `(inicio, fim)` semi-abertos - o vao entre
    a BORDA mais proxima de um e a BORDA mais proxima do outro; zero se se sobrepoem. Nao importa
    qual dos dois vem primeiro no texto (a aspa pode vir antes OU depois do marcador - o corpus
    real usa as duas ordens).

    ONDA 5, D8 - por que a distancia e medida por BORDA, nao por span inteiro caber numa janela:
    a versao anterior exigia que o trecho entre aspas INTEIRO coubesse dentro de
    `[marcador.start()-JANELA, marcador.end()+JANELA)`, e RE_ASPAS aceita ate 300 caracteres -
    uma aspa longa colada ao marcador (gap de poucos caracteres) podia UM POUCO mais que a metade
    da janela e escapar so por comprimento, nunca por distancia real. Medir a distancia entre a
    BORDA mais proxima de cada intervalo decide "por perto" pelo mesmo criterio, sem que o
    comprimento da aspa entre na conta - ver docstring do modulo, secao de LIMITES, para os dois
    casos reais que ancoram o valor de JANELA_RETRATACAO."""
    if a[1] <= b[0]:
        return b[0] - a[1]
    if b[1] <= a[0]:
        return a[0] - b[1]
    return 0


def _citacoes_retratadas(texto):
    """Retorna {citacao_normalizada: texto_original} para toda citacao entre aspas cuja BORDA
    mais proxima fica a ATE JANELA_RETRATACAO caracteres de um marcador de retratacao NESTE
    MESMO texto - nao qualquer aspa do campo inteiro, e nao limitado pelo comprimento da aspa
    (ver `_distancia_span` e a nota de D8 na docstring do modulo). Isto e o mecanismo que torna
    'por perto' (a mensagem de violacao abaixo) literalmente verdadeiro: um campo pode
    legitimamente conter, na MESMA frase, o marcador de retratacao junto do titulo INCORRETO
    (perto - fica retratado) e, numa frase diferente do MESMO campo, o titulo CORRETO sendo
    citado de forma legitima (longe - nao fica retratado, e por isso pode reaparecer alhures
    como fato sem acusar contradicao)."""
    achadas = {}
    marcadores = [m.span() for m in RE_RETRATACAO.finditer(texto)]
    if not marcadores:
        return achadas
    for m in RE_ASPAS.finditer(texto):
        aspa = m.span()
        if any(_distancia_span(marcador, aspa) <= JANELA_RETRATACAO for marcador in marcadores):
            bruto = m.group(1).strip()
            norm = re.sub(r"\s+", " ", bruto).lower()
            if len(norm) >= 8:
                achadas.setdefault(norm, bruto)
    return achadas


def _varre_contradicao(doc):
    """REGRA 5: uma citacao entre aspas marcada como RETRATADA (fonte - RE_RETRATACAO, PROXIMA -
    JANELA_RETRATACAO) nao pode reaparecer, palavra por palavra, em outro campo do documento sem
    a mesma marca por perto NESSE outro campo. Escopo estrito e documentado: cobre so reaparicao
    VERBATIM, nao parafrase - ver docstring do modulo, secao 'O QUE ESTE VALIDADOR NAO FAZ', para
    o porque um comparador de parafrase nao seria honesto aqui."""
    violacoes = []
    folhas = []
    _coleta_folhas(doc, "", folhas)
    retratadas_por_campo = {caminho: _citacoes_retratadas(texto) for caminho, texto in folhas}

    for caminho, citacoes in retratadas_por_campo.items():
        if not citacoes:
            continue
        for outro_caminho, outro_texto in folhas:
            if outro_caminho == caminho:
                continue
            outro_norm = re.sub(r"\s+", " ", outro_texto).lower()
            outro_retratadas = retratadas_por_campo[outro_caminho]
            for norm, bruto in citacoes.items():
                if norm in outro_norm and norm not in outro_retratadas:
                    violacoes.append(
                        f"{caminho} retrata a citacao {bruto!r}, mas ela reaparece "
                        f"verbatim em {outro_caminho} sem marca de retratacao por perto - "
                        f"contradicao interna: afirmacao retratada numa secao, repetida como "
                        f"fato noutra")
    return violacoes


def _valida_findings(findings, arquivo):
    e = []
    def erro(msg):
        e.append(f"{os.path.basename(arquivo)}: {msg}")

    if not isinstance(findings, list) or not findings:
        erro("findings deve ser uma lista nao vazia - toda citacao numerica fica ancorada aqui")
        return e
    for i, f in enumerate(findings):
        if not isinstance(f, dict):
            erro(f"findings[{i}] deve ser um mapeamento com 'metric', 'value' e 'source'")
            continue
        for campo in ("metric", "value", "source"):
            if f.get(campo) in (None, ""):
                erro(f"findings[{i}].{campo} ausente ou vazio - sem 'source' o numero nao tem "
                     f"fonte declarada")
        metrica = f.get("metric")
        if isinstance(metrica, str) and metrica and not RE_METRIC.match(metrica):
            erro(f"findings[{i}].metric '{metrica}' fora do formato snake_case")
    return e


def valida(doc, arquivo, vistos):
    e = []
    def erro(msg):
        e.append(f"{os.path.basename(arquivo)}: {msg}")

    if not isinstance(doc, dict):
        erro("o arquivo nao contem um mapeamento YAML no topo")
        return e

    for campo in OBRIGATORIOS:
        if campo not in doc or doc[campo] in (None, "", [], {}):
            erro(f"campo obrigatorio ausente ou vazio: '{campo}'")
    if e:
        return e

    lid = str(doc["literature_id"])
    if not RE_LITERATURE_ID.match(lid):
        erro(f"literature_id '{lid}' fora do formato (letras/digitos minusculos, "
             f"separadores '-' ou '.')")
    if lid in vistos:
        erro(f"literature_id '{lid}' duplicado (ja usado em {vistos[lid]})")
    else:
        vistos[lid] = os.path.basename(arquivo)
    esperado = f"{lid}.yaml"
    if os.path.basename(arquivo) != esperado:
        erro(f"nome do arquivo deveria ser '{esperado}' para casar com literature_id")

    if doc["provenance"] not in PROVENIENCIA:
        erro(f"provenance '{doc['provenance']}' fora do vocabulario {sorted(PROVENIENCIA)}")

    if doc["inference_strength"] not in FORCA_INFERENCIA:
        erro(f"inference_strength '{doc['inference_strength']}' fora do vocabulario fechado "
             f"{sorted(FORCA_INFERENCIA)}")

    sq = doc.get("study_quality")
    if not isinstance(sq, dict):
        erro("study_quality deve ser um mapeamento")
    else:
        for campo in CAMPOS_STUDY_QUALITY:
            if campo not in sq or sq[campo] in (None, ""):
                erro(f"study_quality.{campo} ausente ou vazio")

    ap = doc.get("applicability")
    if not isinstance(ap, dict):
        erro("applicability deve ser um mapeamento")
    else:
        for campo in CAMPOS_APPLICABILITY:
            if campo not in ap or ap[campo] in (None, ""):
                erro(f"applicability.{campo} ausente ou vazio")

    if not isinstance(doc.get("inference_rationale"), str) or not doc["inference_rationale"].strip():
        erro("inference_rationale deve ser texto nao vazio explicando a forca declarada")

    e.extend(_valida_findings(doc.get("findings"), arquivo))

    if not isinstance(doc.get("limitations"), list) or not doc["limitations"]:
        erro("limitations deve ser uma lista nao vazia - todo estudo tem alcance finito")
    elif any(not isinstance(x, str) or not x.strip() for x in doc["limitations"]):
        erro("limitations nao pode conter item vazio")

    # REGRA 3(b): tudo o que NAO e campo bibliografico e NAO e a subarvore de findings (ja
    # coberta pela regra 3(a), acima) e varrido por numero sem marcador de fonte.
    resto = {k: v for k, v in doc.items() if k not in CAMPOS_BIBLIOGRAFICOS and k != "findings"}
    violacoes_fonte = []
    _varre_fonte(resto, "", violacoes_fonte)
    for v in violacoes_fonte:
        erro(v)

    # REGRA 5: contradicao interna verbatim (ver docstring do modulo e _varre_contradicao para
    # o escopo exato - so cobre reaparicao literal, nao parafrase). Roda sobre o DOCUMENTO
    # inteiro, incluindo campos bibliograficos: uma citacao ou titulo fabricado em `citation` e
    # exatamente o tipo de string que pode reaparecer, sem retratacao, em outro campo.
    for v in _varre_contradicao(doc):
        erro(v)

    return e


# ---------------------------------------------------------------------------------------------
# BUSCA DELIMITADA (evidence/literature/searches/*.yaml)
#
# POR QUE ESTA CAMADA EXISTE. `tests/unit/governance-links.py` ja obriga toda afirmacao de
# ausencia na literatura ("nenhum trabalho mede X") a referenciar `[busca:<id>]`, e verifica que
# o id RESOLVE para um arquivo. Ele nao le o arquivo. Medido nesta arvore: a unica busca
# registrada, BL-0001, declarava `sources: [ledger interno evidence/literature/]` - uma busca
# que consultou APENAS o proprio repositorio e concluiu sobre o estado da literatura mundial.
#
# `NaoEncontrado(consultas, fontes, data)` so substitui a negativa universal se as tres partes
# forem reais. Uma busca cujas FONTES sao o proprio corpus e uma tautologia com forma de
# evidencia: ela nao pode encontrar nada que o repositorio ja nao soubesse, e mesmo assim
# absolve a claim no lint de governanca. Por isso a regra dura desta camada e FONTE EXTERNA.
#
# LIMITE DECLARADO, na mesma disciplina do resto deste validador: isto e FORMA. Verifica que uma
# fonte externa foi APONTADA e que a consulta foi datada - nao contata a rede, nao reexecuta a
# busca, nao confere se o resultado declarado corresponde ao que aquela base devolveria hoje.
CAMPOS_BUSCA = ("claim_id", "question", "searched_at", "searched_by", "sources", "queries",
                "result")

RE_CLAIM_ID = re.compile(r"^[A-Z]{2}-\d{4}$")
RE_DATA_ISO = re.compile(r"^(\d{4})-(\d{2})-(\d{2})$")
RE_URL = re.compile(r"https?://", re.IGNORECASE)

# Vocabulario ABERTO de bases externas reconhecidas por nome. Uma fonte tambem vale como externa
# se trouxer URL - ver `_fonte_externa`. A lista existe para o caso legitimo de busca em base
# consultada por interface propria, sem URL estavel por consulta.
BASES_EXTERNAS = ("arxiv", "acm digital library", "dl.acm.org", "ieee", "ieeexplore", "dblp",
                  "semantic scholar", "google scholar", "springer", "sciencedirect", "usenix",
                  "pubmed", "openreview", "acl anthology", "scopus", "web of science")

# Marcas de fonte INTERNA: o proprio repositorio. Fonte interna e legitima como COMPLEMENTO
# (BL-0001 esta certa em consultar o proprio ledger) e insuficiente como UNICA fonte.
MARCAS_INTERNAS = ("ledger interno", "evidence/", "docs/", "tests/", "este repositorio",
                   "repositorio interno", "corpus interno")

# Uma busca envelhece: "nao encontrado em 2024" nao sustenta afirmacao em 2027. O limiar e largo
# de proposito - o objetivo e barrar a afirmacao FOSSILIZADA, nao obrigar revalidacao de rotina.
# A idade e reportada SEMPRE (visibilidade), e vira violacao acima do limiar.
DIAS_VALIDADE_BUSCA = 730


def _fonte_externa(texto):
    """Uma fonte conta como externa se traz URL ou nomeia uma base externa conhecida.

    A marca interna tem PRECEDENCIA: `ledger interno evidence/literature/` nao vira externa por
    conter a substring de uma base no meio de um caminho.
    """
    t = str(texto).strip().lower()
    # A4 DO REFUTADOR: a precedencia da marca interna sobre a URL produzia FALSO NEGATIVO.
    # `MARCAS_INTERNAS` contem `docs/`, `tests/` e `evidence/` como substring livre, e essas
    # sequencias aparecem no CAMINHO de URLs externas legitimas. Medido:
    # `https://ieeexplore.ieee.org/docs/1234` e `https://platform.openai.com/docs/guides` eram
    # classificadas como INTERNAS, e o validador acusava o autor de "consultou apenas o proprio
    # repositorio" - acusacao falsa, a mesma classe de dano de A3.
    # A URL passa a decidir PRIMEIRO: um endereco http(s) e externo por construcao. As marcas
    # internas continuam valendo para o que NAO e URL, que e onde elas foram medidas (a fonte
    # real de BL-0001 era `ledger interno evidence/literature/`, sem URL nenhuma).
    if RE_URL.search(t):
        return True
    if any(m in t for m in MARCAS_INTERNAS):
        return False
    return any(b in t for b in BASES_EXTERNAS)


def _idade_dias(iso):
    """Dias entre `iso` (YYYY-MM-DD) e hoje. Devolve None se a data nao for legivel."""
    # A9 DO REFUTADOR: `date.today()` e a data LOCAL. Contribuidor a leste do UTC que grava a
    # data local do proprio fuso recebia idade -1 e ERRO DURO "esta no FUTURO". A busca e datada
    # em UTC no resto do repositorio; a comparacao passa a ser em UTC tambem.
    import datetime
    m = RE_DATA_ISO.match(str(iso).strip())
    if not m:
        return None
    try:
        d = datetime.date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
    except ValueError:
        return None
    return (datetime.datetime.now(datetime.timezone.utc).date() - d).days


def valida_busca(doc, arquivo, vistos_busca):
    """Valida UM registro de busca delimitada. Devolve lista de violacoes (vazia = valido)."""
    e = []
    nome = os.path.basename(arquivo)

    def erro(msg):
        e.append(f"{nome}: {msg}")

    if not isinstance(doc, dict):
        return [f"{nome}: raiz do documento nao e um mapa YAML"]

    for campo in CAMPOS_BUSCA:
        if campo not in doc:
            erro(f"campo obrigatorio ausente: {campo}")
    if e:
        return e

    cid = str(doc["claim_id"]).strip()
    if not RE_CLAIM_ID.match(cid):
        erro(f"claim_id '{cid}' fora do formato AA-0000 (duas maiusculas, hifen, quatro digitos)")
    elif cid in vistos_busca:
        erro(f"claim_id '{cid}' duplicado (ja usado em {vistos_busca[cid]})")
    else:
        vistos_busca[cid] = nome
        if not nome.startswith(cid + "-"):
            erro(f"nome do arquivo deveria comecar com '{cid}-' para casar com claim_id")

    if not str(doc["question"]).strip():
        erro("question vazia - a busca precisa declarar O QUE foi perguntado")
    if not str(doc["searched_by"]).strip():
        erro("searched_by vazio - quem executou a busca e parte do registro")

    # QUERIES: a lista de consultas e o que torna `NaoEncontrado` auditavel. Vazia, o registro
    # afirma ausencia sem dizer o que procurou.
    queries = doc["queries"]
    if not isinstance(queries, list) or not queries:
        erro("queries precisa ser uma lista NAO VAZIA - sem as consultas a busca nao e auditavel")
    elif any(not str(q).strip() for q in queries):
        erro("queries contem entrada vazia")

    # FONTES: a regra dura desta camada. Ver o cabecalho do bloco.
    sources = doc["sources"]
    if not isinstance(sources, list) or not sources:
        erro("sources precisa ser uma lista NAO VAZIA")
    elif not any(_fonte_externa(s) for s in sources):
        erro("NENHUMA fonte EXTERNA em sources. Uma busca que consultou apenas o proprio "
             "repositorio nao observa a literatura: ela nao pode encontrar nada que o corpus "
             "ja nao contivesse, e por isso nao sustenta uma afirmacao de ausencia. Declare ao "
             "menos uma fonte com URL (http/https) ou nomeando uma base externa "
             f"({', '.join(BASES_EXTERNAS[:4])}, ...). Fontes declaradas: {sources}")

    # DATA: formato e nao-futuro. Data no futuro tornaria a idade negativa e o envelhecimento
    # inerte - o mesmo modo de falha que o portao ja trata para relogio torto.
    idade = _idade_dias(doc["searched_at"])
    if idade is None:
        erro(f"searched_at '{doc['searched_at']}' fora do formato ISO YYYY-MM-DD")
    elif idade < -1:
        # -1 e tolerado: e a diferenca maxima de fuso horario para quem grava a data local.
        # Reprovar por isso seria acusar de "data no futuro" quem apenas mora a leste do UTC.
        erro(f"searched_at '{doc['searched_at']}' esta no FUTURO ({-idade} dia(s), alem da "
             "tolerancia de 1 dia para fuso) - data invalida torna o envelhecimento inerte")
    elif idade > DIAS_VALIDADE_BUSCA:
        erro(f"busca com {idade} dias (limite {DIAS_VALIDADE_BUSCA}). Uma afirmacao de ausencia "
             "nao envelhece bem: reexecute as consultas e atualize searched_at, ou remova a "
             "afirmacao que depende dela")

    # RESULT: o numero declarado precisa bater com a lista. `matching_studies: 0` com um match
    # listado (ou o inverso) e contradicao interna, a mesma classe que REGRA 5 cobre no corpus.
    result = doc["result"]
    if not isinstance(result, dict):
        erro("result precisa ser um mapa")
    elif "matching_studies" not in result:
        erro("result.matching_studies ausente - o resultado da busca precisa ser um numero")
    else:
        n = result["matching_studies"]
        if not isinstance(n, int) or isinstance(n, bool) or n < 0:
            erro(f"result.matching_studies '{n}' precisa ser inteiro >= 0")
        else:
            matches = result.get("matches") or []
            if not isinstance(matches, list):
                erro("result.matches precisa ser lista")
            elif len(matches) != n:
                erro(f"result.matching_studies={n} mas result.matches lista {len(matches)} "
                     "entrada(s) - contradicao interna no proprio registro")
    return e


RE_CAMINHO_CITED = re.compile(r"^([A-Za-z0-9_][A-Za-z0-9_./\-]*\.[A-Za-z0-9]+)")


def _valida_cited_in(doc, nome, raiz):
    """`cited_in` afirma ONDE a entrada e citada. A afirmacao tem de ser verdadeira.

    Medido nesta arvore em 2026-09-04: cinco entradas novas declaravam
    `cited_in: docs/adr/0042-...` enquanto aquele ADR nao mencionava nenhuma delas. `cited_in`
    esta em CAMPOS_BIBLIOGRAFICOS e por isso escapava da varredura de fonte - o campo era prosa
    livre que ninguem conferia. Uma entrada que declara ser citada onde nao e citada e a mesma
    classe de `[busca:<id>]` que nao resolve: referencia que aponta para o vazio.

    ESCOPO DECLARADO: so confere entradas que COMECAM com algo com cara de caminho de arquivo
    deste repositorio. Texto livre, URL e anotacao entre parenteses sao ignorados de proposito -
    o objetivo e pegar a referencia falsa, nao normatizar a redacao do campo. E confere MENCAO
    (o arquivo cita o literature_id OU o identifier), nao que a citacao seja fiel.
    """
    e = []
    for item in doc.get("cited_in") or []:
        m = RE_CAMINHO_CITED.match(str(item).strip())
        if not m:
            continue
        cam = m.group(1)
        if "/" not in cam:          # nome solto sem diretorio: nao e caminho deste repo
            continue
        abs_ = os.path.join(raiz, cam)
        if not os.path.isfile(abs_):
            e.append(f"{nome}: cited_in aponta para arquivo inexistente: '{cam}'")
            continue
        try:
            with open(abs_, encoding="utf-8", errors="replace") as fh:
                txt = fh.read()
        except OSError as exc:
            e.append(f"{nome}: cited_in '{cam}' nao pode ser lido: {exc}")
            continue
        lid = str(doc.get("literature_id", ""))
        ident = str(doc.get("identifier", ""))
        alvos = [t for t in (lid, ident, ident.replace("arXiv:", ""), ident.replace("DOI ", "")) if t]
        if not any(t in txt for t in alvos):
            e.append(f"{nome}: cited_in declara '{cam}', mas esse arquivo nao menciona nem "
                     f"'{lid}' nem '{ident}'. Referencia que afirma e nao resolve.")
    return e


def _valida_matches_resolvem(doc, nome, raiz):
    """`matches[].ledger`, quando presente, tem de RESOLVER para um arquivo existente.

    Sem esta regra a busca pode citar um ledger que nunca foi escrito, e o `NaoEncontrado` passa
    a apontar para o vazio. Foi exatamente o que aconteceu ao redigir BL-0002 nesta arvore: duas
    entradas foram citadas antes de existirem e o validador aprovou. Referencia que nao resolve e
    a mesma classe que `tests/unit/governance-links.py` ja fecha para `[busca:<id>]`; faltava o
    outro sentido da seta.
    """
    e = []
    res = doc.get("result")
    if not isinstance(res, dict):
        return e
    for i, m in enumerate(res.get("matches") or []):
        if not isinstance(m, dict):
            continue
        cam = m.get("ledger")
        if not cam:
            continue
        if not os.path.isfile(os.path.join(raiz, str(cam))):
            e.append(f"{nome}: result.matches[{i}].ledger nao resolve: '{cam}' nao existe. "
                     "Busca que cita ledger inexistente aponta para o vazio.")
    return e


def valida_buscas(sdir, raiz):
    """Varre o diretorio de buscas. Devolve (violacoes, linhas_de_relatorio).

    Diretorio AUSENTE nao e violacao aqui: quem exige que o repositorio real tenha ao menos uma
    busca registrada e `tests/unit/governance-links.py` (a regra de `[busca:<id>]` seria vacua
    sem nenhuma). Este validador tambem roda sobre corpora sinteticos de teste, que nao tem a
    camada. O relatorio declara qual dos dois casos ocorreu, para que "nao violou" nunca seja
    confundido com "nao foi verificado".
    """
    if not os.path.isdir(sdir):
        return [], ["buscas delimitadas: diretorio ausente - camada NAO VERIFICADA neste corpus."]
    arquivos = sorted(f for f in os.listdir(sdir) if f.endswith((".yaml", ".yml")))
    if not arquivos:
        return [], ["buscas delimitadas: diretorio vazio - camada NAO VERIFICADA neste corpus."]
    erros, vistos_busca, idades = [], {}, []
    for nome in arquivos:
        caminho = os.path.join(sdir, nome)
        try:
            with open(caminho, encoding="utf-8") as fh:
                doc = yaml.safe_load(fh)
        except yaml.YAMLError as exc:
            erros.append(f"{nome}: YAML invalido: {exc}")
            continue
        erros.extend(valida_busca(doc, caminho, vistos_busca))
        if isinstance(doc, dict):
            # RAIZ VEM DO ARGUMENTO, nunca derivada do caminho do diretorio de buscas.
            # Deriva-la subindo tres niveis funciona no repositorio real e QUEBRA em
            # qualquer corpus sintetico - os testes montam o diretorio em $TMPDIR, onde
            # subir tres niveis resolve para /tmp e todo `ledger:` valido parece ausente.
            erros.extend(_valida_matches_resolvem(doc, nome, raiz))
        if isinstance(doc, dict):
            i = _idade_dias(doc.get("searched_at", ""))
            if i is not None and i >= 0:
                idades.append((nome, i))
    linhas = [f"buscas delimitadas lidas: {len(arquivos)}"]
    for nome, i in sorted(idades, key=lambda x: -x[1]):
        linhas.append(f"  - {nome}: {i} dia(s) desde a consulta "
                      f"(limite {DIAS_VALIDADE_BUSCA})")
    return erros, linhas


def main(argv):
    raiz = os.path.abspath(argv[1]) if len(argv) > 1 else os.path.abspath(
        os.path.join(os.path.dirname(__file__), ".."))
    ldir = argv[2] if len(argv) > 2 else os.path.join(raiz, "evidence", "literature")

    if not os.path.isdir(ldir):
        sys.stderr.write(f"NAO VERIFICADO: diretorio de literatura inexistente: {ldir}\n")
        return EXIT_NAO_VERIFICADO

    arquivos = sorted(f for f in os.listdir(ldir) if f.endswith((".yaml", ".yml")))
    if not arquivos:
        sys.stderr.write(f"NAO VERIFICADO: nenhuma entrada de literatura em {ldir}\n")
        return EXIT_NAO_VERIFICADO

    erros, vistos = [], {}
    for nome in arquivos:
        caminho = os.path.join(ldir, nome)
        try:
            with open(caminho, encoding="utf-8") as fh:
                doc = yaml.safe_load(fh)
        except yaml.YAMLError as exc:
            erros.append(f"{nome}: YAML invalido: {exc}")
            continue
        erros.extend(valida(doc, caminho, vistos))
        if isinstance(doc, dict):
            erros.extend(_valida_cited_in(doc, nome, raiz))

    # CAMADA DE BUSCA DELIMITADA. Conjuntiva com a de literatura: violacao em qualquer uma das
    # duas reprova o validador inteiro. Ver o cabecalho de CAMPOS_BUSCA para o porque.
    erros_busca, relatorio_busca = valida_buscas(os.path.join(ldir, "searches"), raiz)
    erros.extend(erros_busca)

    print(f"entradas de literatura lidas: {len(arquivos)}")
    for linha in relatorio_busca:
        print(linha)
    if erros:
        print(f"\nVIOLACOES ({len(erros)}):")
        for x in erros:
            print(f"  - {x}")
        return EXIT_VIOLACAO
    print("camada de buscas valida: toda busca delimitada declara consultas, ao menos uma FONTE "
          "EXTERNA (URL ou base nomeada), data ISO nao-futura dentro do prazo de validade, e "
          "result.matching_studies coerente com result.matches.")
    print("camada de literatura valida: campos obrigatorios presentes; inference_strength e "
          "provenance no vocabulario fechado; toda afirmacao numerica com fonte declarada "
          "(findings[].source estrutural, ou marcador 'fonte'/'verificad' inline no restante "
          "do documento).")
    print("ESTE VERDE E FORMA, NAO FIDELIDADE A FONTE PRIMARIA: nao contata a rede, nao baixa o "
          "PDF, nao confere se titulo, autor, numero ou citacao verbatim batem com o artigo. "
          "Precedente concreto: uma rodada anterior desta camada saiu 27/27 verde com um titulo "
          "fabricado e uma citacao verbatim inventada dentro - ver docstring deste arquivo.")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main(sys.argv))
