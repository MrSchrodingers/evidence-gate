#!/usr/bin/env python3
from __future__ import annotations

import json
import pathlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
registry = json.loads((ROOT / "orchestration/registry.json").read_text(encoding="utf-8"))

expected = {
    "policy": "orchestration/skill-policy.json",
    "evaluation_protocol": "orchestration/evaluation-protocol.json",
    "method": "docs/method/skill-evaluation-protocol.md",
    "adr": "docs/adr/0025-skills-evidence-gated.md",
}
actual = registry.get("skill_governance")

if actual != expected:
    raise SystemExit(f"FAIL skill_governance divergente: {actual!r}")

for label, raw_path in expected.items():
    path = ROOT / raw_path
    if not path.is_file():
        raise SystemExit(f"FAIL {label} nao resolve: {raw_path}")

print("PASS registry liga policy, protocolo, metodo e ADR")

# ONDA 15 - O CORPUS NAO PODE DECLARAR UMA CONTAGEM QUE ELE MESMO CONTRADIZ.
#
# `evidence/corpus/agente-x-defeito.json` publica `counts_by_mode`, e a primeira versao dessa
# tabela foi escrita a mao e SAIU ERRADA (remedicao: declarado 8, medido 9). Numero declarado que
# ninguem confere e a forma mais barata do defeito que este repositorio persegue - e ele apareceu
# dentro do proprio corpus que documenta esse defeito. Recontar aqui custa quatro linhas.
corpus_path = ROOT / "evidence/corpus/agente-x-defeito.json"
if not corpus_path.is_file():
    raise SystemExit("FAIL corpus agente-x-defeito ausente")
corpus = json.loads(corpus_path.read_text(encoding="utf-8"))

# ONDA 18: `counts_by_mode` saiu do topo do arquivo e virou parte do bloco DERIVADO, junto do
# resto do frame. A recontagem continua, agora contra `derived` - ver a checagem completa abaixo,
# que compara o bloco inteiro com o que o renderer calcula.
medido: dict[str, int] = {}
for achado in corpus["findings"]:
    medido[achado["mode"]] = medido.get(achado["mode"], 0) + 1
declarado = (corpus.get("derived") or {}).get("counts_by_mode")
if medido != declarado:
    raise SystemExit(f"FAIL corpus: derived.counts_by_mode {declarado} != medido {medido}")

# Todo modo citado numa linha tem de estar definido em `modes`, senao a coluna nao significa nada.
desconhecidos = sorted(set(medido) - set(corpus["modes"]))
if desconhecidos:
    raise SystemExit(f"FAIL corpus: modos usados e nao definidos: {desconhecidos}")

# ONDA 20 (G17), REESCRITO NA 20b. A primeira versao lia o vinculo modo -> agente da PROSA por
# `re.compile(r"Agente \`([^\`]+)\`")`. O `refutador` derrubou em tres direcoes, todas medidas:
#
#   falso negativo   cinco reescritas plausiveis da descricao (sem crases, com dois-pontos, em
#                    minuscula, outra formulacao, aspas tipograficas) desligavam a regra em
#                    SILENCIO, com atribuicao falsa plantada e `PASS` impresso. O contador da
#                    propria linha caia de 3 para 2 modos com agente, e nada assertava isso.
#   falso positivo   uma frase explicativa acrescentada a outro modo reprovava 23 achados corretos.
#   a bomba armada   a descricao do modo NOVO desta onda contem "agente `revisor-codigo`" em
#                    prosa. So a MINUSCULA impedia o casamento: uma maiuscula e o portao reprovava
#                    o achado principal da onda que o construiu.
#
# Era `G12a` (ADR 0037) - lint lexical prometendo a classe e entregando uma lista de realizacoes -
# dentro da correcao que cita `G12a`. O erro estava no FORMATO, nao na regex, e a inversao que o
# resolve ja e doutrina deste repositorio desde a onda 18 (`evidence/corpus/render.py`):
#
#     antes   vinculo escrito em prosa -> regex tenta descobrir se esta la
#     agora   vinculo E campo (`agent`), `null` quando o modo nao tem agente
#
# Nenhuma prosa e interpretada. Mencionar um agente numa descricao volta a ser prosa inofensiva.
_com_agente = {m for m, v in corpus["modes"].items() if v.get("agent")}
_sem_agente = set(corpus["modes"]) - _com_agente
_atribuicao_falsa = [
    f"{_a['finding_id']}: mode={_a['mode']!r} declara o agente "
    f"{corpus['modes'][_a['mode']]['agent']!r} mas found_by={_a.get('found_by')!r}"
    for _a in corpus["findings"]
    if _a["mode"] in _com_agente
    and _a.get("found_by") != corpus["modes"][_a["mode"]]["agent"]
]
if _atribuicao_falsa:
    raise SystemExit("FAIL corpus: `mode` nomeia um agente que `found_by` nao confirma - "
                     f"atribuicao de procedencia sem lastro: {_atribuicao_falsa}")

# ANTIVACUIDADE. Se `agent` sumisse de todos os modos - por refactor, por migracao de schema, por
# um PR que "simplifica" - `_com_agente` ficaria vazio, o laco acima nao iteraria, e o portao
# imprimiria PASS sem ter conferido nada. A primeira versao IMPRIMIA esse contador e nao o
# assertava; era o sinal do proprio desligamento, ignorado.
if not _com_agente:
    raise SystemExit("FAIL corpus: nenhum modo declara `agent` - o portao de procedencia ficaria "
                     "vacuo. Modo sem agente deve trazer `agent: null` explicito, nao omitir.")
if any("agent" not in v for v in corpus["modes"].values()):
    raise SystemExit("FAIL corpus: modo sem o campo `agent` - `null` e declaracao, ausencia e "
                     f"omissao: {sorted(m for m, v in corpus['modes'].items() if 'agent' not in v)}")

# `agent: ""` LE-SE COMO DECLARACAO E AGE COMO AUSENCIA. A guarda de omissao acima passa - a chave
# existe -, e `v.get("agent")` e teste de veracidade, entao a string vazia cai fora de
# `_com_agente` e desliga a checagem em silencio. O tipo tem de ser `null` OU string nao vazia,
# nada no meio.
_agente_ruim = sorted(m for m, v in corpus["modes"].items()
                      if v["agent"] is not None
                      and not (isinstance(v["agent"], str) and v["agent"].strip()))
if _agente_ruim:
    raise SystemExit("FAIL corpus: `agent` tem de ser `null` ou nome nao vazio - valor que se le "
                     f"como declaracao e age como ausencia: {_agente_ruim}")

# A TERCEIRA REALIZACAO DA VACUIDADE, MEDIDA POR DENTRO. A regra de cima so olha modos que TEM
# agente; trocar o `agent` de um modo para `null` o removia de `_com_agente` e desligava a
# checagem para os achados dele - 20 dos 64 no caso de `leitura-estrutural`, com `PASS` impresso.
#
# O que fecha isso SEM exigir a base e a coerencia interna: um modo que declara `agent: null` e
# cujos achados nomeiam OUTRA COISA que nao o proprio modo esta se contradizendo - ou ele tem
# agente e deve declara-lo, ou o `found_by` esta errado. Nao ha terceira leitura.
#
# ISTO NAO REINTRODUZ O DEFEITO SIMETRICO. A regra nao obriga modo sem agente a NOMEAR um agente -
# obriga a nomear o proprio modo, que e o que os tres modos sem agente ja fazem. Inventar
# procedencia continua impossivel; o que deixou de ser possivel e apagar a procedencia declarada.
_orfaos = sorted(
    f"{_a['finding_id']}: mode={_a['mode']!r} declara `agent: null` mas found_by={_a.get('found_by')!r}"
    for _a in corpus["findings"]
    if _a["mode"] in _sem_agente and _a.get("found_by") != _a["mode"])
if _orfaos:
    raise SystemExit("FAIL corpus: modo com `agent: null` cujos achados nomeiam outro ator - ou o "
                     "modo tem agente e deve declara-lo, ou o `found_by` esta errado. Trocar "
                     f"`agent` para null de dentro do PR desligaria a checagem: {_orfaos}")

# E A ANCORA NA ARVORE BASE, como defesa em profundidade para o caso que a regra de cima nao
# alcanca: trocar `agent` para null E reescrever todos os `found_by` no MESMO PR. E a familia
# `D_MAX`. Modo que tinha agente na base nao
# pode perde-lo no head - fato que o PR nao pode forjar, o mesmo principio da onda 14.
#
# LIMITE DECLARADO, e ele importa: a base de HOJE traz `modes` como STRING, anterior ao campo
# estruturado que este PR introduz, entao esta guarda sai `0 com agente na base` e nao morde
# nesta onda. Ela fecha a partir do proximo commit. Quem fecha o buraco AGORA e a coerencia
# interna acima. Duas guardas, alcances diferentes, e dizer que a segunda ja protege seria a
# amplitude que esta onda inteira corrige.
_base_ref = None
for _r in ("origin/main", "main"):
    if subprocess.run(["git", "rev-parse", "--verify", "--quiet", _r],
                      capture_output=True, cwd=str(ROOT)).returncode == 0:
        _base_ref = _r
        break
if _base_ref is None:
    # exit 2 = NAO VERIFICADO, a convencao do repositorio. Sem base nao ha comparacao, e "nao
    # reprovou" seria indistinguivel de "nao foi medido".
    print("NAO VERIFICADO: sem ref de base (origin/main ou main) - a nao-perda de `agent` nao "
          "pode ser conferida, e afirmar que nada regrediu seria claim sem observacao")
else:
    _bruto = subprocess.run(["git", "show", f"{_base_ref}:evidence/corpus/agente-x-defeito.json"],
                            capture_output=True, text=True, cwd=str(ROOT))
    if _bruto.returncode != 0:
        print(f"NAO VERIFICADO: corpus ausente em {_base_ref} - primeira aparicao do arquivo")
    else:
        _modos_base = (json.loads(_bruto.stdout) or {}).get("modes") or {}
        _rebaixados = sorted(
            f"{_m}: base={_v.get('agent')!r} head={corpus['modes'][_m].get('agent')!r}"
            for _m, _v in _modos_base.items()
            # a base pode ser anterior ao schema estruturado, quando `modes` era string
            if isinstance(_v, dict) and _v.get("agent") and _m in corpus["modes"]
            and not corpus["modes"][_m].get("agent"))
        if _rebaixados:
            raise SystemExit(
                "FAIL corpus: modo que tinha `agent` na base o perdeu no head - desligar a "
                f"checagem de procedencia de dentro do PR e a familia D_MAX: {_rebaixados}")
        _com_agente_base = sum(1 for v in _modos_base.values()
                               if isinstance(v, dict) and v.get("agent"))
        if _com_agente_base:
            print(f"PASS corpus: nenhum modo perde `agent` contra {_base_ref} "
                  f"({_com_agente_base} com agente na base)")
        else:
            # O `refutador` apontou: um PASS que se sabe vacuo e a unica linha da saida que afirma
            # mais do que mede. A base anterior ao schema estruturado traz `modes` como STRING, e
            # nao ha o que comparar - "nao reprovou" seria indistinguivel de "nao foi medido". A
            # convencao NAO VERIFICADO ja e usada duas vezes neste mesmo bloco.
            print(f"NAO VERIFICADO: `modes` em {_base_ref} nao traz `agent` (schema anterior ao "
                  "campo estruturado) - a nao-perda so podera ser conferida a partir do proximo "
                  "commit")
print(f"PASS corpus: procedencia coerente - todo `mode` com `agent` tem `found_by` igual "
      f"({len(_com_agente)} modo(s) com agente, {len(_sem_agente)} com `agent: null`)")

# ANTIVACUIDADE: um corpus vazio satisfaria as checagens de contagem e de modo acima sem
# dizer nada. (Uma versao anterior deste comentario dizia "as duas checagens acima" e
# envelheceu no mesmo PR que acrescentou guardas acima dele - a classe corrigida um
# paragrafo adiante, em escala minima. O comentario deixou de contar.)
if len(corpus["findings"]) < 10:
    raise SystemExit(f"FAIL corpus com {len(corpus['findings'])} achados - vazio demais para medir")

# COMPLETUDE, NAO SO CONSISTENCIA. Achado de auditoria externa, e ele e a tese deste
# repositorio aplicada ao proprio instrumento que a documenta: a recontagem acima confere que
# `counts_by_mode` bate com as linhas PRESENTES, e nunca conferiu se as linhas presentes sao
# TODOS os achados da fonte declarada. Estavam faltando dezesseis - os cinco criticos e oito
# avisos do `revisor-codigo`, e os tres do `refutador`, todos da onda 15. Sobre esse universo
# incompleto, um relatorio publicado concluiu que a auditoria externa fora o modo mais
# produtivo; com o universo completo a ordem se inverte.
#
#     corpus internamente consistente  NAO IMPLICA  corpus completo
#
# A regra: todo identificador citado com MARCADOR ESTRUTURADO num ADR (`**C1 -`, `**F2 -`,
# `**A4 -`) tem de existir como `finding_id` aqui. Marcador estruturado, e nao qualquer mencao,
# porque prosa cita identificador de passagem e transformar isso em obrigacao produziria ruido.
ids_corpus = {f.get("finding_id") for f in corpus["findings"]}
faltando: dict[str, list[str]] = {}
for adr in sorted((ROOT / "docs/adr").glob("*.md")):
    citados = set(re.findall(r"\*\*([A-Z]\d{1,3})\*{0,2} [-\u2014]", adr.read_text(encoding="utf-8")))
    ausentes = sorted(citados - ids_corpus)
    if ausentes:
        faltando[adr.name] = ausentes
if faltando:
    raise SystemExit(f"FAIL corpus INCOMPLETO: achados citados em ADR e ausentes do corpus: {faltando}")

# ANTIVACUIDADE: se nenhum ADR citasse identificador algum, a checagem acima passaria vazia e
# nao distinguiria "completo" de "nada a conferir".
_citados_total = set()
for adr in sorted((ROOT / "docs/adr").glob("*.md")):
    _citados_total |= set(re.findall(r"\*\*([A-Z]\d{1,3})\*{0,2} [-\u2014]", adr.read_text(encoding="utf-8")))
if len(_citados_total) < 5:
    raise SystemExit(f"FAIL completude vacua: so {len(_citados_total)} identificadores citados em ADR")

if "inclusion_criterion" not in corpus:
    raise SystemExit("FAIL corpus sem criterio de inclusao explicito - sem ele, 'produtividade "
                     "do revisor' fica vulneravel a selecao retrospectiva")

print(f"PASS corpus agente-x-defeito coerente ({len(corpus['findings'])} achados, {len(medido)} modos)")
print(f"PASS completude ADR-ID: os {len(_citados_total)} achados citados com marcador\n     estruturado em ADR estao no corpus. NAO e completude absoluta do universo de\n     defeitos - defeito descrito em ADR SEM identificador fica fora deste frame.")

# ONDA 15, SEGUNDA RODADA - O NUMERO PUBLICADO NO ADR E RECONFERIDO CONTRA O PORTAO.
#
# Achado C4 de revisao independente: o ADR 0035 e a errata da observacao publicavam
# `D_E = 87 sobre 33 capabilities` enquanto o portao do MESMO commit media 89 sobre 34. A prosa
# fora escrita antes de a ultima capability entrar, e nada reconferia - a mesma classe do
# `counts_by_mode` do corpus, corrigida logo acima, reaparecendo no arquivo que JUSTIFICA a onda.
# Numero que justifica uma decisao e o ultimo lugar onde se pode confiar em copia manual.

ADR = ROOT / "docs/adr/0035-a-divida-era-de-uma-classe-so.md"
if not ADR.is_file():
    raise SystemExit("FAIL ADR 0035 ausente")

_saida = subprocess.run([sys.executable, str(ROOT / "tests/unit/capability-conformance.py")],
                        capture_output=True, text=True, cwd=str(ROOT))
_medido = re.search(r"D_E\(head\)=(\d+) obrigacoes em aberto sobre (\d+) capabilities",
                    _saida.stdout)
if _medido is None:
    # O portao sai 2 = NAO VERIFICADO quando nao ha ref de base. Sem medida nao se pode conferir
    # a publicacao, e inventar um veredito aqui seria pior que declarar a lacuna.
    print("NAO VERIFICADO: o portao nao produziu D_E (sem ref de base?) - numero do ADR nao conferido")
else:
    _pub = re.search(r"D_E\(head\) = (\d+) obrigacoes em aberto sobre (\d+) capabilities",
                     ADR.read_text(encoding="utf-8"))
    if _pub is None:
        raise SystemExit("FAIL ADR 0035 nao publica o D_E medido - o numero que justifica a onda sumiu")
    if _pub.groups() != _medido.groups():
        raise SystemExit(f"FAIL ADR 0035 publica D_E={_pub.group(1)}/{_pub.group(2)} "
                         f"e o portao mede {_medido.group(1)}/{_medido.group(2)}")
    # ONDA 18 - A PROSA DO CORPUS NAO PODE CONTER NUMERAL, e o frame e DERIVADO.
#
# A onda 17 pos um lint de numeral com excecao por janela lexical. Auditoria externa mostrou que
# nao fechava a classe: "Antes de discutir severidade, sao 40 achados no corpus atual" passava,
# porque "Antes" caia na janela de excecao; e o mesmo cabecalho declarava "ondas 11 a 15" com
# onda 17 nos dados. O erro estava no FORMATO, nao no regex:
#
#     contagem estruturada -> humano escreve o numero -> regex tenta descobrir se copiou certo
#
# Invertido: a prosa usa marcadores, `evidence/corpus/render.py` os resolve a partir dos
# findings, e digito literal em campo de prosa passa a ser recusado. Nao ha o que copiar errado.
#
# LIMITE: numero por EXTENSO nao e alcancado. A garantia e de FORMATO - nenhum digito -, nao de
# semantica de texto. Dizer o contrario seria a amplitude que esta serie vem corrigindo.
sys.path.insert(0, str(ROOT / "evidence/corpus"))
import render as _render                                                    # noqa: E402

_derivado = _render.derivar(corpus["findings"])
_divergente = {k: (corpus["derived"].get(k), v) for k, v in _derivado.items()
               if corpus["derived"].get(k) != v}
if _divergente:
    raise SystemExit(f"FAIL corpus: bloco `derived` diverge dos findings: {_divergente} "
                     "- rode `python3 evidence/corpus/render.py --update`")

# ESCOPO DESTE LINT, dito com precisao porque a versao anterior errou justamente aqui. Ele
# recusa DUAS formas de contagem escritas a mao - `<N> achados` e `N=<N>` -, que sao as que de
# fato reincidiram. Nao pretende cobrir prosa derivada em geral: numero por extenso, aritmetica
# em texto e referencia narrativa a uma onda passada ficam fora, e a garantia contra elas nao
# vem daqui - vem de o FRAME ser derivado em `derived`, onde nao ha o que copiar errado.
#
# A EXCECAO LEXICAL FOI REMOVIDA. A versao da onda 17 absolvia o numeral se a janela de noventa
# caracteres anterior contivesse "antes", "anterior", "primeira versao" ou "ja esteve. Auditoria
# externa mediu: "Antes de discutir severidade, sao 40 achados no corpus atual" passava, com o
# numero corrente FALSO. Excecao por vizinhanca de palavra e adivinhacao de intencao. O historico
# nao precisa dela: vive em `historical_states`, estruturado, e o renderer o imprime.
_sem_marcador = [re.sub(r"\{\{[^}]+\}\}", "", s) for s in _render.prosa(corpus)]
_com_contagem = [s[:70] for s in _sem_marcador if re.search(r"\b\d+ achados\b|\bN=\d+\b", s)]
if _com_contagem:
    raise SystemExit("FAIL corpus: contagem escrita a mao na prosa; use marcador resolvido por "
                     f"evidence/corpus/render.py, e historico em historical_states: {_com_contagem}")
if not (corpus.get("historical_states") or []):
    raise SystemExit("FAIL corpus sem `historical_states` - sem ele o registro do proprio erro "
                     "so caberia na prosa, que e o que esta regra acabou de proibir")

_mapa = _render.substituicoes(corpus)
_orfaos = [m for s in _render.prosa(corpus) for m in _render._MARCADOR.findall(s) if m not in _mapa]
if _orfaos:
    raise SystemExit(f"FAIL corpus: marcador que nao resolve: {sorted(set(_orfaos))}")

# ONDA 19 - `source_ref` E `resolution_ref` TEM DE RESOLVER (G14), e o estado e enum (G15).
#
# G14 - o renderer deriva `sources` do campo `source_ref` de cada achado, o que garante que o
# frame liste o que foi DECLARADO e nada sobre o que EXISTE. Medido: `source_ref` apontando para
# `docs/adr/nao-existe.md` passava com rc=0, com o frame derivado atualizado e o portao verde. E
# a familia da onda 12 - "referencia publicada que nao resolve" - voltando dentro do instrumento
# construido para medir a propria trajetoria de defeitos.
#
# G15 - `open_findings` derivava de `status.startswith("aberto")`, texto livre. Medido: trocar a
# string de um achado ABERTO por "corrigido" o removia da lista, com tudo consistente e rc=0. O
# estado passa a ser enum fechado, e `resolved` exige `resolution_ref` que RESOLVA. Isso nao
# prova que o defeito foi corrigido - prova que existe artefato alegando corrigi-lo, e essa e a
# claim que o corpus pode sustentar.
_ESTADOS = set((corpus.get("state_machine") or {}).get("states") or [])
if not _ESTADOS:
    raise SystemExit("FAIL corpus sem `state_machine.states` - o estado voltaria a ser texto livre")

def _ref_valida(rel: str) -> str | None:
    """Motivo da recusa, ou None se o caminho resolve e esta confinado."""
    if not rel:
        return "vazio"
    if rel.startswith("/") or ".." in pathlib.PurePosixPath(rel).parts:
        return "fora do repositorio"
    return None if (ROOT / rel).is_file() else "nao existe"

_ruins, _estado_ruim, _sem_resolucao, _sem_nota = [], [], [], []
for _f in corpus["findings"]:
    _id = _f.get("finding_id", "?")
    _m = _ref_valida(_f.get("source_ref", ""))
    if _m:
        _ruins.append(f"{_id}: source_ref {_f.get('source_ref')!r} {_m}")
    if _f.get("state") not in _ESTADOS:
        _estado_ruim.append(f"{_id}: state={_f.get('state')!r}")
    if _f.get("state") == "resolved":
        _m2 = _ref_valida(_f.get("resolution_ref", ""))
        if _m2:
            _sem_resolucao.append(f"{_id}: resolution_ref {_f.get('resolution_ref')!r} {_m2}")

    if _f.get("state") == "open" and not _f.get("open_note"):
        _sem_nota.append(_id)
# ONDA 22b (A4, `revisor-codigo`). O portao so conferia a direcao "open exige open_note". A
# inversa ficava aberta, e `G6b` foi o unico dos 83 a exibi-la: marcado `resolved` carregando um
# `open_note` residual que afirmava o OPOSTO do `measured` novo - "E_A declarada como dimensao
# candidata, nao implementada", ao lado de um `measured` dizendo que a sonda tem eventos medidos.
# Campo que sobrevive a mudanca de estado publica a versao anterior do achado.
_residuo = [f"{_f.get('finding_id')}: state={_f.get('state')} com open_note residual"
            for _f in corpus["findings"]
            if _f.get("state") != "open" and _f.get("open_note")]
if _residuo:
    raise SystemExit(f"FAIL corpus: `open_note` sobrevivendo a mudanca de estado - o campo publica "
                     f"a versao anterior do achado: {_residuo}")

if _ruins:
    raise SystemExit(f"FAIL corpus: source_ref que nao resolve ou escapa do repositorio: {_ruins}")
if _estado_ruim:
    raise SystemExit(f"FAIL corpus: state fora do enum {sorted(_ESTADOS)}: {_estado_ruim}")
if _sem_resolucao:
    raise SystemExit(f"FAIL corpus: `resolved` sem resolution_ref que resolva: {_sem_resolucao}")
if _sem_nota:
    raise SystemExit(f"FAIL corpus: `open` sem open_note dizendo o que falta: {_sem_nota}")

print(f"PASS corpus: {len(corpus['findings'])} referencias resolvem, estados no enum, "
      f"{len(_derivado['open_findings'])} aberto(s) com nota")

# ONDA 18 - AFIRMACAO DE AUSENCIA NA LITERATURA EXIGE BUSCA DELIMITADA.
#
# A onda 17 proibiu a forma lexical e abriu duas excecoes: a palavra ERRATA numa janela de oito
# linhas, e o token `[citacao-corrigida]` na propria linha. Auditoria externa mediu as duas
# falhas. Quatro reformulacoes triviais passavam intocadas ("Nao ha estudo publicado que meca",
# "A literatura ainda nao mede", "Inexiste trabalho que", "There are no published studies"), e o
# token de escape podia ser escrito pelo MESMO PR que escrevia a claim - criterio de excecao
# dentro do objeto governado, a familia do D_MAX numa representacao nova.
#
# Duas mudancas. A primeira: a lista de realizacoes cresce, e a claim sobre ela ENCOLHE - isto e
# um LINT de realizacoes lexicais, nunca um detector semantico de negativa universal.
#
# A segunda e a que fecha a classe para claim NOVA: a unica forma autorizada de afirmar ausencia
# e referenciar uma busca delimitada, `[busca:<id>]`, resolvendo para um registro em
# `evidence/literature/searches/`. `PARA TODO p, nao P(p)` nao e demonstravel por busca finita;
# `NaoEncontrado(consultas, fontes, data)` e.
#
# E a valvula de CITACAO nao e mais autodeclarada: uma linha com a forma so e absolvida se
# EXISTIR IDENTICA NA ARVORE BASE - fato que o PR nao pode forjar, o mesmo principio da onda 14.
_NEG = re.compile(
    r"(nenhum[a]? (?:trabalho|paper|estudo|artigo|pesquisa)"
    r"|ninguem (?:mede|mediu|avalia)"
    r"|inexiste (?:trabalho|estudo)"
    r"|nao (?:ha|existe) (?:trabalho|estudo|paper|pesquisa)"
    r"|a literatura (?:ainda )?nao mede"
    r"|no (?:work|paper|study|research) (?:measures|evaluates)"
    r"|there (?:are|is) no published)", re.IGNORECASE)
_BUSCA = re.compile(r"\[busca:([A-Z]{2}-\d{4})\]")

_base_ref = None
for _r in ("origin/main", "main"):
    if subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--verify", _r],
                      capture_output=True).returncode == 0:
        _base_ref = _r
        break

_sem_busca, _busca_morta = [], []
for _adr in sorted((ROOT / "docs/adr").glob("*.md")):
    _linhas = _adr.read_text(encoding="utf-8").splitlines()
    _base_txt = ""
    if _base_ref:
        _r = subprocess.run(["git", "-C", str(ROOT), "show", f"{_base_ref}:docs/adr/{_adr.name}"],
                            capture_output=True, text=True)
        _base_txt = _r.stdout if _r.returncode == 0 else ""
    for _i, _linha in enumerate(_linhas, 1):
        if not _NEG.search(_linha):
            continue
        if _linha in _base_txt:          # citacao de texto que ja existia na BASE
            continue
        _ids = _BUSCA.findall(_linha)
        if not _ids:
            _sem_busca.append(f"{_adr.name}:{_i}")
            continue
        for _id in _ids:
            if not list((ROOT / "evidence/literature/searches").glob(f"{_id}-*.yaml")):
                _busca_morta.append(f"{_adr.name}:{_i} -> {_id}")
if _sem_busca:
    raise SystemExit("FAIL afirmacao de ausencia na literatura sem busca delimitada "
                     f"[busca:<id>], e sem existir identica na base: {_sem_busca}")
if _busca_morta:
    raise SystemExit(f"FAIL referencia [busca:<id>] que nao resolve: {_busca_morta}")

_buscas = sorted((ROOT / "evidence/literature/searches").glob("*.yaml"))
if not _buscas:
    raise SystemExit("FAIL nenhuma busca delimitada registrada - a regra acima seria vacua")

print(f"PASS corpus: frame derivado dos dados, prosa sem numeral literal "
      f"({_derivado['n_findings']} achados, ondas {_derivado['wave_min']}-{_derivado['wave_max']})")
print(f"PASS ausencia na literatura so por busca delimitada ({len(_buscas)} registrada(s))")
print(f"PASS ADR 0035 publica o D_E que o portao mede ({_medido.group(1)} sobre {_medido.group(2)})")
