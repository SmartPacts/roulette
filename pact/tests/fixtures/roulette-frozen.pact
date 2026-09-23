;; roulette.pact — provably-fair on-chain European roulette (Pact 5 / KDA-CE).
;;
;; ONE SIGNED TRANSACTION PER PLAYER. You place a board and that is all you sign.
;; If you win you claim; if you lose you do nothing. The three-transaction
;; commit-reveal round this replaces existed only to stop the last actor steering
;; a block-hash outcome, and ADR-R1 removes that reason entirely.
;;
;; WHERE THE NUMBER COMES FROM (ADR-R1). A drand BN254 beacon, verified on chain
;; by `n_48867b242317a0216a67f8c7ca26696b5878e0e3.drand`. NOT a Kadena block hash: the miner of a deciding block sees
;; the outcome before publishing and can discard the block and keep mining, which
;; wins 71.1% of even-money bets at the largest mainnet miner's measured 61.5%
;; share and is still profitable at 10%. Combining several future blocks does not
;; help (the first N-1 already exist when the last is mined); deriving per player
;; from the player's own committed secret does not help either (the attacker is a
;; miner WHO IS ALSO A PLAYER). Both were tested and both failed.
;;
;; The round's drand round is pinned when the round opens and is not published
;; until a fixed WAIT after betting closes, so nobody -- player, miner or
;; operator -- can know the number while a bet can still be placed. That wait is
;; an operator setting for FUTURE rounds, 180 s at launch and never under 60 s,
;; and a live round keeps the beacon it was pinned to. Afterwards ANYONE may
;; submit the beacon; a forged one cannot verify, and drand values never expire,
;; so there is no capture window to miss and no gain from staying silent.
;;
;; NO HOUSE INPUT. No house secret, no per-round house transaction. The standing
;; constraint (founder, 2026-08-31: "the house is never a human input") holds.
;;
;; SOLVENCY IS STRUCTURAL, NOT STATISTICAL. Each round carries a 37-slot EXPOSURE
;; VECTOR: exposure[n] is exactly what the house owes if n wins. The round reserves
;; max(exposure) -- the true worst case over every board in it, not the sum of each
;; board's worst case -- so the pot can never be short. It can only refuse a bet.
;; At resolve the liability is exposure[winning number], one lookup, and everything
;; else is released. That is also why a LOSER never has to send a transaction for
;; their reserve to come back.
;;
;; THE FEE NEVER TOUCHES THE PLAYER. Player return is exactly 36/37 = 97.297...%
;; on every bet on the table, always. The fee is paid out of the POT and only
;; decides how much of the house's own edge is forwarded to the SPT treasury
;; rather than retained. It is a rate on the pot's health (ADR-R2):
;;   rate = HOUSE-EDGE * min(1, available / target-float)
;; so the pot fills to its target and then forwards the whole edge. Charging more
;; than HOUSE-EDGE would give the pot negative drift, which is why that is the
;; immutable ceiling.
;;
;; LIMITS. The share of the spare pot one round may put at risk
;; (reserve-fraction), the table minimum and the wait between a round's close and
;; its beacon (drand-margin) are OPERATOR INPUTS, and they stay that way for the
;; life of the module: `set-params` is gated on ADMIN, not on GOVERNANCE, so all
;; three are still settable after the module is frozen. The wait is the one whose
;; SAFETY bound points down -- a wait too SHORT is the exploitable direction, and
;; the measurement behind its floor is recorded beside MIN-DRAND-MARGIN. The
;; contract's own bound on the share is ARITHMETIC and nothing more -- (0, 1.0],
;; because a round cannot put at risk more than the whole spare pot -- and the
;; operator owns every choice underneath it. A front end cannot substitute for
;; that bound: `bet` is public and anyone calls it directly, so the fraction the
;; round froze at open is the only thing binding a board. A front end is invited
;; to build on `pot-status`, which publishes the SMALLER of the table cap and
;; the bankroll rule -- the pot must hold at least 100x the advertised
;; even-money maximum -- so the number it advertises is a board `bet` accepts.
;;
;; 🔴 WHERE THE BANK STOPS GROWING, AND WHY IT IS ADVICE AND NOT A CEILING.
;; A uniform cap on GROSS exposure cannot be full Kelly for every family at once:
;; the zero-growth crossing falls as the payout rises -- even money 0.1081,
;; column/dozen 0.0807, double street 0.0644, corner 0.0603, street 0.0585,
;; split 0.0567, STRAIGHT-UP 0.0551 -- so any share above about 0.0551 gives the
;; bank negative median growth as soon as a straight-up board fills it.
;; Simulated worst case, the whole cap on one family every round over 20,000
;; rounds and 4,000 paths: at 0.025 every family's median bank grows and under
;; 1% of paths ever fall below a tenth of the bank; at 0.05 and at 0.055,
;; between 4% and 36% do. That is HOUSE capital volatility and nothing else --
;; `reserved <= balance` is enforced separately, so no player's claim is ever at
;; risk. The launch share is 0.025, under every family's crossing, and the
;; operator may raise it to the whole spare pot; that power is disclosed rather
;; than designed away. Pinned by PIN-2..PIN-2f, which recompute the crossing
;; from the wheel rather than restating this comment.
;;
;; THE TABLE MINIMUM is floored at 0.001 KDA and has no ceiling. Paying one
;; winner costs the house about 445 gas inside a batch and 483 on its own, so
;; even at a hundredfold gas price a claim costs about 0.0005 KDA: below 0.001 a
;; bet is worth less than twice what it costs to pay it, and nothing lower
;; carries an economic meaning. With no ceiling the operator can lift the
;; minimum above any bankroll and so close the table to new bets -- the same
;; disclosed cost of leaving the dial in the operator's hands.
;;
;; A DRAND STALL REFUNDS; IT DOES NOT FORFEIT (ADR-R3 s8). This departs from the
;; 2026-09-01 directive "nothing should refund", which was recorded as safe
;; explicitly because MIN-REVEALS was 1 -- a void then meant nobody had revealed
;; and a non-revealer forfeited anyway. There are no reveals now, so forfeiting
;; would confiscate players for an outage they could not cause or prevent. It is
;; safe from gaming because nobody can stall drand for one specific round, and
;; because a refund now requires ON-CHAIN EVIDENCE that drand went away: the
;; module records the highest beacon it has ever verified, and refuses a refund
;; for any round whose beacon is at or below it. Without that, a losing player
;; could read the public beacon off-chain, decline to resolve, and wait out the
;; clock for a free escape from every losing bet.
;; 🔴 RATIFIED by the founder, 2026-09-20: "refund".

;; 🔴 FRESH DEPLOY ONLY. This module cannot be upgraded over an earlier
;; INITIALIZED deployment. Adding a schema field does not fail at upgrade:
;; MEASURED, the module loads clean, a full `read` of an old row silently returns
;; it WITHOUT the field, and it breaks at the first access that READS the new
;; field -- `bet` and `pot-status` abort with `Key "..." not found in object`
;; while `resolve`, `void-round` and `withdraw-house` still run, so the table
;; stops taking bets and stops reporting its own solvency while everything that
;; settles what is already on it carries on. Repair needs module admin, so after
;; a freeze it is impossible. Verify the target chain carries no rows before
;; deploying.

(namespace "n_48867b242317a0216a67f8c7ca26696b5878e0e3")

; Load-time admin gate: deploying or upgrading this file requires the admin keyset.
; 🔴 THAT KEYSET IS SPT's `spt-gov` -- founder, 2026-09-21: "pink, purple and red",
; which are exactly the three spt-gov devices, 2-of-3. Referencing the keyset that
; already exists on every mainnet chain (measured) instead of defining a duplicate
; under a casino name removes one hardware-wallet ceremony and one way to get the
; roster wrong. Rotating spt-gov rotates this module's admin with it, by design.
(enforce-guard (keyset-ref-guard "n_48867b242317a0216a67f8c7ca26696b5878e0e3.spt-gov"))

(module roulette GOVERNANCE

  @doc "European single-zero roulette. One signed transaction per player; the \
  \number comes from a verified drand beacon; winners claim. Revenue is forwarded \
  \to the SPT treasury by a rate that depends only on the pot's health."

  (use coin)
  ; Sealed, tableless, pure -- and PINNED BY CODE HASH. This module refuses to
  ; load against any other bytes under that name, so the beacon verifier cannot
  ; be swapped for one that accepts a chosen number. n_48867b242317a0216a67f8c7ca26696b5878e0e3.drand's own governance
  ; is `enforce false`, so the pin can never be invalidated by an upgrade either.
  (use n_48867b242317a0216a67f8c7ca26696b5878e0e3.drand "Y07t-duJmkXkcGth0TfBRg3ThbNR-uh9PdNUd1MKHBQ"
    [ verified-seed round-at time-of-round ])

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; CONSTANTS ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ; The 37 European wheel numbers in wheel order (0..36). The draw indexes this.
  (defconst ROULETTE:[integer]
    [0 32 15 19 4 21 2 25 17 34 6 27 13 36 11 30 8 23 10 5 24 16 33 1 20 14 31 9 22 18 29 7 28 12 35 3 26])

  (defconst BETS-INDEX:list
     ; Single Numbers
     ["bet-0"
     ,"bet-1"       ,"bet-2"       ,"bet-3"
     ,"bet-4"       ,"bet-5"       ,"bet-6"
     ,"bet-7"       ,"bet-8"       ,"bet-9"
     ,"bet-10"      ,"bet-11"      ,"bet-12"
     ,"bet-13"      ,"bet-14"      ,"bet-15"
     ,"bet-16"      ,"bet-17"      ,"bet-18"
     ,"bet-19"      ,"bet-20"      ,"bet-21"
     ,"bet-22"      ,"bet-23"      ,"bet-24"
     ,"bet-25"      ,"bet-26"      ,"bet-27"
     ,"bet-28"      ,"bet-29"      ,"bet-30"
     ,"bet-31"      ,"bet-32"      ,"bet-33"
     ,"bet-34"      ,"bet-35"      ,"bet-36"
     ; Split Numbers
     ,"bet-1-2"     ,"bet-2-3"     ,"bet-4-5"
     ,"bet-5-6"     ,"bet-7-8"     ,"bet-8-9"
     ,"bet-10-11"   ,"bet-11-12"   ,"bet-13-14"
     ,"bet-14-15"   ,"bet-16-17"   ,"bet-17-18"
     ,"bet-19-20"   ,"bet-20-21"   ,"bet-22-23"
     ,"bet-23-24"   ,"bet-25-26"   ,"bet-26-27"
     ,"bet-28-29"   ,"bet-29-30"   ,"bet-31-32"
     ,"bet-32-33"   ,"bet-34-35"   ,"bet-35-36"
     ,"bet-1-4"     ,"bet-2-5"     ,"bet-3-6"
     ,"bet-4-7"     ,"bet-5-8"     ,"bet-6-9"
     ,"bet-10-13"   ,"bet-11-14"   ,"bet-12-15"
     ,"bet-13-16"   ,"bet-14-17"   ,"bet-15-18"
     ,"bet-19-22"   ,"bet-20-23"   ,"bet-21-24"
     ,"bet-22-25"   ,"bet-23-26"   ,"bet-24-27"
     ,"bet-28-31"   ,"bet-29-32"   ,"bet-30-33"
     ,"bet-31-34"   ,"bet-32-35"   ,"bet-33-36"
     ,"bet-7-10"    ,"bet-8-11"    ,"bet-9-12"
     ,"bet-16-19"   ,"bet-17-20"   ,"bet-18-21"
     ,"bet-25-28"   ,"bet-26-29"   ,"bet-27-30"
     ; Zero Splits
     ,"bet-0-1"     ,"bet-0-2"     ,"bet-0-3"
     ; Street Numbers
     ,"bet-1-2-3"   
     ,"bet-4-5-6"   
     ,"bet-7-8-9"
     ,"bet-10-11-12"      
     ,"bet-13-14-15"
     ,"bet-16-17-18"
     ,"bet-19-20-21"
     ,"bet-22-23-24"
     ,"bet-25-26-27"
     ,"bet-28-29-30"
     ,"bet-31-32-33"
     ,"bet-34-35-36"
     ; Trio Numbers (streets through zero)
     ,"bet-0-1-2"
     ,"bet-0-2-3"
     ; Corner Numbers
     ,"bet-1-2-4-5"       ,"bet-2-3-5-6"
     ,"bet-4-5-7-8"       ,"bet-5-6-8-9"
     ,"bet-7-8-10-11"     ,"bet-8-9-11-12"
     ,"bet-10-11-13-14"   ,"bet-11-12-14-15"
     ,"bet-13-14-16-17"   ,"bet-14-15-17-18"
     ,"bet-16-17-19-20"   ,"bet-17-18-20-21"
     ,"bet-19-20-22-23"   ,"bet-20-21-23-24"
     ,"bet-22-23-25-26"   ,"bet-23-24-26-27"
     ,"bet-25-26-28-29"   ,"bet-26-27-29-30"
     ,"bet-28-29-31-32"   ,"bet-29-30-32-33"
     ,"bet-31-32-34-35"   ,"bet-32-33-35-36"
     ; Double Street Numbers
     ,"bet-1-2-3-4-5-6"
     ,"bet-4-5-6-7-8-9"
     ,"bet-7-8-9-10-11-12"
     ,"bet-10-11-12-13-14-15"
     ,"bet-13-14-15-16-17-18"
     ,"bet-16-17-18-19-20-21"
     ,"bet-19-20-21-22-23-24"
     ,"bet-22-23-24-25-26-27"
     ,"bet-25-26-27-28-29-30"
     ,"bet-28-29-30-31-32-33"
     ,"bet-31-32-33-34-35-36"
     ; Column Numbers
     ,"bet-1-4-7-10-13-16-19-22-25-28-31-34"
     ,"bet-2-5-8-11-14-17-20-23-26-29-32-35"
     ,"bet-3-6-9-12-15-18-21-24-27-30-33-36"
     ; First Dozen Numbers
     ,"bet-1-12"
     ; Second Dozen Numbers
     ,"bet-13-24"
     ; Third Dozen Numbers
     ,"bet-25-36"
     ; Top Numbers 0, 1, 2 and 3
     ,"bet-top"
     ; Snake Numbers 1, 5, 9, 12, 14, 16, 19, 23, 27, 30, 32 and 34.
     ,"bet-snake"
     ; Odd Numbers 1, 3, 5, ..., 35
     ,"bet-odd"
     ; Even Numbers 2, 4, 6, ..., 36
     ,"bet-even"
     ; Red Numbers 32, 19, 21, 25, 34, 27, 36, 30, 23, 5, 16, 1, 14, 9, 18, 7, 12, 3
     ,"bet-red"
     ; Black Numbers 	15, 4, 2, 17, 6, 13, 11, 8, 10, 24, 33, 20, 31, 22, 29, 28, 35, 26
     ,"bet-black"
     ; Low Numbers 1, 2, 3, ..., 18
     ,"bet-low"
     ; High Numbers 1, 2, 3, ..., 18
     ,"bet-high"])

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; THE COVERAGE TABLE ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ; Which numbers each bet key covers. GENERATED from `winning-bets` below, which
  ; is the specification and is what the rules suite pins. Pact cannot build an
  ; object with a computed key, so this cannot be derived at load -- instead the
  ; unit suite asserts the two agree for ALL 158 keys across ALL 37 numbers, so a
  ; drift between them cannot survive a test run.
  (defconst BET-NUMBERS
    { "bet-0": [0], "bet-1": [1], "bet-2": [2], "bet-3": [3], "bet-4": [4], "bet-5": [5], "bet-6": [6]
    , "bet-7": [7], "bet-8": [8], "bet-9": [9], "bet-10": [10], "bet-11": [11], "bet-12": [12], "bet-13": [13]
    , "bet-14": [14], "bet-15": [15], "bet-16": [16], "bet-17": [17], "bet-18": [18], "bet-19": [19]
    , "bet-20": [20], "bet-21": [21], "bet-22": [22], "bet-23": [23], "bet-24": [24], "bet-25": [25]
    , "bet-26": [26], "bet-27": [27], "bet-28": [28], "bet-29": [29], "bet-30": [30], "bet-31": [31]
    , "bet-32": [32], "bet-33": [33], "bet-34": [34], "bet-35": [35], "bet-36": [36], "bet-1-2": [1 2]
    , "bet-2-3": [2 3], "bet-4-5": [4 5], "bet-5-6": [5 6], "bet-7-8": [7 8], "bet-8-9": [8 9]
    , "bet-10-11": [10 11], "bet-11-12": [11 12], "bet-13-14": [13 14], "bet-14-15": [14 15]
    , "bet-16-17": [16 17], "bet-17-18": [17 18], "bet-19-20": [19 20], "bet-20-21": [20 21]
    , "bet-22-23": [22 23], "bet-23-24": [23 24], "bet-25-26": [25 26], "bet-26-27": [26 27]
    , "bet-28-29": [28 29], "bet-29-30": [29 30], "bet-31-32": [31 32], "bet-32-33": [32 33]
    , "bet-34-35": [34 35], "bet-35-36": [35 36], "bet-1-4": [1 4], "bet-2-5": [2 5], "bet-3-6": [3 6]
    , "bet-4-7": [4 7], "bet-5-8": [5 8], "bet-6-9": [6 9], "bet-10-13": [10 13], "bet-11-14": [11 14]
    , "bet-12-15": [12 15], "bet-13-16": [13 16], "bet-14-17": [14 17], "bet-15-18": [15 18]
    , "bet-19-22": [19 22], "bet-20-23": [20 23], "bet-21-24": [21 24], "bet-22-25": [22 25]
    , "bet-23-26": [23 26], "bet-24-27": [24 27], "bet-28-31": [28 31], "bet-29-32": [29 32]
    , "bet-30-33": [30 33], "bet-31-34": [31 34], "bet-32-35": [32 35], "bet-33-36": [33 36]
    , "bet-7-10": [7 10], "bet-8-11": [8 11], "bet-9-12": [9 12], "bet-16-19": [16 19], "bet-17-20": [17 20]
    , "bet-18-21": [18 21], "bet-25-28": [25 28], "bet-26-29": [26 29], "bet-27-30": [27 30], "bet-0-1": [0 1]
    , "bet-0-2": [0 2], "bet-0-3": [0 3], "bet-1-2-3": [1 2 3], "bet-4-5-6": [4 5 6], "bet-7-8-9": [7 8 9]
    , "bet-10-11-12": [10 11 12], "bet-13-14-15": [13 14 15], "bet-16-17-18": [16 17 18]
    , "bet-19-20-21": [19 20 21], "bet-22-23-24": [22 23 24], "bet-25-26-27": [25 26 27]
    , "bet-28-29-30": [28 29 30], "bet-31-32-33": [31 32 33], "bet-34-35-36": [34 35 36], "bet-0-1-2": [0 1 2]
    , "bet-0-2-3": [0 2 3], "bet-1-2-4-5": [1 2 4 5], "bet-2-3-5-6": [2 3 5 6], "bet-4-5-7-8": [4 5 7 8]
    , "bet-5-6-8-9": [5 6 8 9], "bet-7-8-10-11": [7 8 10 11], "bet-8-9-11-12": [8 9 11 12]
    , "bet-10-11-13-14": [10 11 13 14], "bet-11-12-14-15": [11 12 14 15], "bet-13-14-16-17": [13 14 16 17]
    , "bet-14-15-17-18": [14 15 17 18], "bet-16-17-19-20": [16 17 19 20], "bet-17-18-20-21": [17 18 20 21]
    , "bet-19-20-22-23": [19 20 22 23], "bet-20-21-23-24": [20 21 23 24], "bet-22-23-25-26": [22 23 25 26]
    , "bet-23-24-26-27": [23 24 26 27], "bet-25-26-28-29": [25 26 28 29], "bet-26-27-29-30": [26 27 29 30]
    , "bet-28-29-31-32": [28 29 31 32], "bet-29-30-32-33": [29 30 32 33], "bet-31-32-34-35": [31 32 34 35]
    , "bet-32-33-35-36": [32 33 35 36], "bet-1-2-3-4-5-6": [1 2 3 4 5 6], "bet-4-5-6-7-8-9": [4 5 6 7 8 9]
    , "bet-7-8-9-10-11-12": [7 8 9 10 11 12], "bet-10-11-12-13-14-15": [10 11 12 13 14 15]
    , "bet-13-14-15-16-17-18": [13 14 15 16 17 18], "bet-16-17-18-19-20-21": [16 17 18 19 20 21]
    , "bet-19-20-21-22-23-24": [19 20 21 22 23 24], "bet-22-23-24-25-26-27": [22 23 24 25 26 27]
    , "bet-25-26-27-28-29-30": [25 26 27 28 29 30], "bet-28-29-30-31-32-33": [28 29 30 31 32 33]
    , "bet-31-32-33-34-35-36": [31 32 33 34 35 36]
    , "bet-1-4-7-10-13-16-19-22-25-28-31-34": [1 4 7 10 13 16 19 22 25 28 31 34]
    , "bet-2-5-8-11-14-17-20-23-26-29-32-35": [2 5 8 11 14 17 20 23 26 29 32 35]
    , "bet-3-6-9-12-15-18-21-24-27-30-33-36": [3 6 9 12 15 18 21 24 27 30 33 36]
    , "bet-1-12": [1 2 3 4 5 6 7 8 9 10 11 12], "bet-13-24": [13 14 15 16 17 18 19 20 21 22 23 24]
    , "bet-25-36": [25 26 27 28 29 30 31 32 33 34 35 36], "bet-top": [0 1 2 3]
    , "bet-snake": [1 5 9 12 14 16 19 23 27 30 32 34]
    , "bet-odd": [1 3 5 7 9 11 13 15 17 19 21 23 25 27 29 31 33 35]
    , "bet-even": [2 4 6 8 10 12 14 16 18 20 22 24 26 28 30 32 34 36]
    , "bet-red": [1 3 5 7 9 12 14 16 18 19 21 23 25 27 30 32 34 36]
    , "bet-black": [2 4 6 8 10 11 13 15 17 20 22 24 26 28 29 31 33 35]
    , "bet-low": [1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18]
    , "bet-high": [19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36] })

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; ECONOMICS ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ; The wheel's own edge: one number in 37 never pays. Everything economic derives
  ; from it, so it is written once and never as a decimal literal.
  (defconst HOUSE-EDGE:decimal (round (/ 1.0 37.0) 12))

  ; A fee above the edge would give the pot negative expected drift. Immutable.
  (defconst MAX-FEE-RATE:decimal HOUSE-EDGE)

  ; The share of the spare pot one round may put at risk, at deploy. The
  ; operator sets it from here on, including after the freeze. 0.025 sits under
  ; every family's zero-growth crossing, the worst of which is 0.0551 for a
  ; straight-up board; the header carries the simulation behind that choice.
  (defconst LAUNCH-RESERVE-FRACTION:decimal 0.025)
  ; The whole spare pot, and that is the point: the only bound on the share is
  ; the arithmetic one. A round cannot risk more than the pot has spare, so a
  ; share above 1.0 would open a round the pot could not cover. Growth is the
  ; operator's judgement, not this module's -- see the header.
  ; 🔴 At 1.0 the reserve a board books can exceed the table limit it passed,
  ; because the reserve must also cover a VOID refund of every stake: the
  ; `the pot cannot cover this bet` check downstream is what refuses that, and
  ; it is reachable only because this constant is no longer fractional.
  (defconst MAX-RESERVE-FRACTION:decimal 1.0)

  ; The table minimum at deploy, and its floor. The operator sets the minimum
  ; from here on, including after the freeze; the floor is immutable and there
  ; is no ceiling.
  ; 🔴 THE FLOOR IS THE COST OF PAYING A WIN, not a business preference.
  ; A claim costs the house about 445 gas inside a batch and 483 alone, so at a
  ; hundredfold gas price paying one winner costs about 0.0005 KDA. 0.001 is
  ; twice that; below it a bet is worth less than settling it.
  (defconst LAUNCH-MIN-BET:decimal 0.01)
  (defconst MIN-BET-FLOOR:decimal 0.001)

  ; Gas scales with entries placed, so an unbounded list is a gas-exhaustion
  ; vector. The old fixed-158-field board was accidentally immune to this.
  (defconst MAX-ENTRIES:integer 24)

  ; How long a round takes bets. Adjustable for FUTURE rounds only; floored so a
  ; round cannot be made too short to bet in.
  (defconst LAUNCH-BET-WINDOW:decimal 120.0)
  (defconst MIN-BET-WINDOW:decimal 30.0)
  (defconst MAX-BET-WINDOW:decimal 3600.0)

  ; 🔴 THE WAIT BETWEEN THE CLOSE AND THE BEACON, AND WHY IT IS LOAD-BEARING.
  ; Pact's block-time is the PARENT block's time, so a bet is accepted while the
  ; parent's time is <= close-time and can still be mined a whole block interval
  ; later in real time. If the round's pinned beacon were published inside that
  ; gap, anyone watching could read the number and THEN send a winning board --
  ; no mining power needed at all. The wait is the only thing that closes it.
  ; It is an OPERATOR INPUT for FUTURE rounds; a live round keeps the beacon it
  ; was pinned to, so moving the dial can never reach a bet already placed.
  ;
  ; 🔴 SIZED FROM THE MEASURED TAIL, NOT FROM THE POISSON MODEL. Over 120,001
  ; consecutive canonical chain-2 blocks (41.7 days) the mean gap is 30.03 s, the
  ; 99.9th percentile 102.4 s and the longest 136.2 s; 8 gaps passed 120 s and
  ; NONE passed 150 s. Memoryless arithmetic predicts 0.25% of gaps beyond 180 s
  ; and the chain produced zero, because Chainweb's braid stalls its neighbours
  ; within a few heights and the whole hashrate then targets the stalled chain.
  ; So 180 s is nearly 44 s beyond the longest gap ever measured here and six
  ; times the mean, and it costs three minutes of settlement instead of ten.
  ;
  ; 🔴 THE BOUND THAT MATTERS IS THE FLOOR. 7.0% of those gaps exceed 60 s, so at
  ; the floor roughly one round in fourteen would have no block between its close
  ; and its beacon -- exploitable by anyone reading a public value. Below 60 s it
  ; stops being a table at all, which is why the contract refuses it outright.
  ; The 3600 s ceiling is hygiene and nothing more: a wait longer than an hour
  ; delays every settlement and buys nothing the tail does not already cover.
  ;
  ; 🔴 RESIDUAL, DISCLOSED RATHER THAN CLAIMED AWAY: a network halt LONGER than
  ; the wait exposes exactly one round -- the one open when the chain stopped --
  ; up to that round's own cap. A shorter wait changes how often such a halt
  ; could reach a round, never what it costs when it does.
  (defconst LAUNCH-DRAND-MARGIN:decimal 180.0)
  (defconst MIN-DRAND-MARGIN:decimal 60.0)
  (defconst MAX-DRAND-MARGIN:decimal 3600.0)

  ; 🔴 HOW LONG EVERYONE MUST STAY SILENT BEFORE A REFUND OPENS. Ninety days, not
  ; seven, and the length IS the safety argument.
  ;
  ; The module cannot tell "the beacon is unobtainable" from "nobody fetched it",
  ; and no permissionless on-chain construction can -- drand beacons never expire.
  ; So a refund is reachable whenever nobody resolves and nobody proves liveness.
  ; MEASURED at seven days: a player staked 50 on one number, read the public
  ; beacon off-chain, saw they had lost, declined to resolve, waited, voided and
  ; claimed, and ended with EXACTLY their starting balance. A second player, who
  ; had WON 200, was left with only their 100 stake because the void is
  ; round-level -- the loss landed on someone who had not acted.
  ;
  ; Ninety days does not make that impossible; it makes it require the operator
  ; AND every player to ignore the table for a quarter, when ONE `prove-liveness`
  ; call costing ~2,000 gas blocks every pending refund. The condition under which
  ; the option opens is therefore the condition under which the game has been
  ; abandoned -- which is exactly when refunding is the right answer.
  ;
  ; The residual that remains, and belongs in the player terms: a winner must
  ; claim within the window. They can always act alone, permissionlessly, and the
  ; beacon is public, so they can see that they need to.
  (defconst VOID-AFTER:decimal 7776000.0)   ; 90 days

  (defconst PREC:integer 12)
  (defconst GAME-KEY:string "roulette")

  ; 🔴 THE POT'S GUARD, AND WHY IT IS A MODULE GUARD.
  ; coin enforces this guard where the row lives, so whatever it accepts is what
  ; can spend the pot. A module guard passes only while THIS module is on the
  ; call stack; from anywhere else it falls through to module admin, which is
  ; GOVERNANCE, which is `(enforce false)` once frozen. That is a property of the
  ; guard and of nothing else -- no engine version, no fork, no capability scope.
  ; A capability guard over a `true`-bodied capability would instead be exactly
  ; as strong as the engine's rule on composing a foreign capability on the day
  ; it runs, and a module that can never be replaced cannot afford to depend on
  ; that. Built inside a defun because the native refuses a bare defconst frame.
  ;
  ; FOUR RESIDUALS, AND ALL FOUR ARE PERMANENT:
  ;  1. The native is DEPRECATED (the static gate warns on it, and this comment
  ;     is the justification the gate asks for). It is still present in 5.4.1 and
  ;     no removal is scheduled; a guard that freezes outlives the deprecation
  ;     notice, and no capability guard gives the same fork-independence.
  ;  2. UNTIL THE FREEZE, MODULE ADMIN CAN SPEND THE POT. The fallback runs
  ;     GOVERNANCE, so the spt-gov keyset satisfies this guard from anywhere: a
  ;     STRANGER fails, this key never does. That is custody, it is disclosed in
  ;     the player terms, and freezing is what ends it.
  ;  3. THIS MODULE CAN NEVER BE RENAMED OR MOVED. The principal contains the
  ;     module name, so a rename is a different account and abandons the pot.
  ;  4. THE GUARD, AND THEREFORE THE ACCOUNT, IS FIXED AT FIRST FUNDING -- before
  ;     the freeze, not at it. Changing it changes the principal, and a frozen
  ;     module can never sweep the old one.
  (defun pot-guard:guard () (create-module-guard "roulette-pot"))

  (defconst HOUSE_ACCOUNT:string (create-principal (pot-guard)))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; CAPABILITIES ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ; 🔴 UPGRADE AUTHORITY ONLY. Freezing this module means replacing this body
  ; with (enforce false ...) and changing NOTHING ELSE -- founder, 2026-09-20:
  ; "when freezed, the only thing that changes is that the module is no longer
  ; upgradable, everything else should work as always and expected."
  ; That is only true if no operational function depends on this capability, so
  ; none does: they use ADMIN below. roulette-frozen-testing.repl pins it by
  ; running the whole lifecycle against a copy whose body is already (enforce
  ; false), and it goes RED the moment an operation is gated on GOVERNANCE.
  ; It also means the frozen code can still be DEPLOYED to a new chain and
  ; initialised there -- a fresh deploy needs no module admin, only an upgrade does.
  (defcap GOVERNANCE ()
    (enforce false "this module is frozen: it can never be upgraded"))

  ; Operational authority: initialize, set-params, withdraw-house. The SAME
  ; keyset as GOVERNANCE today (spt-gov, 2-of-3 of pink/purple/red), deliberately
  ; a DIFFERENT capability, so a freeze cannot strand the pot's capital or stop a
  ; chain being opened. Two devices per admin action is the estate's rule for
  ; anything that moves value out (ADR-037): withdraw-house does.
  (defcap ADMIN ()
    (enforce-guard (keyset-ref-guard "n_48867b242317a0216a67f8c7ca26696b5878e0e3.spt-gov")))

  (defcap PRIVATE:bool () true)

  (defcap BET-PLACED:bool  (account:string seq:integer stake:decimal reserve:decimal) @event true)
  (defcap ROUND-OPENED:bool (seq:integer close-time:time drand-round:integer) @event true)
  (defcap SPIN-RESULT:bool (seq:integer number:integer drand-round:integer) @event true)
  (defcap CLAIMED:bool     (account:string seq:integer amount:decimal) @event true)
  (defcap ROUND-VOID:bool  (seq:integer stake:decimal) @event true)
  (defcap LIVENESS-PROVEN:bool (drand-round:integer) @event true)
  (defcap FEE-PAID:bool    (seq:integer amount:decimal to:string) @event true)
  (defcap HOUSE-FUNDED:bool    (funder:string amount:decimal) @event true)
  (defcap HOUSE-WITHDRAWN:bool (to:string amount:decimal) @event true)
  (defcap PARAMS-SET:bool  (reserve-fraction:decimal min-bet:decimal target-float:decimal bet-window:decimal drand-margin:decimal) @event true)
  (defcap INITIALIZED:bool (revenue:string) @event true)

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; SCHEMAS ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (defschema entry
    @doc "One chip on the table: a bet key from BET-NUMBERS and its stake."
    key:string
    amt:decimal)

  (defschema game
    last-beacon:integer      ; highest drand round this module has ever VERIFIED
    round-seq:integer        ; last round opened
    current:integer          ; the round currently taking bets, 0 = none
    reserved:decimal         ; total locked across every unsettled round
    revenue:string           ; SPT treasury account, set once at initialize
    reserve-fraction:decimal
    target-float:decimal
    bet-window:decimal
    min-bet:decimal
    drand-margin:decimal)    ; the wait a NEW round puts between its close and its beacon

  (defschema spin
    avail-at-open:decimal    ; the pot's unreserved capital when this round opened
    frac-at-open:decimal     ; and the reserve fraction in force then
    min-bet-at-open:decimal  ; and the table minimum -- a live round keeps all three
    close-time:time          ; last block-time at which a bet is accepted
    drand-round:integer      ; pinned at open, published only after close-time
    exposure:[decimal]       ; 37 slots: what the house owes if n wins
    stake:decimal            ; total staked into this round
    fee-owed:decimal         ; accrued at bet, paid once at resolve
    reserve:decimal          ; what this round locks: max(max(exposure), stake) + fee-owed
    state:string             ; "open" | "resolved" | "void"
    number:integer           ; -1 until resolved
    liability:decimal)       ; owed to winners (or refundable), decremented by claims

  (defschema board
    seq:integer
    account:string
    entries:[object{entry}]
    stake:decimal
    claimed:bool)

  (deftable game-table:{game})
  (deftable rounds:{spin})
  (deftable boards:{board})

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; RULE TABLES ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ; The specification. Unchanged, and pinned by roulette-rules-testing.repl.
  (defun winning-bets:[string] (n:integer)
    @doc "The bet keys that WIN when the wheel lands on number n (verbatim roulette rules)."
    (cond 
            ((= n 0) ["bet-0" "bet-0-1" "bet-0-2" "bet-0-3" "bet-0-1-2" "bet-0-2-3" "bet-top"])
            ((= n 1) ["bet-1" "bet-0-1" "bet-0-1-2" "bet-1-2" "bet-1-4" "bet-1-2-3" "bet-1-2-4-5" "bet-1-2-3-4-5-6"
            "bet-1-4-7-10-13-16-19-22-25-28-31-34" "bet-1-12" "bet-top" "bet-snake" "bet-odd" "bet-red" "bet-low"])
            ((= n 2) ["bet-2" "bet-0-2" "bet-0-1-2" "bet-0-2-3" "bet-1-2" "bet-2-3" "bet-2-5" "bet-1-2-3" "bet-1-2-4-5" "bet-2-3-5-6" "bet-1-2-3-4-5-6"
            "bet-2-5-8-11-14-17-20-23-26-29-32-35" "bet-1-12" "bet-top" "bet-even" "bet-black" "bet-low"])
            ((= n 3) ["bet-3" "bet-0-3" "bet-0-2-3" "bet-2-3" "bet-3-6" "bet-1-2-3" "bet-2-3-5-6" "bet-1-2-3-4-5-6"  
            "bet-3-6-9-12-15-18-21-24-27-30-33-36" "bet-1-12" "bet-top" "bet-odd" "bet-red" "bet-low"])
            ((= n 4) ["bet-4" "bet-4-5" "bet-1-4" "bet-4-7" "bet-4-5-6" "bet-1-2-4-5" "bet-4-5-7-8" "bet-1-2-3-4-5-6" "bet-4-5-6-7-8-9"
            "bet-1-4-7-10-13-16-19-22-25-28-31-34" "bet-1-12" "bet-even" "bet-black" "bet-low"])
            ((= n 5) ["bet-5" "bet-4-5" "bet-5-6" "bet-2-5" "bet-5-8" "bet-4-5-6" "bet-1-2-4-5" "bet-2-3-5-6" "bet-4-5-7-8" "bet-5-6-8-9" "bet-1-2-3-4-5-6" "bet-4-5-6-7-8-9"
            "bet-2-5-8-11-14-17-20-23-26-29-32-35" "bet-1-12" "bet-snake" "bet-odd" "bet-red" "bet-low"])
            ((= n 6) ["bet-6" "bet-5-6" "bet-3-6" "bet-6-9" "bet-4-5-6" "bet-2-3-5-6" "bet-5-6-8-9" "bet-1-2-3-4-5-6" "bet-4-5-6-7-8-9"
            "bet-3-6-9-12-15-18-21-24-27-30-33-36" "bet-1-12" "bet-even" "bet-black" "bet-low"])
            ((= n 7) ["bet-7" "bet-7-10" "bet-7-8" "bet-4-7" "bet-7-8-9" "bet-4-5-7-8" "bet-7-8-10-11" "bet-4-5-6-7-8-9" "bet-7-8-9-10-11-12"
            "bet-1-4-7-10-13-16-19-22-25-28-31-34" "bet-1-12" "bet-odd" "bet-red" "bet-low"])
            ((= n 8) ["bet-8" "bet-8-11" "bet-7-8" "bet-8-9" "bet-5-8" "bet-7-8-9" "bet-4-5-7-8" "bet-5-6-8-9" "bet-7-8-10-11" "bet-8-9-11-12" "bet-4-5-6-7-8-9" "bet-7-8-9-10-11-12" 
            "bet-2-5-8-11-14-17-20-23-26-29-32-35" "bet-1-12" "bet-even" "bet-black" "bet-low"])
            ((= n 9) ["bet-9" "bet-9-12" "bet-8-9" "bet-6-9" "bet-7-8-9" "bet-5-6-8-9" "bet-8-9-11-12" "bet-4-5-6-7-8-9" "bet-7-8-9-10-11-12"
            "bet-3-6-9-12-15-18-21-24-27-30-33-36" "bet-1-12" "bet-snake" "bet-odd" "bet-red" "bet-low"])
            ((= n 10) ["bet-10" "bet-7-10" "bet-10-11" "bet-10-13" "bet-10-11-12" "bet-7-8-10-11" "bet-10-11-13-14" "bet-7-8-9-10-11-12" "bet-10-11-12-13-14-15" 
            "bet-1-4-7-10-13-16-19-22-25-28-31-34" "bet-1-12" "bet-even" "bet-black" "bet-low"])
            ((= n 11) ["bet-11" "bet-8-11" "bet-10-11" "bet-11-12" "bet-11-14" "bet-10-11-12" "bet-7-8-10-11" "bet-8-9-11-12" "bet-10-11-13-14" "bet-11-12-14-15" "bet-7-8-9-10-11-12" "bet-10-11-12-13-14-15"
            "bet-2-5-8-11-14-17-20-23-26-29-32-35" "bet-1-12" "bet-odd" "bet-black" "bet-low"])
            ((= n 12) ["bet-12" "bet-9-12" "bet-11-12" "bet-12-15" "bet-10-11-12" "bet-8-9-11-12" "bet-11-12-14-15" "bet-7-8-9-10-11-12" "bet-10-11-12-13-14-15" 
            "bet-3-6-9-12-15-18-21-24-27-30-33-36" "bet-1-12" "bet-snake" "bet-even" "bet-red" "bet-low"])
            ((= n 13) ["bet-13" "bet-13-14" "bet-10-13" "bet-13-16" "bet-13-14-15" "bet-10-11-13-14" "bet-13-14-16-17" "bet-10-11-12-13-14-15" "bet-13-14-15-16-17-18"
            "bet-1-4-7-10-13-16-19-22-25-28-31-34" "bet-13-24" "bet-odd" "bet-black" "bet-low"])
            ((= n 14) ["bet-14" "bet-13-14" "bet-14-15" "bet-11-14" "bet-14-17" "bet-13-14-15" "bet-10-11-13-14" "bet-11-12-14-15" "bet-13-14-16-17" "bet-14-15-17-18" "bet-10-11-12-13-14-15" "bet-13-14-15-16-17-18"
            "bet-2-5-8-11-14-17-20-23-26-29-32-35" "bet-13-24" "bet-snake" "bet-even" "bet-red" "bet-low"])
            ((= n 15) ["bet-15" "bet-14-15" "bet-12-15" "bet-15-18" "bet-13-14-15" "bet-11-12-14-15" "bet-14-15-17-18" "bet-10-11-12-13-14-15" "bet-13-14-15-16-17-18"
            "bet-3-6-9-12-15-18-21-24-27-30-33-36" "bet-13-24" "bet-odd" "bet-black" "bet-low"])
            ((= n 16) ["bet-16" "bet-16-19" "bet-16-17" "bet-13-16" "bet-16-17-18" "bet-13-14-16-17" "bet-16-17-19-20" "bet-13-14-15-16-17-18" "bet-16-17-18-19-20-21"
            "bet-1-4-7-10-13-16-19-22-25-28-31-34" "bet-13-24" "bet-snake" "bet-even" "bet-red" "bet-low"])
            ((= n 17) ["bet-17" "bet-17-20" "bet-16-17" "bet-17-18" "bet-14-17" "bet-16-17-18" "bet-13-14-16-17" "bet-14-15-17-18" "bet-16-17-19-20" "bet-17-18-20-21" "bet-13-14-15-16-17-18" "bet-16-17-18-19-20-21"
            "bet-2-5-8-11-14-17-20-23-26-29-32-35" "bet-13-24" "bet-odd" "bet-black" "bet-low"])
            ((= n 18) ["bet-18" "bet-18-21" "bet-17-18" "bet-15-18" "bet-16-17-18" "bet-14-15-17-18" "bet-17-18-20-21" "bet-13-14-15-16-17-18" "bet-16-17-18-19-20-21"
            "bet-3-6-9-12-15-18-21-24-27-30-33-36" "bet-13-24" "bet-even" "bet-red" "bet-low"])
            ((= n 19) ["bet-19" "bet-16-19" "bet-19-20" "bet-19-22" "bet-19-20-21" "bet-16-17-19-20" "bet-19-20-22-23" "bet-16-17-18-19-20-21" "bet-19-20-21-22-23-24"
            "bet-1-4-7-10-13-16-19-22-25-28-31-34" "bet-13-24" "bet-snake" "bet-odd" "bet-red" "bet-high"])
            ((= n 20) ["bet-20" "bet-17-20" "bet-19-20" "bet-20-21" "bet-20-23" "bet-19-20-21" "bet-16-17-19-20" "bet-17-18-20-21" "bet-19-20-22-23" "bet-20-21-23-24" "bet-16-17-18-19-20-21" "bet-19-20-21-22-23-24"
            "bet-2-5-8-11-14-17-20-23-26-29-32-35" "bet-13-24" "bet-even" "bet-black" "bet-high"])
            ((= n 21) ["bet-21" "bet-18-21" "bet-20-21" "bet-21-24" "bet-19-20-21" "bet-17-18-20-21" "bet-20-21-23-24" "bet-16-17-18-19-20-21" "bet-19-20-21-22-23-24"
            "bet-3-6-9-12-15-18-21-24-27-30-33-36" "bet-13-24" "bet-odd" "bet-red" "bet-high"])
            ((= n 22) ["bet-22" "bet-22-23" "bet-19-22" "bet-22-25" "bet-22-23-24" "bet-19-20-22-23" "bet-22-23-25-26" "bet-19-20-21-22-23-24" "bet-22-23-24-25-26-27"
            "bet-1-4-7-10-13-16-19-22-25-28-31-34" "bet-13-24" "bet-even" "bet-black" "bet-high"])
            ((= n 23) ["bet-23" "bet-22-23" "bet-23-24" "bet-20-23" "bet-23-26" "bet-22-23-24" "bet-19-20-22-23" "bet-20-21-23-24" "bet-22-23-25-26" "bet-23-24-26-27" "bet-19-20-21-22-23-24" "bet-22-23-24-25-26-27"
            "bet-2-5-8-11-14-17-20-23-26-29-32-35" "bet-13-24" "bet-snake" "bet-odd" "bet-red" "bet-high"])
            ((= n 24) ["bet-24" "bet-23-24" "bet-21-24" "bet-24-27" "bet-22-23-24" "bet-20-21-23-24" "bet-23-24-26-27" "bet-19-20-21-22-23-24" "bet-22-23-24-25-26-27"
            "bet-3-6-9-12-15-18-21-24-27-30-33-36" "bet-13-24" "bet-even" "bet-black" "bet-high"])
            ((= n 25) ["bet-25" "bet-25-28" "bet-25-26" "bet-22-25" "bet-25-26-27" "bet-22-23-25-26" "bet-25-26-28-29" "bet-22-23-24-25-26-27" "bet-25-26-27-28-29-30"
            "bet-1-4-7-10-13-16-19-22-25-28-31-34" "bet-25-36" "bet-odd" "bet-red" "bet-high"])
            ((= n 26) ["bet-26" "bet-26-29" "bet-25-26" "bet-26-27" "bet-23-26" "bet-25-26-27" "bet-22-23-25-26" "bet-23-24-26-27" "bet-25-26-28-29" "bet-26-27-29-30" "bet-22-23-24-25-26-27" "bet-25-26-27-28-29-30"
            "bet-2-5-8-11-14-17-20-23-26-29-32-35" "bet-25-36" "bet-even" "bet-black" "bet-high"])
            ((= n 27) ["bet-27" "bet-27-30" "bet-26-27" "bet-24-27" "bet-25-26-27" "bet-23-24-26-27" "bet-26-27-29-30" "bet-22-23-24-25-26-27" "bet-25-26-27-28-29-30"
            "bet-3-6-9-12-15-18-21-24-27-30-33-36" "bet-25-36" "bet-snake" "bet-odd" "bet-red" "bet-high"])
            ((= n 28) ["bet-28" "bet-25-28" "bet-28-29" "bet-28-31" "bet-28-29-30" "bet-25-26-28-29" "bet-28-29-31-32" "bet-25-26-27-28-29-30" "bet-28-29-30-31-32-33"
            "bet-1-4-7-10-13-16-19-22-25-28-31-34" "bet-25-36" "bet-even" "bet-black" "bet-high"])
            ((= n 29) ["bet-29" "bet-26-29" "bet-28-29" "bet-29-30" "bet-29-32" "bet-28-29-30" "bet-25-26-28-29" "bet-26-27-29-30" "bet-28-29-31-32" "bet-29-30-32-33" "bet-25-26-27-28-29-30" "bet-28-29-30-31-32-33"
            "bet-2-5-8-11-14-17-20-23-26-29-32-35" "bet-25-36" "bet-odd" "bet-black" "bet-high"])
            ((= n 30) ["bet-30" "bet-27-30" "bet-29-30" "bet-30-33" "bet-28-29-30" "bet-26-27-29-30" "bet-29-30-32-33" "bet-25-26-27-28-29-30" "bet-28-29-30-31-32-33"
            "bet-3-6-9-12-15-18-21-24-27-30-33-36" "bet-25-36" "bet-snake" "bet-even" "bet-red" "bet-high"])
            ((= n 31) ["bet-31" "bet-31-32" "bet-28-31" "bet-31-34" "bet-31-32-33" "bet-28-29-31-32" "bet-31-32-34-35" "bet-28-29-30-31-32-33" "bet-31-32-33-34-35-36"
            "bet-1-4-7-10-13-16-19-22-25-28-31-34" "bet-25-36" "bet-odd" "bet-black" "bet-high"])
            ((= n 32) ["bet-32" "bet-31-32" "bet-32-33" "bet-29-32" "bet-32-35" "bet-31-32-33" "bet-28-29-31-32" "bet-29-30-32-33" "bet-31-32-34-35" "bet-32-33-35-36" "bet-28-29-30-31-32-33" "bet-31-32-33-34-35-36"
            "bet-2-5-8-11-14-17-20-23-26-29-32-35" "bet-25-36" "bet-snake" "bet-even" "bet-red" "bet-high"])
            ((= n 33) ["bet-33" "bet-32-33" "bet-30-33" "bet-33-36" "bet-31-32-33" "bet-29-30-32-33" "bet-32-33-35-36" "bet-28-29-30-31-32-33" "bet-31-32-33-34-35-36"
            "bet-3-6-9-12-15-18-21-24-27-30-33-36" "bet-25-36" "bet-odd" "bet-black" "bet-high"])
            ((= n 34) ["bet-34" "bet-34-35" "bet-31-34" "bet-34-35-36" "bet-31-32-34-35" "bet-31-32-33-34-35-36"
            "bet-1-4-7-10-13-16-19-22-25-28-31-34" "bet-25-36" "bet-snake" "bet-even" "bet-red" "bet-high"])
            ((= n 35) ["bet-35" "bet-34-35" "bet-35-36" "bet-32-35" "bet-34-35-36" "bet-31-32-34-35" "bet-32-33-35-36" "bet-31-32-33-34-35-36"
            "bet-2-5-8-11-14-17-20-23-26-29-32-35" "bet-25-36" "bet-odd" "bet-black" "bet-high"])
            ((= n 36) ["bet-36" "bet-35-36" "bet-33-36" "bet-34-35-36" "bet-32-33-35-36" "bet-31-32-33-34-35-36"
            "bet-3-6-9-12-15-18-21-24-27-30-33-36" "bet-25-36" "bet-even" "bet-red" "bet-high"])
            false))

  (defun payout-mult:decimal (x:string)
    @doc "Payout multiplier for a winning bet key (35:1 straight ... 1:1 even-money; verbatim)."
    (cond
                     ; Single bets payout 35 to 1
                     ((= x "bet-0") 35.0)
                     ((= x "bet-1") 35.0)       ((= x "bet-2") 35.0)       ((= x "bet-3") 35.0)
                     ((= x "bet-4") 35.0)       ((= x "bet-5") 35.0)       ((= x "bet-6") 35.0)
                     ((= x "bet-7") 35.0)       ((= x "bet-8") 35.0)       ((= x "bet-9") 35.0)
                     ((= x "bet-10") 35.0)      ((= x "bet-11") 35.0)      ((= x "bet-12") 35.0)
                     ((= x "bet-13") 35.0)      ((= x "bet-14") 35.0)      ((= x "bet-15") 35.0)
                     ((= x "bet-16") 35.0)      ((= x "bet-17") 35.0)      ((= x "bet-18") 35.0)
                     ((= x "bet-19") 35.0)      ((= x "bet-20") 35.0)      ((= x "bet-21") 35.0)
                     ((= x "bet-22") 35.0)      ((= x "bet-23") 35.0)      ((= x "bet-24") 35.0)
                     ((= x "bet-25") 35.0)      ((= x "bet-26") 35.0)      ((= x "bet-27") 35.0)
                     ((= x "bet-28") 35.0)      ((= x "bet-29") 35.0)      ((= x "bet-30") 35.0)
                     ((= x "bet-31") 35.0)      ((= x "bet-32") 35.0)      ((= x "bet-33") 35.0)
                     ((= x "bet-34") 35.0)      ((= x "bet-35") 35.0)      ((= x "bet-36") 35.0)
                     ; Split bets payout 17 to 1
                     ((= x "bet-1-2") 17.0)     ((= x "bet-2-3") 17.0)     ((= x "bet-4-5") 17.0)
                     ((= x "bet-5-6") 17.0)     ((= x "bet-7-8") 17.0)     ((= x "bet-8-9") 17.0)
                     ((= x "bet-10-11") 17.0)   ((= x "bet-11-12") 17.0)   ((= x "bet-13-14") 17.0)
                     ((= x "bet-14-15") 17.0)   ((= x "bet-16-17") 17.0)   ((= x "bet-17-18") 17.0)
                     ((= x "bet-19-20") 17.0)   ((= x "bet-20-21") 17.0)   ((= x "bet-22-23") 17.0)
                     ((= x "bet-23-24") 17.0)   ((= x "bet-25-26") 17.0)   ((= x "bet-26-27") 17.0)
                     ((= x "bet-28-29") 17.0)   ((= x "bet-29-30") 17.0)   ((= x "bet-31-32") 17.0)
                     ((= x "bet-32-33") 17.0)   ((= x "bet-34-35") 17.0)   ((= x "bet-35-36") 17.0)
                     ((= x "bet-1-4") 17.0)     ((= x "bet-2-5") 17.0)     ((= x "bet-3-6") 17.0)
                     ((= x "bet-4-7") 17.0)     ((= x "bet-5-8") 17.0)     ((= x "bet-6-9") 17.0)
                     ((= x "bet-10-13") 17.0)   ((= x "bet-11-14") 17.0)   ((= x "bet-12-15") 17.0)
                     ((= x "bet-13-16") 17.0)   ((= x "bet-14-17") 17.0)   ((= x "bet-15-18") 17.0)
                     ((= x "bet-19-22") 17.0)   ((= x "bet-20-23") 17.0)   ((= x "bet-21-24") 17.0)
                     ((= x "bet-22-25") 17.0)   ((= x "bet-23-26") 17.0)   ((= x "bet-24-27") 17.0)
                     ((= x "bet-28-31") 17.0)   ((= x "bet-29-32") 17.0)   ((= x "bet-30-33") 17.0)
                     ((= x "bet-31-34") 17.0)   ((= x "bet-32-35") 17.0)   ((= x "bet-33-36") 17.0)
                     ((= x "bet-7-10") 17.0)    ((= x "bet-8-11") 17.0)    ((= x "bet-9-12") 17.0)
                     ((= x "bet-16-19") 17.0)   ((= x "bet-17-20") 17.0)   ((= x "bet-18-21") 17.0)
                     ((= x "bet-25-28") 17.0)   ((= x "bet-26-29") 17.0)   ((= x "bet-27-30") 17.0)
                     ; Zero split payout 17 to 1
                     ((= x "bet-0-1") 17.0)     ((= x "bet-0-2") 17.0)     ((= x "bet-0-3") 17.0)
                     ; Street payout 11 to 1 
                     ((= x "bet-1-2-3") 11.0)
                     ((= x "bet-4-5-6") 11.0)
                     ((= x "bet-7-8-9") 11.0)
                     ((= x "bet-10-11-12") 11.0)
                     ((= x "bet-13-14-15") 11.0)
                     ((= x "bet-16-17-18") 11.0)
                     ((= x "bet-19-20-21") 11.0)
                     ((= x "bet-22-23-24") 11.0)
                     ((= x "bet-25-26-27") 11.0)
                     ((= x "bet-28-29-30") 11.0)
                     ((= x "bet-31-32-33") 11.0)
                     ((= x "bet-34-35-36") 11.0)
                     ; Trio payout 11 to 1
                     ((= x "bet-0-1-2") 11.0)
                     ((= x "bet-0-2-3") 11.0)
                     ; Corner payout 8 to 1
                     ((= x "bet-1-2-4-5") 8.0)        ((= x "bet-2-3-5-6") 8.0)
                     ((= x "bet-4-5-7-8") 8.0)        ((= x "bet-5-6-8-9") 8.0)
                     ((= x "bet-7-8-10-11") 8.0)      ((= x "bet-8-9-11-12") 8.0)
                     ((= x "bet-10-11-13-14") 8.0)    ((= x "bet-11-12-14-15") 8.0)
                     ((= x "bet-13-14-16-17") 8.0)    ((= x "bet-14-15-17-18") 8.0)
                     ((= x "bet-16-17-19-20") 8.0)    ((= x "bet-17-18-20-21") 8.0)
                     ((= x "bet-19-20-22-23") 8.0)    ((= x "bet-20-21-23-24") 8.0)
                     ((= x "bet-22-23-25-26") 8.0)    ((= x "bet-23-24-26-27") 8.0)
                     ((= x "bet-25-26-28-29") 8.0)    ((= x "bet-26-27-29-30") 8.0)
                     ((= x "bet-28-29-31-32") 8.0)    ((= x "bet-29-30-32-33") 8.0)
                     ((= x "bet-31-32-34-35") 8.0)    ((= x "bet-32-33-35-36") 8.0)
                     ; Double Street payout 5 to 1 
                     ((= x "bet-1-2-3-4-5-6") 5.0)
                     ((= x "bet-4-5-6-7-8-9") 5.0)
                     ((= x "bet-7-8-9-10-11-12") 5.0)
                     ((= x "bet-10-11-12-13-14-15") 5.0)
                     ((= x "bet-13-14-15-16-17-18") 5.0)
                     ((= x "bet-16-17-18-19-20-21") 5.0)
                     ((= x "bet-19-20-21-22-23-24") 5.0)
                     ((= x "bet-22-23-24-25-26-27") 5.0)
                     ((= x "bet-25-26-27-28-29-30") 5.0)
                     ((= x "bet-28-29-30-31-32-33") 5.0)
                     ((= x "bet-31-32-33-34-35-36") 5.0)
                     ; Column payout 2 to 1
                     ((= x "bet-1-4-7-10-13-16-19-22-25-28-31-34") 2.0)
                     ((= x "bet-2-5-8-11-14-17-20-23-26-29-32-35") 2.0)
                     ((= x "bet-3-6-9-12-15-18-21-24-27-30-33-36") 2.0)
                     ; First Dozen payout 2 to 1
                     ((= x "bet-1-12") 2.0)
                     ; Second Dozen payout 2 to 1
                     ((= x "bet-13-24") 2.0)
                     ; Third Dozen payout 2 to 1
                     ((= x "bet-25-36") 2.0)
                     ; Top payout 8 to 1
                     ((= x "bet-top") 8.0)
                     ; Snake payout 2 to 1
                     ((= x "bet-snake") 2.0)
                     ; Odd payout 1 to 1
                     ((= x "bet-odd") 1.0)
                     ; Even payout 1 to 1
                     ((= x "bet-even") 1.0)
                     ; Red payout 1 to 1
                     ((= x "bet-red") 1.0)
                     ; Back payout 1 to 1
                     ((= x "bet-black") 1.0)
                     ; Low payout 1 to 1
                     ((= x "bet-low") 1.0)
                     ; High payout 1 to 1
                     ((= x "bet-high") 1.0)
                     ; Returns false if any if all false
                     false))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; HELPERS ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (defun curr-time:time () (at 'block-time (chain-data)))
  (defun rkey:string (seq:integer) (int-to-str 10 seq))
  (defun bkey:string (seq:integer account:string) (format "{}|{}" [seq account]))

  (defun vmax:decimal (v:[decimal])
    (fold (lambda (a:decimal b:decimal) (if (> b a) b a)) 0.0 v))

  ; Each entry reduced ONCE to the numbers it covers and what it pays if one hits.
  ; Doing it once matters: payout-mult is a 158-branch cond and the vector pass
  ; below would otherwise call it 37 times per entry.
  (defun prep:[object] (entries:[object{entry}])
    (map (lambda (e:object{entry})
           { "nums": (at (at 'key e) BET-NUMBERS)     ; unknown key aborts here
           , "pay":  (* (at 'amt e) (+ (payout-mult (at 'key e)) 1.0)) })
         entries))

  ; This board's own 37-slot vector: what IT alone would owe on each number.
  (defun own-vector:[decimal] (pre:[object])
    (map (lambda (n:integer)
           (fold (+) 0.0
             (map (lambda (e:object) (if (contains n (at 'nums e)) (at 'pay e) 0.0)) pre)))
         (enumerate 0 36)))

  ; What this board is owed if `n` wins. Same arithmetic as own-vector, one number.
  (defun board-payout:decimal (entries:[object{entry}] n:integer)
    (fold (+) 0.0
      (map (lambda (e:object{entry})
             (if (contains n (at (at 'key e) BET-NUMBERS))
                 (* (at 'amt e) (+ (payout-mult (at 'key e)) 1.0))
                 0.0))
           entries)))

  ; ADR-R2: the fee ramps with the pot's health and never exceeds the wheel's edge.
  ; It comes out of the POT, so a player's return is 36/37 whatever this returns.
  (defun fee-rate:decimal (available:decimal target:decimal)
    (enforce (> target 0.0) "target float must be positive")
    (if (>= available target)
        MAX-FEE-RATE
        ; floor, not round: a half-ulp above the edge is still above the edge.
        ; Difference is 1e-12 and no test distinguishes them; the choice is
        ; deliberate but it is not load-bearing.
        (floor (* MAX-FEE-RATE (/ (if (> available 0.0) available 0.0) target)) PREC)))

  (defun validate-entries:decimal (entries:[object{entry}])
    @doc "Check every chip and return the total staked. All bets must be positive \
    \and coin-precise; duplicate keys are allowed and simply add."
    (enforce (> (length entries) 0) "place at least one bet")
    (enforce (<= (length entries) MAX-ENTRIES)
      (format "at most {} bets on one board" [MAX-ENTRIES]))
    (fold (+) 0.0
      (map (lambda (e:object{entry})
             (let ((a (at 'amt e)))
               (enforce (> a 0.0) "every bet must be positive")
               (enforce-unit a)
               a))
           entries)))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; ADMIN / SETUP ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (defun house-account:string () HOUSE_ACCOUNT)

  (defun initialize:string (revenue:string target-float:decimal)
    @doc "Admin, once: create the pot and record where revenue goes. `revenue` is \
    \a plain account STRING, never a module import -- an import would bind this \
    \module to another module's hash and silently orphan the destination on an \
    \upgrade. The account must already exist so a typo cannot be frozen in."
    (with-capability (ADMIN)
      (validate-account revenue)
      ;; 🔴 A PRINCIPAL, not just any existing account. Checking only that the
      ;; account EXISTS lets a stranger pre-create a plain name like
      ;; "spt-treasury" under their own keyset and have this module pay them every
      ;; fee and every withdrawal forever -- `revenue` has no setter and
      ;; initialize runs once. MEASURED before this line existed.
      ;; 🔴 IT IS A TYPO AND SQUAT GUARD, NOT AN AUTHORITY GUARD. It does not stop
      ;; whoever runs initialize from naming a principal they themselves control:
      ;; a `k:` of their own passes. Measured. Who holds the revenue account is a
      ;; deployment fact, and it belongs in the deploy checklist, not here.
      (enforce (is-principal revenue)
        "revenue must be a principal account (k:, m:, r:, w: or u:), not a claimable name")
      (enforce (!= revenue HOUSE_ACCOUNT) "revenue must not be this module's own pot")
      ;; 🔴 REFUSED BY CLASS, BECAUSE ENUMERATION CANNOT CLOSE IT (audit 5 F1).
      ;; This check previously refused exactly ONE account -- the `c:` over this
      ;; module's PRIVATE capability -- and its comment claimed that was the only
      ;; such principal this module could form. That was FALSE. Measured: a `c:`
      ;; over ADMIN forms just as easily (c:KRrTrDA4tgQMWaBS0pB7OkR4movtQ8WeAoYx19JIrDo),
      ;; so does one over GOVERNANCE, and the eleven @event caps are PARAMETERISED,
      ;; so their principals are not enumerable at all. `initialize` accepted the
      ;; ADMIN one and recorded it as revenue.
      ;; Naming any of them sends every fee and every withdrawal to an account only
      ;; module admin can reach -- and that NOTHING can reach once this module
      ;; freezes. `revenue` has no setter and initialize runs once, so it is
      ;; unrecoverable: exactly the shape Rule 16 says to refuse where it happens.
      ;; Neither a `c:` nor a `p:` can be satisfied by an external signer, and this
      ;; module cannot tell its own capability guards from another module's, so the
      ;; whole class goes. COST TODAY: none -- SPT's FUNDING-ACCOUNT is an `m:`
      ;; module-guard principal. If some future destination were a `c:` of another
      ;; module, the answer is a redeploy, which a setter-less once-only field
      ;; already implies. `k:`, `w:`, `r:`, `u:` and `m:` are unaffected.
      (enforce (and (!= "c:" (take 2 revenue)) (!= "p:" (take 2 revenue)))
        "revenue must be an account an external signer can spend: not a c: or p: principal")
      ; `try`, because get-balance ABORTS on a missing account -- without it this
      ; enforce is unreachable and the operator gets a raw table error instead of
      ; being told what is actually wrong.
      (let ((bal (try -1.0 (get-balance revenue))))
        (enforce (>= bal 0.0) "the revenue account must already exist"))
      ; A zero target float would make the fee rate undefined and abort even the
      ; read-only pot-status, so it is required here rather than left to be set.
      (enforce (> target-float 0.0) "target float must be positive")
      (enforce-unit target-float)
      ; the game row goes in FIRST, so a second initialize fails on it plainly
      (insert game-table GAME-KEY
        { "last-beacon": 0, "round-seq": 0, "current": 0, "reserved": 0.0
        , "revenue": revenue
        , "reserve-fraction": LAUNCH-RESERVE-FRACTION
        , "target-float": target-float
        , "bet-window": LAUNCH-BET-WINDOW
        , "min-bet": LAUNCH-MIN-BET
        , "drand-margin": LAUNCH-DRAND-MARGIN })
      ;; 🔴 HOUSE_ACCOUNT is a principal over this module's own guard, and that
      ;; guard value can be built from TRANSACTION DATA ALONE -- measured, on a
      ;; chain where this module has never been deployed. A stranger can create
      ;; the coin row first, and an unconditional create-account would then abort
      ;; initialize FOREVER on that chain, with no remedy once frozen.
      ;; Tolerating a pre-existing row is safe because coin refuses that name to
      ;; any other guard: creating it under a different guard fails with
      ;; "Reserved protocol guard violation". So a squatted row IS our account.
      (if (< (try -1.0 (get-balance HOUSE_ACCOUNT)) 0.0)
          (create-account HOUSE_ACCOUNT (pot-guard))
          "the pot account already exists")
      (emit-event (INITIALIZED revenue)))
    "roulette initialized")

  (defun fund-house:string (funder:string amount:decimal)
    @doc "Add capital to the pot. Permissionless: anyone may strengthen the bank, \
    \and nothing about doing so grants any claim on it."
    (enforce (> amount 0.0) "amount must be positive")
    (transfer funder HOUSE_ACCOUNT amount)
    (emit-event (HOUSE-FUNDED funder amount))
    "house funded")

  (defun withdraw-house:string (amount:decimal)
    @doc "Admin: move UNRESERVED pot funds to the recorded revenue account. The \
    \destination is not a parameter here -- it is the account fixed once at \
    \initialize. \
    \ \
    \BUT UNTIL THIS MODULE IS FROZEN THAT IS NOT A LIMIT ON THE KEY. The admin \
    \keyset is also module governance, and the pot's guard falls through to module \
    \admin. MEASURED: with module admin acquired, a foreign module moved the WHOLE \
    \pot, 50000 to 0, to an account of the caller's choosing. Until the freeze, \
    \this key is CUSTODY of the pot, and the player terms must say so."
    (enforce (> amount 0.0) "amount must be positive")
    (enforce-unit amount)
    (with-capability (ADMIN)
      (let* ((bal (get-balance HOUSE_ACCOUNT))
             (g (read game-table GAME-KEY))
             (reserved (at 'reserved g))
             (to (at 'revenue g))
             (available (- bal reserved)))
        (enforce (<= amount available)
          (format "withdrawal {} exceeds unreserved balance {}" [amount available]))
        (install-capability (coin.TRANSFER HOUSE_ACCOUNT to amount))
        (transfer HOUSE_ACCOUNT to amount)
        (emit-event (HOUSE-WITHDRAWN to amount))))
    "house withdrawal complete")

  (defun set-params:string (reserve-fraction:decimal min-bet:decimal
                            target-float:decimal bet-window:decimal
                            drand-margin:decimal)
    @doc "Admin: economics for FUTURE rounds. No bound here can be widened by a \
    \setter, the beacon wait is bounded below because a short wait is the \
    \exploitable direction, and a live round keeps the values it opened under -- \
    \including the beacon it was pinned to."
    (enforce (and (> reserve-fraction 0.0) (<= reserve-fraction MAX-RESERVE-FRACTION))
      (format "reserve-fraction must be in (0, {}]" [MAX-RESERVE-FRACTION]))
    (enforce (>= min-bet MIN-BET-FLOOR) (format "min-bet below the floor {}" [MIN-BET-FLOOR]))
    (enforce-unit min-bet)
    (enforce (> target-float 0.0) "target float must be positive")
    (enforce-unit target-float)
    (enforce (and (>= bet-window MIN-BET-WINDOW) (<= bet-window MAX-BET-WINDOW))
      (format "bet-window must be in [{}, {}]" [MIN-BET-WINDOW MAX-BET-WINDOW]))
    (enforce (and (>= drand-margin MIN-DRAND-MARGIN) (<= drand-margin MAX-DRAND-MARGIN))
      (format "drand-margin must be in [{}, {}]" [MIN-DRAND-MARGIN MAX-DRAND-MARGIN]))
    (with-capability (ADMIN)
      (update game-table GAME-KEY
        { "reserve-fraction": reserve-fraction, "min-bet": min-bet
        , "target-float": target-float, "bet-window": bet-window
        , "drand-margin": drand-margin })
      (emit-event (PARAMS-SET reserve-fraction min-bet target-float bet-window drand-margin)))
    "params set")

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; BET ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (defun open-round:integer ()
    @doc "Internal: start a round. It takes NO arguments -- its number, window, \
    \share, minimum and beacon all come from the game row -- and the values it \
    \opens under are the ones it keeps for its whole life."
    (require-capability (PRIVATE))
    ;; 🔴 NOTHING A ROUND OPENS UNDER IS AN ARGUMENT. Pact has no private
    ;; functions, so this is a public export behind an argument-free token: any
    ;; caller who can put PRIVATE in scope calls it directly. Every economic term
    ;; a round freezes -- the share of the pot it may risk, the table minimum, the
    ;; window, the wait that pins its beacon -- is therefore read HERE, from the
    ;; row only ADMIN can write, never accepted from the caller. A caller who
    ;; could name the wait could name a beacon that is already published, and a
    ;; caller who could name the share could put the whole pot on one spin. There
    ;; is no argument left to pick.
    ;; 🔴 ONE READ, bound outside any enforce condition: a table read inside an
    ;; enforce CONDITION is node-regime-dependent and REPL-invisible.
    (with-read game-table GAME-KEY
      { "reserved" := reserved, "round-seq" := prev-seq, "drand-margin" := margin
      , "bet-window" := window, "reserve-fraction" := frac, "min-bet" := min-bet }
      (let* ((seq (+ 1 prev-seq))
             (avail (- (get-balance HOUSE_ACCOUNT) reserved))
             (close (add-time (curr-time) window))
             (dr (round-at (add-time close margin))))
        (insert rounds (rkey seq)
          { "avail-at-open": avail, "frac-at-open": frac, "min-bet-at-open": min-bet
          , "close-time": close, "drand-round": dr
          , "exposure": (make-list 37 0.0)
          , "stake": 0.0, "fee-owed": 0.0, "reserve": 0.0
          , "state": "open", "number": -1, "liability": 0.0 })
        (update game-table GAME-KEY { "round-seq": seq, "current": seq })
        (emit-event (ROUND-OPENED seq close dr))
        seq)))

  (defun bet:string (account:string entries:[object{entry}])
    @doc "Place a board. THE ONLY TRANSACTION A PLAYER SIGNS. Sign coin.TRANSFER \
    \of your total stake. If you win, call claim; if you lose, do nothing."
    (validate-account account)
    (enforce (!= "m:" (take 2 account))
      "a module-guarded account cannot bet: it could not be paid back")
    (with-capability (PRIVATE)
      (with-read game-table GAME-KEY
        { "current" := cur, "reserved" := reserved
        , "target-float" := target, "min-bet" := min-bet }
        (let* ((t (curr-time))
               (stake (validate-entries entries))
               (bal (get-balance HOUSE_ACCOUNT))
               (available (- bal reserved))
               (rate (fee-rate available target))
               (fee (floor (* rate stake) PREC))
               (pre (prep entries))
               (own (own-vector pre)))
          ; keep the open round if it is still taking bets, else start one.
          ;; 🔴 THE MINIMUM IS THE ROUND'S, NOT THE LIVE GAME ROW'S. Reading
          ;; `min-bet` live let a set-params mid-round shut an OPEN round to
          ;; every later player -- a pause by another name, and the one opened
          ;; value FAIR-3 did not cover. A round keeps the window, fraction AND
          ;; minimum it opened under; the live value binds the NEXT round only.
          ;; Key "0" never exists, so before the first round the defaults apply.
          (with-default-read rounds (rkey cur)
            { "state": "none", "close-time": t, "min-bet-at-open": min-bet }
            { "state" := cst, "close-time" := cclose, "min-bet-at-open" := cmb }
          (let* ((keep (and (= "open" cst) (<= t cclose)))
                 (mb (if keep cmb min-bet)))
            (enforce (>= stake mb) "total bet below the table minimum")
          (let ((seq (if keep cur (open-round))))
            ;; F3: one board per account per round. `write` used to CLOBBER an
            ;; earlier board while the round's exposure still counted both, which
            ;; destroyed the first stake and left liability nobody could ever
            ;; claim. Refuse it where it happens: place every chip in one call.
            (with-default-read boards (bkey seq account) { "stake": -1.0 } { "stake" := prior }
              (enforce (< prior 0.0)
                "you already have a board in this round: place every chip in one transaction"))
            (with-read rounds (rkey seq)
              ; 🔴 F3. BOTH operands of the cap come from the ROUND, not the live
              ; game row. Reading the fraction live let set-params retroactively
              ; widen the cap of a round that already had bets in it.
              { "exposure" := ex, "stake" := rstake, "fee-owed" := rfee, "reserve" := rres
              , "avail-at-open" := a0, "frac-at-open" := f0 }
              (let* ((new-ex (zip (lambda (a:decimal b:decimal) (+ a b)) ex own))
                     (new-stake (+ rstake stake))
                     (new-fee (+ rfee fee))
                     ; the reserve must dominate BOTH outcomes: paying the best
                     ; number, and refunding every stake on a void. A diversified
                     ; board nets BELOW its own total (all 37 singles: 36/37), so
                     ; max(exposure) alone would under-reserve a refund.
                     (new-res (+ (vmax [(vmax new-ex) new-stake]) new-fee)))
                ;; 🔴 THE TABLE LIMIT BOUNDS THE ROUND, NOT THE BOARD, and it is
                ;; measured against the pot as it stood when the round OPENED.
                ;; Bounding one board against the CURRENT available lets boards
                ;; stack geometrically: each one only shrinks `available` by its
                ;; own stake, so N correlated boards converge on 100% of house
                ;; capital riding one number. Measured before this fix: 40 boards
                ;; on red put 63.6% of the pot at risk on a single spin -- 23x
                ;; Kelly, while `reserved <= balance` stayed true the whole way.
                ;; Solvency was never the property under attack.
                ;; 🔴 BOUND BY THE SMALLER OF THE POT AT OPEN AND THE POT NOW.
                ;; Freezing `a0` stops the numerator being widened mid-round; it
                ;; does nothing about the DENOMINATOR disappearing. MEASURED: with
                ;; a round open, an admin withdrawal of 95% of the pot left a
                ;; stranger able to put 90.96% of the remaining bank on one spin,
                ;; with no enforce firing. The fraction stays the one frozen at
                ;; open, so a later set-params still cannot widen anything.
                (enforce (<= (+ (vmax new-ex) new-fee)
                             (* f0 (if (< available a0) available a0)))
                  (format "this round's exposure {} would exceed the table limit {}"
                          [(+ (vmax new-ex) new-fee)
                           (* f0 (if (< available a0) available a0))]))
                ;; and what this bet adds must be covered by the pot's OWN spare
                ;; capital, not by the stake arriving with it. 🔴 THIS IS THE
                ;; BINDING CHECK AT THE TOP OF THE RANGE: the table limit bounds
                ;; vmax(new-ex)+new-fee, but the reserve must ALSO cover a void
                ;; refund of every stake, and a board spread across the wheel
                ;; stakes more than its own best pocket pays -- so with the share
                ;; at the whole spare pot a board satisfies the table limit and
                ;; still books a reserve larger than the spare pot. Refused here.
                ;; 🔴 AND IT IS A CONSERVATIVE OVER-REFUSAL, NOT THE SOLVENCY
                ;; CHECK. MEASURED with this line alone removed and the table
                ;; limit kept: the CF-6 board is accepted and `reserved`
                ;; (51,369.86) still stays under `balance` (100,684.93), because
                ;; a stake funds its own refund reserve on the way in. Literal
                ;; solvency comes from the table limit plus self-funding stakes;
                ;; what this line adds is that a round's reserve is backed by
                ;; capital the house already had. Pinned by CF-6, which pins the
                ;; refusal -- the intended behaviour -- not the solvency.
                (enforce (<= (- new-res rres) available)
                  "the pot cannot cover this bet")
                (update rounds (rkey seq)
                  { "exposure": new-ex, "stake": new-stake
                  , "fee-owed": new-fee, "reserve": new-res })
                (update game-table GAME-KEY
                  { "reserved": (+ reserved (- new-res rres)) })
                (transfer account HOUSE_ACCOUNT stake)
                (insert boards (bkey seq account)
                  { "seq": seq, "account": account, "entries": entries
                  , "stake": stake, "claimed": false })
                (emit-event (BET-PLACED account seq stake (- new-res rres)))
                (format "bet placed in round {}" [seq]))))))))))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; RESOLVE ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (defun resolve:integer (seq:integer sig-hex:string)
    @doc "Fix this round's number from the drand beacon. PERMISSIONLESS and \
    \unprivileged: a forged signature cannot verify, and the value never expires, \
    \so there is no window to miss. Winners resolve to be paid; on a round the \
    \house wins outright the house resolves to free its own reserve."
    (with-capability (PRIVATE)
      (with-read rounds (rkey seq)
        { "state" := st, "drand-round" := dr, "exposure" := ex
        , "fee-owed" := fee, "reserve" := res }
        (enforce (= "open" st) "this round is already settled")
        ; No time check is needed: the beacon for a round that is not yet
        ; published does not exist, so verified-seed cannot succeed early.
        (let* ((seed (verified-seed (format "roulette|{}" [seq]) dr sig-hex))
               ; Modulo bias here is bounded by 37/2^256, i.e. ~1e-75.
               (n (at (mod seed 37) ROULETTE))
               (liab (at n ex)))
          ; fee-owed is zeroed because it is PAID below. Leaving a settled
          ; liability on the row would misread as still outstanding.
          (update rounds (rkey seq)
            { "state": "resolved", "number": n, "liability": liab, "fee-owed": 0.0 })
          (with-read game-table GAME-KEY
            { "reserved" := reserved, "revenue" := rev, "last-beacon" := lb }
            ; A verified beacon is PROOF drand was alive at that round. Recording
            ; the high-water mark is what lets void-round tell "the beacon never
            ; came" apart from "nobody bothered to fetch it".
            (update game-table GAME-KEY
              { "reserved": (- reserved (- res liab))
              , "last-beacon": (if (> dr lb) dr lb) })
            ; the `let` is only there to sequence: an `if` branch is one expression
            (if (> fee 0.0)
                (let ((dest rev))
                  (install-capability (coin.TRANSFER HOUSE_ACCOUNT dest fee))
                  (transfer HOUSE_ACCOUNT dest fee)
                  (emit-event (FEE-PAID seq fee dest))
                  "fee paid")
                "no fee"))
          (emit-event (SPIN-RESULT seq n dr))
          n))))

  (defun prove-liveness:integer (rnd:integer sig-hex:string)
    @doc "Permissionless: verify a drand beacon and record that drand was alive \
    \at that round. Settles nothing, pays nothing, moves no money. ONE call \
    \blocks a premature refund on EVERY pending round whose beacon is at or \
    \below `rnd`, which is why it exists separately from resolve."
    ;; 🔴 WHY THIS IS HERE. `last-beacon` used to be raised only by `resolve`, so
    ;; "drand went away" was indistinguishable from "nobody settled this round" --
    ;; and the second is the attacker's own choice. MEASURED before this existed:
    ;; a player staked 50 on one number, read the public beacon off-chain, saw the
    ;; round had landed elsewhere, declined to resolve, waited out VOID-AFTER,
    ;; voided and claimed, and ended with EXACTLY their starting balance. The
    ;; losing bet cost nothing. This lets anyone keep the record current without
    ;; settling anything.
    ;;
    ;; It cannot be abused to block a legitimate refund: `rnd` only verifies if
    ;; drand actually published it, so `last-beacon` can never run ahead of drand.
    ;; And a round with `drand-round <= last-beacon` is never stranded -- it is
    ;; un-voidable precisely because its own beacon demonstrably exists.
    (with-capability (PRIVATE)
      (let ((seed (verified-seed "liveness" rnd sig-hex)))
        ;; 🔴 NOT A CHECK (audit 5 F5): `verified-seed` ABORTS on a bad signature, so
    ;; it never returns to be tested, and a zero seed would need an all-zero
    ;; 256-bit hash. Survives deletion. Kept as a belt on a value that decides
    ;; whether a round can still be settled; it costs one comparison.
    (enforce (!= seed 0) "beacon did not verify")
        (with-read game-table GAME-KEY { "last-beacon" := lb }
          (enforce (> rnd lb) "a later beacon is already on record")
          (update game-table GAME-KEY { "last-beacon": rnd })
          (emit-event (LIVENESS-PROVEN rnd))
          rnd))))

  (defun void-round:string (seq:integer)
    @doc "Refund a round whose beacon can never arrive. Permissionless. Requires \
    \on-chain evidence that drand has not been seen since -- elapsed time alone \
    \is not enough, because a losing player can read the public beacon off-chain \
    \and would otherwise just wait out the clock and take a refund instead."
    (with-read rounds (rkey seq)
      { "state" := st, "drand-round" := dr, "reserve" := res, "stake" := stk }
      (enforce (= "open" st) "this round is not open")
      (enforce (> (diff-time (curr-time) (time-of-round dr)) VOID-AFTER)
        "the beacon can still be submitted")
      ;; 🔴 THE CHECK THAT NARROWS THE FREE OPTION -- it does not close it. If this module has verified a
      ;; beacon at or after this round's, drand was demonstrably alive by then and
      ;; this round's beacon was obtainable -- so the round must be resolved, not
      ;; refunded. Measured 2026-09-20: drand evmnet has produced 20,808,324
      ;; rounds over 722 days with no gap found in 240 samples spread across its
      ;; whole history, so the real failure mode is the network being RETIRED,
      ;; not an outage. A refund must answer that, and nothing else.
      ;;
      ;; 🔴 RESIDUAL, STATED HONESTLY AND NOT CLAIMED AWAY. This check is only as
      ;; strong as somebody calling `prove-liveness` or `resolve` within
      ;; VOID-AFTER. Anyone may; it costs about 2,000 gas and one call covers
      ;; every pending round. If NOBODY does for ninety days, a player who has
      ;; lost can still recover their stake, and because the void is round-level
      ;; it also refunds a passive winner their stake instead of their winnings.
      ;; Both are disclosed. The ninety days is what makes them require an
      ;; abandoned table rather than an inattentive afternoon.
      ;;
      ;; 🔴 AND THE HOUSE CARRIES ONE TOO. If a beacon is unretrievable while
      ;; `last-beacon` already sits at or above the round's, the round is neither
      ;; resolvable nor refundable and its reserve stays in `reserved` forever,
      ;; out of reach of withdraw-house, with no sweep and no post-freeze remedy.
      ;; The arguments above turn on the beacon EXISTING; n_48867b242317a0216a67f8c7ca26696b5878e0e3.drand's own header
      ;; says the property that matters is RETRIEVABILITY. They are not the same.
      (with-read game-table GAME-KEY { "last-beacon" := lb }
        (enforce (< lb dr)
          "drand has been seen since this round: resolve it, do not refund it"))
      ; no fee is taken on a void, so the accrual is dropped, not paid
      (update rounds (rkey seq) { "state": "void", "liability": stk, "fee-owed": 0.0 })
      (with-read game-table GAME-KEY { "reserved" := reserved }
        (update game-table GAME-KEY { "reserved": (- reserved (- res stk)) }))
      (emit-event (ROUND-VOID seq stk)))
    "round void: every stake is refundable")

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; CLAIM ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (defun claim:string (seq:integer account:string)
    @doc "Collect a win, or a refund from a void round. PERMISSIONLESS -- it always \
    \pays the account that placed the board, so anyone may crank it for a winner."
    (with-capability (PRIVATE)
      (with-read boards (bkey seq account)
        { "entries" := es, "stake" := stk, "claimed" := done }
        (enforce (not done) "this board has already been claimed")
        (with-read rounds (rkey seq) { "state" := st, "number" := n, "liability" := liab }
          (let ((amount (cond ((= st "resolved") (floor (board-payout es n) PREC))
                              ((= st "void") stk)
                              (enforce false "this round has not been settled yet"))))
            (enforce (> amount 0.0) "nothing to claim: this board did not win")
            (update boards (bkey seq account) { "claimed": true })
            (update rounds (rkey seq) { "liability": (- liab amount) })
            (with-read game-table GAME-KEY { "reserved" := reserved }
              (update game-table GAME-KEY { "reserved": (- reserved amount) }))
            (install-capability (coin.TRANSFER HOUSE_ACCOUNT account amount))
            (transfer HOUSE_ACCOUNT account amount)
            (emit-event (CLAIMED account seq amount))
            (format "paid {}" [amount]))))))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; VIEWS ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (defun get-round:object (seq:integer) (read rounds (rkey seq)))
  (defun get-board:object (seq:integer account:string) (read boards (bkey seq account)))
  (defun get-params:object () (read game-table GAME-KEY))

  ; The boards of one round, for whoever pays winners. `claim` pays the board's
  ; own account whoever sends it, so the house's helper collects for every
  ; winner (and every refund) without a gas station -- but a caller outside this
  ; module cannot read the table at all ("Module admin necessary for operation",
  ; measured), so the listing has to be exported. Read-only, no capability, no
  ; state. A full scan: for /local use, never inside a transaction.
  (defun round-boards:[object{board}] (seq:integer)
    (select boards (where 'seq (= seq))))

  (defun pot-status:object ()
    @doc "Solvency at a glance. `max-even-money-bet` is what `bet` would ACCEPT \
    \right now -- it accounts for the open round's remaining headroom and the \
    \fee, not just the pot, so a front end built on it does not send failing \
    \transactions."
    (let* ((bal (get-balance HOUSE_ACCOUNT))
           (g (read game-table GAME-KEY))
           (reserved (at 'reserved g))
           (available (- bal reserved))
           (rate (fee-rate available (at 'target-float g)))
           (cur (at 'current g))
           ;; 🔴 F7. The cap binds on the OPEN round, not on a fresh one. Sizing
           ;; against `available` alone advertised a board `bet` then refused --
           ;; measured mid-round at 2463.67 advertised versus refused.
           (headroom
             (if (= cur 0)
                 (* (at 'reserve-fraction g) available)
                 (let ((r (read rounds (rkey cur))))
                   (if (and (= "open" (at 'state r)) (<= (curr-time) (at 'close-time r)))
                       ;; 🔴 F2. `bet` bounds against min(available, a0); sizing
                       ;; here against a0 alone over-advertises whenever the pot
                       ;; SHRANK after open (a withdrawal, or a loss paid out).
                       ;; Measured 12% high. The two must be the same expression.
                       (let ((a0 (at 'avail-at-open r)))
                         (- (* (at 'frac-at-open r) (if (< available a0) available a0))
                            (+ (vmax (at 'exposure r)) (at 'fee-owed r))))
                       (* (at 'reserve-fraction g) available)))))
           ;; the minimum `bet` will apply: the open round's own, else the live one
           (mb (if (= cur 0)
                   (at 'min-bet g)
                   (let ((r (read rounds (rkey cur))))
                     (if (and (= "open" (at 'state r)) (<= (curr-time) (at 'close-time r)))
                         (at 'min-bet-at-open r)
                         (at 'min-bet g)))))
           (room (if (> headroom 0.0) headroom 0.0))
           (by-cap (floor (/ room (+ 2.0 rate)) PREC))
           ;; 🔴 The header's bankroll rule is "bank >= 100x the advertised
           ;; even-money max". The cap alone advertises about bank/40, which
           ;; contradicts it -- and a front end is explicitly invited to build on
           ;; this number. Publish the smaller of the two.
           (by-bankroll (floor (/ available 100.0) PREC))
           (advert (if (< by-bankroll by-cap) by-bankroll by-cap)))
      { "balance": bal, "reserved": reserved, "available": available
      , "fee-rate-now": rate
      ;; 0.0 rather than a number `bet` would refuse: below the table minimum
      ;; there is no acceptable even-money board, and saying otherwise sends a
      ;; front end to a failing transaction.
      , "max-even-money-bet": (if (>= advert mb) advert 0.0) }))
)

(create-table game-table)
(create-table rounds)
(create-table boards)
