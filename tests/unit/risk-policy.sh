#!/usr/bin/env bash
# G103 (issue #47) - O KERNEL GOVERNA POR CLASSE DE RISCO, A ORQUESTRACAO POR ID DE WORKFLOW, E
# ATE AQUI NENHUM ARTEFATO VERSIONADO LIGAVA OS DOIS VOCABULARIOS.
#
# `execution/config/CLAUDE.md` (secao 7) declara 4 classes de risco. `orchestration/registry.json`
# e `orchestration/workflows/*.json` declaram 3 ids de workflow. A ligacao vivia so em prosa nao
# verificavel (CLAUDE.md:3 mapeia por DOMINIO; docs/method/orquestracao-e-avaliacao.md:7 diz so
# "o classificador escolhe"). `orchestration/risk-policy.json` e o artefato que declara a funcao
# risco->workflow, e `orchestration/render.py` e o oraculo que a verifica.
#
# PRINCIPIO ANTITAUTOLOGICO: o oraculo NUNCA le a prosa do proprio arquivo de politica. O DOMINIO
# vem do kernel (a tabela `| Risco | Caminho |`), o CONTRADOMINIO vem do diretorio de workflows em
# disco. A politica so pode ser JULGADA por duas fontes externas a ela, nunca se autoconfirma -
# fixture N6/N7 abaixo provam isso por interseccao: mudar o kernel ou o diretorio, com a politica
# INTACTA, tem de reprovar.
#
# Cada fixture e uma arvore MINIMA sob TOLLENS_ROOT que satisfaz as demais checagens de
# `orchestration/render.py --check` (registry schema_version=2, agents vazio, arquivos de
# convergencia presentes) para que a UNICA coisa em jogo seja a politica de risco.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh). Fixa TMPDIR tambem.
. "$(dirname "$0")/../lib/lock.sh"
VALIDADOR="$PWD/orchestration/render.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

echo "== fixtures sinteticas sob TOLLENS_ROOT proprio =="
python3 - "$TMP" <<'PY'
import copy, json, os, sys

root = sys.argv[1]

KERNEL_BASE = """# kernel de teste (fixture, nao e o kernel real)

## 7. Delegação por risco, não por ritual

| Risco | Caminho |
|---|---|
| trivial | direto |
| normal | escrever, testar |
| médio | escrever, testar, revisar |
| alto — autorização, dado, entrada não confiável, irreversível | investigar, escrever, testar, revisar, refutar |

## 8. outra secao, fora da tabela
"""

# N6 - ANTI-TAUTOLOGIA: uma 5a linha na tabela do KERNEL, politica intacta.
KERNEL_5_CLASSES = KERNEL_BASE.replace(
    "| alto — autorização, dado, entrada não confiável, irreversível | investigar, escrever, testar, revisar, refutar |\n",
    "| alto — autorização, dado, entrada não confiável, irreversível | investigar, escrever, testar, revisar, refutar |\n"
    "| crítico | pânico |\n",
)

# GUARDA DE VACUIDADE: kernel sem a tabela `| Risco | Caminho |` nenhuma.
KERNEL_SEM_TABELA = """# kernel de teste sem secao 7

## 7. Delegação por risco, não por ritual

Prosa sem tabela nenhuma.
"""


def wf(id_):
    return {"id": id_, "entry": "a", "nodes": ["a"], "edges": []}


WORKFLOWS_BASE = {
    "investigation-only": wf("investigation-only"),
    "standard-change": wf("standard-change"),
    "high-risk-change": wf("high-risk-change"),
}

# OPCAO A (ADR 0043): 'normal' e 'medio' convergem para standard-change; 'trivial' sem workflow
# com ausencia DECLARADA; 'alto' -> high-risk-change.
POLICY_BASE = {
    "schema_version": 1,
    "map": {
        "trivial": {"workflow": None, "rationale": "caminho direto; nenhum grafo multi-no e escalonado"},
        "normal": {"workflow": "standard-change", "rationale": "ADR 0043 - superprovisionamento deliberado"},
        "medio": {"workflow": "standard-change", "rationale": "ADR 0043"},
        "alto": {"workflow": "high-risk-change", "rationale": "ADR 0043"},
    },
    "not_risk_selected": {
        "investigation-only": "selecionado pelo tipo da tarefa (investigar sem mutar), nao por classe de risco",
    },
}


def escreve(cenario, kernel_md, workflows, policy, reg_workflows=None):
    d = os.path.join(root, cenario)
    os.makedirs(os.path.join(d, "execution/config"), exist_ok=True)
    os.makedirs(os.path.join(d, "orchestration/workflows"), exist_ok=True)
    os.makedirs(os.path.join(d, ".claude"), exist_ok=True)
    os.makedirs(os.path.join(d, ".codex"), exist_ok=True)
    with open(os.path.join(d, "execution/config/CLAUDE.md"), "w") as f:
        f.write(kernel_md)
    for wid, graph in workflows.items():
        with open(os.path.join(d, "orchestration/workflows", wid + ".json"), "w") as f:
            json.dump(graph, f)
    if policy is not None:
        with open(os.path.join(d, "orchestration/risk-policy.json"), "w") as f:
            json.dump(policy, f, ensure_ascii=False)
    reg = {
        "schema_version": 2,
        "agents": {},
        "workflows": sorted(workflows.keys()) if reg_workflows is None else reg_workflows,
    }
    with open(os.path.join(d, "orchestration/registry.json"), "w") as f:
        json.dump(reg, f)
    with open(os.path.join(d, ".claude/settings.json"), "w") as f:
        f.write("{}")
    with open(os.path.join(d, ".codex/config.toml"), "w") as f:
        f.write("")
    with open(os.path.join(d, ".codex/hooks.json"), "w") as f:
        f.write('{"hooks": {"x": 1}}')
    with open(os.path.join(d, "CLAUDE.md"), "w") as f:
        f.write("x")
    with open(os.path.join(d, "AGENTS.md"), "w") as f:
        f.write("x")


# C0 - positivo: politica da OPCAO A, dominio total, contradominio resolvido.
escreve("c0-base-valido", KERNEL_BASE, WORKFLOWS_BASE, POLICY_BASE)

# C1 - positivo, ROBUSTEZ DE ACENTO: a chave da politica usa "médio" acentuado (igual ao kernel),
# nao a forma ja normalizada - prova que a normalizacao NFD roda dos dois lados, nao so do lado
# do kernel.
pol_c1 = copy.deepcopy(POLICY_BASE)
pol_c1["map"]["médio"] = pol_c1["map"].pop("medio")
escreve("c1-acento-medio", KERNEL_BASE, WORKFLOWS_BASE, pol_c1)

# AUSENTE - risk-policy.json nao existe. E a REPROVA ANTES original (medida na arvore real antes
# desta correcao); replicada aqui como fixture para nao depender do estado da arvore real.
escreve("ausente-sem-politica", KERNEL_BASE, WORKFLOWS_BASE, None)

# VACUO - guarda contra portao por vacuidade: kernel sem a tabela de risco. Um parser que
# devolvesse lista vazia faria a checagem de totalidade passar por ausencia de classe a cobrir.
escreve("vacuo-kernel-sem-tabela", KERNEL_SEM_TABELA, WORKFLOWS_BASE, POLICY_BASE)

# N1 - TOTALIDADE: politica sem a classe 'trivial'.
pol_n1 = copy.deepcopy(POLICY_BASE)
del pol_n1["map"]["trivial"]
escreve("n1-sem-trivial", KERNEL_BASE, WORKFLOWS_BASE, pol_n1)

# N2 - SEM CLASSE ORFA: politica com 'catastrofico', que o kernel nao declara.
pol_n2 = copy.deepcopy(POLICY_BASE)
pol_n2["map"]["catastrofico"] = {"workflow": None, "rationale": "nao existe no kernel"}
escreve("n2-classe-orfa", KERNEL_BASE, WORKFLOWS_BASE, pol_n2)

# N3 - RESOLUCAO: 'medio' aponta para workflow inexistente em disco.
pol_n3 = copy.deepcopy(POLICY_BASE)
pol_n3["map"]["medio"] = {"workflow": "normal-change", "rationale": "workflow que nao existe"}
escreve("n3-workflow-inexistente", KERNEL_BASE, WORKFLOWS_BASE, pol_n3)

# N4 - AUSENCIA DECLARADA (criterio 2 da issue): 'trivial' -> null SEM rationale.
pol_n4 = copy.deepcopy(POLICY_BASE)
pol_n4["map"]["trivial"] = {"workflow": None}
escreve("n4-sem-rationale", KERNEL_BASE, WORKFLOWS_BASE, pol_n4)

# N5 - SEM WORKFLOW ORFAO: remove not_risk_selected, e investigation-only fica inalcancavel.
pol_n5 = copy.deepcopy(POLICY_BASE)
del pol_n5["not_risk_selected"]
escreve("n5-sem-not-risk-selected", KERNEL_BASE, WORKFLOWS_BASE, pol_n5)

# N6 - ANTI-TAUTOLOGIA: kernel com uma 5a classe ('critico'), politica INTACTA.
escreve("n6-kernel-5-classes", KERNEL_5_CLASSES, WORKFLOWS_BASE, POLICY_BASE)

# N7 - CODOMINIO: renomeia high-risk-change no disco para 'high-risk', politica INTACTA (ainda
# aponta para 'high-risk-change'). Prova que o contradominio vem do filesystem, nao de copia.
wf_n7 = {
    "investigation-only": wf("investigation-only"),
    "standard-change": wf("standard-change"),
    "high-risk": wf("high-risk"),
}
escreve("n7-workflow-renomeado", KERNEL_BASE, wf_n7, POLICY_BASE)

# N8 - CONVERGENCIA registry["workflows"] x DISCO (docs/architecture/orquestracao-multirruntime.md
# afirmava "definidos em JSON [...] e validados contra o registry", o que ate esta correcao era
# falso: a lista nunca era lida por verificador algum). registry["workflows"] fica com um item a
# mais do que o disco declara, politica e disco intactos.
escreve("n8-registry-workflows-diverge", KERNEL_BASE, WORKFLOWS_BASE, POLICY_BASE,
        reg_workflows=sorted(WORKFLOWS_BASE.keys()) + ["workflow-fantasma"])
PY

roda(){ TOLLENS_ROOT="$TMP/$1" python3 "$VALIDADOR" --check; }

OUT_C0="$(roda c0-base-valido 2>&1)"; RC_C0=$?
chk "C0 politica da Opcao A (dominio total, contradominio resolvido): aprova" "$RC_C0" 0

OUT_C1="$(roda c1-acento-medio 2>&1)"; RC_C1=$?
chk "C1 chave acentuada 'médio' na politica: aprova (normalizacao dos dois lados)" "$RC_C1" 0

OUT_AUS="$(roda ausente-sem-politica 2>&1)"; RC_AUS=$?
chk "AUSENTE risk-policy.json nao existe: RECUSADO" "$RC_AUS" 1
printf '%s' "$OUT_AUS" | grep -qF "RISK_POLICY_ERROR orchestration/risk-policy.json ausente"
chk "  AUSENTE nomeia o artefato que falta" $? 0

OUT_VAC="$(roda vacuo-kernel-sem-tabela 2>&1)"; RC_VAC=$?
chk "VACUO kernel sem a tabela de risco: RECUSADO (nao passa por vacuidade)" "$RC_VAC" 1
printf '%s' "$OUT_VAC" | grep -qF "nao foi parseada"
chk "  VACUO diagnostica parse vazio, nao aprova por ausencia de ramo" $? 0

OUT_N1="$(roda n1-sem-trivial 2>&1)"; RC_N1=$?
chk "N1 politica sem a classe 'trivial': RECUSADO" "$RC_N1" 1
printf '%s' "$OUT_N1" | grep -qF "classe do kernel sem entrada na politica: 'trivial'"
chk "  N1 nomeia a classe ausente (TOTALIDADE)" $? 0

OUT_N2="$(roda n2-classe-orfa 2>&1)"; RC_N2=$?
chk "N2 politica com 'catastrofico' que o kernel nao declara: RECUSADO" "$RC_N2" 1
printf '%s' "$OUT_N2" | grep -qF "classe na politica que o kernel nao declara: 'catastrofico'"
chk "  N2 nomeia a classe orfa (SEM CLASSE ORFA)" $? 0

OUT_N3="$(roda n3-workflow-inexistente 2>&1)"; RC_N3=$?
chk "N3 'medio' aponta para workflow inexistente: RECUSADO" "$RC_N3" 1
printf '%s' "$OUT_N3" | grep -qF "classe 'medio' aponta para workflow inexistente: 'normal-change'"
chk "  N3 nomeia a classe e o workflow (RESOLUCAO)" $? 0

OUT_N4="$(roda n4-sem-rationale 2>&1)"; RC_N4=$?
chk "N4 'trivial' -> null SEM rationale: RECUSADO" "$RC_N4" 1
printf '%s' "$OUT_N4" | grep -qF "classe 'trivial' sem workflow e SEM justificativa declarada"
chk "  N4 exige ausencia DECLARADA, nao inferida (criterio 2 da issue)" $? 0

OUT_N5="$(roda n5-sem-not-risk-selected 2>&1)"; RC_N5=$?
chk "N5 sem not_risk_selected: investigation-only fica orfao: RECUSADO" "$RC_N5" 1
printf '%s' "$OUT_N5" | grep -qF "workflow 'investigation-only' nao e alcancavel por classe alguma nem declarado em 'not_risk_selected'"
chk "  N5 nomeia o workflow orfao (SEM WORKFLOW ORFAO)" $? 0

OUT_N6="$(roda n6-kernel-5-classes 2>&1)"; RC_N6=$?
chk "N6 ANTI-TAUTOLOGIA: 5a classe no KERNEL, politica intacta: RECUSADO" "$RC_N6" 1
printf '%s' "$OUT_N6" | grep -qF "classe do kernel sem entrada na politica: 'critico'"
chk "  N6 prova que o dominio vem do kernel, nao da propria politica" $? 0

OUT_N7="$(roda n7-workflow-renomeado 2>&1)"; RC_N7=$?
chk "N7 CODOMINIO: workflow renomeado no disco, politica intacta: RECUSADO" "$RC_N7" 1
printf '%s' "$OUT_N7" | grep -qF "classe 'alto' aponta para workflow inexistente: 'high-risk-change'"
chk "  N7 pega o lado do mapa que aponta para o nome antigo" $? 0
printf '%s' "$OUT_N7" | grep -qF "workflow 'high-risk' nao e alcancavel por classe alguma nem declarado em 'not_risk_selected'"
chk "  N7 pega o workflow novo que ficou sem classe (prova que vem do filesystem)" $? 0

OUT_N8="$(roda n8-registry-workflows-diverge 2>&1)"; RC_N8=$?
chk "N8 registry['workflows'] com item que nao existe em disco: RECUSADO" "$RC_N8" 1
printf '%s' "$OUT_N8" | grep -qF "registry['workflows'] diverge do diretorio orchestration/workflows"
chk "  N8 nomeia a divergencia (docs/architecture/orquestracao-multirruntime.md deixa de mentir)" $? 0

echo
echo "== os 3 workflows reais deste repositorio =="
OUTP="$(python3 "$VALIDADOR" --check 2>&1)"; RCP=$?
chk "producao: politica de risco real aprova sobre a arvore real" "$RCP" 0

echo
echo "================ PASS=$P  FAIL=$F ================"
EXPECTED=24
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
[ "$F" -eq 0 ] && echo "politica de risco verde ($P/$EXPECTED)" || echo "politica de risco VERMELHA"
exit "$F"
