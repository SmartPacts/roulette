# Verify this yourself

Five checks and one warning, in increasing order of what they prove. None of them needs a key, an
account, or our permission, and none of them sends a transaction.

If any of this disagrees with what you read elsewhere in this repository — **trust the chain, not
this repository.**

---

## 1. The chain is running this code

This is the one that matters. Two commands per module. Read both scripts first — they are short,
and they only make a read-only `/local` request. Pass any node URL you trust as a second argument;
the default is a public community node.

```bash
python3 .github/scripts/fetch-onchain.py roulette > /tmp/onchain-roulette.pact
python3 .github/scripts/compare-onchain.py roulette /tmp/onchain-roulette.pact

python3 .github/scripts/fetch-onchain.py drand > /tmp/onchain-drand.pact
python3 .github/scripts/compare-onchain.py drand /tmp/onchain-drand.pact
```

Expected output, measured against mainnet on 2026-09-23:

```
IDENTICAL: the 71843 characters mainnet runs for `roulette` are, character for character,
           deploy-bytes/roulette.pact.
IDENTICAL: the 10324 characters mainnet runs for `drand` are, character for character,
           deploy-bytes/drand.pact.
```

**Why it is two scripts and not a `curl`.** A Pact command carries its own hash, the node checks
that hash against the exact command *bytes*, and re-serialising the JSON changes those bytes — so
the request has to be built and hashed in one place. `fetch-onchain.py` does that (blake2b-256,
base64url, unpadded) and nothing else.

**The comparison fails closed.** A truncated or failed fetch must never read as a pass, so
`compare-onchain.py` refuses to compare anything under a per-module size floor and says so. You
can check that yourself: run it against an empty file and it must refuse, and change one character
of the fetched file and it must report the character position where they diverge. Both were
verified when this was written.

## 2. The annotated file you are reading is those bytes

`deploy-bytes/` is what the deploy transactions sent. `pact/modules/` is that same `(module …)`
form with a header, a `namespace` line and a `create-table` footer around it — lines that ran once
at deploy and are not stored on chain. This proves the two are the same program, so §1 reaches the
file you actually read:

```bash
python3 .github/scripts/module-region.py --check
sha256sum -c deploy-bytes/SHA256SUMS          # run from inside deploy-bytes/
```

```
   ok   pact/modules/roulette.pact's (module …) form IS deploy-bytes/roulette.pact (71843 characters)
   ok   pact/modules/drand.pact's (module …) form IS deploy-bytes/drand.pact (10324 characters)
```

The slice is taken the way the engine takes it: from `(module <name>` to its matching close paren,
skipping parens inside strings and `;` comments. Comments are **inside** that region, which is why
they are on chain and why nothing in those two files is ever scrubbed — including by this
repository's own publication-hygiene check, which exempts them by exact path.

## 3. 🔴 For `roulette`, do NOT verify by comparing module hashes — for `drand`, do

A Pact 5 module hash covers the module's **dependencies' hashes**, not only its own code.

- **`roulette` depends on `coin`.** The test suite loads a vendored `coin` snapshot; mainnet runs a
  different `coin`. So a hash computed locally will **never** equal the hash mainnet reports, and a
  mismatch tells you nothing about the code. The hash on chain is
  `Yk2rarIR8oFm9ttwQexea3vVol7MnQye_HZZNKqx0fU`; compare it with what `describe-module` reports if
  you like, but §1 is the check that means something.
- **`drand` depends on nothing.** It uses no other module, holds no table, and every function in
  it is pure. Its hash is therefore reproducible, and this one is worth running: build it in the
  REPL and you get `Y07t-duJmkXkcGth0TfBRg3ThbNR-uh9PdNUd1MKHBQ`, which is exactly what mainnet
  reports **and** the literal `roulette` pins in its `use`. `run-tests.sh` does this on every run.

To read either hash from the chain, add `--hash`:

```bash
python3 .github/scripts/fetch-onchain.py drand --hash
```

## 4. The tests pass on your machine, not just ours

Install [Pact 5.4ce](https://github.com/kda-community/pact-5), then:

```bash
cd pact/tests && ./run-tests.sh
```

Every suite is scored by **exit code**. This matters more than it sounds: a later hard error in a
Pact REPL suppresses earlier `FAILURE` lines, so a broken assertion can leave a transcript that
looks clean. Grepping for `FAILURE` is not a test result; an exit code is.

The runner also fails if `or`, `and` or `+` is ever given more than two operands, if any
`expect-failure` in the suites was written with too few arguments to say *why* it expected the
failure (that checker tests itself on a known sample first, so it cannot pass by scanning
nothing), if the frozen-module fixture is anything other than `roulette` with its governance body
replaced, if the `drand` hash built here is not the one `roulette` pins, or if the published
player terms state a number the contract does not.

And it runs one file that **must exit 1, for a named reason**: `roulette-pin-must-fail.repl`. It
plants an impostor `drand` whose `verified-seed` accepts any signature and returns a number the
attacker chooses, and `roulette` must refuse to load with `hash not blessed`. Exit code alone
would not be enough — any typo also exits 1 — so the refusal message is required too.

## 5. The descriptions match the contract

[`docs/ROULETTE-PLAYER-TERMS.md`](docs/ROULETTE-PLAYER-TERMS.md) states numbers, and every one of
them is read out of `pact/modules/roulette.pact` by
[`.github/scripts/check-player-terms.sh`](.github/scripts/check-player-terms.sh), which CI runs on
every push. If the contract changes and that page does not, CI fails.

[`docs/ROULETTE-WHAT-IT-DOES.md`](docs/ROULETTE-WHAT-IT-DOES.md) is **generated**, not written by
hand, by a script in our private repository that reads the contract source, the verifier, the test
results and a manifest of which test backs which promise. That generator is not published, so from
here its ✅ marks are our claim rather than something you can re-run. Its header names the
generator and its source for exactly that reason. The checkable version is the player terms above,
plus the suites themselves.

🔴 **That page is an OUTPUT, and this copy of it was produced before the deployment finished, so
three of its sentences are behind the chain.** We publish it unedited, because hand-correcting a
generated file is how a generated file stops being one — and we say plainly what is stale:

| what the page says | what is true, and how to check |
|---|---|
| the wait before the beacon is "3 minutes" | it is **2 minutes** since 2026-09-23 — `(get-params)` returns `drand-margin: 120`, and [`deployments/mainnet01-chain-2.md`](deployments/mainnet01-chain-2.md) §5 has the transaction that changed it |
| ⛔ "a machine and a budget for the helper … nothing runs it yet" | the helper runs, and has paid winners on chain — two of its payments are in `deployments/…` §4, and its code is in [`crank/`](crank/) |
| 📋 "the contract must be deployed fresh" | it was, on 2026-09-22 — that line was written before the deploy |

Everything else on that page was true when it was generated and, as far as we know, still is. The
page will be regenerated; until it has been, **the live numbers come from `get-params` and from
[`docs/ROULETTE-PLAYER-TERMS.md`](docs/ROULETTE-PLAYER-TERMS.md)**, which CI checks against the
contract on every push.

Read all of it against the module and tell us if you find a sentence the code does not support.

---

## What was deployed, and who holds the keys

Every transaction, with its request key, its gas and the on-chain reading that confirmed it, is in
[`deployments/mainnet01-chain-2.md`](deployments/mainnet01-chain-2.md).

Two keysets matter, and both are readable from any node:

```lisp
(describe-keyset "n_48867b242317a0216a67f8c7ca26696b5878e0e3.spt-gov")
(n_48867b242317a0216a67f8c7ca26696b5878e0e3.roulette.get-params)
(n_48867b242317a0216a67f8c7ca26696b5878e0e3.roulette.pot-status)
(at 'hash (describe-module "n_48867b242317a0216a67f8c7ca26696b5878e0e3.drand"))
```

`n_48867b242317a0216a67f8c7ca26696b5878e0e3.spt-gov` is `roulette`'s GOVERNANCE, predicate
`keys-2` over three keys — **two of the three governance keys** sign anything it gates: an
upgrade, the freeze, `initialize`, `set-params`, and withdrawing the pot's earnings. There is no
one-key path to any of them. The same keyset also governs the namespace, so nobody else can ever
define a module under these names.

`get-params` returns the dials and where the fee goes; `pot-status` returns the pot's balance,
what is reserved against open rounds, and the largest even-money bet the contract would accept
right now. `drand` has no keyset at all: its governance is `(enforce false)`.

**The exception to everything above.** While `roulette` is not frozen, those same two keys hold
*module admin*, so one transaction can move the pot or rewrite any stored record — a round's
terms, a board, where the fee goes — with no new code. Such a transaction leaves the module hash
and the §1 check unchanged; it is visible only as a transaction signed by two of those keys.
Freezing ends it permanently, and `pact/tests/roulette-frozen-testing.repl` runs the whole
lifecycle against a frozen copy to prove the freeze changes that and nothing else.

---

## What none of this proves

- **Not that the contract is correct.** It proves the code you can read is the code that runs, and
  that its own tests pass. Tests encode what their author believed.
- **Not that the tests are strong.** A green suite is a floor, not a ceiling. Read them.
- **Not that drand is honest.** It proves the contract verifies a real drand signature for a round
  it pinned before betting closed. drand's own threshold assumptions are drand's.
- **Not that the operators are trustworthy.** It proves what the *code* can and cannot do. While
  `roulette` is not frozen, its 2-of-3 keyset can replace it or override it directly, and §1
  cannot see a direct override — it changes records, not code. That is stated in the README rather
  than hidden, and freezing is what ends it.
- **Not anything about a chain you did not query.** If you use our node URL and we lie to you, you
  have verified our lie. Use a node you trust, or run one.
