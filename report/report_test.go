package main

import (
	"html"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/harlanljones/bend-re24/internal/bendout"
	"github.com/harlanljones/bend-re24/internal/vsbook"
)

const sampleRun = `GAMES 2 2 0
HALVES 32 0
PLAYS 30
RE 0 0 10 20 500
RE 1 0 9 10 900
RE 1 1 2 4 500
T 0 0 1 0 0 12
T 0 0 0 1 0 8
T 1 0 1 1 0 4
T 1 0 3 0 0 5
T 1 0 0 3 1 1
BE steal2 1 0 7325
BE bunt 1 0 23215
DRE bunt 1 0 -2043713
DRE ibb 1 0 NA
`

const sampleBoot = `BOOT 1024 7 2
CI RE 1 0 8500000 9500000
CI BE steal2 1 0 7000 7600
CI BE bunt 1 0 NA NA
CI DRE bunt 1 0 -2500000 -1500000
`

func testServer(t *testing.T) *httptest.Server {
	t.Helper()
	run, err := bendout.Parse(strings.NewReader(sampleRun))
	if err != nil {
		t.Fatal(err)
	}
	boot, err := bendout.Parse(strings.NewReader(sampleBoot))
	if err != nil {
		t.Fatal(err)
	}
	lit := []litRow{{"steal2", bendout.State{Bases: 1, Outs: 0}, "70", "75", "2009-2011", "https://blogs.fangraphs.com/breaking-down-stolen-base-break-even-points/"}}
	srv := httptest.NewServer(newHandler(data{year: 2023, run: run, boot: boot, lit: lit}))
	t.Cleanup(srv.Close)
	return srv
}

func get(t *testing.T, srv *httptest.Server, path string) (int, string) {
	t.Helper()
	resp, err := http.Get(srv.URL + path)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	return resp.StatusCode, string(body)
}

func TestRoutes(t *testing.T) {
	srv := testServer(t)

	code, body := get(t, srv, "/state?b=1&o=0")
	if code != http.StatusOK {
		t.Fatalf("/state?b=1&o=0: status %d", code)
	}
	for _, want := range []string{"<td>4</td>", "<td>5</td>", "<td>1</td>", "<td>10</td>", "0.9000"} {
		if !strings.Contains(body, want) {
			t.Errorf("/state?b=1&o=0: missing %q in %s", want, body)
		}
	}
	if strings.Contains(body, "<td>12</td>") {
		t.Errorf("/state?b=1&o=0: shows another state's transitions")
	}

	if code, body := get(t, srv, "/state?b=9&o=0"); code != http.StatusBadRequest || strings.TrimSpace(body) != "bad state" {
		t.Errorf("/state?b=9&o=0: got %d %q, want 400 bad state", code, body)
	}

	code, body = get(t, srv, "/")
	if code != http.StatusOK {
		t.Fatalf("/: status %d", code)
	}
	plain := html.UnescapeString(body)
	if !strings.Contains(plain, notice) {
		t.Errorf("/: missing the Retrosheet notice")
	}
	if !strings.Contains(plain, "2023 run expectancy") {
		t.Errorf("/: year was not taken from the report data")
	}
	if !strings.Contains(plain, "Decision marks were not loaded") {
		t.Errorf("/: missing the unloaded-marks note")
	}
}

func TestManagers(t *testing.T) {
	run, err := bendout.Parse(strings.NewReader(sampleRun))
	if err != nil {
		t.Fatal(err)
	}
	margin := int64(-4000)
	rows := []vsbook.Row{{
		ID: "coraa001", Name: "Alex Cora", Kind: "steal2",
		Attempts: 2, Graded: 2, Successes: 1, MarginBP: &margin,
	}}
	srv := httptest.NewServer(newHandler(data{year: 2024, run: run, boot: &bendout.Output{}, mgrLoaded: true, mgrs: rows}))
	t.Cleanup(srv.Close)
	code, body := get(t, srv, "/")
	if code != http.StatusOK {
		t.Fatalf("/: status %d", code)
	}
	plain := html.UnescapeString(body)
	for _, want := range []string{"Alex Cora", "Steal of second", "-20.00 pp", "50.00%"} {
		if !strings.Contains(plain, want) {
			t.Errorf("/: missing %q", want)
		}
	}
	if strings.Contains(plain, "Decision marks were not loaded") {
		t.Errorf("/: loaded marks still show the empty note")
	}
}

func TestManagersNeedBothFiles(t *testing.T) {
	if _, _, err := loadManagers("marks.csv", "", nil); err == nil {
		t.Fatal("marks without games was accepted")
	}
	if _, _, err := loadManagers("", "games.csv", nil); err == nil {
		t.Fatal("games without marks was accepted")
	}
}

func TestExportManagers(t *testing.T) {
	run, err := bendout.Parse(strings.NewReader(sampleRun))
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	if err := exportCSV(dir, 2024, run, &bendout.Output{}, nil, false); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(dir + "/managers-2024.csv"); !os.IsNotExist(err) {
		t.Fatalf("managers csv exists without marks: %v", err)
	}
	margin := int64(-4000)
	cost := int64(4005000)
	rows := []vsbook.Row{
		{ID: "coraa001", Name: "Alex Cora", Kind: "steal2", Attempts: 2, Graded: 2, Successes: 1, MarginBP: &margin},
		{ID: "washr001", Name: "Ron Washington", Kind: "ibb", Attempts: 1, Graded: 1, RunCost7: &cost},
	}
	if err := exportCSV(dir, 2024, run, &bendout.Output{}, rows, true); err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(dir + "/managers-2024.csv")
	if err != nil {
		t.Fatal(err)
	}
	got := string(b)
	want := "manager_id,manager,kind,attempts,graded,successes,success_rate,avg_margin_pp,ibb_dre\n" +
		"coraa001,Alex Cora,steal2,2,2,1,50.00,-20.00,\n" +
		"washr001,Ron Washington,ibb,1,1,0,,,0.4005\n"
	if got != want {
		t.Fatalf("managers csv:\n%s\nwant:\n%s", got, want)
	}
}

func TestServerTimeouts(t *testing.T) {
	s := newServer("127.0.0.1:0", http.NewServeMux())
	if s.ReadHeaderTimeout != 5*time.Second || s.ReadTimeout != 10*time.Second || s.WriteTimeout != 15*time.Second {
		t.Fatalf("timeouts = header %s read %s write %s", s.ReadHeaderTimeout, s.ReadTimeout, s.WriteTimeout)
	}
}
