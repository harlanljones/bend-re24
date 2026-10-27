# The laws. Each is a claim that must hold for every input; PROOF.bend
# proves them, and `bend PROOF.bend` must print ALL PROOFS CHECK before any
# commit. Human-owned: this text comes verbatim from the approved plan.
import Base
import ./src/state.bend as Game
import ./src/spec.bend as Spec
import ./src/counts.bend as Counts
import ./src/re24.bend as RE

# Conservation (OBR 9.03(c), "How to Prove a Box Score"): for each team, the
# batters who completed a plate appearance equal its runs, plus the putouts
# by the defense, plus runners left on base, plus runners still on base.
law box_balances_away:
  for +ps: List<&2, Game.Play>
  {Game.away_supply(Game.replay(Game.start(), ps)) == Game.away_demand(Game.replay(Game.start(), ps)) : Nat}

law box_balances_home:
  for +ps: List<&2, Game.Play>
  {Game.home_supply(Game.replay(Game.start(), ps)) == Game.home_demand(Game.replay(Game.start(), ps)) : Nat}

# Three outs end the half-inning: the scorebook never shows three or more
# outs, and a play either keeps the same side batting or hands the next
# half a fresh state, bases empty with no outs.
law outs_below_three:
  for ps: List<&2, Game.Play>
  {Nat.is_lt(Game.outs(Game.replay(Game.start(), ps)), 3n) == True{} : Bool}

law half_resets:
  for +s: Game.State
  for +p: Game.Play
  {Spec.resets(s, Game.step(s, p)) == True{} : Bool}

# Only legal transitions: a play the scorebook observes moves no runner
# back, lets no runner pass another, and scores at most four runs.
law observed_legal:
  for +s: Game.State
  for +p: Game.Play
  {Spec.implies(Spec.some(RE.observe(s, p)), Spec.legal(Game.bases(s), p)) == True{} : Bool}

law runs_at_most_four:
  for +s: Game.State
  for +p: Game.Play
  {Spec.runs_ok(RE.observe(s, p)) == True{} : Bool}

# The transition counts out of each state sum to the plays observed in it.
law rows_sum:
  for +os: List<&2, Spec.Obs>
  for +i: Nat
  {Spec.row_sum(Counts.tally(os), i) == Spec.seen(os, i) : Nat}
