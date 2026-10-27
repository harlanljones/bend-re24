# bend-re24 research notes

Findings for TODO section 2 (Research). Checked on host `diocletian`, 2026-10-26. "Not accessible" means the URL was tried and did not load.

## Bend 2

Source: https://github.com/bendlang/bend (README), local `bend guide` (`~/.bend/guide/GUIDE.md`), local `~/.bend/bend2/base.bend`.

- Installed: `~/.bend/bin/bend version` prints `bend 2.0.39` (already installed; not on PATH, so the Makefile uses `BEND ?= $(HOME)/.bend/bin/bend`). clang 23.1.3 also present.
- Laws live in `LAWS.bend`, proofs in `PROOF.bend`; `bend PROOF.bend` checks them. The checker is backed by a Lean formalization of the kernel (`bend2/bendtt.lean` ships in `~/.bend/bend2`).
- Parallelism is divide-and-conquer: the two calls of `a b = f(x) f(y)` run in parallel; `f!(…)` runs the call tree on the GPU.
- Numeric types:
  - `Nat`: proofs see Zero/Succ; the native runtime uses a u64 capped at 2^48−1 and aborts on overflow (from `bend2/comp.ts` in bendlang/bend, recorded in the plan; locally, `base.bend` line 2317 bounds `Nat.read` at `281474976710655` = 2^48−1).
  - `U32` wraps mod 2^32.
  - `F32` is axiomatic: no float proofs are possible. This repo uses no floats.
- Native builds: `bend file.bend -o file` needs clang 14+, and 19+ when `!` (GPU) is used (`GUIDE.md` line 550). On Linux, native builds need glibc 2.34+.
- Platforms: the Bend README says it "works best on the back-end, on Linux or macOS"; bend-kit's README states "Windows is not supported". No Windows.
- Measured here: a 190,000-line, 5.6 MB CSV parsed in 0.14 s (chunked `File.read` → `String.lines` → `String.split` → `Nat.read`); `bend PROOF.bend` on bend-winprob's 975-line proof in 0.12 s, `--verdict` in 0.17 s.

## bend-kit

Source: https://github.com/paymog/bend-kit (README, main branch, read 2026-10-26).

- One folder per package, each with its own `LAWS.bend`/`PROOF.bend` and hub version; imports are hash-pinned (`bend-kit-<pkg>@<ver>/<file>.bend`). Alpha; no compatibility shims. Proofs do not cover `.c`/`.js` effects.
- `bend-kit-bignum@0.1.0.0` (`bigint.bend`, `decimal.bend`, `rational.bend`): exact integers, decimals, rationals. `bignum/LAWS.bend` on main now contains 40 `law` declarations; the plan's earlier note of "0 laws" was not reproduced on 2026-10-26.
- `bend-kit-csv@0.2.0.0`: RFC 4180 records over `Bytes` (30 laws on main).
- `bend-kit-int@0.2.0.0`: `U8`, `U16`, `U64`, `I32`, `I64`; the README says "`U64` and `I64` are slow".
- None used. Native `Nat` already covers every value here (see DESIGN.md, Integer representation); the CSV is simple integer fields that `String.split` + `Nat.read` parse in 0.14 s; a hub import adds a fetch and a second proof gate outside this repo.

## mizchi/bend-playground

Source: https://github.com/mizchi/bend-playground (README, Japanese; measurements on Apple M5 / Metal, Bend 2.0.23 and 2.0.34).

- Single-core Bend is close to C `-O3` (nbody 1.13x slower; Monte Carlo within 1%).
- GPU was 55x one-core C, but loses to launch cost (~90 ms) unless the work takes ≥ 1 s on one core.
- Load imbalance is fatal (12.4x worse) only when it correlates with index range, because each lane gets a contiguous subtree; imbalance by residue is free. Divergence costs nothing on GPU.
- In-place array algorithms lose to C by an order of magnitude (FWHT 11x).
- `@unsafe` can prove anything; Bend tracks the taint ("N defs rely on unsafe or foreign code"), and since 2.0.34 such a file exits 1 with `SOME PROOFS FAIL`. This repo bans `@unsafe`.
- Applied here: the bootstrap is a balanced fork/join over sample index k with equal work per leaf (every resample draws G games), so no range-correlated imbalance.

## maxencefrenette/bendbase

Source: https://github.com/maxencefrenette/bendbase.

- Chess WDL tablebases in Bend 2 with a formal correctness proof. README: "Astra can't quite do the proofs required to make this work, so I'm abandoning the project until models get better." The repo has dozens of `*_proof.bend` files beside the code.
- Lesson: keep the proved core small. Here only the scorebook, the observation gate and the tally are under laws; RE ratios, decisions and the bootstrap are computed, and checked by certificate or tests.

## Chadwick

Source: Chadwick 0.11.0 release tarball, https://github.com/chadwickbureau/chadwick/releases/download/v0.11.0/chadwick-0.11.0.tar.gz (sha256 `c80d24dfd37707719c3e81883417a57339c4d60865e39ae73aebdbbfe2190259`), built repo-locally at `.tools/chadwick` with `./configure --prefix=… --disable-shared && make && make install`. No AUR package.

- Options used: `-Q` quiet, `-n` header row, `-y` year, `-i` one game id, `-f` standard fields, `-x` extended fields; ranges like `58-61` work. `cwevent -d` lists fields.
- Standard fields used (`-f 0,1,2,4,34,35,40,58-61`): 0 game id, 1 visiting team, 2 inning, 4 outs, 34 event type, 35 batter event flag, 40 outs on play, 58-61 batter / runner on 1st / 2nd / 3rd destination.
- Extended fields used (`-x 3,13,14,45,55`): 3 half inning (`BAT_LAST_ID`, 0 for the top even when the home team bats first), 13 base state at start, 14 base state at end, 45 runs on play, 55 runs scored in the half after this event (`FATE_RUNS_CT`).
- Base states are bitmasks: 1 = first, 2 = second, 4 = third. Destinations: 0 = out or no runner, 1-3 = base, ≥ 4 scored (5/6 = unearned variants). A runner who does not move gets `dest = own base`.
- `cwevent` skips NP (no-play) events.
- Defect handled in ingest: 80 third-out force plays in 2024 omit the forced runners' advances (e.g. `5(2)/FO/G56.B-1` from 1B+2B), so Chadwick shows two runners on first. `ingest` repairs them (`repair` in `ingest/`).
- For v1: field 38 SH flag, field 48 bunt flag.

## Retrosheet data and notice

- retrosheet.org timed out from this host. Data comes from the GitHub mirror https://github.com/chadwickbureau/retrosheet, branch `official`, pinned commit `118094bb3fc2ca292c25fccf54e7541762887bf6`, path `seasons/2024/`: `TEAM2024`, 30 `2024<T>.EV{A,N}` and 30 `<T>2024.ROS` (61 files). `TEAM2024` also lists `ALS`/`NLS` (All-Star teams) with no event files.
- Fallback: https://www.retrosheet.org/events/2024eve.zip.
- Required notice (verbatim, two spaces after "Retrosheet."; also in `fixtures/NOTICE`, README and the report footer):

  > The information used here was obtained free of charge from and is copyrighted by Retrosheet.  Interested parties may contact Retrosheet at "www.retrosheet.org".

## Baselines

- Ben Clemens, "The Run Expectancy Matrix, Reloaded for the 2020s", FanGraphs, 2025-05-29, https://blogs.fangraphs.com/the-run-expectancy-matrix-reloaded-for-the-2020s/. Method (quoted in substance): regular-season play-by-play; for each play, runners on base, outs, and runs scored from that moment to the end of the inning; first eight innings only (ninth and extras are biased by walk-offs and playing to the score). Gives 2-decimal tables for 2021-2025, 2021-24, 2015-19, 2000-04; the 2024 table is `fixtures/reference/fangraphs-2024-re24.csv`.
- Ben Clemens, "When Should You Intentionally Walk Aaron Judge?", FanGraphs, 2025-05-13, https://blogs.fangraphs.com/when-should-you-intentionally-walk-aaron-judge/: 2024 league RE 0.895 at 1B/0 outs and 1.491 at 1B+2B/0 outs (the two 3-decimal checkpoints). Also models IBB run cost with a batter-specific outcome distribution, which is why this repo reports only league ΔRE for IBB.
- Tango's pooled 2010-2024 RE chart: https://tangotiger.net/files/re24_full.png (image; HTTP 200, last-modified 2025-04-08). Not used as a numeric baseline (pooled years, image only). *The Book* tables: Clemens links https://tangotiger.net/re24.html; the steal/bunt/IBB chapters were not found publicly, so they are not compared.
- FanGraphs Guts, https://www.fangraphs.com/tools/guts: tabs are wOBA & FIP constants, park factors and handedness park factors (2024 row: runSB .200, runCS −.405). No per-season RE table.
- Soper's Retrosheet RE essay: a search found Michael Soper, "Understanding The Value of the Next Run" (2014), https://retrosheet.org/Research/SoperM/The%20value%20of%20the%20next%20run.pdf — not accessible (timed out twice, same as retrosheet.org generally). Not confirmed to be the essay the TODO means; left open.

## Bootstrap

- Resample whole games with replacement (cluster bootstrap), not innings or plays: plays within a game share pitchers, lineups and park, and half-innings are the unit RE is computed over, so games keep that dependence intact. B = 1024, 95% percentile intervals.
- Field & Welsh (2007), "Bootstrapping Clustered Data", JRSS B, doi:10.1111/j.1467-9868.2007.00593.x (https://doi.org/10.1111/j.1467-9868.2007.00593.x, abstract read): the cluster bootstrap gives consistent variance estimates under both the transformation and the random-effect model, whereas the residual bootstrap is consistent only under the transformation model.

## Papers

### Kira, Inakawa & Fujita (2019), "A Dynamic Programming Algorithm for Optimizing Baseball Strategies", JORSJ 62(2):64-82, doi:10.15807/jorsj.62.64

Read: abstract at https://www.jstage.jst.go.jp/article/jorsj/62/2/62_64/_article (free-access PDF linked there; full text not read).

- Models baseball as a finite non-zero-sum Markov game with about 6.45 million states, solved by dynamic programming in under 2 s per game.
- Computes equilibrium strategies and win percentages for both teams: batting side chooses hit, steal or sacrifice bunt; fielding side chooses pitch-to or intentional walk.
- Also addresses last-batting-team advantage and optimal batting order.
- Relevance: the same decisions as our book, but valued by win probability under a model; ours are run values from observed transitions (v0).

### Hirotsu & Bickel (2019), "Using a Markov decision process to model the value of the sacrifice bunt", J. Quant. Anal. Sports 15(4):327-344, doi:10.1515/jqas-2017-0092

Read: abstract at https://econpapers.repec.org/article/bpjjqsprt/v_3a15_3ay_3a2019_3ai_3a4_3ap_3a327-344_3an_3a2.htm (full text paywalled; not read).

- MDP over a nine-inning game with non-identical batters, populated with NL data; computes how much a sacrifice raises win probability.
- Argues maximizing win probability is superior to maximizing expected runs or P(score ≥ 1) in the half-inning.
- Finds the sacrifice bunt more beneficial than previously thought; discusses effect sizes and the effect of simplifying runner advancement or ignoring double plays.
- Relevance: our run-based bunt break-evens (e.g. ≥ 10000 bp = never pays) are expected to look worse for the bunt than a WP analysis; motivates v1 WP via bend-winprob.

### Isabelle AFP, "Verified Algorithms for Solving Markov Decision Processes" (MDP-Algorithms)

Read: entry page https://www.isa-afp.org/entries/MDP-Algorithms.html (abstract and theory list; theories not read).

- Formalizes value iteration and policy iteration for finite discounted MDPs from the Bellman operator, plus Gauss-Seidel value iteration and modified policy iteration, with optimality guarantees; covers most of Puterman ch. 6.
- Exports executable code with both float and exact rational arithmetic (`*_Code_Export_Float` / `*_Code_Export_Rat` theories).
- Builds on the AFP entry "Markov Decision Processes with Rewards".
- Pattern taken: prove the algorithm's laws once, run it on exact rationals, and keep floats out of the trusted path. The entry page does not itself describe a certificate checker; the runtime certificate here (table total = RE visit count) is our own.

## `bend_rl_research.md` / `bend_research.md`

The TODO asks to reread `/workspace/bend/bend_rl_research.md` and `bend_research.md`. `/workspace` does not exist on diocletian, and `find /home/harlan / -xdev -name 'bend_r*research.md'` returns nothing (2026-10-26). Item left open.
