# The decision book: break-even success rates for steals and bunts, and the
# run cost of bunts and intentional walks, all from the RE table. Every
# outcome is a play through the proven scorebook (RE.observe), so it passes
# the same legality gate as the season's plays.
import Base
import ./state.bend as Game
import ./spec.bend as Spec
import ./re24.bend as RE

# Signed values
# -------------

type Z is Data:
  Z{neg: Bool, mag: Nat}

def zsub.go(ge: Bool, +a: Nat, +b: Nat) -> Z:
  match ge:
    case True{}:
      Z{False{}, Nat.sub(a, b)}
    case False{}:
      Z{True{}, Nat.sub(b, a)}

# a - b, signed.
def zsub(+a: Nat, +b: Nat) -> Z:
  zsub.go(Nat.is_le(b, a), a, b)

def zshow.go(minus: Bool, +mag: Nat) -> String:
  match minus:
    case True{}:
      "-" ++ Nat.show(mag)
    case False{}:
      Nat.show(mag)

def zshow(z: Z) -> String:
  match z:
    case Z{neg, +mag}:
      zshow.go(neg && Nat.is_lt(0n, mag), mag)

# Signed order: a <= b.
def zle(a: Z, b: Z) -> Bool:
  match a b:
    case Z{True{}, x} Z{True{}, y}:
      Nat.is_le(y, x)
    case Z{True{}, x} Z{False{}, y}:
      True{}
    case Z{False{}, +x} Z{True{}, +y}:
      Nat.is_eq(x, 0n) && Nat.is_eq(y, 0n)
    case Z{False{}, x} Z{False{}, y}:
      Nat.is_le(x, y)

# Outcomes
# --------

def bit(+n: Nat, +k: Nat) -> Bool:
  Nat.is_eq(Nat.mod(Nat.div(n, k), 2n), 1n)

def bases_of(+c: Nat) -> Game.Bases:
  Game.Bases{bit(c, 1n), bit(c, 2n), bit(c, 4n)}

# The play from (bases, outs), through the scorebook and its legality gate.
def outcome(+bases: Nat, +outs: Nat, p: Game.Play) -> Maybe<&2, Spec.Obs>:
  RE.observe(Game.State{1n, True{}, outs, bases_of(bases), Game.zero(), Game.zero(), 0n}, p)

def value.of(m: Maybe<&2, Nat>, runs: Nat) -> Maybe<&2, Nat>:
  match m:
    case None{}:
      None{}
    case Some{x}:
      Some{Nat.add(x, Nat.mul(runs, 10000000n))}

# A play's worth in 10^-7 runs: the RE of where it ends, plus the runs it scored.
def value(+ts: List<&2, RE.Tot>, o: Maybe<&2, Spec.Obs>) -> Maybe<&2, Nat>:
  match o:
    case None{}:
      None{}
    case Some{Spec.Obs{_, to, runs}}:
      value.of(RE.re7(ts, to), runs)

def before(+ts: List<&2, RE.Tot>, +bases: Nat, +outs: Nat) -> Maybe<&2, Nat>:
  RE.re7(ts, Nat.add(Nat.mul(outs, 8n), bases))

# Break-even
# ----------

def breakeven.cmp(sf: Bool, bf: Bool, +b: Nat, +s: Nat, +f: Nat) -> Maybe<&2, Nat>:
  match sf bf:
    case True{} _:
      None{}
    case False{} True{}:
      Some{0n}
    case False{} False{}:
      Some{Nat.div(Nat.mul(10000n, Nat.sub(b, f)), Nat.sub(s, f))}

# The success rate, in basis points, at which a move with before-value B,
# success S and failure F breaks even: (B - F) / (S - F). None when a value
# is undefined or success is worth no more than failure; 0 when even failure
# beats standing pat.
def breakeven(mb: Maybe<&2, Nat>, ms: Maybe<&2, Nat>, mf: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match mb ms mf:
    case Some{+b} Some{+s} Some{+f}:
      breakeven.cmp(Nat.is_le(s, f), Nat.is_le(b, f), b, s, f)
    case _ _ _:
      None{}

def gain(mb: Maybe<&2, Nat>, ms: Maybe<&2, Nat>) -> Maybe<&2, Z>:
  match mb ms:
    case Some{+b} Some{+s}:
      Some{zsub(s, b)}
    case _ _:
      None{}

# The catalogue
# -------------

# One decision: where it is made, the play if it works, and the play if it fails.
type Choice is Data:
  Choice{kind: String, bases: Nat, outs: Nat, win: Game.Play, lose: Game.Play}

def play(r3: Game.Dest, r2: Game.Dest, r1: Game.Dest, bat: Game.Dest) -> Game.Play:
  Game.Play{r3, r2, r1, bat}

def outs2(+kind: String, +b: Nat, +w: Game.Play, +l: Game.Play) -> List<&2, Choice>:
  [Choice{kind, b, 0n, w, l}, Choice{kind, b, 1n, w, l}]

def outs3(+kind: String, +b: Nat, +w: Game.Play, +l: Game.Play) -> List<&2, Choice>:
  [Choice{kind, b, 0n, w, l}, Choice{kind, b, 1n, w, l}, Choice{kind, b, 2n, w, l}]

def steal2() -> List<&2, Choice>:
  +win = play(Game.Absent{}, Game.Absent{}, Game.To2{}, Game.Absent{})
  +lose = play(Game.Absent{}, Game.Absent{}, Game.Out{}, Game.Absent{})
  List.append(&2, Choice, outs3("steal2", 1n, win, lose), outs3("steal2", 5n, win, lose))

def steal3() -> List<&2, Choice>:
  +win = play(Game.Absent{}, Game.To3{}, Game.Absent{}, Game.Absent{})
  +lose = play(Game.Absent{}, Game.Out{}, Game.Absent{}, Game.Absent{})
  List.append(&2, Choice, outs3("steal3", 2n, win, lose), outs3("steal3", 3n, win, lose))

# Success: every runner moves up one and the batter is out. Failure: the lead
# runner is forced, the others move up one, the batter is safe at first.
def bunt() -> List<&2, Choice>:
  List.append(&2, Choice,
    outs2("bunt", 1n, play(Game.Absent{}, Game.Absent{}, Game.To2{}, Game.Out{}), play(Game.Absent{}, Game.Absent{}, Game.Out{}, Game.To1{})),
    List.append(&2, Choice,
      outs2("bunt", 2n, play(Game.Absent{}, Game.To3{}, Game.Absent{}, Game.Out{}), play(Game.Absent{}, Game.Out{}, Game.Absent{}, Game.To1{})),
      outs2("bunt", 3n, play(Game.Absent{}, Game.To3{}, Game.To2{}, Game.Out{}), play(Game.Absent{}, Game.Out{}, Game.To2{}, Game.To1{}))))

# The walk from each base code: forced runners move up one.
def walk(c: Nat) -> Game.Play:
  match c:
    case 0n:
      play(Game.Absent{}, Game.Absent{}, Game.Absent{}, Game.To1{})
    case 1n+c1:
      match c1:
        case 0n:
          play(Game.Absent{}, Game.Absent{}, Game.To2{}, Game.To1{})
        case 1n+c2:
          match c2:
            case 0n:
              play(Game.Absent{}, Game.Absent{}, Game.Absent{}, Game.To1{})
            case 1n+c3:
              match c3:
                case 0n:
                  play(Game.Absent{}, Game.To3{}, Game.To2{}, Game.To1{})
                case 1n+c4:
                  match c4:
                    case 0n:
                      play(Game.Absent{}, Game.Absent{}, Game.Absent{}, Game.To1{})
                    case 1n+c5:
                      match c5:
                        case 0n:
                          play(Game.Absent{}, Game.Absent{}, Game.To2{}, Game.To1{})
                        case 1n+c6:
                          match c6:
                            case 0n:
                              play(Game.Absent{}, Game.Absent{}, Game.Absent{}, Game.To1{})
                            case 1n+c7:
                              play(Game.Run{}, Game.To3{}, Game.To2{}, Game.To1{})

def ibb.from(n: Nat, +c: Nat) -> List<&2, Choice>:
  match n:
    case 0n:
      Nil{}
    case 1n+m:
      +w = walk(c)
      List.append(&2, Choice, outs3("ibb", c, w, w), ibb.from(m, 1n+c))

# Every state; the walk is both outcomes (IBB has no failure).
def ibb() -> List<&2, Choice>:
  ibb.from(8n, 0n)

# Choices with a break-even rate: steal2, steal3, bunt.
def be_choices() -> List<&2, Choice>:
  List.append(&2, Choice, steal2(), List.append(&2, Choice, steal3(), bunt()))

# Choices with a run cost: bunt, ibb.
def dre_choices() -> List<&2, Choice>:
  List.append(&2, Choice, bunt(), ibb())

# Values
# ------

def be_of(+ts: List<&2, RE.Tot>, c: Choice) -> Maybe<&2, Nat>:
  match c:
    case Choice{_, +b, +o, w, l}:
      breakeven(before(ts, b, o), value(ts, outcome(b, o, w)), value(ts, outcome(b, o, l)))

def dre_of(+ts: List<&2, RE.Tot>, c: Choice) -> Maybe<&2, Z>:
  match c:
    case Choice{_, +b, +o, w, _}:
      gain(before(ts, b, o), value(ts, outcome(b, o, w)))

def be_go(cs: List<&2, Choice>, +ts: List<&2, RE.Tot>) -> List<&2, Maybe<&2, Nat>>:
  match cs:
    case Nil{}:
      Nil{}
    case Con{c, rest}:
      be_of(ts, c) <> be_go(rest, ts)

def dre_go(cs: List<&2, Choice>, +ts: List<&2, RE.Tot>) -> List<&2, Maybe<&2, Z>>:
  match cs:
    case Nil{}:
      Nil{}
    case Con{c, rest}:
      dre_of(ts, c) <> dre_go(rest, ts)

# Break-evens in basis points, in be_choices order.
def be_vals(+ts: List<&2, RE.Tot>) -> List<&2, Maybe<&2, Nat>>:
  be_go(be_choices(), ts)

# Run values in 10^-7 runs, in dre_choices order.
def dre_vals(+ts: List<&2, RE.Tot>) -> List<&2, Maybe<&2, Z>>:
  dre_go(dre_choices(), ts)
