# The bootstrap on the GPU: `re24-gpu boot <plays.csv> <seed>` prints what
# `re24 boot` prints, with the sample tree handed to the GPU by `!`.
import Base
import ./src/cli.bend as Cli
import ./src/bootstrap.bend as Boot

def run.gpu(c: Boot.Cfg) -> List<&2, Boot.Sample>:
  Boot.tree!(Boot.log_size(), 0n, c)

def usage() -> IO(Unit):
  do IO<Unit>:
    IO.print_err("usage: re24-gpu boot <plays.csv> <seed>")
    IO.exit(2)

def route(args: List<String>, is_boot: Bool) -> IO(Unit):
  match is_boot:
    case True{}:
      Cli.boot(~run.gpu, args)
    case False{}:
      usage()

def dispatch(args: List<String>) -> IO(Unit):
  match args:
    case Con{prog, Con{+cmd, rest}}:
      route(rest, String.eq(cmd, "boot"))
    case _:
      usage()

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    dispatch(args)
