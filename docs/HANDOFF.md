# Handoff - apos a sessao de fechamento da Fase 1

- Origem: sessao de 2026-08-04 (a anterior, de 2026-08-03, produziu a versao antecessora deste arquivo)
- Estado: **M3 parcial** - enforcement e runtime atingidos; managed policy construida e NAO ativada; sandbox nao iniciado
- Referencia canonica do estado: `docs/status.generated.md` (gerado por execucao) e `docs/adr/0023`

---

## 1. Leia isto antes de qualquer coisa

**O que este projeto e:** uma configuracao de Claude Code cuja regra unica e

> Um artefato so atravessa a fronteira externa quando uma politica **fora da autoridade do ator**
> confirma evidencia valida, nao obsoleta e vinculada ao mesmo snapshot.

**O que mudou:** a fronteira externa passou a IMPOR, e isso foi medido, nao configurado. Push
direto para `main` a partir do token com `admin: true` e recusado com `GH013`. O que ainda NAO
existe e a raiz de confianca LOCAL: `~/.claude` continua gravavel pelo ator.

**Onde esta a verdade:** `docs/status.generated.md`. Nunca digite contagens a mao.

**As afirmacoes verificaveis** estao em `evidence/claims/*.yaml`, e o validador RESOLVE cada
referencia contra a suite real - citar regressao ou mutante inexistente reprova.

---

## 2. O contrato de teste deste repositorio

Sete defeitos ja tiveram esta forma:

```
precondicao falha -> operacao nao executa -> pos-condicao vacuamente verdadeira -> VERDE
```

| Onde ocorreu | O que nao executou |
|---|---|
| `--dry-run` | o `cd` falhou; nada rodou |
| locale | `LC_ALL=pt_BR` sem o locale instalado |
| locale, 2a tentativa | `locale` ecoa nome de locale inexistente |
| matcher do `apt` | `apt-get -o ... install` nao casava |
| `packaging` em S5 | SKIP reduzia o esperado junto |
| **R4** | payload com `transcript_path`/`subagent_type`, campos que o hook NAO LE |
| **L3, PB3** (nesta sessao) | fixture YAML invalido reprovava no parser; nome hostil com `/` nem era criado |

Um teste novo nao vale sem:

```
precondicoes satisfeitas
  E tratamento efetivamente aplicado
  E oraculo capaz de discriminar
  E operacao comprovadamente executada
  E Q(estado_final)
```

**Regra que emergiu desta sessao:** todo caso POSITIVO precisa de um NEGATIVO correspondente. A
ancora de evidencia do contrato de subagente teve so positivos por versoes inteiras, e por isso
seu poder de decisao nunca foi medido. Positivo sozinho mede PRESENCA, nao decisao.

E a distincao que decide como tratar pre-requisito ausente:

| Tipo | Ausente significa | Tratamento |
|---|---|---|
| **dependencia do ORACULO** (`packaging`, `pyyaml`, `flock`) | o teste **nao foi realizado** | `exit 2`, NOT_VERIFIED |
| **variacao de AMBIENTE** (locales instalados) | uma variante nao pode ser exercitada | `SKIP` + assercao-guarda exigindo ao menos uma |

---

## 3. Rigor exigido - nao negociavel

1. **Reproduza antes de corrigir**, com saida colada.
2. **Corrija a CLASSE, nao a instancia.** A allowlist de comandos do oraculo da ancora nao foi
   "acrescida de `wc`": foi trocada por FORMA de comando. Enumerar comandos nao e conjunto
   decidivel.
3. **Todo teste novo passa por mutacao**, e o kill precisa ser atribuivel ao caso-alvo. Caso com
   DUAS ancoras nao serve de alvo de mutante - nao isola qual alternativa o sustenta.
4. **Contagem e invariante.** `EXPECTED` fixo. Nesta sessao a invariante pegou tres testes meus
   errados antes que eu os publicasse.
5. **Fonte primaria para todo fato externo.** A doc primaria corrigiu o plano de P2 do handoff
   anterior (plugin NAO serve de raiz de confianca).
6. **Estado sem execucao colada e NAO VERIFICADO.**
7. **Sem emoji, sem hype, em qualquer artefato.**
8. **Uma suite por vez.** `tests/lib/lock.sh` sai 3 em corrida; isso e o lock, nao defeito.

---

## 4. Como rodar

```bash
cd ~/tollens

bash scripts/status.sh && cat docs/status.generated.md   # estado por execucao real
bash install/verify.sh                                    # conformidade repo <-> ~/.claude
bash install/apply-managed.sh --verify                    # conformidade do escopo managed

# suites - UMA POR VEZ (o lock reprova corrida com exit 3)
for s in supply-chain document-tools reprodutibilidade managed propriedades \
         claims concorrencia regressao-gate; do bash tests/unit/$s.sh || break; done
bash tests/unit/run.sh   # bateria completa de tests/unit/*.sh e *.py, despacho por disco
bash tests/mutation/run.sh
bash tests/mutation/contrato.sh
bash tests/mutation/install.sh

gh run list --limit 3
```

O fluxo de commit mudou: **`main` esta sob ruleset**. Push direto e recusado. Trabalhe em branch
e abra PR; o check `verify` precisa passar sobre o SHA.

---

## 5. O que falta, em ordem

### P2 - RAIZ DE CONFIANCA: construida, NAO ativada. E o primeiro item.

`install/apply-managed.sh` existe, tem 23 assercoes em `tests/unit/managed.sh` contra prefixo
de ensaio, e cobre 30 componentes (14 hooks + 11 adaptadores + 5 doctools - nao bastam os
hooks: o gate le a tabela de adaptadores, e tabela gravavel desliga o gate sem tocar em hook).

Falta a ativacao, que exige `sudo` com senha:

```bash
sudo bash install/apply-managed.sh              # deploy, SEM ativar
sudo bash install/apply-managed.sh --verify     # 30 componentes, 0 divergentes, 0 gravaveis
# medir aqui: cada hook deve rodar DUAS vezes (managed + usuario). Se nao dobrar, PARE.
sudo bash install/apply-managed.sh --enforce    # so depois de a medicao dobrar
# medir de novo: deve voltar a UMA vez, com os caminhos vindo de /opt.
sudo bash install/apply-managed.sh --revert     # desfaz por completo
```

**ARMADILHA, e o instalador ja a trata:** `allowManagedHooksOnly` bloqueia hook de usuario E de
plugin. Ativa-lo com deploy incompleto derruba o mecanismo inteiro. Por isso o portao de
conformidade PRECEDE toda escrita de politica (caso MG6). Nao remova essa ordem.

**Como medir** (foi assim que a precedencia de hooks foi determinada):

```bash
claude -p "responda exatamente: OK" --model claude-haiku-4-5-20251001 --tools "" \
  --no-session-persistence --output-format stream-json --include-hook-events --verbose \
  | jq -r 'select(.subtype=="hook_started") | .hook_event' | sort | uniq -c
```

### P3 - SANDBOX. E a lacuna aberta mais relevante.

`pandoc`, `libreoffice` e `pdftotext` processam entrada nao confiavel com a autoridade do
usuario. D5 impoe timeout, teto de bytes e tmpdir - isso e contencao de RECURSO, nao
isolamento. **Isto deve travar a expansao para OCR e novos formatos ate haver isolamento.**
Caminhos: `bwrap`/`nsjail`, ou container por digest.

### P3b - hermeticidade

`ubuntu-24.04` fixa familia, nao digest. Container por digest + SBOM.

### P4 - eficacia (NAO cabe numa sessao)

Corpus congelado, contraste `baseline vs harness`, `UAR/URR/AR/VY`, piloto para `p01`/`p10`,
power analysis, pre-registro, modelo logistico hierarquico. Sem isso nenhuma afirmacao sobre
melhoria de engenharia e dizivel.

### P5 - auditoria autoralmente independente

A CI e observador AMBIENTAL, nao autoral: executa testes escritos pelo mesmo processo, contra
os mesmos oraculos. Precisa de mutantes nao revelados e fixtures hostis de terceiro.

### Nao priorizar

**Metodos formais.** Dos ~19 defeitos ja catalogados, zero foram violacao de invariante de
maquina de estados. Gatilho legitimo para reavaliar: concorrencia no ledger, corrida entre
snapshot e verificacao, composicao de autoridades.

**Grafos.** Estagio exploratorio. LSP antes de indice proprio.

---

## 6. Armadilhas que ja custaram tempo

1. **`$(...)` cria subshell** - `R=$(funcao)` perde o `cd`.
2. **`head`/`tail` num pipe destroem o exit code.** Aconteceu de novo nesta sessao.
3. **`CLAUDE_ADAPTERS_DIR` vive no `settings.json`** e entra no ambiente das ferramentas.
4. **`pandoc -o x.pdf` exige engine LaTeX** - ausente na CI.
5. **`locale` ecoa o nome pedido** mesmo para locale inexistente.
6. **`sed 'y/.../.../'` quebra sob `LC_ALL=C`** com multi-byte.
7. **As suites nao sao reentrantes** - agora ha lock (`exit 3`), mas continue rodando uma por vez.
8. **`$TMPDIR` pode estar vazio no zsh** - use `${TMPDIR:-/tmp}`, nunca `${TMPDIR-/tmp}`.
9. **NOVO: crase de markdown quebra regex.** ``exit code `0` `` tem `0x60` entre `code ` e `0`.
   Qualquer padrao que atravesse "espaco opcional" falha ali. Foi um falso bloqueio em producao.
10. **NOVO: nome de arquivo nao contem `/`.** Fixture hostil com caminho absoluto embutido nem
    chega a ser criada, e a assercao passa sobre arquivos inexistentes.
11. **NOVO: `git cat-file -e <valor>`** - valor iniciado por `-` e lido como opcao. Valide a
    forma antes, `--` nao resolve em `cat-file`.
12. **NOVO: backup so do que nao e seu.** Um instalador que faz backup do arquivo que ele mesmo
    escreveu produz um `--revert` que RESTAURA a coisa que deveria remover.

---

## 7. Criterio de pronto

Nao declare a sessao concluida sem, colado na resposta:

- [ ] `bash scripts/status.sh --check` -> exit 0
- [ ] `bash install/verify.sh` -> exit 0, ou 3 se a fase managed nao esta implantada nesta
      maquina (implantar exige root; 1 = projecao de usuario divergente, e ai sim e falha)
- [ ] as 9 suites unitarias e os 3 runners de mutacao -> exit 0
- [ ] `python3 evidence/validate-claims.py` -> exit 0
- [ ] CI verde no commit final, com SHA e URL, e o PR mergeado pelo ruleset
- [ ] `docs/status.generated.md` regenerado e committado
- [ ] ADR com o que foi feito **e com o que nao foi**
- [ ] claims novas para garantias novas, com `limitations` preenchido
- [ ] portao final no agente `refutador`, sobre o diff cru

## 8. Como NAO fechar

"Fechar TUDO" nao e alcancavel numa sessao, e prometer isso repete a classe de defeito que este
projeto existe para impedir. P4 leva semanas; P5 exige um terceiro; P3 (sandbox) e trabalho de
engenharia real, nao configuracao.

O padrao que atravessa as tres ultimas sessoes: **os defeitos aparecem quando MUDA O QUE
EXECUTA** - outro locale, duas execucoes simultaneas, um plugin a mais, o binario de verdade,
variantes de formatacao, a garantia removida. Ler o mesmo codigo com mais atencao encontrou
zero deles.
