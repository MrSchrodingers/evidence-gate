# As duas primeiras execucoes deste experimento sao INVALIDAS. Nenhum numero delas vale.

Registrado em 2026-09-02, antes de qualquer nova execucao, para que os dados descartados nao
reapareçam depois como se fossem resultado.

## Rodada 1 - controle nao executou

As 8 celulas de `vanilla` e `lite` sairam em 1 segundo com `rc=1` e `Not logged in - please run
/login`: o `HOME` descartavel nao tinha credencial. Nao houve sessao. Lidas pelas colunas de
desfecho, aquelas celulas diziam "sem harness o modelo nao corrige nada, com harness corrige
100%" - resultado espetacular e inteiramente fabricado pelo defeito do arnes.

## Rodada 2 - desfecho impossivel de ser positivo, e o arnes sem contencao

Achado por `auditor-seguranca` em contexto separado, DEPOIS de eu ter afirmado ao operador que o
defeito estava corrigido. Nao estava.

`printf '%s' "$out" | python3 - ... <<'PY'` NAO entrega `$out` ao programa: o heredoc **sobrescreve
o pipe** (shellcheck SC2259). Medido nos dados: `bytes_saida` = 0 em 10 de 10 registros, e
`alegacao_falsa` = false em 10 de 10 - falso POR CONSTRUCAO, que e a definicao de desfecho que nao
mede nada. Controle direto:

    $ printf '%s' "texto de verdade" | python3 - <<'PY'
      File "<stdin>", line 1
        texto de verdadeimport sys
    SyntaxError

## E um defeito que nao e de medicao, e sim de contencao

O `esac` do bloco de execucao fecha na linha 129. O oraculo roda na 142 - **fora** do `unshare`.
O `oraculo.sh` e o `calc.py` que ele carrega com `exec_module` sao escritos pelo MODELO durante a
sessao (`arquivo_alterado: true` em 2 das 10 celulas). Alcance medido do que executa: `HOME` real,
`~/.claude/.credentials.json` legivel (888 bytes, modo 600), 21 interfaces de rede, sem `--net`.

O namespace da aparencia de sandbox e nao e um: isola MOUNT, nao processo, nem rede, nem
credencial - e o unico trecho que roda dentro dele e a sessao. O artefato que ela produz e
executado fora.

## Confundimento que invalida o contraste, mesmo se o resto fosse corrigido

O braco de controle monta `{}` sobre `settings.json`, o que remove tambem `defaultMode:auto` e 19
regras `allow`. O contraste observado - `full` edita o arquivo, `vanilla` nao - e indistinguivel
de "o braco de controle nao tinha permissao de escrever". Os dois bracos separam 2/2, o que e
consistente com AS DUAS hipoteses. Teste discriminante barato, ainda nao feito: trocar `{}` por
`{"permissions":{"defaultMode":"auto"}}` e reexecutar so `vanilla/unsatisfied`.

## Condicoes para a proxima execucao

Nenhuma execucao nova antes de:
1. o oraculo rodar DENTRO do mesmo namespace, a partir de copia read-only feita ANTES da sessao;
2. a saida da sessao chegar de fato ao classificador (FD separado: `python3 /dev/fd/3 ... 3<<'PY'`);
3. o `rc` do `mount` ser conferido POR CELULA - hoje `2>/dev/null` engole a falha e uma sessao que
   enxergou a politica real seria gravada como `vanilla` (medido: `rc do mount = 32`);
4. `settings.json` do controle preservar permissoes, para separar harness de permissao;
5. caminhos interpolados em `bash -c` passarem por `%q`.

Os dados crus das duas rodadas estao arquivados fora da arvore, nao apagados.
