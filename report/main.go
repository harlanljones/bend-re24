// Command report serves bin/re24's results as a templ + htmx page, or with
// -export writes them as CSV files and exits. Every printed decimal is an
// exact integer ratio rendered with math/big.Rat.
package main

import (
	"bytes"
	"embed"
	"encoding/csv"
	"errors"
	"flag"
	"fmt"
	"io/fs"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/a-h/templ"
	"github.com/harlanljones/bend-re24/internal/bendout"
)

//go:embed static
var static embed.FS

// notice is the Retrosheet notice, verbatim as in fixtures/NOTICE.
const notice = `The information used here was obtained free of charge from and is copyrighted by Retrosheet.  Interested parties may contact Retrosheet at "www.retrosheet.org".`

// litRow is one published break-even rate, low_pct..high_pct percent.
type litRow struct {
	Kind           string
	State          bendout.State
	Low, High      string
	Season, Source string
}

// data is everything the report shows. boot is never nil; it has no CI
// lines when no bootstrap output was loaded.
type data struct {
	run, boot *bendout.Output
	lit       []litRow
}

func main() {
	runPath := flag.String("run", "out/run-2024.txt", "bin/re24 run output")
	bootPath := flag.String("boot", "out/boot-2024.txt", "bin/re24 boot output; CIs are omitted when absent")
	refs := flag.String("refs", "fixtures/reference", "reference directory (breakeven-literature.csv)")
	addr := flag.String("addr", "127.0.0.1:8024", "listen address")
	export := flag.String("export", "", "write the CSV files to this directory and exit")
	year := flag.Int("year", 2024, "season in the exported file names")
	flag.Parse()
	if flag.NArg() != 0 {
		fmt.Fprintln(os.Stderr, "usage: report -run <run.txt> [-boot <boot.txt>] [-refs <dir>] [-addr <host:port>] [-export <dir>]")
		os.Exit(2)
	}
	if err := run(*runPath, *bootPath, *refs, *addr, *export, *year); err != nil {
		fmt.Fprintln(os.Stderr, "report:", err)
		os.Exit(1)
	}
}

func run(runPath, bootPath, refs, addr, export string, year int) error {
	out, err := parseFile(runPath)
	if err != nil {
		return err
	}
	boot, err := parseFile(bootPath)
	if errors.Is(err, fs.ErrNotExist) {
		fmt.Fprintf(os.Stderr, "report: no bootstrap output at %s; CIs omitted\n", bootPath)
		boot = &bendout.Output{}
	} else if err != nil {
		return err
	}
	if export != "" {
		return exportCSV(export, year, out, boot)
	}
	lit, err := readLiterature(filepath.Join(refs, "breakeven-literature.csv"))
	if err != nil {
		return err
	}
	log.Printf("report: serving http://%s", addr)
	return http.ListenAndServe(addr, newHandler(data{out, boot, lit}))
}

func parseFile(path string) (*bendout.Output, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	out, err := bendout.Parse(f)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	return out, nil
}

func readLiterature(path string) ([]litRow, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	rows, err := csv.NewReader(f).ReadAll()
	if err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	const header = "kind,bases,outs,low_pct,high_pct,season,source_url"
	if len(rows) == 0 || strings.Join(rows[0], ",") != header {
		return nil, fmt.Errorf("%s: want header %s", path, header)
	}
	var lit []litRow
	for i, row := range rows[1:] {
		b, errB := strconv.Atoi(row[1])
		o, errO := strconv.Atoi(row[2])
		_, okLo := parseRat(row[3])
		_, okHi := parseRat(row[4])
		if errB != nil || errO != nil || !okLo || !okHi {
			return nil, fmt.Errorf("%s: row %d: bad state or percent", path, i+2)
		}
		lit = append(lit, litRow{row[0], bendout.State{Bases: b, Outs: o}, row[3], row[4], row[5], row[6]})
	}
	return lit, nil
}

func newHandler(d data) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {
		render(w, r, page(d.pageView()))
	})
	mux.HandleFunc("GET /state", func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query()
		b, errB := strconv.Atoi(q.Get("b"))
		o, errO := strconv.Atoi(q.Get("o"))
		if errB != nil || errO != nil || b < 0 || b > 7 || o < 0 || o > 2 {
			http.Error(w, "bad state", http.StatusBadRequest)
			return
		}
		render(w, r, statePanel(d.stateView(bendout.State{Bases: b, Outs: o})))
	})
	mux.Handle("GET /static/", http.FileServerFS(static))
	return mux
}

func render(w http.ResponseWriter, r *http.Request, c templ.Component) {
	var buf bytes.Buffer
	if err := c.Render(r.Context(), &buf); err != nil {
		http.Error(w, "render failed", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write(buf.Bytes())
}
