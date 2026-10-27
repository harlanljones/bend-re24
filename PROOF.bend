# Proofs of LAWS.bend, one def per law (`def Laws.<law>`). A law with no def
# here is an open claim, and `bend PROOF.bend` reports it.
import Base
import ./src/state.bend as Game
import ./src/spec.bend as Spec
import ./src/counts.bend as Counts
import ./src/re24.bend as RE
import ./LAWS.bend as Laws

# Addition (as in demos/proof_numerics)
# -------------------------------------

def add_succ(a: Nat, -b: Nat) -> {1n+Nat.add(a, b) == Nat.add(a, 1n+b) : Nat}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      %add_succ(p, b) : {2n+Nat.add(p, b) == 1n+_ : Nat}
      {==}

def add_swap(x: Nat, +y: Nat, +z: Nat) -> {Nat.add(x, Nat.add(y, z)) == Nat.add(y, Nat.add(x, z)) : Nat}:
  match x:
    case 0n:
      {==}
    case 1n+q:
      %add_succ(y, Nat.add(q, z)) : {1n+Nat.add(q, Nat.add(y, z)) == _ : Nat}
      %add_swap(q, y, z) : {1n+Nat.add(q, Nat.add(y, z)) == 1n+_ : Nat}
      {==}

def swap4(a: Nat, +b: Nat, +c: Nat, +d: Nat) -> {Nat.add(Nat.add(a, b), Nat.add(c, d)) == Nat.add(Nat.add(a, c), Nat.add(b, d)) : Nat}:
  match a:
    case 0n:
      add_swap(b, c, d)
    case 1n+p:
      %swap4(p, b, c, d) : {1n+Nat.add(Nat.add(p, b), Nat.add(c, d)) == 1n+_ : Nat}
      {==}

# Outs
# ----

def outs_close(o: Nat, top: Bool, -inn: Nat, -so: Nat, -sb: Game.Bases, -away: Game.Line, -home: Game.Line, -rej: Nat, -bs: Game.Bases, -l: Game.Line, w: {Nat.is_lt(so, 3n) == True{} : Bool})
  -> {Nat.is_lt(Game.outs(Game.close(o, Game.State{inn, top, so, sb, away, home, rej}, bs, l)), 3n) == True{} : Bool}:
  match o:
    case 0n:
      match top:
        case True{}:
          {==}
        case False{}:
          {==}
    case 1n+o1:
      match o1:
        case 0n:
          match top:
            case True{}:
              {==}
            case False{}:
              {==}
        case 1n+o2:
          match o2:
            case 0n:
              match top:
                case True{}:
                  {==}
                case False{}:
                  {==}
            case 1n+o3:
              match o3:
                case 0n:
                  match top:
                    case True{}:
                      {==}
                    case False{}:
                      {==}
                case 1n+o4:
                  w

def outs_after(m: Maybe<Game.Half>, top: Bool, -inn: Nat, -so: Nat, -sb: Game.Bases, -away: Game.Line, -home: Game.Line, -rej: Nat, w: {Nat.is_lt(so, 3n) == True{} : Bool})
  -> {Nat.is_lt(Game.outs(Game.after(Game.State{inn, top, so, sb, away, home, rej}, m)), 3n) == True{} : Bool}:
  match m:
    case None{}:
      w
    case Some{h}:
      match h:
        case Game.Half{bs, l, o}:
          outs_close(o, top, inn, so, sb, away, home, rej, bs, l, w)

def outs_step(s: Game.State, p: Game.Play, w: {Nat.is_lt(Game.outs(s), 3n) == True{} : Bool})
  -> {Nat.is_lt(Game.outs(Game.step(s, p)), 3n) == True{} : Bool}:
  match s:
    case Game.State{+inn, +top, +so, +sb, +away, +home, +rej}:
      outs_after(Game.slots(p, Game.half_of(Game.State{inn, top, so, sb, away, home, rej})), top, inn, so, sb, away, home, rej, w)

def outs_run(ps: List<&2, Game.Play>, +s: Game.State, w: {Nat.is_lt(Game.outs(s), 3n) == True{} : Bool})
  -> {Nat.is_lt(Game.outs(Game.run(ps, s)), 3n) == True{} : Bool}:
  match ps:
    case Nil{}:
      w
    case Con{+p, rest}:
      outs_run(rest, Game.step(s, p), outs_step(s, p, w))

def Laws.outs_below_three(ps):
  outs_run(ps, Game.start(), {==})

# Box score (OBR 9.03(c))
# -----------------------
# HBal(e, h): batters equal e held runners, plus runners on base, runs,
# outs and left on base. The take pass increases e; the place pass lowers it.

def sym(-A: Type, -a: A, -b: A, e: {a == b : A}) -> {b == a : A}:
  %e : {_ == a : A}
  {==}

def add_succ_back(a: Nat, -b: Nat) -> {Nat.add(a, 1n+b) == 1n+Nat.add(a, b) : Nat}:
  sym(Nat, 1n+Nat.add(a, b), Nat.add(a, 1n+b), add_succ(a, b))

def HBal(e: Nat, h: Game.Half) -> Type:
  match h:
    case Game.Half{+bs, +l, o}:
      {Game.line_bat(l) == Nat.add(e, Nat.add(Game.count(bs), Game.line_demand(l))) : Nat}

def OkM(e: Nat, m: Maybe<Game.Half>) -> Type:
  match m:
    case None{}:
      Unit
    case Some{h}:
      HBal(e, h)

def count_b2(b1: Bool, -b3: Bool) -> {Game.count(Game.Bases{b1, True{}, b3}) == 1n+Game.count(Game.Bases{b1, False{}, b3}) : Nat}:
  match b1:
    case True{}:
      {==}
    case False{}:
      {==}

def count_b3(b1: Bool, b2: Bool) -> {Game.count(Game.Bases{b1, b2, True{}}) == 1n+Game.count(Game.Bases{b1, b2, False{}}) : Nat}:
  match b1:
    case True{}:
      match b2:
        case True{}:
          {==}
        case False{}:
          {==}
    case False{}:
      match b2:
        case True{}:
          {==}
        case False{}:
          {==}

def take1_bal_e(e: Nat, h: Game.Half, w: HBal(e, h)) -> OkM(1n+e, Game.take1(h)):
  match h:
    case Game.Half{bs, +l, o}:
      match bs:
        case Game.Bases{b1, b2, b3}:
          match b1:
            case True{}:
              %add_succ_back(e, Nat.add(Game.count(Game.Bases{False{}, b2, b3}), Game.line_demand(l))) : {Game.line_bat(l) == _ : Nat}
              w
            case False{}:
              Unit{}

def take2_bal_e(e: Nat, h: Game.Half, w: HBal(e, h)) -> OkM(1n+e, Game.take2(h)):
  match h:
    case Game.Half{bs, +l, o}:
      match bs:
        case Game.Bases{+b1, b2, +b3}:
          match b2:
            case True{}:
              %add_succ_back(e, Nat.add(Game.count(Game.Bases{b1, False{}, b3}), Game.line_demand(l))) : {Game.line_bat(l) == _ : Nat}
              %count_b2(b1, b3) : {Game.line_bat(l) == Nat.add(e, Nat.add(_, Game.line_demand(l))) : Nat}
              w
            case False{}:
              Unit{}

def take3_bal_e(e: Nat, h: Game.Half, w: HBal(e, h)) -> OkM(1n+e, Game.take3(h)):
  match h:
    case Game.Half{bs, +l, o}:
      match bs:
        case Game.Bases{+b1, +b2, b3}:
          match b3:
            case True{}:
              %add_succ_back(e, Nat.add(Game.count(Game.Bases{b1, b2, False{}}), Game.line_demand(l))) : {Game.line_bat(l) == _ : Nat}
              %count_b3(b1, b2) : {Game.line_bat(l) == Nat.add(e, Nat.add(_, Game.line_demand(l))) : Nat}
              w
            case False{}:
              Unit{}

def take_bat_bal_e(e: Nat, h: Game.Half, w: HBal(e, h)) -> HBal(1n+e, Game.take_bat(h)):
  match h:
    case Game.Half{+bs, l, o}:
      match l:
        case Game.Line{+bat, +runs, +lo, +lob}:
          %w : {1n+bat == 1n+_ : Nat}
          {==}

def take_origin_bal(k: Nat, e: Nat, h: Game.Half, w: HBal(e, h)) -> OkM(1n+e, Game.take_origin(k, h)):
  match k:
    case 0n:
      take3_bal_e(e, h, w)
    case 1n+k1:
      match k1:
        case 0n:
          take2_bal_e(e, h, w)
        case 1n+k2:
          match k2:
            case 0n:
              take1_bal_e(e, h, w)
            case 1n+k3:
              take_bat_bal_e(e, h, w)

def put_bal_e(e: Nat, d: Game.Dest, h: Game.Half, w: HBal(1n+e, h)) -> OkM(e, Game.put(d, h)):
  match d:
    case Game.Absent{}:
      Unit{}
    case Game.Out{}:
      match h:
        case Game.Half{+bs, l, o}:
          match l:
            case Game.Line{+bat, +runs, +lo, +lob}:
              %add_succ(runs, Nat.add(lo, lob)) : {bat == Nat.add(e, Nat.add(Game.count(bs), _)) : Nat}
              %add_succ(Game.count(bs), Nat.add(runs, Nat.add(lo, lob))) : {bat == Nat.add(e, _) : Nat}
              %add_succ(e, Nat.add(Game.count(bs), Nat.add(runs, Nat.add(lo, lob)))) : {bat == _ : Nat}
              w
    case Game.Run{}:
      match h:
        case Game.Half{+bs, l, o}:
          match l:
            case Game.Line{+bat, +runs, +lo, +lob}:
              %add_succ(Game.count(bs), Nat.add(runs, Nat.add(lo, lob))) : {bat == Nat.add(e, _) : Nat}
              %add_succ(e, Nat.add(Game.count(bs), Nat.add(runs, Nat.add(lo, lob)))) : {bat == _ : Nat}
              w
    case Game.To1{}:
      match h:
        case Game.Half{bs, +l, o}:
          match bs:
            case Game.Bases{b1, b2, b3}:
              match b1:
                case True{}:
                  Unit{}
                case False{}:
                  %add_succ(e, Nat.add(Game.count(Game.Bases{False{}, b2, b3}), Game.line_demand(l))) : {Game.line_bat(l) == _ : Nat}
                  w
    case Game.To2{}:
      match h:
        case Game.Half{bs, +l, o}:
          match bs:
            case Game.Bases{+b1, b2, +b3}:
              match b2:
                case True{}:
                  Unit{}
                case False{}:
                  %sym(Nat, Game.count(Game.Bases{b1, True{}, b3}), 1n+Game.count(Game.Bases{b1, False{}, b3}), count_b2(b1, b3)) : {Game.line_bat(l) == Nat.add(e, Nat.add(_, Game.line_demand(l))) : Nat}
                  %add_succ(e, Nat.add(Game.count(Game.Bases{b1, False{}, b3}), Game.line_demand(l))) : {Game.line_bat(l) == _ : Nat}
                  w
    case Game.To3{}:
      match h:
        case Game.Half{bs, +l, o}:
          match bs:
            case Game.Bases{+b1, +b2, b3}:
              match b3:
                case True{}:
                  Unit{}
                case False{}:
                  %sym(Nat, Game.count(Game.Bases{b1, b2, True{}}), 1n+Game.count(Game.Bases{b1, b2, False{}}), count_b3(b1, b2)) : {Game.line_bat(l) == Nat.add(e, Nat.add(_, Game.line_demand(l))) : Nat}
                  %add_succ(e, Nat.add(Game.count(Game.Bases{b1, b2, False{}}), Game.line_demand(l))) : {Game.line_bat(l) == _ : Nat}
                  w

# Pending predicates: the hand count is part of the invariant.
def PBal(p: Game.Pending) -> Type:
  match p:
    case Game.Pending{+h, +n, _, _, _, _}:
      HBal(n, h)

def OkP(m: Maybe<&2, Game.Pending>) -> Type:
  match m:
    case None{}:
      Unit
    case Some{p}:
      PBal(p)

def take_done_bal(m: Maybe<Game.Half>, p: Game.Pending, w: OkM(1n+Game.p_hand(p), m)) -> OkP(Game.take_slot_done(m, p)):
  match m:
    case None{}:
      Unit{}
    case Some{h}:
      match p:
        case Game.Pending{_, n, r3, r2, r1, bd}:
          w

def take_dest_move(d: Game.Dest, +k: Nat, p: Game.Pending, w: PBal(p)) -> OkP(Game.take_slot_dest(True{}, k, p)):
  match p:
    case Game.Pending{+h, +n, r3, r2, r1, bd}:
      take_done_bal(Game.take_origin(k, h), Game.Pending{h, n, r3, r2, r1, bd}, take_origin_bal(k, n, h, w))

def take_dest_absent(k: Nat, p: Game.Pending, w: PBal(p)) -> OkP(Game.take_slot_dest(False{}, k, p)):
  match p:
    case Game.Pending{h, n, r3, r2, r1, bd}:
      w

def take_dest_bal(d: Game.Dest, +k: Nat, p: Game.Pending, w: PBal(p)) -> OkP(Game.take_slot_dest(Game.is_moved(d), k, p)):
  match d:
    case Game.Absent{}:
      take_dest_absent(k, p, w)
    case Game.Out{}:
      take_dest_move(d, k, p, w)
    case Game.Run{}:
      take_dest_move(d, k, p, w)
    case Game.To1{}:
      take_dest_move(d, k, p, w)
    case Game.To2{}:
      take_dest_move(d, k, p, w)
    case Game.To3{}:
      take_dest_move(d, k, p, w)

def take_slot_bal(+k: Nat, +p: Game.Pending, w: PBal(p)) -> OkP(Game.take_slot(k, p)):
  match p:
    case Game.Pending{+h, +n, r3, r2, r1, bd}:
      +q = {Game.Pending{h, n, r3, r2, r1, bd} : Game.Pending}
      take_dest_bal(Game.p_dest(k, q), k, q, w)

def bind_take_bal(+k: Nat, m: Maybe<&2, Game.Pending>, w: OkP(m)) -> OkP(Game.bind_take(k, m)):
  match m:
    case None{}:
      Unit{}
    case Some{p}:
      take_slot_bal(k, p, w)

def take_all_bal(+p: Game.Play, +h: Game.Half, w: HBal(0n, h)) -> OkP(Game.take_all(p, h)):
  match p:
    case Game.Play{+r3, +r2, +r1, +bd}:
      bind_take_bal(3n, Game.bind_take(2n, Game.bind_take(1n, Game.take_slot(0n, Game.Pending{h, 0n, r3, r2, r1, bd}))),
        bind_take_bal(2n, Game.bind_take(1n, Game.take_slot(0n, Game.Pending{h, 0n, r3, r2, r1, bd})),
          bind_take_bal(1n, Game.take_slot(0n, Game.Pending{h, 0n, r3, r2, r1, bd}),
            take_slot_bal(0n, Game.Pending{h, 0n, r3, r2, r1, bd}, w))))

def place_done_bal(m: Maybe<Game.Half>, e: Nat, p: Game.Pending, w: OkM(e, m)) -> OkP(Game.place_slot_done(m, e, p)):
  match m:
    case None{}:
      Unit{}
    case Some{h}:
      match p:
        case Game.Pending{_, n, r3, r2, r1, bd}:
          w

def place_dest_absent(p: Game.Pending, w: PBal(p)) -> OkP(Game.place_slot_dest(Game.Absent{}, p)):
  match p:
    case Game.Pending{h, n, r3, r2, r1, bd}:
      w

def place_dest_move(+d: Game.Dest, p: Game.Pending, w: PBal(p)) -> OkP(Game.place_slot_dest.go(True{}, d, p)):
  match p:
    case Game.Pending{+h, +n, r3, r2, r1, bd}:
      match n:
        case 0n:
          Unit{}
        case 1n+e:
          place_done_bal(Game.put(d, h), e, Game.Pending{h, n, r3, r2, r1, bd}, put_bal_e(e, d, h, w))

def place_dest_bal(d: Game.Dest, p: Game.Pending, w: PBal(p)) -> OkP(Game.place_slot_dest(d, p)):
  match d:
    case Game.Absent{}:
      place_dest_absent(p, w)
    case Game.Out{}:
      place_dest_move(d, p, w)
    case Game.Run{}:
      place_dest_move(d, p, w)
    case Game.To1{}:
      place_dest_move(d, p, w)
    case Game.To2{}:
      place_dest_move(d, p, w)
    case Game.To3{}:
      place_dest_move(d, p, w)

def place_slot_bal(+k: Nat, +p: Game.Pending, w: PBal(p)) -> OkP(Game.place_slot(k, p)):
  match p:
    case Game.Pending{+h, +n, r3, r2, r1, bd}:
      +q = {Game.Pending{h, n, r3, r2, r1, bd} : Game.Pending}
      place_dest_bal(Game.p_dest(k, q), q, w)

def bind_place_bal(+k: Nat, m: Maybe<&2, Game.Pending>, w: OkP(m)) -> OkP(Game.bind_place(k, m)):
  match m:
    case None{}:
      Unit{}
    case Some{p}:
      place_slot_bal(k, p, w)

def finish_bal(m: Maybe<&2, Game.Pending>, w: OkP(m)) -> OkM(0n, Game.finish(m)):
  match m:
    case None{}:
      Unit{}
    case Some{p}:
      match p:
        case Game.Pending{h, n, r3, r2, r1, bd}:
          match n:
            case 0n:
              w
            case 1n+e:
              Unit{}

def put_all_bal(+m: Maybe<&2, Game.Pending>, w: OkP(m)) -> OkM(0n, Game.put_all(m)):
  finish_bal(Game.bind_place(3n, Game.bind_place(2n, Game.bind_place(1n, Game.bind_place(0n, m)))),
    bind_place_bal(3n, Game.bind_place(2n, Game.bind_place(1n, Game.bind_place(0n, m))),
      bind_place_bal(2n, Game.bind_place(1n, Game.bind_place(0n, m)),
        bind_place_bal(1n, Game.bind_place(0n, m), bind_place_bal(0n, m, w)))))

def slots_bal(+p: Game.Play, +h: Game.Half, w: HBal(0n, h)) -> OkM(0n, Game.slots(p, h)):
  put_all_bal(Game.take_all(p, h), take_all_bal(p, h, w))

# The whole state: both teams balance (the side in the field has no one on base).
def SBal(+s: Game.State) -> Type:
  {Game.away_supply(s) == Game.away_demand(s) : Nat} & {Game.home_supply(s) == Game.home_demand(s) : Nat}

def lob_move(+c: Nat, l: Game.Line, w: {Game.line_bat(l) == Nat.add(c, Game.line_demand(l)) : Nat})
  -> {Game.line_bat(Game.add_lob(l, c)) == Game.line_demand(Game.add_lob(l, c)) : Nat}:
  match l:
    case Game.Line{+bat, +runs, +lo, +lob}:
      %add_swap(c, lo, lob) : {bat == Nat.add(runs, _) : Nat}
      %add_swap(c, runs, Nat.add(lo, lob)) : {bat == _ : Nat}
      w

def close_top(o: Nat, -inn: Nat, -so: Nat, -sb: Game.Bases, -away: Game.Line, -home: Game.Line, -rej: Nat, +bs: Game.Bases, +l: Game.Line,
  wm: HBal(0n, Game.Half{bs, l, o}), wa: {Game.line_bat(away) == Nat.add(Game.count(sb), Game.line_demand(away)) : Nat}, wh: {Game.line_bat(home) == Game.line_demand(home) : Nat})
  -> SBal(Game.close(o, Game.State{inn, True{}, so, sb, away, home, rej}, bs, l)):
  match o:
    case 0n:
      (wm, wh)
    case 1n+o1:
      match o1:
        case 0n:
          (wm, wh)
        case 1n+o2:
          match o2:
            case 0n:
              (wm, wh)
            case 1n+o3:
              match o3:
                case 0n:
                  (lob_move(Game.count(bs), l, wm), wh)
                case 1n+o4:
                  (wa, wh)

def close_bot(o: Nat, -inn: Nat, -so: Nat, -sb: Game.Bases, -away: Game.Line, -home: Game.Line, -rej: Nat, +bs: Game.Bases, +l: Game.Line,
  wm: HBal(0n, Game.Half{bs, l, o}), wa: {Game.line_bat(away) == Game.line_demand(away) : Nat}, wh: {Game.line_bat(home) == Nat.add(Game.count(sb), Game.line_demand(home)) : Nat})
  -> SBal(Game.close(o, Game.State{inn, False{}, so, sb, away, home, rej}, bs, l)):
  match o:
    case 0n:
      (wa, wm)
    case 1n+o1:
      match o1:
        case 0n:
          (wa, wm)
        case 1n+o2:
          match o2:
            case 0n:
              (wa, wm)
            case 1n+o3:
              match o3:
                case 0n:
                  (wa, lob_move(Game.count(bs), l, wm))
                case 1n+o4:
                  (wa, wh)

def after_top(m: Maybe<Game.Half>, -inn: Nat, -so: Nat, -sb: Game.Bases, -away: Game.Line, -home: Game.Line, -rej: Nat,
  wm: OkM(0n, m), wa: {Game.line_bat(away) == Nat.add(Game.count(sb), Game.line_demand(away)) : Nat}, wh: {Game.line_bat(home) == Game.line_demand(home) : Nat})
  -> SBal(Game.after(Game.State{inn, True{}, so, sb, away, home, rej}, m)):
  match m:
    case None{}:
      (wa, wh)
    case Some{h}:
      match h:
        case Game.Half{bs, l, o}:
          close_top(o, inn, so, sb, away, home, rej, bs, l, wm, wa, wh)

def after_bot(m: Maybe<Game.Half>, -inn: Nat, -so: Nat, -sb: Game.Bases, -away: Game.Line, -home: Game.Line, -rej: Nat,
  wm: OkM(0n, m), wa: {Game.line_bat(away) == Game.line_demand(away) : Nat}, wh: {Game.line_bat(home) == Nat.add(Game.count(sb), Game.line_demand(home)) : Nat})
  -> SBal(Game.after(Game.State{inn, False{}, so, sb, away, home, rej}, m)):
  match m:
    case None{}:
      (wa, wh)
    case Some{h}:
      match h:
        case Game.Half{bs, l, o}:
          close_bot(o, inn, so, sb, away, home, rej, bs, l, wm, wa, wh)

def step_bal(s: Game.State, +p: Game.Play, w: SBal(s)) -> SBal(Game.step(s, p)):
  match s:
    case Game.State{+inn, top, +so, +sb, +away, +home, +rej}:
      match top:
        case True{}:
          (+wa, wh) = w
          after_top(Game.slots(p, Game.Half{sb, away, so}), inn, so, sb, away, home, rej,
            slots_bal(p, Game.Half{sb, away, so}, wa), wa, wh)
        case False{}:
          (wa, +wh) = w
          after_bot(Game.slots(p, Game.Half{sb, home, so}), inn, so, sb, away, home, rej,
            slots_bal(p, Game.Half{sb, home, so}, wh), wa, wh)

def run_bal(ps: List<&2, Game.Play>, +s: Game.State, w: SBal(s)) -> SBal(Game.run(ps, s)):
  match ps:
    case Nil{}:
      w
    case Con{+p, rest}:
      run_bal(rest, Game.step(s, p), step_bal(s, p, w))

def start_bal() -> SBal(Game.start()):
  ({==}, {==})

def bal_away(-s: Game.State, w: SBal(s)) -> {Game.away_supply(s) == Game.away_demand(s) : Nat}:
  (a, h) = w
  a

def bal_home(-s: Game.State, w: SBal(s)) -> {Game.home_supply(s) == Game.home_demand(s) : Nat}:
  (a, h) = w
  h

def Laws.box_balances_away(ps):
  bal_away(Game.run(ps, Game.start()), run_bal(ps, Game.start(), start_bal()))

def Laws.box_balances_home(ps):
  bal_home(Game.run(ps, Game.start()), run_bal(ps, Game.start(), start_bal()))
