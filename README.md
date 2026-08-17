# étalon

The reference standard this estate measures itself against. Two things live
here, and they live **only** here:

- **`bin/markdown-cost.sh`** — the prose guard. Prices what a diff adds and
  holds the tree against a ratchet that only falls.
- **`bin/lib/exit-codes.sh`** — the exit vocabulary. `EXIT_BLIND` and friends,
  so the number is one edit rather than twenty-one.

## Using the guard

Six lines in any repo, forever:

```yaml
name: prose
on: [pull_request]
jobs:
  prose:
    uses: hf7y/etalon/.github/workflows/guard.yml@main
```

That is the whole integration. No script is copied, no ratchet is ported, no
credential is needed. Optional inputs: `ratchet` (default `.prose-ratchet`)
and `ref` (default `main` — pin it to freeze a repo against a known étalon).

The **first run seeds** the ratchet from your tree and prints it; commit that
file and the next run has a floor.

## Why this repo exists

`BUILD-DISCIPLINE.md` in hf7y/realisateur records **eleven byte-identical
corrupted copies** of this guard, produced by hand-copying it from repo to
repo. A later port shipped a test suite that could not run, to every repo it
reached, because it copied the test but not the harness it sourced. Another
shipped a ratchet with no CI step reading it.

Every one of those is the same failure: **a guard that has copies has
versions.** Zach, 2026-08-17: *"Can this guard be universal in the ecosystem
and only maintained in one place."*

So: one copy, called by reference. Changing the guard changes it everywhere at
once. There is no port step to forget and no drift to detect, because there is
nothing to drift from.

## Why public

A reusable workflow's *file* travels to the caller, but the repo holding it is
never checked out — so the script has to be fetchable, and `GITHUB_TOKEN` is
scoped to the calling repo. The alternative was distributing a cross-repo
credential to fifteen repos, which is the sprawl hf7y/realisateur#171 exists to
reduce.

This repo holds a lint, its tests, and a list of integers. No host layout, no
account names, no paths, no configuration.

## Per-repo baseline, per-estate guard

The **number** is local — each repo's `.prose-ratchet` is its own floor, seeded
where that repo actually is, so adopting the guard never fails on arrival. The
**measurement** is not local. That split is the point: a shared bar nobody can
meet gets disabled, and a private measurement drifts.

## The exit vocabulary

`bin/lib/exit-codes.sh`. The distinction that carries the weight is **BLIND vs
OK**: *"I looked and found nothing"* and *"I could not look"* are different
answers, and this estate's recorded pathology is the second being reported as
the first. A guard that cannot tell must exit `EXIT_BLIND`, never `EXIT_OK`.
