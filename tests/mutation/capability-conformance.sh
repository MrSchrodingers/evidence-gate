#!/usr/bin/env bash
# VALIDACAO POR MUTACAO DO PORTAO DE CONFORMIDADE DE CAPABILITY.
#
# POR QUE EXISTE, e o achado e do portao final da onda 13.
#
# `tests/unit/capability-conformance.py` nasceu com sete mutantes validando suas assercoes - e
# os sete foram rodados A MAO, num clone descartado no fim da sessao. Nenhum comando deste
# repositorio os reexecutava. A tabela de validacao do ADR 0033 era honesta e IRREPRODUZIVEL, o
# que a torna afirmacao, nao evidencia: ninguem consegue refutar amanha o que so existiu num
# terminal ontem.
#
# Pior, e o portao final mediu: `docs/status.generated.md` registra o exit do portao como VALOR
# numa tabela, nao como condicao. Com o portao reprovando, `scripts/status.sh --check` acusa o
# artefato desatualizado e a instrucao publicada manda regenerar - o que grava `| 15 | 1 |` e
# devolve o `--check` ao verde COM O PORTAO VERMELHO. Enforcement por comparacao de bytes de uma
# tabela e lavavel. Por isso o portao entra tambem em `tests/unit/runtime-ports.sh`, que e passo
# dedicado de CI com propagacao de exit.
#
# Este arnes e `.sh` de proposito: a varredura de completude de `scripts/status.sh` faz
# `for _mf in tests/mutation/*.sh`, e um arnes `.py` nasceria fora do relatorio - a mesma classe
# que o ADR 0029 nomeia como "instrumento escrito e nao reportado".
#
# CADA MUTANTE MUTA O REGISTRY (ou o manifesto), NUNCA O PORTAO. Mutar o verificador provaria
# que ele reage a si mesmo; o que precisa ser provado e que ele reage ao ARTEFATO.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/lib/lock.sh
. tests/lib/arena.sh

P=0; F=0; EXPECTED_MUTANTS=29
REG="orchestration/registry.json"
LOCK="install/manifest.lock"
POR="tests/unit/capability-conformance.py"

# BASELINE. Sem ele todo "mutante morto" abaixo poderia ser crash de ambiente, e o arnes de
# `tests/mutation/methodology.py` ja pagou exatamente essa forma nesta mesma semana: matava
# 16/16 por FileNotFoundError, com o tester nao mutado ja reprovando.
if ! python3 "$POR" >/dev/null 2>&1; then
  echo "BASELINE VERMELHO: o portao ja reprova na arvore nao mutada." >&2
  echo "Sem baseline verde, todo 'MORTO' abaixo seria crash e nao assercao - o arnes e VACUO." >&2
  exit 1
fi
echo "baseline verde: portao sai 0 na arvore nao mutada"

_bak(){ cp "$REG" "$REG.bak"; cp "$LOCK" "$LOCK.bak"; }
_rst(){ mv -f "$REG.bak" "$REG"; mv -f "$LOCK.bak" "$LOCK"; }

mutante(){ # $1=nome $2=descricao $3=exit esperado $4=script python de mutacao
  local nome="$1" desc="$2" want="$3" prog="$4" got
  _bak
  python3 -c "$prog" || { echo "  ERRO  $nome: mutacao falhou"; F=$((F+1)); _rst; return; }
  python3 "$POR" >/dev/null 2>&1; got=$?
  if [ "$got" -eq "$want" ]; then echo "  MORTO $nome - $desc (exit=$got)"; P=$((P+1))
  else echo "  SOBREVIVEU $nome - $desc (exit=$got, esperado=$want)"; F=$((F+1)); fi
  _rst
}

_PY='import json,pathlib
p=pathlib.Path("orchestration/registry.json"); r=json.loads(p.read_text()); c=r["capabilities"]
'
_SAVE='
p.write_text(json.dumps(r,ensure_ascii=False,indent=2))'

echo "== mutantes do lifecycle =="
mutante MCAP1 "promoted sem dossie reprova" 1 \
  "$_PY"'c["graphify"]["state"]="promoted"'"$_SAVE"

mutante MCAP2 "dossie cobrindo 2 dos 7 requisitos reprova" 1 \
  "$_PY"'
import os
os.makedirs("evidence/skills",exist_ok=True)
open("evidence/skills/graphify.json","w").write(json.dumps({"paired_evaluation":{"ok":1},"cost_measurement":{"ok":1}}))
c["graphify"].update(state="promoted",evidence={"dossier":"evidence/skills/graphify.json","status":"valid"})'"$_SAVE"

# CONTROLE POSITIVO, e ele e o que impede o portao de ser "reprova tudo". Sem este caso,
# "nunca aprova" seria indistinguivel de "verifica corretamente".
# CONTROLE POSITIVO. Sem ele o portao podia ser `return FAIL` e todos os mutantes negativos
# "morreriam". Desde a onda 15 o dossie tambem precisa de `evaluated_with` que ainda case com o
# ambiente - o controle passa a exercitar a validade TEMPORAL no sentido de que ela APROVA.
#
# O digest e recalculado aqui com o mesmo algoritmo do portao. Isso NAO testa o algoritmo (um
# erro nele passaria nos dois lados); testa a POLITICA - dossie casado aprova, dossie
# descasado reprova, que e o par MCAP3/MCAP18. Limite declarado, nao disfarcado.
_DIG='
import hashlib, pathlib
def dig(rel):
    c = pathlib.Path(rel)
    if c.is_file(): return hashlib.sha256(c.read_bytes()).hexdigest()
    h = hashlib.sha256()
    for f in sorted(x for x in c.rglob("*") if x.is_file()):
        h.update(str(f.relative_to(c)).encode()); h.update(hashlib.sha256(f.read_bytes()).digest())
    return h.hexdigest()
def digpol():
    h = hashlib.sha256()
    for rel in ("orchestration/skill-policy.json","orchestration/evidence-policy.json"):
        h.update(pathlib.Path(rel).read_bytes())
    return h.hexdigest()
import os, json as _j
reqs=_j.load(open("orchestration/skill-policy.json"))["lifecycle"]["promotion_requires"]
os.makedirs("evidence/skills",exist_ok=True)
def dossie(extra=None, fonte="execution/skills/graphify"):
    d={k:{"ok":True} for k in reqs}
    d["evaluated_with"]={"runtime":{"claude_code":"2.1.0"},"model":{"name":"opus-5"},
                         "artifact_digest":dig(fonte),"policy_digest":digpol()}
    if extra is not None: d["evaluated_with"].update(extra)
    open("evidence/skills/graphify.json","w").write(_j.dumps(d))
'

# `exposure` acompanha a promocao hipotetica (ADR 0044): `promoted` nao admite
# `experimental_auto` (o nivel real de graphify no registry), entao o controle positivo tem de
# elevar tambem o eixo de exposicao para um nivel que `promoted` admite - `auto`, coerente com o
# frontmatter de graphify (sem `disable-model-invocation`, que reprovaria `manual`). Sem este
# ajuste o controle positivo reprovaria por um eixo que este mutante nunca pretendeu exercitar.
mutante MCAP3 "dossie 7/7 com evaluated_with casado APROVA (controle positivo)" 0 \
  "$_PY$_DIG"'
dossie()
c["graphify"].update(state="promoted",exposure={"level":"auto"},evidence={"dossier":"evidence/skills/graphify.json","status":"valid"})'"$_SAVE"

mutante MCAP4 "dossie com os 7 nomes e valores VAZIOS reprova" 1 \
  "$_PY"'
import os
reqs=json.load(open("orchestration/skill-policy.json"))["lifecycle"]["promotion_requires"]
os.makedirs("evidence/skills",exist_ok=True)
open("evidence/skills/graphify.json","w").write(json.dumps({k:None for k in reqs}))
c["graphify"].update(state="promoted",evidence={"dossier":"evidence/skills/graphify.json","status":"valid"})'"$_SAVE"

echo "== mutantes da divida de avaliacao =="
mutante MCAP5 "capability nova em candidate estoura o teto" 1 \
  "$_PY"'c["nova"]={"kind":"skill","source":"execution/skills/graphify","state":"candidate","installed":False,"activation":"contextual","evidence":{"dossier":None,"status":"absent"}}'"$_SAVE"

# O FURO QUE O PORTAO FINAL ACHOU: `quarantine` e o `initial_state` da policy e ficava FORA da
# contagem. Entrada gratuita usando o estado default, sem precisar levantar o teto.
mutante MCAP6 "capability nova em QUARANTINE tambem estoura o teto" 1 \
  "$_PY"'c["nova"]={"kind":"skill","source":"execution/skills/graphify","state":"quarantine","installed":False,"activation":"contextual","evidence":{"dossier":None,"status":"absent"}}'"$_SAVE"

mutante MCAP7 "capability em quarantine INSTALADA reprova" 1 \
  "$_PY"'c["graphify"]["state"]="quarantine"'"$_SAVE"

# ONDA 14. AS DUAS FUGAS DO TETO CONSTANTE, medidas por auditoria externa. `D_MAX` era numero
# literal DENTRO do arquivo que o PR edita, entao a proibicao de levanta-lo era prosa no objeto
# governado - `PolicyDeclared`, nao `PolicyEnforced`. Agora o criterio e o SHA-base.
mutante MCAP10 "capability nova + o PR levantando o proprio teto reprova" 1 \
  "$_PY"'
import os
os.makedirs("execution/skills/nova",exist_ok=True)
open("execution/skills/nova/SKILL.md","w").write("---\nname: nova\ndescription: x\n---\n")
c["nova"]={"kind":"skill","source":"execution/skills/nova","state":"candidate","installed":False,"activation":"contextual","evidence":{"dossier":None,"status":"absent"}}'"$_SAVE"

# A FUGA MAIS SUTIL: paga um dossie e adiciona outra sem dossie. O TAMANHO da divida nao muda
# (8 -> 8), entao qualquer regra baseada em contagem aprova. So a regra de SUBCONJUNTO pega.
mutante MCAP11 "trocar uma divida por outra reprova (tamanho constante nao basta)" 1 \
  "$_PY"'
import os
reqs=json.load(open("orchestration/skill-policy.json"))["lifecycle"]["promotion_requires"]
os.makedirs("evidence/skills",exist_ok=True)
open("evidence/skills/graphify.json","w").write(json.dumps({k:{"ok":True} for k in reqs}))
c["graphify"]["evidence"]={"dossier":"evidence/skills/graphify.json","status":"valid"}
os.makedirs("execution/skills/nova",exist_ok=True)
open("execution/skills/nova/SKILL.md","w").write("---\nname: nova\ndescription: x\n---\n")
c["nova"]={"kind":"skill","source":"execution/skills/nova","state":"candidate","installed":False,"activation":"contextual","evidence":{"dossier":None,"status":"absent"}}'"$_SAVE"

echo "== mutantes do par registry x manifesto =="
mutante MCAP8 "manifesto sem uma skill do registry reprova" 1 \
  'import pathlib
p=pathlib.Path("install/manifest.lock")
p.write_text("\n".join(l for l in p.read_text().splitlines() if "skills/forge" not in l)+"\n")'

# Este sobreviveu na primeira versao do portao, que comparava so o nome de destino.
mutante MCAP9 "manifesto com a ORIGEM do layout antigo reprova" 1 \
  'import pathlib
p=pathlib.Path("install/manifest.lock")
p.write_text(p.read_text().replace("\texecution/skills/forge\t","\texecution/skills/promoted/forge\t"))'

echo "== onda 15: vetor de evidencia, amplitude da claim e bijecao com o manifesto =="
mutante MCAP12 "confinamento declarado como sandbox com agentes de shell" 1 \
  "$_PY"'r["invariants"]["write_confinement"]="sandbox"
p.write_text(json.dumps(r,ensure_ascii=False,indent=2)+"\n")'
mutante MCAP13 "single_writer deixa de ser declarado como escalonamento" 1 \
  "$_PY"'del r["invariants"]["single_writer_is_scheduling_only"]
p.write_text(json.dumps(r,ensure_ascii=False,indent=2)+"\n")'
# MENCAO NAO E EXECUCAO - o achado que abriu a onda 15. `tests/unit/run.sh` cita quatro hooks
# dentro de um conjunto de classificacao estatica e nunca roda nenhum; creditar E_M por citacao
# reproduziria, DENTRO do instrumento, o defeito que o instrumento existe para medir.
mutante MCAP14 "E_M creditado a suite que apenas MENCIONA o hook" 1 \
  "$_PY"'c["lentes.sh"]["evidence"]["dimensions"]["E_M"]["ref"]="tests/unit/run.sh"
p.write_text(json.dumps(r,ensure_ascii=False,indent=2)+"\n")'
mutante MCAP15 "E_M creditado a suite inexistente" 1 \
  "$_PY"'c["verify-gate.sh"]["evidence"]["dimensions"]["E_M"]["ref"]="tests/unit/nao-existe.sh"
p.write_text(json.dumps(r,ensure_ascii=False,indent=2)+"\n")'
mutante MCAP16 "hook instalado sai do registry e some do instrumento" 1 \
  "$_PY"'del c["read-budget.sh"]
p.write_text(json.dumps(r,ensure_ascii=False,indent=2)+"\n")'
mutante MCAP17 "hook registrado com o kind de skill (obrigacao de prova errada)" 1 \
  "$_PY"'c["read-budget.sh"]["kind"]="skill"
p.write_text(json.dumps(r,ensure_ascii=False,indent=2)+"\n")'

echo "== onda 15: EvidenceValidity - o dossie tem data de validade =="
mutante MCAP18 "dossie valido, mas o ARTEFATO mudou depois: STALE, reprova" 1 \
  "$_PY$_DIG"'
dossie()
open("execution/skills/graphify/SKILL.md","a").write("\n<!-- mudanca posterior a avaliacao -->\n")
c["graphify"].update(state="promoted",evidence={"dossier":"evidence/skills/graphify.json","status":"valid"})'"$_SAVE"
mutante MCAP19 "dossie 7/7 SEM evaluated_with: nao ha como saber se ainda vale, reprova" 1 \
  "$_PY$_DIG"'
import json as _j2
d={k:{"ok":True} for k in reqs}
open("evidence/skills/graphify.json","w").write(_j2.dumps(d))
c["graphify"].update(state="promoted",evidence={"dossier":"evidence/skills/graphify.json","status":"valid"})'"$_SAVE"
mutante MCAP20 "dossie avaliado sob OUTRA policy: STALE, reprova" 1 \
  "$_PY$_DIG"'
dossie({"policy_digest":"0"*64})
c["graphify"].update(state="promoted",evidence={"dossier":"evidence/skills/graphify.json","status":"valid"})'"$_SAVE"

echo "== onda 15, segunda rodada: as regras que a revisao independente exigiu =="
# C1 - o `kind` e a chave de entrada na tabela de obrigacoes e mora no objeto governado.
# Reclassificar para um tipo que deve MENOS derrubava a divida com o portao verde.
mutante MCAP21 "hook_guidance reclassificado para hook_instrument (deve menos prova)" 1 \
  "$_PY"'c["lentes.sh"]["kind"]="hook_instrument"
c["lentes.sh"]["evidence"]["dimensions"]={"E_M":c["lentes.sh"]["evidence"]["dimensions"]["E_M"]}
p.write_text(json.dumps(r,ensure_ascii=False,indent=2)+"\n")'
# C2 - "a fonte ja existia na base" nao amarra a fonte ao ARTEFATO: o PR escolhe o caminho.
mutante MCAP22 "capability nova apontando para fonte preexistente fora da forma do tipo" 1 \
  "$_PY"'c["intruso"]={"kind":"agent","source":"README.md","state":"candidate",
  "installed":False,"activation":"delegated",
  "evidence":{"dossier":None,"status":"absent","dimensions":{k:{"status":"absent"} for k in ("E_M","E_U","E_C","E_S")}}}
p.write_text(json.dumps(r,ensure_ascii=False,indent=2)+"\n")'
mutante MCAP23 "duas capabilities compartilhando a mesma fonte" 1 \
  "$_PY"'c["clone-do-refutador"]=json.loads(json.dumps(c["refutador"]))
p.write_text(json.dumps(r,ensure_ascii=False,indent=2)+"\n")'
# C3 - confinamento declarado maior que o medido, com o rotulo `writes` esvaziando a condicao.
mutante MCAP24 "sandbox declarado depois de esvaziar a condicao via writes: true" 1 \
  "$_PY"'for a in r["agents"].values(): a["writes"]=True
r["invariants"]["write_confinement"]="sandbox"
p.write_text(json.dumps(r,ensure_ascii=False,indent=2)+"\n")'
# A2 - a policy declarava tres condicoes para `executed_suite` e o portao aplicava duas.
mutante MCAP25 "E_M creditado a suite que invoca o hook mas nao e executada pelo gerador" 1 \
  "$_PY"'import pathlib as _pl
_pl.Path("tests/unit/nao-enumerada.sh").write_text(
  "#!/usr/bin/env bash\nbash control/hooks/artifact-discipline.sh\n")
c["artifact-discipline.sh"]["evidence"]["dimensions"]["E_M"]["ref"]="tests/unit/nao-enumerada.sh"
p.write_text(json.dumps(r,ensure_ascii=False,indent=2)+"\n")'

echo "== onda 15, terceira rodada: o criterio do lado BASE vem da BASE =="
# F1 e F2 sao a MESMA familia da onda 14 (`D_MAX`) e da segunda rodada (`kind`): um insumo da
# comparacao vindo do HEAD e usado para julgar os dois lados. Os dois so sao exercitaveis com a
# base tendo policy, e no commit que a INTRODUZ ela nao tem - dai a base sintetica: commitar a
# arena e apontar `origin/main` para ela poe head e base em pe de igualdade, que e a condicao de
# todo commit a partir do proximo.
_BASE_SINTETICA=0
if git -C . rev-parse --git-dir >/dev/null 2>&1; then
  git -C . add -A >/dev/null 2>&1
  git -C . -c user.email=a@b -c user.name=arnes commit -q -m "base sintetica do arnes" >/dev/null 2>&1
  git -C . update-ref refs/remotes/origin/main HEAD >/dev/null 2>&1 && _BASE_SINTETICA=1
fi
if [ "$_BASE_SINTETICA" != 1 ]; then
  echo "  INAPLICAVEL MCAP26/MCAP27 - nao foi possivel criar base sintetica na arena"
  EXPECTED_MUTANTS=$((EXPECTED_MUTANTS-2))
else
  _POL="orchestration/evidence-policy.json"
  _bak_pol(){ cp "$_POL" "$_POL.bak"; }
  _rst_pol(){ mv -f "$_POL.bak" "$_POL"; }
  # MCAP26 - a tabela de obrigacoes esvaziada no head zera a divida.
  _bak_pol
  python3 -c 'import json,pathlib
p=pathlib.Path("orchestration/evidence-policy.json"); d=json.loads(p.read_text())
d["proof_obligations"]={k:[] for k in d["proof_obligations"]}
p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'
  python3 "$POR" >/dev/null 2>&1; _got=$?
  if [ "$_got" -eq 1 ]; then echo "  MORTO MCAP26 - proof_obligations esvaziado no head (exit=1)"; P=$((P+1))
  else echo "  SOBREVIVEU MCAP26 - proof_obligations esvaziado no head (exit=$_got, esperado=1)"; F=$((F+1)); fi
  _rst_pol
  # MCAP27 - retirar a enumeracao de uma suite do gerador tira o E_M no head e nao na base.
  cp scripts/status.sh scripts/status.sh.bak
  grep -v 'tests/unit/hooks-de-guarda.sh' scripts/status.sh.bak > scripts/status.sh
  python3 "$POR" >/dev/null 2>&1; _got=$?
  if [ "$_got" -eq 1 ]; then echo "  MORTO MCAP27 - suite deixa de ser enumerada pelo gerador (exit=1)"; P=$((P+1))
  else echo "  SOBREVIVEU MCAP27 - suite deixa de ser enumerada pelo gerador (exit=$_got, esperado=1)"; F=$((F+1)); fi
  mv -f scripts/status.sh.bak scripts/status.sh
fi

echo "== onda 27 (G104, issue #48): numero de aparencia medida e derivado, nao guardado =="
# CADA MUTANTE MUTA O ARTEFATO, NUNCA O PORTAO (cabecalho, linha 23). MCAP28 muta so o registry
# (coberto por _bak/_rst via `mutante`); MCAP29 muta TAMBEM a fonte, e por isso nao usa o helper.
mutante MCAP28 "valor obsoleto de measured_size_bytes volta a claude-md reprova" 1 \
  "$_PY"'c["claude-md"]["measured_size_bytes"]=18274'"$_SAVE"

# MCAP29 - o UNICO mutante que distingue "le a fonte" de "compara com um literal escondido no
# portao". Registra o valor CORRETO (st_size atual de execution/config/CLAUDE.md) no registry -
# CC7 deve aprovar nesse instante - e SO DEPOIS muda a fonte em 1 byte. `_bak`/`_rst` cobrem
# apenas REG e LOCK; a fonte mutada aqui nao esta coberta, entao usa cp/mv proprio, precedente
# exato em MCAP27 (scripts/status.sh.bak).
_CLAUDE_MD="execution/config/CLAUDE.md"
cp "$REG" "$REG.bak"
cp "$_CLAUDE_MD" "$_CLAUDE_MD.bak"
python3 -c "$_PY"'
import pathlib
c["claude-md"]["measured_size_bytes"] = pathlib.Path("execution/config/CLAUDE.md").stat().st_size'"$_SAVE"
printf '\n' >> "$_CLAUDE_MD"
python3 "$POR" >/dev/null 2>&1; _got=$?
if [ "$_got" -eq 1 ]; then echo "  MORTO MCAP29 - registry correto no instante da escrita, fonte muda depois (exit=1)"; P=$((P+1))
else echo "  SOBREVIVEU MCAP29 - registry correto no instante da escrita, fonte muda depois (exit=$_got, esperado=1)"; F=$((F+1)); fi
mv -f "$REG.bak" "$REG"
mv -f "$_CLAUDE_MD.bak" "$_CLAUDE_MD"

rm -rf evidence/skills execution/skills/nova tests/unit/nao-enumerada.sh 2>/dev/null
echo
echo "baseline=ok  mutantes_esperados=$EXPECTED_MUTANTS  mortos=$P  sobreviventes=$F"
if [ "$F" -eq 0 ] && [ "$P" -eq "$EXPECTED_MUTANTS" ]; then
  echo "================================================================"
  echo "mutacao verde: os $EXPECTED_MUTANTS mutantes se comportaram como o portao promete"
  exit 0
fi
echo "mutacao VERMELHA"
exit 1
