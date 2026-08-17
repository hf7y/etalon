#!/usr/bin/env bash
# exit-codes.sh -- the estate's exit vocabulary, defined once.
#
# WHY THIS FILE EXISTS. Measured across hf7y/realisateur's bin/ on 2026-08-17,
# THREE different codes were live for the SAME condition -- a guard that could
# not look:
#
#   exit 2  hardcoded-home-lint, no-worktree-lint, ownership-audit,
#           path-provenance-audit, precipitation-scan, repo-settings-provision,
#           run-suites, served-not-cloned, shellcheck-lint
#   exit 3  carry-drift, install-verb-build, pivot, reach-lint, release-ledger,
#           selfdev-release-tick, silence-audit, verbs-refresh
#   exit 6  claim-drift, closeout-lint, floor-check, gh-sign
#
# Zach, 2026-08-17: "Anything that requires 21 scripts to change should not; it
# should be changeable in one place. That is an obvious drift liability."
#
# So the NUMBER lives here and nowhere else. A script says `exit "$EXIT_BLIND"`,
# and changing what BLIND means is one edit in this file.
#
# THE DISTINCTION THAT MATTERS MOST is BLIND vs OK. "I looked and found
# nothing" and "I could not look" are different answers, and this estate's
# recorded pathology is the second being reported as the first -- a survey
# reaching zero projects and printing a tidy summary, a lint auditing an empty
# temp repo and exiting 0. A guard that cannot tell must exit BLIND, never OK.
#
# USAGE
#   . "$(dirname "${BASH_SOURCE[0]}")/exit-codes.sh"
#   ... || exit "$EXIT_BLIND"
#
# The values are deliberately NOT the sh convention for signals (128+n) and
# stop below 64, which is where sysexits.h begins; nothing here needs to
# coexist with sendmail.

# 0 -- the question was asked, and the answer is no findings.
: "${EXIT_OK:=0}"

# 1 -- the guard looked and FOUND something. A real finding, reported.
: "${EXIT_FINDING:=1}"

# 2 -- the CALLER is wrong: unknown flag, missing argument, bad value.
#      Distinct from a finding, because nothing was measured.
: "${EXIT_USAGE:=2}"

# 3 -- BLIND. The guard could not perform its measurement: no repository, an
#      unreadable range, an unreachable API, a registry that is not present.
#      NEVER report this as clean. It is the whole reason this file exists.
: "${EXIT_BLIND:=3}"

# 4 -- REFUSED. The guard could look, and declines to act on principle rather
#      than on a finding. A refusal is permanent; a BLIND is a condition that
#      may clear. Keeping them apart is what stops a "will not" being filed as
#      a "not yet" (hf7y/realisateur#373).
: "${EXIT_REFUSED:=4}"

export EXIT_OK EXIT_FINDING EXIT_USAGE EXIT_BLIND EXIT_REFUSED
