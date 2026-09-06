#!/usr/bin/env python3
"""PROBE - atribui cada arquivo do ledger do Stop-gate a um repositorio, e mede a distribuicao.

POR QUE ESTE ARQUIVO EXISTE
----------------------------
O ledger e nomeado por `sha256(ROOT)[:32]` (`evidence/hooks/verify-gate.sh`, funcao `sha`). Isso
da identidade sem publicar caminho, o que e defensavel. Mas tornava IMPOSSIVEL, na pratica,
responder a pergunta que motivou a onda 25 - "quais repositorios concentram as reprovacoes?".

Em 2026-09-02 essa pergunta foi respondida A MAO, varrendo 334 raizes candidatas da maquina e
casando digests. O resultado refutou a atribuicao publicada da onda 25: `/var/www/amaral-intern-hub`
respondia por 14 reprovacoes, e o dominante era `/home/ti/debthub-wt-phone3` com 1.116. Uma
analise que so foi possivel por forca bruta nao e capacidade do instrumento - e por isso este
probe existe: a proxima pessoa nao precisa refazer a varredura.

O QUE ELE MEDE, E O QUE NAO
----------------------------
MEDE: por repositorio identificado, a contagem de `pass`/`fail`/`gap`, o numero de snapshots
distintos, a parada mais repetida sobre UM MESMO snapshot, e quantas reexecucoes foram
ESTRITAMENTE redundantes (mesmo snapshot, verificadores e ambiente, veredito anterior `fail`).

NAO MEDE efeito. A distribuicao de vereditos nao diz se o portao melhorou o trabalho - isso e
pergunta de experimento pareado, que continua nao executado.

LIMITE DECLARADO: a atribuicao depende do repositorio AINDA EXISTIR no caminho original. Ledger de
worktree apagada fica com `<nao identificado>` para sempre, e o probe reporta quantos sao em vez
de calar - ledger nao atribuido e ausencia conhecida, nao zero.
"""
from __future__ import annotations

import collections
import hashlib
import json
import os
import pathlib
import sys

EXIT_OK = 0
EXIT_NAO_VERIFICADO = 2

# Profundidade da varredura. `git` nao e consultado: o predicado e "diretorio que contem `.git`",
# que e o mesmo que `verify-gate.sh` usa para decidir que esta num repositorio.
PROFUNDIDADE = 4
BASES_PADRAO = ("/home/ti", "/var/www", "/opt", "/srv")
# Ledger nao atribuido com menos que isto nao entra na tabela (segue nos totais).
LIMIAR_EXIBICAO = int(os.environ.get("TOLLENS_LEDGER_LIMIAR", "10"))


def chave(caminho: str) -> str:
    """Reproduz `sha(){ sha256sum | cut -c1-32; }` sobre o caminho da raiz."""
    return hashlib.sha256(caminho.encode("utf-8")).hexdigest()[:32]


def raizes(bases) -> dict[str, str]:
    """digest -> caminho, para todo diretorio com `.git` sob as bases."""
    achados: dict[str, str] = {}
    for base in bases:
        if not os.path.isdir(base):
            continue
        corte = base.count(os.sep) + PROFUNDIDADE
        for dirpath, dirnames, _ in os.walk(base, onerror=lambda _e: None):
            if dirpath.count(os.sep) > corte:
                dirnames[:] = []
                continue
            if os.path.exists(os.path.join(dirpath, ".git")):
                achados[chave(dirpath)] = dirpath
            dirnames[:] = [d for d in dirnames
                           if d not in (".git", "node_modules", ".venv", "__pycache__", ".cache")]
    return achados


def le_ledger(diretorio: pathlib.Path):
    """Devolve {digest: [registro, ...]} apenas dos registros COM veredito.

    Registros sem `verdict` sao de outro esquema (`session_integrity`) gravado no mesmo
    diretorio; contados a parte para que a mistura nao vire silencio.
    """
    por_chave: dict[str, list] = collections.defaultdict(list)
    sem_veredito = 0
    for arquivo in sorted(diretorio.glob("*.jsonl")):
        k = arquivo.stem
        for linha in arquivo.read_text(encoding="utf-8", errors="replace").splitlines():
            try:
                r = json.loads(linha)
            except json.JSONDecodeError:
                continue
            if r.get("verdict"):
                por_chave[k].append(r)
            else:
                sem_veredito += 1
    return por_chave, sem_veredito


def mede(registros):
    """Contagens por repositorio, incluindo a redundancia estrita."""
    v = collections.Counter(r["verdict"] for r in registros)
    snaps = collections.Counter(r["snapshot"] for r in registros)
    visto: dict[tuple, str] = {}
    redundantes = 0
    for r in registros:
        ident = (r["snapshot"], r.get("verifiers"), r.get("env"))
        if visto.get(ident) == "fail" and r["verdict"] == "fail":
            redundantes += 1
        visto[ident] = r["verdict"]
    return {
        "paradas": len(registros),
        "fail": v["fail"], "pass": v["pass"], "gap": v["gap"],
        "snapshots": len(snaps),
        "max_repeticoes": max(snaps.values(), default=0),
        "redundantes": redundantes,
    }


def main() -> int:
    diretorio = pathlib.Path(os.environ.get("EVIDENCE_LEDGER_DIR")
                             or (pathlib.Path.home() / ".claude" / "evidence"))
    if not diretorio.is_dir():
        print(f"NAO VERIFICADO: ledger ausente em {diretorio}.", file=sys.stderr)
        return EXIT_NAO_VERIFICADO
    bases = tuple(os.environ.get("TOLLENS_BASES_LEDGER", "").split(":")) \
        if os.environ.get("TOLLENS_BASES_LEDGER") else BASES_PADRAO
    mapa = raizes(bases)
    por_chave, sem_veredito = le_ledger(diretorio)
    if not por_chave:
        print(f"NAO VERIFICADO: nenhum registro com veredito em {diretorio} "
              f"({sem_veredito} de outro esquema). Nada a atribuir.", file=sys.stderr)
        return EXIT_NAO_VERIFICADO

    linhas = []
    for k, regs in por_chave.items():
        m = mede(regs)
        m["repositorio"] = mapa.get(k, f"<nao identificado {k[:10]}>")
        m["identificado"] = k in mapa
        linhas.append(m)
    linhas.sort(key=lambda m: -m["fail"])

    if "--json" in sys.argv:
        print(json.dumps({"linhas": linhas, "sem_veredito": sem_veredito,
                          "raizes_varridas": len(mapa)}, ensure_ascii=False))
        return EXIT_OK

    larg = max((len(x["repositorio"]) for x in linhas), default=12)
    larg = min(larg, 52)
    print(f"{'repositorio'.ljust(larg)}  {'fail':>6s} {'pass':>6s} {'gap':>5s} "
          f"{'snaps':>6s} {'max-rep':>7s} {'redund':>7s}")
    tot = collections.Counter()
    for m in linhas:
        # LIMIAR DE EXIBICAO, e ele e declarado: ledger nao identificado com poucas paradas e,
        # quase sempre, repositorio temporario de teste ja apagado. Imprimir mil linhas dessas
        # afoga o sinal. Eles continuam nos TOTAIS - omitir da tabela nao e descartar do numero.
        if not m["identificado"] and m["paradas"] < LIMIAR_EXIBICAO:
            tot["ocultos"] += 1
            for c in ("fail", "pass", "gap", "redundantes", "paradas"):
                tot[c] += m[c]
            continue
        print(f"{m['repositorio'][:larg].ljust(larg)}  {m['fail']:6d} {m['pass']:6d} "
              f"{m['gap']:5d} {m['snapshots']:6d} {m['max_repeticoes']:7d} {m['redundantes']:7d}")
        for c in ("fail", "pass", "gap", "redundantes", "paradas"):
            tot[c] += m[c]
    print()
    print(f"paradas com veredito: {tot['paradas']} | fail {tot['fail']} | pass {tot['pass']} "
          f"| gap {tot['gap']}")
    if tot["paradas"]:
        print(f"reexecucoes estritamente redundantes: {tot['redundantes']} "
              f"({100 * tot['redundantes'] / tot['paradas']:.1f}%) - mesmo snapshot, mesmos "
              f"verificadores, mesmo ambiente, veredito anterior ja `fail`")
    nao_ident = sum(1 for m in linhas if not m["identificado"])
    print(f"ledgers: {len(linhas)} | nao atribuidos: {nao_ident} "
          f"(repositorio apagado ou fora das bases varridas) | linhas de outro esquema: {sem_veredito}")
    if tot["ocultos"]:
        print(f"omitidos da tabela: {tot['ocultos']} ledgers nao identificados com menos de "
              f"{LIMIAR_EXIBICAO} paradas - contados nos totais acima, nao descartados")
    return EXIT_OK


if __name__ == "__main__":
    raise SystemExit(main())
