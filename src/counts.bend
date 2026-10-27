import Base
import ./state.bend as Game
import ./spec.bend as Spec

def cell_is(cs: List<&2, Spec.Cell>, +to: Nat, +r: Nat) -> Bool:
  match cs:
    case Nil{}:
      False{}
    case Con{Spec.Cell{t, x, _}, _}:
      Nat.is_eq(t, to) && Nat.is_eq(x, r)

# Add one play to a row's cells; `hit` says whether the first cell is (to, r).
def bump(cs: List<&2, Spec.Cell>, hit: Bool, +to: Nat, +r: Nat) -> List<&2, Spec.Cell>:
  match cs hit:
    case Nil{} _:
      [Spec.Cell{to, r, 1n}]
    case Con{Spec.Cell{t, x, n}, rest} True{}:
      Spec.Cell{t, x, 1n+n} <> rest
    case Con{c, +rest} False{}:
      c <> bump(rest, cell_is(rest, to, r), to, r)

def row_is(t: List<&2, Spec.Row>, +f: Nat) -> Bool:
  match t:
    case Nil{}:
      False{}
    case Con{Spec.Row{g, _}, _}:
      Nat.is_eq(g, f)

# Add one observation; `hit` says whether the first row is its `from`.
def add(t: List<&2, Spec.Row>, hit: Bool, o: Spec.Obs) -> List<&2, Spec.Row>:
  match t hit:
    case Nil{} _:
      match o:
        case Spec.Obs{f, to, r}:
          [Spec.Row{f, [Spec.Cell{to, r, 1n}]}]
    case Con{Spec.Row{g, +cs}, rest} True{}:
      match o:
        case Spec.Obs{_, +to, +r}:
          Spec.Row{g, bump(cs, cell_is(cs, to, r), to, r)} <> rest
    case Con{w, +rest} False{}:
      match o:
        case Spec.Obs{+f, to, r}:
          w <> add(rest, row_is(rest, f), Spec.Obs{f, to, r})

def from_of(o: Spec.Obs) -> Nat:
  match o:
    case Spec.Obs{f, _, _}:
      f

def tally(os: List<&2, Spec.Obs>) -> List<&2, Spec.Row>:
  match os:
    case Nil{}:
      Nil{}
    case Con{+o, t}:
      +tt = tally(t)
      add(tt, row_is(tt, from_of(o)), o)
