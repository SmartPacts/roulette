# Roulette — how it works, and everything that can go wrong

The contract's launch constants quoted in this document — the minimum, the chips per board, the
betting window, the wait and its floor, the refund delay, the table limit and its ceiling, the
return and the edge — are checked against the contract by `.github/scripts/check-player-terms.sh`, which CI runs on every push. If
the contract changes and this page does not, the gate fails. The live settings are read from the
chain on the play page, not from this document.

---

## The wheel

European single zero: pockets **0 to 36**, one green, eighteen red, eighteen black.

**Your return is exactly 36/37 — 97.297% — on every bet on the table.** Straight-up, split,
street, corner, dozen, column, red, black, odd, even, high, low: every one of them pays
`(payout + 1) x (numbers it covers) = 36`. **There is no sucker bet here.** One pocket in 37
never pays you, and that is the entire house edge: **2.7027%**.

No operator setting can change that: the payouts and the wheel are constants, and a test checks
all 158 bets and goes red if a single multiplier moves. Until the contract is frozen, the key
that can upgrade it could replace those constants with new code — honest limit 1 below says what
that means, and freezing ends it.

## A round

1. **You place a board** — up to **24** chips in one transaction, **0.01 KDA** minimum in total.
   This is the only thing you sign. One board per round: place every chip in that one
   transaction. The minimum and the closing time are fixed when the round opens. The table limit
   is the smaller of the limit fixed at the open and the same portion of the pot as it stands
   now, so a withdrawal from the pot while the round is open can lower it — nothing can raise it.
2. **Betting closes 120 seconds** after the round opens.
3. **The winning number comes from drand** — a random number produced every 3 seconds by a
   group of independent organisations, outside Kadena entirely. The round is locked to a
   specific drand number a fixed wait after betting closes, so it does not exist while you
   can still bet. The contract launched with that wait at **180 seconds after betting closes**;
   since 2026-09-23 it is **120 seconds**. drand publishes every 3 seconds and the round pins the
   last number published at or before that moment, so the real wait is the setting minus up to
   3 seconds — 117 to 120 seconds today. The wait is a setting the operator controls, and
   the contract holds it to a range: never below **60 seconds**, never above an hour. That
   floor is the lowest the setting can go, not a value that would be safe to run at. The wait
   has to outlast the gap between one Kadena block and the next: over six weeks of blocks the
   longest gap was 136 seconds, and at 120 seconds a fresh two-week sample shows a round
   exposed about once in five hundred days of continuous play — at 90 seconds it would be about
   once in five days, which is why the wait is not shorter. A round that has opened keeps the
   drand number it was given — changing the setting reaches only rounds that have not started
   yet.
4. **Anyone submits it.** The contract checks the cryptographic proof itself, so a fake number
   is rejected. drand numbers never expire, so a round settles correctly whether that happens
   in a minute or a month.
5. **If you won, you claim.** If you lost, you do nothing.

**Why not a Kadena block?** Because whoever produces that block would see the result first and
could throw the block away if they did not like it. Measured against the largest miner on
Kadena, that turns a red/black bet from 48.65% into **71.1%**. drand is produced off Kadena, so
no miner touches it.

## Table limits

The portion of the pot one round may risk is a setting the operator controls, and today it is
**2.5%** of the house's spare capital. Five settings are the operator's: that portion, the table
minimum, the length of the betting window (30 seconds to an hour), the wait before the drand
number is locked in, and the pot's target — the level below which the pot keeps part of the
house edge to grow, above which the whole edge goes to the funding account. The operator can
change any of them at any time — **including after the contract is frozen**, because all five
are day-to-day settings and not part of what freezing locks. Every such change is a public
transaction on the chain that anyone can read, and none of them can touch a round that is
already taking bets: a live round keeps its closing time, its minimum, its drand number and its
limit (a withdrawal from the pot can lower that limit; nothing can raise it).

The contract's own bound on the portion is arithmetic and nothing else: it refuses any portion above
**100%** of the pot's spare capital, because a round cannot risk more than the pot has spare.
There is no lower bound above zero on the portion, and no upper bound at all on the minimum bet.
Of those five, two are bounded at both ends by the contract: the betting window, between 30
seconds and an hour, and the wait, which it refuses under 60 seconds and over an hour. That floor is the lowest the dial can go, not a value that
would be safe to run at. 7.0% of measured Kadena block gaps are longer than 60 seconds, so at the
floor roughly one round in fourteen would have no block between the close and the drand number,
and anyone watching could read that number and then bet on it. We run at 120 seconds, twice the
floor (180 at launch). What such a bet takes comes out of the pot, never out of another player's stake: the
pot reserves your board's worst case before it accepts it, whoever else is at the table.

The growth arithmetic that guided today's setting, for the record: above roughly **5.5%** the
house's own bank stops growing on the worst kind of bet. That is advice the operator followed,
not a limit the contract enforces, and 2.5% sits well below it. It is the house's capital that
this decides, never yours — what the pot has reserved against your board is enforced separately
and is never at risk.

The limit applies to the **whole round**, not per player, and it uses whichever is smaller: the
pot when the round opened, or the pot now.

Consequence worth understanding: **a round can fill up.** If other players have already taken
the round's capacity, your bet is refused and you wait for the next one.

**The pot can never fail to pay.** Before accepting any board the contract reserves the exact
worst case across all 37 pockets. It can refuse a bet; it cannot run short on one it took.

## What you should know before you play

**You do not need any KDA to be paid.** The house runs a helper that sends every winner's
collection for them — and, once a stalled round has been voided, every refund — usually within
minutes of the result. Voiding is a public call anyone can send; the helper does not send it. You sign nothing
and you need hold nothing: a collection always pays the account that placed the board, never
whoever sent the transaction. You can also collect yourself at any time, from a public round
number, and so can anyone else on your behalf. If the helper were ever down, nothing is lost —
only delayed.

**Unclaimed winnings never expire.** They stay owed to you indefinitely. Nothing sweeps them to
the house.

**Anyone can settle a round or claim on your behalf.** Both are open to everybody, and a claim
always pays the account that placed the board — never the person who sent the transaction.

---

## 🔴 The honest limits

These are real. They are listed because they are true, not because they are comfortable.

**1. Until the contract is frozen, the operator's key controls the pot — and the rules.** The
same key that can upgrade the contract can move the pot's entire balance anywhere, and can
replace the contract's code, including how a round that is still waiting for its number is
decided. The drain is measured, not theoretical; the code replacement is what any upgrade is.
Nothing can reach money you have already won and claimed, but while the contract is upgradeable
**the bankroll is custody, not escrow, and every rule on this page holds only as long as the key
leaves the code alone.** Freezing the contract ends this, and nothing else about the game
changes when it does.

**2. If drand is ever retired, rounds refund after 90 days.** Nobody can prove on-chain that a
number is gone for good rather than simply un-fetched, so the contract waits. One cheap,
public call from anyone — the operator, a player, a bot — shows the contract a newer number, and
every pending round locked at or below it loses its refund for good: it can then only be
settled. **Two consequences:** if truly nobody acts for 90 days, a player who lost can take their
stake back; and because a refund applies to a whole round, it would also return a **winner**
their stake instead of their winnings. **If you win, claim it.** You can do that yourself, at
any time, from a public number.

**3. The outcome is secret only while Kadena's clock behaves.** The wait between the close and
the drand number — 120 seconds today, 180 at launch — is what keeps that number unpublished
while betting is open. It is sized against measured Kadena blocks (longest gap in six weeks:
136 seconds; at 120 seconds, about one exposed round in five hundred days of continuous
play), but that is a measurement of the past and an assumption about the network, not
something the contract can prove. **If the chain stopped producing blocks for longer than the
wait**, one round would be exposed: the one open when it stopped, and only up to that round's
own limit. That was equally true when the wait was ten minutes; a shorter wait makes such a
halt likelier to reach a round, and changes nothing about what it would cost.

**4. A round can, in principle, stick.** If a drand number becomes permanently unavailable
*after* the contract has already seen a later one, that round can be neither settled nor
refunded, and its reserved funds stay locked. This has never happened — drand has produced
more than **20 million** numbers over two years with no gap found — but it is possible.

**5. Two claims to the same account cannot go in one transaction.** A Kadena limitation.
Claim them separately.

---

## What we do not do

We do not hold your funds between rounds. Under the contract's rules there is no way to reverse
a bet, cancel a round you are winning, or change the odds after you have played: no correction,
no override and no undo — **a wrong bet stays wrong, and so does a winning one.** (Honest limit
1 is the exception, until the contract is frozen.)

**What the operator can still do, said plainly.** There is no pause button and we are not
building one. A round that has opened runs to its end on the terms it opened with — nothing
we hold can touch it, apart from the upgrade key named in honest limit 1. What we can do is stop
**future** rounds: by withdrawing the bankroll, or by raising the minimum bet or lowering the
table limit for the rounds that follow. We can also change the betting window, the wait before
the drand number is locked in (within the 60-second-to-one-hour range the contract enforces) and
the pot's target. All five dials stay ours after the contract is frozen — that is deliberate,
and it is the cost of keeping them tunable rather than fixing them in code forever. Any such
change is a public transaction on the chain.
