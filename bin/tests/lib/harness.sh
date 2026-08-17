#!/usr/bin/env bash
# tests/lib/harness.sh -- the six lines 51 of 54 suites re-declare, in two
# whitespace spellings and 18 summary formats. run-suites.sh reads exit codes
# and ignores all of it, which is why it drifted unnoticed.
#
#   . "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/harness.sh"
#   harness_tmp                       # sets $T, removes it on exit
#   section "A. the thing"
#   ok "A1 it worked"; eq "A2" "$got" "$want"; has "A3" "$out" needle
#   summary                           # returns nonzero if anything failed

pass=0; fail=0

section() { printf '\n%s\n' "$*"; }
ok()      { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad()     { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; return 0; }

eq()    { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$3] got [$2]"; fi; }
# rc is (label, WANT, GOT) -- the order all 54 suites already call it with.
# eq is (label, GOT, WANT). They disagree, and that is the existing
# convention, not an improvement to make while converting 51 files.
rc()    { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want exit $2, got $3"; fi; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing: $3" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "present but should not be: $3" ;; *) ok "$1" ;; esac; }

summary() {
  printf '\n%s: %d passed, %d failed\n' "${0##*/}" "$pass" "$fail"
  [ "$fail" -eq 0 ]
}

# Sets $T; must be called bare. `T="$(harness_tmp)"` runs it in a subshell
# where the EXIT trap fires immediately and deletes the directory.
harness_tmp() {
  T="$(mktemp -d)" || { echo "harness: cannot mktemp -- refusing to run blind" >&2; exit 2; }
  # shellcheck disable=SC2064  # expanded now: remove the dir this call made
  trap "rm -rf '$T'" EXIT
}
