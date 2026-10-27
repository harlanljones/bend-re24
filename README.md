# bend-re24

> The information used here was obtained free of charge from and is copyrighted by Retrosheet.  Interested parties may contact Retrosheet at "www.retrosheet.org".

A run expectancy (RE24) table and decision book for the 2024 MLB season, computed by replaying every Retrosheet play through a scorebook whose rules are machine-checked proofs.

## Thesis

Published RE24 tables (FanGraphs, Tango) are numbers produced by code nobody else checks. Here every Retrosheet play is replayed through a scorebook whose conservation, three-out and legality rules are machine-checked proofs (Bend 2, with a Lean-verified kernel). Chadwick's output is certified play by play against that scorebook. The count table is proven to account for every observed play. The RE values are exact integer ratios that reproduce FanGraphs 2024 to within 0.01 runs, and the decision-book numbers are derived from them.

## Method

1. **Data.** Retrosheet 2024 event files from the `chadwickbureau/retrosheet` mirror, pinned to commit `118094bb3fc2ca292c25fccf54e7541762887bf6` (`ingest/fetch.sh`).
2. **Chadwick.** `cwevent` 0.11.0, built in the repo under `.tools/`, writes one row per event.
3. **Ingest** (`ingest/`, Go). Keeps innings 1–8 and writes each play as four destination characters, one per slot: runner on third, runner on second, runner on first, batter (`data/plays-2024.csv`). It also restores the forced advances that Retrosheet leaves out on 80 third-out force plays.
4. **Replay** (`src/re24.bend`, Bend 2). Every game is replayed from the first pitch through `step`, the scorebook copied verbatim from [bend-winprob](https://github.com/harlanljones/bend-winprob) (`src/state.bend`).
   - Before each play, Chadwick's starting state is checked against the scorebook: inning, half, outs and bases.
   - The play then has to pass the legality gate, `RE.observe`, and the scorebook must accept it.
   - After it, Chadwick's runs and outs on the play, its end bases (except at the third out) and its `FATE_RUNS_CT` must all match.
   - A game where any check fails is reported as `BADGAME` and left out entirely.
5. **RE.** The direct count: for each base-out state, the runs from that state to the end of the half-inning, over the number of times the state was visited. Only complete half-innings count, and every event counts, not only the start of each plate appearance. The values are exact `Nat` ratios.
6. **Certificate.** For each state, the transition table produced by the proven `Counts.tally` must total the same number of plays as the RE visit count. If any state differs, `bin/re24` stops with `ERROR table <i>`.
7. **Decision book** (`src/decisions.bend`). Each outcome is a play run through `RE.observe` from a synthetic state, so it passes the same proven gate as the season's plays. A play's value is the RE7 of the state it ends in, plus the runs it scores. RE7 is RE in units of 10⁻⁷ runs, rounded down.
8. **Bootstrap** (`src/bootstrap.bend`). Draws 1024 resamples of whole games with replacement, using an xorshift32 RNG seeded per sample, and reports 95% percentile intervals. The samples run as a fork/join tree, either on 32 CPU lanes, each with its own copy of the games, or on the GPU (`gpu.bend`).
9. **Report** (`report/`, Go + templ + htmx). Turns the exact integers into decimals with `math/big.Rat`.

## Laws proved vs checked

`LAWS.bend` states 7 laws. `PROOF.bend` proves all of them, and `./check.sh` gates every commit on `bend PROOF.bend` and `bend PROOF.bend --verdict` (the Lean-verified kernel).

| Law | Claim |
|---|---|
| `box_balances_away`, `box_balances_home` | For each team, batters who completed a plate appearance = runs + putouts + left on base + still on base (OBR 9.03(c)) |
| `outs_below_three` | The scorebook never shows three or more outs |
| `half_resets` | A play either keeps the same side batting or starts the next half fresh: bases empty, no outs |
| `observed_legal` | Every play `RE.observe` counts is legal: no runner moves back, none passes another |
| `runs_at_most_four` | Every counted play scores at most four runs |
| `rows_sum` | The transition counts out of each state sum to the plays observed in it |

| Checked | How |
|---|---|
| Chadwick's state, runs, outs, end bases and fate runs on every play | At runtime, in Bend (`BADGAME` on any mismatch) |
| Transition table total vs RE visits for each state | At runtime, in Bend (`ERROR table`) |
| Fixture RE vs an independent awk oracle; bootstrap identical on 1 and 24 threads | `tests/run.sh` |
| RE24 vs FanGraphs 2024, ±0.01 runs | `make compare` |
| Literature break-evens | Displayed beside ours, not tested |

## Results (2024, innings 1–8)

The season replays cleanly: `GAMES 2429 2429 0`, `HALVES 38854 1`, `PLAYS 169935`, and no `BADGAME` lines.

RE in runs. The CI is the 95% bootstrap interval. FanGraphs values are from [Clemens 2025-05-29](https://blogs.fangraphs.com/the-run-expectancy-matrix-reloaded-for-the-2020s/).

| Bases | Outs | Runs / visits | RE | 95% CI | FanGraphs | Diff |
|---|---|---|---|---|---|---|
| empty | 0 | 19970 / 40650 | 0.4913 | 0.4815–0.5013 | 0.49 | +0.0013 |
| empty | 1 | 7933 / 29895 | 0.2654 | 0.2563–0.2742 | 0.27 | −0.0046 |
| empty | 2 | 2364 / 23993 | 0.0985 | 0.0930–0.1043 | 0.10 | −0.0015 |
| 1B | 0 | 8584 / 9626 | 0.8918 | 0.8657–0.9194 | 0.89 (0.895) | +0.0018 (−0.0032) |
| 1B | 1 | 6379 / 11974 | 0.5327 | 0.5128–0.5516 | 0.53 | +0.0027 |
| 1B | 2 | 2813 / 12305 | 0.2286 | 0.2164–0.2412 | 0.23 | −0.0014 |
| 2B | 0 | 3116 / 2781 | 1.1205 | 1.0737–1.1701 | 1.12 | +0.0005 |
| 2B | 1 | 3230 / 4699 | 0.6874 | 0.6552–0.7223 | 0.69 | −0.0026 |
| 2B | 2 | 2125 / 6207 | 0.3424 | 0.3200–0.3650 | 0.35 | −0.0076 |
| 3B | 0 | 519 / 370 | 1.4027 | 1.2819–1.5307 | 1.40 | +0.0027 |
| 3B | 1 | 1377 / 1434 | 0.9603 | 0.9059–1.0190 | 0.96 | +0.0003 |
| 3B | 2 | 842 / 2368 | 0.3556 | 0.3238–0.3859 | 0.36 | −0.0044 |
| 1B+2B | 0 | 3461 / 2322 | 1.4905 | 1.4226–1.5649 | 1.49 (1.491) | +0.0005 (−0.0005) |
| 1B+2B | 1 | 3741 / 4020 | 0.9306 | 0.8887–0.9734 | 0.93 | +0.0006 |
| 1B+2B | 2 | 2196 / 4928 | 0.4456 | 0.4161–0.4744 | 0.45 | −0.0044 |
| 1B+3B | 0 | 1498 / 784 | 1.9107 | 1.7945–2.0358 | 1.91 | +0.0007 |
| 1B+3B | 1 | 2219 / 1820 | 1.2192 | 1.1572–1.2832 | 1.22 | −0.0008 |
| 1B+3B | 2 | 1275 / 2515 | 0.5070 | 0.4676–0.5519 | 0.51 | −0.0030 |
| 2B+3B | 0 | 1165 / 572 | 2.0367 | 1.9018–2.1808 | 2.03 | +0.0067 |
| 2B+3B | 1 | 1929 / 1370 | 1.4080 | 1.3408–1.4818 | 1.41 | −0.0020 |
| 2B+3B | 2 | 1070 / 1780 | 0.6011 | 0.5496–0.6485 | 0.60 | +0.0011 |
| loaded | 0 | 1364 / 587 | 2.3237 | 2.1563–2.5025 | 2.32 | +0.0037 |
| loaded | 1 | 2056 / 1275 | 1.6125 | 1.5128–1.7222 | 1.61 | +0.0025 |
| loaded | 2 | 1362 / 1660 | 0.8205 | 0.7361–0.9008 | 0.82 | +0.0005 |

`make compare`: `compare: 26/26 within 0.01 runs; worst 0.0076 at 2/2`. The two 3-decimal checkpoints in parentheses are from [Clemens' Judge IBB article](https://blogs.fangraphs.com/when-should-you-intentionally-walk-aaron-judge/).

### Break-evens (success rate needed), with 95% CIs

| Move | State | 2024 | 95% CI | Literature |
|---|---|---|---|---|
| Steal 2B | 1B, 0 out | 73.25% | 68.20–78.31% | 70–75% (Goldman, 2009–11); 73.5% (Rybarczyk, 2012) |
| Steal 2B | 1B, 1 out | 73.73% | 68.90–78.65% | 70–75% (Goldman, 2009–11) |
| Steal 2B | 1B, 2 out | 66.77% | 62.12–71.99% | 70–75% (Goldman, 2009–11) |
| Steal 2B | 1B+3B, 0 out | 88.29% | 74.74–104.96% | |
| Steal 2B | 1B+3B, 1 out | 82.06% | 75.08–89.28% | |
| Steal 2B | 1B+3B, 2 out | 84.33% | 76.11–93.79% | |
| Steal 3B | 2B, 0 out | 75.18% | 66.96–84.67% | 78% (Goldman, 2009–11) |
| Steal 3B | 2B, 1 out | 68.33% | 62.72–73.93% | 69% (Goldman, 2009–11) |
| Steal 3B | 2B, 2 out | 96.28% | 87.24–106.92% | 88% (Goldman, 2009–11) |
| Steal 3B | 1B+2B, 0 out | 69.50% | 63.18–77.44% | |
| Steal 3B | 1B+2B, 1 out | 70.86% | 64.91–77.04% | |
| Steal 3B | 1B+2B, 2 out | 87.90% | 79.47–96.48% | |
| Sac bunt | 1B, 0 out | 232.15% (never pays) | 187.47–297.59% | |
| Sac bunt | 1B, 1 out | 267.37% (never pays) | 223.21–330.69% | |
| Sac bunt | 2B, 0 out | 137.47% (never pays) | 119.66–156.46% | |
| Sac bunt | 2B, 1 out | 361.33% (never pays) | 287.50–473.89% | |
| Sac bunt | 1B+2B, 0 out | 117.27% (never pays) | 96.98–140.49% | |
| Sac bunt | 1B+2B, 1 out | 311.87% (never pays) | 234.90–484.63% | |

A bunt "succeeds" when every runner moves up a base and the batter is out. It "fails" when the lead runner is forced out and the batter reaches first. A break-even above 100% means that even a bunt that always works loses runs. For example, a successful bunt with a runner on first and none out costs 0.2044 runs (CI 0.1635–0.2430). *The Book*'s tables are not compared because they were not found publicly. The ΔRE of an intentional walk in every state is in `out/decisions-2024.csv`: with the bases empty and none out it is +0.4005 runs (CI 0.3789–0.4223), and with the bases loaded exactly +1 run in every out state.

Literature sources: [Goldman](https://blogs.fangraphs.com/breaking-down-stolen-base-break-even-points/), [Rybarczyk](https://tht.fangraphs.com/stolen-base-attempts-an-algorithm-for-allocating-run-value/).

### Timing (`make time`, `bin/re24 boot data/plays-2024.csv 2024`; RTX 4070 Ti, 24 CPU threads)

| Mode | Seconds |
|---|---|
| cpu-1 | 3.401 |
| cpu-24 | 0.479 |
| gpu | 1.296 |

The CPU, GPU, 1-thread and 24-thread runs all print byte-identical output. A single fork tree over all 1024 samples, reading one shared copy of the games, took 1.644 s on 1 thread and 0.715 s on 24, only a 2.3× speedup; Bend's guide notes that a `+` value read by every lane costs an atomic per read. Two fixes were measured:

- giving every sample its own copy: 13.99 s on 1 thread and 0.838 s on 24;
- giving each of 32 lanes its own copy, with the lane running its 32 samples in turn: 3.4 s and 0.48 s.

The last one is what `run.cpu` does. `gpu.bend` keeps the single shared tree (`Boot.tree!`).

## Reproduce

Requirements: Bend 2.0.39 at `~/.bend/bin/bend` (override with `BEND=`), clang ≥ 14, Go 1.26, curl, and a C toolchain for Chadwick. `make gpu` and `make time` also need clang ≥ 19 and CUDA 12 or 13.

```sh
make ingest && make check && make run && make compare && make report
```

- `make ingest`: builds Chadwick, fetches the 61 pinned season files and writes `data/plays-2024.csv`. Prints `ingest: 2429 games, 169940 plays (innings 1-8), 80 forced-advance repairs`.
- `make check`: proofs (plain and `--verdict`), the native build, `tests/run.sh` and `go test ./...`.
- `make run`: writes `out/run-2024.txt`, `out/boot-2024.txt` (seed `SEED=2024`) and the CSVs `out/transitions-2024.csv`, `out/re24-2024.csv` and `out/decisions-2024.csv`.
- `make compare`: compares with FanGraphs. `make report`: serves http://127.0.0.1:8024. `make time`: writes `out/timing-2024.txt`.

## Limits

- **80 repaired plays.** On 80 third-out force plays (for example `5(2)/FO/G56.B-1` from 1B+2B), Retrosheet omits the forced runners' advances, so Chadwick puts two runners on one base. `ingest` moves each forced runner up one base, and after that every game replays cleanly. A runner forced off third would be ambiguous, so such a play is left unrepaired and would be rejected; none occur in 2024. Because Chadwick's end bases are lossy on these plays, the replay does not compare end bases at the third out.
- **One partial half.** The records of `MIN202407040` stop in the bottom of the 7th, 5 events into the half. That half is dropped whole, so the table and the RE denominators cover the same plays.
- **GPU.** The GPU build (`bin/re24-gpu`, `bin/re24-gpu.gpu`) runs and matches the CPU output. At 1.296 s it is slower than 24 CPU threads on this workload.
- **Bend.**
  - `Nat` is a native u64 capped at 2⁴⁸−1 that aborts on overflow; the largest value here is about 2×10¹¹.
  - `F32` is axiomatic, so nothing here uses floats.
  - No Windows.
  - Decisions use RE7 values rounded down to 10⁻⁷ runs, and break-evens are rounded down to whole basis points.
- **Decision book.** Run values come from a league-wide table, not from specific batters or game situations. Win-probability versions are v1 (see `docs/DESIGN.md`).

See `docs/DESIGN.md` for the design decisions and `docs/RESEARCH.md` for the sources.
