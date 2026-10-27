# bend-re24 design

Decisions for TODO section 1 (Brainstorm). Code references are to this repo.

## Thesis

Published RE24 tables (FanGraphs, Tango) are numbers produced by code nobody else checks. Here every Retrosheet play is replayed through a scorebook whose conservation, three-out and legality rules are machine-checked proofs (Bend 2, with a Lean-verified kernel). Chadwick's output is certified play by play against that scorebook. The count table is proven to account for every observed play. The RE values are exact integer ratios that reproduce FanGraphs 2024 to within 0.01 runs, and the decision-book numbers are derived from them.

## v0 scope

- 2024 MLB regular season (Retrosheet event files, 2,429 games).
- 24 base-out states: index `outs * 8 + bases`, bases as Chadwick's bitmask (1 = 1B, 2 = 2B, 4 = 3B); index 24 is the end of the half-inning (`src/spec.bend`).
- RE = runs from the state to the end of the half-inning, divided by visits to the state.
- Innings 1-8 only (ingest drops `INN_CT > 8`), as in Clemens' FanGraphs method.
- Every event counts, not only plate-appearance starts (PA-start counting missed FanGraphs by up to 0.0335 runs in the prototype).
- Complete half-innings only. A half still open at the end of a game's records is counted as `partial` and contributes nothing to the table or to RE (`RE.game`: observations are pushed only when the half closes).

## The 7 laws, mapped to the 4 TODO laws

All 7 are in `LAWS.bend`; proofs are in `PROOF.bend`.

| TODO law | `LAWS.bend` law(s) | Statement |
|---|---|---|
| Runs + outs + runners on base account for every batter (conservation) | `box_balances_away`, `box_balances_home` | For any play list replayed from the start, each team's completed PAs equal runs + putouts + left on base + still on base (OBR 9.03(c)). |
| 3 outs ends the half; state resets to empty, 0 outs | `outs_below_three`, `half_resets` | Replayed outs are always < 3; every `step` keeps the same side batting or yields a `fresh` state (bases empty, 0 outs). |
| Only legal transitions (no passing, at most 4 runs per play) | `observed_legal`, `runs_at_most_four` | Any play `RE.observe` returns `Some` for satisfies `Spec.legal` (no runner moves back, none passes another); every observation scores ≤ 4 runs. |
| Transition counts out of each state sum to the plays observed in it | `rows_sum` | For any observation list and state `i`, `Spec.row_sum(Counts.tally(os), i) == Spec.seen(os, i)`. |

## Proved vs checked

| Claim | How | Where |
|---|---|---|
| The 7 laws above | Proved, for all inputs | `PROOF.bend`, gated by `./check.sh` (plain and `--verdict`) |
| Chadwick's per-play claims: state before (inning, half, outs, bases), runs on the play, outs on the play, end bases (except at the third out), and `FATE_RUNS_CT` | Checked at runtime by Bend on every play; a failure makes the game `BADGAME <g> <at> <why>` | `RE.game` (`src/re24.bend`) |
| Play legality and scorebook acceptance | Checked at runtime through `RE.observe` (whose behaviour is covered by `observed_legal`, `runs_at_most_four`) | `src/re24.bend` |
| Table total out of each state equals the RE visit count | Checked at runtime (certificate); mismatch → `ERROR table <i>`, exit 1 | `src/cli.bend` |
| RE values, break-evens, ΔRE | Exact integer arithmetic on `Nat` (floor division); not proved optimal or "correct" beyond the definitions | `src/re24.bend`, `src/decisions.bend` |
| Bootstrap CIs deterministic across thread counts | Checked by test | `tests/run.sh` |
| Fixture RE equals an independent awk oracle | Checked by test | `tests/run.sh` |
| RE24 matches FanGraphs 2024 within ±0.01 runs | Checked externally | `go run ./compare` |
| Literature steal break-evens | Displayed beside ours, not tested | report |

## Integer representation

- All counts and ratios are Bend `Nat`: at runtime a native u64 capped at 2^48−1 that aborts on overflow (it never wraps). Proofs treat `Nat` as Zero/Succ.
- Observed 2024 maxima: 19,970 runs and 40,650 visits (bases empty, 0 outs). The largest intermediate is runs × 10^7 ≤ 2×10^11, far below 2^48−1 ≈ 2.8×10^14.
- `U32` (wraps mod 2^32) is used only in the bootstrap RNG. `F32` is axiomatic in Bend and cannot be reasoned about in proofs, so no floats are used.
- RE is printed exactly as `runs n`, plus `milli = round(runs·1000 / n)`. Decisions and CIs use RE7 fixed point: `floor(runs·10^7 / n)`, i.e. units of 10^-7 runs; break-evens are basis points.
- Decimals for humans are produced in Go from the exact integers with `math/big.Rat`.
- Rejected: bend-kit `bignum` (unnecessary given the maxima above, and a hub fetch outside the repo's proof gate; see RESEARCH.md for its law count) and runs × 1000 fixed point (too coarse for break-even differences).

## Decision-book outputs

Outcomes come from `RE.observe` applied to a synthetic state (inning 1, top, given outs and bases), so every decision value passes through the proven scorebook and its legality gate. `value(o) = RE7(to) + runs·10^7`, with RE7 at the end of the half = 0.

- `steal2`: bases 1 and 5, outs 0-2. `steal3`: bases 2 and 3, outs 0-2.
- `bunt`: bases 1, 2, 3; outs 0-1. Success: runners advance one, batter out. Failure: lead runner forced, others advance one, batter safe at first.
- Break-even of a decision with before value B, success S, failure F: `NA` if any is undefined or S ≤ F; `0` if B ≤ F; else `floor(10000·(B−F)/(S−F))` bp. Values ≥ 10000 mean the move never pays and are printed as is.
- `DRE bunt`: S − B, signed, 10^-7 runs.
- `ibb`: all 24 states, `DRE ibb` = value(walk) − B. The walk play forces runners only as needed (bases loaded: runner from third scores).
- IBB run-cost rationale: an IBB has no "success rate". Its break-even depends on the distribution of the specific batter's outcomes, which a league RE table does not contain. The book number is therefore its league-average run cost; a batter-specific model (as in Clemens' Judge article) is out of scope.
- Infield-in delta: dropped from v0. Retrosheet does not record infield alignment, so the delta cannot be computed from this data.

## Objective

Runs (RE24) for v0. Win probability is v1, by running the same certified transitions through bend-winprob's `Sim`.

## Managers-vs-the-Book sketch

- `data/plays-2024.csv` keeps the game index and `event_cd` (Chadwick event types: 4 = SB, 6 = CS, 15 = IBB); `data/games-2024.csv` keeps `game_id` and `away_team`. Bend ignores `event_cd`.
- v1 adds `SH_FL` and `BUNT_FL` (cwevent fields 38 and 48) and manager ids from `gl2024.txt` (game logs, same mirror commit), then scores each attempt against the break-even for its base-out state and aggregates by manager.

## Name

`bend-re24`; GitHub `harlanljones/bend-re24`. The local folder stays `bend-run-exp`.
