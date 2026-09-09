# tollens — Claude Code

O workflow acionado por classe de risco é declarado em `orchestration/risk-policy.json`, não nesta frase - ver ADR 0043 e `docs/architecture/orquestracao-multirruntime.md`. Leitura pode ser paralela; escrita é serializada. `tdd` precede `implementador`; revisão e refutação são independentes. O estado local máximo é `CANDIDATE`; somente `verify-pr` no SHA autoriza merge. Lacuna é `NOT_VERIFIED`.
