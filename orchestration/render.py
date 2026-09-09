#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, os, pathlib, re, tomllib, unicodedata
# ROOT POR OVERRIDE DE AMBIENTE (mesmo idioma de orchestration/schedule.py:89-90). Sem isto,
# nenhuma fixture sintetica sob TOLLENS_ROOT pode exercitar este validador sem copiar a arvore
# inteira - necessario desde a onda 27 (G103/issue #47), ver tests/unit/risk-policy.sh.
DEFAULT_ROOT=pathlib.Path(__file__).resolve().parents[1]
ROOT=pathlib.Path(os.environ.get('TOLLENS_ROOT', DEFAULT_ROOT)).resolve()

def fail(msg): print(f'PROJECTION_ERROR {msg}'); return 1

# ONDA 12, achado da revisao. A primeira versao fazia `re.search(r'^description:[ ]*(.+)$')` no
# .md e comparava com o TOML PARSEADO. Dois modos de falha, ambos medidos pelo revisor:
#   - description entre aspas (obrigatorias em YAML assim que o texto contem `: `) devolvia a
#     string COM as aspas e reprovava projecao correta - falso vermelho;
#   - escalar de bloco (`>` ou `|`) devolvia o INDICADOR. Canonico e projecao Claude com o mesmo
#     indicador comparavam `'|' == '|'` e o portao PASSAVA POR VACUIDADE, no lado que ele existe
#     para vigiar, acusando o Codex que estava certo. Diagnostico invertido.
# As dez estao limpas hoje, entao era latente. Um portao que so funciona enquanto o dado for
# simples nao e portao: e sorte com sintaxe.
#
# Sem dependencia nova: `tomllib` e stdlib e ja estava importado; `pyyaml` nao e garantido aqui.
# Entao o frontmatter e desescapado por um subconjunto EXPLICITO (escalar plano, ou aspas simples
# ou duplas numa linha), e qualquer coisa fora dele RECUSA em vez de comparar lixo.
def _desc_md(p):
 t=p.read_text(encoding='utf-8')
 m=re.search(r'^description:[ ]*(.*)$',t,re.M)
 if not m: return None
 v=m.group(1).strip()
 if v[:1] in ('|','>',''): return None      # escalar de bloco ou vazio: fora do subconjunto
 if len(v)>=2 and v[0]==v[-1] and v[0] in '"\'':
  return v[1:-1].replace('\\"','"') if v[0]=='"' else v[1:-1].replace("''","'")
 if v[:1] in ('"',"'"): return None         # aspa aberta e nao fechada na linha: recusa
 return v

# ONDA 27 (G105/issue #49). O ADR 0024 registrava, como decisao ja aceita, um renderizador com
# "modo de convergencia" que GERA as projecoes de agente. Ate aqui isto nunca existiu:
# `orchestration/render.py` era verificador puro desde o commit inicial, e `--check` era inerte
# porque `p.parse_args()` descartava o namespace do argparse (a flag nunca era lida) - as dez
# projecoes em `.claude/agents/*.md` e `.codex/agents/*.toml` eram mantidas A MAO contra o que o
# ADR e este arquivo afirmavam.
#
# `_plain_md` extrai `tools:`/`model:` do canonico pelo MESMO subconjunto explicito de
# `_desc_md`: escalar plano de uma linha, recusa (None) em qualquer forma mais rica (bloco,
# aspas, lista YAML de fato). Nenhuma dependencia nova: seguem regex + stdlib.
def _plain_md(p, campo):
 t=p.read_text(encoding='utf-8')
 m=re.search(rf'^{campo}:[ ]*(.*)$',t,re.M)
 if not m: return None
 v=m.group(1).strip()
 if not v or v[:1] in ('|','>','"',"'"): return None
 return v

# `_desc_md` DESESCAPA para o VALOR semantico (tira aspas, resolve escape). Reemitir esse valor
# como escalar PLANO na projecao so e seguro se ele proprio nao precisaria de aspas em YAML -
# testar isso na LEITURA e simetrico a `_desc_md` recusar aspas nao fechadas na escrita: as duas
# funcoes recusam em vez de produzir YAML/TOML que parece certo e nao fecha.
_INDICADORES_RESERVADOS = '|>"\'-?:[]{}#&*!%@`'
def _plano_seguro(v):
 return bool(v) and v[:1] not in _INDICADORES_RESERVADOS and ': ' not in v and '\n' not in v

# ONDA 27 (G103/issue #47). O kernel governa por CLASSE DE RISCO (execution/config/CLAUDE.md,
# secao 7: trivial/normal/medio/alto) e a orquestracao governa por ID DE WORKFLOW
# (orchestration/workflows/*.json: investigation-only/standard-change/high-risk-change). Ate
# aqui a ligacao entre os dois vocabularios vivia so em prosa (CLAUDE.md:3, docs/method/
# orquestracao-e-avaliacao.md:7), nao verificavel por oraculo nenhum. `orchestration/
# risk-policy.json` declara a funcao risco->workflow como artefato; o que segue e o verificador.
#
# PRINCIPIO ANTITAUTOLOGICO: a politica NUNCA se autoconfirma. O DOMINIO vem do kernel (lido
# aqui, nunca copiado) e o CONTRADOMINIO vem do diretorio de workflows em disco - se qualquer um
# dos dois mudar sem a politica acompanhar, o portao reprova (tests/unit/risk-policy.sh N6/N7).
def _norm_risco(s):
 s=unicodedata.normalize('NFD', s)
 s=''.join(c for c in s if unicodedata.category(c)!='Mn')
 return s.strip().lower()

def _classes_do_kernel(p):
 # Le a tabela `| Risco | Caminho |` da secao 7 e devolve os ids de classe, na ordem em que
 # aparecem. "alto — autorizacao, dado, ..." tem travessao e qualificadores: o token de classe e
 # so o PRIMEIRO, separado por espaco ou travessao.
 linhas=p.read_text(encoding='utf-8').splitlines()
 dentro=False; out=[]
 for ln in linhas:
  if re.match(r'^\|\s*Risco\s*\|\s*Caminho\s*\|', ln): dentro=True; continue
  if not dentro: continue
  if not ln.startswith('|'): break
  if re.match(r'^\|[\s:-]+\|', ln): continue          # linha separadora `|---|---|`
  celula=ln.split('|')[1].strip()
  token=re.split(r'[\s—–-]+', celula)[0]
  if token: out.append(_norm_risco(token))
 return out

def _check_risk_policy(root):
 # Devolve a lista de erros (vazia = politica valida). GUARDA CONTRA VACUIDADE: um parser que
 # devolvesse menos de 2 classes (secao 7 removida ou reformatada) faria a checagem de
 # totalidade passar por ausencia de ramo a cobrir - o mesmo modo de falha que este arquivo ja
 # documentou em `'|' == '|'` (comentario ONDA 12, acima). Por isso reprova aqui, explicito.
 kernel=root/'execution/config/CLAUDE.md'
 if not kernel.is_file(): return ['kernel ausente: execution/config/CLAUDE.md']
 dominio=_classes_do_kernel(kernel)
 if len(dominio)<2:
  return [f'tabela de risco do kernel nao foi parseada (achei {dominio}) - recusado para nao passar por vacuidade']
 existentes={p.stem for p in (root/'orchestration/workflows').glob('*.json')}
 pol_p=root/'orchestration/risk-policy.json'
 if not pol_p.is_file():
  return [f'orchestration/risk-policy.json ausente: a funcao risco->workflow nao existe como artefato (dominio do kernel: {dominio})']
 pol=json.loads(pol_p.read_text(encoding='utf-8'))
 mapa=pol.get('map')
 if not isinstance(mapa, dict): return ["risk-policy.json sem objeto 'map'"]
 mapa_norm={_norm_risco(k): v for k, v in mapa.items()}
 erros=[]
 for c in dominio:                                     # (i) TOTALIDADE
  if c not in mapa_norm: erros.append(f"classe do kernel sem entrada na politica: '{c}'")
 for c in mapa_norm:                                    # (ii) SEM CLASSE ORFA
  if c not in dominio: erros.append(f"classe na politica que o kernel nao declara: '{c}'")
 for c, v in mapa_norm.items():                         # (iii) RESOLUCAO / (iv) AUSENCIA DECLARADA
  if not isinstance(v, dict) or 'workflow' not in v:
   erros.append(f"entrada '{c}' sem campo 'workflow'"); continue
  wf=v['workflow']
  if wf is None:
   if not str(v.get('rationale', '')).strip():
    erros.append(f"classe '{c}' sem workflow e SEM justificativa declarada")
  elif wf not in existentes:
   erros.append(f"classe '{c}' aponta para workflow inexistente: '{wf}'")
 imagem={v.get('workflow') for v in mapa_norm.values() if isinstance(v, dict)}   # (v) ALCANCE
 nao_por_risco=pol.get('not_risk_selected') or {}
 for wid in sorted(existentes):
  if wid not in imagem and wid not in nao_por_risco:
   erros.append(f"workflow '{wid}' nao e alcancavel por classe alguma nem declarado em 'not_risk_selected'")
 for wid in sorted(nao_por_risco):
  if wid not in existentes:
   erros.append(f"'not_risk_selected' cita workflow inexistente: '{wid}'")
  if not str(nao_por_risco.get(wid, '')).strip():
   erros.append(f"'not_risk_selected[{wid}]' sem justificativa")
 return erros

def _perfil(reg, escreve):
 perfis = reg.get('projection_profiles') or {}
 p = perfis.get('writes_true' if escreve else 'writes_false')
 return p if isinstance(p, dict) else None

def _render_claude(nome, desc, tools, modelo, perfil):
 linhas=['---', f'name: {nome}', f'description: {desc}', f'tools: {tools}', f'model: {modelo}']
 if 'memory' in perfil: linhas.append(f"memory: {perfil['memory']}")
 linhas.append(f"permissionMode: {perfil['permissionMode']}")
 linhas.append(f"maxTurns: {perfil['maxTurns']}")
 if 'isolation' in perfil: linhas.append(f"isolation: {perfil['isolation']}")
 linhas.append('---')
 linhas.append(f'Siga `execution/agents/{nome}.md` como instrução canônica. Produza evidência e declare `NOT_VERIFIED` quando faltar oráculo.')
 return '\n'.join(linhas) + '\n'

def _esc_toml(v):
 return v.replace('\\', '\\\\').replace('"', '\\"')

def _render_codex(nome, desc, codex_modelo, codex_effort, sandbox):
 linhas=[
  f'name="{nome}"',
  f'description="{_esc_toml(desc)}"',
  f'model="{codex_modelo}"',
  f'model_reasoning_effort="{codex_effort}"',
  f'sandbox_mode="{sandbox}"',
  f'developer_instructions="Siga execution/agents/{nome}.md. Evidência obrigatória; ausência de oráculo é NOT_VERIFIED."',
 ]
 return '\n'.join(linhas) + '\n'

def main():
 ap=argparse.ArgumentParser()
 ap.add_argument('--check', action='store_true',
                 help='gera em memoria e compara byte a byte com o que esta em disco; nao escreve nada')
 args=ap.parse_args()
 check=args.check
 reg=json.loads((ROOT/'orchestration/registry.json').read_text())
 if reg.get('schema_version')!=2:return fail('schema_version')
 names=set(reg['agents'])
 for n,s in reg['agents'].items():
  src=ROOT/s['source']
  if not src.is_file(): return fail(f'fonte ausente: {n}')
  # HISTORICO (ONDA 12). Ate 2026-08-17 este arquivo validava so existencia e inventario, nunca
  # conteudo, e as dez projecoes traziam `description: "Projecao do agente canonico <nome>"`
  # enquanto o canonico trazia o GATILHO real ("PORTAO FINAL antes de declarar pronto ou fazer
  # merge [...] Read-only, nunca corrige"). Pela doc primaria do Claude Code, `description` e o
  # campo que o modelo usa para decidir delegar, e a precedencia poe `.claude/agents/` de
  # projeto ACIMA de `~/.claude/agents/` de usuario - a descricao util ficava sombreada pela
  # inutil, nos dez agentes. Desde a onda 27 (G105) a projecao deixa de ter descricao PROPRIA:
  # `description:` e GERADA a partir do canonico, o mesmo texto nas duas pontas por construcao,
  # entao a classe de sombreamento fica estruturalmente impossivel em vez de so verificada.
  #
  # A mensagem distingue AUSENTE de FORA DO SUBCONJUNTO: "sem description" para um arquivo que
  # TEM description em escalar de bloco manda o leitor procurar a coisa errada.
  _c=_desc_md(src)
  if not _c: return fail(f'description do canonico ausente ou fora do subconjunto suportado (plano/aspas em uma linha): {n}')
  if not _plano_seguro(_c): return fail(f'description do canonico exige aspas/bloco na projecao Claude, fora do subconjunto que este gerador emite: {n}')
  _tools=_plain_md(src,'tools')
  if not _tools: return fail(f'tools do canonico ausente ou fora do subconjunto suportado (escalar plano): {n}')
  if not _plano_seguro(_tools): return fail(f'tools do canonico exige aspas/bloco, fora do subconjunto que este gerador emite: {n}')
  _modelo=_plain_md(src,'model')
  if not _modelo: return fail(f'model do canonico ausente ou fora do subconjunto suportado (escalar plano): {n}')
  if not _plano_seguro(_modelo): return fail(f'model do canonico exige aspas/bloco, fora do subconjunto que este gerador emite: {n}')
  perfil=_perfil(reg, s.get('writes'))
  if perfil is None: return fail(f'projection_profiles sem entrada para writes={s.get("writes")!r}: {n}')
  _cx_modelo=s.get('codex_model'); _cx_effort=s.get('codex_reasoning_effort')
  if not _cx_modelo or not _cx_effort: return fail(f'codex_model/codex_reasoning_effort ausente no registry: {n}')
  claude_esperado=_render_claude(n,_c,_tools,_modelo,perfil)
  codex_esperado=_render_codex(n,_c,_cx_modelo,_cx_effort,perfil['sandbox_mode'])
  claude_path=ROOT/f'.claude/agents/{n}.md'
  codex_path=ROOT/f'.codex/agents/{n}.toml'
  if check:
   if not claude_path.is_file(): return fail(f'projecao Claude ausente: {n}')
   if claude_path.read_text(encoding='utf-8')!=claude_esperado: return fail(f'projecao Claude diverge do canonico: {n}')
   if not codex_path.is_file(): return fail(f'projecao Codex ausente: {n}')
   if codex_path.read_text(encoding='utf-8')!=codex_esperado: return fail(f'projecao Codex diverge do canonico: {n}')
  else:
   claude_path.write_text(claude_esperado, encoding='utf-8')
   codex_path.write_text(codex_esperado, encoding='utf-8')
 for f in ['.claude/settings.json','.codex/config.toml','.codex/hooks.json','CLAUDE.md','AGENTS.md']:
  if not (ROOT/f).is_file(): return fail(f'arquivo ausente: {f}')
 tomllib.loads((ROOT/'.codex/config.toml').read_text())
 if not json.loads((ROOT/'.codex/hooks.json').read_text()).get('hooks'): return fail('hooks Codex vazios')
 for pth in sorted((ROOT/'orchestration/workflows').glob('*.json')):
  w=json.loads(pth.read_text()); nodes=set(w['nodes'])
  if w['entry'] not in nodes or any(a not in nodes or b not in nodes for a,b in w['edges']): return fail(f'grafo invalido: {pth.name}')
 if names!={p.stem for p in (ROOT/'.claude/agents').glob('*.md')}:return fail('inventario Claude diverge')
 if names!={p.stem for p in (ROOT/'.codex/agents').glob('*.toml')}:return fail('inventario Codex diverge')
 # ONDA 27 (G103/issue #47). `registry.json["workflows"]` era lido por NADA: a lista podia
 # divergir do diretorio real sem que verificador algum acusasse (docs/architecture/
 # orquestracao-multirruntime.md:53 afirmava "validados contra o registry", o que era falso -
 # medido). Esta checagem torna a afirmacao verdadeira em vez de so corrigir a prosa.
 wf_disco={p.stem for p in (ROOT/'orchestration/workflows').glob('*.json')}
 wf_reg=set(reg.get('workflows') or [])
 if wf_reg!=wf_disco:
  falt=sorted(wf_disco-wf_reg); orf=sorted(wf_reg-wf_disco); det=[]
  if falt: det.append(f"sem entrada em registry['workflows']: {falt}")
  if orf: det.append(f"em registry['workflows'] sem arquivo em disco: {orf}")
  return fail("registry['workflows'] diverge do diretorio orchestration/workflows (" + '; '.join(det) + ')')
 erros_risco=_check_risk_policy(ROOT)
 if erros_risco:
  for e in erros_risco: print(f'RISK_POLICY_ERROR {e}')
  return 1
 modo = 'verificadas' if check else 'geradas e verificadas'
 print(f'projeções {modo}: {len(names)} agentes, {len(list((ROOT/"orchestration/workflows").glob("*.json")))} workflows')
 return 0
if __name__=='__main__': raise SystemExit(main())
