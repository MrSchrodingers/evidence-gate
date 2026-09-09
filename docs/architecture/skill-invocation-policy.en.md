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
