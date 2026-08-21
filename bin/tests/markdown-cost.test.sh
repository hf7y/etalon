#!/usr/bin/env bash
#
# Usage: bin/tests/markdown-cost.test.sh   (exit 0 = all pass)

set -uo pipefail
# shellcheck source=bin/tests/lib/harness.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/harness.sh"
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/markdown-cost.sh"
[ -x "$SCRIPT" ] || { echo "FAIL: $SCRIPT not executable"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
# has <name> <output> <pattern>   -- output must contain pattern
# hasnt <name> <output> <pattern> -- output must NOT contain pattern
# rc <name> <expected-exit> <actual-exit>

G() { git -c user.email=t@test -c user.name=T -C "$1" "${@:2}"; }

# newrepo <name> -- a repo at $T/<name> with one base commit holding a
# pre-existing code file AND a pre-existing top-level CHANGES.md, so a later
# case can EDIT an existing document (C3) rather than only add one.
newrepo() {
  mkdir -p "$T/$1"
  G "$T/$1" init -q -b main
  printf 'echo base\n' > "$T/$1/base.sh"
  printf 'existing document\n' > "$T/$1/CHANGES.md"
  G "$T/$1" add -A
  G "$T/$1" commit -qm base
}

# lines <path> <n> <word> -- write n distinct lines (distinct so git counts
# them as n added lines, not one)
lines() { local i=1; : > "$2"; while [ "$i" -le "$1" ]; do printf '%s %d\n' "$3" "$i" >> "$2"; i=$((i+1)); done; }

# run <repo> [env...] -- sets RUN_OUT (stdout+stderr) and RUN_RC
run() { local r="$1"; shift; RUN_OUT="$(cd "$T/$r" && "$@" "$SCRIPT" main..HEAD 2>&1)"; RUN_RC=$?; }

echo "markdown-cost.test.sh"

echo "-- A. a code-only diff is free"
newrepo codeonly
lines 40 "$T/codeonly/feature.sh" 'echo line'
G "$T/codeonly" checkout -q -b work
G "$T/codeonly" add -A
G "$T/codeonly" commit -qm feature
run codeonly env
rc   "A1 a code-only diff exits 0"            0 "$RUN_RC"
has  "A2 it reports the ratio it measured"    "$RUN_OUT" "0 of 40 added line(s) are markdown -- 0%"
hasnt "A2 and raises no FLAG"                 "$RUN_OUT" "FLAG ["

echo "-- B. a prose-heavy diff is not"
newrepo prosey
mkdir -p "$T/prosey/docs"
lines 90 "$T/prosey/docs/essay.md" 'a paragraph about the system'
lines 10 "$T/prosey/small.sh" 'echo line'
G "$T/prosey" checkout -q -b work
G "$T/prosey" add -A
G "$T/prosey" commit -qm prose
run prosey env
rc  "B1 a 90%-prose diff exits 1"             1 "$RUN_RC"
has "B2 it names the ratio and threshold"     "$RUN_OUT" "90 of 100 added line(s) are markdown -- 90% (threshold 30%)"
has "B2 it FLAGs the ratio"                   "$RUN_OUT" "FLAG [markdown-ratio]"
has "B3 it names the file that cost it"       "$RUN_OUT" "docs/essay.md:90"

run prosey env MARKDOWN_COST_MAX_PCT=95
rc  "B4 a higher threshold from the env passes the same diff" 0 "$RUN_RC"
has "B4 and the report states the threshold it used"          "$RUN_OUT" "threshold 95%"

# Deletions are free: reaping prose is the behaviour we want, not the one we
# tax. A commit that ONLY removes markdown must not be billed for it.
newrepo reaper
lines 60 "$T/reaper/CHANGES.md" 'an old paragraph'
G "$T/reaper" add -A
G "$T/reaper" commit -qm grow
G "$T/reaper" checkout -q -b work
: > "$T/reaper/CHANGES.md"          # 60 markdown lines deleted, none added
lines 10 "$T/reaper/reaped.sh" 'echo line'
G "$T/reaper" add -A
G "$T/reaper" commit -qm reap
run reaper env
rc  "B5 deleting 60 lines of prose is free"  0 "$RUN_RC"
has "B5 the deletions are not in the count"  "$RUN_OUT" "0 of 10 added line(s) are markdown"

# B6: THE REWRITE-AS-REAP. B5 only covers a diff that adds NO prose. A real
# reap replaces a long stale passage with a short correct one, so it is
# markdown-only and therefore 100% markdown -- over any threshold, forever.
#   [rest: vault:realisateur/guard-archaeology-20260817.md]
newrepo rewriter
lines 200 "$T/rewriter/DOC.md" 'a long stale passage about a retired mechanism'
G "$T/rewriter" add -A
G "$T/rewriter" commit -qm grow
G "$T/rewriter" checkout -q -b work
lines 40 "$T/rewriter/DOC.md" 'the short correct replacement'
G "$T/rewriter" add -A
G "$T/rewriter" commit -qm reap
run rewriter env
rc  "B6 a markdown-only rewrite that nets NEGATIVE passes"  0 "$RUN_RC"
has "B6 and it is reported as a reap, with the net"         "$RUN_OUT" "net prose: -160 line(s)"
hasnt "B6 and raises no ratio FLAG"                         "$RUN_OUT" "FLAG [markdown-ratio]"

# B6b: THE PRODUCER FIX (#287). #187 makes a reap incomplete until it also
# repoints the command file that WROTE the surface being deleted, and that
# edit adds a net line or two. Under a one-line "grew" trigger the mandatory
#   [rest: vault:realisateur/guard-archaeology-20260817.md]
newrepo producer
mkdir -p "$T/producer/.claude/commands"
lines 200 "$T/producer/DOC.md" 'a retired prose surface'
lines 10 "$T/producer/.claude/commands/nightly.md" 'write DOC.md every night'
G "$T/producer" add -A
G "$T/producer" commit -qm seed
G "$T/producer" checkout -q -b work
lines 5 "$T/producer/DOC.md" 'see the issue tracker'
lines 12 "$T/producer/.claude/commands/nightly.md" 'file an issue every night'
G "$T/producer" add -A
G "$T/producer" commit -qm reap
run producer env
rc  "B6b a reap whose producer fix nets +2 still passes" 0 "$RUN_RC"
has "B6b and is reported as a reap"  "$RUN_OUT" "a reap, not a cost."

# The exemption is self-limiting: prose that GROWS still pays, even though
# this diff also deletes. Otherwise "delete a line, add a hundred" would buy
# an exemption, which is the same dodge inverted.
newrepo grower
lines 20 "$T/grower/DOC.md" 'a short passage'
G "$T/grower" add -A
G "$T/grower" commit -qm seed
G "$T/grower" checkout -q -b work
lines 150 "$T/grower/DOC.md" 'a much longer passage that replaced it'
G "$T/grower" add -A
G "$T/grower" commit -qm grow
run grower env
rc  "B7 a markdown-only rewrite that nets POSITIVE still exits 1" 1 "$RUN_RC"
has "B7 and still FLAGs the ratio"  "$RUN_OUT" "FLAG [markdown-ratio]"

# B8: THE LAUNDERING CASE. Netting repo-wide is not enough on its own --
# deleting one obsolete document buys room for a brand-new essay somewhere
# else, and the total still reads negative. Found by fixture against the
# exemption's own first version, before it had shipped a week. So the test is
# per FILE as well as in total: no markdown file may grow.
newrepo launderer
mkdir -p "$T/launderer/docs"
lines 300 "$T/launderer/docs/OLD.md" 'an obsolete paragraph'
G "$T/launderer" add -A
G "$T/launderer" commit -qm seed
G "$T/launderer" checkout -q -b work
rm "$T/launderer/docs/OLD.md"
lines 250 "$T/launderer/docs/NEW.md" 'a brand new essay line'
G "$T/launderer" add -A
G "$T/launderer" commit -qm launder
run launderer env
rc  "B8 a big delete does NOT buy a big new document elsewhere" 1 "$RUN_RC"
has "B8 and the grown file is named"  "$RUN_OUT" "docs/NEW.md:+250"
has "B8 and it says why this is not a reap"  "$RUN_OUT" "these grew, so this is not a reap"

echo "-- C. a new top-level document"
newrepo newroot
lines 50 "$T/newroot/big.sh" 'echo line'
printf 'a brand new root document\n' > "$T/newroot/PLAN-2026-08-07.md"
G "$T/newroot" checkout -q -b work
G "$T/newroot" add -A
G "$T/newroot" commit -qm addroot
run newroot env
rc  "C1 a new top-level .md exits 1 even at a low ratio" 1 "$RUN_RC"
has "C2 it names the document"       "$RUN_OUT" "FLAG [new-root-document]"
has "C2 by path"                     "$RUN_OUT" "PLAN-2026-08-07.md"
has "C2 and prints the allowlist"    "$RUN_OUT" "allowlist: README.md CLAUDE.md CONTRACT.md GAPS.md man/*"

# C3: editing the document that was already there is how a record stays
# current. It must cost nothing beyond the ratio.
newrepo editroot
G "$T/editroot" checkout -q -b work
printf 'one more line\n' >> "$T/editroot/CHANGES.md"
lines 50 "$T/editroot/more.sh" 'echo line'
G "$T/editroot" add -A
G "$T/editroot" commit -qm edit
run editroot env
rc    "C3 EDITING an existing top-level .md exits 0" 0 "$RUN_RC"
hasnt "C3 and is not a new root document"            "$RUN_OUT" "FLAG [new-root-document]"

# C4: a new .md inside a directory is a document with a home. Only the ROOT is
# rationed.
newrepo nesteddoc
mkdir -p "$T/nesteddoc/notes"
printf 'a nested note\n' > "$T/nesteddoc/notes/thing.md"
lines 50 "$T/nesteddoc/more.sh" 'echo line'
G "$T/nesteddoc" checkout -q -b work
G "$T/nesteddoc" add -A
G "$T/nesteddoc" commit -qm nested
run nesteddoc env
rc    "C4 a new .md under a directory exits 0" 0 "$RUN_RC"
hasnt "C4 and is not a new root document"      "$RUN_OUT" "FLAG [new-root-document]"

echo "-- D. the allowlist (one list, both checks)"
# D1: CLAUDE.md is the project's own front door. Adding it must not be
# rationed -- this is the new-root-document call site reading the allowlist.
newrepo allowroot
printf 'project instructions\n' > "$T/allowroot/CLAUDE.md"
lines 50 "$T/allowroot/more.sh" 'echo line'
G "$T/allowroot" checkout -q -b work
G "$T/allowroot" add -A
G "$T/allowroot" commit -qm claude
run allowroot env
rc    "D1 a NEW allowlisted root document exits 0" 0 "$RUN_RC"
hasnt "D1 and raises no FLAG at all"               "$RUN_OUT" "FLAG ["

# D1b: the two the bashify skeleton writes. A repo converting to `bashified`
# adds both, named by the skeleton rather than chosen, so flagging them made
# every conversion PR unmergeable (hf7y/gardien#59).
newrepo allowskel
printf 'the contract\n' > "$T/allowskel/CONTRACT.md"
printf 'the gaps\n' > "$T/allowskel/GAPS.md"
lines 50 "$T/allowskel/more.sh" 'echo line'
G "$T/allowskel" checkout -q -b work
G "$T/allowskel" add -A
G "$T/allowskel" commit -qm skeleton
run allowskel env
rc    "D1b the skeleton's own root documents exit 0" 0 "$RUN_RC"
hasnt "D1b and raise no new-root-document FLAG" "$RUN_OUT" "FLAG [new-root-document]"

# D2: the ratio's call site reads the SAME list. 90 lines of README.md would be
# a 90% prose diff if the allowlist were only consulted by the other check.
newrepo allowratio
G "$T/allowratio" checkout -q -b work
lines 90 "$T/allowratio/README.md" 'how to use this'
lines 10 "$T/allowratio/small.sh" 'echo line'
G "$T/allowratio" add -A
G "$T/allowratio" commit -qm readme
run allowratio env
rc    "D2 90 lines of README.md are not priced as prose" 0 "$RUN_RC"
has   "D2 and the numerator really was zero"             "$RUN_OUT" "0 of 100 added line(s) are markdown"

# D3: man/ at any depth.
newrepo allowman
mkdir -p "$T/allowman/man/verbs"
lines 90 "$T/allowman/man/verbs/thing.md" 'the manual page'
lines 10 "$T/allowman/small.sh" 'echo line'
G "$T/allowman" checkout -q -b work
G "$T/allowman" add -A
G "$T/allowman" commit -qm man
run allowman env
rc    "D3 anything under man/ is allowlisted" 0 "$RUN_RC"

echo "-- E. it must never answer 'found nothing' with exit 0"
newrepo unresolvable
G "$T/unresolvable" checkout -q -b work
printf 'echo x\n' >> "$T/unresolvable/base.sh"
G "$T/unresolvable" add -A
G "$T/unresolvable" commit -qm x
RUN_OUT="$(cd "$T/unresolvable" && "$SCRIPT" no-such-ref..HEAD 2>&1)"; RUN_RC=$?
rc  "E1 an unresolvable range exits 2, not 0" 2 "$RUN_RC"
has "E2 and says which range it could not read" "$RUN_OUT" "cannot read the diff for 'no-such-ref..HEAD'"

mkdir -p "$T/notarepo"
RUN_OUT="$(cd "$T/notarepo" && "$SCRIPT" 2>&1)"; RUN_RC=$?
rc  "E3 outside a git repository exits 2" 2 "$RUN_RC"
has "E3 and says so"                      "$RUN_OUT" "not inside a git repository"

RUN_OUT="$(cd "$T/unresolvable" && MARKDOWN_COST_MAX_PCT=lots "$SCRIPT" main..HEAD 2>&1)"; RUN_RC=$?
rc  "E4 a non-numeric threshold exits 2, not silently 30%" 2 "$RUN_RC"
has "E4 and names the value it rejected"                   "$RUN_OUT" "got 'lots'"

RUN_OUT="$(cd "$T/unresolvable" && "$SCRIPT" main..HEAD extra 2>&1)"; RUN_RC=$?
rc  "E5 a second positional argument exits 2" 2 "$RUN_RC"

echo "-- F. comments in files that are not markdown"

newrepo commenter
G "$T/commenter" checkout -q -b work
{ printf '#!/usr/bin/env bash\n'
  for i in $(seq 1 200); do printf '# an explanatory line number %d\n' "$i"; done
  for i in $(seq 1 10); do printf 'code_%d=1\n' "$i"; done; } > "$T/commenter/tool.sh"
G "$T/commenter" add -A
G "$T/commenter" commit -qm header
run commenter env
rc  "F1 200 comment lines at 95% of a .sh exits 1"  1 "$RUN_RC"
has "F1 and FLAGs the comment ratio"  "$RUN_OUT" "FLAG [comment-ratio]"
has "F1 and names the file"           "$RUN_OUT" "tool.sh:200"
hasnt "F1 and does NOT call it a markdown-ratio problem" "$RUN_OUT" "FLAG [markdown-ratio]"

newrepo diluted
G "$T/diluted" checkout -q -b work
{ printf '#!/usr/bin/env bash\n'
  for i in $(seq 1 200); do printf '# an explanatory line number %d\n' "$i"; done
  for i in $(seq 1 400); do printf 'code_%d=1\n' "$i"; done; } > "$T/diluted/tool.sh"
G "$T/diluted" add -A
G "$T/diluted" commit -qm mostly-code
run diluted env
rc  "F2 the same 200 comment lines at 33% exits 0"  0 "$RUN_RC"
hasnt "F2 and raises no comment FLAG"  "$RUN_OUT" "FLAG [comment-ratio]"

newrepo dense
G "$T/dense" checkout -q -b work
{ for i in $(seq 1 60); do printf '# setting %d\n' "$i"; done; } > "$T/dense/x.conf"
G "$T/dense" add -A
G "$T/dense" commit -qm small
run dense env
rc  "F3 60 comment lines at 100% is under the floor, exits 0" 0 "$RUN_RC"

newrepo museum
G "$T/museum" checkout -q -b work
mkdir -p "$T/museum/residue"
{ printf '#!/usr/bin/env bash\n'
  for i in $(seq 1 200); do printf '# a retired explanation %d\n' "$i"; done; } > "$T/museum/residue/old.sh"
G "$T/museum" add -A
G "$T/museum" commit -qm retired
run museum env
rc  "F4 the same header under residue/ exits 0" 0 "$RUN_RC"

echo "-- G. the tree ratchet"

newrepo ratchet
export MARKDOWN_COST_RATCHET="$T/ratchet/.ratchet"
{ printf '#!/usr/bin/env bash\n'; for i in $(seq 1 50); do printf '# line %d\n' "$i"; done; } > "$T/ratchet/tool.sh"
G "$T/ratchet" add -A
G "$T/ratchet" commit -qm seed
RUN_OUT="$(cd "$T/ratchet" && "$SCRIPT" --census 2>&1)"; RUN_RC=$?
rc  "G1 a census with no baseline exits 2, never 0" 2 "$RUN_RC"
has "G1 and says a missing baseline is not a pass" "$RUN_OUT" "not a pass"

RUN_OUT="$(cd "$T/ratchet" && "$SCRIPT" --accept 2>&1)"; RUN_RC=$?
rc  "G2 --accept seeds the baseline" 0 "$RUN_RC"
has "G2 and reports the number it recorded" "$RUN_OUT" "51 prose line(s)"

{ printf '#!/usr/bin/env bash\n'; for i in $(seq 1 90); do printf '# line %d\n' "$i"; done; } > "$T/ratchet/tool.sh"
RUN_OUT="$(cd "$T/ratchet" && "$SCRIPT" --census 2>&1)"; RUN_RC=$?
rc  "G3 a tree that grew past the baseline exits 1" 1 "$RUN_RC"
has "G3 and FLAGs the ratchet"       "$RUN_OUT" "FLAG [prose-ratchet]"
has "G3 and says how far it rose"    "$RUN_OUT" "gained 40 prose line(s)"

{ printf '#!/usr/bin/env bash\n'; for i in $(seq 1 20); do printf '# line %d\n' "$i"; done; } > "$T/ratchet/tool.sh"
RUN_OUT="$(cd "$T/ratchet" && "$SCRIPT" --census 2>&1)"; RUN_RC=$?
rc  "G4 a tree that shrank exits 0" 0 "$RUN_RC"
has "G4 and invites locking the reduction in" "$RUN_OUT" "run --accept to lock it in"

# G5/G6. The ratchet only falls, and BOTH doors are shut: --accept cannot
# re-accept upward, and a hand edit that raises the number is rejected by
# --census. The hand-raise used to be advertised in the FLAG itself, and was
# taken twice on 2026-08-15 -- both times inside a PR that merged itself.
{ printf '#!/usr/bin/env bash\n'; for i in $(seq 1 90); do printf '# line %d\n' "$i"; done; } > "$T/ratchet/tool.sh"
RUN_OUT="$(cd "$T/ratchet" && "$SCRIPT" --accept 2>&1)"; RUN_RC=$?
rc  "G5 --accept refuses to raise the baseline" 1 "$RUN_RC"
has "G5 and says so out loud"        "$RUN_OUT" "REFUSED"
has "G5 and names the reap instead"  "$RUN_OUT" "Reap prose instead"

# G6 needs a real merge base, because that is what the check compares against.
G6="$T/g6"; mkdir -p "$G6" && (
  cd "$G6" && git init -q -b main .
  git config user.email t@t.invalid && git config user.name t
  printf '#!/usr/bin/env bash\n# one\n' > tool.sh
  printf '# r\n100\n' > .ratchet
  git add -A && git commit -qm base
  git update-ref refs/remotes/origin/main HEAD
  printf '# r\n999\n' > .ratchet
)
RUN_OUT="$(cd "$G6" && MARKDOWN_COST_RATCHET="$G6/.ratchet" "$SCRIPT" --census 2>&1)"; RUN_RC=$?
rc  "G6 a hand-raised baseline is rejected" 1 "$RUN_RC"
has "G6 and names both numbers"   "$RUN_OUT" "RAISES the baseline from 100 to 999"
has "G6 and offers no override"   "$RUN_OUT" "there is no override"
unset MARKDOWN_COST_RATCHET

echo
summary
[ "$fail" -eq 0 ] || exit 1
