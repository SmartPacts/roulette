# Deployment — Kadena mainnet01, chain 2

Every line here is on chain. Each request key links to a public explorer; each row says what the
transaction did and the read-only call that confirms it today. Nothing in this file is a claim you
have to take from us — the calls are free, need no key, and can be run against any node.

Where a row says "read back 2026-09-23", we ran that call against
`https://api.chainweb-community.org`, chain 2, on that date and the value below is what came back.

**Who signs.** Everything gated on governance was signed by **two of the three governance keys**
(`n_48867b242317a0216a67f8c7ca26696b5878e0e3.spt-gov`, predicate `keys-2`), plus a separate key
that only pays gas. There is no one-key path to any of it.

---

## 1. The contracts

| date | what it did | request key | gas | block | confirmed by |
|---|---|---|---:|---:|---|
| 2026-09-22 | deploy `drand`, the beacon verifier — sealed at deploy, `(enforce false)` governance | [`niHtcnxu0iN8eFWCZjAtZ_sK1H6GpNrXc5bCK8hznqI`](https://explorer.chainweb-community.org/mainnet/tx/niHtcnxu0iN8eFWCZjAtZ_sK1H6GpNrXc5bCK8hznqI) | 16,943 | 7252453 | its result is `Loaded module …drand, hash Y07t-duJmkXkcGth0TfBRg3ThbNR-uh9PdNUd1MKHBQ` — the same hash `roulette` pins, and the same one you get building `pact/modules/drand.pact` locally |
| 2026-09-22 | deploy `roulette` and create its three tables | [`HLMEjROPbscKaXXihTktIVBwAOlLZQZ1piE6Zk6EMXk`](https://explorer.chainweb-community.org/mainnet/tx/HLMEjROPbscKaXXihTktIVBwAOlLZQZ1piE6Zk6EMXk) | 70,772 | 7252462 | result `TableCreated`; `describe-module` returns exactly `deploy-bytes/roulette.pact` — see [VERIFY.md](../VERIFY.md) §1 |

The `cmd` of those two transactions carries the code that was sent. `deploy-bytes/roulette.pact`
and `deploy-bytes/drand.pact` are the `(module …)` region sliced out of it, and CI proves they are
still the module in `pact/modules/`.

## 2. Setting it up

| date | what it did | request key | gas | block | confirmed by |
|---|---|---|---:|---:|---|
| 2026-09-22 | `initialize` — names where the fee goes, once, and sets the target float | [`ar3Rx8xbsgC0PCMbSsadF-MudzBcdq0eWtbxTp1CpS8`](https://explorer.chainweb-community.org/mainnet/tx/ar3Rx8xbsgC0PCMbSsadF-MudzBcdq0eWtbxTp1CpS8) | 323 | 7252469 | `(get-params)` → `revenue: "m:n_48867b242317a0216a67f8c7ca26696b5878e0e3.SPT:SPT-funding"`, `target-float: 30000`. Read back 2026-09-23 |
| 2026-09-22 | `fund-house` — 15,000 KDA into the pot | [`hgQkaYlG5dL5plu4bJNtwdDhqUvFjit-ILSEb9IGZpI`](https://explorer.chainweb-community.org/mainnet/tx/hgQkaYlG5dL5plu4bJNtwdDhqUvFjit-ILSEb9IGZpI) | 308 | 7252480 | result `house funded`; `(coin.get-balance "m:n_48867b242317a0216a67f8c7ca26696b5878e0e3.roulette:roulette-pot")` → `15006.643507434311`. Read back 2026-09-23 |

The pot is `m:n_48867b242317a0216a67f8c7ca26696b5878e0e3.roulette:roulette-pot`, a module-guarded
account: no key holds it directly. It was funded from the company account
`r:n_48867b242317a0216a67f8c7ca26696b5878e0e3.spt-gov`. Its balance is above 15,000 today because
settled rounds have left their edge behind.

## 3. Where the capital came from

The pot's 15,000 KDA is SPT sale proceeds, which live on **chain 0**. Moving them to chain 2 took
a rehearsal, a control drill and then the real transfer — all on 2026-09-22, all on chain 0 except
where noted. A cross-chain transfer's request key names the chain-0 half; the continuation lands
on chain 2.

| what it did | request key | gas | block | result |
|---|---|---:|---:|---|
| create the company account | [`c6yCdYGIOd8wqxm4ghNjLFyN4fHsk2WuaJu1Dyvbt40`](https://explorer.chainweb-community.org/mainnet/tx/c6yCdYGIOd8wqxm4ghNjLFyN4fHsk2WuaJu1Dyvbt40) | 152 | 7252298 | `Write succeeded` |
| 0.1 KDA cross-chain seed, chain 0 → 2 | [`Mii3rlCl574Mw6enF9sUBunvZAqbYThrfLtBbyFVZds`](https://explorer.chainweb-community.org/mainnet/tx/Mii3rlCl574Mw6enF9sUBunvZAqbYThrfLtBbyFVZds) | 302 | 7252300 | 0.1 to `r:…spt-gov`, source chain 0 |
| 1 KDA rehearsal withdrawal from the sale proceeds | [`keJfZAAbXH8K596tRgeP_tLARIlAM8Bd_mUHaEYtEY8`](https://explorer.chainweb-community.org/mainnet/tx/keJfZAAbXH8K596tRgeP_tLARIlAM8Bd_mUHaEYtEY8) | 309 | 7252379 | `proceeds withdrawn` |
| control drill — 0.4 KDA out | [`h_VQggnltnHvkJCXCoIchMT8ZgeoM4HMONB_3cr8JJA`](https://explorer.chainweb-community.org/mainnet/tx/h_VQggnltnHvkJCXCoIchMT8ZgeoM4HMONB_3cr8JJA) | 305 | 7252390 | `Write succeeded` |
| control drill — and back | [`XEeXhcgj9QSI3VKoApei-vK6G98VWAAFXXITtCosi28`](https://explorer.chainweb-community.org/mainnet/tx/XEeXhcgj9QSI3VKoApei-vK6G98VWAAFXXITtCosi28) | 253 | 7252392 | `Write succeeded` |
| 1 KDA cross-chain rehearsal, chain 0 → 2 | [`ea-4rKZUQLii5ogpUkOcDlqmKoOQua39B2b84xGQkQ8`](https://explorer.chainweb-community.org/mainnet/tx/ea-4rKZUQLii5ogpUkOcDlqmKoOQua39B2b84xGQkQ8) | 344 | 7252395 | 1 to `r:…spt-gov`, source chain 0 |
| 14,999 KDA withdrawal from the sale proceeds | [`3KEyjHwEQ22kyM6az2BxK6RsxTjcH1pgAZ1tFggLgLs`](https://explorer.chainweb-community.org/mainnet/tx/3KEyjHwEQ22kyM6az2BxK6RsxTjcH1pgAZ1tFggLgLs) | 309 | 7252415 | `proceeds withdrawn` — the sale's balance went 575,159 → 560,159 |
| 14,999 KDA cross-chain, chain 0 → 2 | [`nvcmXT0cdcKl6dYVey2Hfqf5ye7SUgzpn4oCQSJKVak`](https://explorer.chainweb-community.org/mainnet/tx/nvcmXT0cdcKl6dYVey2Hfqf5ye7SUgzpn4oCQSJKVak) | 344 | 7252421 | 14,999 to `r:…spt-gov`, source chain 0 |

**The helper accounts.** Two bot accounts were funded 5 KDA each, chain 0 → 2, in block 7252182:
[`4jCF-g2d5uUUW2LQ-5DffgrR1tjK4h3d-aT6q6Mcsvs`](https://explorer.chainweb-community.org/mainnet/tx/4jCF-g2d5uUUW2LQ-5DffgrR1tjK4h3d-aT6q6Mcsvs)
and
[`uNLQJZ32sR_7DiTq5f6M0Kd0Uizk97a9TMVXXuURr6A`](https://explorer.chainweb-community.org/mainnet/tx/uNLQJZ32sR_7DiTq5f6M0Kd0Uizk97a9TMVXXuURr6A)
(310 gas each). They are
`k:535f34ebf0a8ab0605f4c1c5f3a3d31a23966804f25f53c9706c30a1f0755737` and
`k:2023550ab269d4d877456e85f426b520e2db8d5572f1ffe91947384faf304baa`. They hold **no privilege the
contract recognises**: they pay gas to submit beacons and to send winners their money, which is
something anyone may do. Their 5 KDA is gas money, not house money, and it is not in the pot.

## 4. Proving it works, with real money

| date | what it did | request key | gas | block | confirmed by |
|---|---|---|---:|---:|---|
| 2026-09-22 | round 1 — a 0.01 KDA board on red | — | — | — | `(get-round 1)` → `state: "resolved"`, `number: 26`, `stake: 0.01`, `drand-round: 20865052`. 26 is black, so the board lost. Read back 2026-09-23 |
| 2026-09-22 | round 2 — red + black + zero, 0.03 KDA | — | — | — | `(get-round 2)` → `state: "resolved"`, `number: 11`, `stake: 0.03`, `drand-round: 20865177`. Read back 2026-09-23 |
| 2026-09-22 | the helper paid round 2's winner, 0.02 KDA | [`5XSmDveHOshr1lry0HRF92FoMmLRLqapFHJwjPKPHt8`](https://explorer.chainweb-community.org/mainnet/tx/5XSmDveHOshr1lry0HRF92FoMmLRLqapFHJwjPKPHt8) | 575 | 7252528 | result `paid 0.020000000000` |
| 2026-09-23 | the helper paid round 5's winner, 0.38 KDA | [`zkJqt-1q2ZKycpKdAa70FNc-lWsMZ569bkJw4F_G3PA`](https://explorer.chainweb-community.org/mainnet/tx/zkJqt-1q2ZKycpKdAa70FNc-lWsMZ569bkJw4F_G3PA) | 626 | 7253140 | result `paid 0.380000000000` |

**The fee is readable, and it is small.** A round's `reserve` is
`max(max(exposure), stake) + fee-owed`, so the fee the round accrued is the difference. Round 1
reserved `0.020135135135` against a worst case of `0.02`, so its fee was `0.000135135135` KDA —
the stake times the rate the ramp was charging at the time. Round 2 reserved `0.360405405672`
against a worst case of `0.36`: `0.000405405672`. Both are paid **out of the pot** at settlement,
to the account `get-params` names, and neither comes out of a player's stake. Read back
2026-09-23.

## 5. Changing a dial

| date | what it did | request key | gas | block | confirmed by |
|---|---|---|---:|---:|---|
| 2026-09-23 | `set-params` — the wait between a round's close and its beacon, 180 s → 120 s; every other dial unchanged | [`UuNDTUqsaV7r0JntkOyWXec7aEQWI8epsuB5qoUSHLs`](https://explorer.chainweb-community.org/mainnet/tx/UuNDTUqsaV7r0JntkOyWXec7aEQWI8epsuB5qoUSHLs) | 215 | 7253189 | `(get-params)` → `drand-margin: 120`, `reserve-fraction: 0.025`, `min-bet: 0.01`, `target-float: 30000`, `bet-window: 120`. Read back 2026-09-23 |

**Why.** The wait has to outlast the gap between one Kadena block and the next, because a round
whose beacon is published before betting has actually closed on chain is a round somebody could
bet into knowing the answer. On a two-week sample of 40,000 chain-2 blocks, 120 s leaves about one
exposed round in 500 days of continuous play; 90 s would leave about one in five days. That is why
the wait was shortened to 120 and not further, and why the contract's floor is 60 s.

The change reaches **future rounds only**. A round that has already opened keeps the beacon, the
window, the minimum and the limit it was given — which is why the two proof rounds above still
read `drand-round` numbers computed under the old wait.

---

## Reading it yourself

```lisp
(n_48867b242317a0216a67f8c7ca26696b5878e0e3.roulette.get-params)
(n_48867b242317a0216a67f8c7ca26696b5878e0e3.roulette.pot-status)
(n_48867b242317a0216a67f8c7ca26696b5878e0e3.roulette.get-round 1)
(coin.get-balance "m:n_48867b242317a0216a67f8c7ca26696b5878e0e3.roulette:roulette-pot")
(describe-keyset "n_48867b242317a0216a67f8c7ca26696b5878e0e3.spt-gov")
```

All read-only, all free, from any node on mainnet01 chain 2 — with `/local`, with Chainweaver, or
with `.github/scripts/fetch-onchain.py` as a worked example of building the request.
