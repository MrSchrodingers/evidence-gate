# Skill invocation policy

Status: **CANDIDATE — depends on CI/merge**  
Date: 2026-08-25  
Related: #33

## Principle

The target is not to maximize how many Skills get used. It is to maximize correct selection and marginal utility.

```text
INSTALLED != TRIGGERED != USEFUL
```

A rare Skill may be correct if eligible tasks are rare. Forcing usage turns routing into ritual.

## Side effects

Workflows that mutate external state and whose timing should remain user-controlled are manual-only. Claude Code represents this with:

```yaml
disable-model-invocation: true
```

The flag also removes the Skill description from automatic context, reducing both accidental triggering surface and context cost for manual workflows.

### Current decision

`prd-to-issues` contains `gh issue create` and creates remote GitHub state. It becomes manual-only.

This decision is **not** generalized by analogy to every other Skill. `graphify`, for example, remains eligible for automatic routing while routing/utility are evaluated.

### G102 (issue #46) — the graphify exception now lives in the policy artifact

Before this fix, `orchestration/skill-policy.json` carried a `default_activation` field with no
operational definition and no consumer: no executable in the repository read it to decide
anything, and the one assertion that cited it reopened the same JSON and compared it against
the literal it contains. `orchestration/registry.json` declared `capabilities.*.activation`
with nothing checking it against the Skills' actual frontmatter — it had already diverged in 3
of 8 (`depreciar`, `forge`, `prd-to-issues` said `contextual` while each `SKILL.md` carries
`disable-model-invocation: true`), with nothing turning red.

The fix:

1. `skill-policy.json` gains an `activation` block with `default`, `vocabulary` (closed enum
   `["manual", "contextual"]`), `mechanism` (the frontmatter key that produces each value), and
   `model_invocable_exceptions` — the list, with a `reason` per item, of the Skills that remain
   eligible for automatic routing. The `graphify` exception stops living only in the test's
   negative control and is now declared here.
2. `registry.json` corrected in the 3 entries that contradicted their own frontmatter.
3. `tests/unit/skill-invocation-policy.sh` compares, for every Skill, the value declared in
   `registry.json` against the one derived from frontmatter, requires every contextual Skill to
   have an entry in `model_invocable_exceptions` with a non-empty `reason`, and rejects any
   `activation` value outside the closed vocabulary.

DECLARED LIMIT, and it is what prevents overclaim: this closes `PolicyDeclared !=
PolicyEnforced` at the ARTIFACT layer — the three records (policy, registry, frontmatter) now
agree with each other. This does **not measure E_A**: it does not observe whether the runtime
actually routed to, or away from, a Skill. Reading this as proof of activation would repeat the
ADR 0036 defect (G6a) — representation of the mechanism is not the phenomenon.

### G106 (issue #50) — effect is a dimension independent of activation, and now has to be declared

The G102 fix closed `activation.registry != frontmatter`, but said nothing about WHAT a Skill
does. `write-a-prd` published `gh issue create` in its body — a remote write — while
`activation.model_invocable_exceptions` justified it with "local and reversible effect", never
checked by any executable. The same configuration (consistent activation,
`model_invocable_exceptions` with a non-empty `reason`) was satisfied by any "contextual + any
body" pair, including one containing `gh issue create`: `PolicyDeclared` without
`PolicyEnforced`, now on the EFFECT dimension instead of the activation one.

The fix:

1. `skill-policy.json` gains an `effects` block — a sibling of `activation`, because it is a
   different dimension — with `vocabulary` (closed enum `["pure", "local-write", "remote-write",
   "destructive"]`) and `by_skill` (skill → effect map, one entry per directory under
   `execution/skills/`).
2. The new invariant: `effect in {remote-write, destructive} => activation != contextual`,
   checked with the activation side coming from the FRONTMATTER on disk (not from the policy) —
   two independent files, the same pattern the G102 assertion already uses.
3. Syntactic detectors (`gh issue create`, `gh pr create`, `gh api`, `git push`, `curl -X
   POST|PUT|PATCH|DELETE`, `http(x).post|put|patch|delete(`, `aws s3 cp`) enter as an
   INCONSISTENCY CONTROL, never as the definition of the class: matching a pattern with a
   declared effect BELOW `remote-write` fails. The precise reading of the criterion is "below
   `remote-write`", not "declared `pure`" — `gh issue create` in a `local-write` skill is
   equally a remote write that the local effect does not cover.
4. The ASYMMETRY, which has to survive any future extension: the ABSENCE of any syntactic
   pattern NEVER promotes a skill to `pure`. Absence of a string is absence of syntactic
   evidence, not evidence of absence of effect. Only the human declaration in `by_skill` defines
   the class; the detector can only aggravate it.
5. `write-a-prd` was fixed via the path the issue prefers: drafting the PRD now saves it locally
   (`./prds/<slug>.md`, mirroring `/prd-to-plan`), and the remote publish (`gh issue create`) was
   moved to `/prd-to-issues` (already manual-only). `write-a-prd` remains `contextual` — it
   stopped being false because the effect stopped being remote, not because the check was
   weakened.

DECLARED LIMIT, and it is exactly what issue #50 already named: a mutant that only dies because
of the NAME ("write-a-prd") or the LITERAL ("gh issue create") would prove the repro, not the
predicate. The mutation harness registers a fictitious skill with a different name and a
different remote-write form (`publicar-relatorio`, `curl -X POST`), consistent on every other
dimension, and checks that it dies by the MESSAGE of the inconsistency block — not merely by
exit code.

## E_A — activation evaluation

For model-invocable Skills, measure separately:

```text
TriggerRecall    = TP / (TP + FN)
TriggerPrecision = TP / (TP + FP)
UtilityDelta     = Q_with - Q_without
CostDelta        = tokens/latency_with - baseline
```

Development and held-out trigger prompts must be separate. Editing a description until it passes the prompts used to write it and calling that “better routing” is overfitting.

## What this PR proves

The narrow oracle protects only two current decisions:

1. the known Skill that executes `gh issue create` is manual-only;
2. `graphify` was not disabled as a collateral blanket fix.

It does not attempt to semantically infer every possible side effect using regex.

## Limits

- manual-only does not establish internal implementation safety;
- manual-only does not establish utility;
- automatic routing of other Skills remains NOT_VERIFIED until #33 experiments it;
- a local/temporary side effect is not automatically equivalent to an irreversible remote side effect.
