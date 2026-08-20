#!/usr/bin/env bash
# exit-codes.sh -- the estate's exit vocabulary, defined once.
#
# The number lives here and nowhere else. A script says `exit "$EXIT_BLIND"`,
# and changing what BLIND means is one edit in this file. The values are the
# verb ladder's, so a caller switching on a code reads one vocabulary.
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
#      Verbs have no equivalent: a verb keeps its promise or does not.
: "${EXIT_FINDING:=1}"

# 2 -- the CALLER is wrong: unknown flag, missing argument, bad value.
#      Distinct from a finding, because nothing was measured.
: "${EXIT_USAGE:=2}"

# 3 -- NEEDS-SUMMON. Contracted here, no mechanism behind it yet, and no
#      spend was authorised. A FINDING, not an error: the tool prints the
#      summon it would have made and costs nothing.
: "${EXIT_NEEDS_SUMMON:=3}"

# 4 -- GAP. SHOULD DO: in scope, not built yet. A TEMPORAL claim, and an
#      invitation -- summon, or do it by hand and mechanize it. GAPS.md is
#      its sink and those entries are meant to DRAIN.
: "${EXIT_GAP:=4}"

# 5 -- BROKEN. It ran and produced a wrong or partial answer. The tool
#      exists; it failed.
: "${EXIT_BROKEN:=5}"

# 6 -- BLIND. The guard could not perform its measurement: no repository, an
#      unreadable range, an unreachable API, a registry that is not present.
#      NEVER report this as clean. It is the whole reason this file exists.
: "${EXIT_BLIND:=6}"

# 7 -- REFUSED. WON'T DO: out of scope on principle, not unbuilt. A claim
#      about SCOPE where 4 is a claim about TIME. Filing a refusal as a gap
#      puts a permanent decision on a to-do list and stops GAPS.md being a
#      list that can drain, which destroys it as a signal.
#
#      The rule that keeps 4 and 7 honest: --summon is available on 4 and
#      FORBIDDEN on 7. A gap names its own escalation; a refusal offers none,
#      because having no escalation path is what refusing on principle MEANS
#      (hf7y/realisateur#373).
: "${EXIT_REFUSED:=7}"

# 8 and above -- project-specific, documented in that tool's EXIT STATUS,
# never a redefinition of one of the above. ecosim's `sonde` is the worked
# example: 8 WARN, 9 CRIT, on top of this vocabulary rather than beside it.

export EXIT_OK EXIT_FINDING EXIT_USAGE EXIT_NEEDS_SUMMON EXIT_GAP \
       EXIT_BROKEN EXIT_BLIND EXIT_REFUSED
