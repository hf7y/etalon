# canon/ — artifacts etalon hosts for the estate

Everything here is a file **another repo runs** and etalon merely holds the one
true copy of. It is not etalon's own mechanism and not etalon's own prose, so
`bin/markdown-cost.sh` and `bin/state-prose-lint.sh` both skip this directory:
pricing it would charge this repo for text it must not edit, since the whole
point is byte identity with what ships.

## verb.sh

The shared runtime every bashified verb sources — the exit vocabulary
(`verb_gap` 4, `verb_broke` 5, `verb_blind` 6, `verb_refuse` 7), the `--summon`
spending rule, and the flag parsing. Its own header states the promise: it
exists *"so nineteen utilities cannot drift into nineteen dialects."*

It is sourced, not called, so it cannot be depended on remotely — `source`
needs a local file. Nine repos each carry a physical copy on their `bashified`
branch, and hf7y/realisateur#393 measured what that produced: every runtime
that could be checked had drifted, and most could not be checked at all.

These are the canonical bytes, chosen by measurement rather than by preference:
of the eight runtimes in the shipped build on monkey, six are byte-identical at
277 lines — bibliothecaire, ecosim, realisateur, scheduler, senechal,
vim-arcade. crt ships 124 lines and gardien 147.

`guard.yml`'s `runtime` job compares a calling repo's copy to this one and
fails the PR if they differ. Take this copy rather than editing yours.

## Why the gate is a job in `guard.yml`, not its own workflow

`bin/mechanism-budget.sh` prices a new workflow file as a mechanism and asks
two retirements for it. A six-line byte comparison does not deserve that, and
the budget was right to refuse it — so the check is a second job in a workflow
that already exists. Callers turn it on with `runtime: true`.

Could-not-look is never a pass there. A missing canonical copy, or a missing
copy in the calling repo, fails the job rather than reporting "identical" —
that substitution is the exact failure `bin/lib/exit-codes.sh` exists to name.
