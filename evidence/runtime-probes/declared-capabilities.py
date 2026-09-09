#!/usr/bin/env python3
"""Conformidade DECLARADA de ferramentas de subagente - a metade ESTATICA do probe.

POR QUE ESTE ARQUIVO EXISTE, E O QUE ELE NAO PROVA
----------------------------------------------------
A pergunta que interessa e RuntimeConformant(a,r): o conjunto de ferramentas que o runtime
CONCEDE em execucao a um agente `a` (ObservedCapabilities) e exatamente o conjunto listado em
`tools:` no frontmatter dele (DeclaredCapabilities)? Nem mais, nem menos.

Este script NAO responde essa pergunta. Ele fecha uma metade mais estreita e mais barata:

    DeclaredCapabilities(execution/agents/X.md) == DeclaredCapabilities(<instalado>/agents/X.md)

isto e, que as fontes que DECLARAM capacidade concordam entre si. Isso e necessario mas nao
suficiente: um agente pode ser instalado com `tools:` identico ao canonico e mesmo assim o
runtime conceder mais do que essa linha diz - foi exatamente o que uma sessao real capturou
para `refutador` (ver evidence/observations/2026-08-10-capacidade-declarada-vs-observada.md).
Fechar so a metade declarada e valioso, mas chama-la de "conformidade" sem qualificar seria o
MESMO erro epistemologico de tests/unit/methodology.py: esse arquivo valida que
orchestration/skill-policy.json e orchestration/evaluation-protocol.json contem as constantes
que eles mesmos declaram - nunca observa uma execucao real. Comparar frontmatter contra
frontmatter tem a mesma limitacao estrutural: sao TRES fontes de texto declarado (canonica,
projecao do repo, instalada), nunca o comportamento do runtime.

A metade OBSERVADA exige uma sessao capaz de delegar a agentes reais e ler o resultado - isto
e, o protocolo em evidence/runtime-probes/capabilities.md, executado pelo ORQUESTRADOR (uma
sessao principal, nunca um subagente: subagente nao cria subagente).

O QUE ESTE SCRIPT VERIFICA
---------------------------
Para cada `execution/agents/<nome>.md` (a fonte canonica):
  1. O `tools:` do frontmatter e extraido como um CONJUNTO (a ORDEM dos nomes nao importa).
     HISTORICO (ate a onda 27/G105): a projecao do repo para `tdd` era mantida A MAO e listava
     as mesmas seis ferramentas em ordem diferente da fonte canonica - por isso a comparacao
     precisava ignorar ordem. Desde que `orchestration/render.py` passou a GERAR a projecao do
     repo (em vez de so verifica-la), `tools:` copia o valor do canonico verbatim e a ordem
     casa POR CONSTRUCAO para essa perna; a comparacao por conjunto (em vez de sequencia)
     permanece porque a leitura instalada (`<CLAUDE_HOME>/agents`, item 3 abaixo) continua fora
     do alcance do gerador e pode divergir em ordem por qualquer outro motivo.
  2. O mesmo campo e extraido de `.claude/agents/<nome>.md` (projecao local deste repositorio,
     gerada por `orchestration/render.py` - um estipe DIFERENTE do arquivo canonico, com corpo
     truncado e campos extras como `permissionMode`, mas que declara `tools:` de novo).
  3. O mesmo campo e extraido de `<CLAUDE_HOME>/agents/<nome>.md` (a copia instalada que o
     runtime de fato carrega; `CLAUDE_HOME` segue a mesma convencao de `install/verify.sh`,
     default `$HOME/.claude`). Com `--repo-only`, este passo NAO RODA - a saida declara o numero
     de fontes efetivamente comparadas (2, nao 3) e diz explicitamente que a perna instalada
     ficou de fora; nunca reporta "identico nas 3 fontes" tendo comparado so 2.
  4. Os conjuntos comparados nesta execucao precisam ser IDENTICOS. Arquivo ausente numa das
     dependencias, frontmatter que nao fecha, YAML invalido dentro dele, ou falha ambiental de
     leitura (permissao, E/S), e NAO_VERIFICADO (nao se pode concluir conformidade nem
     divergencia). Conjunto diferente e VIOLACAO - inclusive quando a diferenca e uma chave
     `tools:` OMITIDA numa projecao: pela doc primaria do Claude Code, omitir `tools:` faz o
     subagente herdar TODAS as ferramentas disponiveis (a concessao MAXIMA), o que e decidivel e
     diverge de qualquer lista finita do canonico - nao e lacuna, e VIOLACAO.

`orchestration/render.py --check` ja confere que as tres arvores existem e que os workflows sao
validos. Desde a onda 27 (G105) ele TAMBEM gera a projecao do repo a partir do canonico, o que
faz `tools:` (e `description:`, `model:`) casar por CONSTRUCAO entre `execution/agents` e
`.claude/agents` - conferir os dois de novo aqui seria duplicar logica de render.py sem ganhar
poder de deteccao. O valor residual deste script para `tools:` passa a ser a perna que a
geracao NAO alcanca: `<CLAUDE_HOME>/agents` (item 3 acima), que so este arquivo compara -
render.py nunca escreve fora deste repositorio, e `install/manifest.lock` prende a copia
instalada ao digest do canonico, nunca ao conteudo de `tools:` por si.

SEGUNDA PROPRIEDADE: CONTRATO DE ESCRITA x CAPACIDADE DECLARADA
----------------------------------------------------------------
`orchestration/registry.json` declara, por agente, `writes: true|false` - o contrato de
escrita, e o unico oraculo legivel por maquina de quem pode alterar arquivo. A comparacao de
`tools:` entre fontes nao ve esse contrato: as tres podiam concordar em conceder escrita a um
agente declarado sem escrita, e a comparacao continuaria verde.

Para cada agente com `writes: false`, nenhuma das duas arvores deste repositorio (canonica e
projecao) pode conceder escrita pelo frontmatter. Duas formas de conceder:
  1. listar `Write`/`Edit`/`MultiEdit`/`NotebookEdit` em `tools:`; e
  2. declarar o campo `memory:`. Pela doc primaria do Claude Code (sub-agents, secao "Enable
     persistent memory", https://code.claude.com/docs/en/sub-agents): "Read, Write, and Edit
     tools are automatically enabled so the subagent can manage its memory files." A concessao
     e do RUNTIME e nao aparece em `tools:` - por isso nenhuma comparacao de `tools:` a
     detecta.

O QUE ESTA SEGUNDA CHECAGEM NAO AFIRMA
---------------------------------------
Nao afirma que o agente e read-only. `Bash` esta no `tools:` dos agentes com `writes: false`, e
Bash e superficie de escrita ESTRITAMENTE MAIOR que Write/Edit (`>`, `tee`, `sed -i`,
`python3 -c`, `git apply`, qualquer binario), sem portao equivalente: em
install/hooks-spec.sh:39-46, `artifact-discipline.sh` e `self-mod-audit.sh` so rodam no matcher
`Write|Edit|MultiEdit|NotebookEdit`, e o matcher que alcanca `Bash` roda apenas
`fable-guard.sh`, de escopo declaradamente restrito. A propriedade verificada aqui e menor e
verdadeira: capacidade DECLARADA compativel com o contrato declarado. Read-only de fato depende
de sandbox de filesystem, que nao mora no frontmatter.

LIMITE DECLARADO
-----------------
- So compara TEXTO declarado. Nao invoca nenhum agente, nao inspeciona `~/.claude/logs` nem
  transcritos de sessao - isso e do protocolo runtime, deliberadamente fora deste arquivo.
- A checagem de contrato le as duas arvores do repositorio; a copia INSTALADA fica de fora
  porque `install/verify.sh` ja a prende ao digest do arquivo canonico em
  `install/manifest.lock` (ver o docstring de `confere_contrato`). Se aquele elo cair, esta
  checagem passa a nao dizer nada sobre o que esta instalado.
- So confere `.codex/agents/*.toml`? NAO - nem para `tools:`, nem para `memory:`. O runtime
  Codex usa `sandbox_mode` (um modelo de sandbox de SO), nao uma allowlist de nomes de
  ferramenta - comparar os dois exigiria uma ontologia de equivalencia que nao existe hoje,
  entao fica fora de escopo (nao "resolvido em silencio").
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

EXIT_OK, EXIT_VIOLACAO, EXIT_NAO_VERIFICADO = 0, 1, 2

# Contrato de escrita: o unico oraculo legivel por maquina de quem pode alterar arquivo.
REGISTRY_REL = "orchestration/registry.json"
# Ferramentas que concedem escrita por NOME. `Bash` NAO esta aqui de proposito: ele tambem
# escreve, e escreve mais (`>`, `tee`, `sed -i`, `python3 -c`, `git apply`), mas nao ha como
# decidir isso pelo nome da ferramenta - ver "O QUE ESTA SEGUNDA CHECAGEM NAO AFIRMA".
FERRAMENTAS_DE_ESCRITA = frozenset({"Write", "Edit", "MultiEdit", "NotebookEdit"})

try:
    import yaml
except ImportError:
    # Sem parser YAML de referencia nao ha como decidir `tools:` - "nao reprovou" seria
    # indistinguivel de "nao foi verificado". Mesma convencao de evidence/validate-claims.py e
    # evidence/validate-literature.py, que ja dependem de pyyaml.
    sys.stderr.write(
        "NAO VERIFICADO: pyyaml ausente. `tools:` do frontmatter nao pode ser comparado "
        "neste ambiente. Instale a versao pinada (ver .github/workflows/verify-pr.yml).\n")
    sys.exit(EXIT_NAO_VERIFICADO)

DEFAULT_ROOT = Path(__file__).resolve().parents[2]
ROOT = Path(os.environ.get("TOLLENS_ROOT", DEFAULT_ROOT)).resolve()
CLAUDE_HOME = Path(os.environ.get("CLAUDE_HOME", Path.home() / ".claude")).resolve()

ROTULO_PROJECAO = "projecao do repo (.claude/agents)"
ROTULO_INSTALADA = "instalada (CLAUDE_HOME/agents)"
ROTULO_CANONICA = "canonica (execution/agents)"


def contrato_de_escrita(root: Path) -> dict | str:
    """Mapa `nome -> entrada` de `orchestration/registry.json`, onde cada entrada declara
    `writes: true|false` - o contrato de escrita do agente.

    Devolve o mapa, ou uma STRING com o motivo pelo qual o contrato nao pode ser lido. Toda
    falha de leitura e INDECIDIVEL (NAO_VERIFICADO), nunca violacao: sem contrato nao ha com o
    que comparar a capacidade declarada, e inventar um default ("assume read-only") produziria
    veredito sobre um oraculo que nao existe."""
    caminho = root / REGISTRY_REL
    try:
        reg = json.loads(caminho.read_text(encoding="utf-8"))
    except OSError:
        return f"{REGISTRY_REL} nao pode ser lido (ausente, ou falha de permissao/E-S)"
    except json.JSONDecodeError:
        return f"{REGISTRY_REL} nao e JSON valido"
    agentes = reg.get("agents") if isinstance(reg, dict) else None
    if not isinstance(agentes, dict):
        return f"{REGISTRY_REL} nao tem o mapeamento `agents`"
    return agentes


class _ChaveToolsAusente:
    """Sentinela devolvida por `tools_declarados`: o frontmatter FECHOU, foi lido por inteiro e
    reconhecido como YAML valido, e mesmo assim nenhuma lista `tools:` foi encontrada - chave
    omitida, ou presente e vazia (`tools:` sem valor, `tools: ""`, `tools: []`). Isto e DIFERENTE
    de `None`/`ERRO_AMBIENTAL`/`YAML_INVALIDO` (onde nada pode ser concluido sobre o conteudo):
    aqui o documento foi lido e entendido ate o fim, e a ausencia da chave e ela mesma o dado.
    Pela tabela de frontmatter da doc primaria do Claude Code
    (https://code.claude.com/docs/en/sub-agents, campo `tools`: "Inherits every tool available to
    subagents if omitted"), omitir `tools:` faz o subagente HERDAR TODAS as ferramentas - a
    concessao MAXIMA, o oposto de uma lacuna indecidivel."""


TOOLS_AUSENTE = _ChaveToolsAusente()


class _ErroAmbiental:
    """Sentinela: a LEITURA do arquivo falhou por causa ALHEIA ao conteudo do frontmatter -
    permissao negada, erro de E/S, ou a fonte sumiu entre o `glob` e a leitura (corrida rara).
    Distinto de frontmatter malformado (`None`) e de YAML invalido (`YAML_INVALIDO`): nos dois
    outros casos o documento FOI lido; aqui ele nao pode nem ser aberto. Classificar uma falha de
    ambiente como defeito estrutural do agente e o falso positivo que ensina o operador a
    desligar o mecanismo - por isso este caso sempre resulta em NAO_VERIFICADO, nunca VIOLACAO,
    inclusive quando a fonte afetada e a canonica."""


ERRO_AMBIENTAL = _ErroAmbiental()


class _YamlInvalido:
    """Sentinela: o bloco entre os dois `---` foi lido por inteiro, mas `yaml.safe_load` recusa
    o conteudo (`yaml.YAMLError`) ou o produz num formato que nao e um mapeamento (frontmatter
    nao e uma lista solta nem um escalar). Indecidivel pela mesma razao que frontmatter que nao
    fecha: nao se pode concluir conformidade nem divergencia de um documento que o parser de
    referencia recusa. Por decisao explicita desta correcao, NAO e VIOLACAO - e um defeito de
    SINTAXE do documento, nao de capability (o que este probe existe para medir)."""


YAML_INVALIDO = _YamlInvalido()


def frontmatter_lines(caminho: Path) -> list[str] | _ErroAmbiental | None:
    """Linhas ENTRE os dois `---` do frontmatter YAML.
    ERRO_AMBIENTAL = a leitura do arquivo falhou (permissao, E/S, arquivo sumiu) - a causa e do
                     ambiente, nao do conteudo do agente.
    None           = arquivo lido, mas sem frontmatter fechado (nao abre com `---`, ou abre e
                     nunca fecha) - indecidivel, nao ausencia de divergencia."""
    try:
        linhas = caminho.read_text(encoding="utf-8").splitlines()
    except OSError:
        return ERRO_AMBIENTAL
    if not linhas or linhas[0].strip() != "---":
        return None
    for i, linha in enumerate(linhas[1:], start=1):
        if linha.strip() == "---":
            return linhas[1:i]
    return None


def frontmatter_doc(caminho: Path) -> dict | _ErroAmbiental | _YamlInvalido | None:
    """O frontmatter INTEIRO como mapeamento, para decidir sobre chaves que nao sao `tools:`
    (hoje: `memory:`). Devolve as mesmas sentinelas de indecidibilidade de `tools_declarados`.

    Parse proprio, e nao um refactor de `tools_declarados`: aquela funcao decide UMA chave e tem
    contrato, casos de borda e mutantes proprios (a forma escalar separada por virgula, a lista
    de bloco, a ausencia como concessao maxima). Esta so precisa do mapeamento cru."""
    fm = frontmatter_lines(caminho)
    if fm is ERRO_AMBIENTAL:
        return ERRO_AMBIENTAL
    if fm is None:
        return None
    try:
        carregado = yaml.safe_load("\n".join(fm))
    except yaml.YAMLError:
        return YAML_INVALIDO
    return carregado if isinstance(carregado, dict) else YAML_INVALIDO


def tools_declarados(
    caminho: Path,
) -> frozenset[str] | _ChaveToolsAusente | _ErroAmbiental | _YamlInvalido | None:
    """Conjunto de ferramentas em `tools:`, lido via `yaml.safe_load` sobre o bloco de
    frontmatter - nao um parser artesanal. YAML define DUAS formas de SEQUENCIA (nao "duas
    formas de chave de lista"): bloco (`tools:` seguido de `  - A` / `  - B` nas linhas
    seguintes, com linha em branco e comentario ignorados como em qualquer YAML) e fluxo
    (`tools: [A, B]`). A forma usada pelos 10 agentes reais deste repositorio - `tools: A, B` -
    e um ESCALAR separado por virgula, nao uma sequencia YAML; e aceita explicitamente aqui.

    Retorno:
      None            = indecidivel: frontmatter que nao abre ou nao fecha.
      ERRO_AMBIENTAL  = indecidivel: a leitura do arquivo falhou (causa alheia ao conteudo).
      YAML_INVALIDO   = indecidivel: frontmatter fechado, mas o YAML dentro dele nao parseia ou
                        nao e um mapeamento.
      TOOLS_AUSENTE   = decidivel: frontmatter valido, mas nenhuma `tools:` foi encontrada - ver
                        a doutrina no docstring de `_ChaveToolsAusente`.
      frozenset[str]  = a lista declarada, com pelo menos um nome de ferramenta.
    """
    fm = frontmatter_lines(caminho)
    if fm is ERRO_AMBIENTAL:
        return ERRO_AMBIENTAL
    if fm is None:
        return None
    try:
        doc = yaml.safe_load("\n".join(fm))
    except yaml.YAMLError:
        return YAML_INVALIDO
    if not isinstance(doc, dict):
        # Frontmatter fechou, mas o conteudo nao e um mapeamento YAML (ex.: lista solta,
        # escalar) - a mesma indecidibilidade de YAML invalido: nao ha `tools:` para ler de algo
        # que nao tem chaves.
        return YAML_INVALIDO
    valor = doc.get("tools")
    if valor is None:
        # Chave omitida, OU presente sem valor (`tools:` sozinho, `tools: null`) - as duas formas
        # que a doc primaria trata como omissao.
        return TOOLS_AUSENTE
    if isinstance(valor, str):
        itens = frozenset(t.strip() for t in valor.split(",") if t.strip())
    elif isinstance(valor, list):
        itens = frozenset(str(t).strip() for t in valor if str(t).strip())
    else:
        # Tipo inesperado (numero, booleano, mapeamento aninhado) - nao e uma forma reconhecida
        # de lista de ferramentas; indecidivel, nao violacao por adivinhacao de forma.
        return YAML_INVALIDO
    return itens if itens else TOOLS_AUSENTE


def parse_args(argv: list[str]) -> argparse.Namespace:
    """Argumentos de linha de comando. `argparse` recusa qualquer flag desconhecida com exit 2
    (SystemExit) e mensagem em stderr - o mesmo codigo de EXIT_NAO_VERIFICADO deste script, o que
    e a leitura correta: um invocador que passa algo que este programa nao reconhece nao pode ter
    seu pedido decidido, entao "nao verificado" (e nao "modo completo por omissao silenciosa") e
    a unica resposta honesta. Antes, `"--repo-only" in sys.argv` aceitava QUALQUER outro token sem
    reclamar - `--repoonly` (erro de digitacao) rodava o modo completo calado, sem avisar que o
    filtro pedido nunca foi aplicado."""
    ap = argparse.ArgumentParser(
        description="Compara `tools:` do frontmatter entre a fonte canonica, a projecao do "
                    "repo e (fora de --repo-only) a copia instalada em CLAUDE_HOME.")
    ap.add_argument(
        "--repo-only", action="store_true",
        help="compara so execution/agents x .claude/agents; NAO verifica CLAUDE_HOME/agents "
             "(uso: CI, onde a perna instalada nao existe no runner)")
    return ap.parse_args(argv)


def confere_contrato(canon_files: list[Path]) -> tuple[list[str], list[str], int]:
    """Compara o CONTRATO de escrita (`writes` em orchestration/registry.json) com a capacidade
    que o frontmatter concede, nas DUAS arvores deste repositorio (canonica e projecao).
    Devolve (violacoes, nao_verificados, pares_conferidos).

    So agentes com `writes: false` sao conferidos - quem tem `writes: true` declara escrita por
    contrato, e listar Write/Edit ou `memory:` ali e coerencia, nao violacao.

    A copia INSTALADA fica de fora, e nao por omissao: `install/verify.sh` compara o sha256 do
    arquivo instalado com o digest de `install/manifest.lock`, calculado sobre o arquivo
    canonico - conformidade da canonica mais digest igual implica a instalada. A projecao NAO
    herda esse argumento: e um estipe diferente, com corpo truncado e campos proprios, entao
    tem digest proprio e precisa ser conferida aqui."""
    violacoes: list[str] = []
    nao_verificados: list[str] = []
    conferidos = 0

    contrato = contrato_de_escrita(ROOT)
    if isinstance(contrato, str):
        return violacoes, [f"contrato de escrita indecidivel: {contrato}"], conferidos

    for canon_path in canon_files:
        nome = canon_path.stem
        entrada = contrato.get(nome)
        escreve = entrada.get("writes") if isinstance(entrada, dict) else None
        if not isinstance(escreve, bool):
            nao_verificados.append(
                f"{nome}: {REGISTRY_REL} nao declara `writes` booleano para este agente - "
                f"sem contrato nao ha capacidade a conferir")
            continue
        if escreve:
            continue
        fontes = [(ROTULO_CANONICA, canon_path),
                  (ROTULO_PROJECAO, ROOT / ".claude" / "agents" / f"{nome}.md")]
        for rotulo, caminho in fontes:
            if not caminho.is_file():
                # Fonte ausente ja e reportada pela comparacao de `tools:` acima, que tambem ja
                # decide o exit code - repetir aqui duplicaria a linha, nao acrescentaria sinal.
                continue
            doc = frontmatter_doc(caminho)
            if not isinstance(doc, dict):
                nao_verificados.append(
                    f"{nome}: frontmatter {rotulo} em {caminho} ilegivel ou nao e um mapeamento "
                    f"- indecidivel, nao violacao")
                continue
            conferidos += 1
            if doc.get("memory") is not None:
                violacoes.append(
                    f"{nome}: {REGISTRY_REL} declara `writes: false`, mas o frontmatter {rotulo} "
                    f"declara `memory: {doc['memory']}` - pela doc primaria do Claude Code "
                    f"(sub-agents, \"Enable persistent memory\"), com memoria habilitada \"Read, "
                    f"Write, and Edit tools are automatically enabled\", concessao que nao "
                    f"aparece em `tools:` e que nenhuma comparacao entre fontes detecta")
            declaradas = tools_declarados(caminho)
            escrita_direta = (sorted(declaradas & FERRAMENTAS_DE_ESCRITA)
                              if isinstance(declaradas, frozenset) else [])
            if escrita_direta:
                violacoes.append(
                    f"{nome}: {REGISTRY_REL} declara `writes: false`, mas `tools:` do "
                    f"frontmatter {rotulo} concede escrita direta "
                    f"({', '.join(escrita_direta)})")

    return violacoes, nao_verificados, conferidos


def main() -> int:
    args = parse_args(sys.argv[1:])
    repo_only = args.repo_only

    # `--repo-only` COMPARA SO AS DUAS ARVORES INTERNAS AO REPOSITORIO.
    #
    # Existe para a CI. Num runner limpo `CLAUDE_HOME/agents` nao existe, e a perna instalada
    # sai NAO_VERIFICADO (exit 2) - correto localmente, mas transformaria um passo de CI em
    # vermelho permanente por ausencia esperada, o que ensina a ignorar o passo.
    #
    # O que ele NAO faz: afrouxar. A comparacao `execution/agents` x `.claude/agents` continua
    # exit 1 em divergencia e exit 2 se qualquer das duas arvores faltar. A perna descartada NAO
    # E VERIFICADA neste modo - nem PASS nem FAIL sao emitidos para ela - e isso e declarado
    # tanto no numero de fontes de cada linha PASS quanto num aviso explicito abaixo, nao so em
    # comentario: uma saida que dissesse "identico nas 3 fontes" comparando so 2 seria uma prova
    # arquivada de uma comparacao que nunca ocorreu.
    #
    # Valor colateral (ONDA 27/G105): `orchestration/render.py` gera `.claude/agents` a partir
    # do canonico, entao `tools:` ja casa por construcao entre essas duas arvores - esta
    # comparacao de conteudo deixa de acrescentar poder de deteccao ali. O que sobra e a perna
    # `<CLAUDE_HOME>/agents`, que a geracao nunca alcanca: e essa comparacao (canonico x
    # instalada) que continua sendo o valor real deste modo, nao a comparacao canonico x
    # projecao do repo.
    canon_dir = ROOT / "execution" / "agents"
    repo_proj_dir = ROOT / ".claude" / "agents"
    home_dir = CLAUDE_HOME / "agents"

    canon_files = sorted(canon_dir.glob("*.md"))
    if not canon_files:
        sys.stderr.write(
            f"NAO VERIFICADO: nenhum agente canonico em {canon_dir} - "
            f"o contrato de extracao nao tem o que comparar.\n")
        return EXIT_NAO_VERIFICADO

    rotulos_desta_execucao = [ROTULO_PROJECAO] if repo_only else [ROTULO_PROJECAO, ROTULO_INSTALADA]
    n_fontes = 1 + len(rotulos_desta_execucao)  # canonica + as demais deste modo

    if repo_only:
        print(f"--repo-only: comparando {n_fontes} fontes ({ROTULO_CANONICA}, {ROTULO_PROJECAO}). "
              f"A perna instalada ({home_dir}) NAO e verificada nesta execucao - PASS abaixo "
              f"nao decide conformidade com o runtime realmente instalado.\n")

    violacoes: list[str] = []
    nao_verificados: list[str] = []
    ok = 0

    for canon_path in canon_files:
        nome = canon_path.stem
        t_canon = tools_declarados(canon_path)
        if t_canon is ERRO_AMBIENTAL:
            # Falha AMBIENTAL (permissao, E/S) na fonte canonica: indecidivel, nao defeito
            # estrutural - ver docstring de `_ErroAmbiental`.
            nao_verificados.append(
                f"{nome}: fonte canonica {canon_path} nao pode ser lida (falha ambiental de "
                f"permissao ou E/S) - indecidivel, nao defeito estrutural")
            continue
        if t_canon is YAML_INVALIDO:
            nao_verificados.append(
                f"{nome}: fonte canonica {canon_path} tem frontmatter fechado mas o YAML dentro "
                f"dele nao parseia - indecidivel, nao violacao")
            continue
        if t_canon is None or t_canon is TOOLS_AUSENTE:
            motivo = ("frontmatter ausente ou que nao fecha" if t_canon is None
                      else "`tools:` omitido na fonte canonica")
            violacoes.append(f"{nome}: fonte canonica {canon_path} sem `tools:` legivel "
                              f"({motivo}) - isto e defeito estrutural, nao ausencia de dado")
            continue

        fontes = {ROTULO_PROJECAO: repo_proj_dir / f"{nome}.md"}
        if not repo_only:
            fontes[ROTULO_INSTALADA] = home_dir / f"{nome}.md"

        divergiu = False
        for rotulo, caminho in fontes.items():
            if not caminho.is_file():
                nao_verificados.append(f"{nome}: {rotulo} ausente em {caminho}")
                divergiu = True
                continue
            t_outra = tools_declarados(caminho)
            if t_outra is ERRO_AMBIENTAL:
                nao_verificados.append(
                    f"{nome}: {rotulo} existe mas nao pode ser lido (falha ambiental de "
                    f"permissao ou E/S) em {caminho} - indecidivel")
                divergiu = True
                continue
            if t_outra is None or t_outra is YAML_INVALIDO:
                motivo = ("o frontmatter nao fecha" if t_outra is None
                          else "o YAML do frontmatter nao parseia")
                nao_verificados.append(f"{nome}: {rotulo} existe mas {motivo} "
                                        f"em {caminho} - indecidivel")
                divergiu = True
                continue
            if t_outra is TOOLS_AUSENTE:
                violacoes.append(
                    f"{nome}: {rotulo} nao declara `tools:` em {caminho} - por omissao o "
                    f"subagente HERDA TODAS as ferramentas disponiveis (concessao MAXIMA, "
                    f"doc primaria do Claude Code), o OPOSTO de conformidade com o canonico "
                    f"({', '.join(sorted(t_canon))})")
                divergiu = True
                continue
            if t_outra != t_canon:
                falta = sorted(t_canon - t_outra)
                sobra = sorted(t_outra - t_canon)
                detalhe = []
                if falta:
                    detalhe.append(f"ausentes ali: {', '.join(falta)}")
                if sobra:
                    detalhe.append(f"a mais ali: {', '.join(sobra)}")
                violacoes.append(
                    f"{nome}: {rotulo} DIVERGE do canonico ({'; '.join(detalhe)})")
                divergiu = True

        if not divergiu:
            ok += 1
            print(f"PASS {nome}: tools: identico nas {n_fontes} fontes comparadas "
                  f"({ROTULO_CANONICA}, {', '.join(rotulos_desta_execucao)}) "
                  f"({', '.join(sorted(t_canon))})")

    total = len(canon_files)
    modo = " [--repo-only: perna instalada NAO verificada]" if repo_only else ""
    print(f"\nagentes canonicos: {total} | conformes: {ok} | "
          f"divergentes: {len(violacoes)} | nao verificados: {len(nao_verificados)}{modo}")

    if violacoes:
        print("\nVIOLACOES (tools: declarado diverge entre fontes, ou concede mais do que o "
              "canonico declara):")
        for v in violacoes:
            print(f"  - {v}")
    if nao_verificados:
        print("\nNAO VERIFICADO (fonte ausente ou frontmatter ilegivel - nao decide conformidade):")
        for v in nao_verificados:
            print(f"  - {v}")

    violacoes_contrato, nao_verificados_contrato, conferidos = confere_contrato(canon_files)

    print(f"\nCONTRATO DE ESCRITA ({REGISTRY_REL} `writes: false` x capacidade que o "
          f"frontmatter concede): {conferidos} pares agente-fonte conferidos | "
          f"{len(violacoes_contrato)} violacoes | "
          f"{len(nao_verificados_contrato)} nao verificados")
    if violacoes_contrato:
        print("CONTRATO DE ESCRITA - VIOLACOES (o frontmatter concede escrita a agente "
              "declarado sem escrita):")
        for v in violacoes_contrato:
            print(f"  - {v}")
    if nao_verificados_contrato:
        print("CONTRATO DE ESCRITA - NAO VERIFICADO (sem oraculo legivel, nada e decidido):")
        for v in nao_verificados_contrato:
            print(f"  - {v}")
    print("CONTRATO DE ESCRITA - LIMITE: isto compara DECLARACAO com DECLARACAO e NAO afirma "
          "read-only. `Bash` consta no `tools:` desses agentes e escreve por `>`, `tee`, "
          "`sed -i`, `python3 -c` ou `git apply` - superficie maior que Write/Edit, e nao "
          "decidivel por nome de ferramenta. Read-only de fato exige sandbox de filesystem, "
          "fora do frontmatter. A copia instalada nao e conferida aqui (fica presa ao digest "
          "de install/manifest.lock, ver install/verify.sh).")

    print("\nISTO FECHA APENAS A METADE DECLARADA. ObservedCapabilities (o que o runtime "
          "realmente concede em execucao) NAO foi medido aqui - ver "
          "evidence/runtime-probes/capabilities.md.")
    if repo_only:
        print(f"--repo-only tambem NAO fechou a metade declarada inteira: {ROTULO_INSTALADA} "
              f"ficou fora desta execucao por desenho (ver acima).")

    if violacoes or violacoes_contrato:
        return EXIT_VIOLACAO
    if nao_verificados or nao_verificados_contrato:
        return EXIT_NAO_VERIFICADO
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
