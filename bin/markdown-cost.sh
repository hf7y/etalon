#!/usr/bin/env bash
# markdown-cost.sh -- give prose a price.
#
# RUNNER: .github/workflows/tests.yml
# GUARD-TEST: bin/tests/markdown-cost.test.sh
# GATE: none -- its range is a merge-base against origin/main, which a fixture repo with no origin cannot form; its suite builds a throwaway repo per case instead
#
# TRAPS (the rest of this header is in the vault):
# THE ONE BUG IT MUST NOT HAVE. In this ecosystem "found nothing" has
# repeatedly been reported as "nothing is wrong" -- a survey that reached zero
# projects printing a tidy summary and exiting 0 (see bin/lib/conf.sh's header
# for the propagation case that reached NOBODY). So every path here that cannot
# resolve the range, cannot read the diff, or cannot classify a file exits 2 and
# says which. Exit 0 from this script means one specific thing: the diff was
# read, the added lines were counted, and the count came in under the price.
# It never means the script could not tell.
#

set -uo pipefail

CLI_NAME='markdown-cost.sh'
CLI_SUMMARY='what fraction of this branch is prose, and did it add another root document?'
CLI_USAGE='  markdown-cost.sh            price $(git merge-base HEAD origin/main)..HEAD
  markdown-cost.sh <range>    price an explicit range, e.g. main..HEAD
  markdown-cost.sh --census   count prose in the TREE against bin/markdown-cost.ratchet
  markdown-cost.sh --accept   record the current tree count as the baseline
  markdown-cost.sh --count-docstrings <file.py>
                              print the docstring prose lines in one file, so
                              the heuristic can be checked against Python ast'
CLI_FLAGS='--census --accept --count-docstrings'
CLI_EXITS='  0  the diff was read and priced, and it came in under the threshold
  1  over the markdown ratio, it adds a new top-level *.md file, or the tree
     rose above the prose ratchet
  2  the range could not be resolved, the diff could not be read, or a file
     could not be classified -- NEVER "I looked and found nothing"'
CLI_POSITIONAL=any
. "$(dirname "${BASH_SOURCE[0]}")/lib/cli-guard.sh"
cli_guard "$@"

# --- the allowlist, in ONE place ---------------------------------------------
# Both call sites read it here; retyping it per site is how they drift apart.
#   [rest: vault:realisateur/guard-archaeology-20260817.md]
MD_ALLOW=( 'README.md' 'CLAUDE.md' 'CONTRACT.md' 'GAPS.md' 'man/*' '.claude/commands/*' )

md_allowlisted() { # <path> -> 0 if the allowlist covers it
  local pat
  for pat in "${MD_ALLOW[@]}"; do
    # shellcheck disable=SC2254 # the pattern is meant to glob
    case "$1" in $pat) return 0 ;; esac
  done
  return 1
}

md_is_markdown() { # <path> -> 0 if prose_lang prices this file as markdown
  [ "$(prose_lang "$1")" = m ]
}

md_is_top_level() { # <path> -> 0 if the path has no directory component
  case "$1" in */*) return 1 ;; *) return 0 ;; esac
}

# --- what language is a file's prose written in? ------------------------------
# ONE predicate, read by the census, the diff check and md_is_markdown, so none
# can disagree. A trailing SCAFFOLDING suffix is not a language: a .md.template
# is markdown waiting to be COPIED, which is how prose multiplies -- #18 found
# a 7.5 KB one free to keep, free to copy, and worth nothing when deleted.
# Only suffixes this estate uses; a bare foo.template is not guessed at.
prose_lang() { # <path> -> 'h', 'j', 'm', 'p', or empty for a file we do not price
  local f="$1"
  case "$f" in *.template|*.tmpl|*.example|*.in) f="${f%.*}" ;; esac
  case "$f" in
    *.md|*.markdown)                       printf 'm' ;;
    *.sh|*.bash|*.conf|*.yml|*.yaml)       printf 'h' ;;
    *.py)                                  printf 'p' ;;
    *.mjs|*.js)                            printf 'j' ;;
    *)                                     : ;;
  esac
}

prose_excluded() { # <path> -> 0 if no rule should grade this file
  case "$1" in residue/*|*/residue/*|canon/*|*/canon/*) return 0 ;; esac
  return 1
}

# is_comment <lang> <line> -> 0 if this line is prose. Callers skip blanks.
is_comment() {
  local s="$2"
  s="${s#"${s%%[![:space:]]*}"}"     # strip leading whitespace
  case "$1" in
    h|p) case "$s" in '#!'*) return 1 ;; '#'*) return 0 ;; esac ;; # '#!' is a directive
    j) case "$s" in '//'*|'/*'*|'*'*) return 0 ;; esac ;;
  esac
  return 1
}

# --- Python docstrings are prose, and used not to be ------------------------
# Unit 2's case, the same shape as the scaffolding gap above: wtul#73 reaped
# module docstrings and this census never moved.
#
# A docstring is a triple-quoted block that BEGINS its line (so `SQL = """..."""`
# stays data, not prose) and sits in first-statement position: start of file, or
# after a header line ending in ':'. That pair of conditions is what separates a
# docstring from a triple-quoted string literal, and it is checked against
# Python's own `ast` in bin/tests/markdown-cost.test.sh rather than asserted.
# Delimiter-only lines and blanks are not prose, exactly as a ``` fence is not.
count_py_docstrings() { # <path> -> docstring prose lines
  awk '
  { line = $0; s = line; sub(/^[ \t]+/, "", s)
    if (indoc) {
      if (index(s, q) == 1 && length(s) == 3) { indoc = 0; next }
      p = index(line, q)
      if (p > 0) { rest = substr(line, 1, p - 1); indoc = 0
                   if (rest ~ /[^ \t]/) n++; next }
      if (s != "") n++
      next }
    if (s ~ /^[ \t]*#/) next
    if (s == "") next
    t = s; sub(/^[A-Za-z]{0,2}/, "", t)          # r"""  f"""  rb"""
    if (index(t, "\"\"\"") == 1) q = "\"\"\""
    else if (index(t, "'"'"'") == 1) q = "'"'"'"
    else { prev = s; prevset = 1; next }
    if (!(prevset == 0 || prev ~ /:[ \t]*$/)) { prev = s; prevset = 1; next }
    body = substr(t, 4); cp = index(body, q)
    if (cp > 0) { head = substr(body, 1, cp - 1)
                  if (head ~ /[^ \t]/) n++
                  prev = s; prevset = 1; next }
    if (body ~ /[^ \t]/) n++
    indoc = 1; prevset = 1; next }
  END { print n+0 }' "$1"
}

die2() { printf '%s: %s\n' "$CLI_NAME" "$*" >&2; exit 2; }

MAX_PCT="${MARKDOWN_COST_MAX_PCT:-30}"
case "$MAX_PCT" in
  ''|*[!0-9]*) die2 "MARKDOWN_COST_MAX_PCT must be a whole number of percent, got '$MAX_PCT'" ;;
esac

# Net lines a single markdown file may gain inside a reap without disqualifying
# it. See the md_grew assignment for why this is not zero.
GROW_TOL="${MARKDOWN_COST_GROW_TOL:-10}"
case "$GROW_TOL" in
  ''|*[!0-9]*) die2 "MARKDOWN_COST_GROW_TOL must be a whole number of lines, got '$GROW_TOL'" ;;
esac

CM_MAX_PCT="${MARKDOWN_COST_COMMENT_PCT:-60}"
CM_FLOOR="${MARKDOWN_COST_COMMENT_FLOOR:-150}"
case "$CM_MAX_PCT$CM_FLOOR" in
  ''|*[!0-9]*) die2 "MARKDOWN_COST_COMMENT_PCT and _FLOOR must be whole numbers, got '$CM_MAX_PCT' and '$CM_FLOOR'" ;;
esac

# --- the census and its ratchet ----------------------------------------------
RATCHET="${MARKDOWN_COST_RATCHET:-$(dirname "${BASH_SOURCE[0]}")/markdown-cost.ratchet}"

# MEASURE_UNIT is the version of the QUESTION, not of the script. Bump it only
# when a change makes an old baseline mean something different -- a new language
# priced, a predicate widened. A bug fix that makes the same question answered
# correctly does NOT bump it.
#
#   1  markdown + '#' and '//' comment lines
#   2  ...and Python docstrings (2026-08-26)
#   3  ...and files behind a scaffolding suffix (hf7y/etalon#18)
#
# WHY THIS EXISTS AT ALL. Unit 2 raised five of six estate repos above their
# committed floor at once (crt +3278, wtul +1933, senechal +693). The ratchet
# only falls and --accept refuses to raise, so without this the whole estate
# wedges: no PR passes anywhere, and the only way out is the hand edit the
# guard is built to reject. A measurement change is not prose growth, and must
# not be charged as it.
#
# It is NOT an override, and it is deliberately not reachable from a repo. On a
# unit mismatch the committed integer is never read as a floor -- it is in the
# wrong unit and says nothing -- so the floor becomes the merge-base tree,
# measured LIVE in the current unit. Editing the stamp in your own ratchet
# therefore buys nothing: the branch still cannot add a line, because the
# comparison it must pass never involved the stamped number.
MEASURE_UNIT=3

ratchet_unit() { # <file-or-stdin-text> -> the unit a ratchet was written in
  local u
  u="$(printf '%s\n' "$1" | sed -n 's/^# *unit: *\([0-9][0-9]*\).*/\1/p' | head -1)"
  printf '%s' "${u:-1}"     # every ratchet written before the stamp is unit 1
}

# census_stream reads NUL-separated repo-relative paths and totals their prose.
# Every caller must hand it the same file set for a given tree, or a working
# tree and a ref stop being comparable. NOT a second checkout -- creating one is
# a violation bin/no-worktree-lint.sh exists to catch, and it caught this.
census_stream() {
  local f lang n=0
  while IFS= read -r -d '' f; do
    f="${f#./}"
    [ -L "$f" ] && continue
    [ -f "$f" ] || continue
    prose_excluded "$f" && continue
    lang="$(prose_lang "$f")"
    [ -n "$lang" ] || continue
    n=$((n + $(count_prose "$lang" "$f")))
  done
  printf '%d' "$n"
}

census() { git ls-files -z | census_stream; }

census_ref() { # <ref> -> prose lines in that tree, or empty if it cannot be read
  local d out=''
  d="$(mktemp -d)" || return 1
  if git archive --format=tar "$1" 2>/dev/null | tar -x -C "$d" 2>/dev/null; then
    out="$( cd "$d" && find . -type f -print0 | census_stream )"
  fi
  rm -rf "$d"
  printf '%s' "$out"
}

count_prose() { # <lang> <path> -> prose line count for one file
  if [ "$1" = m ]; then
    # Everything outside a ``` fence. The fence lines themselves are not prose.
    awk '/^[ \t]*```/{fence=!fence; next} {if($0~/^[ \t]*$/)next; if(!fence)n++} END{print n+0}' "$2"
  else
    local line s n=0
    while IFS= read -r line || [ -n "$line" ]; do
      s="${line#"${line%%[![:space:]]*}"}"
      [ -n "$s" ] || continue
      is_comment "$1" "$line" && n=$((n + 1))
    done < "$2"
    [ "$1" = p ] && n=$((n + $(count_py_docstrings "$2")))
    printf '%d' "$n"
  fi
}

# Exposed so bin/tests can pin this heuristic to Python's own ast. A scanner for
# a language it does not parse is a guess until something independent checks it.
if [ "${1:-}" = --count-docstrings ]; then
  [ $# -eq 2 ] || die2 "--count-docstrings takes exactly one file, got $(($# - 1))"
  [ -f "$2" ] || die2 "no such file: $2"
  count_py_docstrings "$2"
  exit 0
fi

if [ "${1:-}" = --census ] || [ "${1:-}" = --accept ]; then
  git rev-parse --git-dir >/dev/null 2>&1 || die2 "not inside a git repository"
  now="$(census)"
  [ -n "$now" ] || die2 "the census produced no count -- refusing to report a number I did not measure"
  if [ "${1:-}" = --accept ]; then
    # A ratchet that can be re-accepted upward is not a ratchet. If the tree
    # has grown, --accept refuses; reap prose, do not move the floor.
    if [ -f "$RATCHET" ]; then
      prev_text="$(cat "$RATCHET")"
      prev="$(printf '%s\n' "$prev_text" | grep -v '^#' | tr -d '[:space:]')"
      prev_unit="$(ratchet_unit "$prev_text")"
      case "$prev" in ''|*[!0-9]*) prev='' ;; esac
      # Across a unit change the old number is not a smaller measurement of the
      # same thing, so "above it" is not growth. Re-base once, and say so.
      if [ -n "$prev" ] && [ "$prev_unit" != "$MEASURE_UNIT" ]; then
        printf 'markdown-cost --accept -- RE-BASING from unit %s to unit %s.\n' "$prev_unit" "$MEASURE_UNIT"
        printf '  The old baseline of %s is in a unit this guard no longer measures in;\n' "$prev"
        printf '  %s is the same tree re-measured, not prose that was added.\n' "$now"
        prev=''
      fi
      if [ -n "$prev" ] && [ "$now" -gt "$prev" ]; then
        printf 'markdown-cost --accept -- REFUSED. The tree is %d line(s) ABOVE the\n' "$((now - prev))" >&2
        printf '  baseline of %s, and this ratchet only falls. Reap prose instead.\n' "$prev" >&2
        exit 1
      fi
    fi
    # SEEDING BEFORE `git add` IS THE RECURRING TRAP, and it is silent.
    # census() is `git ls-files`, so a prose file that is written but not yet
    # STAGED is not counted -- the baseline lands too low and the very next
    # --census fails on the commit that seeded it. It has bitten four separate
    # ports; hf7y/ecosim#73 diagnosed it after the third. A warning is cheap
    # and the alternative is remembering, which has not worked.
    untracked="$(git ls-files --others --exclude-standard -z 2>/dev/null \
      | { n=0; while IFS= read -r -d '' u; do
            prose_excluded "$u" && continue
            [ -n "$(prose_lang "$u")" ] && n=$((n+1))
          done; printf '%s' "$n"; })"
    if [ "${untracked:-0}" -gt 0 ]; then
      printf 'markdown-cost --accept -- WARNING: %s prose file(s) are UNTRACKED and\n' "$untracked" >&2
      printf '  therefore NOT in this baseline. census() reads `git ls-files`. Stage them\n' >&2
      printf '  and re-run --accept, or the next --census fails on this very commit.\n' >&2
    fi
    printf '# markdown-cost.ratchet -- prose lines in this tree. SHRINKS ONLY.\n# Written by markdown-cost.sh --accept, which refuses to raise it. A hand\n# edit that raises it is rejected by --census. See bin/markdown-cost.sh.\n# unit: %s -- what was measured. A number from another unit is not a floor.\n# accepted %s\n%s\n' \
      "$MEASURE_UNIT" "$(date -Is)" "$now" > "$RATCHET" || die2 "cannot write $RATCHET"
    printf 'markdown-cost --accept -- baseline is now %s prose line(s).\n' "$now"
    exit 0
  fi
  [ -f "$RATCHET" ] || die2 "no ratchet at $RATCHET -- run --accept to seed it. A missing baseline is not a pass."
  was_text="$(cat "$RATCHET")"
  was="$(printf '%s\n' "$was_text" | grep -v '^#' | tr -d '[:space:]')"
  case "$was" in ''|*[!0-9]*) die2 "unreadable baseline in $RATCHET: '$was'" ;; esac
  was_unit="$(ratchet_unit "$was_text")"
  stale_unit=0
  [ "$was_unit" = "$MEASURE_UNIT" ] || stale_unit=1
  if [ "$stale_unit" = 1 ]; then
    printf 'markdown-cost --census -- %s prose line(s); baseline %s is unit %s, this guard measures in unit %s.\n' \
      "$now" "$was" "$was_unit" "$MEASURE_UNIT"
  else
    printf 'markdown-cost --census -- %s prose line(s), baseline %s\n' "$now" "$was"
  fi

  # A branch answers for the prose IT adds, not for main moving beneath it.
  # Found on this guard's own first CI run: the branch was under its own
  # baseline and still failed, because main had gained 235 lines since it was
  # cut. On an absolute gate every PR re-accepts, and re-accepting on autopilot
  # is how a ratchet loosens itself. So the FLAG needs both conditions.
  base=''
  mb=''
  if git rev-parse --verify -q origin/main >/dev/null 2>&1; then
    mb="$(git merge-base HEAD origin/main 2>/dev/null)" || mb=''
    [ -n "$mb" ] && base="$(census_ref "$mb")"
  fi

  # THE BASELINE ITSELF ONLY FALLS. Raising it by hand was an affordance this
  # guard printed in its own FLAG, and it was taken twice in one day -- once
  # to fit three guards, once to fit a rollout -- each time with a written
  #   [rest: vault:realisateur/guard-archaeology-20260817.md]
  if [ -n "$mb" ]; then
    prev_text="$(git show "$mb:${RATCHET#"$(git rev-parse --show-toplevel)/"}" 2>/dev/null)"
    prev="$(printf '%s\n' "$prev_text" | grep -v '^#' | tr -d '[:space:]')"
    case "$prev" in ''|*[!0-9]*) prev='' ;; esac
    # Two numbers in different units are not a raise; the re-base IS the change.
    [ "$(ratchet_unit "$prev_text")" = "$was_unit" ] || prev=''
    if [ -n "$prev" ] && [ "$was" -gt "$prev" ]; then
      printf '  FLAG [prose-ratchet] this branch RAISES the baseline from %s to %s.\n' "$prev" "$was"
      printf '        The ratchet only falls, and there is no override. Reap prose until\n'
      printf '        the tree fits, or leave the number alone.\n'
      exit 1
    fi
  fi

  if [ "$stale_unit" = 1 ]; then
    # The number in the file answers a question this guard no longer asks, so it
    # is not consulted. The merge-base tree is, measured live in the current
    # unit -- which is why a hand-edited stamp wins nothing: this comparison
    # never reads the stamped integer.
    if [ -z "$base" ]; then
      printf '  FLAG [prose-ratchet] the baseline is unit %s and there is no merge base to\n' "$was_unit"
      printf '        re-measure against, so this branch cannot be priced at all.\n'
      printf '        Fetch origin/main, or run --accept to re-base deliberately.\n'
      exit 1
    fi
    printf '  merge base holds %s in unit %s; this branch is %+d against it.\n' "$base" "$MEASURE_UNIT" "$((now - base))"
    if [ "$now" -gt "$base" ]; then
      printf '  FLAG [prose-ratchet] this branch adds %d prose line(s).\n' "$((now - base))"
      printf '        (The unit changed since %s was written, so that number is not the\n' "$RATCHET"
      printf '        floor here -- the merge-base tree is. Re-basing does not pay for\n'
      printf '        prose this branch adds.) Reap prose elsewhere in this branch.\n'
      exit 1
    fi
    printf '  ok -- adds nothing over the merge base. Run --accept to re-base %s to unit %s.\n' "$RATCHET" "$MEASURE_UNIT"
    exit 0
  fi

  if [ "$now" -gt "$was" ]; then
    if [ -z "$base" ]; then
      printf '  FLAG [prose-ratchet] the tree gained %d prose line(s) over the baseline,\n' "$((now - was))"
      printf '        and there is no merge base to say whether this branch is responsible.\n'
      exit 1
    fi
    printf '  merge base holds %s; this branch is %+d against it.\n' "$base" "$((now - base))"
    if [ "$now" -gt "$base" ]; then
      printf '  FLAG [prose-ratchet] this branch adds %d prose line(s), and the tree is\n' "$((now - base))"
      printf '        already %d over the baseline of %s.\n' "$((now - was))" "$was"
      printf '        The ratchet only falls, and raising %s is\n' "$RATCHET"
      printf '        rejected too. Reap prose elsewhere in this branch.\n'
      exit 1
    fi
    printf '  over the baseline, but not by this branch -- main drifted. Not this PR to answer for.\n'
  fi
  [ "$now" -lt "$was" ] && printf '  %d line(s) below the baseline -- run --accept to lock it in.\n' "$((was - now))"
  printf '  ok -- at or under the baseline.\n'
  exit 0
fi

# --- resolve the range -------------------------------------------------------
[ $# -le 1 ] || die2 "takes at most one argument (a ref range), got $#"
git rev-parse --git-dir >/dev/null 2>&1 || die2 "not inside a git repository"

RANGE="${1:-}"
if [ -z "$RANGE" ]; then
  # The default is deliberately merge-base and not `origin/main..HEAD`: the
  # latter also prices whatever landed on main since this branch was cut, which
  # is somebody else's prose and not this branch's bill.
  git rev-parse --verify -q origin/main >/dev/null 2>&1 || \
    die2 "no origin/main to compare against -- fetch it, or pass a range explicitly"
  BASE="$(git merge-base HEAD origin/main 2>/dev/null)" || BASE=''
  [ -n "$BASE" ] || die2 "HEAD and origin/main have no merge base -- pass a range explicitly"
  RANGE="$BASE..HEAD"
fi

ERR="$(mktemp)"; trap 'rm -f "$ERR"' EXIT

NUMSTAT="$(git diff --numstat "$RANGE" -- 2>"$ERR")" || \
  die2 "cannot read the diff for '$RANGE': $(tr '\n' ' ' < "$ERR")"
NAMESTATUS="$(git diff --name-status --diff-filter=A "$RANGE" -- 2>"$ERR")" || \
  die2 "cannot list added files for '$RANGE': $(tr '\n' ' ' < "$ERR")"

# --- count -------------------------------------------------------------------
total_added=0
md_added=0
md_deleted=0
md_grew=''
md_files=''
binary_files=''

while IFS=$'\t' read -r added deleted path; do
  [ -n "${path:-}" ] || continue
  case "$added" in
    -)  # A binary file has no line count. It is classifiable (not markdown)
        # but not countable, so it contributes nothing and is reported by name
        # rather than silently folded into the denominator.
        binary_files="$binary_files $path"
        continue ;;
    ''|*[!0-9]*)
        die2 "cannot classify the diff: unparseable numstat added-count '$added' for '$path'" ;;
  esac
  total_added=$((total_added + added))
  if md_is_markdown "$path" && ! md_allowlisted "$path"; then
    md_added=$((md_added + added))
    md_files="$md_files $path:$added"
    case "$deleted" in ''|*[!0-9]*) deleted=0 ;; esac
    md_deleted=$((md_deleted + deleted))
    # PER FILE, not just in total: a file that GREW is named here even when
    # some other file shrank by more. Repo-wide netting alone let a 300-line
    # delete of an obsolete doc launder a brand-new 250-line essay through as
    #   [rest: vault:realisateur/guard-archaeology-20260817.md]
    [ "$((added - deleted))" -gt "$GROW_TOL" ] && md_grew="$md_grew $path:+$((added - deleted))"
  fi
done <<EOF
$NUMSTAT
EOF

# --- added comment lines, in files that are not markdown ---------------------
# The ratio above cannot see these: to it a 400-line header added to a shell
# script is 400 lines of code. Read from the patch, not numstat, which knows how
#   [rest: vault:realisateur/guard-archaeology-20260817.md]
cm_added=0; cm_deleted=0; cm_total=0; cm_files=''
cur_lang=''; cur_n=0; cur_path=''
flush_cm() {
  [ -n "$cur_path" ] && [ "$cur_n" -gt 0 ] && cm_files="$cm_files $cur_path:$cur_n"
  cur_n=0
}
while IFS= read -r line; do
  case "$line" in
    '+++ b/'*)
      flush_cm
      cur_path="${line#+++ b/}"
      if prose_excluded "$cur_path"; then cur_lang=''
      else
        cur_lang="$(prose_lang "$cur_path")"
        [ "$cur_lang" = m ] && cur_lang=''   # *.md is priced by the ratio above
      fi
      continue ;;
    '+++ '*|'--- '*|'+++'|'@@'*|'diff --git '*|'index '*) continue ;;
  esac
  [ -n "$cur_lang" ] || continue
  case "$line" in
    '-'*)
      # Deletions are counted for ONE purpose: telling a reap from a cost.
      # They never enter cm_total, so the ratio below is still over ADDED
      # lines only and the threshold keeps exactly its original meaning.
      d="${line#-}"
      ds="${d#"${d%%[![:space:]]*}"}"
      [ -n "$ds" ] || continue
      is_comment "$cur_lang" "$d" && cm_deleted=$((cm_deleted + 1))
      continue ;;
    '+'*) ;;
    *) continue ;;
  esac
  line="${line#+}"
  s="${line#"${line%%[![:space:]]*}"}"
  [ -n "$s" ] || continue          # blanks count as neither, both sides
  cm_total=$((cm_total + 1))
  if is_comment "$cur_lang" "$line"; then
    cm_added=$((cm_added + 1)); cur_n=$((cur_n + 1))
  fi
done < <(git diff --unified=0 "$RANGE" -- 2>/dev/null)
flush_cm

# --- Python docstrings, added ------------------------------------------------
# Deliberately NOT read from the patch. A docstring is only distinguishable from
# a triple-quoted data literal by what precedes it, and `--unified=0` hunks omit
# exactly those lines -- a patch-side scanner would have to guess, and would
# guess differently on each side of a rename. So each changed .py file is
# measured WHOLE on both ends of the range and the difference is the bill. Files
# added by the range have no left side; `git show` fails and the left is 0.
ds_added=0
while IFS= read -r dpath; do
  [ -n "$dpath" ] || continue
  prose_excluded "$dpath" && continue
  case "$dpath" in *.py) ;; *) continue ;; esac
  l=0; r=0
  lt="$(mktemp)"; rt="$(mktemp)"
  git show "${RANGE%%..*}:$dpath" >"$lt" 2>/dev/null && l="$(count_py_docstrings "$lt")"
  git show "${RANGE##*..}:$dpath" >"$rt" 2>/dev/null && r="$(count_py_docstrings "$rt")"
  rm -f "$lt" "$rt"
  [ "$r" -gt "$l" ] && ds_added=$((ds_added + r - l))
done < <(git diff --name-only "$RANGE" -- 2>/dev/null)
# cm_added only. Those lines already came through the patch as added non-blank
# lines and are in cm_total; is_comment just could not see they were prose. This
# RECLASSIFIES them, and adding to the denominator too would bill them twice.
[ "$ds_added" -gt 0 ] && cm_added=$((cm_added + ds_added))

# --- report ------------------------------------------------------------------
printf 'markdown-cost -- %s\n' "$RANGE"
[ -z "$binary_files" ] || printf '  note: binary file(s) not line-counted:%s\n' "$binary_files"

rc=0

# 1. new top-level documents
new_root_md=''
while IFS=$'\t' read -r _status path; do
  [ -n "${path:-}" ] || continue
  md_is_markdown "$path" || continue
  md_is_top_level "$path" || continue
  md_allowlisted "$path" && continue
  new_root_md="$new_root_md $path"
done <<EOF
$NAMESTATUS
EOF

if [ -n "$new_root_md" ]; then
  printf '  FLAG [new-root-document] this diff adds a new top-level *.md file:%s\n' "$new_root_md"
  printf '        Editing an existing document is free. Adding another root document\n'
  printf '        is not -- put it under a directory, or fold it into one that exists.\n'
  printf '        allowlist: %s\n' "${MD_ALLOW[*]}"
  rc=1
fi

# 2. the ratio
if [ "$total_added" -eq 0 ]; then
  # NOT a pass-by-silence: say plainly that there was nothing to price, so this
  # line can never be read as "the prose was checked and was fine".
  printf '  0 added line(s) in this range -- nothing to price.\n'
else
  pct=$(( md_added * 100 / total_added ))
  printf '  %d of %d added line(s) are markdown -- %d%% (threshold %d%%)\n' \
    "$md_added" "$total_added" "$pct" "$MAX_PCT"
  if [ "$md_deleted" -ge "$md_added" ] && [ "$md_added" -gt 0 ] && [ -z "$md_grew" ]; then
    # A REAP IS NOT A COST. This guard prices ADDED prose, which makes any
    # markdown-only diff 100% markdown -- including one that deletes far more
    # than it adds. So it flagged hf7y/realisateur#231, a pass that removed 330
    #   [rest: vault:realisateur/guard-archaeology-20260817.md]
    printf '  net prose: -%d line(s) (added %d, deleted %d) -- a reap, not a cost.\n' \
      "$((md_deleted - md_added))" "$md_added" "$md_deleted"
  elif [ $(( md_added * 100 )) -gt $(( MAX_PCT * total_added )) ]; then
    printf '  FLAG [markdown-ratio] %d%% of the added lines are prose, over the %d%% threshold.\n' \
      "$pct" "$MAX_PCT"
    [ -n "$md_grew" ] && { printf '        these grew, so this is not a reap (path:+net):\n'
      for f in $md_grew; do printf '          %s\n' "$f"; done; }
    printf '        contributing file(s) (path:added-lines):\n'
    for f in $md_files; do printf '          %s\n' "$f"; done
    printf '        Prose that describes mechanism is cheaper than the mechanism.\n'
    printf '        Either the mechanism is missing, or the description outran it.\n'
    rc=1
  fi
fi

# 3. comments added to files that are not markdown
if [ "$cm_total" -gt 0 ]; then
  cm_pct=$(( cm_added * 100 / cm_total ))
  printf '  %d of %d added non-markdown line(s) are comments -- %d%% (flags at %d%% and %d lines)\n' \
    "$cm_added" "$cm_total" "$cm_pct" "$CM_MAX_PCT" "$CM_FLOOR"
  if [ "$cm_deleted" -ge "$cm_added" ] && [ "$cm_added" -gt 0 ]; then
    # A REAP IS NOT A COST -- the exemption the markdown ratio above has
    # carried since #231, applied to the axis it was missing on. This check
    # prices ADDED comment lines, so a pass that deletes 4795 lines of header
    # essay and puts back 318 lines of TRAP statement scores 74% comments and
    # FLAGS: the guard taxing the exact behaviour it exists to produce. #287
    # fixed this for markdown and left check 3 asymmetric.
    printf '  net comments: -%d line(s) (added %d, deleted %d) -- a reap, not a cost.\n' \
      "$((cm_deleted - cm_added))" "$cm_added" "$cm_deleted"
  elif [ "$cm_added" -ge "$CM_FLOOR" ] && [ $(( cm_added * 100 )) -ge $(( CM_MAX_PCT * cm_total )) ]; then
    printf '  FLAG [comment-ratio] this diff adds %d comment line(s) at %d%% of its non-markdown lines.\n' \
      "$cm_added" "$cm_pct"
    printf '        contributing file(s) (path:added-comment-lines):\n'
    for f in $cm_files; do printf '          %s\n' "$f"; done
    printf '        A header explaining a script is prose, and it is not free because\n'
    printf '        it lives in a .sh. Both conditions must hold: dense is allowed, and\n'
    printf '        bulk is allowed, but not both at once.\n'
    rc=1
  fi
fi

[ "$rc" -eq 0 ] && printf '  ok -- priced, and under the threshold.\n'
exit "$rc"
