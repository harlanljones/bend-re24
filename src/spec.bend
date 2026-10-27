# The data model and the predicates LAWS.bend is stated in. Human-owned:
# this text comes verbatim from the approved plan; never edit it.
import Base
import ./state.bend as Game

# One counted play: the base-out state before it (`from`), after it (`to`),
# and the runs it scored. A state's index is outs * 8 + bases, with bases as
# Chadwick's bitmask (1 = first, 2 = second, 4 = third); 24 is the end of
# the half-inning.
type Obs is Data:
  Obs{from: Nat, to: Nat, runs: Nat}

# The transition table: one Row per starting state, and in it one Cell per
# (to, runs) pair with the number of plays `n` that went that way.
type Cell is Data:
  Cell{to: Nat, runs: Nat, n: Nat}

type Row is Data:
  Row{from: Nat, cells: List<&2, Cell>}

def implies(a: Bool, b: Bool) -> Bool:
  match a:
    case True{}:
      b
    case False{}:
      True{}

def when(b: Bool, n: Nat) -> Nat:
  match b:
    case True{}:
      n
    case False{}:
      0n

# Legal plays
# -----------

# Where one slot's runner stands after the play: 0 if he is out or nobody
# was there, 1..3 for a base, 4 if he scored. A runner marked Absent stays
# on `start`, the base he began the play on.
def spot(on: Bool, +start: Nat, d: Game.Dest) -> Nat:
  match on:
    case False{}:
      0n
    case True{}:
      match d:
        case Game.Absent{}:
          start
        case Game.Out{}:
          0n
        case Game.Run{}:
          4n
        case Game.To1{}:
          1n
        case Game.To2{}:
          2n
        case Game.To3{}:
          3n

# A runner still on the field never ends behind the base he started on.
def forward(+start: Nat, +at: Nat) -> Bool:
  Nat.is_eq(at, 0n) || Nat.is_le(start, at)

# Of two runners, the lead one first: the trailing runner ends behind the
# lead runner, unless either is out (or nobody), or both scored.
def behind(+lead: Nat, +trail: Nat) -> Bool:
  (Nat.is_eq(lead, 0n) || Nat.is_eq(trail, 0n)) ||
    (Nat.is_lt(trail, lead) || (Nat.is_eq(lead, 4n) && Nat.is_eq(trail, 4n)))

# A legal play: no runner moves back, and no runner passes another.
def legal(bs: Game.Bases, p: Game.Play) -> Bool:
  match bs:
    case Game.Bases{b1, b2, b3}:
      match p:
        case Game.Play{r3, r2, r1, +bat}:
          +s3 = spot(b3, 3n, r3)
          +s2 = spot(b2, 2n, r2)
          +s1 = spot(b1, 1n, r1)
          +s0 = spot(Game.is_moved(bat), 0n, bat)
          (forward(3n, s3) && (forward(2n, s2) && forward(1n, s1))) &&
            ((behind(s3, s2) && (behind(s3, s1) && behind(s3, s0))) &&
              (behind(s2, s1) && (behind(s2, s0) && behind(s1, s0))))

# Half-innings
# ------------

# Bases empty and no outs: where every half-inning starts.
def fresh(s: Game.State) -> Bool:
  match s:
    case Game.State{_, _, o, bs, _, _, _}:
      Nat.is_eq(o, 0n) && Nat.is_eq(Game.count(bs), 0n)

# After a play the same side still bats, or the next half starts fresh.
def resets(+s: Game.State, +t: Game.State) -> Bool:
  Bool.not(Bool.xor(Game.is_top(s), Game.is_top(t))) || fresh(t)

# Observations
# ------------

def some(m: Maybe<&2, Obs>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{o}:
      True{}

def runs_ok(m: Maybe<&2, Obs>) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{Obs{_, _, r}}:
      Nat.is_le(r, 4n)

# How many observations start from state i.
def seen(os: List<&2, Obs>, +i: Nat) -> Nat:
  match os:
    case Nil{}:
      0n
    case Con{Obs{f, _, _}, t}:
      Nat.add(Game.b2n(Nat.is_eq(f, i)), seen(t, i))

def cells_sum(cs: List<&2, Cell>) -> Nat:
  match cs:
    case Nil{}:
      0n
    case Con{Cell{_, _, n}, t}:
      Nat.add(n, cells_sum(t))

# A table's total out of state i: every cell of every row for i.
def row_sum(t: List<&2, Row>, +i: Nat) -> Nat:
  match t:
    case Nil{}:
      0n
    case Con{Row{f, cs}, rest}:
      Nat.add(when(Nat.is_eq(f, i), cells_sum(cs)), row_sum(rest, i))
