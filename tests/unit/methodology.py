#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import os
from pathlib import Path

DEFAULT_ROOT = Path(__file__).resolve().parents[2]
ROOT = Path(os.environ.get("TOLLENS_ROOT", DEFAULT_ROOT)).resolve()
policy = json.loads((ROOT / "orchestration/skill-policy.json").read_text(encoding="utf-8"))
protocol = json.loads((ROOT / "orchestration/evaluation-protocol.json").read_text(encoding="utf-8"))

checks: list[tuple[bool, str]] = []


# Tokens com barra que NAO sao invocacao de skill: caminho, flag, unidade, fracao.
_CONHECIDAS_NAO_SKILL = {
    "dev", "tmp", "etc", "opt", "usr", "bin", "var", "home", "root", "proc",
    "sec", "min", "req", "run", "src", "doc", "docs", "img", "png", "svg", "css",
    "com", "org", "net", "app", "api", "url", "www", "http", "https",
}

def check(condition: bool, message: str) -> None:
    checks.append((condition, message))
    print(("PASS" if condition else "FAIL") + " " + message)


selection = policy["selection"]
check(policy["schema_version"] == 1, "schema da politica conhecido")
check(selection["mode"] == "evidence-gated", "selecao de skill exige evidencia")
check(selection["require_observable_trigger"] is True, "gatilho observavel obrigatorio")
check(selection["require_repository_compatibility"] is True, "compatibilidade com repositorio obrigatoria")
check(selection["require_version_compatibility"] is True, "compatibilidade de versao obrigatoria")
check(selection["allow_blanket_injection"] is False, "injecao blanket proibida")
check(selection["max_selected_skills_per_task"] == 1, "composicao multi-skill permanece desabilitada sem avaliacao")

lifecycle = policy["lifecycle"]
check(lifecycle["initial_state"] == "quarantine", "skill nova inicia em quarentena")
check(set(lifecycle["states"]) == {"quarantine", "candidate", "promoted", "deprecated", "rejected"}, "estados de lifecycle fechados")
required = set(lifecycle["promotion_requires"])
check({
    "paired_evaluation",
    "fixed_repository_snapshot",
    "deterministic_requirement_verifier",
    "compatibility_manifest",
    "negative_control",
    "cost_measurement",
    "context_interference_check",
} <= required, "promocao cobre baseline, snapshot, oraculo, compatibilidade, custo e interferencia")
check({"negative_correctness_delta", "version_mismatch", "security_regression", "verifier_invalidated"} <= set(lifecycle["deprecate_on"]), "depreciacao cobre regressao e invalidacao")
claims = policy["claims"]
check(claims["skill_is_not_authority"] is True, "skill nao e autoridade")
check(claims["skill_is_not_certifier"] is True, "skill nao certifica a propria eficacia")
check(claims["self_generated_skill_requires_quarantine"] is True, "skill auto-gerada exige quarentena")

# G102 (issue #46). A LINHA QUE ESTAVA AQUI CHECAVA `policy["default_activation"] == "off"`
# reabrindo o MESMO skill-policy.json e comparando com o literal que ele proprio contem - nao
# podia reprovar em estado nenhum do arquivo, so em erro de leitura. O campo `default_activation`
# nao tinha executor: nenhum programa deste repositorio o lia para decidir coisa alguma.
#
# A proposicao que fica no lugar tem DOIS LADOS INDEPENDENTES, cada um lido de um arquivo
# diferente: o conjunto de skills MODEL-INVOCABLE (`contextual`) DECLARADO em
# `activation.model_invocable_exceptions` de skill-policy.json contra o conjunto DERIVADO do
# FRONTMATTER de cada skill em disco (ausencia da chave `disable-model-invocation: true` em
# execution/skills/<n>/SKILL.md). Nenhum dos dois arquivos contem a string do outro; editar
# qualquer um sozinho reprova.
#
# `tests/unit/skill-invocation-policy.sh` cobre o mesmo par de fontes por skill individual
# (registry.json contra frontmatter) e por presenca de `reason`; este bloco cobre o CONJUNTO
# (activation.model_invocable_exceptions contra o disco), como defesa em profundidade contra
# uma excecao adicionada aqui sem correspondente em disco, ou vice-versa.
_activacao = policy.get("activation") or {}
_excecoes_policy = {e["skill"] for e in _activacao.get("model_invocable_exceptions", [])}
_dir_skills = ROOT / "execution/skills"
_contextual_em_disco = set()
if _dir_skills.is_dir():
    for _sk_dir in sorted(_dir_skills.iterdir()):
        if not _sk_dir.is_dir():
            continue
        _skill_md = _sk_dir / "SKILL.md"
        if not _skill_md.is_file():
            continue
        _bloco_fm = _skill_md.read_text(encoding="utf-8").split("---", 2)
        _fm_texto = _bloco_fm[1] if len(_bloco_fm) >= 3 else ""
        if not re.search(r"^disable-model-invocation:\s*true\s*$", _fm_texto, re.MULTILINE):
            _contextual_em_disco.add(_sk_dir.name)
check(_excecoes_policy == _contextual_em_disco,
      "excecoes de ativacao por modelo em skill-policy.json == skills contextuais em disco"
      + ("" if _excecoes_policy == _contextual_em_disco
         else f" - so na policy: {sorted(_excecoes_policy - _contextual_em_disco)};"
              f" so no disco: {sorted(_contextual_em_disco - _excecoes_policy)}"))
check(len(_contextual_em_disco) >= 1, f"ha skill contextual em disco a conferir (medido: {len(_contextual_em_disco)})")

check(protocol["schema_version"] == 1, "schema do protocolo conhecido")
check(protocol["unit"] == "repository_task_trial", "unidade experimental explicita")
check(protocol["task_tuple"] == ["repository", "environment", "requirement", "skill_condition", "agent_scaffold", "model", "trial"], "tupla experimental controla scaffold, modelo e trial")
repository = protocol["repository"]
check(repository["fixed_commit_required"] is True, "snapshot fixo por tarefa")
check(repository["container_or_immutable_environment_required"] is True, "ambiente reproduzivel obrigatorio")
requirement = protocol["requirement"]
check(requirement["self_sufficient"] is True, "requisito autocontido")
check(requirement["acceptance_criteria_required"] is True, "criterios de aceitacao obrigatorios")
check(requirement["must_not_leak_skill_content"] is True, "requisito nao vaza conteudo da skill")
check(requirement["traceability_required"] is True, "rastreabilidade requisito-oraculo obrigatoria")

verifier = protocol["verifier"]
check(verifier["deterministic"] and verifier["execution_based"], "desfecho primario e deterministico e executado")
check(verifier["llm_as_judge_for_primary_outcome"] is False, "LLM-as-judge nao decide outcome primario")
check(verifier["keyword_only_checks_prohibited"] is True, "oraculo keyword-only proibido")
check(verifier["file_existence_only_checks_prohibited"] is True, "oraculo existence-only proibido")
check(verifier["edge_cases_required"] is True, "casos de borda obrigatorios")
check(verifier["negative_control_required"] is True, "controle negativo obrigatorio")

design = protocol["design"]
check(design["paired_conditions"] == ["without_skill", "with_skill"], "contraste pareado explicito")
check(design["same_task_snapshot_between_conditions"] is True, "snapshot identico entre condicoes")
check(design["same_environment_between_conditions"] is True, "ambiente identico entre condicoes")
check(design["same_model_scaffold_between_paired_conditions"] is True, "modelo e scaffold controlados no par")
check(design["repeated_trials_required_for_stochastic_agents"] is True, "agentes estocasticos exigem repeticao")
check(design["record_execution_order"] is True, "ordem de execucao registrada")
check(design["skill_selection_evaluated_separately"] is True, "retrieval/selecao nao se confunde com utilidade")

metrics = protocol["metrics"]
check({"requirement_pass_rate", "paired_correctness_delta"} <= set(metrics["primary"]), "metricas primarias preservam requisito e delta pareado")
check({"token_cost", "wall_clock_latency", "tool_calls", "test_runs"} <= set(metrics["secondary"]), "custo, latencia e atividade medidos")
check({"security_regressions", "scope_violations", "context_interference_failures"} <= set(metrics["safety"]), "seguranca, escopo e interferencia medidos")
check({"selection_precision", "selection_recall", "unnecessary_injection_rate"} <= set(metrics["selection"]), "qualidade do seletor medida separadamente")

analysis = protocol["analysis"]
check(analysis["report_confidence_intervals"] is True, "incerteza estatistica reportada")
check(analysis["report_discordant_pairs"] is True, "pares discordantes reportados")
check(analysis["separate_model_scaffold_results"] is True, "resultados estratificados por modelo e scaffold")
check(analysis["report_null_and_negative_results"] is True, "resultados nulos e negativos nao sao ocultados")
check(analysis["no_universal_skill_claim_from_single_model"] is True, "um modelo nao sustenta claim universal")
check(analysis["no_universal_scaffold_claim_from_single_scaffold"] is True, "um scaffold nao sustenta claim universal")

# ------------------------------------------------------------------------------------------
# REFERENCIA ENTRE SKILLS TEM DE RESOLVER. Achado de 2026-08-14, e a forma ja e conhecida:
# `execution/skills/promoted/design-system-proposal/SKILL.md` invocava `/direcao-de-arte` em
# QUATRO pontos, e essa skill nao existe - foi absorvida pelo agente `revisor-frontend`. Chamava
# tambem `/defesa-de-tese`, que o CLAUDE.md global declarava absorvida pelo `refutador` desde
# antes, e que continuava promovida.
#
# Referencia morta num fluxo que o operador aciona por comando, sobrevivendo porque NADA
# validava coerencia do registro consigo mesmo. `orchestration/skill-policy.json` ja lista
# `unresolved_reference` como gatilho de depreciacao - o criterio existia e nao tinha portao.
#
# ONDA 12. O PORTAO ACIMA LIA UM UNICO ARQUIVO POR SKILL, e o comentario nao dizia isso.
# `_f = _dir / "SKILL.md"`: os quatro pontos citados foram corrigidos em SKILL.md e o portao
# nascido junto com a correcao passou a ler exatamente o arquivo corrigido. Sobreviveram QUATRO
# invocacoes mortas em `references/` da MESMA skill - `/direcao-de-arte` x2 e `/defesa-de-tese`
# x2 - com o portao verde (TOTAL=50 FAIL=0, medido em 2026-08-17 antes desta linha existir).
#
# A linha de `_locais` ja fazia `rglob("*.md")`: os arquivos de apoio eram universo de RESOLUCAO
# e nunca fonte de LEITURA. O portao conhecia os arquivos que se recusava a abrir.
#
# LIMITE DECLARADO: isto resolve nome de SKILL em qualquer `.md` sob o diretorio da skill. Nao
# verifica que o passo descrito faca o que promete - e oraculo de referencia, nao de conteudo -
# nem alcanca skill `deprecated/`, cujo conteudo e registro e nao instrucao viva.
# ONDA 13: o diretorio deixou de codificar estado. A fonte de verdade do conjunto a
# conferir passa a ser `registry.capabilities` com `source` sob `execution/skills/`.
_reg = json.loads((ROOT / "orchestration/registry.json").read_text(encoding="utf-8"))
governadas = {n for n, c in (_reg.get("capabilities") or {}).items()
              if (c.get("source") or "").startswith("execution/skills/")}
depreciadas = {n for n, c in (_reg.get("capabilities") or {}).items()
               if c.get("state") == "deprecated"}
agentes = {f.stem for f in (ROOT / "execution/agents").glob("*.md")}

# O universo que uma invocacao `/x` pode resolver: skill promovida, agente, ou um arquivo de
# apoio DENTRO da propria skill (`references/x.md`). Qualquer outra coisa e placeholder de prosa
# (declarado abaixo) ou referencia morta.
_PLACEHOLDERS = {"cmd", "nome", "plugin", "exemplo", "path", "arquivo", "termo", "id"}

mortas = []
for _sk in sorted(governadas):
    _dir = ROOT / "execution/skills" / _sk
    _f = _dir / "SKILL.md"
    if not _f.is_file():
        mortas.append(f"{_sk}: sem SKILL.md")
        continue
    _locais = {q.stem for q in _dir.rglob("*.md")} | {q.stem for q in _dir.rglob("*.sh")}
    # TODO arquivo `.md` da skill, nao so o SKILL.md: `references/` e instrucao que o operador
    # segue, e foi exatamente onde a referencia morta sobreviveu ao portao anterior.
    for _md in sorted(_dir.rglob("*.md")):
        # `<` no lookbehind exclui tag de fechamento XML: `</regras-fatia-vertical>` casava
        # como invocacao e era falso positivo. `)` exclui alternancia em prosa: ao alargar a
        # leitura para `references/`, `Marca(s)/produto(s)` passou a casar como `/produto`.
        # Invocacao nunca vem colada a parentese de fechamento; alternancia sempre vem.
        for _tok in sorted(set(re.findall(r"(?<![\w/.<)])/([a-z][a-z0-9-]{2,})(?![\w/.-])", _md.read_text(encoding="utf-8")))):
            if _tok in governadas or _tok in agentes or _tok == _sk:
                continue
            if _tok in _locais or _tok in _PLACEHOLDERS:
                continue
            _onde = _md.relative_to(_dir)
            mortas.append(f"{_sk}/{_onde} -> /{_tok}" + (" (DEPRECADA)" if _tok in depreciadas else " (INEXISTENTE)"))

check(not mortas, "toda invocacao /x em .md da skill resolve para skill, agente ou arquivo local"
      + ("" if not mortas else f" - mortas: {sorted(set(mortas))}"))
# ANTIVACUIDADE em dois eixos: sem skills o caso passaria vazio, e sem agentes o universo de
# resolucao ficaria largo demais e absolveria referencia morta.
check(len(governadas) >= 5, f"ha skills governadas a conferir (medido: {len(governadas)})")
check(len(agentes) >= 5, f"o universo de agentes foi carregado (medido: {len(agentes)})")

# ------------------------------------------------------------------------------------------
# ONDA 12. COMANDO PUBLICADO TEM DE EXISTIR, e a §6.3 regra 1 diz que ele e EXECUTADO antes de
# ser publicado. Medido em 2026-08-17: `execution/skills/promoted/depreciar/SKILL.md` mandava
# `bash scripts/medir-skills.sh` no passo 1 - caminho inexistente desde que a telemetria mudou
# para `evidence/telemetry/`. O operador que seguisse a skill recebia
# "No such file or directory" no primeiro passo. `docs/method/COMO-ADICIONAR-ECOSSISTEMA.md`
# mandava `bash tests/run.sh`, que nunca existiu neste repositorio.
#
# ESCOPO ESTREITO, e a estreiteza e o ponto: so casa caminho REPO-RELATIVO (primeiro segmento e
# diretorio de topo real) precedido de interpretador. Isso exclui de proposito os tres tipos de
# falso positivo medidos na varredura ampla, que rendia 28 achados para 2 defeitos:
#   - exemplo ilustrativo   `src/auth/session.py` (formato de ID), `src/gen_tokens.py` (roda no
#                           projeto do usuario, nao neste)
#   - tabela de referencia  `tests/conftest.py` como ponto de entrada do pytest
#   - registro datado       docs/adr/** inteiro: o caminho era verdadeiro quando escrito, e
#                           reescrever registro e falsificacao de evidencia
_TOPO = {d.name for d in ROOT.iterdir() if d.is_dir() and not d.name.startswith(".")}
_FONTES = sorted((ROOT / "execution").rglob("*.md")) + sorted((ROOT / "docs/method").rglob("*.md"))
_CMD = re.compile(r"(?:bash|sh|python3?)\s+([a-z][a-z0-9_./-]*/[a-z0-9_.-]+\.(?:sh|py))")

comandos_mortos = []
for _src in _FONTES:
    if "/deprecated/" in _src.as_posix():
        continue  # registro de skill morta, nao instrucao viva
    for _cmd in sorted(set(_CMD.findall(_src.read_text(encoding="utf-8")))):
        if _cmd.split("/", 1)[0] not in _TOPO:
            continue  # caminho do projeto do usuario, nao deste repositorio
        if not (ROOT / _cmd).is_file():
            comandos_mortos.append(f"{_src.relative_to(ROOT)} -> {_cmd}")

check(not comandos_mortos, "todo comando publicado em skill/agente/metodo aponta para arquivo existente"
      + ("" if not comandos_mortos else f" - mortos: {comandos_mortos}"))
check(len(_FONTES) >= 20, f"ha fontes de instrucao a conferir (medido: {len(_FONTES)})")

# REFERENCIA POR NUMERO DE SECAO AO CLAUDE.md E PROIBIDA. Medido em 2026-08-17: havia 8
# referencias vivas, e a numeracao ja tinha mudado sob todas elas - `Diretriz 13`/`13.1` (3x)
# apontavam para secao que nao existe mais, `Diretriz 3.1` (4x) e `Diretriz 5` (1x) resolviam
# para secao existente que diz OUTRA COISA. Resolver errado e pior que nao resolver: o leitor
# confere, encontra texto, e conclui que a citacao procede.
#
# ERRATA DA MESMA ONDA. Ate a revisao deste diff, este comentario justificava a proibicao com
# "o referente nao e governado - o CLAUDE.md nao consta do manifesto (48 componentes)". A MESMA
# onda passou a versiona-lo (`execution/config/CLAUDE.md`, tipo `config`, 49 componentes), o que
# tornou a justificativa FALSA no instante em que foi escrita. Dois revisores independentes
# pegaram. Fica registrado em vez de reescrito em silencio: uma ata que afirma o contrario do
# que o commit faz e o defeito central deste repositorio, cometido na correcao dele.
#
# A PROIBICAO CONTINUA, por uma razao que independe de governanca: NUMERO DE SECAO NAO E
# IDENTIFICADOR ESTAVEL. Renumerar muda o referente sem tocar na referencia, e nenhum portao
# consegue detectar "resolve para outra ideia" - so "resolve para o vazio". Foi exatamente o modo
# de falha dominante aqui: 5 das 8 resolviam, para a coisa errada. Governar o arquivo remove o
# caso "nao existe"; nao remove o caso pior. A correcao nao foi renumerar: foi remover o
# acoplamento, porque as frases se sustentam sem o numero.
_diretrizes = []
for _src in _FONTES:
    if "/deprecated/" in _src.as_posix():
        continue
    for _m in re.finditer(r"Diretriz\s+[0-9]+(?:\.[0-9]+)?", _src.read_text(encoding="utf-8")):
        _diretrizes.append(f"{_src.relative_to(ROOT)}: {_m.group(0)}")

check(not _diretrizes, "nenhuma instrucao viva cita secao do CLAUDE.md por numero (referente nao governado)"
      + ("" if not _diretrizes else f" - achadas: {_diretrizes}"))

failed = sum(not ok for ok, _ in checks)
print(f"TOTAL={len(checks)} FAIL={failed}")
raise SystemExit(1 if failed else 0)
