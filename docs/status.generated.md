# Estado gerado

NAO EDITAR. Gerado por `scripts/status.sh` a partir de execucao real.
O README referencia este arquivo em vez de duplicar numeros.

## Suites

| Suite | Assercoes | Exit |
|---|---:|---:|
| `tests/unit/regressao-gate.sh` | 65 | 0 |
| `tests/unit/document-tools.sh` | 57 | 0 |
| `tests/unit/supply-chain.sh` | 9 | 0 |
| `tests/unit/reprodutibilidade.sh` | variavel (ambiente) | 0 |
| `tests/unit/concorrencia.sh` | 8 | 0 |
| `tests/unit/claims.sh` | 54 | 0 |
| `tests/unit/propriedades.sh` | 31 | 0 |
| `tests/unit/fronteira-externa.sh` | 13 | 0 |
| `tests/unit/managed.sh` | 66 | 0 |
| `tests/unit/conformidade-managed.sh` | 21 | 0 |
| `tests/unit/arnes-de-mutacao.sh` | ? | 2 |
| `tests/unit/schedule.sh` | 34 | 0 |
| `tests/unit/fronteira-viva.sh` | 188 | 0 |
| `tests/unit/literatura.sh` | 76 | 0 |
| `tests/unit/capabilities.sh` | 60 | 0 |
| `tests/unit/cobertura.sh` | 36 | 0 |
| `tests/unit/contrato-de-instalador.sh` | 53 | 0 |
| `tests/unit/hooks-de-guarda.sh` | variavel (base) | 0 |
| `tests/unit/capability-conformance.py` | variavel (base) | 0 |
| `tests/unit/run.sh` | variavel (ambiente) | 0 |
| `tests/unit/managed-root-trust.sh` | variavel (sudo) | 0 |

## Mutacao

| Alvo | Mutantes | Exit |
|---|---:|---:|
| gate | 15 | passo dedicado no CI |
| contrato de subagente | 9 | passo dedicado no CI |
| instalador | 5 | passo dedicado no CI |
| fronteira externa | 7 | passo dedicado no CI |
| conformidade de dois escopos | 7 | passo dedicado no CI |
| escalonamento | 10 | passo dedicado no CI |
| fronteira viva | 30 | passo dedicado no CI |
| camada de literatura | 24 | passo dedicado no CI |
| claim ledger | 8 | passo dedicado no CI |
| capability declarada | 7 | passo dedicado no CI |
| cobertura de decisao | 6 | passo dedicado no CI |
| adaptadores (auto) | 5 | passo dedicado no CI |
| capability-conformance (auto) | 27 | passo dedicado no CI |
| corpus-completude (auto) | 22 | passo dedicado no CI |
| fable-guard (auto) | 12 | passo dedicado no CI |
| hooks-de-guarda (auto) | 18 | passo dedicado no CI |
| lint-delta (auto) | 11 | passo dedicado no CI |
| managed-transitive-trust (auto) | 2 | NAO executado no CI |
| skill-invocation-policy (auto) | 2 | NAO executado no CI |
| verify-gate-delta (auto) | 18 | passo dedicado no CI |

## Cobertura de decisao (branch), medida via subprocesso instrumentado

Piso por arquivo (evidence/cobertura.sh --check); ver o script para a mecanica de
medicao e o LIMITE declarado (cobertura prova execucao de ramo, nao correcao de
assercao).

| Arquivo | Medido | Piso | Status |
|---|---:|---:|---|
| `evidence/probes/github-ruleset.py` | 86.0% | 86.0% | OK |
| `evidence/validate-claims.py` | 81.4% | 81.4% | OK |
| `evidence/validate-literature.py` | 94.6% | 94.6% | OK |
| `evidence/runtime-probes/declared-capabilities.py` | 92.6% | 92.6% | OK |
| `orchestration/schedule.py` | 89.3% | 89.3% | OK |
| `evidence/corpus/render.py` | 93.6% | 93.6% | OK |
| `evidence/validate-adapters.py` | 69.3% | 69.3% | OK |
| `evidence/lint-delta.py` | 99.0% | 99.0% | OK |

## Componentes

| Tipo | Qtd |
|---|---:|
| adapter | 11 |
| agent | 10 |
| doctool | 5 |
| hook | 15 |
| lib | 1 |
| skill | 8 |
| **total** | **50** |

## Limites declarados

- `allowManagedHooksOnly` continua sendo uma decisao administrativa de deploy; o repositorio nao afirma que esteja ativo em toda instalacao.
- a execucao root do instalador stock agora recusa fonte que nao seja integralmente `root:root`, livre de symlinks e sem escrita de grupo/outros; isso e uma precondicao operacional, nao autenticacao criptografica do release.
- `TOLLENS_REPO`, quando usado por hooks managed para localizar verificadores, continua sendo uma dependencia que deve receber uma fronteira de confianca compativel com o ambiente onde for ativada.
- o ambiente de CI e auditavel, nao hermetico: `ubuntu-24.04` fixa a familia da imagem, nao seu digest, e a excecao `apt` permanece declarada.
- sem corpus proprio de desfecho, nao ha claim de superioridade universal de engenharia; a governanca de skills e evidence-gated e falsificavel.
- parsers e adaptadores documentais nao constituem sandbox de sistema operacional.
- rollback cobre falhas observadas pelo supervisor. `SIGKILL` do supervisor, falha de host/filesystem e comprometimento administrativo permanecem fora da garantia.
- ownership/mode checks usam semantica POSIX/GNU exercitada no CI; ACLs, capabilities e atributos de filesystem fora desse contrato exigem verificacao especifica antes de ampliar a claim.
- o ruleset impoe o check requerido enquanto a regra estiver ativa; administradores com autoridade para alterar a regra permanecem fora desse mecanismo.
- cobertura de decisao (branch, evidence/cobertura.sh) prova que um ramo foi executado por algum teste; nao prova que a assercao daquele teste esta correta. E piso, nao teto: torna a omissao detectavel (ramo nunca exercitado), nunca a torna impossivel (ramo exercitado e mal testado continua passando).

## Propriedades de seguranca medidas

- fonte privilegiada user-owned, symlinkada ou group/world-writable e rejeitada antes da delegacao quando o supervisor roda como root na raiz real.
- `TOLLENS_MANAGED_WORKER` e proibido em execucao root sobre a raiz real; o override permanece apenas para ensaios com `MANAGED_PREFIX`.
- modos esperados sao revalidados apos o deploy (`0755` para diretorios/scripts/document-tools; `0644` para os demais arquivos regulares), e divergencia provoca rollback.
- ownership usa `find ... \( ! -user root -o ! -group root \) -print -quit`, evitando o bug de precedencia onde `owner!=root, group=root` podia nao produzir saida.
- confinamento de origem/destino do manifesto, re-hash do staging, restauracao transacional e verificacao de permissao continuam cobertos pelas suites managed existentes.
