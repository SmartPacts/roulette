#!/usr/bin/env node
// roulette-crank.mjs — the resolver and liveness bot for n_48867b242317a0216a67f8c7ca26696b5878e0e3.roulette.
//
// 🔴 WHY THIS IS SAFETY-CRITICAL, not a convenience.
// The module cannot tell "the drand beacon is unobtainable" from "nobody fetched
// it" — beacons never expire, so absence is never provable on chain. A refund is
// therefore reachable after VOID-AFTER (90 days) of TOTAL silence, and because
// the void is round-level it would also strip a passive winner back to their
// stake. This bot is what makes that silence never happen.
//
// 🔴 THE DUTY IS ONE CALL PER NINETY DAYS, NOT ONE PER PASS.
// `void-round` needs three conditions at once: the round still open, more than
// VOID-AFTER past its pinned beacon's publish time, AND `last-beacon` still
// below that round's own drand round. One `prove-liveness` carrying any beacon
// above the on-chain record satisfies the third for EVERY pending round at or
// below it. So liveness is driven by the age of the ON-CHAIN record, never by a
// timer of this process and never by whether a pass happened to settle
// anything. LIVENESS_MS (default 6h) is the refresh interval, ~360x inside the
// 90-day requirement.
//
// COST AT STEADY STATE. `prove-liveness` costs 1,643 gas; at GAS_PRICE 1e-8
// that is 0.00001643 KDA a call. Four calls a day = 0.0000657 KDA/day, about
// 0.024 KDA a year, per instance; two instances 0.000131 KDA/day. `resolve` is
// on top and scales with the table — one send per round, not per pass.
//
// It holds NO privilege. Every call it makes is permissionless: `resolve`,
// `prove-liveness` and `claim` can be sent by anyone, and none of them can choose
// an outcome. It signs `coin.GAS` and nothing else. A stolen key buys its holder
// the ability to pay our gas. The house runs it because the house is the party
// with the standing reason to, not because it is the only party who may: a
// player can make every one of these calls for themselves.
//
// 🔴 RUN AT LEAST TWO, ON SEPARATE MACHINES. One call to `prove-liveness` blocks
// every pending refund, so redundancy here is cheap and the failure it prevents
// is expensive. Two instances collide harmlessly: the loser of the race is
// rejected with "a later beacon is already on record", which is the module
// saying the record is already current — the outcome the call was for. This bot
// logs that as benign, not as a failure.
//
// 🔴 IT ALSO PAYS EVERY WINNER AND EVERY REFUND, AND THAT IS THE WHOLE MECHANISM
// BEHIND THE PLAYER-FACING "you need no KDA to be paid".
// `claim` is permissionless and pays the BOARD'S OWN account whoever sends the
// transaction, so this bot collects for every winner -- and every refund after a
// void -- with no gas station, no float and no meter. The player signs nothing,
// holds nothing and does nothing. The promise is therefore kept by a PROCESS,
// not by the module, and that is the honest way to state it.
// 🔴 IF THIS BOT IS DOWN, NOTHING IS LOST AND NOTHING EXPIRES. A winner can still
// claim for themselves, and anyone at all can claim for them -- the module does
// not care who sends it. Payment is delayed, never forfeited, and the first pass
// after a restart pays every board still outstanding, including the rounds that
// settled while the bot was gone.
//
// A ROUND IS PAID IN BATCHES: MANY CLAIMS IN ONE TRANSACTION.
// `claim` measured 519 gas on its own on a node. Measured in the 5.4 REPL, forty
// claims to forty DIFFERENT accounts in ONE transaction cost 17,831 gas -- 445 a
// claim -- so roughly 300 winners fit inside the 150,000 transaction limit.
// MINED ON A NODE (devnet crowd run, 100 players x 5 chips, 2026-09-22): a
// 40-claim batch 20,067 gas and 5,892 bytes; an 83-claim batch 41,407 gas and
// 11,569 bytes -- about 500 gas a claim on the node, and a transaction far
// larger than 40 members accepted. The 120 cap below is therefore not a size
// guess any more; it stays as the gas headroom rule it always was.
// SPEED is the reason, not gas: one claim per transaction meant one mined block
// per winner, and at a block every ~30s a 200-winner round took hours to pay.
// That round is now five transactions, submitted together and polled together.
//
// COST. Only the gas CONSUMED is billed -- coin's `redeem-gas` refunds the unused
// part of the limit to the sender -- so at GAS_PRICE 1e-8:
//     per claim      445 * 1e-8       = 0.00000445 KDA
//     500 winners/d  13 transactions, 222,500 gas = 0.0022250 KDA/day
//     a year of that 365 * 0.0022250  = 0.812     KDA/year
// A busy table costs under 1 KDA a year to pay everyone on.
//
// 🔴 EVERY MEMBER IS DRY-RUN FIRST, AND NO ACCOUNT APPEARS TWICE IN A BATCH.
// A batch aborts AS A WHOLE if any member fails, and there are exactly two ways
// that happens: a member who did not win, or an account listed twice. Both are
// pinned by roulette-payout-testing.repl. A /local runs the same code and commits
// nothing, so the losers are filtered out for free before anything is signed.
// Distinct receivers never collide -- each claim installs its own coin.TRANSFER
// and Pact's managed-install identity is (sender, receiver).
// CLAIM_GAS (2000) is the per-claim allowance, about 4.5x the measurement,
// because a board carrying many entries costs more to pay than the average one.
// A batch asks for CLAIM_GAS * members + 2000, capped at the chain's 150,000. A
// batch that fails is logged with its request key and its members are dry-run
// again on the next pass -- money cannot be lost that way, and the operator can
// raise CLAIM_GAS or lower CLAIMS_PER_TX without touching this file.
import { readFileSync } from 'node:fs';
import { resolve, sep } from 'node:path';
import { Pact, createClient, createSignWithKeypair } from '@kadena/client';

const HOST    = process.env.ROULETTE_HOST ?? 'http://localhost:8095';
const NETWORK = process.env.ROULETTE_NETWORK ?? 'recap-development';
const CH      = process.env.ROULETTE_CHAIN ?? '2';
// Defaults to the PRODUCTION module. A devnet run must override it, because a
// devnet cannot host the principal namespace -- ROULETTE_MOD=free.roulette.
const MOD     = process.env.ROULETTE_MOD ?? 'n_48867b242317a0216a67f8c7ca26696b5878e0e3.roulette';
// A setting that does not parse falls back to the default instead of becoming NaN: a NaN
// LIVENESS_MS would make every pass send a liveness proof (about 0.1 KDA a day, the whole
// year's budget in ten days) and a NaN POLL_MS a tight loop against the public node.
const posNum = (name, dflt) => { const v = Number(process.env[name] ?? dflt); return Number.isFinite(v) && v > 0 ? v : dflt; };
const POLL    = posNum('POLL_MS', 15000);
const LIVENESS_EVERY = posNum('LIVENESS_MS', 6 * 60 * 60 * 1000); // 6h
const ONCE    = process.argv.includes('--once');
const GAS_PRICE = 1e-8;
const SEND_GAS  = 30000;
// The chain's per-transaction gas ceiling. A /local is free to send but still
// runs under it, so it bounds the READS as hard as it bounds the sends.
const CHAIN_GAS_LIMIT = 150_000;
// The claim budget of one pass. It bounds the CLAIMS -- not the transactions and
// not the reads: one busy round must never starve the resolution of every other
// round, and whatever is left over is simply paid by the next pass.
const CLAIMS_PER_PASS = posNum('CLAIMS_PER_PASS', 400);
// How many claims ride in one transaction. 40 is the measured shape; 120 is a
// hard ceiling, still well inside 150,000 at the measured 445 a claim. Above it
// the batch would be betting on a gas figure nobody has measured -- and on a
// payload nobody has measured either. The accounts ride in the transaction's
// `data` rather than in the code, so the size that matters is the whole signed
// command: with production account names 40 claims is 7,519 bytes and 120 is
// 21,240 (measured 2026-09-21; 3,429 and 10,329 of that is the exec code).
const perTx = Math.floor(Number(process.env.CLAIMS_PER_TX ?? 40));
const CLAIMS_PER_TX = Number.isFinite(perTx) && perTx >= 1 ? Math.min(120, perTx) : 40;
const CLAIM_GAS = posNum('CLAIM_GAS', 2000);
// An explicit envelope, not the client default: a tx that cannot be mined
// inside ten minutes has lost its race and should expire rather than land late.
const TTL       = 600;
const MAINNET   = NETWORK === 'mainnet01';

// drand evmnet — the ONLY network Pact can verify (it is the only BN254 one).
const DRAND_CHAIN = '04f1e9062b8a81f848fded9c12306733282b2727ecced50032187751166ec8c3';
const DRAND_GENESIS = 1727521075, DRAND_PERIOD = 3;
// Independent relays of the SAME chain. A hostile relay cannot forge a beacon the
// contract will accept, so this covers silence — which is the only real risk.
const RELAYS = (process.env.DRAND_RELAYS ??
  'https://api.drand.sh,https://api2.drand.sh,https://api3.drand.sh,https://drand.cloudflare.com'
).split(',');

// The module's own time-of-round, mirrored: GENESIS + PERIOD * (round - 1).
const drandRoundAt = (ms) => Math.floor((ms / 1000 - DRAND_GENESIS) / DRAND_PERIOD) + 1;
const publishedAt  = (r) => (DRAND_GENESIS + DRAND_PERIOD * (r - 1)) * 1000;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (...a) => console.log(new Date().toISOString(), ...a);

// ---- THE DEAD-MAN'S SWITCH. Set HEARTBEAT_URL to a ping URL from any uptime
// service that alerts when pings STOP (healthchecks.io's free tier, Better
// Stack, your own endpoint). This bot pings it after every pass in which it
// read the chain successfully, so silence means the process, the machine, the
// network or the node is gone — and you hear about it from something that is
// not running on the machine that died. Nothing tells you otherwise: a crank
// that stops resolving delays every payout, and nothing on chain complains
// about a silent liveness duty until the ninety-day void is within reach.
//
// It never throws and never waits long: monitoring that can break the thing it
// monitors is worse than no monitoring. Be honest about what it proves — the
// bot is alive and can read the chain, NOT that a particular round settled.
const HEARTBEAT_URL = process.env.HEARTBEAT_URL ?? '';
let beatFailed = false;
async function beat() {
  if (!HEARTBEAT_URL) return;
  try {
    await fetch(HEARTBEAT_URL, { signal: AbortSignal.timeout(10000) });
    beatFailed = false;
  } catch (e) {
    // Said once per outage, not once per pass: a heartbeat that cannot be sent
    // is worth knowing about, but it is not what this bot is for.
    if (!beatFailed) log(`heartbeat ping failed (${String(e.message).slice(0, 80)}) — the bot keeps running`);
    beatFailed = true;
  }
}

const client = createClient(({ chainId, networkId }) =>
  `${HOST}/chainweb/0.0/${networkId}/chain/${chainId}/pact`);

// ---- the bot's key. It needs no privilege; it only pays gas. ----------------
const KEYFILE = process.env.ROULETTE_BOT_KEY;
if (!KEYFILE) { console.error('set ROULETTE_BOT_KEY to a json file with {account,publicKey,secretKey}'); process.exit(1); }
const BOT = JSON.parse(readFileSync(KEYFILE, 'utf8'));
// The directory this file runs from -- on a host, the checkout under /opt.
const HERE = new URL('.', import.meta.url).pathname;

// 🔴 Mainnet interlocks: an accident here spends real KDA.
if (MAINNET) {
  if (process.env.ROULETTE_MAINNET !== 'armed') { console.error('refusing mainnet01: set ROULETTE_MAINNET=armed'); process.exit(1); }
  if (HOST.includes('localhost')) { console.error('refusing mainnet01 against localhost'); process.exit(1); }
  if (/(^|\/)(crank|roulette-public)\//.test(KEYFILE)) { console.error('refusing mainnet01: keep the key file OUTSIDE the repo'); process.exit(1); }
  // Wherever the code runs from, the key must not be under it: an update
  // replaces that directory wholesale, and a key inside it would go with it.
  // On a host that means /etc/roulette, never /opt/roulette-crank.
  if (resolve(KEYFILE).startsWith(resolve(HERE) + sep)) { console.error('refusing mainnet01: the key file must live outside this checkout'); process.exit(1); }
}

// 🔴 THE TWO FAILURES ARE DIFFERENT AND MUST STAY DIFFERENT. A contract abort is
// an answer -- "this board did not win" is the module telling us something true.
// A transport failure is no answer at all. `localResult` returns the first and
// throws the second, so a node outage can never be written into the log as a
// player's board being a loser.
// 🔴 AN ACCOUNT IS DATA, NEVER CODE. Every account this bot names -- a board's,
// its own -- travels in the transaction's `data` and is read back in Pact with
// `read-string`, so no account is ever quoted into a code string and there is
// nothing to escape. coin's charset is CHARSET_LATIN1, which admits every code
// point below 256: a quote, a backslash and a newline are all legal in an
// account name, and a name holding them is payable exactly like any other.
// gasLimit is the chain maximum on purpose: `round-boards` is a full table
// select, charged a flat ~40,000 gas plus ~0.6 per row in the table (measured
// 2026-09-21: 40,005 at 1 board, 40,039 at 60). So the listing stops FITTING
// once the boards table holds roughly 184,000 rows, and the failure is silent
// in the worst way -- payout reads nothing, lists nobody, pays nobody, and
// every other line of the log still looks normal. `noteBoardsGas` is what
// makes that arrival visible while there is still room to act on it.
// This returns the WHOLE command result, not `result`: `gas` sits beside it,
// and the ceiling monitor is built on `gas`.
async function localCmd(code, data = {}) {
  const tx = Object.entries(data)
    .reduce((b, [k, v]) => b.addData(k, v), Pact.builder.execution(code))
    .setMeta({ chainId: CH, gasLimit: CHAIN_GAS_LIMIT, gasPrice: GAS_PRICE, senderAccount: BOT.account, ttl: TTL })
    .setNetworkId(NETWORK).createTransaction();
  // undici reports every transport problem as a bare "fetch failed"; the cause is
  // the half that names the host and the reason, and this is a bot whose first
  // symptom of a wrong node path is a log line nobody can act on.
  try { return await client.local(tx, { preflight: false, signatureVerification: false }); }
  catch (e) { throw new Error(`${HOST} chain ${CH}: ${e.cause?.message ?? e.message}`); }
}

const localResult = async (code, data) => (await localCmd(code, data)).result;

async function local(code, data) {
  const r = await localResult(code, data);
  if (r.status !== 'success') throw new Error(r.error?.message ?? 'local failed');
  return r.data;
}
const num = (v) => Number(typeof v === 'object' && v !== null && 'decimal' in v ? v.decimal
                        : typeof v === 'object' && v !== null && 'int' in v ? v.int : v);

// The signing half on its own: `send` submits and waits, a payout batch submits
// and waits for nothing until the whole pass is in flight. Both sign coin.GAS and
// nothing else -- every call this bot makes is permissionless.
// `data` is how untrusted strings reach the chain here too: an account, a drand
// signature. Nothing a third party controls is ever written into `code`.
async function signedTx(code, gasLimit, data = {}) {
  const tx = Object.entries(data)
    .reduce((b, [k, v]) => b.addData(k, v),
      Pact.builder.execution(code).addSigner(BOT.publicKey, (wc) => [wc('coin.GAS')]))
    .setMeta({ chainId: CH, senderAccount: BOT.account, gasLimit, gasPrice: GAS_PRICE, ttl: TTL })
    .setNetworkId(NETWORK).createTransaction();
  return createSignWithKeypair([BOT])(tx);
}

async function send(code, label, data = {}, gasLimit = SEND_GAS) {
  const r = await client.pollOne(await client.submit(await signedTx(code, gasLimit, data)), { timeout: 600000, interval: 5000 });
  if (r.result.status !== 'success') throw new Error(`${label}: ${JSON.stringify(r.result.error)}`);
  log(`  ✓ ${label} (gas ${r.gas})`);
  return r;
}

// ---- beacons: try each relay until one answers ------------------------------
// 🔴 A RELAY ANSWER IS UNTRUSTED INPUT, AND ONE OF ITS FIELDS ENDS UP INSIDE A
// SIGNED TRANSACTION. Exactly TWO fields are ever read, and both are checked.
// `signature` must be 128 hex characters, which is the CONTRACT'S OWN bound:
// `g1-from-hex` enforces `(= 128 (length h))` and then parses each 64-character
// half with `str-to-int 16`, so a short, long or non-hex answer is refused on
// chain whatever this bot does. Checking it here refuses it EARLY -- before it
// is signed, submitted and paid for -- which turns a broken or hostile relay
// into a wasted relay instead of a wasted transaction. Either hex case is
// accepted because the contract's seed is case-independent: `verified-seed`
// derives it from the decoded coordinates, never from the hex.
// 🔴 `randomness` IS DELIBERATELY NOT READ, though every real relay sends it.
// The contract derives its own seed from the G1 coordinates reduced mod P, so a
// relay's idea of the randomness cannot move any outcome -- and reading it would
// manufacture a value that looks authoritative and is not. Conveniently the gate
// also catches the mix-up: drand's `randomness` is 64 hex characters, so it can
// never be mistaken for a signature.
const SIG_HEX = /^[0-9a-fA-F]{128}$/;

async function beacon(round) {
  for (const base of RELAYS) {
    try {
      const res = await fetch(`${base}/${DRAND_CHAIN}/public/${round}`, { signal: AbortSignal.timeout(10000) });
      if (!res.ok) continue;
      const j = await res.json();
      // A relay that answers a DIFFERENT round is answering a different question.
      // The signature would not verify on chain, so this only costs a wasted send
      // — but a relay that does it is not one to take the next answer from either.
      if (Number(j?.round) !== round) { log(`  relay ${base} answered round ${j?.round} for ${round} — skipped`); continue; }
      const sig = j?.signature;
      // Named relay, named reason, next relay. One bad answer must never be able
      // to stop a round from settling, and silence is the only real risk here.
      if (typeof sig !== 'string' || !SIG_HEX.test(sig)) {
        log(`  relay ${base} answered round ${round} with a signature that is not 128 hex characters (${typeof sig === 'string' ? `${sig.length} chars, starts ${JSON.stringify(sig.slice(0, 24))}` : `type ${typeof sig}`}) — skipped, trying the next relay`);
        continue;
      }
      return sig;
    } catch { /* try the next relay */ }
  }
  return null;
}

// ---- the open-round set -----------------------------------------------------
// 🔴 WHY A SET AND NOT A WINDOW. This used to scan `round-seq` down to
// `round-seq - 200`. A round that failed to resolve and then fell 200 behind was
// forgotten permanently — and because liveness keeps raising `last-beacon`, a
// forgotten round can never be voided either, so its reserve stays locked in
// `reserved` forever. The set is enumerated ONCE, from `round-seq` down to 1,
// and only ever shrinks on evidence: a `/local` read showing the round is no
// longer open. A read that FAILS keeps the round in the set — dropping one on a
// transient error is the same bug in a smaller window.
const openRounds = new Set();
let highestSeen = 0;
let scanned = false;

// ---- the rounds that still owe somebody -------------------------------------
// A settled round stays here until it is PROVEN to owe nothing. It is entered
// when this bot settles it, when a pass finds it settled by someone else, and at
// the startup scan -- because a round that resolved while the bot was down is
// exactly the round nobody is watching.
const payRounds = new Set();
// Boards already shown to be losers, per round. A resolved round's number never
// changes, so a board that cannot claim now can never claim: remembering them
// keeps a round with one stuck winner from re-testing every loser on every pass.
const losers = new Map();

async function scanAll(lastSeq) {
  let owing = 0;
  for (let seq = lastSeq; seq >= 1; seq--) {
    // Deliberately NOT wrapped: an error here must abort the scan and leave
    // `scanned` false so the next pass retries the whole enumeration. A round
    // skipped at startup would be a round forgotten for the life of the process.
    const r = await local(`(${MOD}.get-round ${seq})`);
    if (r.state === 'open') openRounds.add(seq);
    else if (num(r.liability) > 0) { payRounds.add(seq); owing++; }
  }
  highestSeen = lastSeq;
  scanned = true;
  log(`  startup scan: ${lastSeq} round(s) on chain, ${openRounds.size} still open, ${owing} settled and still owing`);
}

// ---- the round-boards ceiling ----------------------------------------------
// 🔴 THE ENUMERATION HAS AN END AND NOTHING ELSE WOULD ANNOUNCE IT. The cost of
// `round-boards` grows with every board EVER placed, not with the round being
// paid, so the table that breaks it is the table a successful table builds. The
// warn line is about 100,000 boards and the alert about 167,000; the listing
// itself stops fitting at roughly 184,000. Both name the remedy, because a
// figure with no action attached is a line nobody reads twice.
const BOARDS_GAS_WARN  = 100_000;
const BOARDS_GAS_ALERT = 140_000;
const BOARDS_REMEDY = 'replace the board enumeration with an event indexer';
let boardsGasPeak = 0, boardsGasCalls = 0, boardsGasFailed = 0;

// The node's own gas-exhaustion abort, e.g. `Gas limit "150000"exceeded: 150001`
// -- measured verbatim, without the space, on a 5.4 node. It earns its own log
// line: it is neither a contract answer nor a transport fault, it is the ceiling
// arriving, and "read failed" would send the operator hunting a node problem
// that does not exist.
const isGasExhausted = (msg) => /gas limit/i.test(msg) && /exceeded/i.test(msg);

// Every round-boards call passes through here.
// 🔴 ONLY A CALL THAT SUCCEEDED MEASURES THE TABLE. A node charges an ABORTED
// /local the whole limit -- measured: every failing /local on a 5.4 node
// reports gas 150,000 whatever went wrong -- so thresholding a failure would
// announce a ceiling that may be nowhere near, in the voice of a measurement.
// The one failure that genuinely IS the ceiling gets its own ALERT at the call
// site, and that line says strictly more than this one could.
function noteBoardsGas(seq, cmd) {
  if (cmd.result?.status !== 'success') { boardsGasFailed++; return; }
  const g = Number(cmd.gas);
  if (!Number.isFinite(g)) {
    log(`  round ${seq}: round-boards reported no usable gas figure (${JSON.stringify(cmd.gas)}) — the ceiling monitor is blind for this round`);
    return;
  }
  boardsGasCalls++;
  if (g > boardsGasPeak) boardsGasPeak = g;
  if (g > BOARDS_GAS_ALERT) log(`  ALERT round ${seq}: round-boards used ${g} gas of the ${CHAIN_GAS_LIMIT} ceiling — the listing is about to stop fitting, and once it does payout lists nobody and pays nobody. Remedy: ${BOARDS_REMEDY}`);
  else if (g > BOARDS_GAS_WARN) log(`  WARNING round ${seq}: round-boards used ${g} gas of the ${CHAIN_GAS_LIMIT} ceiling. Remedy: ${BOARDS_REMEDY}`);
}

// ---- paying winners ---------------------------------------------------------
// 🔴 EVERY CLAIM IS DRY-RUN FIRST. `claim` aborts for a loser and an aborted send
// still burns gas, while a /local executes the same code and commits nothing --
// so the losers are filtered for free. With batching the dry run stops being a
// saving and becomes the precondition: one loser in a batch aborts the WHOLE
// transaction and nobody in it is paid. The dry run is also the only thing that
// tells a loser ("nothing to claim") apart from a race ("already been claimed")
// and from a node that is not answering.
// A BATCH IS ONE ROUND'S CLAIMS, EACH ACCOUNT AT MOST ONCE. Two claims for the
// same account in one transaction abort it -- the second reads a board already
// marked claimed -- so the approved set is built per round as a Set and sliced,
// which makes the invariant true by construction. Different accounts never
// collide: each claim installs its own coin.TRANSFER, and Pact's managed-install
// identity is (sender, receiver), so forty receivers are forty installs.
const batchTx = (seq, members) => ({
  seq,
  members,
  // Several top-level forms in one exec run in order. Pact.builder.execution()
  // joins its arguments with NO separator, so the separator is ours to pick and
  // a space keeps the payload on one line.
  // 🔴 NOT ONE ACCOUNT LITERAL APPEARS IN THIS CODE. Each member is carried in
  // `data` under its index and read back with `read-string`, so a board account
  // -- a string the CHAIN handed us, holding whatever a player chose -- is never
  // parsed as Pact. The index is ours, so nothing about the key is attacker-set.
  code: members.map((_, i) => `(${MOD}.claim ${seq} (read-string "a${i}"))`).join(' '),
  data: Object.fromEntries(members.map((a, i) => [`a${i}`, a])),
  gasLimit: Math.min(CHAIN_GAS_LIMIT, CLAIM_GAS * members.length + 2000),
});

async function payout() {
  let budget = CLAIMS_PER_PASS, losersSkipped = 0;
  boardsGasPeak = 0; boardsGasCalls = 0; boardsGasFailed = 0;
  const batches = [];
  for (const seq of [...payRounds].sort((a, b) => a - b)) {
    if (budget <= 0) break;
    let row, boards;
    try {
      row = await local(`(${MOD}.get-round ${seq})`);
      const rb = await localCmd(`(${MOD}.round-boards ${seq})`);
      noteBoardsGas(seq, rb);
      if (rb.result.status !== 'success') {
        const msg = String(rb.result.error?.message ?? 'round-boards failed');
        if (isGasExhausted(msg)) log(`  ALERT round ${seq}: round-boards EXHAUSTED THE ${CHAIN_GAS_LIMIT} GAS CEILING (${msg}) — the boards table has outgrown a full-table select, so this round's winners cannot be listed at all and this bot can pay none of them. Remedy: ${BOARDS_REMEDY}`);
        else log(`  round ${seq}: round-boards refused, keeping the round tracked (${msg.slice(0, 120)})`);
        continue;
      }
      boards = rb.result.data;
    } catch (e) {
      log(`  round ${seq}: payout read failed, keeping it tracked (${String(e.message).slice(0, 100)})`);
      continue;
    }
    // The done memo, written only on PROOF: the round owes exactly nothing, or
    // every board has collected. Anything weaker here is a winner who stops
    // being paid, so a round that cannot be read stays in the set.
    if (num(row.liability) === 0 || boards.every((b) => b.claimed === true)) {
      payRounds.delete(seq);
      losers.delete(seq);
      continue;
    }
    const known = losers.get(seq) ?? new Set();
    losers.set(seq, known);
    let noted = false;
    // The claims this round has proven payable. A Set, not an array: the boards
    // table is keyed (seq, account) so a repeat cannot occur on chain, and this
    // is what stops trusting that from being load-bearing.
    const approved = new Set();
    for (const b of boards) {
      if (budget <= 0) break;
      // A Pact bool arrives as a JSON bool (ints and decimals are the wrapped
      // ones). If that ever stops being true every board would look claimed and
      // the round would sit here paying nobody, so say so instead of stalling.
      if (typeof b.claimed !== 'boolean') { log(`  round ${seq}: board ${b.account} has claimed=${JSON.stringify(b.claimed)} — not a bool, skipped`); continue; }
      // A chain string is DATA, never code: the account below is passed in the
      // transaction's `data`, so there is no quoting and nothing to escape, and
      // no character in a name can be refused on that account. What is still
      // refused is a value that is not an ACCOUNT at all -- coin's own bounds
      // are MINIMUM_ACCOUNT_LENGTH 3 and MAXIMUM_ACCOUNT_LENGTH 256, and `claim`
      // pays through coin.transfer, which re-enforces them, so nothing outside
      // that range could be paid by anyone. This can never drop a winner.
      if (typeof b.account !== 'string' || b.account.length < 3 || b.account.length > 256) {
        log(`  round ${seq}: a board account is not a 3..256 character string (${String(JSON.stringify(b.account)).slice(0, 60)}), skipped`);
        continue;
      }
      if (b.claimed !== false || known.has(b.account)) continue;
      if (approved.has(b.account)) { log(`  round ${seq}: ${b.account} is listed twice in the round, the repeat is dropped`); continue; }
      const r = await localResult(`(${MOD}.claim ${seq} (read-string "a"))`, { a: b.account });
      if (r.status !== 'success') {
        const msg = String(r.error?.message ?? '');
        if (msg.includes('nothing to claim')) { known.add(b.account); losersSkipped++; continue; }
        if (msg.includes('already been claimed') || msg.includes('has not been settled yet')) {
          if (!noted) { log(`  round ${seq}: a board raced us or is not settled (${msg.slice(0, 90)})`); noted = true; }
          continue;
        }
        log(`  round ${seq} ${b.account}: claim refused: ${msg.slice(0, 160)}`);
        continue;
      }
      budget--;   // an APPROVED claim spends the budget: a round that keeps
                  // failing must not be able to loop through the whole table.
      approved.add(b.account);
    }
    const payable = [...approved];
    for (let i = 0; i < payable.length; i += CLAIMS_PER_TX) batches.push(batchTx(seq, payable.slice(i, i + CLAIMS_PER_TX)));
  }

  // 🔴 SUBMIT THE WHOLE PASS, THEN POLL IT. This is where the hours went: a
  // submit that waits for its own block before the next one is sent serialises
  // every transaction a block apart. Submitted together, they are mined together.
  const sent = [];
  for (const t of batches) {
    try {
      const d = await client.submit(await signedTx(t.code, t.gasLimit, t.data));
      sent.push({ ...t, requestKey: d.requestKey, desc: d });
      log(`  round ${t.seq}: ${t.members.length} claim(s) submitted in one transaction (gas limit ${t.gasLimit}, request key ${d.requestKey})`);
    } catch (e) {
      log(`  round ${t.seq}: a batch of ${t.members.length} failed to submit, retried next pass: ${String(e.message).slice(0, 160)}`);
    }
  }

  const roundsPaid = new Set();
  let claimsPaid = 0, batchesOk = 0;
  if (sent.length > 0) {
    const poll = client.pollStatus(sent.map((s) => s.desc), { timeout: 600000, interval: 5000 });
    // The aggregate promise rejects the moment ANY member does; each batch is
    // judged on its own promise below, so this only keeps the rejection handled.
    poll.catch(() => {});
    const outcomes = await Promise.allSettled(sent.map((s) => poll.requests[s.requestKey]));
    outcomes.forEach((o, i) => {
      const s = sent[i];
      if (o.status === 'fulfilled' && o.value?.result?.status === 'success') {
        batchesOk++; claimsPaid += s.members.length; roundsPaid.add(s.seq);
        log(`  ✓ round ${s.seq}: ${s.members.length} claim(s) paid in ${s.requestKey} (gas ${o.value.gas})`);
        return;
      }
      const why = String(o.status === 'rejected'
        ? (o.reason?.message ?? o.reason)
        : JSON.stringify(o.value?.result?.error ?? o.value ?? 'no result'));
      // A player claiming for themselves between the dry run and the block aborts
      // the batch they were in. That is the module working, not a fault: those
      // members are dry-run again next pass and the claimed one drops out.
      if (why.includes('already been claimed')) log(`  round ${s.seq}: batch ${s.requestKey} lost a race, its ${s.members.length} claim(s) are retried next pass`);
      else log(`  round ${s.seq}: batch ${s.requestKey} failed, its ${s.members.length} claim(s) are retried next pass: ${why.slice(0, 160)}`);
    });
  }
  log(`  payout: ${roundsPaid.size} round(s) paid, ${claimsPaid} claim(s) paid, ${batches.length} batch(es) built, ${sent.length} sent, ${batchesOk} landed, ${losersSkipped} board(s) skipped as losers`);
  // Said every pass, not only when it is alarming: a ceiling nobody watches in
  // the quiet months is a ceiling nobody recognises in the busy one. Zero calls
  // is reported as NOT MEASURED -- a monitor that inspected nothing must never
  // read as a clean bill of health.
  log(boardsGasCalls === 0
    ? `  round-boards ceiling: NOT MEASURED this pass (0 listing(s) read, ${boardsGasFailed} refused)`
    : `  round-boards ceiling: peak ${boardsGasPeak} gas of ${CHAIN_GAS_LIMIT} over ${boardsGasCalls} listing(s) read${boardsGasFailed > 0 ? `, ${boardsGasFailed} refused` : ''} (warn above ${BOARDS_GAS_WARN}, alert above ${BOARDS_GAS_ALERT})`);
  if (sent.length > 0) log(`  batch request keys: ${sent.map((s) => s.requestKey).join(' ')}`);
}

// ---- one pass ---------------------------------------------------------------
async function pass() {
  const g = await local(`(${MOD}.get-params)`);
  const lastSeq = num(g['round-seq']);

  if (!scanned) await scanAll(lastSeq);
  else {
    // Everything above the high-water mark is new; the settle loop's own read
    // decides whether it is still open.
    for (let seq = highestSeen + 1; seq <= lastSeq; seq++) openRounds.add(seq);
    highestSeen = lastSeq;
  }
  log(`  ${openRounds.size} open round(s) tracked (round-seq ${lastSeq})`);

  // 1. settle every tracked round whose beacon has been published.
  //    One resolve per transaction: two installs of coin.TRANSFER to the same
  //    revenue account collide, because Pact's install identity excludes the amount.
  for (const seq of [...openRounds].sort((a, b) => b - a)) {
    let r;
    try { r = await local(`(${MOD}.get-round ${seq})`); }
    catch (e) { log(`  round ${seq}: read failed, keeping it tracked (${String(e.message).slice(0, 100)})`); continue; }
    // Settled by someone else, or voided: it leaves the open set and joins the
    // set of rounds that still owe somebody.
    if (r.state !== 'open') {
      openRounds.delete(seq);
      if (num(r.liability) > 0) payRounds.add(seq);
      continue;
    }
    const dr = num(r['drand-round']);
    if (Date.now() < publishedAt(dr) + 2000) continue;           // not published yet
    const sig = await beacon(dr);
    if (!sig) { log(`  round ${seq}: beacon ${dr} not available from any relay`); continue; }
    try {
      // The signature travels in `data`, exactly like an account: a relay's
      // answer is as much untrusted input as a player's account name.
      const res = await send(`(${MOD}.resolve ${seq} (read-string "sig"))`, `resolve round ${seq}`, { sig });
      log(`  round ${seq} landed on ${num(res.result.data)}`);
      openRounds.delete(seq);
      payRounds.add(seq);
    } catch (e) { log(`  round ${seq} resolve failed: ${String(e.message).slice(0, 160)}`); }
  }

  // 2. pay what the settled rounds owe: every winner, and every refund after a
  //    void. This is the step that makes "you need no KDA to be paid" true.
  await payout();

  // 3. keep the ON-CHAIN liveness mark current. The only thing that matters is
  //    the age of `last-beacon` as the module holds it: while it is younger than
  //    LIVENESS_EVERY, every pending round is already un-voidable and a send here
  //    would buy nothing. `last-beacon` 0 reads as 2024, i.e. always stale.
  //    Re-read rather than reuse the row from the top of the pass: `resolve`
  //    raises `last-beacon` itself, so a pass that settled anything has already
  //    refreshed the record and the stale copy would buy a redundant send.
  const lb = num((await local(`(${MOD}.get-params)`))['last-beacon']);
  const lbAge = Date.now() - publishedAt(lb);
  if (lbAge <= LIVENESS_EVERY) return;
  const target = drandRoundAt(Date.now()) - 4;                   // a few rounds back, safely published
  if (target <= lb) return;
  const sig = await beacon(target);
  if (!sig) { log('  no relay answered for the liveness beacon'); return; }
  try {
    await send(`(${MOD}.prove-liveness ${target} (read-string "sig"))`, `prove drand alive at ${target} (record was ${(lbAge / 3600000).toFixed(1)}h old)`, { sig });
  } catch (e) {
    const msg = String(e.message);
    if (msg.includes('a later beacon is already on record')) log('  liveness already current (another instance won the race)');
    else log(`  liveness failed: ${msg.slice(0, 160)}`);
  }
}

// ---- startup self-test ------------------------------------------------------
// 🔴 WITHOUT THIS THE FIRST REAL EXERCISE OF THE KEY, THE FUNDING AND THE NODE
// PATH IS A ROUND WITH A PLAYER'S MONEY IN IT. The bot used to log "no rounds
// yet" and send nothing until the first bet, so a wrong key file, an unfunded
// account or a bad host stayed invisible until it mattered.
async function selfTest() {
  try {
    const p = await local(`(${MOD}.pot-status)`);
    log(`  pot: balance ${num(p.balance)} reserved ${num(p.reserved)} available ${num(p.available)} max-even-money-bet ${num(p['max-even-money-bet'])}`);
  } catch (e) {
    log(`  pot-status unavailable: ${String(e.message).slice(0, 160)}`);
  }
  let bal = null;
  // The bot's own account travels in `data` too. One rule with no exception is
  // the only kind that stays true: there is no second code path where a name
  // could be quoted into Pact.
  try { bal = num(await local(`(coin.get-balance (read-string "a"))`, { a: BOT.account })); log(`  bot gas balance: ${bal} KDA`); }
  catch (e) { log(`  bot gas balance UNREADABLE: ${String(e.message).slice(0, 160)}`); }
  if (MAINNET && !(bal > 0)) {
    console.error(`refusing mainnet01: ${BOT.account} has no readable positive KDA balance on chain ${CH} via ${HOST}.`);
    console.error('  A bot that cannot pay gas cannot resolve a round or prove liveness. Fund it, or fix the node path, then restart.');
    process.exit(1);
  }
}

log(`roulette crank: ${MOD} on ${NETWORK} chain ${CH} via ${HOST}`);
log(`  bot ${BOT.account} (signs coin.GAS only, holds no privilege)`);
log(`  heartbeat ${HEARTBEAT_URL ? 'ON' : 'OFF (set HEARTBEAT_URL and nothing will tell you when this bot dies)'}`);
await selfTest();
let failed = false;
do {
  failed = false;
  // The ping rides on the path where pass() RETURNED. Every read it does not
  // catch itself -- the params row, the startup scan, the liveness re-read --
  // throws out of it, so a pass that comes back is a pass that read the chain,
  // whatever it then decided to send or not send; and an unreachable node makes
  // the pings stop, which is the one thing the switch is for. A single pass
  // pings too, so `--once` proves the URL works before the alert that never came.
  try { await pass(); await beat(); } catch (e) { failed = true; log(`pass failed: ${String(e.message).slice(0, 200)}`); }
  if (!ONCE) await sleep(POLL);
} while (!ONCE);
if (ONCE && failed) process.exit(1);
