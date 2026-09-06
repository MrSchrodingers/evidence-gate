#!/usr/bin/env bash
# CAMADA DE QUALIDADE DE EVIDENCIA PARA LITERATURA - a suite do validador
# (evidence/validate-literature.py).
#
# O caso LT1 sozinho nao vale nada: um validador que aprovasse QUALQUER coisa passaria nele. O
# valor desta suite esta nos casos NEGATIVOS, cada um mutando UM campo do MOLDE (base.py) para
# que a reprovacao seja atribuivel aquele campo, nunca a um documento genericamente malformado
# - mesma disciplina de tests/unit/claims.sh.
#
# Os TRES requisitos da delegacao viram tres grupos de caso:
#   LT3-LT7   - campos obrigatorios presentes (raiz, study_quality, applicability, findings);
#   LT8-LT9   - inference_strength e provenance dentro dos vocabularios FECHADOS;
#   LT12-LT16 - toda afirmacao numerica com fonte declarada, pelos DOIS mecanismos do validador:
#               findings[].source (estrutural) e o marcador 'fonte'/'verificad' no resto do texto.
#
# PREFIXO 'LT' (Literatura Test), nao 'L': ate esta correcao os casos daqui usavam 'L1'..'L22',
# o MESMO prefixo que tests/unit/claims.sh ja usava em `main` para os SEUS proprios casos (L1..
# L18). O inventario de mutantes/regressoes de evidence/validate-claims.py e um SET PLANO por
# design (`inventario()`), entao os dois espacos colidiam - "L6" citado por uma claim resolveria
# para QUALQUER um dos dois casos, e o proprio validador declara os espacos "disjuntos de
# proposito". Nenhuma claim cita um ID 'L*' hoje (conferido), entao a colisao nunca produziu um
# falso-verde real, mas a garantia de resolucao nao-ambigua estava falsa. Renomeado o prefixo
# DESTE arquivo (o mais novo dos dois) em vez de qualificar o inventario por arquivo: qualificar
# exigiria mudar o FORMATO de citacao em evidence/claims/*.yaml (risco maior, nenhuma claim usa
# hoje) para resolver uma colisao que nunca foi citada; renomear e uma mudanca so de rotulo,
# confinada a este arquivo e a tests/mutation/literatura.sh, sem tocar o schema do ledger.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
V="$PWD/evidence/validate-literature.py"
REPO="$PWD"
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

# DEPENDENCIA DE ORACULO: sem pyyaml o validador nao decide nada, e "nao reprovou" seria
# indistinguivel de "nao foi verificado". Reprova a suite em vez de virar SKIP silencioso.
if ! python3 -c "import yaml" >/dev/null 2>&1; then
  echo "NAO VERIFICADO: pyyaml ausente - o validador sob teste nao pode operar." >&2
  exit 2
fi

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
val(){ python3 "$V" "$REPO" "$1" >/dev/null 2>&1; echo $?; }

# MOLDE: um documento MINIMO e VALIDO, reutilizado por todo caso negativo abaixo. Cada caso
# importa `doc()` e muda UM campo antes de gravar - se o molde sozinho nao validasse, nenhum
# caso negativo teria controle (foi exatamente a falta de controle que deixou LT2 de
# tests/unit/claims.sh medir o parser, nao o validador, na primeira versao daquele arquivo).
cat > "$T/base.py" <<'PY'
def doc():
    return {
        "literature_id": "arxiv-0000.00000",
        "citation": "Fixture, F. Fixture Paper for Testing. arXiv:0000.00000, 2026 preprint.",
        "identifier": "arXiv:0000.00000",
        "url": "https://arxiv.org/abs/0000.00000",
        "provenance": "preprint",
        "study_quality": {
            "benchmark": "fixture-bench",
            "n": "10 tarefas fixture (fonte: fixture)",
            "models": "modelo fixture",
            "scaffold": "scaffold fixture",
            "oracle": "verificador fixture",
            "baseline": "50.0% fixture (fonte: fixture)",
            "trials_repeated": "[nao verificado]",
            "uncertainty_reported": "[nao verificado]",
            "code_data_available": "[nao verificado]",
            "replicated": False,
        },
        "applicability": {
            "domain_similarity": "baixa",
            "scaffold_similarity": "baixa",
            "oracle_similarity": "media",
        },
        "inference_strength": "EXTRAPOLATED",
        "inference_rationale": "fixture sem numero solto - ver findings para o dado bruto",
        "findings": [
            {"metric": "fixture_metric", "value": "50%", "source": "fixture"},
        ],
        "limitations": ["fixture sem alcance real"],
    }
PY

echo "== LT1. a camada REAL de evidence/literature/ e valida =="
chk "evidence/literature/ valida" "$(val "$REPO/evidence/literature")" 0

echo "== LT2. o MOLDE, sozinho, e valido (controle geral dos negativos abaixo) =="
D="$T/l2"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
yaml.safe_dump(doc(), open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "molde sem mutacao passa" "$(val "$D")" 0

echo "== LT3. campo obrigatorio de raiz ausente reprova =="
D="$T/l3"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); del d["citation"]
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "'citation' ausente -> reprova" "$(val "$D")" 1

echo "== LT4. literature_id fora do padrao reprova; controle: id valido passa =="
D="$T/l4"; mkdir -p "$D"
python3 - "$D/BAD ID.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); d["literature_id"] = "BAD ID"
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "literature_id com maiuscula/espaco -> reprova" "$(val "$D")" 1
D="$T/l4b"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
yaml.safe_dump(doc(), open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "  o MESMO molde com id valido passa" "$(val "$T/l4b")" 0

echo "== LT5. nome do arquivo que nao bate com literature_id reprova =="
D="$T/l5"; mkdir -p "$D"
python3 - "$D/nome-errado.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
yaml.safe_dump(doc(), open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "arquivo 'nome-errado.yaml' com literature_id 'arxiv-0000.00000' -> reprova" "$(val "$D")" 1

echo "== LT6. literature_id duplicado entre dois arquivos reprova, com a violacao NOMEADA =="
# SOBREDETERMINACAO ESTRUTURAL, nao so desta fixture: se dois arquivos no MESMO diretorio
# declaram o MESMO literature_id, o nome de arquivo de cada um so pode casar com o proprio id
# (regra de LT5) se os dois arquivos tiverem o MESMO nome - impossivel no mesmo diretorio (o
# sistema de arquivos nao aceita dois arquivos com nomes identicos). Logo, TODO fixture de
# duplicidade dispara tambem a violacao de nome de arquivo em pelo menos um dos dois documentos
# - nao ha como construir um caso onde SO a duplicidade falhe. Um caso que afira apenas o exit
# code (!=0) e por isso estruturalmente incapaz de discriminar um mutante que remova a guarda de
# duplicidade: o exit code continua 1, vindo so da violacao de nome. Por isso este caso confere
# tambem a MENSAGEM (mesma tecnica de F2/F3/F5 de tests/unit/schedule.sh): a palavra 'duplicado'
# tem de aparecer na saida, o que so acontece se a guarda de duplicidade de fato executou.
D="$T/l6"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
yaml.safe_dump(doc(), open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
python3 - "$D/arxiv-0000.00001.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc()
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
OUT6="$(python3 "$V" "$REPO" "$D" 2>&1)"; RC6=$?
chk "dois arquivos com o mesmo literature_id -> reprova" "$RC6" 1
printf '%s' "$OUT6" | grep -qF "duplicado"
chk "  a violacao de duplicidade e NOMEADA na mensagem (nao so o mismatch de nome de arquivo)" $? 0

echo "== LT7. findings vazio reprova; study_quality/applicability incompletos reprovam =="
D="$T/l7a"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); d["findings"] = []
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "findings=[] -> reprova" "$(val "$D")" 1
D="$T/l7b"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); del d["study_quality"]["oracle"]
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "study_quality.oracle ausente -> reprova" "$(val "$D")" 1
D="$T/l7c"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); del d["applicability"]["oracle_similarity"]
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "applicability.oracle_similarity ausente -> reprova" "$(val "$D")" 1
D="$T/l7d"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); d["limitations"] = []
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "limitations=[] -> reprova" "$(val "$D")" 1

echo "== LT8. inference_strength fora do vocabulario fechado reprova; controle: valor valido passa =="
D="$T/l8"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); d["inference_strength"] = "PROBABLY"
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "inference_strength='PROBABLY' -> reprova" "$(val "$D")" 1
D="$T/l8b"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); d["inference_strength"] = "DIRECT"
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "  'DIRECT' (no vocabulario fechado) passa" "$(val "$T/l8b")" 0

echo "== LT9. provenance fora do vocabulario fechado reprova; controle: valor valido passa =="
D="$T/l9"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); d["provenance"] = "trust_me_bro"
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "provenance='trust_me_bro' -> reprova" "$(val "$D")" 1
D="$T/l9b"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); d["provenance"] = "peer_reviewed"
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "  'peer_reviewed' (no vocabulario fechado) passa" "$(val "$T/l9b")" 0

echo "== LT10. findings[].metric fora de snake_case reprova =="
D="$T/l10"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); d["findings"][0]["metric"] = "Not Snake Case"
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "metric='Not Snake Case' -> reprova" "$(val "$D")" 1

echo "== LT11. findings[] sem 'source' reprova - o campo estrutural E a fonte declarada =="
D="$T/l11"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); del d["findings"][0]["source"]
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "findings[0] sem 'source' -> reprova" "$(val "$D")" 1

echo "== LT12. numero solto em inference_rationale SEM marcador de fonte reprova =="
# ESTE E O CASO CENTRAL DO TERCEIRO REQUISITO DA DELEGACAO: "toda afirmacao numerica com fonte
# declarada". Um numero podia entrar pela prosa argumentativa sem nunca passar por findings -
# foi exatamente a rota do defeito original da secao 6.1 do README (ver docstring do validador).
D="$T/l12"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); d["inference_rationale"] = "o estudo mostra um ganho de 47 por cento sem contexto"
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "'47 por cento' solto, sem marcador -> reprova" "$(val "$D")" 1
D="$T/l12b"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc()
d["inference_rationale"] = "ganho de 47 por cento (fonte: findings acima)"
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "  o MESMO numero com marcador 'fonte' no texto passa" "$(val "$T/l12b")" 0

echo "== LT13. numero solto em limitations[] SEM marcador de fonte reprova =="
D="$T/l13"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); d["limitations"] = ["so 12 instancias foram observadas"]
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "'12 instancias' solto, sem marcador -> reprova" "$(val "$D")" 1

echo "== LT14. numero solto em study_quality.* SEM marcador de fonte reprova =="
D="$T/l14"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); d["study_quality"]["baseline"] = "91 por cento sem marcador nenhum aqui"
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "study_quality.baseline com numero sem marcador -> reprova" "$(val "$D")" 1

echo "== LT15. numero DENTRO de findings[].value NAO exige o marcador de texto =="
# A fonte de um numero em findings[] e o campo estrutural 'source' (LT11 ja cobre a ausencia
# dele). Exigir TAMBEM o marcador textual dentro de findings seria redundante e obrigaria
# prosa artificial em todo 'value' - o desenho deste validador separa os dois mecanismos por
# regiao do documento (ver docstring: 3a cobre findings, 3b cobre o resto).
D="$T/l15"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc()
d["findings"][0]["value"] = "39/49 sem a palavra-marcador"
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "findings[].value com numero e SEM marcador de texto ainda passa (source cobre)" "$(val "$D")" 0

echo "== LT16. numero em campo BIBLIOGRAFICO (citation/identifier/url/cited_in) nao exige marcador =="
# citation/identifier/url/cited_in sao ENDERECO (onde o paper esta, onde e citado), nao
# afirmacao empirica sobre o que o paper mediu - por isso ficam fora da varredura 3b.
D="$T/l16"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc()
# NAO usa caminho: desde a onda 25e `cited_in` que COMECA com um caminho de arquivo tem de
# resolver e mencionar a entrada (BD16). Este caso mede outra coisa - que DIGITO em campo
# bibliografico nao exige marcador de fonte -, e um caminho ficticio aqui faria o caso
# reprovar pela regra errada, medindo BD16 em vez de LT16.
d["cited_in"] = ["ADR 0099 (fixture, referencia sem caminho)"]
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "cited_in com digito (numero de ADR) sem marcador ainda passa" "$(val "$D")" 0

echo "== LT17. diretorio de literatura inexistente e NAO VERIFICADO (exit 2), nao aprovacao =="
chk "diretorio ausente -> exit 2" "$(python3 "$V" "$REPO" "$T/nao-existe" >/dev/null 2>&1; echo $?)" 2

echo "== LT18. diretorio de literatura VAZIO (sem yaml) e NAO VERIFICADO (exit 2) =="
D="$T/l18-vazio"; mkdir -p "$D"
chk "diretorio sem entradas -> exit 2" "$(python3 "$V" "$REPO" "$D" >/dev/null 2>&1; echo $?)" 2

echo "== LT19. pyyaml ausente e NAO VERIFICADO (exit 2), nao aprovacao =="
# Mesma tecnica usada em tests/unit/claims.sh L9: um modulo que lanca ImportError precede o
# real no PYTHONPATH.
SB="$T/sabotagem"; mkdir -p "$SB"; printf 'raise ImportError("indisponivel por fixture")\n' > "$SB/yaml.py"
rc=$(PYTHONPATH="$SB" python3 "$V" "$REPO" "$REPO/evidence/literature" >/dev/null 2>&1; echo $?)
chk "sem parser, o validador declara NAO VERIFICADO" "$rc" 2

echo "== LT20. YAML sintaticamente invalido reprova, nao trava a suite inteira =="
D="$T/l20"; mkdir -p "$D"
printf 'literature_id: [nao fecha\n' > "$D/arxiv-0000.00000.yaml"
chk "YAML quebrado -> reprova (nao exit 0, nao crash)" "$(val "$D")" 1

echo "== LT21. CONTRADICAO INTERNA: citacao retratada numa secao reaparece verbatim noutra =="
# ESCOPO DECLARADO (ver evidence/validate-literature.py, docstring, secao de LIMITES): este
# caso cobre so reaparicao LITERAL da string retratada. Nao existe, neste validador, deteccao
# de PARAFRASE (a mesma alegacao reescrita com outras palavras) - isso exigiria compreensao de
# linguagem que uma varredura de string nao tem como fazer honestamente. O mutante abaixo e
# construido para o que o mecanismo REALMENTE cobre: a mesma citacao entre aspas, retratada num
# campo ("... NAO existe no texto ...") e repetida verbatim, sem retratacao, noutro campo.
D="$T/l21"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc()
d["study_quality"]["scaffold"] = (
    'A frase "does not evaluate alternative agent frameworks" NAO existe no texto completo - '
    'era citacao inventada (fonte: verificado nesta sessao).'
)
d["limitations"] = [
    'O artigo declara "does not evaluate alternative agent frameworks" como limite central.'
]
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
OUT21="$(python3 "$V" "$REPO" "$D" 2>&1)"; RC21=$?
chk "citacao retratada reaparece verbatim em limitations -> reprova" "$RC21" 1
printf '%s' "$OUT21" | grep -qF "contradicao interna"
chk "  a violacao e NOMEADA como contradicao interna (nao generica)" $? 0

echo "== LT22. controle de LT21: a MESMA retratacao, SEM a citacao reaparecer alhures, passa =="
D="$T/l22"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc()
d["study_quality"]["scaffold"] = (
    'A frase "does not evaluate alternative agent frameworks" NAO existe no texto completo - '
    'era citacao inventada (fonte: verificado nesta sessao).'
)
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "  retratacao isolada, sem reaparicao verbatim, passa (controle de LT21)" "$(val "$D")" 0

echo "== LT23-LT26. REGRESSAO: FP e FN medidos por revisao independente em REGRA 5 =="
# Par controlado, formato exigido pela delegacao: reproduz a FORMA REAL do campo `citation` de
# arxiv-2602.06547.yaml (titulo CORRETO citado numa frase, titulo INCORRETO retratado na frase
# seguinte, marcador "nao existe na" colado no titulo incorreto) e prova as duas pontas:
#   LT23 - o titulo CORRETO, reusado alhures como fato legitimo, PASSA (era o falso positivo:
#         antes da janela de proximidade, QUALQUER aspa do campo `citation` virava "retratada").
#   LT24 - controle: o titulo FABRICADO (o que de fato esta retratado), reusado alhures como
#         fato, continua REPROVANDO - prova que a correcao nao apagou a deteccao real.
#   LT25 - o mesmo reuso do titulo fabricado, mas dentro de uma frase que contem a palavra
#         "inventario" (raiz "invent-", sem relacao com fabricacao) REPROVA - era o falso
#         negativo: o marcador antigo (`\binvent\w*`, sem fronteira de palavra) casava
#         "inventario" e o campo inteiro virava isento, calando a reafirmacao.
#   LT26 - controle par de LT25: a MESMA frase com "resumo" no lugar de "inventario" - mesmo
#         veredito (reprova). O par LT25/LT26 prova que uma palavra IRRELEVANTE nao muda mais o
#         resultado (antes: INVENTARIO->passa/calava, RESUMO->reprova/pegava - a mesma
#         fabricacao, dois vereditos, so pela presenca acidental de uma raiz de palavra).
D="$T/l23base"; mkdir -p "$D"
cat > "$T/l23_citation.py" <<'PY'
CITATION = (
    'Fixture, F. "Correct Fixture Title About Testing Methodology" : A Study. '
    'arXiv:0000.00000, 2026 preprint. Titulo conferido nesta sessao contra a fonte primaria, '
    'texto completo lido do zero - o titulo usado antes desta correcao '
    '("Fabricated Fixture Title Nobody Wrote") nao existe na fonte.'
)
CORRETO = "Correct Fixture Title About Testing Methodology"
FABRICADO = "Fabricated Fixture Title Nobody Wrote"
PY

D="$T/l23"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
from l23_citation import CITATION, CORRETO
d = doc()
d["citation"] = CITATION
d["limitations"] = [f'O titulo real do estudo, "{CORRETO}", descreve o achado central.']
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "LT23 titulo CORRETO reusado em limitations -> passa (fix do falso positivo)" "$(val "$D")" 0

D="$T/l24"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
from l23_citation import CITATION, FABRICADO
d = doc()
d["citation"] = CITATION
d["limitations"] = [
    f'O estudo descreve seu achado central como "{FABRICADO}", conforme o resumo original.'
]
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "  LT24 controle: titulo FABRICADO reusado como fato -> reprova (deteccao real preservada)" "$(val "$D")" 1

D="$T/l25"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
from l23_citation import CITATION, FABRICADO
d = doc()
d["citation"] = CITATION
d["limitations"] = [f'Ver o inventario deste estudo, "{FABRICADO}", para a metodologia completa.']
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "LT25 'inventario' (raiz invent- irrelevante) nao desliga mais a deteccao -> reprova" "$(val "$D")" 1

D="$T/l26"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
from l23_citation import CITATION, FABRICADO
d = doc()
d["citation"] = CITATION
d["limitations"] = [f'Ver o resumo deste estudo, "{FABRICADO}", para a metodologia completa.']
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "  LT26 par de LT25 ('resumo' no lugar de 'inventario') -> mesmo veredito (reprova)" "$(val "$D")" 1

echo "== LT27-LT28. REGRESSAO (D8): par controlado por COMPRIMENTO da aspa colada ao marcador =="
# ONDA 5, D8 (CRITICO). Falso negativo ESTRUTURAL: JANELA_RETRATACAO (100) limitava a
# PROXIMIDADE corretamente, mas RE_ASPAS aceita aspas de ate 300 caracteres, e o casamento antigo
# exigia que o SPAN INTEIRO coubesse na janela ao redor do marcador - uma aspa longa colada ao
# marcador (gap de poucos caracteres, a MESMA proximidade da citacao fabricada real) escapava so
# por nao COUBER, nunca por estar longe. Medido antes do fix: aspa de 96 caracteres colada ao
# marcador detectava; 97+ escapava - alcancavel no corpus real (arxiv-2603.15401.yaml,
# study_quality.scaffold, aspa de 223 chars). Par controlado: LT27 (aspa curta) e LT28 (aspa
# longa) usam o MESMO gap ate o marcador - so o comprimento muda; as DUAS tem de reprovar.
fixture_d8(){ # $1=destino  $2=comprimento da aspa fabricada, colada ao marcador
python3 - "$T" "$1" "$2" <<'PY'
import sys, yaml
sys.path.insert(0, sys.argv[1])
from base import doc
dest, n = sys.argv[2], int(sys.argv[3])
fabricado = "Z" * n
d = doc()
d["citation"] = (
    'Fixture, F. "Correct Fixture Title" : A Study. arXiv:0000.00000, 2026 preprint. '
    'O titulo usado antes desta correcao ("' + fabricado + '") nao existe na fonte.'
)
d["limitations"] = [
    'O estudo descreve seu achado central como "' + fabricado + '", conforme o resumo original.'
]
yaml.safe_dump(d, open(dest, "w"), allow_unicode=True, sort_keys=False)
PY
}
D="$T/lt27"; mkdir -p "$D"; fixture_d8 "$D/arxiv-0000.00000.yaml" 20
chk "LT27 aspa CURTA (20 chars) colada ao marcador, reusada alhures -> reprova" "$(val "$D")" 1
D="$T/lt28"; mkdir -p "$D"; fixture_d8 "$D/arxiv-0000.00000.yaml" 150
chk "  LT28 par: aspa LONGA (150 chars, MESMO gap do marcador) tambem reprova (fix do falso negativo)" "$(val "$D")" 1

echo "== LT29. D8, caso do CORPUS REAL: aspa legitima de 223 chars segue NAO retratada =="
# arxiv-2603.15401.yaml, study_quality.scaffold, tem uma aspa REAL de 223 caracteres a 113 do
# marcador de retratacao mais proximo - fora da janela de 100 por DISTANCIA (nao mais por
# comprimento, ver D8 acima). Prova que o fix nao troca o falso negativo por um falso positivo:
# uma aspa longa e GENUINA, fora da janela, continua nao contando como retratada.
RES29="$(python3 - <<'PY'
import sys, yaml, importlib
sys.path.insert(0, "evidence")
vl = importlib.import_module("validate-literature")
doc = yaml.safe_load(open("evidence/literature/arxiv-2603.15401.yaml"))
scaffold = doc["study_quality"]["scaffold"]
retratadas = vl._citacoes_retratadas(scaffold)
alvo = next(m.group(1) for m in vl.RE_ASPAS.finditer(scaffold) if len(m.group(1)) > 200)
norm = " ".join(alvo.split()).lower()
print("sim" if norm not in retratadas else "nao")
PY
)"
chk "aspa real de 223 chars (fora da janela por DISTANCIA) segue NAO retratada" "$RES29" "sim"

echo "== BD. BUSCA DELIMITADA: NaoEncontrado(consultas, fontes, data) precisa das TRES partes =="
# POR QUE ESTA SECAO EXISTE. `tests/unit/governance-links.py` obriga toda afirmacao de ausencia
# na literatura a citar `[busca:<id>]` e verifica que o id RESOLVE para um arquivo - sem nunca
# LER o arquivo. Medido nesta arvore antes desta mudanca: a unica busca registrada, BL-0001,
# declarava `sources: [ledger interno evidence/literature/]`. Uma busca que consultou apenas o
# proprio repositorio nao pode encontrar nada que o corpus ja nao contivesse; ela absolvia a
# claim sem observar a literatura. A regra dura desta camada e FONTE EXTERNA, e os casos abaixo
# existem para que ela nao possa ser afrouxada em silencio.
#
# CONTROLE POSITIVO PRIMEIRO (BD1): sem ele, todo negativo seria indistinguivel de "o validador
# reprova qualquer coisa" - a mesma falha que LT2 corrigiu para a camada de literatura.
cat > "$T/busca.py" <<'PY'
def busca():
    return {
        "claim_id": "BL-0001",
        "question": "Existe trabalho que meca X?",
        "searched_at": "DATA_HOJE",
        "searched_by": "fixture",
        "sources": ["https://arxiv.org/list/cs.SE/recent", "ledger interno evidence/literature/"],
        "queries": ["false success", "self-reported success"],
        "result": {"matching_studies": 0, "matches": []},
    }
PY
sed -i "s/DATA_HOJE/$(date +%F)/" "$T/busca.py"
# helper: grava o molde de literatura VALIDO (para a camada de literatura nao ser a causa) mais
# UMA busca, no diretorio dado.
bd_lit(){ python3 - "$1/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
yaml.safe_dump(doc(), open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
}

D="$T/bd1"; mkdir -p "$D/searches"; bd_lit "$D"
python3 - "$D/searches/BL-0001-fixture.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from busca import busca
yaml.safe_dump(busca(), open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "BD1 CONTROLE: busca com fonte externa, consultas e data valida passa" "$(val "$D")" 0

# BD2 e o caso motivador, reproduzido: a busca REAL que existia nesta arvore.
D="$T/bd2"; mkdir -p "$D/searches"; bd_lit "$D"
python3 - "$D/searches/BL-0001-fixture.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from busca import busca
b = busca(); b["sources"] = ["ledger interno evidence/literature/"]
yaml.safe_dump(b, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "BD2 so fonte INTERNA (o caso real de BL-0001) -> reprova" "$(val "$D")" 1

# BD3: a marca interna tem PRECEDENCIA sobre o nome da base. Sem esta regra, a string
# 'ledger interno evidence/literature/arxiv-2606.09863.yaml' passaria por conter 'arxiv'.
D="$T/bd3"; mkdir -p "$D/searches"; bd_lit "$D"
python3 - "$D/searches/BL-0001-fixture.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from busca import busca
b = busca(); b["sources"] = ["ledger interno evidence/literature/arxiv-2606.09863.yaml"]
yaml.safe_dump(b, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "BD3 caminho INTERNO que contem 'arxiv' NAO vira fonte externa" "$(val "$D")" 1

# BD4: base externa NOMEADA, sem URL - caso legitimo de base com interface propria.
D="$T/bd4"; mkdir -p "$D/searches"; bd_lit "$D"
python3 - "$D/searches/BL-0001-fixture.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from busca import busca
b = busca(); b["sources"] = ["ACM Digital Library (consulta pela interface web)"]
yaml.safe_dump(b, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "BD4 CONTROLE: base externa nomeada sem URL passa" "$(val "$D")" 0

D="$T/bd5"; mkdir -p "$D/searches"; bd_lit "$D"
python3 - "$D/searches/BL-0001-fixture.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from busca import busca
b = busca(); b["queries"] = []
yaml.safe_dump(b, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "BD5 queries VAZIA (ausencia sem dizer o que procurou) -> reprova" "$(val "$D")" 1

D="$T/bd6"; mkdir -p "$D/searches"; bd_lit "$D"
python3 - "$D/searches/BL-0001-fixture.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from busca import busca
b = busca(); del b["searched_by"]
yaml.safe_dump(b, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "BD6 campo obrigatorio ausente -> reprova" "$(val "$D")" 1

D="$T/bd7"; mkdir -p "$D/searches"; bd_lit "$D"
python3 - "$D/searches/BL-0001-fixture.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from busca import busca
b = busca(); b["searched_at"] = "agosto de 2026"
yaml.safe_dump(b, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "BD7 searched_at em prosa (nao ISO) -> reprova" "$(val "$D")" 1

# BD8: data no FUTURO tornaria a idade negativa e o envelhecimento inerte - o mesmo modo de
# falha que o portao ja trata para relogio torto (A2 do revisor, em verify-gate.sh).
D="$T/bd8"; mkdir -p "$D/searches"; bd_lit "$D"
python3 - "$D/searches/BL-0001-fixture.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from busca import busca
b = busca(); b["searched_at"] = "$(date -d '+3 days' +%F)"
yaml.safe_dump(b, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "BD8 searched_at no FUTURO -> reprova" "$(val "$D")" 1

D="$T/bd9"; mkdir -p "$D/searches"; bd_lit "$D"
python3 - "$D/searches/BL-0001-fixture.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from busca import busca
b = busca(); b["searched_at"] = "$(date -d '-800 days' +%F)"
yaml.safe_dump(b, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "BD9 busca FOSSILIZADA (800 dias > limite 730) -> reprova" "$(val "$D")" 1
D="$T/bd9b"; mkdir -p "$D/searches"; bd_lit "$D"
python3 - "$D/searches/BL-0001-fixture.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from busca import busca
b = busca(); b["searched_at"] = "$(date -d '-700 days' +%F)"
yaml.safe_dump(b, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "  CONTROLE: 700 dias (dentro do limite) passa" "$(val "$T/bd9b")" 0

D="$T/bd10"; mkdir -p "$D/searches"; bd_lit "$D"
python3 - "$D/searches/BL-0001-fixture.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from busca import busca
b = busca(); b["result"] = {"matching_studies": 0, "matches": [{"id": "arXiv:0000.00000"}]}
yaml.safe_dump(b, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "BD10 matching_studies=0 com 1 match listado (contradicao interna) -> reprova" "$(val "$D")" 1

# BD11: "nao encontrei nada" e RESULTADO VALIDO. A camada nao pode punir o zero honesto - se
# punisse, empurraria quem registra a busca a inventar match.
D="$T/bd11"; mkdir -p "$D/searches"; bd_lit "$D"
python3 - "$D/searches/BL-0001-fixture.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from busca import busca
b = busca(); b["result"] = {"matching_studies": 0, "matches": []}
yaml.safe_dump(b, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "BD11 CONTROLE: zero achados, honestamente declarado, passa" "$(val "$D")" 0

D="$T/bd12"; mkdir -p "$D/searches"; bd_lit "$D"
python3 - "$D/searches/BL-9999-fixture.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from busca import busca
yaml.safe_dump(busca(), open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "BD12 nome do arquivo nao casa com claim_id -> reprova" "$(val "$D")" 1

D="$T/bd13"; mkdir -p "$D/searches"; bd_lit "$D"
for _n in BL-0001-a BL-0001-b; do
python3 - "$D/searches/$_n.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from busca import busca
yaml.safe_dump(busca(), open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
done
chk "BD13 claim_id duplicado em dois arquivos -> reprova" "$(val "$D")" 1

# BD14: diretorio AUSENTE nao e violacao (corpus sintetico nao tem a camada), mas o relatorio
# precisa DIZER que nao verificou - senao "nao violou" vira indistinguivel de "verificado", que
# e exatamente a confusao que este repositorio existe para impedir.
D="$T/bd14"; mkdir -p "$D"; bd_lit "$D"
chk "BD14 sem diretorio de buscas: nao reprova..." "$(val "$D")" 0
chk "  ...mas DECLARA que a camada nao foi verificada" \
    "$(python3 "$V" "$REPO" "$D" 2>&1 | grep -c 'NAO VERIFICADA')" 1

# BD15: `matches[].ledger` tem de RESOLVER. Sem esta regra a busca cita um ledger que nunca foi
# escrito e o `NaoEncontrado` aponta para o vazio - foi exatamente o que aconteceu ao redigir
# BL-0002 nesta arvore: duas entradas foram citadas antes de existirem e o validador aprovou.
D="$T/bd15"; mkdir -p "$D/searches"; bd_lit "$D"
python3 - "$D/searches/BL-0001-fixture.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from busca import busca
b = busca()
b["result"] = {"matching_studies": 1,
               "matches": [{"id": "x", "ledger": "evidence/literature/nao-existe-jamais.yaml"}]}
yaml.safe_dump(b, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "BD15 match citando ledger INEXISTENTE -> reprova" "$(val "$D")" 1
D="$T/bd15b"; mkdir -p "$D/searches"; bd_lit "$D"
python3 - "$D/searches/BL-0001-fixture.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from busca import busca
b = busca()
b["result"] = {"matching_studies": 1,
               "matches": [{"id": "x", "ledger": "evidence/validate-literature.py"}]}
yaml.safe_dump(b, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "  CONTROLE: ledger que RESOLVE passa" "$(val "$T/bd15b")" 0

# BD16: `cited_in` afirma ONDE a entrada e citada, e a afirmacao tem de ser verdadeira. MEDIDO
# nesta arvore: sete referencias falsas, entre elas uma entrada declarando ser citada por
# `execution/agents/refutador.md` quando aquele agente nao a menciona em lugar nenhum. O campo
# estava em CAMPOS_BIBLIOGRAFICOS e por isso escapava de toda varredura - era prosa que ninguem
# conferia.
D="$T/bd16"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); d["cited_in"] = ["docs/adr/nao-existe-jamais.md"]
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "BD16 cited_in para arquivo INEXISTENTE -> reprova" "$(val "$D")" 1
D="$T/bd16b"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); d["cited_in"] = ["evidence/validate-literature.py"]   # existe, mas nao cita o id
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "  arquivo existe mas NAO menciona a entrada -> reprova" "$(val "$D")" 1
D="$T/bd16c"; mkdir -p "$D"
python3 - "$D/arxiv-2603.15401.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc()
d["literature_id"] = "arxiv-2603.15401"
d["identifier"] = "arXiv:2603.15401"
d["cited_in"] = ["docs/method/CONHECIMENTO.md"]   # cita de verdade
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "  CONTROLE: arquivo que MENCIONA a entrada passa" "$(val "$T/bd16c")" 0
D="$T/bd16d"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); d["cited_in"] = ["conversa com o operador", "https://exemplo.invalido/x"]
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "  CONTROLE: texto livre e URL nao sao tratados como caminho" "$(val "$T/bd16d")" 0

# BD17-BD26: os RAMOS DE ENTRADA MALFORMADA da camada de busca. Sem eles a camada nova derruba a
# cobertura de decisao do arquivo (medido: 92,3% -> 88,78%, ABAIXO DO PISO), e piso furado por
# codigo novo e exatamente a regressao silenciosa que `evidence/cobertura.sh` existe para barrar.
# Cada caso exercita UM ramo de recusa; o valor esta em o validador nao ESTOURAR nem APROVAR
# diante de documento torto - as duas falhas sao piores que reprovar.
bd_busca(){ # $1=subdir  $2=mutacao python sobre `b`
  local D="$T/$1"; mkdir -p "$D/searches"; bd_lit "$D"
  python3 - "$D/searches/BL-0001-fixture.yaml" "$2" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from busca import busca
b = busca()
exec(sys.argv[2])
yaml.safe_dump(b, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
  printf '%s' "$D"
}
D="$(bd_busca bd17 'b["question"]="   "')"
chk "BD17 question em branco -> reprova" "$(val "$D")" 1
D="$(bd_busca bd18 'b["searched_by"]=""')"
chk "BD18 searched_by vazio -> reprova" "$(val "$D")" 1
D="$(bd_busca bd19 'b["queries"]=["a",""]')"
chk "BD19 queries com entrada VAZIA -> reprova" "$(val "$D")" 1
D="$(bd_busca bd20 'b["sources"]="nao e lista"')"
chk "BD20 sources que nao e lista -> reprova" "$(val "$D")" 1
D="$(bd_busca bd21 'b["result"]="nao e mapa"')"
chk "BD21 result que nao e mapa -> reprova" "$(val "$D")" 1
D="$(bd_busca bd22 'b["result"]={"matches":[]}')"
chk "BD22 result sem matching_studies -> reprova" "$(val "$D")" 1
D="$(bd_busca bd23 'b["result"]={"matching_studies":-1,"matches":[]}')"
chk "BD23 matching_studies negativo -> reprova" "$(val "$D")" 1
D="$(bd_busca bd24 'b["result"]={"matching_studies":True,"matches":[]}')"
chk "BD24 matching_studies booleano (True nao e contagem) -> reprova" "$(val "$D")" 1
D="$(bd_busca bd25 'b["result"]={"matching_studies":1,"matches":"nao e lista"}')"
chk "BD25 matches que nao e lista -> reprova" "$(val "$D")" 1
D="$(bd_busca bd26 'b["searched_at"]="2026-13-45"')"
chk "BD26 data ISO com mes/dia impossiveis -> reprova" "$(val "$D")" 1
# BD27: matches[] com entrada que nao e mapa - o laco de resolucao tem de PULAR, nao estourar.
D="$(bd_busca bd27 'b["result"]={"matching_studies":1,"matches":["string solta"]}')"
chk "BD27 CONTROLE: matches[] nao-mapa nao derruba o validador" "$(val "$D")" 0
# BD28: raiz do documento que nao e mapa.
D="$T/bd28"; mkdir -p "$D/searches"; bd_lit "$D"
printf -- "- isto e uma lista, nao um mapa\n" > "$D/searches/BL-0001-fixture.yaml"
chk "BD28 raiz da busca que nao e mapa -> reprova" "$(val "$D")" 1
# BD29: YAML sintaticamente invalido no diretorio de buscas.
D="$T/bd29"; mkdir -p "$D/searches"; bd_lit "$D"
printf 'claim_id: [nao fecha\n' > "$D/searches/BL-0001-fixture.yaml"
chk "BD29 YAML invalido em searches/ -> reprova (nao estoura)" "$(val "$D")" 1
# BD30: diretorio de buscas EXISTE mas esta vazio - nao e violacao, e NAO VERIFICADO declarado.
D="$T/bd30"; mkdir -p "$D/searches"; bd_lit "$D"
chk "BD30 diretorio de buscas vazio: nao reprova..." "$(val "$D")" 0
chk "  ...e DECLARA que a camada nao foi verificada" \
    "$(python3 "$V" "$REPO" "$D" 2>&1 | grep -c 'NAO VERIFICADA')" 1
# BD31: cited_in com caminho SEM barra nao e tratado como caminho do repositorio.
D="$T/bd31"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); d["cited_in"] = ["README.md"]
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "BD31 CONTROLE: cited_in sem diretorio nao e caminho deste repo" "$(val "$D")" 0

echo
echo "================ PASS=$P  FAIL=$F ================"
EXPECTED=76
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
[ "$F" -eq 0 ] && echo "camada de literatura verde ($P/$EXPECTED)" || echo "camada de literatura VERMELHA"
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
