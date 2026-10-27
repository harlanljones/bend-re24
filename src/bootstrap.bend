# Game-resampled bootstrap: 1024 seasons drawn from the good games with
# replacement, each scored with the same RE and decision-book functions as
# the point estimates, then 95% percentile intervals. The samples run as a
# balanced fork tree across CPU threads (or the GPU, from gpu.bend).
import Base
import ./state.bend as Game
import ./re24.bend as RE
import ./decisions.bend as Dec

# Random numbers (verbatim from bend-winprob sim.bend)
# ---------------------------------------------------

# A U32 hash (the mixer of demos/app_slash_boss_3d Synth.noise, no float).
def mix(+i: U32) -> U32:
  +a = (U32.xor(i, (i >> 16n : U32)) * 2146121005 : U32)
  +b = (U32.xor(a, (a >> 15n : U32)) * 2221713035 : U32)
  U32.xor(b, (b >> 16n : U32))

def nz.go(z: Bool, x: U32) -> U32:
  match z:
    case True{}:
      2654435769
    case False{}:
      x

# xorshift32 sticks at 0: never start it there.
def nz(+x: U32) -> U32:
  nz.go(U32.is_eq(x, 0), x)

def next(+x: U32) -> U32:
  +a = U32.xor(x, (x << 13n : U32))
  +b = U32.xor(a, (a >> 17n : U32))
  U32.xor(b, (b << 5n : U32))

# The games
# ---------

# Each leaf is one game's own 24-state counts.
type GTree is Data:
  GNil{}
  GLeaf{tots: List<&2, RE.Tot>}
  GNode{l: GTree, r: GTree}

def pow2(d: Nat) -> Nat:
  match d:
    case 0n:
      1n
    case 1n+p:
      +h = pow2(p)
      Nat.add(h, h)

# Binary digits of n (`fuel` bounds the loop; 64 covers every Nat).
def bits(fuel: Nat, n: Nat) -> Nat:
  match fuel n:
    case 0n _:
      0n
    case 1n+f 0n:
      0n
    case 1n+f 1n+m:
      1n+bits(f, Nat.div(1n+m, 2n))

# The least d with 2^d >= g.
def depth(+g: Nat) -> Nat:
  bits(64n, Nat.sub(g, 1n))

def leaf(xs: List<&2, List<&2, RE.Tot>>) -> GTree:
  match xs:
    case Nil{}:
      GNil{}
    case Con{ts, _}:
      GLeaf{ts}

# A perfect tree of depth d over the games in order.
def build(d: Nat, +xs: List<&2, List<&2, RE.Tot>>) -> GTree:
  match d:
    case 0n:
      leaf(xs)
    case 1n++p:
      +h = pow2(p)
      GNode{build(p, List.take(&2, List<&2, RE.Tot>, xs, h)), build(p, List.drop(&2, List<&2, RE.Tot>, xs, h))}

# Game i of a depth-d tree; `h` is 2^(d-1).
def pick(d: Nat, +t: GTree, +i: Nat, +h: Nat) -> List<&2, RE.Tot>:
  match d:
    case 0n:
      match t:
        case GLeaf{ts}:
          ts
        case _:
          RE.zeros24()
    case 1n+p:
      match t:
        case GNode{l, r}:
          +left = Nat.is_lt(i, h)
          pick(p, Bool.pick(GTree, left, l, r), Bool.pick(Nat, left, i, Nat.sub(i, h)), Nat.div(h, 2n))
        case _:
          RE.zeros24()

# Resampling
# ----------

type Cfg is Data:
  Cfg{tree: GTree, depth: Nat, games: Nat, seed: U32}

def cfg(+games: List<&2, List<&2, RE.Tot>>, seed: U32) -> Cfg:
  +g = List.length(&2, List<&2, RE.Tot>, games)
  +d = depth(g)
  Cfg{build(d, games), d, g, seed}

def draw(n: Nat, +x: U32, acc: List<&2, RE.Tot>, +t: GTree, +d: Nat, +g: Nat) -> List<&2, RE.Tot>:
  match n:
    case 0n:
      acc
    case 1n+m:
      +y = next(x)
      +i = Nat.mod(U32.to_nat(y), g)
      draw(m, y, RE.tots_sum(acc, pick(d, t, i, Nat.div(pow2(d), 2n))), t, d, g)

# Season k: G games drawn with replacement, summed.
def resample(+k: Nat, +c: Cfg) -> List<&2, RE.Tot>:
  match c:
    case Cfg{t, d, g, seed}:
      draw(g, nz(mix(U32.xor(seed, U32.from_nat(k)))), RE.zeros24(), t, d, g)

type Sample is Data:
  Sample{re: List<&2, Maybe<&2, Nat>>, be: List<&2, Maybe<&2, Nat>>, dre: List<&2, Maybe<&2, Dec.Z>>}

def re_list(n: Nat, +ts: List<&2, RE.Tot>, +i: Nat) -> List<&2, Maybe<&2, Nat>>:
  match n:
    case 0n:
      Nil{}
    case 1n+m:
      RE.re7(ts, i) <> re_list(m, ts, 1n+i)

def sample(+k: Nat, +c: Cfg) -> Sample:
  +ts = resample(k, c)
  Sample{re_list(24n, ts, 0n), Dec.be_vals(ts), Dec.dre_vals(ts)}

# Samples k .. k + 2^d - 1, in index order, as a balanced fork tree.
def tree(d: Nat, +k: Nat, +c: Cfg) -> List<&2, Sample>:
  match d:
    case 0n:
      [sample(k, c)]
    case 1n++p:
      a b = tree(p, k, c) tree(p, Nat.add(k, pow2(p)), c)
      List.append(&2, Sample, a, b)

# A private copy of the games: a lane that reads its own copy pays no atomic
# count on a tree every lane shares.
def copy_tots(ts: List<&2, RE.Tot>) -> List<&2, RE.Tot>:
  match ts:
    case Nil{}:
      Nil{}
    case Con{RE.Tot{r, n}, rest}:
      RE.Tot{r, n} <> copy_tots(rest)

def copy_tree(t: GTree) -> GTree:
  match t:
    case GNil{}:
      GNil{}
    case GLeaf{ts}:
      GLeaf{copy_tots(ts)}
    case GNode{l, r}:
      GNode{copy_tree(l), copy_tree(r)}

def fresh(c: Cfg) -> Cfg:
  match c:
    case Cfg{t, d, g, seed}:
      Cfg{copy_tree(t), d, g, seed}

# Samples k .. k + n - 1, one after another.
def seq(n: Nat, +k: Nat, +c: Cfg) -> List<&2, Sample>:
  match n:
    case 0n:
      Nil{}
    case 1n+m:
      sample(k, c) <> seq(m, 1n+k, c)

# Samples k .. k + 2^(top+inner) - 1, in index order: `top` levels of forks,
# each of whose 2^top leaves runs 2^inner samples in turn on its own copy.
def lanes(top: Nat, +inner: Nat, +k: Nat, +c: Cfg) -> List<&2, Sample>:
  match top:
    case 0n:
      seq(pow2(inner), k, fresh(c))
    case 1n++p:
      a b = lanes(p, inner, k, c) lanes(p, inner, Nat.add(k, pow2(Nat.add(p, inner))), c)
      List.append(&2, Sample, a, b)

# B = 2^10 = 1024 samples; the percentile ranks below assume it.
def log_size() -> Nat:
  10n

def size() -> Nat:
  pow2(log_size())

# 2^5 lanes, each with its own copy of the games, each running 2^5 samples:
# on 24 threads this beats one tree of 1024 samples sharing one copy.
def run.cpu(c: Cfg) -> List<&2, Sample>:
  lanes(5n, Nat.sub(log_size(), 5n), 0n, c)

# Percentile intervals
# --------------------

# 0-based ranks 25 and 998 of 1024 sorted values: the 95% interval.
type Band is Data:
  Band{lo: Maybe<&2, Nat>, hi: Maybe<&2, Nat>}

type ZBand is Data:
  ZBand{lo: Maybe<&2, Dec.Z>, hi: Maybe<&2, Dec.Z>}

type CIs is Data:
  CIs{re: List<&2, Band>, be: List<&2, Band>, dre: List<&2, ZBand>}

# Ascending, undefined last.
def le_n(a: Maybe<&2, Nat>, b: Maybe<&2, Nat>) -> Bool:
  match a b:
    case Some{x} Some{y}:
      Nat.is_le(x, y)
    case Some{_} None{}:
      True{}
    case None{} Some{_}:
      False{}
    case None{} None{}:
      True{}

def le_z(a: Maybe<&2, Dec.Z>, b: Maybe<&2, Dec.Z>) -> Bool:
  match a b:
    case Some{x} Some{y}:
      Dec.zle(x, y)
    case Some{_} None{}:
      True{}
    case None{} Some{_}:
      False{}
    case None{} None{}:
      True{}

def at_n(xs: List<&2, Maybe<&2, Nat>>, j: Nat) -> Maybe<&2, Nat>:
  match xs j:
    case Nil{} _:
      None{}
    case Con{x, _} 0n:
      x
    case Con{_, rest} 1n+m:
      at_n(rest, m)

def at_z(xs: List<&2, Maybe<&2, Dec.Z>>, j: Nat) -> Maybe<&2, Dec.Z>:
  match xs j:
    case Nil{} _:
      None{}
    case Con{x, _} 0n:
      x
    case Con{_, rest} 1n+m:
      at_z(rest, m)

def band(xs: List<&2, Maybe<&2, Nat>>) -> Band:
  +s = List.sort(~Maybe<&2, Nat>, ~le_n, xs)
  Band{at_n(s, 25n), at_n(s, 998n)}

def zband(xs: List<&2, Maybe<&2, Dec.Z>>) -> ZBand:
  +s = List.sort(~Maybe<&2, Dec.Z>, ~le_z, xs)
  ZBand{at_z(s, 25n), at_z(s, 998n)}

def col_re(ss: List<&2, Sample>, +j: Nat) -> List<&2, Maybe<&2, Nat>>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{Sample{re, _, _}, rest}:
      at_n(re, j) <> col_re(rest, j)

def col_be(ss: List<&2, Sample>, +j: Nat) -> List<&2, Maybe<&2, Nat>>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{Sample{_, be, _}, rest}:
      at_n(be, j) <> col_be(rest, j)

def col_dre(ss: List<&2, Sample>, +j: Nat) -> List<&2, Maybe<&2, Dec.Z>>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{Sample{_, _, dre}, rest}:
      at_z(dre, j) <> col_dre(rest, j)

def bands_re(n: Nat, +ss: List<&2, Sample>, +j: Nat) -> List<&2, Band>:
  match n:
    case 0n:
      Nil{}
    case 1n+m:
      band(col_re(ss, j)) <> bands_re(m, ss, 1n+j)

def bands_be(n: Nat, +ss: List<&2, Sample>, +j: Nat) -> List<&2, Band>:
  match n:
    case 0n:
      Nil{}
    case 1n+m:
      band(col_be(ss, j)) <> bands_be(m, ss, 1n+j)

def bands_dre(n: Nat, +ss: List<&2, Sample>, +j: Nat) -> List<&2, ZBand>:
  match n:
    case 0n:
      Nil{}
    case 1n+m:
      zband(col_dre(ss, j)) <> bands_dre(m, ss, 1n+j)

# The intervals for every RE state and every decision, in catalogue order.
def cis(+ss: List<&2, Sample>) -> CIs:
  CIs{bands_re(24n, ss, 0n),
    bands_be(List.length(&2, Dec.Choice, Dec.be_choices()), ss, 0n),
    bands_dre(List.length(&2, Dec.Choice, Dec.dre_choices()), ss, 0n)}
