// Command compare checks bin/re24's RE table against published values: a
// state passes when runs/n is within 0.01 runs of the reference, tested
// exactly in integers at the reference's own precision.
package main

import (
	"encoding/csv"
	"flag"
	"fmt"
	"math/big"
	"os"
	"strconv"
	"strings"

	"github.com/harlanljones/bend-re24/internal/bendout"
)

// ref is one reference value, value = v / 10^k exactly.
type ref struct {
	state  bendout.State
	v, k   int64
	text   string
	source string
}

func pow10(k int64) int64 {
	p := int64(1)
	for range k {
		p *= 10
	}
	return p
}

// decimal reads "1.40" as v = 140, k = 2.
func decimal(s string) (v, k int64, err error) {
	whole, frac, _ := strings.Cut(s, ".")
	v, err = strconv.ParseInt(whole+frac, 10, 64)
	if err != nil || v < 0 {
		return 0, 0, fmt.Errorf("bad value %q", s)
	}
	return v, int64(len(frac)), nil
}

func readRefs(path string) ([]ref, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	rows, err := csv.NewReader(f).ReadAll()
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 || strings.Join(rows[0], ",") != "bases,outs,value,source" {
		return nil, fmt.Errorf("%s: want header bases,outs,value,source", path)
	}
	var refs []ref
	for i, row := range rows[1:] {
		b, errB := strconv.Atoi(row[0])
		o, errO := strconv.Atoi(row[1])
		v, k, errV := decimal(row[2])
		if errB != nil || errO != nil || errV != nil {
			return nil, fmt.Errorf("%s: row %d: bad state or value", path, i+2)
		}
		refs = append(refs, ref{bendout.State{Bases: b, Outs: o}, v, k, row[2], row[3]})
	}
	return refs, nil
}

func main() {
	runPath := flag.String("run", "", "bin/re24 run output")
	refPath := flag.String("ref", "", "reference CSV (bases,outs,value,source)")
	flag.Parse()
	if *runPath == "" || *refPath == "" {
		fmt.Fprintln(os.Stderr, "usage: compare -run <run.txt> -ref <reference.csv>")
		os.Exit(2)
	}
	ok, err := compare(*runPath, *refPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "compare:", err)
		os.Exit(1)
	}
	if !ok {
		os.Exit(1)
	}
}

func compare(runPath, refPath string) (bool, error) {
	f, err := os.Open(runPath)
	if err != nil {
		return false, err
	}
	defer f.Close()
	out, err := bendout.Parse(f)
	if err != nil {
		return false, err
	}
	refs, err := readRefs(refPath)
	if err != nil {
		return false, err
	}
	pass := 0
	worst, worstAt := new(big.Rat), bendout.State{}
	for _, r := range refs {
		re, found := out.REAt(r.state)
		if !found || re.N == 0 {
			return false, fmt.Errorf("state %d/%d has no visits", r.state.Bases, r.state.Outs)
		}
		scale := pow10(r.k)
		// |runs/n - v/10^k| <= 1/100  <=>  |runs·10^k - v·n| <= (10^k/100)·n
		d := re.Runs*scale - r.v*re.N
		within := max(d, -d) <= scale/100*re.N
		bend := big.NewRat(re.Runs, re.N)
		diff := new(big.Rat).Sub(bend, big.NewRat(r.v, scale))
		verdict := "FAIL"
		if within {
			verdict = "ok"
			pass++
		}
		fmt.Printf("%d %d %s %s %s %s\n", r.state.Bases, r.state.Outs, bend.FloatString(4), r.text, diff.FloatString(4), verdict)
		if abs := new(big.Rat).Abs(diff); abs.Cmp(worst) > 0 {
			worst, worstAt = abs, r.state
		}
	}
	fmt.Printf("compare: %d/%d within 0.01 runs; worst %s at %d/%d\n", pass, len(refs), worst.FloatString(4), worstAt.Bases, worstAt.Outs)
	return pass == len(refs), nil
}
