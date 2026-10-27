package main

import (
	"fmt"
	"math/big"
	"strconv"

	"github.com/harlanljones/bend-re24/internal/bendout"
)

// Exact decimal rendering. RE lines carry runs and visits; CI RE and DRE
// values are 10^-7 runs; break-evens are basis points.

func ratio(num, den int64, places int) string {
	if den == 0 {
		return "NA"
	}
	return big.NewRat(num, den).FloatString(places)
}

func runs7(v int64) string { return ratio(v, 10_000_000, 4) }

func pct(bp int64) string { return ratio(bp, 100, 2) }

func opt(p *int64, f func(int64) string) string {
	if p == nil {
		return "NA"
	}
	return f(*p)
}

func parseRat(s string) (*big.Rat, bool) {
	return new(big.Rat).SetString(s)
}

// interval renders a CI as "[lo, hi]", or "—" when there is no CI line.
func interval(c bendout.CI, ok bool, f func(int64) string, unit string) string {
	if !ok {
		return "—"
	}
	return "[" + opt(c.Lo, f) + unit + ", " + opt(c.Hi, f) + unit + "]"
}

var baseNames = [8]string{"empty", "1B", "2B", "1B+2B", "3B", "1B+3B", "2B+3B", "loaded"}

// baseOrder lists base codes in the usual RE24 table order.
var baseOrder = [8]int{0, 1, 2, 4, 3, 5, 6, 7}

func baseName(b int) string {
	if b < 0 || b >= len(baseNames) {
		return strconv.Itoa(b)
	}
	return baseNames[b]
}

func outsName(o int) string {
	if o == 1 {
		return "1 out"
	}
	return strconv.Itoa(o) + " outs"
}

func stateName(s bendout.State) string {
	if s.Outs == 3 {
		return "end of half"
	}
	return baseName(s.Bases) + ", " + outsName(s.Outs)
}

var kindTitles = map[string]string{
	"steal2": "Steal of second",
	"steal3": "Steal of third",
	"bunt":   "Sacrifice bunt",
	"ibb":    "Intentional walk",
}

var beKinds = []string{"steal2", "steal3", "bunt"}

var dreKinds = []string{"bunt", "ibb"}

// Page view.

type summaryView struct {
	Seen, Good, Bad, Plays, Halves, Partial string
	BadGames                                []string
	Boot                                    string
}

type cellView struct {
	Label, URL, RE, Frac, CI string
}

type gridRow struct {
	Name  string
	Cells []cellView
}

type litView struct {
	Text, Season, URL string
}

type beRow struct {
	State, Outs, Value, CI string
	Never                  bool
	Lit                    []litView
}

type dreRow struct {
	State, Outs, Value, CI string
}

type kindTable[R any] struct {
	Kind, Title string
	Rows        []R
}

type pageView struct {
	Summary summaryView
	Grid    []gridRow
	BE      []kindTable[beRow]
	DRE     []kindTable[dreRow]
	Chart   chartView
	HasBoot bool
	Notice  string
}

func (d data) litFor(kind string, s bendout.State) []litView {
	var out []litView
	for _, l := range d.lit {
		if l.Kind != kind || l.State != s {
			continue
		}
		text := l.Low + "%"
		if l.Low != l.High {
			text = l.Low + "–" + l.High + "%"
		}
		out = append(out, litView{text, l.Season, l.Source})
	}
	return out
}

func (d data) pageView() pageView {
	r := d.run
	v := pageView{
		Summary: summaryView{
			Seen:    strconv.Itoa(r.Games.Seen),
			Good:    strconv.Itoa(r.Games.Good),
			Bad:     strconv.Itoa(r.Games.Bad),
			Plays:   strconv.FormatInt(r.Plays, 10),
			Halves:  strconv.Itoa(r.Halves.Complete),
			Partial: strconv.Itoa(r.Halves.Partial),
		},
		HasBoot: len(d.boot.CIs) > 0,
		Notice:  notice,
	}
	for _, g := range r.BadGames {
		v.Summary.BadGames = append(v.Summary.BadGames, fmt.Sprintf("game %d, record %d: %s", g.Game, g.At, g.Why))
	}
	if b := d.boot.Boot; b.B > 0 {
		v.Summary.Boot = fmt.Sprintf("%d resamples of %d games, seed %d", b.B, b.Games, b.Seed)
	}
	for _, b := range baseOrder {
		row := gridRow{Name: baseName(b)}
		for o := range 3 {
			s := bendout.State{Bases: b, Outs: o}
			c := cellView{
				Label: stateName(s),
				URL:   fmt.Sprintf("/state?b=%d&o=%d", b, o),
				RE:    "NA",
				Frac:  "—",
			}
			if re, ok := r.REAt(s); ok {
				c.RE = ratio(re.Runs, re.N, 4)
				c.Frac = fmt.Sprintf("%d/%d", re.Runs, re.N)
			}
			ci, ok := d.boot.CIAt("RE", "", s)
			c.CI = interval(ci, ok, runs7, "")
			row.Cells = append(row.Cells, c)
		}
		v.Grid = append(v.Grid, row)
	}
	for _, k := range beKinds {
		t := kindTable[beRow]{Kind: k, Title: kindTitles[k]}
		for _, be := range r.BreakEvens {
			if be.Kind != k {
				continue
			}
			ci, ok := d.boot.CIAt("BE", k, be.State)
			t.Rows = append(t.Rows, beRow{
				State: baseName(be.Bases),
				Outs:  strconv.Itoa(be.Outs),
				Value: opt(be.BP, func(bp int64) string { return pct(bp) + "%" }),
				CI:    interval(ci, ok, pct, "%"),
				Never: be.BP != nil && *be.BP >= 10000,
				Lit:   d.litFor(k, be.State),
			})
		}
		v.BE = append(v.BE, t)
	}
	for _, k := range dreKinds {
		t := kindTable[dreRow]{Kind: k, Title: kindTitles[k]}
		for _, x := range r.DeltaREs {
			if x.Kind != k {
				continue
			}
			ci, ok := d.boot.CIAt("DRE", k, x.State)
			t.Rows = append(t.Rows, dreRow{
				State: baseName(x.Bases),
				Outs:  strconv.Itoa(x.Outs),
				Value: opt(x.Value, runs7),
				CI:    interval(ci, ok, runs7, ""),
			})
		}
		v.DRE = append(v.DRE, t)
	}
	v.Chart = d.chart()
	return v
}

// State panel.

type transRow struct {
	To, Runs, Count, Share string
}

type stateView struct {
	Name, RE, Frac, CI string
	Rows               []transRow
	Total              string
}

func (d data) stateView(s bendout.State) stateView {
	v := stateView{Name: stateName(s), RE: "NA", Frac: "—"}
	if re, ok := d.run.REAt(s); ok {
		v.RE = ratio(re.Runs, re.N, 4)
		v.Frac = fmt.Sprintf("%d/%d", re.Runs, re.N)
	}
	ci, ok := d.boot.CIAt("RE", "", s)
	v.CI = interval(ci, ok, runs7, "")
	var total int64
	for _, t := range d.run.Transitions {
		if t.From == s {
			total += t.Count
		}
	}
	for _, t := range d.run.Transitions {
		if t.From != s {
			continue
		}
		v.Rows = append(v.Rows, transRow{
			To:    stateName(t.To),
			Runs:  strconv.Itoa(t.Runs),
			Count: strconv.FormatInt(t.Count, 10),
			Share: ratio(100*t.Count, total, 2) + "%",
		})
	}
	v.Total = strconv.FormatInt(total, 10)
	return v
}

// Break-even chart: one horizontal bar per steal/bunt entry on a 0–100%
// axis, CI whiskers, and literature markers. Coordinates are exact
// rationals rendered to one decimal.

const (
	chartLabelW = 190
	chartPlotW  = 480
	chartTop    = 28
	chartRowH   = 24
	chartTailW  = 150
)

type tick struct{ X, Label string }

type whisker struct {
	X1, X2, Y, CapY1, CapY2 string
	CapLo, CapHi            bool
}

type litMark struct {
	X1, X2, Y, Transform, Title string
	Point                       bool
}

type chartBar struct {
	Label, LabelY, BarY, W, ValueX, ValueY, Value string
	HasBar, Never                                 bool
	Whisker                                       *whisker
	Lits                                          []litMark
}

type chartView struct {
	ViewBox, Width, Height, X0, X1, GridY1, GridY2, LegendY string
	Ticks                                                   []tick
	Bars                                                    []chartBar
}

func num(r *big.Rat) string { return r.FloatString(1) }

func intStr(n int) string { return strconv.Itoa(n) }

// xAt maps basis points to a chart x, clamped to the 0–100% axis.
func xAt(bp *big.Rat) (string, bool) {
	clamped := false
	if bp.Sign() < 0 {
		bp, clamped = new(big.Rat), true
	} else if bp.Cmp(big.NewRat(10000, 1)) > 0 {
		bp, clamped = big.NewRat(10000, 1), true
	}
	x := new(big.Rat).Mul(bp, big.NewRat(chartPlotW, 10000))
	return num(x.Add(x, big.NewRat(chartLabelW, 1))), clamped
}

func xBP(bp int64) (string, bool) { return xAt(big.NewRat(bp, 1)) }

func (d data) chart() chartView {
	var bes []bendout.BreakEven
	for _, k := range beKinds {
		for _, be := range d.run.BreakEvens {
			if be.Kind == k {
				bes = append(bes, be)
			}
		}
	}
	bottom := chartTop + len(bes)*chartRowH
	height := bottom + 40
	width := chartLabelW + chartPlotW + chartTailW
	c := chartView{
		ViewBox: fmt.Sprintf("0 0 %d %d", width, height),
		Width:   intStr(width),
		Height:  intStr(height),
		X0:      intStr(chartLabelW),
		X1:      intStr(chartLabelW + chartPlotW),
		GridY1:  intStr(chartTop - 4),
		GridY2:  intStr(bottom),
		LegendY: intStr(bottom + 24),
	}
	for p := int64(0); p <= 100; p += 25 {
		x, _ := xBP(p * 100)
		c.Ticks = append(c.Ticks, tick{x, strconv.FormatInt(p, 10) + "%"})
	}
	for i, be := range bes {
		top := chartTop + i*chartRowH
		b := chartBar{
			Label:  kindTitles[be.Kind] + ", " + baseName(be.Bases) + ", " + outsName(be.Outs),
			LabelY: intStr(top + 15),
			BarY:   intStr(top + 4),
			ValueY: intStr(top + 15),
			Value:  "NA",
		}
		if be.BP != nil {
			x, _ := xBP(*be.BP)
			w, _ := new(big.Rat).SetString(x)
			b.W = num(w.Sub(w, big.NewRat(chartLabelW, 1)))
			b.HasBar = true
			b.Never = *be.BP >= 10000
			b.Value = pct(*be.BP) + "%"
			if b.Never {
				b.Value += " never pays"
			}
		}
		b.ValueX = intStr(chartLabelW + chartPlotW + 8)
		if ci, ok := d.boot.CIAt("BE", be.Kind, be.State); ok && ci.Lo != nil && ci.Hi != nil {
			lo, clLo := xBP(*ci.Lo)
			hi, clHi := xBP(*ci.Hi)
			b.Whisker = &whisker{
				X1: lo, X2: hi, Y: intStr(top + 10),
				CapY1: intStr(top + 5), CapY2: intStr(top + 15),
				CapLo: !clLo, CapHi: !clHi,
			}
		}
		for _, l := range d.lit {
			if l.Kind != be.Kind || l.State != be.State {
				continue
			}
			lo, _ := parseRat(l.Low)
			hi, _ := parseRat(l.High)
			x1, _ := xAt(lo.Mul(lo, big.NewRat(100, 1)))
			x2, _ := xAt(hi.Mul(hi, big.NewRat(100, 1)))
			y := top + 20
			text := l.Low + "%"
			if l.Low != l.High {
				text = l.Low + "–" + l.High + "%"
			}
			b.Lits = append(b.Lits, litMark{
				X1: x1, X2: x2, Y: intStr(y),
				Transform: "translate(" + x1 + "," + intStr(y) + ")",
				Title:     "literature " + text + " (" + l.Season + ")",
				Point:     l.Low == l.High,
			})
		}
		c.Bars = append(c.Bars, b)
	}
	return c
}
