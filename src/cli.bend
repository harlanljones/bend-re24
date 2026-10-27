# The re24 command line: read a plays CSV, replay it, print the records.
#   re24 run <plays.csv>          summary, RE, transition table, decisions
# Every number printed comes from re24.bend (or decisions.bend, bootstrap.bend).
import Base
import ./state.bend as Game
import ./spec.bend as Spec
import ./counts.bend as Counts
import ./re24.bend as RE
import ./decisions.bend as Dec
import ./bootstrap.bend as Boot

# Reading a file
# --------------

def read.step(r: File & Result<&1, &1, U32 & String, String>, acc: List<&2, String>, more: File -> List<&2, String> -> IO(Maybe<&2, String>)) -> IO(Maybe<&2, String>):
  (f, res) = r
  match res:
    case Fail{e}:
      do IO<Maybe<&2, String>>:
        File.close(f)
        return None{}
    case Done{SNil{}}:
      do IO<Maybe<&2, String>>:
        File.close(f)
        return Some{String.concat(List.reverse(&2, String, acc))}
    case Done{chunk}:
      more(f, chunk <> acc)

# The whole file, 64 KiB at a time (at most 16384 chunks).
def read.go(fuel: Nat, f: File, acc: List<&2, String>) -> IO(Maybe<&2, String>):
  match fuel:
    case 0n:
      do IO<Maybe<&2, String>>:
        File.close(f)
        return None{}
    case 1n+g:
      do IO<Maybe<&2, String>>:
        r : File & Result<&1, &1, U32 & String, String> <- File.read(f, 65536)
        read.step(r, acc, f2 => acc2 => read.go(g, f2, acc2))

def read.opened(r: Result<&1, &1, U32 & String, File>) -> IO(Maybe<&2, String>):
  match r:
    case Fail{e}:
      IO.pure(Maybe<&2, String>, None{})
    case Done{f}:
      read.go(16384n, f, Nil{})

# Parsing the plays CSV
# ---------------------
# game,inn,half,outs,bases,play,end_bases,event_outs,event_runs,fate_runs,event_cd

def dest(c: Char) -> Maybe<&2, Game.Dest>:
  match c:
    case '-':
      Some{Game.Absent{}}
    case 'X':
      Some{Game.Out{}}
    case 'R':
      Some{Game.Run{}}
    case '1':
      Some{Game.To1{}}
    case '2':
      Some{Game.To2{}}
    case '3':
      Some{Game.To3{}}
    case _:
      None{}

def play4(m3: Maybe<&2, Game.Dest>, m2: Maybe<&2, Game.Dest>, m1: Maybe<&2, Game.Dest>, mb: Maybe<&2, Game.Dest>) -> Maybe<&2, Game.Play>:
  do Maybe<&2, Game.Play>:
    a : Game.Dest <- m3
    b : Game.Dest <- m2
    c : Game.Dest <- m1
    d : Game.Dest <- mb
    return Game.Play{a, b, c, d}

# Four characters, slots r3 r2 r1 batter.
def play_of(s: String) -> Maybe<&2, Game.Play>:
  match s:
    case SCon{c3, SCon{c2, SCon{c1, SCon{cb, SNil{}}}}}:
      play4(dest(c3), dest(c2), dest(c1), dest(cb))
    case _:
      None{}

# 0 bats first (the top), 1 bats last.
def half_n(n: Nat) -> Maybe<&2, Bool>:
  match n:
    case 0n:
      Some{True{}}
    case 1n+k:
      match k:
        case 0n:
          Some{False{}}
        case 1n+j:
          None{}

def half_of(m: Maybe<&2, Nat>) -> Maybe<&2, Bool>:
  match m:
    case None{}:
      None{}
    case Some{n}:
      half_n(n)

def bad(+n: Nat, field: String) -> String:
  "ERROR line " ++ Nat.show(n) ++ ": bad " ++ field

def need(-A: Data, m: Maybe<&2, A>, +n: Nat, field: String) -> Result<&2, &2, String, A>:
  match m:
    case None{}:
      Fail{bad(n, field)}
    case Some{x}:
      Done{x}

def fields(fs: List<&2, String>, +n: Nat) -> Result<&2, &2, String, RE.Rec>:
  match fs:
    case Con{g, Con{inn, Con{half, Con{outs, Con{bases, Con{play, Con{eb, Con{eo, Con{er, Con{fr, Con{cd, Nil{}}}}}}}}}}}}:
      do Result<&2, &2, String, RE.Rec>:
        g1 : Nat <- need(Nat, Nat.read(g), n, "game")
        inn1 : Nat <- need(Nat, Nat.read(inn), n, "inn")
        top : Bool <- need(Bool, half_of(Nat.read(half)), n, "half")
        outs1 : Nat <- need(Nat, Nat.read(outs), n, "outs")
        bases1 : Nat <- need(Nat, Nat.read(bases), n, "bases")
        p : Game.Play <- need(Game.Play, play_of(play), n, "play")
        eb1 : Nat <- need(Nat, Nat.read(eb), n, "end_bases")
        eo1 : Nat <- need(Nat, Nat.read(eo), n, "event_outs")
        er1 : Nat <- need(Nat, Nat.read(er), n, "event_runs")
        fr1 : Nat <- need(Nat, Nat.read(fr), n, "fate_runs")
        cd1 : Nat <- need(Nat, Nat.read(cd), n, "event_cd")
        return RE.Rec{g1, inn1, top, outs1, bases1, p, eb1, eo1, er1, fr1}
    case _:
      Fail{bad(n, "fields")}

def parse.add(r: Result<&2, &2, String, RE.Rec>, rs: List<&2, RE.Rec>) -> Result<&2, &2, String, List<&2, RE.Rec>>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{x}:
      Done{x <> rs}

def parse.line(l: String, +n: Nat, rs: List<&2, RE.Rec>) -> Result<&2, &2, String, List<&2, RE.Rec>>:
  match l:
    case SNil{}:
      Done{rs}
    case SCon{c, t}:
      parse.add(fields(String.split(SCon{c, t}, ','), n), rs)

def parse.step(acc: Result<&2, &2, String, List<&2, RE.Rec>>, l: String, +n: Nat) -> Result<&2, &2, String, List<&2, RE.Rec>>:
  match acc:
    case Fail{e}:
      Fail{e}
    case Done{rs}:
      parse.line(l, n, rs)

# Records newest first; `n` is the 1-based line number.
def parse.go(ls: List<&2, String>, +n: Nat, acc: Result<&2, &2, String, List<&2, RE.Rec>>) -> Result<&2, &2, String, List<&2, RE.Rec>>:
  match ls:
    case Nil{}:
      acc
    case Con{l, rest}:
      parse.go(rest, 1n+n, parse.step(acc, l, n))

def parse.fin(r: Result<&2, &2, String, List<&2, RE.Rec>>) -> Result<&2, &2, String, List<&2, RE.Rec>>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{rs}:
      Done{List.reverse(&2, RE.Rec, rs)}

# Line 1 is the header.
def parse.body(ls: List<&2, String>) -> Result<&2, &2, String, List<&2, RE.Rec>>:
  match ls:
    case Nil{}:
      Done{Nil{}}
    case Con{_, rest}:
      parse.fin(parse.go(rest, 2n, Done{Nil{}}))

def parse(text: String) -> Result<&2, &2, String, List<&2, RE.Rec>>:
  parse.body(String.lines(text))

# Printing
# --------

def sp(+n: Nat) -> String:
  " " ++ Nat.show(n)

# State i is bases i mod 8 and outs i / 8; the end of the half (24) is `0 3`.
def state(+i: Nat) -> String:
  sp(Nat.mod(i, 8n)) ++ sp(Nat.div(i, 8n))

def milli_show(+runs: Nat, n: Nat) -> String:
  match n:
    case 0n:
      " NA"
    case 1n+m:
      sp(RE.milli(runs, 1n+m))

def re_lines(ts: List<&2, RE.Tot>, +i: Nat) -> List<&2, String>:
  match ts:
    case Nil{}:
      Nil{}
    case Con{RE.Tot{+runs, +n}, rest}:
      ("RE" ++ state(i) ++ sp(runs) ++ sp(n) ++ milli_show(runs, n)) <> re_lines(rest, 1n+i)

def plays(ts: List<&2, RE.Tot>) -> Nat:
  match ts:
    case Nil{}:
      0n
    case Con{RE.Tot{_, n}, rest}:
      Nat.add(n, plays(rest))

# One transition-table entry: from, to, runs, count.
type TL is Data:
  TL{from: Nat, to: Nat, runs: Nat, n: Nat}

def t_cells(+f: Nat, cs: List<&2, Spec.Cell>, acc: List<&2, TL>) -> List<&2, TL>:
  match cs:
    case Nil{}:
      acc
    case Con{Spec.Cell{to, r, n}, rest}:
      t_cells(f, rest, TL{f, to, r, n} <> acc)

def t_rows(rows: List<&2, Spec.Row>, acc: List<&2, TL>) -> List<&2, TL>:
  match rows:
    case Nil{}:
      acc
    case Con{Spec.Row{f, cs}, rest}:
      t_rows(rest, t_cells(f, cs, acc))

def tl_le(a: TL, b: TL) -> Bool:
  match a:
    case TL{+f1, +t1, r1, _}:
      match b:
        case TL{+f2, +t2, r2, _}:
          Nat.is_lt(f1, f2) || (Nat.is_eq(f1, f2) &&
            (Nat.is_lt(t1, t2) || (Nat.is_eq(t1, t2) && Nat.is_le(r1, r2))))

def t_line(t: TL) -> String:
  match t:
    case TL{f, to, r, n}:
      "T" ++ state(f) ++ state(to) ++ sp(r) ++ sp(n)

def t_lines(ts: List<&2, TL>) -> List<&2, String>:
  match ts:
    case Nil{}:
      Nil{}
    case Con{t, rest}:
      t_line(t) <> t_lines(rest)

# The certificate: each state's visit count equals the table's row total.
def cert.at(ok: Bool, i: Nat, rest: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match ok:
    case False{}:
      Some{i}
    case True{}:
      rest

def cert(ts: List<&2, RE.Tot>, +table: List<&2, Spec.Row>, +i: Nat) -> Maybe<&2, Nat>:
  match ts:
    case Nil{}:
      None{}
    case Con{RE.Tot{_, n}, rest}:
      cert.at(Nat.is_eq(n, Spec.row_sum(table, i)), i, cert(rest, table, 1n+i))

# The decision book

def opt(m: Maybe<&2, Nat>) -> String:
  match m:
    case None{}:
      " NA"
    case Some{x}:
      sp(x)

def zopt(m: Maybe<&2, Dec.Z>) -> String:
  match m:
    case None{}:
      " NA"
    case Some{z}:
      " " ++ Dec.zshow(z)

# `<tag> <kind> <bases> <outs>`
def head(tag: String, c: Dec.Choice) -> String:
  match c:
    case Dec.Choice{kind, b, o, _, _}:
      tag ++ " " ++ kind ++ sp(b) ++ sp(o)

def be_lines(cs: List<&2, Dec.Choice>, vs: List<&2, Maybe<&2, Nat>>) -> List<&2, String>:
  match cs vs:
    case Con{c, cr} Con{v, vr}:
      (head("BE", c) ++ opt(v)) <> be_lines(cr, vr)
    case _ _:
      Nil{}

def dre_lines(cs: List<&2, Dec.Choice>, vs: List<&2, Maybe<&2, Dec.Z>>) -> List<&2, String>:
  match cs vs:
    case Con{c, cr} Con{v, vr}:
      (head("DRE", c) ++ zopt(v)) <> dre_lines(cr, vr)
    case _ _:
      Nil{}

def report(sea: RE.Season, +table: List<&2, Spec.Row>) -> String:
  match sea:
    case RE.Season{seen, good, bad, lines, +ts, _, _, halves, partial}:
      String.join(
        ("GAMES" ++ sp(seen) ++ sp(good) ++ sp(bad)) <>
        ("HALVES" ++ sp(halves) ++ sp(partial)) <>
        ("PLAYS" ++ sp(plays(ts))) <>
        List.append(&2, String, lines,
          List.append(&2, String, re_lines(ts, 0n),
            List.append(&2, String, t_lines(List.sort(~TL, ~tl_le, t_rows(table, Nil{}))),
              List.append(&2, String, be_lines(Dec.be_choices(), Dec.be_vals(ts)),
                dre_lines(Dec.dre_choices(), Dec.dre_vals(ts)))))), "\n")

# Bootstrap intervals

def band_line(head: String, b: Boot.Band) -> String:
  match b:
    case Boot.Band{lo, hi}:
      head ++ opt(lo) ++ opt(hi)

def zband_line(head: String, b: Boot.ZBand) -> String:
  match b:
    case Boot.ZBand{lo, hi}:
      head ++ zopt(lo) ++ zopt(hi)

def ci_re(bs: List<&2, Boot.Band>, +i: Nat) -> List<&2, String>:
  match bs:
    case Nil{}:
      Nil{}
    case Con{b, rest}:
      band_line("CI RE" ++ state(i), b) <> ci_re(rest, 1n+i)

def ci_be(cs: List<&2, Dec.Choice>, bs: List<&2, Boot.Band>) -> List<&2, String>:
  match cs bs:
    case Con{c, cr} Con{b, br}:
      band_line(head("CI BE", c), b) <> ci_be(cr, br)
    case _ _:
      Nil{}

def ci_dre(cs: List<&2, Dec.Choice>, bs: List<&2, Boot.ZBand>) -> List<&2, String>:
  match cs bs:
    case Con{c, cr} Con{b, br}:
      zband_line(head("CI DRE", c), b) <> ci_dre(cr, br)
    case _ _:
      Nil{}

def boot.report(+seed: U32, +g: Nat, cis: Boot.CIs) -> String:
  match cis:
    case Boot.CIs{re, be, dre}:
      String.join(("BOOT" ++ sp(Boot.size()) ++ " " ++ U32.show(seed) ++ sp(g)) <>
        List.append(&2, String, ci_re(re, 0n),
          List.append(&2, String, ci_be(Dec.be_choices(), be), ci_dre(Dec.dre_choices(), dre))), "\n")

# Effects
# -------

def usage() -> IO(Unit):
  do IO<Unit>:
    IO.print_err("usage: re24 run <plays.csv> | re24 boot <plays.csv> <seed>")
    IO.exit(2)

def fail(msg: String, code: U32) -> IO(Unit):
  do IO<Unit>:
    IO.print_err(msg)
    IO.exit(code)

def run.cert(m: Maybe<&2, Nat>, text: String) -> IO(Unit):
  match m:
    case None{}:
      IO.print(text)
    case Some{i}:
      fail("ERROR table " ++ Nat.show(i), 1)

def run.season(sea: RE.Season) -> IO(Unit):
  match sea:
    case RE.Season{seen, good, bad, lines, +ts, games, +obs, halves, partial}:
      +table = Counts.tally(obs)
      run.cert(cert(ts, table, 0n), report(RE.Season{seen, good, bad, lines, ts, games, obs, halves, partial}, table))

def run.parsed(r: Result<&2, &2, String, List<&2, RE.Rec>>) -> IO(Unit):
  match r:
    case Fail{e}:
      fail(e, 2)
    case Done{recs}:
      run.season(RE.season(recs))

def run.text(+path: String, text: Maybe<&2, String>) -> IO(Unit):
  match text:
    case None{}:
      fail("ERROR cannot read " ++ path, 2)
    case Some{t}:
      run.parsed(parse(t))

def read_file(+path: String) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    read.opened(r)

def run(args: List<String>) -> IO(Unit):
  match args:
    case Con{+path, Nil{}}:
      do IO<Unit>:
        text : Maybe<&2, String> <- read_file(path)
        run.text(path, text)
    case _:
      usage()

# `go` runs the samples: Boot.run.cpu here, the GPU fork in gpu.bend.
def boot.games(~go: Boot.Cfg -> List<&2, Boot.Sample>, +seed: U32, +g: Nat, +games: List<&2, List<&2, RE.Tot>>, none: Bool) -> IO(Unit):
  match none:
    case True{}:
      fail("ERROR no good games", 1)
    case False{}:
      IO.print(boot.report(seed, g, Boot.cis(go(Boot.cfg(games, seed)))))

def boot.season(~go: Boot.Cfg -> List<&2, Boot.Sample>, +seed: U32, sea: RE.Season) -> IO(Unit):
  match sea:
    case RE.Season{_, +good, _, _, _, +games, _, _, _}:
      boot.games(~go, seed, good, games, Nat.is_eq(good, 0n))

def boot.parsed(~go: Boot.Cfg -> List<&2, Boot.Sample>, +seed: U32, r: Result<&2, &2, String, List<&2, RE.Rec>>) -> IO(Unit):
  match r:
    case Fail{e}:
      fail(e, 2)
    case Done{recs}:
      boot.season(~go, seed, RE.season(recs))

def boot.text(~go: Boot.Cfg -> List<&2, Boot.Sample>, +seed: U32, +path: String, text: Maybe<&2, String>) -> IO(Unit):
  match text:
    case None{}:
      fail("ERROR cannot read " ++ path, 2)
    case Some{t}:
      boot.parsed(~go, seed, parse(t))

def boot.seeded(~go: Boot.Cfg -> List<&2, Boot.Sample>, +path: String, m: Maybe<&2, U32>) -> IO(Unit):
  match m:
    case None{}:
      usage()
    case Some{+seed}:
      do IO<Unit>:
        text : Maybe<&2, String> <- read_file(path)
        boot.text(~go, seed, path, text)

def boot(~go: Boot.Cfg -> List<&2, Boot.Sample>, args: List<String>) -> IO(Unit):
  match args:
    case Con{+path, Con{s, Nil{}}}:
      boot.seeded(~go, path, U32.read(s))
    case _:
      usage()

def route(args: List<String>, is_run: Bool, is_boot: Bool) -> IO(Unit):
  match is_run is_boot:
    case True{} _:
      run(args)
    case False{} True{}:
      boot(~Boot.run.cpu, args)
    case False{} False{}:
      usage()

def dispatch(args: List<String>) -> IO(Unit):
  match args:
    case Con{prog, Con{+cmd, rest}}:
      route(rest, String.eq(cmd, "run"), String.eq(cmd, "boot"))
    case _:
      usage()

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    dispatch(args)
