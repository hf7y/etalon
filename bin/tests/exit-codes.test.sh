#!/usr/bin/env bash
# exit-codes.test.sh -- the vocabulary is defined once, and every name is distinct.
#
# The property worth pinning is not the NUMBERS -- those may be changed, which
# is the whole point of the file. It is that BLIND has a name, that the names
# do not collide, and that OK and BLIND can never become the same value, since
# reporting could-not-look as clean is the failure the file exists against.
set -uo pipefail
# shellcheck source=bin/tests/lib/harness.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/harness.sh"

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/exit-codes.sh"
printf 'exit-codes.sh\n'

[ -r "$LIB" ] && ok "A1 the library exists and is readable" \
              || bad "A1 the library exists and is readable" "$LIB"

# shellcheck source=/dev/null
. "$LIB"

for n in EXIT_OK EXIT_FINDING EXIT_USAGE EXIT_BLIND EXIT_REFUSED; do
  if [ -n "${!n+set}" ]; then ok "B1 $n is defined"; else bad "B1 $n is defined"; fi
  case "${!n:-x}" in
    ''|*[!0-9]*) bad "B2 $n is a whole number" "${!n:-unset}" ;;
    *)           ok  "B2 $n is a whole number" ;;
  esac
done

# C -- OK and BLIND must never coincide. This is the load-bearing one.
if [ "$EXIT_OK" != "$EXIT_BLIND" ]; then
  ok "C1 OK and BLIND are different -- could-not-look cannot read as clean"
else
  bad "C1 OK and BLIND are different" "both are $EXIT_OK"
fi

# D -- every name distinct, so a caller switching on the code can tell them apart.
dupes="$(printf '%s\n' "$EXIT_OK" "$EXIT_FINDING" "$EXIT_USAGE" "$EXIT_BLIND" "$EXIT_REFUSED" \
  | sort | uniq -d | tr '\n' ' ')"
[ -z "$dupes" ] && ok "D1 all five codes are distinct" \
                || bad "D1 all five codes are distinct" "repeated: $dupes"

# E -- the caller's environment wins, so a repo may retarget without editing
#      this file. `: "${VAR:=default}"` is what makes that true.
out="$(EXIT_BLIND=9 bash -c '. "$1"; printf %s "$EXIT_BLIND"' _ "$LIB")"
eq "E1 a preset value is honoured, not overwritten" "$out" "9"

# F -- sourcing prints nothing. A library that chatters breaks any caller
#      capturing stdout, and every consumer here is a guard that does.
noise="$(. "$LIB" 2>/dev/null)"
[ -z "$noise" ] && ok "F1 sourcing is silent on stdout" \
                || bad "F1 sourcing is silent on stdout" "$noise"

summary
[ "$fail" -eq 0 ]
