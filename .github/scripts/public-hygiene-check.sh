#!/usr/bin/env bash
# public-hygiene-check.sh — the scrub that made this repository publishable, enforced on every
# push instead of once. A one-time removal decays: the next paragraph copied in from somewhere
# internal brings an identifier back and nobody notices.
#
# WHAT IT DOES NOT DO: it does not remove reasoning. Saying WHAT a guard prevents, and why, is the
# point of publishing. What it bans is internal bookkeeping an outside reader cannot resolve —
# decision-record numbers, review-round and finding numbers, private paths, custody and device
# identifiers, assistant trace — and any description of an engine weakness whose fix a reader
# cannot assume is deployed everywhere.
#
# 🔴 THE ONE EXCEPTION, AND WHY. pact/modules/roulette.pact and pact/modules/drand.pact are
# DEPLOYED VERBATIM: the code on chain is the `(module …)` form of those files, comments included,
# and VERIFY.md's whole claim is that they are identical. Scrubbing a comment out of either would
# break that claim while hiding nothing — those comments are already public on the chain, readable
# by anyone with `describe-module`. deploy-bytes/ is that same text, and the frozen-module fixture
# is roulette.pact with one substitution. All five are excluded BY EXACT PATH, never by a wildcard
# that could quietly cover a new file.
#
# 🔴 THE SECOND EXCEPTION, narrower. .github/scripts/pact-static-check.sh is the estate's generic
# Pact gate, shipped here byte for byte as it is already published at
# github.com/SmartPacts/prize-draw. Its own text names the release the weakness it warns about was
# fixed in. It is exempt from the engine-weakness pattern ONLY, and only at that exact path;
# changing it here would make this repository's gate differ from the published one for no gain.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

SELF=".github/scripts/public-hygiene-check.sh"
DEPLOYED_VERBATIM=("pact/modules/roulette.pact" "pact/modules/drand.pact"
                   "deploy-bytes/roulette.pact" "deploy-bytes/drand.pact"
                   "pact/tests/fixtures/roulette-frozen.pact")
STATIC_GATE=".github/scripts/pact-static-check.sh"
# Kadena's own code, vendored so the suite can run. Not ours to rewrite, and `compose-capability`
# is ordinary Pact in it.
VENDOR=("pact/vendor/fixtures/coin.pact" "pact/vendor/fixtures/fungible-v2.pact"
        "pact/vendor/fixtures/fungible-xchain-v1.pact")

mapfile -t FILES < <(git ls-files)
if [ "${#FILES[@]}" -lt 20 ]; then
  echo "hygiene: REFUSING — only ${#FILES[@]} tracked files. A scan that inspects nothing is not a pass."
  exit 2
fi

bad=0
check() {                       # check <label> <pattern> [exempt...]
  local label="$1" pat="$2"; shift 2
  local exempt=("$SELF" "$@") f hit
  for f in "${FILES[@]}"; do
    local skip=0
    for e in "${exempt[@]}"; do [ "$f" = "$e" ] && skip=1; done
    [ "$skip" = 1 ] && continue
    [ -f "$f" ] || continue
    if hit=$(grep -nE "$pat" "$f" 2>/dev/null | head -3); then
      [ -n "$hit" ] && { echo "hygiene: $label in $f"; echo "$hit" | sed 's/^/    /'; bad=$((bad+1)); }
    fi
  done
}

check "decision-record reference" 'ADR-[0-9]{3}|ADR-[A-Z][0-9]+|docs/adr' "${DEPLOYED_VERBATIM[@]}"
check "internal epic id"          'CW32-[0-9]+'
check "review-round numbering"    'cold audit|audit #?[0-9]|delta audit|red[- ]team engagement|mutation #[0-9]+' "${DEPLOYED_VERBATIM[@]}"
# An absolute path out of somebody's machine is banned EVERYWHERE, with no exemption: if one ever
# appeared inside a deployed module we would want to know, even though we could not remove it.
check "private path"              '/home/[A-Za-z0-9_-]+|~/claude|/mnt/c/Users'
# The names of our non-public repositories resolve to nothing for a reader. The two deployed
# modules name one in a comment; that comment is already on chain and cannot be edited here
# without breaking VERIFY.md's claim, so they are exempt BY EXACT PATH and nothing else is.
check "internal repository name"  'roulette-ops|casino-private|smartpacts-private' "${DEPLOYED_VERBATIM[@]}"
check "personal email"            'afloresh|@gmail\.com'
check "assistant trace"           'Claude|Anthropic|Co-Authored-By|claude-code|Generated with'
check "internal memory/config"    'CLAUDE\.md|STATUS\.md|MANAGER-NEXT|smart-pacts-shares'
# Device and custody identifiers. The colour words are device names in our signing roster; they
# appear in the deployed modules' own comments, which are already on chain, and nowhere else.
check "device or custody id"      "m/44'?/626|Nano S|device hash|\\bpurple\\b|\\bpink\\b" "${DEPLOYED_VERBATIM[@]}"
# An engine weakness whose fix a reader cannot assume is deployed on every node they might use is
# not ours to describe in public. Ours is to write code that is safe either way and say THAT.
check "engine-weakness description" \
      'compose[- ]cap(ability)?[- ](escape|forgery)|foreign[- ]compose|escape surface|Chainweb32|pre-Chainweb32|CW32' \
      "${DEPLOYED_VERBATIM[@]}" "$STATIC_GATE" "${VENDOR[@]}"

# WRAP-TOLERANT SECOND PASS. A scrubbed phrase can survive by breaking across a line: MEASURED
# elsewhere in this estate, "cold audit #22" shipped publicly because "cold audit" ended one line
# and "#22" began the next. The pattern was right; the line was wrong.
for f in "${FILES[@]}"; do
  [ "$f" = "$SELF" ] && continue
  [ -f "$f" ] || continue
  case " ${DEPLOYED_VERBATIM[*]} " in *" $f "*) continue;; esac
  if paste -d' ' <(sed 's/^[ \t;>*-]*//' "$f") <(sed '1d;s/^[ \t;>*-]*//' "$f") 2>/dev/null \
      | grep -qE 'ADR-[A-Z]?[0-9]|CW32-[0-9]|cold audit|Co-Authored|audit [0-9]+ F[0-9]'; then
    echo "hygiene: a banned phrase appears ACROSS TWO LINES in $f"; bad=$((bad+1))
  fi
done

echo "hygiene: ${#FILES[@]} tracked files scanned"
[ "$bad" -eq 0 ] && { echo "hygiene: clean"; exit 0; }
echo "hygiene: $bad finding(s)"; exit 1
