# The helper — anyone can run one

`roulette-crank.mjs` is a small Node program that keeps rounds moving. It holds **no privilege the
contract recognises**. Every call it makes is one anybody may make:

| call | what it does | who may send it |
|---|---|---|
| `resolve` | submits a round's drand beacon; the contract verifies the BN254 signature itself | anyone |
| `prove-liveness` | records that a newer beacon exists, which is what stops a pending round drifting toward its 90-day refund | anyone |
| `claim` | pays a winning board **its own account**, whoever sends the transaction | anyone |

It signs `coin.GAS` and nothing else. **A stolen crank key buys its holder the ability to pay
somebody else's gas.** It cannot choose a number, cannot touch the pot, and cannot be paid by the
contract: the fee goes to the treasury account inside `resolve`, so there is nothing to redirect.

The house runs two of these because the house is the party with the standing reason to, not
because it is the only party who may. **If every one of ours is down, nothing is lost and nothing
expires**: a winner can claim for themselves, anyone at all can claim for them, drand values never
expire, and the first pass after a restart pays every board still outstanding. Payment is delayed,
never forfeited.

That is also the whole mechanism behind "you need no KDA to be paid": the promise is kept by a
**process**, not by the module. Stating it the other way round would be dishonest.

## Why more than one is worth running

The module cannot tell "the beacon is unobtainable" from "nobody fetched it" — a beacon that is
never fetched is indistinguishable on chain from one that does not exist. So a round can reach its
refund after 90 days of total silence, and because the void is round-level it would also strip a
passive winner back to their stake. **One `prove-liveness` call carrying any newer beacon protects
every pending round at once.** The duty is one call per ninety days, not one per round, and the
cost is about 0.024 KDA a year per instance.

Two instances collide harmlessly: the loser of the race is refused with "a later beacon is already
on record", which is the module saying the record is already current — exactly what the call was
for. The bot logs that as benign.

## Running one

```bash
node crank-keygen.mjs                 # a fresh keypair; fund its k: account with a little gas
cp crank.env.example crank.env        # every setting is optional
node roulette-crank.mjs --once        # one pass, then exit — read what it would do
```

Read `crank.env.example` first: it documents every setting, including the heartbeat URL that tells
you when the bot has stopped, and which node it talks to. For a machine you want to leave running,
`provision-roulette-crank.sh` installs it on a fresh Ubuntu 24.04 host as a systemd service, and
`roulette-crank.service` is that unit — sandboxed, with the key and the settings kept outside the
directory an update replaces. `pack-crank.sh` builds the tarball the provisioner installs, from
committed bytes only, reproducibly.

**Mainnet is interlocked on purpose.** Against `mainnet01` the program refuses to start unless
`ROULETTE_MAINNET=armed` is set, refuses a key file that lives inside this checkout, and refuses a
localhost node. Point it at a devnet first.

**Your key is yours.** Nothing here ever asks for a seed phrase, and the provisioner never
regenerates a key — that would orphan whatever the old account holds.

## What it does not do

- It does not decide anything. The winning number is a drand signature; the contract checks it.
- It does not hold player money. Winnings go from the pot to the board's own account.
- It is not required. The contract is complete without it; this only spares players the trouble.
