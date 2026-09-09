#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
POLICY = json.loads((ROOT / "orchestration/skill-policy.json").read_text(encoding="utf-8"))
PROTOCOL = json.loads((ROOT / "orchestration/evaluation-protocol.json").read_text(encoding="utf-8"))
TESTER = ROOT / "tests/unit/methodology.py"


def set_path(document: dict, path: tuple[str, ...], value: object) -> None:
    cursor = document
    for key in path[:-1]:
        cursor = cursor[key]
    cursor[path[-1]] = value


MUTANTS = [
    ("blanket-injection", "policy", ("selection", "allow_blanket_injection"), True),
    ("sem-gatilho", "policy", ("selection", "require_observable_trigger"), False),
    ("sem-versao", "policy", ("selection", "require_version_compatibility"), False),
    ("sem-quarentena", "policy", ("lifecycle", "initial_state"), "promoted"),
    ("skill-certifica", "policy", ("claims", "skill_is_not_certifier"), False),
    ("snapshot-mutavel", "protocol", ("repository", "fixed_commit_required"), False),
    ("llm-judge", "protocol", ("verifier", "llm_as_judge_for_primary_outcome"), True),
    ("keyword-only", "protocol", ("verifier", "keyword_only_checks_prohibited"), False),
    ("existence-only", "protocol", ("verifier", "file_existence_only_checks_prohibited"), False),
    ("sem-controle-negativo", "protocol", ("verifier", "negative_control_required"), False),
    ("sem-pareamento-snapshot", "protocol", ("design", "same_task_snapshot_between_conditions"), False),
    ("sem-controle-scaffold", "protocol", ("design", "same_model_scaffold_between_paired_conditions"), False),
    ("sem-repeticao", "protocol", ("design", "repeated_trials_required_for_stochastic_agents"), False),
    ("selecao-confundida", "protocol", ("design", "skill_selection_evaluated_separately"), False),
    ("sem-incerteza", "protocol", ("analysis", "report_confidence_intervals"), False),
    ("oculta-negativos", "protocol", ("analysis", "report_null_and_negative_results"), False),
]

# ONDA 12. ESTE ARNES MATAVA POR CRASH, NAO POR ASSERCAO - achado do portao final.
#
# A raiz temporaria continha SO os dois JSON de orchestration. O tester le tambem
# `execution/skills`, `execution/agents` e as fontes de instrucao sob `execution/` e
# `docs/method/`; sem elas ele morre em `FileNotFoundError` ANTES de avaliar qualquer coisa.
# Medido: com a raiz minima e os JSON NAO MUTADOS, `python3 tests/unit/methodology.py` sai 1 com
# traceback. Logo todo `returncode != 0` era o crash, e `KILLED=16/16 EXIT=0` era sinal verde
# medindo nada - invocado ao vivo por `tests/unit/runtime-ports.sh`.
#
# A ironia e registravel: um dos proprios mutantes e `sem-controle-negativo`, e o arnes que o
# executa nao tinha controle negativo. `tests/mutation/run.sh` faz o baseline certo nos arneses
# `.sh`; so este, em Python, nao fazia.
#
# Correcao em duas partes: a raiz passa a espelhar por symlink o que o tester le (leitura apenas),
# e o CONTROLE NEGATIVO roda primeiro - raiz nao mutada tem de sair 0, senao o arnes se declara
# vacuo e reprova em vez de reportar 16/16.
LIDOS_PELO_TESTER = ("execution", "docs")


def monta_raiz(raw: str, policy: dict, protocol: dict) -> Path:
    root = Path(raw)
    (root / "orchestration").mkdir()
    (root / "orchestration/skill-policy.json").write_text(json.dumps(policy), encoding="utf-8")
    (root / "orchestration/evaluation-protocol.json").write_text(json.dumps(protocol), encoding="utf-8")
    # ONDA 13: o tester passou a derivar o conjunto de skills de `registry.capabilities` em vez
    # do nome do diretorio. Sem o registry na raiz, ele volta a morrer por ausencia de arquivo -
    # e o baseline abaixo pegaria isso, mas o arnes ficaria inutil ate alguem consertar.
    (root / "orchestration/registry.json").write_text(
        (ROOT / "orchestration/registry.json").read_text(encoding="utf-8"), encoding="utf-8")
    for nome in LIDOS_PELO_TESTER:
        (root / nome).symlink_to(ROOT / nome, target_is_directory=True)
    return root


def roda(policy: dict, protocol: dict) -> int:
    with tempfile.TemporaryDirectory(prefix="tollens-method-") as raw:
        env = os.environ.copy()
        env["TOLLENS_ROOT"] = str(monta_raiz(raw, policy, protocol))
        return subprocess.run(
            [sys.executable, str(TESTER)],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        ).returncode


baseline = roda(POLICY, PROTOCOL)
if baseline != 0:
    print(f"BASELINE VERMELHO (exit={baseline}): a raiz NAO MUTADA ja reprova.")
    print("Sem baseline verde, todo 'KILLED' abaixo seria crash e nao assercao - o arnes e VACUO.")
    raise SystemExit(1)
print("baseline verde: raiz nao mutada sai 0")

killed = 0
for name, target, path, value in MUTANTS:
    policy = copy.deepcopy(POLICY)
    protocol = copy.deepcopy(PROTOCOL)
    set_path(policy if target == "policy" else protocol, path, value)

    if roda(policy, protocol) == 0:
        print(f"SURVIVED {name}")
    else:
        killed += 1
        print(f"KILLED {name}")

# G107 (issue #51). Os 16 mutantes acima alteram um escalar em policy/protocol; nenhum toca o
# defeito que G107 nomeia, que vive em PROSA sob execution/skills, no proprio universo de
# RESOLUCAO do tester. `monta_raiz` simlinka `execution` inteiro (leitura), entao nao ha como
# reintroduzir o defeito sem escrever no repositorio real. Este bloco isola so
# `execution/skills` como COPIA gravavel - as demais fontes (`execution/agents`, `docs`,
# `orchestration`) continuam simlink/copia read-only da arvore real - e reintroduz `/tdd` num
# arquivo do clone. Segue o precedente do ADR 0032 ("reintroduzido o defeito num clone via
# TOLLENS_ROOT, a assercao reprova; o clone limpo fica verde").
def monta_raiz_skills(raw: str) -> Path:
    root = Path(raw)
    (root / "orchestration").mkdir()
    (root / "orchestration/skill-policy.json").write_text(json.dumps(POLICY), encoding="utf-8")
    (root / "orchestration/evaluation-protocol.json").write_text(json.dumps(PROTOCOL), encoding="utf-8")
    (root / "orchestration/registry.json").write_text(
        (ROOT / "orchestration/registry.json").read_text(encoding="utf-8"), encoding="utf-8")
    (root / "docs").symlink_to(ROOT / "docs", target_is_directory=True)
    (root / "execution").mkdir()
    for _sub in sorted((ROOT / "execution").iterdir()):
        if _sub.name == "skills":
            shutil.copytree(_sub, root / "execution/skills")
        else:
            (root / "execution" / _sub.name).symlink_to(_sub, target_is_directory=True)
    return root


def roda_clone_skills(mutar) -> int:
    with tempfile.TemporaryDirectory(prefix="tollens-method-skills-") as raw:
        root = monta_raiz_skills(raw)
        if mutar is not None:
            mutar(root)
        env = os.environ.copy()
        env["TOLLENS_ROOT"] = str(root)
        return subprocess.run(
            [sys.executable, str(TESTER)],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        ).returncode


def _reintroduz_barra_tdd(root: Path) -> None:
    # Reverte UMA das nove ocorrencias que G107 corrigiu (issue #51):
    # "o agente `tdd`" -> "/tdd". O token `tdd` continua existindo em `execution/agents`
    # (simlink para a arvore real), entao a regressao cai exatamente na classe que a nova
    # assercao existe para pegar: /x que resolve para agente, nao para skill.
    _alvo = root / "execution/skills/prd-to-issues/SKILL.md"
    _texto = _alvo.read_text(encoding="utf-8")
    _texto = _texto.replace("agente `tdd`", "/tdd", 1)
    _alvo.write_text(_texto, encoding="utf-8")


baseline_skills = roda_clone_skills(None)
if baseline_skills != 0:
    print(f"BASELINE CLONE-SKILLS VERMELHO (exit={baseline_skills}): copia intacta de "
          "execution/skills ja reprova antes de qualquer mutacao.")
    print("Sem baseline verde, 'KILLED' abaixo seria crash e nao assercao - o arnes e VACUO.")
    raise SystemExit(1)
print("baseline verde: clone de execution/skills sem mutacao sai 0")

if roda_clone_skills(_reintroduz_barra_tdd) != 0:
    print("KILLED reintroduz-barra-tdd")
    killed += 1
else:
    print("SURVIVED reintroduz-barra-tdd")

TOTAL_MUTANTES = len(MUTANTS) + 1
print(f"KILLED={killed}/{TOTAL_MUTANTES}")
raise SystemExit(0 if killed == TOTAL_MUTANTES else 1)
