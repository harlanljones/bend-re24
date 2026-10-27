// Package bendout parses the line records bin/re24 prints. Every number is
// an exact integer: RE in thousandths (RE lines) or in 10^-7 runs (CI and
// DRE lines), break-evens in basis points. NA fields parse to nil.
package bendout

import (
	"bufio"
	"fmt"
	"io"
	"strconv"
	"strings"
)

// State is a base-out state: bases as Chadwick's bitmask (1 first, 2 second,
// 4 third), outs 0-2; the end of a half-inning is bases 0, outs 3.
type State struct{ Bases, Outs int }

type Games struct{ Seen, Good, Bad int }

type Halves struct{ Complete, Partial int }

type BadGame struct {
	Game, At int
	Why      string
}

// RE is one state's direct count: Runs to the end of the half over N visits,
// and Milli = round(1000·Runs/N), nil when N is 0.
type RE struct {
	State
	Runs, N int64
	Milli   *int64
}

// Transition is one cell of the transition table.
type Transition struct {
	From, To State
	Runs     int
	Count    int64
}

// BreakEven is a decision's break-even success rate in basis points.
type BreakEven struct {
	Kind string
	State
	BP *int64
}

// DeltaRE is a decision's change in run value, in 10^-7 runs; nil when a
// state it needs was never visited.
type DeltaRE struct {
	Kind string
	State
	Value *int64
}

type Boot struct {
	B     int
	Seed  uint32
	Games int
}

// CI is a 95% bootstrap interval. Stat is RE, BE or DRE; Kind is empty for RE.
type CI struct {
	Stat, Kind string
	State
	Lo, Hi *int64
}

type Output struct {
	Games       Games
	Halves      Halves
	Plays       int64
	BadGames    []BadGame
	RE          []RE
	Transitions []Transition
	BreakEvens  []BreakEven
	DeltaREs    []DeltaRE
	Boot        Boot
	CIs         []CI
}

// REAt returns the RE line for a state.
func (o *Output) REAt(s State) (RE, bool) {
	for _, r := range o.RE {
		if r.State == s {
			return r, true
		}
	}
	return RE{}, false
}

// CIAt returns the interval for a statistic, decision kind and state.
func (o *Output) CIAt(stat, kind string, s State) (CI, bool) {
	for _, c := range o.CIs {
		if c.Stat == stat && c.Kind == kind && c.State == s {
			return c, true
		}
	}
	return CI{}, false
}

// Parse reads every record; an unknown or malformed line is an error naming
// its 1-based line number.
func Parse(r io.Reader) (*Output, error) {
	out := &Output{}
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 64*1024), 1024*1024)
	for n := 1; sc.Scan(); n++ {
		line := sc.Text()
		if line == "" {
			continue
		}
		if err := out.add(strings.Fields(line)); err != nil {
			return nil, fmt.Errorf("bendout: line %d: %v: %q", n, err, line)
		}
	}
	if err := sc.Err(); err != nil {
		return nil, fmt.Errorf("bendout: %w", err)
	}
	return out, nil
}

// fields reads typed fields in order, keeping the first error.
type fields struct {
	f   []string
	i   int
	err error
}

func (p *fields) next() string {
	if p.i >= len(p.f) {
		if p.err == nil {
			p.err = fmt.Errorf("short record")
		}
		return ""
	}
	p.i++
	return p.f[p.i-1]
}

func (p *fields) int64() int64 {
	s := p.next()
	v, err := strconv.ParseInt(s, 10, 64)
	if err != nil && p.err == nil {
		p.err = fmt.Errorf("bad integer %q", s)
	}
	return v
}

func (p *fields) int() int { return int(p.int64()) }

// opt reads an integer or NA.
func (p *fields) opt() *int64 {
	if p.i < len(p.f) && p.f[p.i] == "NA" {
		p.i++
		return nil
	}
	v := p.int64()
	return &v
}

func (p *fields) state() State { return State{Bases: p.int(), Outs: p.int()} }

func (p *fields) done() error {
	if p.err == nil && p.i != len(p.f) {
		p.err = fmt.Errorf("extra fields")
	}
	return p.err
}

func (o *Output) add(f []string) error {
	p := &fields{f: f, i: 1}
	switch f[0] {
	case "GAMES":
		o.Games = Games{Seen: p.int(), Good: p.int(), Bad: p.int()}
	case "HALVES":
		o.Halves = Halves{Complete: p.int(), Partial: p.int()}
	case "PLAYS":
		o.Plays = p.int64()
	case "BADGAME":
		o.BadGames = append(o.BadGames, BadGame{Game: p.int(), At: p.int(), Why: p.next()})
	case "RE":
		o.RE = append(o.RE, RE{State: p.state(), Runs: p.int64(), N: p.int64(), Milli: p.opt()})
	case "T":
		o.Transitions = append(o.Transitions, Transition{From: p.state(), To: p.state(), Runs: p.int(), Count: p.int64()})
	case "BE":
		o.BreakEvens = append(o.BreakEvens, BreakEven{Kind: p.next(), State: p.state(), BP: p.opt()})
	case "DRE":
		o.DeltaREs = append(o.DeltaREs, DeltaRE{Kind: p.next(), State: p.state(), Value: p.opt()})
	case "BOOT":
		b, seed, g := p.int(), p.int64(), p.int()
		if p.err == nil && (seed < 0 || seed > 1<<32-1) {
			p.err = fmt.Errorf("bad seed %d", seed)
		}
		o.Boot = Boot{B: b, Seed: uint32(seed), Games: g}
	case "CI":
		c := CI{Stat: p.next()}
		switch c.Stat {
		case "RE":
		case "BE", "DRE":
			c.Kind = p.next()
		default:
			if p.err == nil {
				p.err = fmt.Errorf("unknown CI statistic %q", c.Stat)
			}
		}
		c.State, c.Lo, c.Hi = p.state(), p.opt(), p.opt()
		o.CIs = append(o.CIs, c)
	default:
		return fmt.Errorf("unknown record %q", f[0])
	}
	return p.done()
}
