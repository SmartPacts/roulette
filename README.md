# Roulette — European single zero, decided by a number that did not exist when the bets closed

A Pact 5 smart contract for Kadena. A round opens the moment somebody places the first bet, takes
bets for a fixed window, and is then decided by a random number produced by the **drand** beacon —
a group of independent organisations **outside Kadena entirely** — whose signature this contract
verifies on chain. **One signed transaction per player:** you place a board and that is all you
sign. The house sends no transaction inside a round and holds no secret.

> ## 🟢 DEPLOYED — Kadena mainnet (mainnet01)
>
> - Namespace `n_48867b242317a0216a67f8c7ca26696b5878e0e3`, **chain 2**, two modules:
>   `roulette` (hash `Yk2rarIR8oFm9ttwQexea3vVol7MnQye_HZZNKqx0fU`) and the beacon verifier
>   `drand` (hash `Y07t-duJmkXkcGth0TfBRg3ThbNR-uh9PdNUd1MKHBQ`).
> - The code on chain is **character for character** the files in `deploy-bytes/`, which are in
>   turn the `(module …)` form of the annotated files in `pact/modules/` — comments and all.
>   Check both yourself with [`VERIFY.md`](VERIFY.md); it takes about a minute.
> - 🔴 **`roulette` is not frozen.** Until it is, any **2 of the 3 governance keys** hold *module
>   admin*: in one transaction, with no new code and no change to the module hash, they can move
>   the pot and rewrite any record the contract keeps. They can also publish a new version.
>   Freezing ends all of that; it has not happened. **`drand` is already sealed** — its governance
>   is `(enforce false)` and it can never be upgraded.
> - **Nothing is for sale here.** This repository is source code. Play at
>   [play.smartpacts.io](https://play.smartpacts.io).

Every transaction that built this deployment, with its request key and the reading that confirmed
it, is in [`deployments/mainnet01-chain-2.md`](deployments/mainnet01-chain-2.md).

## Which file am I reading?

| | |
|---|---|
| `pact/modules/roulette.pact` | 🔴 **THE DEPLOYED CONTRACT, annotated.** Its `(module …)` form, comments and all, is the code stored on mainnet. The lines around it — header comments, the `namespace` line, a load-time check and the `create-table` footer — ran once, in the deploy transaction, and are not stored. |
| `pact/modules/drand.pact` | 🔴 **THE DEPLOYED BEACON VERIFIER**, same arrangement. Sealed on chain: it can never be upgraded. |
| `deploy-bytes/` | exactly what the two deploy transactions sent, sliced out of their own `cmd`. This is what `describe-module` returns today. It is *derived* from the files above, and CI re-derives it. |
| everything else | tests, vendored dependencies, the helper anyone can run, and the documents about all of it |

Nothing else in this repository deploys. The file in `pact/modules/` is kept exactly as it was
deployed, comments included, so a comment is never corrected in place.

## What is in here

```
pact/modules/     the two contracts
pact/tests/       eight suites and the inverted control that must FAIL; run-tests.sh runs
                  everything, including the gates
pact/vendor/      Kadena's coin + fungible interfaces, so the suite runs with no network
                  (not ours — see NOTICE)
deploy-bytes/     the exact bytes the deploy transactions carried, plus their sha256
deployments/      every mainnet transaction, with its request key and what confirmed it
docs/             ROULETTE-PLAYER-TERMS.md — the rules and everything that can go wrong,
                  every number in it checked against the contract by CI;
                  ROULETTE-WHAT-IT-DOES.md — the same in plain language, GENERATED from the
                  contract and the test results (VERIFY.md §5)
crank/            the helper that settles rounds and pays winners. Permissionless: it holds
                  no privilege, and anyone can run one
verification/     the recorded identity of the deployed artifact
.github/          the static gate, the checkers, and the CI that runs all of it on every push
```

## Run the tests yourself

Needs [Pact 5.4ce](https://github.com/kda-community/pact-5) on your PATH (or `PACT=/path/to/pact`)
and `python3`.

```
cd pact/tests && ./run-tests.sh
```

That is the same command CI runs, with no reduced subset — a CI that runs less than you do teaches
you to trust a green tick that means less than you think. It runs the static gate over every
source file, checks that `or`, `and` and `+` are always given exactly two operands (Pact 5 refuses
more only when the line runs), checks that no `expect-failure` was written with too few arguments
to assert *why* something failed, proves the annotated modules are the published deploy bytes,
proves the frozen-module fixture is this module with only its governance replaced, proves the
`drand` hash `roulette` pins is the `drand` in this repository, proves the published terms state
the contract's own constants — and then runs the eight suites, scoring each by **exit code**
rather than by grepping the transcript.

It also runs one file that **must fail**: `roulette-pin-must-fail.repl` plants an impostor `drand`
that "verifies" every signature and returns a number of the attacker's choosing, and `roulette`
must refuse to load against it. That row is scored on the exit code *and* on the refusal message,
because any unrelated breakage also exits 1.

## How the number is chosen

When a round opens, the contract computes a drand round number a fixed wait after betting closes
and pins it into the round. That beacon **does not exist while a bet can still be placed** — not
to a player, not to a miner, not to the operator. When it is published, **anyone** may submit it:
the contract checks the BN254 pairing itself, so a forged one cannot verify, and drand values
never expire, so there is no capture window to miss and nothing to gain from staying silent.

**Why not a Kadena block hash.** Whoever mines the deciding block would see the outcome before
publishing it and could throw the block away and keep mining — a free re-roll. Measured against
the largest miner on mainnet, that turns an even-money bet from 48.65% into 71.1%. Combining
several future blocks does not help, because the first N−1 already exist when the last is mined.
drand is produced off Kadena, so no Kadena miner touches it.

## The dials the operator holds, and their bounds

`set-params` is the only setter, it is gated on the governance keyset, and it reaches **future
rounds only**: a round that has opened keeps the limit, the minimum, the window and the beacon it
was given. The bounds below are constants in the module and cannot be widened by any call.

| dial | today | bound in the code |
|---|---|---|
| share of the spare pot one round may risk | 2.5% | greater than 0, at most 100% — a round cannot risk more than the whole spare pot |
| table minimum | 0.01 KDA | never below 0.001 KDA |
| target float (where the fee stops ramping) | 30,000 KDA | must be positive |
| betting window | 120 s | 30 s to 1 hour |
| wait between close and beacon | 120 s | never below 60 s, never above 1 hour |

Two numbers are **not** dials and no key can move them: the payouts, and the fee ceiling. Player
return is exactly 36/37 = 97.297…% on every bet on the table, and the fee is paid out of the pot —
it never touches a player's stake. Its rate is `HOUSE-EDGE × min(1, available / target-float)`,
so the pot fills to its target and then forwards the whole edge; `HOUSE-EDGE` = 1/37 is the
immutable ceiling, because charging more would give the pot negative drift.

## What this contract's code does not do

Every line below describes the deployed code. Until `roulette` is frozen, the governance keys can
override any of it (the box at the top).

- **It cannot pick a number.** No function lets anyone choose one; the decision is a drand
  signature the contract verifies, and a wrong signature does not verify.
- **It cannot settle from a different verifier.** `roulette` pins `drand` by hash, so it refuses
  to load against any other code under that name. `roulette-pin-must-fail.repl` is that proof.
- **It cannot run short.** Each round carries a 37-slot exposure vector and reserves the true
  worst case over every board in it, not the sum of each board's worst case. It can only refuse a
  bet, never fail to pay one.
- **It does not make a loser send a transaction.** A losing board's reserve is released by the
  settlement itself.
- **It does not strand a round whose beacon never arrives.** After 90 days a round nobody could
  settle can be voided, and every stake comes back.
- **Settling is nobody's privilege.** Opening a round, submitting the beacon, and paying a winner
  are calls anybody can make, and the caller gets no say in the outcome. That is why a bot can do
  it — see [`crank/`](crank/), which is here so that anyone can run one.

## Reporting a problem

See [SECURITY.md](SECURITY.md) — open a **GitHub security advisory** on this repository.

## Licence

Apache-2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).
