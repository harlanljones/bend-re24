package main

import (
	"bytes"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/harlanljones/bend-re24/internal/bendout"
)

func writeTemp(t *testing.T, dir, name, body string) string {
	t.Helper()
	p := filepath.Join(dir, name)
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestCompareFixture(t *testing.T) {
	ok, err := compare("testdata/run.txt", "testdata/ref.csv")
	if err != nil {
		t.Fatal(err)
	}
	if !ok {
		t.Fatal("fixture compare failed")
	}
}

func TestCompareBoundary(t *testing.T) {
	// |runs/n - v| <= 0.01 is tested in integers. 1/100 is on the boundary
	// and passes; 2/100 against 0.00 does not.
	dir := t.TempDir()
	run := writeTemp(t, dir, "run.txt", "RE 0 0 1 100 10\nRE 1 0 2 100 20\n")
	ref := writeTemp(t, dir, "ref.csv", "bases,outs,value,source\n0,0,0.00,edge\n")
	ok, err := compare(run, ref)
	if err != nil || !ok {
		t.Fatalf("boundary 0.01: ok=%v err=%v", ok, err)
	}
	ref = writeTemp(t, dir, "ref2.csv", "bases,outs,value,source\n1,0,0.00,edge\n")
	ok, err = compare(run, ref)
	if err != nil {
		t.Fatal(err)
	}
	if ok {
		t.Fatal("0.02 from 0.00 was accepted")
	}
}

func TestCompareErrors(t *testing.T) {
	dir := t.TempDir()
	run := writeTemp(t, dir, "run.txt", "RE 0 0 0 0 NA\n")
	ref := writeTemp(t, dir, "ref.csv", "bases,outs,value,source\n0,0,0.50,x\n")
	if _, err := compare(run, ref); err == nil || !strings.Contains(err.Error(), "no visits") {
		t.Fatalf("zero visits: %v", err)
	}
	run = writeTemp(t, dir, "run2.txt", "RE 0 0 1 2 500\n")
	ref = writeTemp(t, dir, "ref2.csv", "bases,outs,value,source\n1,0,0.50,x\n")
	if _, err := compare(run, ref); err == nil || !strings.Contains(err.Error(), "no visits") {
		t.Fatalf("missing state: %v", err)
	}
	ref = writeTemp(t, dir, "bad.csv", "bases,outs,re,source\n0,0,0.50,x\n")
	if _, err := readRefs(ref); err == nil || !strings.Contains(err.Error(), "want header") {
		t.Fatalf("bad header: %v", err)
	}
	ref = writeTemp(t, dir, "bad2.csv", "bases,outs,value,source\nno,0,0.50,x\n")
	if _, err := readRefs(ref); err == nil {
		t.Fatal("bad state was accepted")
	}
}

func TestDecimal(t *testing.T) {
	v, k, err := decimal("1.491")
	if err != nil || v != 1491 || k != 3 {
		t.Fatalf("decimal = %d %d %v", v, k, err)
	}
	if _, _, err := decimal("x"); err == nil {
		t.Fatal("accepted a non-number")
	}
}

func TestFanGraphs2023Shape(t *testing.T) {
	refs, err := readRefs(filepath.Join("..", "fixtures", "reference", "fangraphs-2023-re24.csv"))
	if err != nil {
		t.Fatal(err)
	}
	if len(refs) != 24 {
		t.Fatalf("2023 reference has %d rows, want 24", len(refs))
	}
	// Clemens prints two cells as "1" and "1.5". They are stored at the same
	// two-decimal width as the rest of his table, and as 2024's "0.1".
	var one, oneFive bool
	for _, r := range refs {
		if r.state == (bendout.State{Bases: 4, Outs: 1}) && r.text == "1.00" {
			one = true
		}
		if r.state == (bendout.State{Bases: 3, Outs: 0}) && r.text == "1.50" {
			oneFive = true
		}
	}
	if !one || !oneFive {
		t.Fatalf("normalized cells: 1.00=%v 1.50=%v", one, oneFive)
	}
}

func TestFanGraphs2024Shape(t *testing.T) {
	refs, err := readRefs(filepath.Join("..", "fixtures", "reference", "fangraphs-2024-re24.csv"))
	if err != nil {
		t.Fatal(err)
	}
	if len(refs) != 26 {
		t.Fatalf("2024 reference has %d rows, want 26", len(refs))
	}
	var three int
	for _, r := range refs {
		if r.k == 3 {
			three++
		}
	}
	if three != 2 {
		t.Fatalf("3-decimal checkpoints = %d, want 2", three)
	}
}

func TestComparePrintsSummary(t *testing.T) {
	old := os.Stdout
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	os.Stdout = w
	ok, cmpErr := compare("testdata/run.txt", "testdata/ref.csv")
	w.Close()
	os.Stdout = old
	var buf bytes.Buffer
	io.Copy(&buf, r)
	if cmpErr != nil || !ok {
		t.Fatalf("compare: ok=%v err=%v", ok, cmpErr)
	}
	if !strings.Contains(buf.String(), "compare: 2/2 within 0.01 runs") {
		t.Fatalf("summary = %q", buf.String())
	}
}
