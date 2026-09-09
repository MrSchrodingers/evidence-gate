#!/usr/bin/env bash
# G110 (issue #54) - ALCANCE DE ATOR NAO ERA DECLARADO NEM VERIFICADO.
#
# `orchestration/render.py:_check_risk_policy` verifica cinco garantias da funcao
# risco->workflow (totalidade, sem classe orfa, resolucao, ausencia declarada, ALCANCE DE
# WORKFLOW), mas para no ID DE WORKFLOW. Um nivel abaixo - ALCANCE DE ATOR - nao existia oraculo
# algum: `control/hooks/risk-trigger.sh`, que roda em toda escrita de toda sessao, prescreve
# agentes (`revisor-frontend` por extensao de arquivo de UI, `analista-otimalidade` por custo
# assintotico no diff) que a funcao canonica risco->workflow->ator nao alcanca por classe
# alguma, e nada ficava vermelho. `execution/hooks/lentes.sh` estava compativel POR COINCIDENCIA
# com o kernel, nao por construcao (ver ADR 0043, Opcao B viva e nao escolhida).
#
# A PROPRIEDADE. Para toda superficie de guidance REGISTRADA (hook listado em
# `install/hooks-spec.sh`), todo PAPEL que ela emite em execucao tem de ser alcancavel pela
# funcao canonica (existe classe c do kernel com o papel em atores(c), via
# orchestration/risk-policy.json["map"] e orchestration/schedule/<workflow>.json) OU estar
# declarado como nao-selecionado-por-risco em
# orchestration/risk-policy.json["not_risk_selected_actors"] (G110, simetrico a
# "not_risk_selected" que ja existia para workflow).
#
# CONFRONTO DE AUTORIDADES, NAO LITERAL. Um teste que procurasse a string 'refutador' em
# lentes.sh cometeria o mesmo erro que methodology.py:31 cometia antes desta onda - verificar o
# literal em vez da propriedade. Este oraculo nao conhece o nome de agente nenhum nem o nome de
# hook nenhum a priori:
#   - classes de risco vem da tabela `| Risco | Caminho |` de execution/config/CLAUDE.md;
#   - a funcao classe->workflow vem de orchestration/risk-policy.json["map"];
#   - ator por no de workflow vem de orchestration/schedule/<id>.json[<no>]["actor"];
#   - vocabulario de agente vem das CHAVES de orchestration/registry.json["agents"];
#   - a lista de superficies vem da SAIDA de `bash install/hooks-spec.sh @B@`, por regex
#     `bash @B@/(...\.sh)` - nenhum nome de arquivo de hook esta escrito neste teste;
#   - o que cada superficie prescreve e OBSERVADO, executando-a com entradas sinteticas e lendo
#     `hookSpecificOutput.additionalContext` ou o stdout cru - nunca lendo o codigo-fonte dela.
#
# GUARDAS DE VACUIDADE (abortam o teste, nao o aprovam) - fecham o modo de falha "instrumento
# que acha zero porque procurou o campo/nome errado", regra 2 das diretrizes globais:
#   - dominio de risco com menos de 2 classes (G1);
#   - registry sem agente algum (G2);
#   - nenhum hook extraido da saida de install/hooks-spec.sh (G3);
#   - nenhuma mencao de agente encontrada em execucao alguma - fecha o caso "jq ausente -> hook
#     sai 0 mudo -> oraculo passa por vacuidade" (G4).
#
# POR QUE O ORACULO VIVE AQUI, NAO EM orchestration/render.py: estender render.py exigiria ler
# orchestration/schedule/*.json, e o helper `escreve()` de tests/unit/risk-policy.sh nao cria
# esse diretorio - as fixtures C0/C1 la reprovariam. E um executavel novo em orchestration/
# aciona a CAMADA 3 de evidence/cobertura.sh (RAIZES inclui "orchestration"), exigindo piso
# medido. `tests/` nao esta em RAIZES: o oraculo fica aqui com custo zero nessa camada.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh). Fixa TMPDIR tambem
# (nunca /tmp: tmpfs com teto fixo de inodes nesta estacao).
. "$(dirname "$0")/../lib/lock.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

# =============================================================================================
# O ORACULO. Escrito uma vez em $TMP/oraculo.py; `roda()` o invoca contra qualquer ROOT (fixture
# sintetica ou a arvore real deste repositorio).
# =============================================================================================
cat > "$TMP/oraculo.py" <<'PY'
import json, os, re, subprocess, sys, tempfile, unicodedata, pathlib

ROOT = pathlib.Path(sys.argv[1])

def norm(s):
    s = unicodedata.normalize('NFD', s)
    return ''.join(c for c in s if unicodedata.category(c) != 'Mn').strip().lower()

# --- (1) DOMINIO: classes de risco do kernel ---
classes = []
dentro = False
for ln in (ROOT / 'execution/config/CLAUDE.md').read_text(encoding='utf-8').splitlines():
    if re.match(r'^\|\s*Risco\s*\|\s*Caminho\s*\|', ln):
        dentro = True
        continue
    if not dentro:
        continue
    if not ln.startswith('|'):
        break
    if re.match(r'^\|[\s:-]+\|', ln):
        continue
    classes.append(norm(re.split(r'[\s\u2014\u2013-]+', ln.split('|')[1].strip())[0]))
assert len(classes) >= 2, f'guarda de vacuidade: dominio de classes de risco tem menos de 2 elementos ({classes})'

# --- (2) FUNCAO CANONICA COMPOSTA: classe -> atores, via risk-policy.json + schedule/*.json ---
pol = json.loads((ROOT / 'orchestration/risk-policy.json').read_text(encoding='utf-8'))
mapa = {norm(k): v for k, v in (pol.get('map') or {}).items()}
atores_por_classe = {}
for c in classes:
    entrada = mapa.get(c) or {}
    wf = entrada.get('workflow')
    if wf is None:
        atores_por_classe[c] = set()
        continue
    sched = json.loads((ROOT / f'orchestration/schedule/{wf}.json').read_text(encoding='utf-8'))
    atores_por_classe[c] = {v['actor'] for v in sched.values() if v.get('actor')}
alcancaveis = set().union(*atores_por_classe.values()) if atores_por_classe else set()
nao_selecionados = set(pol.get('not_risk_selected_actors') or {})
alcancaveis_ou_declarados = alcancaveis | nao_selecionados

# --- (3) VOCABULARIO DE PAPEL: nomes de agente, das CHAVES do registry (fonte externa) ---
reg = json.loads((ROOT / 'orchestration/registry.json').read_text(encoding='utf-8'))
agentes = set(reg.get('agents') or {})
assert agentes, 'guarda de vacuidade: registry sem agentes'

# --- (4) SUPERFICIES: hooks REGISTRADOS, lidos da SAIDA de install/hooks-spec.sh ---
spec = subprocess.run(['bash', str(ROOT / 'install/hooks-spec.sh'), '@B@'],
                      capture_output=True, text=True)
registrados = sorted(set(re.findall(r'bash @B@/([A-Za-z0-9._-]+\.sh)', spec.stdout)))
assert registrados, 'guarda de vacuidade: nenhum hook extraido da saida de install/hooks-spec.sh'

def acha(nome):
    for d in ('execution/hooks', 'control/hooks', 'evidence/hooks'):
        p = ROOT / d / nome
        if p.is_file():
            return p
    return None

# Entradas sinteticas, uma por categoria detectavel pelas superficies conhecidas hoje.
ENTRADAS = [
    ('prompt', '{"prompt":"qualquer"}'),
    ('ui', json.dumps({"tool_input": {"file_path": "/x/a.vue", "content": "<template><div/></template>"}})),
    ('algo', json.dumps({"tool_input": {"file_path": "/x/a.py", "content": "for i in x:\n    for j in y:\n        pass\n"}})),
    ('data', json.dumps({"tool_input": {"file_path": "/x/a.py", "content": "User.objects.filter(request.user)\n"}})),
    ('dep', json.dumps({"tool_input": {"file_path": "/x/package.json", "content": "{\"dependencies\":{\"a\":\"1\"}}"}})),
    ('exec', json.dumps({"tool_input": {"file_path": "/x/a.py", "content": "os.system(cmd)\n"}})),
]

viol = []
achou_alguma_mencao = False
for nome in registrados:
    p = acha(nome)
    if p is None:
        continue
    for rotulo, payload in ENTRADAS:
        home = tempfile.mkdtemp()
        r = subprocess.run(['bash', str(p)], input=payload, capture_output=True, text=True,
                           env={**os.environ, 'HOME': home}, cwd=str(ROOT))
        out = r.stdout
        try:
            j = json.loads(out)
            out = j.get('hookSpecificOutput', {}).get('additionalContext', '') or out
        except Exception:
            pass
        for ag in sorted(agentes):
            if re.search(rf'(?<![\w-]){re.escape(ag)}(?![\w-])', out):
                achou_alguma_mencao = True
                if ag not in alcancaveis_ou_declarados:
                    viol.append((nome, rotulo, ag))
assert achou_alguma_mencao, 'guarda de vacuidade: nenhuma mencao de agente encontrada em execucao alguma'

if viol:
    for h, rot, ag in sorted(set(viol)):
        print(f'GUIDANCE_ERROR {h} (entrada {rot}) prescreve o agente {ag!r}, '
              f'que a funcao canonica risco->workflow->ator nao alcanca por classe alguma '
              f'nem declara em not_risk_selected_actors')
    sys.exit(1)
print('ok: toda prescricao emitida por superficie de guidance registrada e alcancavel pela '
      'funcao canonica ou declarada nao-selecionada-por-risco')
sys.exit(0)
PY

roda(){ python3 "$TMP/oraculo.py" "$1" 2>&1; }

# =============================================================================================
# FIXTURES SINTETICAS sob $TMP. Vocabulario proprio (agente-a/b/c, wf-normal/wf-alto), separado
# do vocabulario real, para que as fixtures nao dependam do estado da arvore real.
# =============================================================================================
echo "== fixtures sinteticas =="
python3 - "$TMP" <<'PY'
import json, os, sys

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

# G1 - GUARDA DE VACUIDADE: dominio de risco com menos de 2 classes.
KERNEL_1_CLASSE = """# kernel de teste com 1 classe so (fixture)

## 7. Delegação por risco, não por ritual

| Risco | Caminho |
|---|---|
| trivial | direto |
"""

POLICY_BASE = {
    "map": {
        "trivial": {"workflow": None, "rationale": "fixture: caminho direto"},
        "normal": {"workflow": "wf-normal", "rationale": "fixture"},
        "medio": {"workflow": "wf-normal", "rationale": "fixture"},
        "alto": {"workflow": "wf-alto", "rationale": "fixture"},
    },
    "not_risk_selected_actors": {
        "agente-fora-do-alcance": "fixture: acionado por tipo de tarefa, nao por classe de risco",
    },
}

SCHEDULE = {
    "wf-normal": {"n1": {"actor": "agente-a"}},
    "wf-alto": {"n1": {"actor": "agente-a"}, "n2": {"actor": "agente-b"}, "n3": {"actor": "agente-c"}},
}

REGISTRY_AGENTS_BASE = ["agente-a", "agente-b", "agente-c", "agente-fora-do-alcance"]

HOOK_BOM = """#!/usr/bin/env bash
cat >/dev/null
echo "aciona agente-a e agente-fora-do-alcance conforme superficie tocada (fixture)"
exit 0
"""

HOOK_MAU = """#!/usr/bin/env bash
IN="$(cat)"
case "$IN" in
  *.vue*) echo "aciona agente-orfao para revisao (fixture)" ;;
esac
exit 0
"""

HOOK_MUDO = """#!/usr/bin/env bash
cat >/dev/null
exit 0
"""

HOOKS_SPEC_UM_HOOK = '#!/usr/bin/env bash\nB="$1"\necho "bash $B/hook-bom.sh"\n'
HOOKS_SPEC_DOIS_HOOKS = HOOKS_SPEC_UM_HOOK + 'echo "bash $B/hook-mau.sh"\n'
HOOKS_SPEC_SEM_HOOK = '#!/usr/bin/env bash\necho "nada aqui, nenhum caminho de hook"\n'
HOOKS_SPEC_HOOK_MUDO = '#!/usr/bin/env bash\nB="$1"\necho "bash $B/hook-mudo.sh"\n'


def escreve(cenario, kernel_md, policy, registry_agents, hooks_spec_body, hook_files, schedule):
    d = os.path.join(root, cenario)
    os.makedirs(os.path.join(d, "execution/config"), exist_ok=True)
    os.makedirs(os.path.join(d, "execution/hooks"), exist_ok=True)
    os.makedirs(os.path.join(d, "orchestration/schedule"), exist_ok=True)
    os.makedirs(os.path.join(d, "install"), exist_ok=True)
    with open(os.path.join(d, "execution/config/CLAUDE.md"), "w", encoding="utf-8") as f:
        f.write(kernel_md)
    with open(os.path.join(d, "orchestration/risk-policy.json"), "w", encoding="utf-8") as f:
        json.dump(policy, f, ensure_ascii=False)
    for wid, sched in (schedule or {}).items():
        with open(os.path.join(d, "orchestration/schedule", wid + ".json"), "w", encoding="utf-8") as f:
            json.dump(sched, f)
    reg = {"schema_version": 2, "agents": {a: {} for a in registry_agents}}
    with open(os.path.join(d, "orchestration/registry.json"), "w", encoding="utf-8") as f:
        json.dump(reg, f)
    spec_path = os.path.join(d, "install/hooks-spec.sh")
    with open(spec_path, "w", encoding="utf-8") as f:
        f.write(hooks_spec_body)
    os.chmod(spec_path, 0o755)
    for nome, conteudo in (hook_files or {}).items():
        p = os.path.join(d, "execution/hooks", nome)
        with open(p, "w", encoding="utf-8") as f:
            f.write(conteudo)
        os.chmod(p, 0o755)


# POS - positiva: toda prescricao emitida e alcancavel ou declarada.
escreve("pos-alcancavel", KERNEL_BASE, POLICY_BASE, REGISTRY_AGENTS_BASE,
        HOOKS_SPEC_UM_HOOK, {"hook-bom.sh": HOOK_BOM}, SCHEDULE)

# NEG - negativa: um hook prescreve um agente que a funcao nao alcanca e que nao esta declarado.
escreve("neg-agente-orfao", KERNEL_BASE, POLICY_BASE, REGISTRY_AGENTS_BASE + ["agente-orfao"],
        HOOKS_SPEC_DOIS_HOOKS, {"hook-bom.sh": HOOK_BOM, "hook-mau.sh": HOOK_MAU}, SCHEDULE)

# G1 - dominio de risco com menos de 2 classes.
escreve("g1-dominio-vazio", KERNEL_1_CLASSE, POLICY_BASE, REGISTRY_AGENTS_BASE,
        HOOKS_SPEC_UM_HOOK, {"hook-bom.sh": HOOK_BOM}, SCHEDULE)

# G2 - registry sem agente algum.
escreve("g2-registry-vazio", KERNEL_BASE, POLICY_BASE, [],
        HOOKS_SPEC_UM_HOOK, {"hook-bom.sh": HOOK_BOM}, SCHEDULE)

# G3 - install/hooks-spec.sh nao emite caminho de hook reconhecivel.
escreve("g3-sem-hook-extraido", KERNEL_BASE, POLICY_BASE, REGISTRY_AGENTS_BASE,
        HOOKS_SPEC_SEM_HOOK, {}, SCHEDULE)

# G4 - hook registrado e existente, mas nenhuma execucao sintetica menciona agente algum.
escreve("g4-sem-mencao", KERNEL_BASE, POLICY_BASE, REGISTRY_AGENTS_BASE,
        HOOKS_SPEC_HOOK_MUDO, {"hook-mudo.sh": HOOK_MUDO}, SCHEDULE)
PY

OUT_POS="$(roda "$TMP/pos-alcancavel")"; RC_POS=$?
chk "POS fixture positiva (toda prescricao alcancavel ou declarada): aprova" "$RC_POS" 0
printf '%s' "$OUT_POS" | grep -qF "ok: toda prescricao emitida"
chk "  POS emite a mensagem de aprovacao" $? 0

OUT_NEG="$(roda "$TMP/neg-agente-orfao")"; RC_NEG=$?
chk "NEG fixture negativa (hook prescreve agente orfao): RECUSADO" "$RC_NEG" 1
printf '%s' "$OUT_NEG" | grep -qF "GUIDANCE_ERROR hook-mau.sh"
chk "  NEG nomeia a superficie culpada" $? 0
printf '%s' "$OUT_NEG" | grep -qF "(entrada ui)"
chk "  NEG nomeia a entrada sintetica que disparou a prescricao" $? 0
printf '%s' "$OUT_NEG" | grep -qF "'agente-orfao'"
chk "  NEG nomeia o agente inalcancavel e nao declarado" $? 0

OUT_G1="$(roda "$TMP/g1-dominio-vazio")"; RC_G1=$?
chk "G1 dominio com menos de 2 classes: ABORTADO (nao aprova por vacuidade)" "$RC_G1" 1
printf '%s' "$OUT_G1" | grep -qF "guarda de vacuidade: dominio de classes de risco"
chk "  G1 diagnostica a guarda, nao aprova por ausencia de ramo" $? 0

OUT_G2="$(roda "$TMP/g2-registry-vazio")"; RC_G2=$?
chk "G2 registry sem agentes: ABORTADO" "$RC_G2" 1
printf '%s' "$OUT_G2" | grep -qF "guarda de vacuidade: registry sem agentes"
chk "  G2 diagnostica a guarda" $? 0

OUT_G3="$(roda "$TMP/g3-sem-hook-extraido")"; RC_G3=$?
chk "G3 nenhum hook extraido de install/hooks-spec.sh: ABORTADO" "$RC_G3" 1
printf '%s' "$OUT_G3" | grep -qF "guarda de vacuidade: nenhum hook extraido"
chk "  G3 diagnostica a guarda" $? 0

OUT_G4="$(roda "$TMP/g4-sem-mencao")"; RC_G4=$?
chk "G4 hook mudo (nenhuma mencao de agente em execucao alguma): ABORTADO" "$RC_G4" 1
printf '%s' "$OUT_G4" | grep -qF "guarda de vacuidade: nenhuma mencao de agente"
chk "  G4 fecha o caso 'jq ausente -> hook mudo -> aprova por vacuidade'" $? 0

echo
echo "== producao: a arvore real deste repositorio =="
OUT_PROD="$(roda "$PWD")"; RC_PROD=$?
chk "producao: nenhuma superficie de guidance registrada prescreve ator inalcancavel/nao-declarado" "$RC_PROD" 0
if [ "$RC_PROD" -ne 0 ]; then
  printf '%s\n' "$OUT_PROD" | sed 's/^/        /'
fi

echo "================ PASS=$P  FAIL=$F ================"
EXPECTED=15
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
[ "$F" -eq 0 ] && echo "projecao de guidance verde ($P/$EXPECTED)" || echo "projecao de guidance VERMELHA"
exit "$F"
