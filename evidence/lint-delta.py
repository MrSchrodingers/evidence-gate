#!/usr/bin/env python3
"""PORTAO QUE JULGA O DELTA, NAO A ARVORE.

O DEFEITO QUE ESTE ARQUIVO EXISTE PARA FECHAR, medido em 2026-08-31 no log do proprio portao
(`~/.claude/evidence/*.jsonl`): 2942 `fail` contra 2110 `pass` em 5054 registros - 42% de
aprovacao - e a causa de TODAS as 2942 e a MESMA linha, `falharam: python-analyzer`. O adaptador
roda o analisador sobre a ARVORE INTEIRA, entao qualquer turno num repositorio com divida
preexistente reprova por trabalho que nao e o do turno.

Um portao que reprova 58% das vezes por motivo alheio ensina o operador a ignora-lo, e ai ele
deixa de ser portao. E a armadilha do `bug preexistente` que a onda 22 tirou das REGRAS e que
seguiu viva na CONFIGURACAO.

A PERGUNTA MUDA. Hoje o portao pergunta "esta arvore esta limpa?", cuja resposta nao depende do
trabalho feito. Deve perguntar "este turno piorou alguma coisa?".

    veredito = f(D(head) \\ D(base))     e nao      f(D(head))

DUAS CLASSES COM ESCOPOS DIFERENTES, e e isso que evita o falso dilema entre `per_file` e arvore
inteira - dilema que a onda 24 tentou resolver escolhendo um lado e falhou nos dois:

    HIGIENE   import/variavel nao usados     conta so nas LINHAS TOCADAS
              Divida de higiene alheia nao e do seu turno. Medido em /var/www/amaral-intern-hub:
              F401 73 + F841 7 = 80 de 86 diagnosticos.

    QUEBRA    sintaxe, nome indefinido,      conta na ARVORE INTEIRA, contra BASELINE
              redefinicao, `__all__` roto    Sua mudanca PODE quebrar arquivo que voce nao tocou -
              remover uma funcao quebra quem a chama. Por isso `per_file` sozinho estava errado:
              ele perde exatamente esta classe. Medido: F822 5 + F811 1 = 6 preexistentes, que sem
              baseline bloqueiam todo turno para sempre.

IDENTIDADE DO DIAGNOSTICO, e este e o ponto sutil. Casar baseline por `(arquivo, linha)` faz
QUALQUER edicao acima deslocar tudo e gerar falso-novo em massa - o baseline viraria ruido em uma
edicao. A chave e `(caminho relativo, codigo, mensagem normalizada)`: sobrevive a deslocamento de
linha, e distingue dois diagnosticos diferentes do mesmo codigo no mesmo arquivo pela mensagem,
que nomeia o simbolo. NAO e afirmacao - `tests/unit/lint-delta.sh` tem o controle positivo que
insere linhas antes e mede que a impressao digital nao muda.

O QUE ESTE ARQUIVO NAO FAZ, declarado: ele nao executa o analisador nem le o repositorio. Recebe
diagnosticos, hunks e baseline, e devolve veredito. Fronteira escolhida para que o nucleo seja
testavel sem repo, sem rede e sem o hook - a logica que decide bloqueio nao pode morar dentro de
um executor de 400 linhas de shell que ninguem consegue exercitar isoladamente.
"""
from __future__ import annotations

import argparse
import hashlib
import pathlib
import json
import re
import sys

EXIT_OK = 0
EXIT_BLOQUEIA = 1
EXIT_NAO_VERIFICADO = 2

# Normalizacao da mensagem para a impressao digital. Ruff escreve `\`uuid\` imported but unused`;
# o backtick e o nome do simbolo importam (distinguem dois F401 no mesmo arquivo), mas espacos
# variaveis e numeros de ocorrencia nao. Numero VIRA `#`: mensagens que contam ocorrencia
# (`redefinition of unused 'x' from line 3`) mudariam de digital a cada edicao acima, que e
# exatamente o falso-novo que a chave por linha produz.
_NUM = re.compile(r"\d+")
_ESPACO = re.compile(r"\s+")


def normaliza(msg: str) -> str:
    return _ESPACO.sub(" ", _NUM.sub("#", msg or "")).strip()


def digital(caminho: str, codigo: str, mensagem: str) -> str:
    """Identidade estavel a deslocamento de linha."""
    base = f"{caminho}\x00{codigo}\x00{normaliza(mensagem)}"
    return hashlib.sha256(base.encode("utf-8")).hexdigest()[:16]


# R6 DO REFUTADOR. `_cava` devolvia `None` para DUAS situacoes diferentes - chave AUSENTE e chave
# PRESENTE com valor `null` - e `normaliza_diagnosticos` tratava as duas como "saida ilegivel".
# Consequencia medida: um analisador que emita `"code": null` (que e como versoes de ruff
# anteriores a criacao de `invalid-syntax` reportam erro de sintaxe) fazia o turno INTEIRO virar
# NAO VERIFICADO, exit 2, em vez de ser julgado. Fail-closed, entao nao abria buraco - mas
# tornava `eh_quebra(codigo is None)` INALCANCAVEL pelo unico caminho que o hook usa
# (`--raw-file` + `--map`), e a justificativa que estava escrita aqui ("sem esta linha uma versao
# que emita code:null reabre o buraco") era FALSA: reabriria como exit 2, nao como aprovacao.
# O sentinela separa as duas: ausente continua sendo ilegivel; nulo e um diagnostico que o
# analisador nao soube nomear, que e informacao - e `eh_quebra` a classifica como quebra.
_AUSENTE = object()


def _cava(obj, caminho: str):
    """Le `location.row` de um dicionario aninhado.

    Devolve `_AUSENTE` quando a chave nao existe (quem chama transforma em NAO VERIFICADO, nunca
    em zero) e o VALOR quando ela existe - inclusive `None`, que e dado e nao ausencia.
    """
    for parte in caminho.split("."):
        if not isinstance(obj, dict) or parte not in obj:
            return _AUSENTE
        obj = obj[parte]
    return obj


def normaliza_diagnosticos(brutos, mapa, prefixo=""):
    """Traduz a saida NATIVA do analisador para o formato do nucleo.

    O mapa vem do ADAPTADOR, nao daqui: cada ferramenta nomeia os campos como quer (`ruff` usa
    `location.row`, outras usam `line`), e embutir isso no nucleo faria cada ferramenta nova exigir
    edicao deste arquivo. Declarativo no adaptador, generico aqui.
    """
    saida = []
    for i, b in enumerate(brutos):
        reg = {}
        for campo in ("path", "line", "code", "message"):
            v = _cava(b, mapa[campo])
            if v is _AUSENTE:
                raise KeyError(f"diagnostico {i}: chave {mapa[campo]!r} ausente na saida do analisador")
            # `code` NULO e o unico campo em que nulo e informacao e nao defeito de leitura:
            # significa "diagnostico que o analisador nao nomeou". Vira string vazia e `eh_quebra`
            # o trata como QUEBRA. Nos outros tres campos nulo nao tem leitura util - sem caminho,
            # sem linha ou sem mensagem nao ha o que julgar nem o que reportar.
            if v is None:
                if campo != "code":
                    raise KeyError(f"diagnostico {i}: chave {mapa[campo]!r} com valor nulo na saida do analisador")
                v = ""
            reg[campo] = v
        if prefixo and isinstance(reg["path"], str) and reg["path"].startswith(prefixo):
            reg["path"] = reg["path"][len(prefixo):]
        reg["line"] = int(reg["line"])
        saida.append(reg)
    return saida


def sob_checkout_aninhado(caminho: str, raizes) -> bool:
    """O caminho esta dentro de OUTRO checkout que mora dentro deste repositorio?

    Medido em /var/www/amaral-intern-hub: 87 de 173 diagnosticos vinham de 4 worktrees aninhadas -
    codigo de OUTRAS branches, que nem esta no HEAD do turno. Nao e questao de escopo semantico
    nem de baseline: aquilo nunca foi objeto do turno, e reprovar por ele e reprovar por um
    checkout alheio. As raizes sao DERIVADAS por quem chama (diretorio com `.git` proprio), nunca
    uma lista de nomes - `.worktrees` e convencao, nao contrato.
    """
    return any(caminho == r or caminho.startswith(r.rstrip("/") + "/") for r in raizes)


def dentro_de_hunk(linha: int, faixas: list[tuple[int, int]]) -> bool:
    return any(ini <= linha <= fim for ini, fim in faixas)


def eh_quebra(codigo, codigos_de_quebra):
    """QUEBRA = codigo declarado, OU codigo ausente.

    Predicado UNICO: `julga` e `--emit-baseline` precisam concordar. Se o baseline usasse um
    criterio mais estreito, uma quebra preexistente jamais entraria nele e bloquearia para sempre
    sem caminho de semeadura - portao que nao pode ser satisfeito e portao que se aprende a
    contornar.
    """
    return codigo in codigos_de_quebra or codigo is None or codigo == ""


def julga(diagnosticos, hunks, baseline, codigos_de_quebra, raizes_aninhadas=()):
    """Devolve (bloqueiam, tolerados, ignorados).

    `bloqueiam`  - o turno piorou aqui
    `tolerados`  - quebra preexistente: REPORTADA, nao bloqueia. Nunca silenciada: um baseline que
                   cala e um portao desligado com aparencia de portao.
    `ignorados`  - higiene fora das linhas tocadas
    `alheios`    - dentro de outro checkout aninhado: nunca foi objeto do turno
    """
    bloqueiam, tolerados, ignorados, alheios = [], [], [], []
    for d in diagnosticos:
        if sob_checkout_aninhado(d["path"], raizes_aninhadas):
            alheios.append(d)
            continue
        fp = digital(d["path"], d["code"], d["message"])
        # CODIGO SEM NOME E QUEBRA, e a regra fecha a CLASSE em vez do repro. Um analisador nomeia
        # a regra que aplicou; diagnostico SEM nome e o analisador dizendo que nao conseguiu
        # aplicar regra nenhuma - falha de parse ou de leitura. Classificar isso como higiene o
        # sujeitaria ao teste de hunk, e a posicao reportada por uma falha de parse nao e a
        # posicao do erro (medido: colchete aberto na linha 1 e reportado na linha 202).
        quebra = eh_quebra(d["code"], codigos_de_quebra)
        registro = dict(d, fingerprint=fp, classe="quebra" if quebra else "higiene")
        if quebra:
            (tolerados if fp in baseline else bloqueiam).append(registro)
        elif dentro_de_hunk(d["line"], hunks.get(d["path"], [])):
            bloqueiam.append(registro)
        else:
            ignorados.append(registro)
    return bloqueiam, tolerados, ignorados, alheios


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="julga diagnosticos contra o delta do turno")
    p.add_argument("--diagnostics", default="[]", help="JSON: [{path,line,code,message}]")
    # SEM `required`: emitir baseline nao tem nada a ver com hunks, e exigi-los ali fazia a
    # semeadura morrer com `error: the following arguments are required: --hunks` - engolido pelo
    # `2>/dev/null` do executor, que entao seguia sem baseline e reprovava para sempre por quebra
    # preexistente. Defeito achado pelo teste PONTA A PONTA; a suite unitaria nao o via porque
    # sempre passava `--hunks`.
    p.add_argument("--hunks", default="{}", help='JSON: {"arquivo.py": [[ini,fim], ...]}')
    # G74, SEGUNDA INSTANCIA DE F3. `--raw` virou `--raw-file` por MAX_ARG_STRLEN e `--hunks`
    # ficou como argv - nunca estourou porque, em repositorio grande, o parser de diff morria
    # antes e `HUNKS` chegava como `{}`. Um defeito escondia o outro. Corrigido o parser, o mapa
    # do amaral passou a ter 2685 chaves e o hook morreu com `Argument list too long`, exit 126.
    p.add_argument("--hunks-file", default=None, help="caminho com o JSON de hunks (sem limite de argv)")
    p.add_argument("--baseline", default="", help="JSON: [fingerprint, ...] (vazio = sem baseline)")
    p.add_argument("--breakage-codes", required=True, help="lista separada por virgula")
    p.add_argument("--raw", default="", help="saida NATIVA do analisador (usar com --map)")
    # F3 DO REFUTADOR, e e defeito INTRODUZIDO pela onda: o Linux limita UM argv a
    # MAX_ARG_STRLEN = 131.072 B, independente do ARG_MAX total. A saida do ruff em
    # /var/www/amaral-intern-hub tem 147.920 B - ja estoura HOJE. O hook morria com
    # `Argument list too long`, exit 126, e como a semeadura exige RC==1 o repositorio ficava
    # BLOQUEADO PARA SEMPRE, sem recurso, gravando no ledger a MESMA linha `falharam:
    # python-analyzer` cujas 2942 ocorrencias justificam esta onda.
    #
    # Consequencia epistemica, e ela e a pior: a afirmacao "verificado em amaral-intern-hub:
    # bloqueiam 0, tolerados 6" NAO podia ter sido observada atraves do hook naquele repositorio.
    # Foi medida chamando este nucleo direto. Arquivo nao tem esse limite.
    p.add_argument("--raw-file", default=None, help="caminho com a saida NATIVA (sem limite de argv)")
    p.add_argument("--map", default="", help='JSON: {"path":"filename","line":"location.row",...}')
    p.add_argument("--strip-prefix", default="", help="prefixo absoluto a remover dos caminhos")
    p.add_argument("--nested-roots", default="", help="JSON: lista de checkouts aninhados (relativos)")
    p.add_argument("--emit-baseline", action="store_true",
                   help="imprime em stdout o baseline das QUEBRAS observadas, e sai 0")
    a = p.parse_args(argv)

    try:
        if a.raw_file is not None:
            if not a.raw_file.strip():
                print("NAO VERIFICADO: --raw-file recebeu caminho VAZIO. Mesma classe de G78: "
                      "criacao de temporario falhou e a saida do analisador nao existe.",
                      file=sys.stderr)
                return EXIT_NAO_VERIFICADO
            a.raw = pathlib.Path(a.raw_file).read_text(encoding="utf-8", errors="replace")
            # `--raw-file` VAZIO nao e arvore limpa: e leitura que nao produziu nada. Cair no
            # `--diagnostics` default (`[]`) transformaria isso em "nenhum diagnostico", que e
            # aprovacao - a mesma classe A2 que esta onda corrigiu no executor, aqui dentro do
            # nucleo. Medido: `--raw-file /dev/null` devolvia rc=0.
            if not a.raw.strip():
                print("NAO VERIFICADO: `--raw-file` nao produziu conteudo. Arquivo vazio nao e "
                      "arvore limpa - o analisador devolve `[]`, nunca nada.", file=sys.stderr)
                return EXIT_NAO_VERIFICADO
        if a.raw.strip():
            if not a.map.strip():
                print("NAO VERIFICADO: `--raw` exige `--map` - sem ele nao ha como saber de que "
                      "chave sai cada campo, e adivinhar seria inventar diagnostico.", file=sys.stderr)
                return EXIT_NAO_VERIFICADO
            diagnosticos = normaliza_diagnosticos(json.loads(a.raw), json.loads(a.map), a.strip_prefix)
        else:
            diagnosticos = json.loads(a.diagnostics)
        raizes = tuple(json.loads(a.nested_roots)) if a.nested_roots.strip() else ()
        # `--hunks-file` VENCE `--hunks`, e um arquivo VAZIO nao e "{}": e leitura que nao
        # produziu nada, e cair no default silencioso tornaria toda higiene ignorada - o mesmo
        # buraco que G74 fechou no executor, aqui dentro do nucleo.
        # S4 DO REVISOR: o predicado era `if a.hunks_file:` (so-nao-vazio) contra `if
        # a.raw_file.strip():` (nao-so-espaco) para `--raw-file` alguns blocos acima - assimetria
        # sem motivo. Com `--hunks-file " "` o valor era truthy, tentava ler o caminho `" "` como
        # arquivo, e o `OSError` subia ate o `except` generico la embaixo: fecha-fechado (correto),
        # mas com a mensagem generica de "entrada ilegivel" em vez desta, mais especifica.
        # Alinhado ao mesmo predicado de `--raw-file`.
        # S4/C3: CAMINHO VAZIO NAO E "NAO FORNECEU". `default=None` separa as duas coisas, e a
        # separacao importa porque a unica forma de chegar aqui com string vazia e quem chamou ter
        # TENTADO passar um arquivo e falhado - foi exatamente o `mktemp` de G78, que produzia
        # `--hunks-file ""`, caia no default `{}` e APROVAVA o turno. Alinhar os dois predicados
        # pela frouxidao (tratar vazio como ausente) tornaria esse caminho MAIS facil de alcancar;
        # a simetria certa e pela severidade.
        if a.hunks_file is not None:
            if not a.hunks_file.strip():
                print("NAO VERIFICADO: --hunks-file recebeu caminho VAZIO. Quem chamou tentou "
                      "passar um arquivo e nao conseguiu; o mapa de linhas tocadas nao existe.",
                      file=sys.stderr)
                return EXIT_NAO_VERIFICADO
            bruto_hunks = pathlib.Path(a.hunks_file).read_text(encoding="utf-8")
            if not bruto_hunks.strip():
                print("NAO VERIFICADO: --hunks-file vazio. O mapa de linhas tocadas nao foi lido.",
                      file=sys.stderr)
                return EXIT_NAO_VERIFICADO
        else:
            bruto_hunks = a.hunks
        hunks = {k: [tuple(x) for x in v] for k, v in json.loads(bruto_hunks).items()}
        baseline = set(json.loads(a.baseline)) if a.baseline.strip() else set()
    except (json.JSONDecodeError, TypeError, ValueError, KeyError, OSError) as exc:
        print(f"NAO VERIFICADO: entrada ilegivel ({exc}). O turno NAO foi julgado.", file=sys.stderr)
        return EXIT_NAO_VERIFICADO

    codigos = frozenset(c.strip() for c in a.breakage_codes.split(",") if c.strip())
    if not codigos:
        # Conjunto vazio faria TODO diagnostico cair na regra de higiene e o portao pararia de
        # olhar a arvore. Falha fechada, nomeando a causa.
        print("NAO VERIFICADO: `--breakage-codes` vazio - sem ele nenhum diagnostico seria "
              "julgado como quebra, e o portao aprovaria arvore roto.", file=sys.stderr)
        return EXIT_NAO_VERIFICADO

    for i, d in enumerate(diagnosticos):
        faltando = {"path", "line", "code", "message"} - set(d)
        if faltando:
            print(f"NAO VERIFICADO: diagnostico {i} sem {sorted(faltando)}.", file=sys.stderr)
            return EXIT_NAO_VERIFICADO

    if a.emit_baseline:
        fps = sorted({digital(d["path"], d["code"], d["message"])
                      for d in diagnosticos
                      if eh_quebra(d["code"], codigos)
                      and not sob_checkout_aninhado(d["path"], raizes)})
        print(json.dumps(fps))
        return EXIT_OK

    bloqueiam, tolerados, ignorados, alheios = julga(diagnosticos, hunks, baseline, codigos, raizes)

    print(json.dumps({
        "bloqueiam": len(bloqueiam), "tolerados": len(tolerados), "ignorados": len(ignorados),
        "alheios": len(alheios),
        "detalhe": [{k: r[k] for k in ("path", "line", "code", "message", "classe")}
                    for r in bloqueiam],
    }, ensure_ascii=False))

    # A EXCLUSAO NUNCA CALA (R1 do refutador). Diagnostico descartado por morar em checkout
    # aninhado era invisivel: o portao aprovava sem dizer que tinha deixado de olhar N arquivos.
    # Silencio e o que transformava a exclusao em bypass - com `git init <subdir>` o ator governado
    # movia o proprio trabalho para fora do julgamento e o portao saia 0 com stdout VAZIO. Exigir
    # historia na raiz (feito no executor) mata a versao de um comando; ela nao fecha a classe,
    # porque um commit a mais recria a raiz valida. O que fecha o SILENCIO e isto: toda execucao
    # diz quantos diagnosticos saiu do julgamento e por qual raiz, e ai a exclusao e uma decisao
    # que o operador ve, nao um buraco.
    if alheios:
        por_raiz = {}
        for r in alheios:
            for raiz in raizes:
                if r["path"] == raiz or r["path"].startswith(raiz.rstrip("/") + "/"):
                    por_raiz[raiz] = por_raiz.get(raiz, 0) + 1
                    break
        print(f"EXCLUIDO POR CHECKOUT ANINHADO: {len(alheios)} diagnostico(s) NAO foram julgados - "
              f"moram em repositorio proprio dentro desta arvore:", file=sys.stderr)
        for raiz, n in sorted(por_raiz.items(), key=lambda kv: -kv[1]):
            print(f"  {raiz}/  {n} diagnostico(s)", file=sys.stderr)

    # O BASELINE NUNCA CALA. Quebra tolerada vai para stderr em toda execucao: se o operador deixar
    # de ver os 6 defeitos preexistentes, o baseline vira anistia permanente em vez de catraca.
    if tolerados:
        print(f"QUEBRA PREEXISTENTE TOLERADA: {len(tolerados)} - nao bloqueia este turno, e "
              f"continua sendo defeito:", file=sys.stderr)
        for r in tolerados[:10]:
            print(f"  {r['path']}:{r['line']} {r['code']} {r['message']}", file=sys.stderr)
    return EXIT_BLOQUEIA if bloqueiam else EXIT_OK


if __name__ == "__main__":
    raise SystemExit(main())
