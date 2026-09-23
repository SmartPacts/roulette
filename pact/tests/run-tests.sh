#!/usr/bin/env bash
# run-tests.sh — everything this repository claims about the two contracts, in one command.
#
#   cd pact/tests && ./run-tests.sh
#
# This is the same command CI runs, with no reduced subset: a CI that runs less than you do
# teaches you to trust a green tick that means less than you think.
#
# SCORED BY EXIT CODE, NEVER BY GREPPING THE TRANSCRIPT. A later hard error in a Pact REPL
# suppresses earlier FAILURE lines, so a mutation that breaks an early assertion can leave a
# transcript with no FAILURE in it at all. Only the exit code is trustworthy — and one file here
# is an INVERTED CONTROL that must FAIL, which grepping cannot score at all.
set -uo pipefail
cd "$(dirname "$0")" || exit 2
PACT="${PACT:-pact}"
BAD=0

echo "== engine"
"$PACT" --version || { echo "no pact on PATH — set PACT=/path/to/pact"; exit 2; }
python3 --version || { echo "the gates fail closed without python3"; exit 2; }

echo
echo "== static gate (every .pact and .repl under pact/, loaded through the engine and scanned)"
# ENUMERATED, never hand-listed: a new suite is picked up automatically instead of being silently
# left outside the gate, and the count is asserted so a broken enumeration FAILS rather than
# reporting clean on nothing.
#
# Two things are outside it, on purpose, and neither is unchecked:
#   * deploy-bytes/ — a bare `(module …)` form with no `namespace` line, so it cannot load on its
#     own. It is checked instead by `module-region.py --check`, which proves it is character for
#     character the module in pact/modules/ that the gate DOES load.
#   * roulette-pin-must-fail.repl — the inverted control. The gate's first tier asks "does it
#     load", and that file is required NOT to.
(
  cd ../..
  mapfile -t SFILES < <(find pact \( -name '*.pact' -o -name '*.repl' \) -type f \
                        | grep -v 'roulette-pin-must-fail\.repl' | sort)
  n=${#SFILES[@]}
  [ "$n" -ge 15 ] || { echo "   BAD: only $n files enumerated — the enumeration broke"; exit 1; }
  ./.github/scripts/pact-static-check.sh "${SFILES[@]}"
) || BAD=$((BAD+1))

echo
# ONE CALL PER FILE, and the count is checked: a gate that inspected zero files must FAIL, never
# pass quietly. In Pact 5 `or`, `and` and `+` take exactly TWO operands: a three-operand form
# loads, passes the static gate, and only throws when that line runs.
echo "== binary forms (or / and / + take exactly two operands in Pact 5)"
(
  cd ../..
  nf=$(find pact -name '*.pact' -o -name '*.repl' | wc -l)
  ar=$(find pact -name '*.pact' -o -name '*.repl' | sort | while read -r f; do python3 .github/scripts/pact-arity-check.py "$f" 2>&1; done)
  na=$(echo "$ar" | grep -c 'forms,')
  bad3=$(echo "$ar" | grep -E 'forms,' | grep -vc ' 0 with 3+ operands')
  echo "   files on disk: $nf   reported on: $na   with a 3+ operand form: $bad3"
  [ "$na" -eq "$nf" ] || { echo "   BAD: the checker reported on $na of $nf files"; exit 1; }
  [ "$bad3" -eq 0 ] || { echo "$ar" | grep -E 'forms,' | grep -v ' 0 with 3+ operands' | sed 's/^/   /'; exit 1; }
) || BAD=$((BAD+1))

# A two-argument `expect-failure` matches ANY failure, so it asserts nothing about WHY the call
# failed — an arity error or a typo would pass it. The checker self-tests before scanning and
# fails if it can parse no file, so it cannot certify an empty scan as clean.
echo "== expect-failure arity (a two-argument expect-failure asserts nothing about WHY)"
( cd ../.. && python3 .github/scripts/expect-failure-arity.py pact/tests/*.repl ) || BAD=$((BAD+1))

# The annotated module and the bytes that were deployed must be the same program. If this row
# fails, everything VERIFY.md says about the file you are reading is about a different file.
echo "== the annotated modules ARE the published deploy bytes"
( cd ../.. && python3 .github/scripts/module-region.py --check ) || BAD=$((BAD+1))

# The frozen-module suite runs the whole lifecycle against a copy of roulette whose GOVERNANCE can
# never pass again. That copy must be THIS module with only that one substitution, or the suite
# proves the freeze behaviour of some other contract. Re-derived here and compared with what is
# committed, so a stale fixture is loud rather than silent.
echo "== the frozen fixture is this module with governance replaced, and nothing else"
KEEP=$(mktemp -d)
cp fixtures/roulette-frozen.pact fixtures/frozen-init.repl "$KEEP/" 2>/dev/null \
  || { echo "   BAD: the committed fixture is missing"; BAD=$((BAD+1)); }
( cd ../.. && ./.github/scripts/build-frozen-fixture.sh ) || BAD=$((BAD+1))
if diff -q "$KEEP/roulette-frozen.pact" fixtures/roulette-frozen.pact > /dev/null 2>&1 \
   && diff -q "$KEEP/frozen-init.repl" fixtures/frozen-init.repl > /dev/null 2>&1; then
  echo "   the committed fixture is exactly what the generator produces"
else
  echo "   BAD: the committed fixture is NOT what build-frozen-fixture.sh produces"; BAD=$((BAD+1))
fi
rm -rf "$KEEP"

# roulette pins the beacon verifier BY HASH, so it refuses to load against any other code under
# that name. drand has no dependencies, so its hash can be computed locally and compared — which
# is exactly what this does, against the literal in the module.
echo "== the drand hash pinned in roulette is the drand in this repository"
RH=$(mktemp /tmp/drand-hash-XXXXXX.repl)
{ echo "(load \"$PWD/drand-test-init.repl\")"
  echo '(print (format "DRANDHASH {}" [(at "hash" (describe-module "n_48867b242317a0216a67f8c7ca26696b5878e0e3.drand"))]))'
} > "$RH"
H=$("$PACT" "$RH" 2>/dev/null | grep -oE 'DRANDHASH [A-Za-z0-9_-]+' | awk '{print $2}')
if [ -n "$H" ] && grep -q "$H" ../modules/roulette.pact; then
  echo "   $H — built here and pinned in roulette.pact"
else
  echo "   BAD: built=${H:-<unreadable>}, which roulette.pact does not pin"; BAD=$((BAD+1))
fi
rm -f "$RH"

# The published terms state numbers. They must BE the contract's constants, read out of the module.
echo "== the player terms state the contract's own numbers"
( cd ../.. && ./.github/scripts/check-player-terms.sh ) || BAD=$((BAD+1))

echo
echo "== suites (every one must exit 0)"
for f in drand-unit-testing.repl \
         roulette-unit-testing.repl roulette-rules-testing.repl roulette-payout-testing.repl \
         roulette-capfloor-testing.repl roulette-internals-testing.repl \
         roulette-oracle-testing.repl roulette-frozen-testing.repl; do
  "$PACT" -t "$f" > "/tmp/$f.out" 2>&1
  rc=$?
  n=$(grep -c 'Expect' "/tmp/$f.out" 2>/dev/null || echo 0)
  if [ $rc -eq 0 ]; then printf '   ok   %-38s exit=0  %s assertions printed\n' "$f" "$n"
  else printf '   FAIL %-38s exit=%s  (see /tmp/%s.out)\n' "$f" "$rc" "$f"; BAD=$((BAD+1)); fi
done

echo
echo "== the inverted control (must exit 1, AND for the stated reason)"
# 🔴 Exit code alone is not enough here. ANY unrelated failure — a typo, a missing fixture, an
# unset keyset — also exits 1, and the row would print ok while proving nothing. Require the
# MESSAGE as well. What it proves: plant an impostor `drand` that "verifies" every signature and
# returns a chosen number, and roulette REFUSES TO LOAD, because it pins the verifier by hash.
PINOUT=$("$PACT" roulette-pin-must-fail.repl 2>&1); PINRC=$?
# 🔴 MATCHED FROM A HERE-STRING, NOT THROUGH A PIPE. Under `set -o pipefail`, `printf … | grep -q`
# reports the PIPE: grep exits the moment it matches, printf dies of SIGPIPE, and the pipeline
# returns 141 — so a successful match reads as a failure, intermittently, depending on how much of
# the 80 KB transcript fitted in the pipe buffer. This row is the one place where a false negative
# would be a false alarm and a false positive would hide a broken pin, so it does not use a pipe.
if grep -q "hash not blessed" <<< "$PINOUT"; then WHY=present; else WHY=ABSENT; fi
if [ "$PINRC" = 1 ] && [ "$WHY" = present ]; then
  printf '   ok   %-38s exit=1 and refused for the right reason\n' "roulette-pin-must-fail.repl"
else
  printf '   FAIL %-38s exit=%s, "hash not blessed" %s\n' "roulette-pin-must-fail.repl" "$PINRC" "$WHY"
  BAD=$((BAD+1))
fi

echo
if [ "$BAD" -eq 0 ]; then echo "SUITE RESULT: PASS"; else echo "SUITE RESULT: FAIL ($BAD)"; fi
exit $((BAD > 0))
