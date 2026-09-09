#!/usr/bin/env python3
"""CONFORMIDADE DE CAPABILITY - o artefato contra a policy, nao a policy contra si mesma.

POR QUE ESTE ARQUIVO EXISTE, e o achado e de auditoria externa, confirmado por medicao.

`orchestration/skill-policy.json` declara cinco estados de lifecycle e SETE condicoes de
promocao: avaliacao pareada, snapshot fixo, verificador deterministico, manifesto de
compatibilidade, controle negativo, medicao de custo e checagem de interferencia de contexto.

`tests/unit/methodology.py` afere que esse JSON CONTEM as clausulas certas. Ele tambem abre
artefatos de skill - resolve invocacoes `/x`, confere comandos publicados - portanto NAO e
verdade que ignore os artefatos. O que ele nao faz, e ninguem fazia, e verificar a proposicao
que de fato importa:

    Promoted(s)  =>  AND_{r in promotion_requires} Evidence(s, r)

Medido em 2026-08-18, antes desta linha existir: oito skills em `execution/skills/promoted/`,
ZERO declarando estado, ZERO com dossie, e `python3 tests/unit/methodology.py` -> TOTAL=53
FAIL=0. O portao provava que a lei estava bem escrita enquanto nada a cumpria. E a forma do
ADR 0030 no nivel da politica: o verificador observa a REPRESENTACAO da garantia, nao o
fenomeno que a garantia pretende controlar.

O QUE MUDOU NA ONDA 13, e o que este arquivo passa a exigir:

  - `state` deixa de ser inferido de nome de diretorio e passa a ser campo declarado em
    `orchestration/registry.json:capabilities`;
  - `state` e `installed` sao INDEPENDENTES, porque colapsa-los tornava a reclassificacao
    epistemologica uma desinstalacao (medido: 49 -> 41 componentes, 0 skills);
  - `promoted` sem dossie valido REPROVA;
  - a divida de avaliacao vira grandeza medida, e nao mais prosa.

DIVIDA DE AVALIACAO (D_E), o mecanismo que faltava para "congelar a expansao":

    D_E = { c : state(c) in {quarantine, candidate, promoted} and not Valid(dossier(c)) }

ONDA 14 - O TETO FOI REMOVIDO, e o motivo importa mais que o mecanismo. A onda 13 comparava
`|D_E| <= D_MAX` com `D_MAX` literal NESTE arquivo, isto e, DENTRO do objeto governado. Duas
fugas foram medidas por auditoria externa e reproduzidas aqui antes de serem aceitas: o mesmo
PR podia adicionar capability e escrever `D_MAX = 9`; e pagar um dossie liberava vaga (8 -> 7)
para outra divida entrar (7 -> 8) sem que nada reprovasse. Teto autodeclarado dentro do que ele
governa e `PolicyDeclared`, nao `PolicyEnforced` - a classe que a onda 13 fechou um nivel
abaixo, cometida um nivel acima pela propria correcao.

A fronteira e agora RELACIONAL, contra o SHA-base:

    D_E(head) SUBCONJUNTO DE D_E(base)      e      |D_E(head)| <= |D_E(base)|

Um PR nao pode editar o proprio criterio, porque o criterio e o estado anterior do repositorio.
As duas regras sao necessarias: a de subconjunto pega a troca de uma divida por outra (que
mantem o TAMANHO), e a de nao-crescimento e o que impede o primeiro debito de entrar livre
depois que a divida chega a zero - conjunto vazio nao tem subconjunto proprio a violar. Sem ref
de base o portao sai 2 (NAO VERIFICADO): "nao reprovou" nao pode ser indistinguivel de "nao foi
medido". Ver ADR 0034.

LIMITE DECLARADO: este portao verifica que o dossie EXISTE e declara os campos exigidos. Nao
verifica que o experimento descrito nele tenha sido de fato executado, nem que suas conclusoes
sejam validas. E oraculo de conformidade, nao de veracidade experimental.
"""
from __future__ import annotations

import datetime
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

try:
    import yaml
except ModuleNotFoundError:                                     # pragma: no cover
    # MESMO PRECEDENTE de evidence/runtime-probes/declared-capabilities.py: sem PyYAML o portao
    # NAO adivinha o frontmatter - ele se declara NAO VERIFICADO. Parser artesanal de YAML erra
    # fail-open, e foi assim que C3/A4 nasceram.
    print("NAO VERIFICADO: pyyaml ausente - o frontmatter dos agentes nao pode ser lido.")
    raise SystemExit(2)

DEFAULT_ROOT = Path(__file__).resolve().parents[2]
ROOT = Path(os.environ.get("TOLLENS_ROOT", DEFAULT_ROOT)).resolve()

registry = json.loads((ROOT / "orchestration/registry.json").read_text(encoding="utf-8"))
policy = json.loads((ROOT / "orchestration/skill-policy.json").read_text(encoding="utf-8"))
# ONDA 15. A obrigacao de prova por tipo de capability vive FORA deste arquivo, em
# `orchestration/evidence-policy.json`. Um portao que carrega o proprio criterio e a
# forma que a onda 14 acabou de remover: quem edita o portao edita a regra.
evpolicy = json.loads((ROOT / "orchestration/evidence-policy.json").read_text(encoding="utf-8"))
OBRIGACOES = evpolicy["proof_obligations"]
DIMENSOES = set(evpolicy["dimensions"])

# F1, ACHADO DO PORTAO FINAL, E A TERCEIRA RECORRENCIA DA MESMA FAMILIA. A onda 14 removeu
# `D_MAX` porque a constante morava no arquivo que o PR edita. A onda 15 removeu o rebaixamento
# de `kind` pela mesma razao. E entao carregou a TABELA DE OBRIGACOES do disco e a usou para
# julgar os DOIS lados da comparacao - head e base. Medido em copia: esvaziar
# `proof_obligations` no mesmo PR devolve `D_E(head)=0` com o portao VERDE.
#
#   PolicyDeclared vs PolicyEnforced, de novo, um nivel acima da correcao anterior.
#
# Mover o arquivo para fora do portao nao removeu a forma: trocou o nome da constante. O que
# remove a forma e a mesma regra que a onda 14 aplicou a divida - o criterio do lado BASE vem
# da ARVORE BASE, que o PR nao pode reescrever.
def _obrigacoes(leitor) -> dict | None:
    """Tabela de obrigacoes na arvore do leitor. `None` quando a policy nao existe la."""
    bruto = leitor("orchestration/evidence-policy.json")
    if bruto is None:
        return None
    try:
        return json.loads(bruto)["proof_obligations"]
    except Exception:
        return None

checks: list[tuple[bool, str]] = []


def check(ok: bool, label: str) -> None:
    checks.append((bool(ok), label))
    print(f"  {'PASS' if ok else 'FAIL'}  {label}")


caps = registry.get("capabilities")
check(isinstance(caps, dict) and len(caps) > 0, "registry declara o bloco `capabilities`")
caps = caps or {}

estados_policy = set(policy["lifecycle"]["states"])
requisitos = list(policy["lifecycle"]["promotion_requires"])
CAMPOS = ("kind", "source", "state", "installed", "activation", "evidence")

# ONDA 14. O TETO CONSTANTE FOI REMOVIDO, e a razao e que ele nao era fronteira.
#
# `D_MAX = 8` era numero literal NESTE arquivo, isto e, dentro do objeto governado. Auditoria
# externa mediu as duas fugas, e ambas passavam pela assercao de divida:
#
#   1. o MESMO PR que adiciona capability sem dossie pode escrever `D_MAX = 9`
#      -> "PASS divida de avaliacao D_E=9 nao excede o teto D_MAX=9"
#   2. dossie pago derruba D_E de 8 para 7, o teto continua 8, e abre uma VAGA:
#      adicionar capability nova sem dossie devolve D_E a 8 -> "PASS 8 <= 8"
#
# O cabecalho proibia levantar o teto por escrito. Proibicao em prosa dentro do arquivo que o
# PR edita e `PolicyDeclared`, nao `PolicyEnforced` - exatamente a classe que a onda 13 fechou
# um nivel abaixo, cometida um nivel acima pela propria correcao.
#
# A fronteira agora e RELACIONAL, medida contra o SHA-base e nao contra uma constante:
#
#     divida(head) SUBCONJUNTO DE divida(base)      e      |divida(head)| <= |divida(base)|
#
# Um PR nao pode editar o proprio criterio, porque o criterio e o estado anterior do
# repositorio. Levantar teto deixa de ser possivel: nao ha teto.

# ---------------------------------------------------------------------------------------
print("== CC1. forma: toda capability declara os campos do schema ==")
sem_campo = [f"{n}:{c}" for n, cap in sorted(caps.items()) for c in CAMPOS if c not in cap]
check(not sem_campo, f"toda capability declara {list(CAMPOS)}"
      + ("" if not sem_campo else f" - faltando: {sem_campo}"))

estado_ruim = [f"{n}={cap.get('state')}" for n, cap in sorted(caps.items())
               if cap.get("state") not in estados_policy]
check(not estado_ruim, f"todo `state` pertence aos estados da policy {sorted(estados_policy)}"
      + ("" if not estado_ruim else f" - invalidos: {estado_ruim}"))

evid_ruim = [n for n, cap in sorted(caps.items())
             if not isinstance(cap.get("evidence"), dict)
             or "status" not in cap["evidence"] or "dossier" not in cap["evidence"]]
check(not evid_ruim, "todo bloco `evidence` declara `status` e `dossier`"
      + ("" if not evid_ruim else f" - malformados: {evid_ruim}"))

# ---------------------------------------------------------------------------------------
print("== CC2. a proposicao que faltava: promoted exige dossie valido ==")


def _le_do_disco(rel: str):
    caminho = ROOT / rel
    return caminho.read_text(encoding="utf-8") if caminho.is_file() else None


def _le_do_git(ref: str):
    def leitor(rel: str):
        r = subprocess.run(["git", "-C", str(ROOT), "show", f"{ref}:{rel}"],
                           capture_output=True, text=True)
        return r.stdout if r.returncode == 0 else None
    # A REF VIAJA COM O LEITOR. Achado de revisao independente (C5): `_digest_de` declarava
    # receber o leitor e nunca o usava - lia sempre do disco. Ao avaliar a BASE, o dossie vinha
    # do blob-base e o digest do artefato vinha do HEAD, entao qualquer PR que tocasse o
    # componente invalidava os dossies DA BASE, inflando `d_base` e AFROUXANDO a monotonicidade.
    # Fail-open, na direcao exata que a onda 14 existiu para fechar.
    leitor.ref = ref  # type: ignore[attr-defined]  # atributo dinamico intencional: a ref viaja com a funcao (ver comentario acima)
    return leitor


def _bytes_do_git(ref: str, rel: str) -> bytes | None:
    r = subprocess.run(["git", "-C", str(ROOT), "show", f"{ref}:{rel}"], capture_output=True)
    return r.stdout if r.returncode == 0 else None


def _arquivos_do_git(ref: str, rel: str) -> list[str] | None:
    """Caminhos de arquivo sob `rel` na ref, relativos a `rel`. None se `rel` nao e arvore."""
    r = subprocess.run(["git", "-C", str(ROOT), "ls-tree", "-r", "--name-only", f"{ref}:{rel}"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return None
    return sorted(l for l in r.stdout.splitlines() if l)


def _digest_de(rel: str, leitor) -> str | None:
    """Digest deterministico de um componente, arquivo ou diretorio, NA ARVORE DO LEITOR.

    Para diretorio, o digest e sobre a lista ORDENADA de (caminho relativo, sha256 do arquivo):
    ordenar e o que torna o valor reproduzivel entre maquinas, e incluir o caminho e o que faz
    renomear dentro do diretorio mudar o digest.

    O MESMO ALGORITMO nos dois lados, por exigencia do ADR 0034: comparar predicados diferentes
    no head e na base produziria diferenca sem significado. Por isso o lado git NAO usa o OID
    nativo do objeto - ele e content-addressed, mas de outro algoritmo, e um dossie escrito sob
    um nao validaria sob o outro.
    """
    ref = getattr(leitor, "ref", None)
    if ref is None:
        caminho = ROOT / rel
        if caminho.is_file():
            return hashlib.sha256(caminho.read_bytes()).hexdigest()
        if caminho.is_dir():
            h = hashlib.sha256()
            for f in sorted(x for x in caminho.rglob("*") if x.is_file()):
                h.update(str(f.relative_to(caminho)).encode())
                h.update(hashlib.sha256(f.read_bytes()).digest())
            return h.hexdigest()
        return None
    bruto = _bytes_do_git(ref, rel)
    filhos = _arquivos_do_git(ref, rel)
    if filhos is None and bruto is not None:
        return hashlib.sha256(bruto).hexdigest()
    if filhos is not None:
        h = hashlib.sha256()
        for nome in filhos:
            conteudo = _bytes_do_git(ref, f"{rel}/{nome}")
            if conteudo is None:
                return None
            h.update(nome.encode())
            h.update(hashlib.sha256(conteudo).digest())
        return h.hexdigest()
    return None


_POLICIES = ("orchestration/skill-policy.json", "orchestration/evidence-policy.json")


def _digest_da_policy(leitor=None) -> str | None:
    """Digest das policies NA ARVORE DO LEITOR. A policy define o que conta como evidencia; um
    dossie avaliado sob outra policy nao vale, e isso tem de ser decidido no mesmo lado em que o
    dossie esta sendo lido."""
    ref = getattr(leitor, "ref", None) if leitor is not None else None
    h = hashlib.sha256()
    for rel in _POLICIES:
        if ref is None:
            h.update((ROOT / rel).read_bytes())
        else:
            b = _bytes_do_git(ref, rel)
            if b is None:
                return None
            h.update(b)
    return h.hexdigest()


# ONDA 28. VOCABULARIO E CHAVES OBRIGATORIAS VEM DA POLICY, NUNCA HARDCODED AQUI - o mesmo
# criterio de F1/onda 15 e de CC8/onda 27: um portao que carrega o proprio criterio nao prova
# nada sobre o artefato, so sobre si mesmo.
_STALENESS = evpolicy.get("staleness") or {}
EVSTATUS_VOCAB = list(_STALENESS.get("evidence_status_vocabulary") or [])
AV_REQUIRED_KEYS = list(_STALENESS.get("evaluated_with_required_keys")
                        or ["runtime", "model", "artifact_digest", "policy_digest"])
STATUS_FRESH = "fresh"


def _le_environment(leitor):
    """Envelope declarado de runtime/modelo suportados (`orchestration/environment.json`),
    NA ARVORE DO LEITOR. `None` quando ausente ou ilegivel."""
    bruto = leitor("orchestration/environment.json")
    if bruto is None:
        return None
    try:
        doc = json.loads(bruto)
    except Exception:
        return None
    return doc if isinstance(doc, dict) else None


def _stale_por_ambiente(av: dict, leitor) -> list[str]:
    """Motivos pelos quais o ambiente declarado em `av` (`evaluated_with`) esta FORA do
    envelope suportado. Lista vazia = ambiente conforme. Envelope ausente ou ilegivel entra
    como motivo (fail-closed): a ausencia do segundo lado da comparacao nao pode virar
    aprovacao silenciosa - o mesmo principio que `_digest_de`/`_digest_da_policy` aplicam a
    digest ausente. PELO LEITOR, NUNCA POR `_le_do_disco`: o mesmo achado C5/F2 dos digests -
    usar o disco do processo para julgar a arvore-BASE e fail-open na direcao exata que a
    onda 14 existiu para fechar."""
    env = _le_environment(leitor)
    if env is None:
        return ["orchestration/environment.json ausente ou ilegivel - ambiente nao verificavel"]
    suportado = env.get("supported") or {}
    motivos = []
    sup_rt = suportado.get("runtime")
    sup_rt = sup_rt if isinstance(sup_rt, dict) else {}
    rt = av.get("runtime")
    if rt not in sup_rt:
        motivos.append(f"runtime {rt!r} fora do conjunto suportado {sorted(sup_rt)}")
    sup_rtv = suportado.get("runtime_version")
    sup_rtv = sup_rtv if isinstance(sup_rtv, list) else []
    rtv = av.get("runtime_version")
    if rtv not in sup_rtv:
        motivos.append(f"runtime_version {rtv!r} fora do conjunto suportado {sup_rtv}")
    sup_md = suportado.get("model")
    sup_md = sup_md if isinstance(sup_md, list) else []
    md = av.get("model")
    if md not in sup_md:
        motivos.append(f"model {md!r} fora do conjunto suportado {sup_md}")
    return motivos


def _upstream_supersession_aberto(cap: dict) -> str | None:
    """Nota da supersessao ABERTA declarada em `cap['upstream_supersession']`, ou `None` se
    nao ha supersessao declarada ou ela ja foi marcada `resolved: true`. Gatilho de
    REAVALIACAO (`evidence-policy.json:staleness.reevaluation_triggers`), nunca de
    depreciacao: esta funcao e PURA sobre o dict e NUNCA le nem escreve `cap['state']` ou
    `cap['installed']` - supersessao aberta impede `fresh`, e nao move o lifecycle."""
    sup = cap.get("upstream_supersession")
    if not isinstance(sup, dict) or not sup:
        return None
    if sup.get("resolved") is True:
        return None
    nota = sup.get("by") or sup.get("note") or "supersessao upstream declarada"
    return f"upstream_supersession aberto: {nota}"


def _status_derivado(cap: dict, leitor=_le_do_disco) -> tuple[str, list[str]]:
    """Status MECANICO do dossie, independente do que `evidence.status` DECLARA: `('absent',
    [])` sem dossie usavel; `('stale', motivos)` quando qualquer dependencia de
    `evidence-policy.json:staleness.invalidated_by` nao casa (ou ha supersessao upstream
    aberta); `('fresh', [])` caso contrario. Quem decide se o dossie e VALIDO como prova de
    promocao (`dossie_valido`, abaixo) combina isto com o que a governanca DECLAROU."""
    ev = cap.get("evidence") or {}
    d = ev.get("dossier")
    if not d:
        return "absent", []
    bruto = leitor(d)
    if bruto is None:
        return "absent", []
    try:
        doc = json.loads(bruto)
    except Exception:
        return "absent", []
    # O dossie tem de cobrir os SETE requisitos que a propria policy declara. Aceitar um
    # dossie que cubra menos seria reintroduzir a lacuna num nivel abaixo.
    #
    # ONDA 13, achado da revisao: `all(r in doc ...)` sozinho aceitava dois casos vazios.
    # Com `doc` sendo dict e valores None, `r in doc` so testa a CHAVE - dossie com os sete
    # nomes e nenhum conteudo passava. Pior: com `doc` sendo uma STRING JSON contendo os sete
    # nomes, `r in doc` vira containment de substring e passava tambem. Uma string nao declara
    # campo nenhum, e o cabecalho promete verificar que o dossie DECLARA os campos.
    if not isinstance(doc, dict):
        return "absent", []
    if not all(r in doc and doc[r] not in (None, "", [], {}) for r in requisitos):
        return "absent", []

    # EVIDENCEVALIDITY (onda 15, estendida onda 28). Valid(c, t0) NAO implica Valid(c, t1). Um
    # dossie e o registro de um experimento PASSADO; quando muda aquilo sobre o que ele
    # concluiu, ele deixa de valer e passa a STALE. Sem isto, "avaliado uma vez" viraria
    # "avaliado para sempre" - a forma temporal do mesmo defeito que este repositorio persegue.
    #
    # DUAS DEPENDENCIAS SAO CONFERIDAS POR DIGEST COMPUTADO AQUI:
    #   artifact_digest  o proprio componente mudou desde a avaliacao
    #   policy_digest    a policy que define o que conta como evidencia mudou
    # DUAS SAO CONFERIDAS CONTRA UM ENVELOPE DECLARADO (onda 28, `orchestration/environment.json`):
    #   runtime, runtime_version, model   ver `_stale_por_ambiente` - a comparacao e
    #                    DECLARADO-contra-DECLARADO, nao observacao de runtime real.
    # `skill_version` e exigido (presenca, `AV_REQUIRED_KEYS`) mas nao comparado contra nada:
    #   nao ha, neste repositorio, um oraculo do "skill_version atualmente vigente" - exigir o
    #   campo torna a dependencia VISIVEL no artefato, nao a torna medida.
    #
    # NAO SE APLICA A `executed_suite`. Evidencia por suite nao envelhece pelo mesmo motivo:
    # ela e REPRODUZIDA a cada execucao da CI. Se o componente mudar e a suite continuar
    # passando, a evidencia continua valida porque acabou de ser produzida de novo. Dossie e
    # registro; suite e producao. So o registro precisa de data de validade.
    av = doc.get("evaluated_with")
    if not isinstance(av, dict):
        return "absent", []
    faltando = [k for k in AV_REQUIRED_KEYS if k not in av or not av[k]]
    if faltando:
        return "absent", [f"evaluated_with sem {faltando}"]

    motivos: list[str] = []
    fonte = cap.get("source") or ""
    if av.get("artifact_digest") != _digest_de(fonte, leitor):
        motivos.append("artifact_digest: o componente mudou desde a avaliacao")
    if av.get("policy_digest") != _digest_da_policy(leitor):
        motivos.append("policy_digest: a policy mudou desde a avaliacao")
    motivos.extend(_stale_por_ambiente(av, leitor))
    sup_motivo = _upstream_supersession_aberto(cap)
    if sup_motivo:
        motivos.append(sup_motivo)
    return ("stale" if motivos else "fresh"), motivos


def dossie_valido(cap: dict, leitor=_le_do_disco) -> bool:
    """Usavel como prova de promocao: a governanca DECLAROU `evidence.status == "fresh"` E a
    derivacao mecanica CONFIRMA `fresh`. As duas condicoes sao necessarias - a primeira e o
    compromisso de que a evidencia foi revista e publicada como tal; a segunda e o que impede
    o compromisso de ser falso (CC9b confere a mesma igualdade para TODA capability, nao so
    para as promovidas)."""
    ev = cap.get("evidence") or {}
    if ev.get("status") != STATUS_FRESH:
        return False
    status, _ = _status_derivado(cap, leitor)
    return status == STATUS_FRESH


promovidas_sem_prova = [n for n, cap in sorted(caps.items())
                        if cap.get("state") == "promoted" and not dossie_valido(cap)]
check(not promovidas_sem_prova,
      "toda capability `promoted` tem dossie que cobre os 7 promotion_requires"
      + ("" if not promovidas_sem_prova else f" - sem prova: {promovidas_sem_prova}"))

# ---------------------------------------------------------------------------------------
print("== CC3. instalacao e independente de lifecycle, mas nao de existencia ==")
# ANCORA, NAO FILTRO. Achado da revisao: `source: "/etc"` passava nas DUAS checagens e a
# lacuna se auto-cancelava. `Path(ROOT) / "/etc"` devolve `/etc` - pathlib deixa o caminho
# absoluto sobrescrever a raiz - entao "fonte existe" dava PASS; e a comparacao disco x registry
# excluia a entrada dos DOIS lados, entao tambem dava PASS. Quem escapava do prefixo saia de
# ambos os oraculos. `install/apply.sh` confina e aborta, mas depender do portao do deploy e
# depender do ultimo elo, como o proprio `install/manifest.sh` registra.
# NOME E COMPONENTE DE CAMINHO. `install/manifest.sh` grava `skills/<nome>` sem validar, e um
# nome com `../` produziu `skills/../../../../tmp/PWNED` no manifesto (medido). `apply.sh:95`
# confina e aborta, entao nao ha escrita arbitraria - mas o proprio `manifest.sh` registra que
# depender do portao do deploy e depender do ultimo elo.
nome_ruim = [n for n in sorted(caps) if not re.fullmatch(r"[a-z0-9][a-z0-9._-]*", n)]
check(not nome_ruim, "todo nome de capability e um componente de caminho seguro"
      + ("" if not nome_ruim else f" - invalidos: {nome_ruim}"))

PREFIXO = "execution/skills/"
fora_do_prefixo = [f"{n} -> {cap.get('source')}" for n, cap in sorted(caps.items())
                   if cap.get("kind") == "skill" and cap.get("installed")
                   and not (cap.get("source") or "").startswith(PREFIXO)]
check(not fora_do_prefixo, f"toda skill instalada declara source sob `{PREFIXO}`"
      + ("" if not fora_do_prefixo else f" - fora: {fora_do_prefixo}"))

fonte_ausente = [f"{n} -> {cap.get('source')}" for n, cap in sorted(caps.items())
                 if cap.get("installed") and not (cap.get("source")
                                                  and (ROOT / cap["source"]).exists())]
check(not fonte_ausente, "toda capability instalada tem fonte existente"
      + ("" if not fonte_ausente else f" - ausentes: {fonte_ausente}"))

retirada_instalada = [n for n, cap in sorted(caps.items())
                      if cap.get("state") in {"deprecated", "rejected"} and cap.get("installed")]
check(not retirada_instalada, "nenhuma capability deprecated/rejected permanece instalada"
      + ("" if not retirada_instalada else f" - instaladas: {retirada_instalada}"))

# O SEGUNDO LADO DO MESMO FURO. `quarantine` significa "nova, nao avaliada", e a policy poe
# `activation.default: manual` (G102, issue #46 - o campo antigo `default_activation: off` nao
# tinha executor nem definicao operacional; ver orchestration/skill-policy.json e
# tests/unit/skill-invocation-policy.sh). Uma capability nao avaliada instalada e carregavel e
# exatamente o risco que a quarentena existe para conter - e era a rota de entrada que escapava
# do teto. Quarentena se exercita por invocacao local explicita, nao por instalacao.
quarentena_instalada = [n for n, cap in sorted(caps.items())
                        if cap.get("state") == "quarantine" and cap.get("installed")]
check(not quarentena_instalada, "nenhuma capability em quarantine esta instalada"
      + ("" if not quarentena_instalada else f" - instaladas: {quarentena_instalada}"))

# O diretorio deixou de carregar semantica, entao ele NAO pode divergir do registry em
# nenhuma direcao: skill em disco nao declarada e capability fantasma; declarada e ausente
# quebra o instalador.
dir_skills = ROOT / "execution/skills"
em_disco = {d.name for d in dir_skills.iterdir() if d.is_dir()} if dir_skills.is_dir() else set()
declaradas_com_fonte = {n for n, cap in caps.items()
                        if (cap.get("source") or "").startswith("execution/skills/")}
check(em_disco == declaradas_com_fonte,
      f"disco e registry coincidem (disco={len(em_disco)} registry={len(declaradas_com_fonte)})"
      + ("" if em_disco == declaradas_com_fonte
         else f" - so em disco: {sorted(em_disco - declaradas_com_fonte)};"
              f" so no registry: {sorted(declaradas_com_fonte - em_disco)}"))

# ---------------------------------------------------------------------------------------
print("== CC3b. a fonte e amarrada ao tipo, e nenhuma capability compartilha fonte ==")
# ACHADO DE REVISAO INDEPENDENTE (C2). CC4 admite capability nova cuja FONTE ja existia na base,
# porque registrar um componente que ja rodava MEDE divida preexistente. A defesa dizia que "a
# fonte ja existir na base" e um fato que o PR nao pode forjar - e e -, mas o PR escolhe QUAL
# caminho declarar. Medido pela revisao: uma capability nova com `kind: agent` e
# `source: "README.md"` entrava com +4 obrigacoes e o portao imprimia PASS pelo nome. Apontar
# para `execution/agents` (o diretorio, que existe na base) tinha o mesmo efeito e cobria um
# `.md` criado no proprio PR.
#
# A fonte passa a ter de casar com a FORMA canonica do tipo. Isso nao e cosmetico: e o que liga
# o nome declarado ao artefato real, sem o qual "descoberta" vira porta de entrada.
FORMA_POR_KIND = {
    "skill": (re.compile(r"^execution/skills/[^/]+$"), "dir"),
    "agent": (re.compile(r"^execution/agents/[^/]+\.md$"), "file"),
    "hook_gate": (re.compile(r"^(control|evidence|execution)/hooks/[^/]+\.sh$"), "file"),
    "hook_guidance": (re.compile(r"^(control|evidence|execution)/hooks/[^/]+\.sh$"), "file"),
    "hook_instrument": (re.compile(r"^(control|evidence|execution)/hooks/[^/]+\.sh$"), "file"),
    "guidance_document": (re.compile(r"^execution/config/[^/]+\.md$"), "file"),
}
_forma_ruim = []
for _n, _c in sorted(caps.items()):
    _src = _c.get("source")
    if _src is None:
        # Tombstone: capability aposentada nao tem fonte, e nao pode estar instalada nem em
        # divida. As duas condicoes ja sao conferidas em CC1/CC3.
        if _c.get("state") in {"deprecated", "rejected"} and not _c.get("installed"):
            continue
        _forma_ruim.append(f"{_n}: source ausente em estado {_c.get('state')!r}")
        continue
    _regra = FORMA_POR_KIND.get(_c.get("kind"))
    if _regra is None:
        _forma_ruim.append(f"{_n}: kind {_c.get('kind')!r} sem forma canonica declarada")
        continue
    _rx, _tipo = _regra
    if not _rx.match(_src):
        _forma_ruim.append(f"{_n}: source {_src!r} fora da forma de {_c.get('kind')}")
        continue
    _cam = ROOT / _src
    if _tipo == "dir" and not _cam.is_dir():
        _forma_ruim.append(f"{_n}: source {_src!r} deveria ser diretorio")
    if _tipo == "file" and not _cam.is_file():
        _forma_ruim.append(f"{_n}: source {_src!r} deveria ser arquivo")
check(not _forma_ruim, "toda fonte casa com a forma canonica do seu tipo"
      + ("" if not _forma_ruim else f" - fora de forma: {_forma_ruim}"))

# FONTE UNICA. Duas capabilities apontando para o mesmo artefato passariam na bijecao de CC5
# (que compara CONJUNTOS) e contariam divida em dobro sobre o mesmo componente - ou, pior,
# permitiriam registrar uma entrada nova reaproveitando a fonte de outra ja conhecida.
_fontes = [c["source"] for c in caps.values() if c.get("source")]
_dup = sorted({s for s in _fontes if _fontes.count(s) > 1})
check(not _dup, "nenhuma fonte e compartilhada por duas capabilities"
      + ("" if not _dup else f" - duplicadas: {_dup}"))

print("== CC4. divida de avaliacao: VETOR por dimensao, monotonico contra a base ==")
# ONDA 15. Ate aqui a divida era um escalar sobre skills: |{skill sem dossie}| = 8. A auditoria
# externa apontou o limite seguinte, e ele e de MEDIDA, nao de mecanismo: 8 e a divida de UMA
# classe. Dez agentes e catorze hooks nao entravam na conta, e o numero 18 citado como "divida
# real" era piso, nao total.
#
# Somar tudo num escalar maior seria pior que o escalar anterior. Skill, agente, portao
# deterministico e guidance sao intervencoes DIFERENTES e nao devem a mesma prova: exigir
# avaliacao pareada de um portao que bloqueia por exit 2 confunde "melhora o resultado" com "faz
# o que diz". Dai o vetor (E_M, E_U, E_C, E_S) e a obrigacao por `kind`, ambos declarados em
# `orchestration/evidence-policy.json` - fora deste arquivo, para que o portao nao carregue o
# criterio que ele aplica.
#
#     divida = { (c, d) : d em obrigacoes(kind(c)) e nao Pago(c, d) }
_EM_DIVIDA = {"quarantine", "candidate", "promoted"}


def _pagas(cap: dict, leitor) -> set:
    """Dimensoes com evidencia VALIDA para esta capability."""
    dims = ((cap.get("evidence") or {}).get("dimensions") or {})
    if not isinstance(dims, dict):
        return set()
    out = set()
    for d, reg in dims.items():
        if not isinstance(reg, dict) or reg.get("status") != "paid":
            continue
        ref = reg.get("ref")
        if reg.get("by") == "executed_suite":
            # MENCAO NAO E EXECUCAO. A medicao que abriu esta onda achou quatro hooks citados
            # pelo NOME dentro de um conjunto de classificacao em `tests/unit/run.sh` - a suite
            # sabia o nome deles, sabia em que categoria caiam, e nunca rodou nenhum. Exigir que
            # o texto da suite contenha o CAMINHO da fonte e o que separa citar de exercitar.
            texto = leitor(ref) if ref else None
            fonte = cap.get("source") or ""
            # TERCEIRA CONDICAO (A2): a suite tem de ser ENUMERADA pelo gerador de relatorio.
            # Sem ela, retirar a linha de `scripts/status.sh` deixava a suite de rodar e nenhum
            # E_M era rebaixado - evidencia paga por uma suite que ninguem executa e a mesma
            # forma de "mencao nao e execucao", um nivel acima. A policy declarava tres
            # condicoes e o portao implementava duas; declarar sem aplicar e o defeito que este
            # repositorio persegue, e ele estava dentro do portao que o persegue.
            # DUAS FORMAS DE SER EXECUTADA pelo gerador: estar na lista literal de suites de
            # unidade, ou cair na varredura `for _mf in tests/mutation/*.sh` que ele faz. Exigir
            # so a primeira reprovaria arnes de mutacao que o gerador de fato roda.
            # PELO LEITOR, NAO PELO DISCO. Achado do portao final (F2): esta linha nasceu com o
            # MESMO defeito de `_digest_de` que a revisao anterior chamou de C5 - o "leitor
            # ignorado" -, e nasceu DENTRO da condicao que a correcao de C5 acabou de
            # acrescentar. Medido com base==head: retirar a enumeracao de uma suite fazia a
            # divida subir de 89 para 102 enquanto o portao imprimia "nao cresce", porque o lado
            # da BASE consultava o `scripts/status.sh` do HEAD e continuava creditando E_M.
            # Segunda reincidencia da mesma familia num arquivo so.
            _ger = leitor("scripts/status.sh") or ""
            enumerada = bool(ref) and (
                ref in _ger
                or (ref.startswith("tests/mutation/") and ref.endswith(".sh")  # type: ignore[union-attr]  # guardado por bool(ref) na linha acima
                    and "tests/mutation/*.sh" in _ger))
            if texto is not None and fonte and fonte in texto and enumerada:
                out.add(d)
        elif reg.get("by") == "dossier":
            if dossie_valido(cap, leitor):
                out.add(d)
    return out


def _divida(registro: dict, leitor, tabela=None) -> set:
    tabela = OBRIGACOES if tabela is None else tabela
    pares = set()
    for n, cap in (registro.get("capabilities") or {}).items():
        if cap.get("state") not in _EM_DIVIDA:
            continue
        obrigadas = tabela.get(cap.get("kind")) or []
        pagas = _pagas(cap, leitor)
        pares |= {(n, d) for d in obrigadas if d not in pagas}
    return pares


# DECLARAR `paid` E UMA AFIRMACAO, NAO UM ROTULO. Sem este caso, uma dimensao marcada `paid`
# com `ref` inexistente - ou apontando para uma suite que apenas MENCIONA o componente - seria
# silenciosamente rebaixada a "nao paga" e apenas engordaria a divida. Isso basta enquanto a
# capability existe nos dois lados da comparacao, e NAO basta no commit que a DESCOBRE: ali ela
# esta fora de `_comuns` e a monotonicidade nao a alcanca. Uma capability recem-registrada podia,
# portanto, nascer com evidencia falsa sem que nada reprovasse. Reprovar a afirmacao FALSA, e nao
# so deixar de credita-la, e o que fecha essa janela - e e a mesma regra que o repositorio aplica
# a si mesmo desde a onda 13: claim maior que a observacao e defeito, nao ruido.
_falsas = sorted(
    f"{n}:{d}" for n, cap in caps.items()
    for d, reg in (((cap.get("evidence") or {}).get("dimensions")) or {}).items()
    if isinstance(reg, dict) and reg.get("status") == "paid" and d not in _pagas(cap, _le_do_disco))
check(not _falsas, "toda dimensao declarada `paid` tem evidencia que de fato valida"
      + ("" if not _falsas else f" - declaradas sem lastro: {_falsas}"))

d_head = _divida(registry, _le_do_disco)
_por_dim = {d: sum(1 for _, dd in d_head if dd == d) for d in sorted(DIMENSOES)}
# ONDA 20 (G17). O numerador percorre so as capabilities em `_EM_DIVIDA`; o denominador imprimia
# `len(caps)`, que inclui o tombstone `deprecated`. Numerador de 33 sobre denominador de 34, na
# mesma linha - e a leitura "34 componentes ativos" que a revisao externa ja tinha corrigido na
# prosa (G16, onda 19) aparecia aqui, na saida do proprio instrumento.
#
# Defeito de EXIBICAO, nao de assercao: as OITO assercoes de CC4 comparam CONJUNTOS de pares
# (capability, dimensao) e cardinalidades desses conjuntos, e nenhuma le este denominador. Os
# unicos leitores de `len(caps)` em assercao sao `len(caps) > 0` e `len(caps) >= 5`, satisfeitos
# por 33 e por 34. Nenhum veredito ja publicado muda.
#
# TROCAR 34 POR 33 NAO FECHARIA A CLASSE, SO A REALIZACAO. "89 obrigacoes sobre 33 capabilities"
# convida a ler "33 capabilities tem divida", e sao 28 - cinco varridas nao devem nada
# (`artifact-discipline.sh`, `ds4-notify.sh`, `fable-guard.sh`, `poka-yoke-lint.sh`,
# `subagent-probe.sh`). A onda inteira existe porque UM denominador foi lido como populacao
# ativa; publicar outro denominador ambiguo trocaria a realizacao do mesmo defeito. Por isso a
# linha publica as TRES populacoes com a relacao entre elas, e o numero que a frase promete -
# "sobre N capabilities endividadas" - e o que ela de fato mede.
_em_divida = sum(1 for c in caps.values() if c.get("state") in _EM_DIVIDA)
_endividadas = len({n for n, _ in d_head})
print(f"        D_E(head)={len(d_head)} obrigacoes em aberto sobre {_endividadas} capabilities "
      f"endividadas")
print(f"        populacao: {_endividadas} endividadas <= {_em_divida} varridas (estado em "
      f"{sorted(_EM_DIVIDA)}) <= {len(caps)} entries no registry")
print(f"        por dimensao: {_por_dim}")

# A BASE E O CRITERIO. Sem ela nao ha comparacao, e "nao reprovou" seria indistinguivel de
# "nao foi medido" - exit 2 = NAO VERIFICADO, a convencao ja usada em tests/unit/concorrencia.sh
# quando o oraculo nao existe no ambiente.
_base = None
for _ref in ("origin/main", "main"):
    if subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--verify", _ref],
                      capture_output=True).returncode == 0:
        _base = _ref
        break

_bruto_base = _le_do_git(_base)("orchestration/registry.json") if _base else None
if _bruto_base is None:
    print("  NAO VERIFICADO: sem ref de base (origin/main ou main). A divida so pode ser")
    print("                  julgada contra o estado anterior, e ele nao esta disponivel.")
    print(f"\nTOTAL={len(checks)} FAIL={sum(not ok for ok, _ in checks)} BASE=ausente")
    raise SystemExit(2)

# AUTOTESTE DO PROPRIO MECANISMO DE VALIDADE TEMPORAL. Achado C5 de revisao independente: a
# primeira versao de `_digest_de` declarava receber o leitor e LIA SEMPRE DO DISCO. Ao avaliar a
# base, o dossie vinha do blob-base e o digest do artefato vinha do HEAD - fail-open, porque
# inflava `d_base` e afrouxava a monotonicidade. Nenhum mutante alcancava: MCAP18/19/20 exercitam
# `dossie_valido` por CC2, que usa o leitor de disco de qualquer forma.
#
# O DISCRIMINANTE E O PROPRIO PR. Todo PR muda pelo menos um arquivo contra a base; para esse
# arquivo, o digest do disco e o da base TEM de diferir. Com o defeito presente eles coincidiam,
# porque os dois vinham do disco. Quando a arvore e identica a base nao ha o que discriminar, e o
# caso se declara NAO VERIFICADO em vez de passar vazio.
_mudados = subprocess.run(["git", "-C", str(ROOT), "diff", "--name-only", _base],
                          capture_output=True, text=True)
_cand = [f for f in _mudados.stdout.splitlines()
         if f and (ROOT / f).is_file() and _digest_de(f, _le_do_git(_base)) is not None]
if not _cand:
    print("  NAO VERIFICADO  o digest honra o leitor: arvore identica a base, nada a discriminar")
else:
    _f = _cand[0]
    check(_digest_de(_f, _le_do_disco) != _digest_de(_f, _le_do_git(_base)),
          f"o digest honra o leitor: disco e base diferem para {_f}")
    _iguais = [f for f in _cand
               if _digest_de(f, _le_do_disco) == _digest_de(f, _le_do_git(_base))]
    check(not _iguais,
          "nenhum arquivo modificado produz digest identico ao da base"
          + ("" if not _iguais else f" - suspeitos: {_iguais[:3]}"))

_reg_base = json.loads(_bruto_base)
# A TABELA DA BASE VEM DA BASE. Quando ela NAO existe la, este e o commit que a introduz: o
# fato e do estado anterior do repositorio e o PR nao pode forja-lo, entao a excecao e limitada
# e temporal. Ela e IMPRESSA, nunca silenciosa, e vale so para o commit de bootstrap.
_OBRIG_BASE = _obrigacoes(_le_do_git(_base))
if _OBRIG_BASE is None:
    print("        bootstrap: `orchestration/evidence-policy.json` nao existe na base; a tabela")
    print("        do head julga os dois lados NESTE commit, e a regra de nao-rebaixamento fica")
    print("        vacua. Do proximo commit em diante a base tem tabela propria.")
    _OBRIG_BASE = OBRIGACOES
else:
    _fracas = sorted(
        f"{k}: base={sorted(set(_OBRIG_BASE[k]))} head={sorted(set(OBRIGACOES.get(k) or []))}"
        for k in _OBRIG_BASE
        if not set(OBRIGACOES.get(k) or []) >= set(_OBRIG_BASE[k]))
    check(not _fracas,
          "nenhum tipo passa a dever MENOS prova do que devia na base"
          + ("" if not _fracas else f" - enfraquecidos: {_fracas}"))

d_base = _divida(_reg_base, _le_do_git(_base), _OBRIG_BASE)
_caps_base = set(_reg_base.get("capabilities") or {})
_novas = set(caps) - _caps_base


def _existe_na_base(rel: str) -> bool:
    if not rel:
        return False
    return subprocess.run(["git", "-C", str(ROOT), "cat-file", "-e", f"{_base}:{rel}"],
                          capture_output=True).returncode == 0


# DESCOBERTA NAO E CRIACAO, e a distincao e decidida por um fato que o PR NAO pode forjar: a
# fonte da capability ja existir na arvore-base. Registrar um hook que ja rodava na maquina do
# operador MEDE divida preexistente; e o oposto de contrai-la. Esta onda registrou 25
# componentes de uma vez por esse caminho, e a divida medida saltou de 8 para dezenas - o
# numero piorou porque a medicao melhorou.
#
# CRIACAO continua permitida, com uma condicao unica e forte: a capability nova precisa NASCER
# COM A DIVIDA ZERADA. Sem essa valvula o portao congelaria o repositorio inteiro, porque um
# componente novo tambem reprovaria em CC3 se ficasse fora do registry - nao haveria movimento
# legal algum. Com ela, expandir continua possivel exatamente na forma que este repositorio
# defende: trazendo a evidencia junto.
_criadas_com_divida = sorted({n for (n, _) in d_head
                              if n in _novas and not _existe_na_base((caps[n] or {}).get("source") or "")})
check(not _criadas_com_divida,
      "capability de fonte NOVA so entra com a divida zerada (descoberta e permitida, criacao endividada nao)"
      + ("" if not _criadas_com_divida else f" - criadas endividadas: {_criadas_com_divida}"))

# MONOTONICIDADE sobre o que ja era conhecido nos DOIS lados. Restringir ao comum e o que
# permite descobrir divida sem que a descoberta seja lida como piora; o que a regra proibe e
# uma capability ja registrada ficar MAIS endividada do que estava.
_comuns = set(caps) & _caps_base
_dh = {(n, d) for (n, d) in d_head if n in _comuns}
_db = {(n, d) for (n, d) in d_base if n in _comuns}
# ACHADO DE REVISAO INDEPENDENTE (C1), e e a mesma classe da onda 14 um nivel acima. A tabela
# de obrigacoes saiu do portao e foi para `orchestration/evidence-policy.json` - correto -, mas
# a CHAVE de entrada nela, o campo `kind`, continuou dentro de `orchestration/registry.json`,
# editavel pelo mesmo PR. Medido pela revisao: reclassificar seis `hook_guidance` para
# `hook_instrument` derruba a divida de 89 para 77 com o portao VERDE, porque a monotonicidade
# proibe CRESCER e reclassificar ENCOLHE.
#
# A regra e de conjunto, nao de igualdade: reclassificar para um tipo MAIS exigente e progresso
# e continua permitido; reclassificar para um tipo que deve MENOS, nao. Capability nova fica de
# fora porque nao ha base com que comparar - e quem a limita e CC3b, que amarra a fonte a forma
# do tipo declarado.
_rebaixadas = []
for _n in sorted(set(caps) & _caps_base):
    # Cada lado com a SUA tabela: usar a do head para julgar a base era metade do defeito F1.
    _ob_h = set(OBRIGACOES.get(caps[_n].get("kind")) or [])
    _ob_b = set(_OBRIG_BASE.get((_reg_base["capabilities"][_n] or {}).get("kind")) or [])
    if not _ob_h >= _ob_b:
        _rebaixadas.append(f"{_n}: {(_reg_base['capabilities'][_n] or {}).get('kind')} -> "
                           f"{caps[_n].get('kind')} perde {sorted(_ob_b - _ob_h)}")
check(not _rebaixadas,
      "nenhuma capability e reclassificada para um tipo que deve MENOS prova"
      + ("" if not _rebaixadas else f" - rebaixadas: {_rebaixadas}"))

_regrediram = sorted(_dh - _db)
check(not _regrediram,
      f"nenhuma capability ja conhecida ganha obrigacao nova em aberto (comuns={len(_comuns)})"
      + ("" if not _regrediram else f" - regressoes: {_regrediram}"))
check(len(_dh) <= len(_db),
      f"a divida das ja conhecidas nao cresce contra {_base}: head={len(_dh)} base={len(_db)}")

# ---------------------------------------------------------------------------------------
print("== CC5. o manifesto reflete o registry (o par que faltava) ==")
# ESTE E O PORTAO QUE TERIA MATADO O CRITICO 1 DESTA ONDA. A onda criou uma SEGUNDA fonte de
# verdade - o registry - e nao fechou o par com a primeira. Medido pela revisao: com o registry
# perdendo a chave `capabilities`, `install/manifest.sh` gravava 41 componentes e ZERO skills com
# exit 0 e stderr vazio, `apply.sh` apagava as oito de `~/.claude/skills/`, e `verify.sh`
# respondia "41/41 ok | ESTADO: conforme". Duas fontes de verdade sem invariante que as ligue
# nao sao duas fontes: sao uma fonte e um boato.
_lock = ROOT / "install/manifest.lock"
if not _lock.is_file():
    check(False, "install/manifest.lock existe para ser conferido contra o registry")
else:
    # PAR (origem, destino), nao so destino. Achado do portao final: comparar apenas o nome de
    # destino deixava sobreviver um manifesto com a ORIGEM do layout pre-onda
    # (`execution/skills/promoted/forge` -> `skills/forge`). O artefato estagnado desta migracao
    # especifica passava justamente pelo portao escrito para pega-la.
    _no_manifesto = {(l.split("\t")[2].split("/", 1)[1], l.split("\t")[1])
                     for l in _lock.read_text(encoding="utf-8").splitlines()
                     if l.startswith("skill\t") and len(l.split("\t")) >= 3}
    _instaladas = {(n, cap["source"]) for n, cap in caps.items()
                   if cap.get("installed") and cap.get("kind") == "skill"}
    check(_no_manifesto == _instaladas,
          f"skills do manifesto == skills instaladas no registry "
          f"(manifesto={len(_no_manifesto)} registry={len(_instaladas)})"
          + ("" if _no_manifesto == _instaladas
             else f" - so no manifesto: {sorted(_no_manifesto - _instaladas)};"
                  f" so no registry: {sorted(_instaladas - _no_manifesto)}"))

    # ONDA 15 - A BIJECAO SOBRE OS QUATRO TIPOS GOVERNADOS, e ela e o que torna a DESCOBERTA de
    # divida limitada.
    #
    # PARCIAL, E O LIMITE E DITO AQUI (achado A3 de revisao independente): dos 49 componentes do
    # manifesto, 33 sao cobertos (8 skill + 10 agent + 14 hook + 1 config) e 16 NAO sao - os 11
    # `adapter` e os 5 `doctool`. Para esses dezesseis continua bastando nao registrar para que
    # nao haja divida a medir. Nao e descuido: adaptador documental e ferramenta de documento sao
    # intervencoes de outra natureza (nao injetam instrucao no contexto nem bloqueiam acao), e a
    # obrigacao de prova delas nao foi modelada. Enquanto nao for, a frase honesta e "o
    # inventario GOVERNADO e fechado", nao "o inventario instalado e fechado". CC4 admite capability nova cuja fonte ja existia na base, porque registrar um
    # hook que ja rodava MEDE divida preexistente em vez de contrai-la. Isso so e seguro se for
    # impossivel um componente instalado ficar FORA do registry: sem esta checagem, bastaria
    # nao registrar para que a divida sumisse do instrumento. Com ela, o inventario instalado e
    # o inventario governado sao o mesmo conjunto, verificado por fonte.
    _TIPO_MANIFESTO = {"skill": "skill", "agent": "agent", "guidance_document": "config",
                       "hook_gate": "hook", "hook_guidance": "hook", "hook_instrument": "hook"}
    _linhas = [l for l in _lock.read_text(encoding="utf-8").splitlines()
               if l and not l.startswith("#") and len(l.split("\t")) >= 3]
    _fontes_manifesto = {l.split("\t")[1] for l in _linhas
                         if l.split("\t")[0] in {"skill", "agent", "hook", "config"}}
    # ONDA 22b. A BIJECAO E POR PROJECAO, NAO GLOBAL. Ate aqui `installed` era lido como
    # "existe no sistema", e o manifesto so modela UMA projecao - a de usuario, `~/.claude`.
    # Quando o kernel passou a ser projetado para o escopo managed, a comparacao global acusou
    # divergencia sobre um componente que esta CORRETAMENTE instalado, so que noutro escopo.
    # O defeito era do modelo: capability e canonica, projecao e derivada, e o manifesto governa
    # uma projecao. `projection` declara qual.
    _fontes_registry = {cap["source"] for cap in caps.values()
                        if cap.get("installed") and cap.get("kind") in _TIPO_MANIFESTO
                        and cap.get("projection", "user") == "user"}
    check(_fontes_manifesto == _fontes_registry,
          f"skill/agente/hook do manifesto == instalados no registry, por FONTE "
          f"(manifesto={len(_fontes_manifesto)} registry={len(_fontes_registry)})"
          + ("" if _fontes_manifesto == _fontes_registry
             else f" - so no manifesto: {sorted(_fontes_manifesto - _fontes_registry)};"
                  f" so no registry: {sorted(_fontes_registry - _fontes_manifesto)}"))

    # E o tipo declarado no registry tem de casar com o tipo do manifesto: registrar um hook
    # como `skill` passaria pela checagem de conjunto acima e mentiria sobre a obrigacao de
    # prova, que e por `kind`.
    _tipo_manifesto = {l.split("\t")[1]: l.split("\t")[0] for l in _linhas}
    _tipo_divergente = sorted(
        f"{cap['source']}: registry={cap['kind']} manifesto={_tipo_manifesto.get(cap['source'])}"
        for cap in caps.values()
        if cap.get("installed") and cap.get("kind") in _TIPO_MANIFESTO
        and cap.get("projection", "user") == "user"
        and _tipo_manifesto.get(cap["source"]) != _TIPO_MANIFESTO[cap["kind"]])
    check(not _tipo_divergente, "o `kind` do registry casa com o tipo do manifesto"
          + ("" if not _tipo_divergente else f" - divergentes: {_tipo_divergente}"))

# ---------------------------------------------------------------------------------------
print("== CC6. amplitude da claim: o registry nao pode declarar confinamento que nao tem ==")
# ONDA 15, achado de auditoria externa. `orchestration/registry.json` declara
# `invariants.single_writer: true` e marca oito agentes com `writes: false`. As duas coisas sao
# lidas como propriedade de ISOLAMENTO - "estes agentes nao escrevem" - e nenhuma das duas e
# isso. Medido: os DEZ agentes recebem `Bash`. Um agente sem `Write`/`Edit` continua podendo
# `sed -i`, `rm`, `git apply`, `python3 -c 'open(...,"w")'`.
#
#     writes=false  NAO IMPLICA  ausencia de capacidade de escrita
#
# O que `writes: false` de fato expressa e PAPEL: o agente nao recebe ferramenta de escrita e
# nao tem mandato para editar. O que `single_writer` de fato expressa e ESCALONAMENTO: o
# validador de `orchestration/schedule.py` recusa configuracao com dois nos de escrita
# concorrentes. Nenhum dos dois e sandbox, mount namespace ou worktree read-only.
#
# Esta e a mesma classe do `--dry-run` da onda 13b - claim mais ampla que a observacao - e a
# correcao e a mesma: nao estreitar a prosa e sim tornar a amplitude VERIFICAVEL. O registry
# passa a declarar `write_confinement`, e este portao exige que a declaracao case com o fato
# medido no frontmatter dos agentes.
_invar = registry.get("invariants") or {}
_conf = _invar.get("write_confinement")
check(_conf in {"none", "tool_grant", "sandbox"},
      f"invariants.write_confinement declarado e valido (medido: {_conf!r})")


def _tools_do_agente(rel: str, leitor=_le_do_disco):
    """Ferramentas do frontmatter do agente. `None` quando o campo `tools:` esta AUSENTE, que
    nao e o mesmo que vazio: pela doc primaria da Anthropic, subagente sem `tools:` HERDA todAS
    as ferramentas - a concessao maxima. Confundir os dois e errar para menos shell, isto e,
    para menos confinamento aparentemente exigido.

    ACHADO DE REVISAO INDEPENDENTE (A4). A primeira versao lia o frontmatter com parser
    artesanal e errava CINCO formas de YAML valido - lista em bloco, lista em flow, escalar
    entre aspas, comentario no fim da linha e `tools:` omitido -, TODAS na direcao fail-open.
    E o repositorio ja sabia disso: `evidence/runtime-probes/declared-capabilities.py` usa
    PyYAML e RECUSA rodar sem ele em vez de adivinhar. O portao novo adivinhava, e adivinhava
    ao contrario.
    """
    texto = leitor(rel)
    if not texto:
        return None
    partes = texto.split("---")
    if len(partes) < 3:
        return None
    fm = yaml.safe_load(partes[1]) or {}
    if not isinstance(fm, dict) or "tools" not in fm:
        return None
    bruto = fm["tools"]
    if isinstance(bruto, str):
        return {x.strip() for x in bruto.split(",") if x.strip()}
    if isinstance(bruto, list):
        return {str(x).strip() for x in bruto if str(x).strip()}
    return set()


_SHELL = {"Bash", "BashOutput", "KillShell"}
# CONFINAMENTO SE DECIDE PELA CAPACIDADE MEDIDA, NAO PELO ROTULO `writes`. Achado de revisao
# independente (C3): a versao anterior so exigia `write_confinement: none` quando havia agente
# `writes: false` COM shell. Marcar os dez agentes como `writes: true` esvaziava a condicao e
# `write_confinement: "sandbox"` passava - a claim exata que esta secao existe para impedir. E a
# clausula de antivacuidade imprimia `PASS ha agentes writes:false a conferir (com shell: 0)`,
# um rotulo afirmando o que a propria contagem negava.
#
# A pergunta certa nao e "quem declarou nao escrever", e "existe ator com shell". Se existe,
# nao ha confinamento a declarar, seja qual for o rotulo.
_com_shell = []
_sem_tools = []
for _n, _a in sorted((registry.get("agents") or {}).items()):
    _tools = _tools_do_agente(_a.get("source", ""))
    if _tools is None:
        _sem_tools.append(_n)      # herda tudo: inclui shell
        _com_shell.append(_n)
    elif _tools & _SHELL:
        _com_shell.append(_n)

# ANTIVACUIDADE REAL: o universo tem de existir e ter sido LIDO. A versao anterior se satisfazia
# com um disjunto vazio.
check(len(registry.get("agents") or {}) >= 5,
      f"ha agentes a conferir (medido: {len(registry.get('agents') or {})})")
check(len(_com_shell) > 0,
      f"a leitura do frontmatter produziu resultado: {len(_com_shell)} de "
      f"{len(registry.get('agents') or {})} agentes tem shell"
      + (f" ({len(_sem_tools)} sem `tools:`, herdando tudo)" if _sem_tools else ""))

check(not _com_shell or _conf == "none",
      "havendo QUALQUER ator com shell, o confinamento declarado tem de ser `none`"
      + ("" if not _com_shell or _conf == "none"
         else f" - declarado {_conf!r} com {len(_com_shell)} agentes de shell: {_com_shell}"))

check(isinstance(_invar.get("single_writer_is_scheduling_only"), bool)
      and _invar.get("single_writer_is_scheduling_only") is True,
      "`single_writer` declarado explicitamente como propriedade de ESCALONAMENTO, nao de isolamento")

# ANTIVACUIDADE. Sem capabilities, todos os casos acima passariam vazios - e um portao que
# aprova o conjunto vazio nao distingue "conforme" de "nao ha o que conferir". Este
# repositorio ja pagou essa forma cinco vezes.
check(len(caps) >= 5, f"ha capabilities a conferir (medido: {len(caps)})")
check(len(requisitos) >= 5, f"a policy declara requisitos de promocao (medido: {len(requisitos)})")

# ---------------------------------------------------------------------------------------
print("== CC7. numero de aparencia medida e derivado, nao guardado ==")
# ACHADO G104 (issue #48). `claude-md` declarava `measured_size_bytes: 18274` como literal
# digitado a mao, sem nenhuma derivacao a partir de `source` nem nenhuma assercao que
# comparasse os dois. A fonte mudou (ce57138, 18274 -> 2924 bytes) e o campo ficou parado em
# 18274, com o portao saindo 0: o nome prometia OBSERVACAO e entregava ESTADO GUARDADO.
#
# A correcao adotada foi REMOVER o campo, nao deriva-lo: zero consumidores medidos por
# varredura do repositorio, e um leitor a mais so pagaria stat() e dependencia de I/O no
# portao para publicar um numero que ninguem le. O que tem de sobreviver a remocao nao e o
# numero, e a REGRA que impede a classe de voltar - por isso esta secao e por CLASSE de nome
# (`^measured_` ou sufixo `_(bytes|count)$`), nao pelo literal `claude-md`: o proximo
# `measured_line_count` digitado a mao ja nasce reprovando.
_PADRAO_MEDIDO = re.compile(r"^measured_|_(bytes|count)$")


def _varre_medidos(caps_):
    """(capability, campo, valor declarado) para todo campo de aparencia medida."""
    return [(n, k, v) for n, cap in sorted(caps_.items())
            for k, v in cap.items() if _PADRAO_MEDIDO.search(k)]


def _deriva_medido(cap, campo):
    """Recomputa o valor a partir do artefato em `source`. `None` = nao derivavel - campo de
    aparencia medida sem fonte, ou com fonte inexistente, e a propria fuga que esta secao
    existe para fechar, entao NAO passa por vacuidade."""
    if campo.endswith("_size_bytes"):
        src = cap.get("source")
        if not src:
            return None
        caminho = ROOT / src
        return caminho.stat().st_size if caminho.is_file() else None
    return None


_medidos = _varre_medidos(caps)
_nao_derivaveis = [f"{n}.{k}={v!r}" for n, k, v in _medidos if _deriva_medido(caps[n], k) is None]
check(not _nao_derivaveis,
      "todo campo de aparencia medida e derivavel de `source`"
      + ("" if not _nao_derivaveis else f" - sem derivacao: {_nao_derivaveis}"))

_divergentes = [f"{n}.{k}: declarado={v} derivado={_deriva_medido(caps[n], k)}"
                for n, k, v in _medidos if _deriva_medido(caps[n], k) not in (None, v)]
check(not _divergentes,
      "todo campo de aparencia medida bate com o valor derivado do artefato"
      + ("" if not _divergentes else f" - {_divergentes}"))

# ANTIVACUIDADE. Apos a remocao do campo em `claude-md`, o conjunto varrido acima fica VAZIO
# e as duas assercoes anteriores passam por vacuidade - "verde" deixaria de distinguir
# "conforme" de "nao ha o que conferir", a mesma forma que este arquivo ja pagou cinco vezes
# (ver fim de CC6). O controle positivo aplica o MESMO walker e o MESMO comparador a um
# fragmento sintetico em memoria, com fonte real (para ser derivavel) e valor sabidamente
# errado, e exige que ele seja acusado.
_sintetico = {"__cc7_controle__": {"source": "orchestration/registry.json",
                                    "measured_size_bytes": -1}}
_hits_sinteticos = _varre_medidos(_sintetico)
_acusado = any(_deriva_medido(_sintetico[n], k) not in (None, v) for n, k, v in _hits_sinteticos)
check(len(_hits_sinteticos) == 1 and _acusado,
      "controle positivo: o walker acusa um valor sabidamente errado em fragmento sintetico"
      + ("" if (len(_hits_sinteticos) == 1 and _acusado)
         else f" - hits={_hits_sinteticos} acusado={_acusado}"))

# ---------------------------------------------------------------------------------------
print("== CC8. lifecycle e exposicao ao router sao eixos independentes (ADR 0044) ==")
# `state` (lifecycle) responde em que fase de avaliacao a capability esta. `exposure` responde o
# que a GOVERNANCA autoriza o router a fazer com ela - proposicao diferente, ja separada de
# `installed` (ADR 0033) e de `projection` (onda 22b) pelo mesmo motivo: colapsar eixos faz uma
# reclassificacao de um deles mudar o outro por acidente.
#
# VOCABULARIO E MAPA VEM DA POLICY, NUNCA HARDCODED AQUI - o mesmo criterio de F1/onda 15: um
# portao que carrega o proprio criterio nao prova nada sobre o artefato, so sobre si mesmo.
_EXPO = evpolicy.get("runtime_exposure") or {}
_EXPO_VOCAB = list(_EXPO.get("vocabulary") or [])
_EXPO_MAPA = _EXPO.get("allowed_by_lifecycle") or {}
_EXPO_EA_CAMPOS = list(_EXPO.get("experimental_auto_requires") or [])
_EXPO_EA_PASTAS = list(_EXPO.get("eval_id_resolves_under") or [])
_EXPO_ESCOPO = _EXPO.get("scope") or "skill"


def _dmi_do_skill(source: str | None) -> bool | None:
    """`disable-model-invocation` do frontmatter de `source/SKILL.md`. `None` quando a fonte
    esta ausente ou o arquivo nao tem frontmatter legivel - indeterminado, nao `False`: um
    tombstone sem `source` nao pode ser lido como 'skill selecionavel pelo modelo'."""
    if not source:
        return None
    caminho = ROOT / source / "SKILL.md"
    if not caminho.is_file():
        return None
    partes = caminho.read_text(encoding="utf-8").split("---")
    if len(partes) < 3:
        return None
    fm = yaml.safe_load(partes[1]) or {}
    if not isinstance(fm, dict):
        return None
    return fm.get("disable-model-invocation") is True


def _eval_id_resolve(eval_id, pastas: list[str]) -> bool:
    """`eval_id` e string decorativa ate resolver para um registro que existe - o mesmo
    principio de `source_ref`/`resolution_ref` do ADR 0038 (tests/unit/governance-links.py)."""
    if not eval_id or not isinstance(eval_id, str):
        return False
    for rel in pastas:
        base = ROOT / rel
        if not base.is_dir():
            continue
        if any(p.is_file() and (p.stem == eval_id or p.name.startswith(f"{eval_id}-")
                                 or p.name.startswith(f"{eval_id}."))
               for p in base.iterdir()):
            return True
    return False


def _exposure_falhas(nome: str, cap: dict) -> list[str]:
    """Falhas de exposicao para UMA capability. Funcao PURA sobre o dict - o mesmo comparador
    julga capabilities reais do registry e fragmentos sinteticos em memoria (padrao de CC7),
    para que as invariantes cuja populacao real e ZERO (quarantine/promoted/rejected) nao
    passem vazias."""
    falhas: list[str] = []
    exp = cap.get("exposure")
    if not isinstance(exp, dict) or "level" not in exp:
        falhas.append(f"{nome}: sem bloco `exposure.level`")
        return falhas
    nivel = exp["level"]
    if _EXPO_VOCAB and nivel not in _EXPO_VOCAB:
        falhas.append(f"{nome}: exposure {nivel!r} fora do vocabulario {_EXPO_VOCAB}")
        return falhas
    estado = cap.get("state")
    permitidos = set(_EXPO_MAPA.get(estado) or [])
    if nivel not in permitidos:
        falhas.append(f"{nome}: lifecycle {estado!r} nao admite exposure {nivel!r}")
    # O SEGUNDO LADO DO MESMO EIXO: `off` e amarrado a `installed`, nao ao lifecycle - e o que
    # liga o eixo novo ao que ja existe (CC3) em vez de criar um paralelo desconectado.
    instalado = bool(cap.get("installed"))
    if nivel == "off" and instalado:
        falhas.append(f"{nome}: exposure off mas installed=true")
    if nivel != "off" and not instalado:
        falhas.append(f"{nome}: exposure {nivel!r} mas installed=false")
    # COERENCIA COM O MECANISMO, na direcao OPOSTA da onda 27: la o esperado vinha do
    # frontmatter e o obtido de `activation`; aqui o eixo e outro (`exposure`, nao `activation`)
    # e a mesma independencia de arquivos-fonte se aplica: SKILL.md de um lado, registry.json
    # do outro.
    dmi = _dmi_do_skill(cap.get("source"))
    if dmi is True and nivel in {"auto", "experimental_auto"}:
        falhas.append(f"{nome}: exposure {nivel!r} mas o frontmatter retira do routing "
                      "(disable-model-invocation: true)")
    if dmi is False and nivel == "manual":
        falhas.append(f"{nome}: exposure manual mas o frontmatter permite selecao pelo modelo")
    if nivel == "experimental_auto":
        faltando = sorted(k for k in _EXPO_EA_CAMPOS if not exp.get(k))
        if faltando:
            falhas.append(f"{nome}: experimental_auto sem {faltando}")
            return falhas
        venc_bruto = exp.get("expires_at")
        try:
            venc = datetime.date.fromisoformat(venc_bruto)
        except (TypeError, ValueError):
            falhas.append(f"{nome}: expires_at nao e data ISO: {venc_bruto!r}")
        else:
            if venc <= datetime.datetime.now(tz=datetime.UTC).date():
                falhas.append(f"{nome}: experimental_auto VENCIDA em {venc.isoformat()}")
        if not _eval_id_resolve(exp.get("eval_id"), _EXPO_EA_PASTAS):
            falhas.append(f"{nome}: eval_id {exp.get('eval_id')!r} nao resolve sob {_EXPO_EA_PASTAS}")
    return falhas


_alvos_expo = {n: c for n, c in caps.items() if c.get("kind") == _EXPO_ESCOPO}
check(len(_alvos_expo) >= 5, f"ha {_EXPO_ESCOPO} a conferir por exposicao (medido: {len(_alvos_expo)})")

_falhas_expo = [f for n, c in sorted(_alvos_expo.items()) for f in _exposure_falhas(n, c)]
check(not _falhas_expo,
      f"toda capability `{_EXPO_ESCOPO}` declara exposure conforme ao lifecycle, a `installed` e ao frontmatter"
      + ("" if not _falhas_expo else f" - {_falhas_expo}"))

# ANTIVACUIDADE + CONTROLE SINTETICO EM MEMORIA, no padrao de CC7 (linhas 903-917 acima). No
# registry real, `quarantine`, `promoted` e `rejected` tem populacao ZERO: sem fixture, tres das
# cinco linhas de `allowed_by_lifecycle` nunca seriam exercitadas, e "verde" nao distinguiria
# "conforme" de "nao ha o que conferir".
_frag_negativo = {"kind": "skill", "state": "quarantine", "installed": False,
                   "exposure": {"level": "auto"}}
_frag_positivo = {"kind": "skill", "source": "execution/skills/depreciar", "state": "candidate",
                   "installed": True, "exposure": {"level": "manual"}}
_falhas_negativo = _exposure_falhas("__cc8_negativo__", _frag_negativo)
_falhas_positivo = _exposure_falhas("__cc8_positivo__", _frag_positivo)
check(bool(_falhas_negativo),
      "controle negativo: fragmento sintetico quarantine+auto e acusado"
      + ("" if _falhas_negativo else " - nao foi acusado, o comparador estaria vacuo"))
check(not _falhas_positivo,
      "controle positivo: fragmento sintetico conforme (candidate+manual) nao e acusado"
      + ("" if not _falhas_positivo else f" - {_falhas_positivo}"))

# ---------------------------------------------------------------------------------------
print("== CC9. evidencia envelhece quando runtime, modelo, artefato ou policy mudam (ADR 0046) ==")
# `evidence.status` (declarado no registry) e o status DERIVADO por `_status_derivado` (digest +
# ambiente + supersessao) sao duas coisas diferentes que tem de COINCIDIR, no mesmo padrao ja
# aplicado a `measured_size_bytes` em CC7: declarar um valor que a derivacao nao sustenta e a
# mesma classe de defeito, so que no campo `status` em vez de num inteiro.
check(len(EVSTATUS_VOCAB) >= 2,
      f"a policy declara vocabulario fechado de evidence.status (medido: {EVSTATUS_VOCAB})")

_status_fora_vocab = [f"{n}={ (cap.get('evidence') or {}).get('status')!r}"
                      for n, cap in sorted(caps.items())
                      if (cap.get("evidence") or {}).get("status") not in EVSTATUS_VOCAB]
check(bool(EVSTATUS_VOCAB) and not _status_fora_vocab,
      f"todo evidence.status pertence ao vocabulario fechado {EVSTATUS_VOCAB}"
      + ("" if not _status_fora_vocab else f" - fora do vocabulario: {_status_fora_vocab}"))

# DECLARADO == DERIVADO, para toda capability - nao so para as promovidas que CC2 ja julga.
# Uma capability em `candidate` que declara `fresh` sem que a mecanica sustente e a MESMA
# forma de claim falsa que CC4 ja reprova para `dimensions..status: paid` sem lastro.
_divergentes_status = []
_relatorio_invalidated_by: dict[str, list[str]] = {}
for _n, _cap in sorted(caps.items()):
    _declarado = (_cap.get("evidence") or {}).get("status")
    _derivado, _motivos = _status_derivado(_cap, _le_do_disco)
    _relatorio_invalidated_by[_n] = _motivos
    if _declarado != _derivado:
        _divergentes_status.append(
            f"{_n}: declarado={_declarado!r} derivado={_derivado!r}"
            + (f" ({'; '.join(_motivos)})" if _motivos else ""))
check(not _divergentes_status,
      "evidence.status declarado bate com o status derivado mecanicamente (digest + ambiente + "
      "supersessao)"
      + ("" if not _divergentes_status else f" - divergentes: {_divergentes_status}"))

# `invalidated_by` DERIVADO, IMPRESSO por capability - nunca guardado (mesmo principio de CC7:
# numero de aparencia medida e derivado, nao guardado).
for _n in sorted(_relatorio_invalidated_by):
    if _relatorio_invalidated_by[_n]:
        print(f"        invalidated_by[{_n}] = {_relatorio_invalidated_by[_n]}")

# CONTROLE: upstream_supersession ABERTO e detectado; RESOLVIDO nao bloqueia. Funcao PURA sobre
# fragmento sintetico, no padrao de CC7/CC8 - a populacao real do registry nao declara nenhuma
# supersessao hoje, e sem fixture as duas branches nunca seriam exercitadas.
_sup_aberta = {"upstream_supersession": {"by": "runtime nativo absorveu a funcao", "resolved": False}}
_sup_resolvida = {"upstream_supersession": {"by": "runtime nativo absorveu a funcao", "resolved": True}}
_sup_ausente: dict = {}
check(_upstream_supersession_aberto(_sup_aberta) is not None,
      "controle positivo: upstream_supersession aberto e detectado")
check(_upstream_supersession_aberto(_sup_resolvida) is None,
      "controle: upstream_supersession com resolved=true nao bloqueia frescor")
check(_upstream_supersession_aberto(_sup_ausente) is None,
      "controle: ausencia de upstream_supersession nao bloqueia frescor (campo e OPCIONAL)")

# upstream_supersession e gatilho de REAVALIACAO, nunca de depreciacao: a mesma funcao que
# calcula o motivo NUNCA le nem escreve `state`/`installed` - a prova e que o fragmento
# sintetico, com `state` presente, sai do calculo intocado.
_frag_estado = {"kind": "skill", "state": "promoted", "installed": True,
               "upstream_supersession": {"by": "x", "resolved": False}}
_antes_estado = (_frag_estado.get("state"), _frag_estado.get("installed"))
_upstream_supersession_aberto(_frag_estado)
check((_frag_estado.get("state"), _frag_estado.get("installed")) == _antes_estado,
      "controle: avaliar upstream_supersession nao move `state` nem `installed` da capability")

failed = sum(not ok for ok, _ in checks)
print(f"\nTOTAL={len(checks)} FAIL={failed}")
raise SystemExit(1 if failed else 0)
