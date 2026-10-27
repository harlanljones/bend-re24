package main

import (
	"html"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/harlanljones/bend-re24/internal/bendout"
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
	srv := httptest.NewServer(newHandler(data{run, boot, lit}))
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
	if !strings.Contains(html.UnescapeString(body), notice) {
		t.Errorf("/: missing the Retrosheet notice")
	}
}
