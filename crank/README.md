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

You need Node (the provisioner installs v24.21.0; that is the version it is run on) and a clone of
this repository. Everything below runs from inside `crank/`.

```bash
cd crank
npm ci                                             # installs the pinned dependencies from package-lock.json
node crank-keygen.mjs "$HOME/roulette/crank-key.json"
```

`crank-keygen.mjs` takes one argument, the path of the key file to write. It creates the directory
if needed, writes the file with mode 0600, prints the public key and the `k:` account, and refuses
to overwrite a file that already exists. Keep that file outside the checkout, and send its account a
little KDA on the chain the crank will use: every call it makes costs gas.

The program reads **environment variables and nothing else**. `crank.env.example` is written for
systemd, which reads `/etc/roulette/crank.env` through the unit's `EnvironmentFile=`; the program
itself never opens that file. By hand, put the settings on the command line, replacing the three
values in angle brackets with your own (see the devnet paragraph below):

```bash
ROULETTE_BOT_KEY="$HOME/roulette/crank-key.json" \
ROULETTE_HOST=<your node's URL> \
ROULETTE_NETWORK=<its network id> \
ROULETTE_MOD=<the module you deployed> \
node roulette-crank.mjs --once
```

`--once` makes one full pass and then exits. It is **not** a dry run: it sends every transaction
that pass calls for — a resolve, the winners' claims, a liveness proof. Without `--once` it repeats
the pass every `POLL_MS` until stopped.

| setting | default in the code | what it is |
|---|---|---|
| `ROULETTE_BOT_KEY` | none, required | path to the key file `crank-keygen.mjs` wrote |
| `ROULETTE_HOST` | `http://localhost:8095` | the node it reads from and sends to |
| `ROULETTE_NETWORK` | `recap-development` | the network id; `mainnet01` turns on the interlocks below |
| `ROULETTE_CHAIN` | `2` | the chain the module lives on |
| `ROULETTE_MOD` | `n_48867b242317a0216a67f8c7ca26696b5878e0e3.roulette` | the module it drives |
| `ROULETTE_MAINNET` | unset | must be `armed` when the network is `mainnet01` |
| `HEARTBEAT_URL` | empty (off) | a URL it requests after every pass that read the chain |
| `POLL_MS` | `15000` | milliseconds between passes |
| `LIVENESS_MS` | `21600000` (6 h) | how old the on-chain liveness record may get before it is refreshed |
| `CLAIMS_PER_PASS` | `400` | the most claims one pass pays |
| `CLAIMS_PER_TX` | `40` | claims per transaction; anything above 120 is capped at 120 |
| `CLAIM_GAS` | `2000` | gas allowed per claim in a batch |
| `DRAND_RELAYS` | `https://api.drand.sh,https://api2.drand.sh,https://api3.drand.sh,https://drand.cloudflare.com` | comma-separated drand relays |

A number that does not parse, or is not positive, falls back to its default.

**To try it on a devnet you need your own deployment.** A devnet does not have the table, and it
cannot host the principal namespace the mainnet modules live in. Deploy `pact/modules/drand.pact`
and `pact/modules/roulette.pact` there yourself under a namespace your devnet allows. Both files
name the mainnet namespace, `roulette` names its governance keyset, and `roulette` pins `drand` by
its full name and hash, so your copy must replace those with your own namespace, your own keyset
and the hash your `drand` reports. Then
set `ROULETTE_MOD` to the name you deployed (for example `free.roulette`), `ROULETTE_HOST` and
`ROULETTE_NETWORK` to your devnet's, and fund the key's account there.

**Mainnet is interlocked on purpose.** With `ROULETTE_NETWORK=mainnet01` the program refuses to
start unless `ROULETTE_MAINNET=armed` is set, refuses a localhost node, refuses a key file inside
this checkout or under any directory named `crank` or `roulette-public`, and refuses to start while
the key's account has no readable positive KDA balance on the chain — all before it sends anything.

For a machine you want to leave running, `provision-roulette-crank.sh` installs it on a fresh
Ubuntu 24.04 host as a systemd service, and `roulette-crank.service` is that unit — sandboxed, with
the mainnet settings already in it and the key and your own settings kept in `/etc/roulette`,
outside the directory an update replaces. `pack-crank.sh` builds the tarball the provisioner
installs, from committed bytes only, reproducibly. Copy `crank.env.example` to
`/etc/roulette/crank.env` for anything you want to change; it lists every setting above.

**Your key is yours.** Nothing here ever asks for a seed phrase, and the provisioner never
regenerates a key — that would orphan whatever the old account holds.

## What it does not do

- It does not decide anything. The winning number is a drand signature; the contract checks it.
- It does not hold player money. Winnings go from the pot to the board's own account.
- It is not required. The contract is complete without it; this only spares players the trouble.
