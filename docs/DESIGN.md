# bend-re24 design

Design decisions for this repository. Code references are to this repo.

## Thesis

Published RE24 tables (FanGraphs, Tango) are numbers produced by code nobody else checks. Here every Retrosheet play is replayed through a scorebook whose conservation, three-out and legality rules are machine-checked proofs (Bend 2, with a Lean-verified kernel). Chadwick's output is certified play by play against that scorebook. The count table is proven to account for every observed play. The RE values are exact integer ratios that reproduce FanGraphs 2024 to within 0.01 runs, and the decision-book numbers are derived from them.

## v0 scope

- 2024 MLB regular season (Retrosheet event files, 2,429 games).
- 24 base-out states: index `outs * 8 + bases`, bases as Chadwick's bitmask (1 = 1B, 2 = 2B, 4 = 3B); index 24 is the end of the half-inning (`src/spec.bend`).
- RE = runs from the state to the end of the half-inning, divided by visits to the state.
- Innings 1-8 only (ingest drops `INN_CT > 8`), as in Clemens' FanGraphs method.
- Every event counts, not only plate-appearance starts (PA-start counting missed FanGraphs by up to 0.0335 runs in the prototype).
- Complete half-innings only. A half still open at the end of a game's records is counted as `partial` and contributes nothing to the table or to RE (`RE.game`: observations are pushed only when the half closes).

## The 7 laws

All 7 are in `LAWS.bend`; proofs are in `PROOF.bend`. They are the four claims below.

| Claim | `LAWS.bend` law(s) | Statement |
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
| RE24 matches the FanGraphs reference for the selected year within ±0.01 runs | Checked externally | `go run ./compare` (`make compare`, `YEAR`) |
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

## Seasons

The Makefile variable `YEAR` (default 2024) selects the Retrosheet season for fetch, ingest, run, compare, and the report. Compare reads `fixtures/reference/fangraphs-$(YEAR)-re24.csv`. The report takes `-year` (default 2024; `make report` passes `$(YEAR)`).

2023 is the second checked season. Its reference is Clemens' single-season table from the same 2025-05-29 article. Cells printed there as `1` and `1.5` are stored as `1.00` and `1.50`. The replay (`GAMES 2430 2430 0`, `PLAYS 171388`, 97 forced-advance repairs, no partial half) matches that table: 24/24 states within 0.01 runs, worst 0.0082 at 1B+3B with none out. Adding the mark columns and re-ingesting left `data/plays-2023.csv` byte-identical, so that match still stands. The same ingest wrote 4490 decision marks and a manager pair for all 2430 games.

## Objective

Runs (RE24) are the v0 book. The planned v1 was a win-probability book: the same certified transitions, scored by win probability rather than by runs.

[bend-winprob](https://github.com/harlanljones/bend-winprob) is public. Its `Sim` (`sim.bend`) is a Monte Carlo over a seven-outcome rate model (`Rates`: cumulative thresholds out of 10000 for strikeout, out, walk, single, double, triple, and home run). It forks `2^d` games, each capped at 400 plate appearances, places the regular-season ghost runner from the tenth, and stops on a walk-off. It does not read this repository's transition table.

Passing league rates into that `Sim` would not be the certified chain. The construction that matches the plan is a Markov chain whose moves are the observed `(to, runs, n)` cells, with `Sim`'s phase and walk-off rules. Value iteration fits in a Bend array: inning 1–10, half, 24 base-out states, and a score margin clamped at ±12 is 10×2×24×25 = 12000 states. The chain can loop inside one out count, so one backward sweep is not enough, and a state with zero visits needs an explicit fallback. That solver is not in this tree. The report prints no win-probability number.

## Managers vs the book

`data/plays-*.csv` stays eleven columns, ending in `event_cd`. Bend's parser requires that shape and ignores `event_cd`. Steal, bunt, and intentional-walk marks go to `data/marks-$(YEAR).csv` with header `game,half,outs,bases,play,event_cd,sh,bunt`. A row is written for Chadwick event 4 (stolen base), 6 (caught stealing), or 15 (intentional walk), and for any event with `SH_FL` or `BUNT_FL` set. Those flags are cwevent fields 38 and 48, listed in `CWFIELDS`.

`data/games-$(YEAR).csv` is `game,game_id,away_team,home_team,away_mgr_id,away_mgr_name,home_mgr_id,home_mgr_name`. The home team is the first three characters of the game id. Manager ids are game-log fields 90 and 92 (1-based); the Retrosheet game id is home team + date + game number. `ingest/fetch.sh` saves the mirror's `glYEAR.txt` or `GLYEAR.TXT` as `glYEAR.txt`. A games file that still has the old three-column header loads; its managers are reported as `unknown`.

`internal/vsbook` only sums integers `bin/re24` printed. It does not recompute a run expectancy.

- A steal of second is graded on bases 1 or 5 when the play is `--2-` (success) or `--X-` (failure). A steal of third is graded on bases 2 or 3 when the play is `-3--` or `-X--`.
- A bunt is graded on bases 1, 2, or 3 with 0 or 1 out when the play is that state's success or failure pattern from the decision book (runner advances, batter out; or the lead runner is forced and the batter reaches).
- One graded steal or bunt contributes 10000 on a success and 0 on a failure, minus that state's break-even in basis points. The report's average divides the sum by the number graded and shows percentage points. A positive average beat the book.
- Any other attempt (a double steal, a steal of home, a bunt that is not the book's pattern) is counted and left ungraded.
- An intentional walk has no break-even. The report sums `DRE ibb` in units of 10^-7 runs.
- Steals and bunts belong to the batting manager. Half 0 is the top of the inning, so the away manager. An intentional walk belongs to the fielding manager.
- Innings 1–8 only, because ingest drops the rest.

The report renders the table when `-marks` and `-games` are both set. `make run` also writes `out/managers-$(YEAR).csv`.

## Scheduling

A game's scorebook is sequential: each play starts from the state the previous play left. Games do not share that state. `RE.season` splits the file into one list per game, replays those lists as a balanced fork, and folds the verdicts from the first game to the last. The fold is what keeps `BADGAME` lines, per-game bootstrap counts, and the transition-table order the same as a sequential pass.

The decision catalogue does not depend on the RE table. `Dec.be_book` and `Dec.dre_book` run each success and failure play through `RE.observe` once. `Boot.cfg` holds those books, and each of the 1024 samples only applies its resampled RE. `Cfg` also stores `2^(depth-1)`, the pivot `pick` used to recompute on every draw.

## GPU lanes

`run.cpu` in `src/bootstrap.bend` is `lanes(5n, Nat.sub(log_size(), 5n), 0n, c)`: 32 lanes, each with its own copy of the games, each running 32 samples in order. The matching GPU call is `Boot.lanes!(5n, Nat.sub(Boot.log_size(), 5n), 0n, c)` in place of `Boot.tree!(Boot.log_size(), 0n, c)` in `gpu.bend`. That edit is not committed. Bend compiles `!` with clang 19 or newer plus a CUDA toolkit, and this environment has clang 18 and no `nvcc`, so the change could not be built or compared with `bin/re24 boot`.

## Name

`bend-re24`; GitHub `harlanljones/bend-re24`. The local folder stays `bend-run-exp`.
