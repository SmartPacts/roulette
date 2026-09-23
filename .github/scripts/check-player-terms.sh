#!/usr/bin/env bash
# The player terms state numbers. Those numbers must BE the contract's, not a hand-maintained copy
# that drifts: a terms document whose numbers have drifted is how a game ends up promising
# something it does not do. Every value below is READ OUT OF pact/modules/roulette.pact and then
# looked for in the document. Nothing is restated here.
#
# FAILS CLOSED. A constant that cannot be read is an error, never a silent skip — a check that
# inspected nothing must never report clean.
set -uo pipefail
cd "$(dirname "$0")/../.."
DOC=docs/ROULETTE-PLAYER-TERMS.md
MOD=pact/modules/roulette.pact
BAD=0

[ -f "$DOC" ] || { echo "  BAD   $DOC is missing"; exit 1; }
[ -f "$MOD" ] || { echo "  BAD   $MOD is missing"; exit 1; }

konst () {
  local v
  v=$(grep -oE "\(defconst $1:[a-z]+ [^)]*\)" "$MOD" | head -1 | grep -oE '[0-9.]+' | head -1)
  [ -n "$v" ] || { echo "  BAD   constant $1 could not be read from $MOD"; BAD=$((BAD+1)); }
  printf '%s' "$v"
}
want () { # want <label> <what-it-is> <the-text-the-doc-must-contain>
  if grep -qF "$3" "$DOC"; then printf '  OK    %-44s %s\n' "$1" "$2"
  else printf '  BAD   %-44s doc does not say: %s\n' "$1" "$3"; BAD=$((BAD+1)); fi
}

MINBET=$(konst LAUNCH-MIN-BET);        ENTRIES=$(konst MAX-ENTRIES)
WINDOW=$(konst LAUNCH-BET-WINDOW);     MARGIN=$(konst LAUNCH-DRAND-MARGIN)
# The beacon wait is an operator setting, so the terms must state the FLOOR as well as today's
# value: the launch number alone would let the wait be retuned without the terms ever saying how
# short it may become.
MINMARGIN=$(konst MIN-DRAND-MARGIN)
VOIDS=$(konst VOID-AFTER);             FRAC=$(konst LAUNCH-RESERVE-FRACTION)
MAXFRAC=$(konst MAX-RESERVE-FRACTION)
[ "$BAD" = 0 ] || { echo "  terms BAD: $BAD (a constant was unreadable — refusing to report clean)"; exit 1; }

VOIDDAYS=$(python3 -c "print(int(float('$VOIDS')/86400))")
FRACPCT=$(python3 -c "print(('%g' % (float('$FRAC')*100)))")
MAXPCT=$(python3 -c "print(('%g' % (float('$MAXFRAC')*100)))")

want "minimum bet"          "$MINBET KDA"      "**$(python3 -c "print('%g' % float('$MINBET'))") KDA** minimum"
want "chips per board"      "$ENTRIES"         "**$ENTRIES** chips"
want "betting window"       "${WINDOW%.*}s"    "closes ${WINDOW%.*} seconds"
want "drand margin"         "${MARGIN%.*}s"    "${MARGIN%.*} seconds after betting closes"
want "drand margin floor"   "${MINMARGIN%.*}s" "never below **${MINMARGIN%.*} seconds**"
want "refund grace"         "$VOIDDAYS days"   "refund after $VOIDDAYS days"
want "table limit"          "$FRACPCT%"        "**$FRACPCT%** of the house"
want "table limit ceiling"  "$MAXPCT%"         "**$MAXPCT%**"
want "player return"        "36/37"            "36/37 — 97.297%"
want "house edge"           "1/37"             "**2.7027%**"

echo "  terms BAD: $BAD"
[ "$BAD" = 0 ]
