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
	"time"

	"github.com/a-h/templ"
	"github.com/harlanljones/bend-re24/internal/bendout"
	"github.com/harlanljones/bend-re24/internal/vsbook"
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
// lines when no bootstrap output was loaded. year is the season being shown.
// mgrs is set only when both the marks file and the games file were loaded.
type data struct {
	year      int
	run, boot *bendout.Output
	lit       []litRow
	mgrLoaded bool
	mgrs      []vsbook.Row
}

func main() {
	runPath := flag.String("run", "out/run-2024.txt", "bin/re24 run output")
	bootPath := flag.String("boot", "out/boot-2024.txt", "bin/re24 boot output; CIs are omitted when absent")
	refs := flag.String("refs", "fixtures/reference", "reference directory (breakeven-literature.csv)")
	addr := flag.String("addr", "127.0.0.1:8024", "listen address")
	export := flag.String("export", "", "write the CSV files to this directory and exit")
	year := flag.Int("year", 2024, "season in the exported file names")
	marks := flag.String("marks", "", "decision-mark CSV from ingest; set with -games")
	games := flag.String("games", "", "games CSV from ingest; set with -marks")
	flag.Parse()
	if flag.NArg() != 0 {
		fmt.Fprintln(os.Stderr, "usage: report -run <run.txt> [-boot <boot.txt>] [-refs <dir>] [-marks <marks.csv> -games <games.csv>] [-addr <host:port>] [-export <dir>] [-year <year>]")
		os.Exit(2)
	}
	if err := run(*runPath, *bootPath, *refs, *addr, *export, *year, *marks, *games); err != nil {
		fmt.Fprintln(os.Stderr, "report:", err)
		os.Exit(1)
	}
}

func run(runPath, bootPath, refs, addr, export string, year int, marks, games string) error {
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
	loaded, mgrs, err := loadManagers(marks, games, out)
	if err != nil {
		return err
	}
	if export != "" {
		return exportCSV(export, year, out, boot, mgrs, loaded)
	}
	lit, err := readLiterature(filepath.Join(refs, "breakeven-literature.csv"))
	if err != nil {
		return err
	}
	log.Printf("report: serving http://%s", addr)
	return listen(addr, newHandler(data{year: year, run: out, boot: boot, lit: lit, mgrLoaded: loaded, mgrs: mgrs}))
}

// loadManagers grades ingest's marks against the run's break-evens. Neither
// path means the report has no manager section. One path without the other
// is an error, so a missing file is not shown as an empty leaderboard.
func loadManagers(marksPath, gamesPath string, book *bendout.Output) (bool, []vsbook.Row, error) {
	if marksPath == "" && gamesPath == "" {
		return false, nil, nil
	}
	if marksPath == "" || gamesPath == "" {
		return false, nil, errors.New("-marks and -games are set together")
	}
	mf, err := os.Open(marksPath)
	if err != nil {
		return false, nil, err
	}
	defer mf.Close()
	attempts, err := vsbook.LoadAttempts(mf)
	if err != nil {
		return false, nil, err
	}
	gf, err := os.Open(gamesPath)
	if err != nil {
		return false, nil, err
	}
	defer gf.Close()
	gs, err := vsbook.LoadGames(gf)
	if err != nil {
		return false, nil, err
	}
	rows, err := vsbook.Grade(attempts, gs, book)
	if err != nil {
		return false, nil, err
	}
	return true, rows, nil
}

// newServer bounds how long a request may sit in read or write. The page is
// rendered before the write, so the write timeout covers sending it.
func newServer(addr string, h http.Handler) *http.Server {
	return &http.Server{
		Addr:              addr,
		Handler:           h,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
}

func listen(addr string, h http.Handler) error {
	return newServer(addr, h).ListenAndServe()
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
