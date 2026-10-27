# Run expectancy from the scorebook: every play is replayed through the
# vendored `step`, every Chadwick claim about it is checked, and the plays of
# each complete half-inning are counted toward the state they started from.
import Base
import ./state.bend as Game
import ./spec.bend as Spec
import ./counts.bend as Counts

# Chadwick's base code: 1 = first, 2 = second, 4 = third.
def code(bs: Game.Bases) -> Nat:
  match bs:
    case Game.Bases{b1, b2, b3}:
      Nat.add(Game.b2n(b1), Nat.add(Nat.mul(2n, Game.b2n(b2)), Nat.mul(4n, Game.b2n(b3))))

def index(bs: Game.Bases, o: Nat) -> Nat:
  Nat.add(Nat.mul(o, 8n), code(bs))

def side_runs(top: Bool, +s: Game.State) -> Nat:
  match top:
    case True{}:
      Game.away_runs(s)
    case False{}:
      Game.home_runs(s)

def to_index(same: Bool, +t: Game.State) -> Nat:
  match same:
    case True{}:
      index(Game.bases(t), Game.outs(t))
    case False{}:
      24n

def observe.kept(ok: Bool, +s: Game.State, +t: Game.State) -> Maybe<&2, Spec.Obs>:
  match ok:
    case False{}:
      None{}
    case True{}:
      +top = Game.is_top(s)
      Some{Spec.Obs{index(Game.bases(s), Game.outs(s)),
        to_index(Bool.not(Bool.xor(top, Game.is_top(t))), t),
        Nat.sub(side_runs(top, t), side_runs(top, s))}}

def observe.gate(ok: Bool, +s: Game.State, p: Game.Play) -> Maybe<&2, Spec.Obs>:
  match ok:
    case False{}:
      None{}
    case True{}:
      +t = Game.step(s, p)
      observe.kept(Nat.is_eq(Game.rejected(s), Game.rejected(t)), s, t)

# The only producer of counted observations: a legal play the scorebook accepts.
def observe(+s: Game.State, +p: Game.Play) -> Maybe<&2, Spec.Obs>:
  observe.gate(Spec.legal(Game.bases(s), p), s, p)

# One row of the plays CSV: where Chadwick says the play started, the play,
# and Chadwick's claims about it (end bases, outs and runs on the play, and
# runs scored after it in the half).
type Rec is Data:
  Rec{game: Nat, inn: Nat, top: Bool, outs: Nat, bases: Nat, play: Game.Play, end_bases: Nat, event_outs: Nat, event_runs: Nat, fate_runs: Nat}

# One state's direct count: runs from the state to the end of the half, and visits.
type Tot is Data:
  Tot{runs: Nat, n: Nat}

type Verdict is Data:
  Good{tots: List<&2, Tot>, obs: List<&2, Spec.Obs>, halves: Nat, partial: Nat}
  Bad{at: Nat, why: String}

# Tallies
# -------

def zeros(n: Nat) -> List<&2, Tot>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Tot{0n, 0n} <> zeros(p)

def zeros24() -> List<&2, Tot>:
  zeros(24n)

# Count one visit to state i with `runs` to the end of the half. Indices past
# the list cannot occur: outs_below_three keeps every index under 24.
def tot_add(ts: List<&2, Tot>, i: Nat, +runs: Nat) -> List<&2, Tot>:
  match ts i:
    case Nil{} _:
      Nil{}
    case Con{Tot{r, n}, rest} 0n:
      Tot{Nat.add(r, runs), 1n+n} <> rest
    case Con{t, rest} 1n+j:
      t <> tot_add(rest, j, runs)

def tots_sum(a: List<&2, Tot>, b: List<&2, Tot>) -> List<&2, Tot>:
  match a b:
    case Con{Tot{r, n}, at} Con{Tot{s, m}, bt}:
      Tot{Nat.add(r, s), Nat.add(n, m)} <> tots_sum(at, bt)
    case _ _:
      Nil{}

def tot_at(ts: List<&2, Tot>, i: Nat) -> Tot:
  match ts i:
    case Nil{} _:
      Tot{0n, 0n}
    case Con{t, _} 0n:
      t
    case Con{_, rest} 1n+j:
      tot_at(rest, j)

# Closing a half
# --------------

# A play waiting in the current half: its record index, its observation,
# and Chadwick's runs-after-it claim.
type Ent is Data:
  Ent{at: Nat, obs: Spec.Obs, fate: Nat}

# Walking a closed half newest-first: `after` is the runs scored after the
# play in hand. Wrong names the first play whose fate claim disagrees.
type Clo is Data:
  Clo{after: Nat, tots: List<&2, Tot>, obs: List<&2, Spec.Obs>}
  Wrong{at: Nat}

def close.ent(ok: Bool, at: Nat, +after: Nat, o: Spec.Obs, tots: List<&2, Tot>, obs: List<&2, Spec.Obs>) -> Clo:
  match ok:
    case False{}:
      Wrong{at}
    case True{}:
      match o:
        case Spec.Obs{+f, t, +r}:
          +total = Nat.add(r, after)
          Clo{total, tot_add(tots, f, total), Spec.Obs{f, t, r} <> obs}

def close.one(c: Clo, e: Ent) -> Clo:
  match c:
    case Wrong{at}:
      Wrong{at}
    case Clo{+after, tots, obs}:
      match e:
        case Ent{at, o, +fate}:
          close.ent(Nat.is_eq(fate, after), at, after, o, tots, obs)

def close(buf: List<&2, Ent>, c: Clo) -> Clo:
  match buf:
    case Nil{}:
      c
    case Con{e, rest}:
      close(rest, close.one(c, e))

# Replaying one game
# ------------------

# The replay so far: the scorebook state, the next record's index, the open
# half's plays (newest first), and the closed halves' counts. Stop names the
# first record whose claim fails, and why.
type Acc is Data:
  Run{s: Game.State, i: Nat, buf: List<&2, Ent>, tots: List<&2, Tot>, obs: List<&2, Spec.Obs>, halves: Nat}
  Stop{at: Nat, why: String}

def shut(c: Clo, t: Game.State, i: Nat, halves: Nat) -> Acc:
  match c:
    case Wrong{at}:
      Stop{at, "fate"}
    case Clo{_, tots, obs}:
      Run{t, i, Nil{}, tots, obs, 1n+halves}

def push(end: Bool, t: Game.State, i: Nat, buf: List<&2, Ent>, tots: List<&2, Tot>, obs: List<&2, Spec.Obs>, halves: Nat) -> Acc:
  match end:
    case False{}:
      Run{t, i, buf, tots, obs, halves}
    case True{}:
      shut(close(buf, Clo{0n, tots, obs}), t, i, halves)

# The first failed claim among runs, outs and bases, in that order.
def fault(a: Bool, b: Bool, c: Bool) -> Maybe<&2, String>:
  match a b c:
    case False{} _ _:
      Some{"runs"}
    case True{} False{} _:
      Some{"outs"}
    case True{} True{} False{}:
      Some{"bases"}
    case True{} True{} True{}:
      None{}

def feed.fault(m: Maybe<&2, String>, i: Nat, end: Bool, e: Ent, t: Game.State, buf: List<&2, Ent>, tots: List<&2, Tot>, obs: List<&2, Spec.Obs>, halves: Nat) -> Acc:
  match m:
    case Some{w}:
      Stop{i, w}
    case None{}:
      push(end, t, 1n+i, e <> buf, tots, obs, halves)

def feed.none(legal: Bool, i: Nat) -> Acc:
  match legal:
    case False{}:
      Stop{i, "illegal"}
    case True{}:
      Stop{i, "rejected"}

# Outs on the play: at the third out the half ends and the scorebook resets,
# so they are the outs the half still had.
def made(end: Bool, +s: Game.State, +t: Game.State) -> Nat:
  match end:
    case True{}:
      Nat.sub(3n, Game.outs(s))
    case False{}:
      Nat.sub(Game.outs(t), Game.outs(s))

def feed.obs(m: Maybe<&2, Spec.Obs>, +s: Game.State, +p: Game.Play, +i: Nat, end_bases: Nat, event_outs: Nat, event_runs: Nat, fate_runs: Nat, buf: List<&2, Ent>, tots: List<&2, Tot>, obs: List<&2, Spec.Obs>, halves: Nat) -> Acc:
  match m:
    case None{}:
      feed.none(Spec.legal(Game.bases(s), p), i)
    case Some{Spec.Obs{+from, +to, +runs}}:
      +t = Game.step(s, p)
      +end = Nat.is_eq(to, 24n)
      +bases_ok = end || Nat.is_eq(code(Game.bases(t)), end_bases)
      feed.fault(fault(Nat.is_eq(runs, event_runs), Nat.is_eq(made(end, s, t), event_outs), bases_ok),
        i, end, Ent{i, Spec.Obs{from, to, runs}, fate_runs}, t, buf, tots, obs, halves)

# Chadwick's starting state for the record matches the scorebook's.
def claim(+s: Game.State, r: Rec) -> Bool:
  match r:
    case Rec{_, inn, top, outs, bases, _, _, _, _, _}:
      Nat.is_eq(Game.inning(s), inn) && (Bool.not(Bool.xor(top, Game.is_top(s))) &&
        (Nat.is_eq(outs, Game.outs(s)) && Nat.is_eq(bases, code(Game.bases(s)))))

def feed.claim(ok: Bool, +s: Game.State, i: Nat, r: Rec, buf: List<&2, Ent>, tots: List<&2, Tot>, obs: List<&2, Spec.Obs>, halves: Nat) -> Acc:
  match ok:
    case False{}:
      Stop{i, "state"}
    case True{}:
      match r:
        case Rec{_, _, _, _, _, +p, end_bases, event_outs, event_runs, fate_runs}:
          feed.obs(observe(s, p), s, p, i, end_bases, event_outs, event_runs, fate_runs, buf, tots, obs, halves)

def feed(acc: Acc, +r: Rec) -> Acc:
  match acc:
    case Stop{at, why}:
      Stop{at, why}
    case Run{+s, i, buf, tots, obs, halves}:
      feed.claim(claim(s, r), s, i, r, buf, tots, obs, halves)

def game.go(rs: List<&2, Rec>, acc: Acc) -> Acc:
  match rs:
    case Nil{}:
      acc
    case Con{r, rest}:
      game.go(rest, feed(acc, r))

def partial_of(buf: List<&2, Ent>) -> Nat:
  match buf:
    case Nil{}:
      0n
    case Con{_, _}:
      1n

# A game's records end mid-half only when the game did: that half is
# dropped whole, so the counts and the table cover the same plays.
def finish(acc: Acc) -> Verdict:
  match acc:
    case Stop{at, why}:
      Bad{at, why}
    case Run{_, _, buf, tots, obs, halves}:
      Good{tots, obs, halves, partial_of(buf)}

# Replay one game's records from the first pitch.
def game(recs: List<&2, Rec>) -> Verdict:
  finish(game.go(recs, Run{Game.start(), 0n, Nil{}, zeros24(), Nil{}, 0n}))

# The season
# ----------

# Games seen, good and bad; one BADGAME line per bad game; the summed counts
# of good games and each good game's own counts; their observations; and the
# closed and dropped halves. Lists are newest first until `season` returns.
type Season is Data:
  Season{seen: Nat, good: Nat, bad: Nat, badlines: List<&2, String>, tots: List<&2, Tot>, games: List<&2, List<&2, Tot>>, obs: List<&2, Spec.Obs>, halves: Nat, partial: Nat}

def absorb(sea: Season, +g: Nat, v: Verdict) -> Season:
  match sea:
    case Season{seen, good, bad, lines, sum, games, obs, halves, partial}:
      match v:
        case Bad{at, why}:
          Season{1n+seen, good, 1n+bad, ("BADGAME " ++ Nat.show(g) ++ " " ++ Nat.show(at) ++ " " ++ why) <> lines, sum, games, obs, halves, partial}
        case Good{+ts, os, h, p}:
          Season{1n+seen, 1n+good, bad, lines, tots_sum(sum, ts), ts <> games, List.append(&2, Spec.Obs, os, obs), Nat.add(h, halves), Nat.add(p, partial)}

def rec_game(r: Rec) -> Nat:
  match r:
    case Rec{g, _, _, _, _, _, _, _, _, _}:
      g

# Records of the game being collected (newest first), and its number.
type Grp is Data:
  Grp{g: Nat, recs: List<&2, Rec>, sea: Season}

def flush(+g: Nat, recs: List<&2, Rec>, sea: Season) -> Season:
  match recs:
    case Nil{}:
      sea
    case Con{r, rest}:
      absorb(sea, g, game(List.reverse(&2, Rec, Con{r, rest})))

def group.same(same: Bool, g: Nat, recs: List<&2, Rec>, sea: Season, +r: Rec) -> Grp:
  match same:
    case True{}:
      Grp{g, r <> recs, sea}
    case False{}:
      Grp{rec_game(r), [r], flush(g, recs, sea)}

def group.one(acc: Grp, +r: Rec) -> Grp:
  match acc:
    case Grp{+g, recs, sea}:
      group.same(Nat.is_eq(g, rec_game(r)), g, recs, sea, r)

def group(rs: List<&2, Rec>, acc: Grp) -> Grp:
  match rs:
    case Nil{}:
      acc
    case Con{r, rest}:
      group(rest, group.one(acc, r))

def season.out(sea: Season) -> Season:
  match sea:
    case Season{seen, good, bad, lines, sum, games, obs, halves, partial}:
      Season{seen, good, bad, List.reverse(&2, String, lines), sum, List.reverse(&2, List<&2, Tot>, games), obs, halves, partial}

def season.fin(acc: Grp) -> Season:
  match acc:
    case Grp{g, recs, sea}:
      season.out(flush(g, recs, sea))

# Replay every game; records of one game are consecutive.
def season(recs: List<&2, Rec>) -> Season:
  season.fin(group(recs, Grp{0n, Nil{}, Season{0n, 0n, 0n, Nil{}, zeros24(), Nil{}, Nil{}, 0n, 0n}}))

# Ratios
# ------

def re7.n(n: Nat, runs: Nat) -> Maybe<&2, Nat>:
  match n:
    case 0n:
      None{}
    case 1n+m:
      Some{Nat.div(Nat.mul(runs, 10000000n), 1n+m)}

def re7.of(t: Tot) -> Maybe<&2, Nat>:
  match t:
    case Tot{runs, n}:
      re7.n(n, runs)

def re7.end(end: Bool, +ts: List<&2, Tot>, i: Nat) -> Maybe<&2, Nat>:
  match end:
    case True{}:
      Some{0n}
    case False{}:
      re7.of(tot_at(ts, i))

# RE of state i in units of 10^-7 runs (floor); the end of the half is 0,
# and a state never visited has none.
def re7(+ts: List<&2, Tot>, +i: Nat) -> Maybe<&2, Nat>:
  re7.end(Nat.is_eq(i, 24n), ts, i)

# runs / n in thousandths, rounded half up.
def milli(runs: Nat, +n: Nat) -> Nat:
  Nat.div(Nat.add(Nat.mul(runs, 1000n), Nat.div(n, 2n)), n)
