#!/usr/bin/env bash
# Mede USO REAL de skill a partir dos transcripts, para decidir criacao e depreciacao por
# evidencia em vez de intuicao.
#
# ARMADILHA QUE ESTE SCRIPT EXISTE PARA EVITAR - ja custou uma decisao errada:
# skill tem DOIS canais de invocacao, e eles aparecem de formas DIFERENTES no transcript:
#   1. modelo invoca  -> `tool_use` com name="Skill" e input.skill
#   2. usuario digita -> marcador estrutural `<command-name>/nome</command-name>`
# Consultar so o canal 1 leva a concluir "nunca usada" sobre uma skill usada toda semana.
# Aconteceu: `defesa-de-tese` tinha 0 no canal 1 e invocacoes no canal 2, e foi arquivada por
# engano.
#
# SEGUNDO DEFEITO, SIMETRICO AO PRIMEIRO (issue #53) - a propria correcao anterior trocou um
# proxy ruim por outro, e cada proxy errou para um lado:
#   (a) SUBTRACAO: excluir as cegas TODO transcript de subagente descarta o canal 1 - que E
#       estrutural e ocorre majoritariamente dentro de subagente, a populacao onde o modelo
#       decide sozinho. Correcao: varrer os DOIS planos e DECLARAR o recorte, nunca descartar.
#   (b) ADICAO: casar `/nome` em texto livre de QUALQUER registro (documento colado, eco de
#       ferramenta, prompt de delegacao) conta como "uso". Correcao: o canal 2 real exige o
#       marcador estrutural `<command-name>...</command-name>`; o regex solto sobre texto livre
#       vira sinal FRACO ('mencao'), e NUNCA soma no total de uso.
#   (c) VEREDITO SEM DENOMINADOR: "zero uso" nao e "prova de inutilidade" sem saber se havia
#       oportunidade de uso. Sem estimar essa oportunidade, o script declara o estado como
#       NAO RESOLVIDO em vez de propor depreciacao.
#   (d) CONFOUND DE CONFIGURACAO: skill com `disable-model-invocation: true` tem oportunidade
#       ZERO no canal 1 POR DESENHO - um modelo=0 ali nao e evidencia de roteamento quebrado e
#       precisa aparecer marcado como tal, nao como qualquer outro zero.
#
# Uso: bash evidence/telemetry/medir-skills.sh [dir-de-projetos] [dir-de-skills] [mapa-artefatos] [base-artefatos]
set -uo pipefail
PROJ="${1:-$HOME/.claude/projects}"
SKILLS="${2:-$HOME/.claude/skills}"
ARTMAP="${3:-$(dirname "$0")/artefatos-de-skill.json}"
ARTBASE="${4:-$PWD}"

python3 - "$PROJ" "$SKILLS" "$ARTMAP" "$ARTBASE" <<'PY'
import json, pathlib, collections, re, sys

proj, skills_dir, artmap_path, artbase = (
    pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]),
    pathlib.Path(sys.argv[3]), pathlib.Path(sys.argv[4]))

instaladas = sorted(d.name for d in skills_dir.glob('*') if (d / 'SKILL.md').exists())
nomes = set(instaladas)

# canal 1 (estrutural, tool_use), particionado por plano - o particionamento e so para
# RELATAR onde a invocacao aconteceu; os dois planos somam no total de uso real.
modelo_main = collections.Counter(); modelo_sub = collections.Counter()
# canal 2 forte (estrutural, <command-name>) e fraco (regex sobre texto livre, NUNCA somado)
cmd = collections.Counter(); mencao = collections.Counter()
sess = collections.defaultdict(set)
n_main = n_sub = 0

pat = re.compile(r'(?:^|\s)/(' + '|'.join(re.escape(n) for n in nomes) + r')\b') if nomes else None
cmd_pat = re.compile(r'<command-name>\s*/?(' + '|'.join(re.escape(n) for n in nomes) +
                      r')\s*</command-name>') if nomes else None
# os dois falsos positivos MEDIDOS na issue #53 tem 104588 e 49303 caracteres de documento
# colado; nenhum comando digitado chega perto disso.
MENCAO_MAX_CHARS = 8000
BLOCO_CODIGO = re.compile(r'```.*?```', re.DOTALL)

for p in proj.rglob('*.jsonl'):
    is_sub = 'subagents' in str(p)
    if is_sub:
        n_sub += 1
    else:
        n_main += 1
    for line in p.open(errors='ignore'):
        d = None
        if '"Skill"' in line:
            try: d = json.loads(line)
            except Exception: d = None
            if d:
                m = d.get('message') or {}
                c = m.get('content') if isinstance(m, dict) else None
                if isinstance(c, list):
                    for b in c:
                        if isinstance(b, dict) and b.get('type') == 'tool_use' and b.get('name') == 'Skill':
                            s = (b.get('input') or {}).get('skill')
                            if s:
                                (modelo_sub if is_sub else modelo_main)[s] += 1
                                sess[s].add(p.stem)
        if cmd_pat and '<command-name>' in line:
            for m3 in cmd_pat.finditer(line):
                cmd[m3.group(1)] += 1; sess[m3.group(1)].add(p.stem)
        # canal fraco: NUNCA em subagente - o prompt de delegacao cita nomes de skill por
        # construcao (3/3 falsos positivos medidos vinham desse plano).
        if pat and not is_sub and '/' in line:
            if d is None:
                try: d = json.loads(line)
                except Exception: continue
            if d.get('type') in ('user', 'last-prompt', 'queued-command', 'queue-operation'):
                m = d.get('message') or {}
                c = m.get('content') if isinstance(m, dict) else None
                txt = c if isinstance(c, str) else (
                    ' '.join(b.get('text', '') for b in c if isinstance(b, dict)) if isinstance(c, list) else '')
                txt += ' ' + str(d.get('prompt', '') or '')
                if len(txt) > MENCAO_MAX_CHARS:
                    continue
                txt = BLOCO_CODIGO.sub(' ', txt)
                for m2 in pat.finditer(txt):
                    mencao[m2.group(1)] += 1

n_transcripts = n_main + n_sub

def frontmatter(nome):
    f = skills_dir / nome / 'SKILL.md'
    try:
        return f.read_text(errors='ignore').split('\n')
    except Exception:
        return []

def custo(nome):
    for ln in frontmatter(nome):
        if ln.startswith('description:'):
            return len(ln) - 13
    return 0

def invocacao_por_modelo_desabilitada(nome):
    return any(ln.strip() == 'disable-model-invocation: true' for ln in frontmatter(nome))

try:
    artefatos = json.loads(artmap_path.read_text())
except Exception:
    artefatos = {}

def artefato(nome):
    """Ressalva (c) como codigo: existe no disco o que a skill declara produzir?
    Retorna None se a skill nao esta mapeada (sem denominador, sem veredito), o Path do
    primeiro achado se o artefato existe, ou False se mapeada e ausente (denominador
    estimado: procurou e nao achou)."""
    padrao = artefatos.get(nome)
    if not padrao:
        return None
    achados = list(artbase.glob(padrao))
    return achados[0] if achados else False

frac_sub = f"{round(100 * n_sub / n_transcripts)}%" if n_transcripts else "0%"
print(f"transcripts: {n_transcripts} total = {n_main} principais + {n_sub} de subagente ({frac_sub})")
print(f"skills instaladas: {len(instaladas)}\n")

hdr = (f"{'skill':32s} {'modelo':>7s} {'modelo(sub)':>12s} {'cmd':>5s} {'mencao':>7s} "
       f"{'total':>6s} {'sessoes':>8s} {'custo B':>8s}")
print(hdr)
print('-' * len(hdr))

linhas = []
for s in instaladas:
    tm, ts, c, me = modelo_main[s], modelo_sub[s], cmd[s], mencao[s]
    tot = tm + ts + c  # mencao NUNCA soma: e sinal fraco, nao uso confirmado
    linhas.append((tot, s, tm, ts, c, me, len(sess[s]), custo(s)))
linhas.sort(reverse=True)

zero_uso = []
for tot, s, tm, ts, c, me, ns, cb in linhas:
    nota = ''
    if tot == 0 and invocacao_por_modelo_desabilitada(s):
        nota = '  <- modelo=0 por config (disable-model-invocation), nao e falha de roteamento'
    elif tot == 0:
        nota = '  <- ZERO USO'
    print(f"{s:32s} {tm:>7} {ts:>12} {c:>5} {me:>7} {tot:>6} {ns:>8} {cb:>8}{nota}")
    if tot == 0:
        zero_uso.append((s, cb))

print()
if not zero_uso:
    print("nenhuma skill com zero uso.")
else:
    candidatas = []
    for s, cb in zero_uso:
        a = artefato(s)
        if a is None:
            print(f"  {s}: ROUTING/OPPORTUNITY UNRESOLVED - sem denominador (artefato nao "
                  f"mapeado em {artmap_path.name}, oportunidade de uso desconhecida)")
        elif a is False:
            print(f"  {s}: artefato: ausente ({artefatos[s]}) -> denominador estimado, zero "
                  f"uso E zero artefato")
            candidatas.append((s, cb))
        else:
            print(f"  {s}: artefato: encontrado {a} -> uso possivel fora do canal medido "
                  f"(rebaixada de 'sem uso', NAO e candidata)")
    print()
    if candidatas:
        total_b = sum(c for _, c in candidatas)
        print(f"CANDIDATAS A DEPRECIACAO: {len(candidatas)} skills, {total_b} B de descricao por sessao")
        for s, c in candidatas:
            print(f"  {s} ({c} B)")
        print()
        print("ANTES DE ARQUIVAR, verifique - zero uso com denominador estimado ainda nao e")
        print("prova definitiva de inutilidade:")
        print("  (a) a skill e nova? Nao houve tempo de uso.")
        print("  (b) o gatilho da `description` esta errado? Ela nunca dispara mesmo sendo util.")
        print("  Depreciar por (b) e jogar fora capacidade por defeito de roteamento.")
    else:
        print("SEM CANDIDATA A DEPRECIACAO: toda skill de zero uso ficou ROUTING/OPPORTUNITY "
              "UNRESOLVED ou teve artefato encontrado no disco.")
PY
