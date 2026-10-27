package main

import (
	"encoding/csv"
	"fmt"
	"os"
	"path/filepath"
	"strconv"

	"github.com/harlanljones/bend-re24/internal/bendout"
)

// exportCSV writes transitions, RE24 and decisions CSVs into dir. A value
// bin/re24 printed as NA is written NA; a field that does not apply, or a CI
// with no bootstrap line, is left empty.
func exportCSV(dir string, year int, run, boot *bendout.Output) error {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	name := func(stem string) string { return filepath.Join(dir, fmt.Sprintf("%s-%d.csv", stem, year)) }
	itoa := strconv.Itoa
	i64 := func(n int64) string { return strconv.FormatInt(n, 10) }

	trans := [][]string{{"from_bases", "from_outs", "to_bases", "to_outs", "runs", "count"}}
	for _, t := range run.Transitions {
		trans = append(trans, []string{itoa(t.From.Bases), itoa(t.From.Outs), itoa(t.To.Bases), itoa(t.To.Outs), itoa(t.Runs), i64(t.Count)})
	}

	re := [][]string{{"bases", "outs", "runs", "visits", "re", "ci_lo", "ci_hi"}}
	for _, r := range run.RE {
		lo, hi := ciFields(boot, "RE", "", r.State, runs7)
		re = append(re, []string{itoa(r.Bases), itoa(r.Outs), i64(r.Runs), i64(r.N), ratio(r.Runs, r.N, 4), lo, hi})
	}

	type key struct {
		kind  string
		state bendout.State
	}
	var order []key
	rows := map[key][]string{}
	row := func(k key) []string {
		if r, ok := rows[k]; ok {
			return r
		}
		order = append(order, k)
		r := []string{k.kind, itoa(k.state.Bases), itoa(k.state.Outs), "", "", "", "", "", ""}
		rows[k] = r
		return r
	}
	for _, be := range run.BreakEvens {
		r := row(key{be.Kind, be.State})
		r[3] = opt(be.BP, pct)
		r[4], r[5] = ciFields(boot, "BE", be.Kind, be.State, pct)
	}
	for _, x := range run.DeltaREs {
		r := row(key{x.Kind, x.State})
		r[6] = opt(x.Value, runs7)
		r[7], r[8] = ciFields(boot, "DRE", x.Kind, x.State, runs7)
	}
	dec := [][]string{{"kind", "bases", "outs", "breakeven_pct", "ci_lo", "ci_hi", "dre", "dre_lo", "dre_hi"}}
	for _, k := range order {
		dec = append(dec, rows[k])
	}

	for _, f := range []struct {
		path string
		rows [][]string
	}{{name("transitions"), trans}, {name("re24"), re}, {name("decisions"), dec}} {
		if err := writeCSV(f.path, f.rows); err != nil {
			return err
		}
	}
	return nil
}

func ciFields(boot *bendout.Output, stat, kind string, s bendout.State, f func(int64) string) (lo, hi string) {
	c, ok := boot.CIAt(stat, kind, s)
	if !ok {
		return "", ""
	}
	return opt(c.Lo, f), opt(c.Hi, f)
}

func writeCSV(path string, rows [][]string) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	w := csv.NewWriter(f)
	w.WriteAll(rows)
	if err := w.Error(); err != nil {
		f.Close()
		return fmt.Errorf("%s: %w", path, err)
	}
	return f.Close()
}
