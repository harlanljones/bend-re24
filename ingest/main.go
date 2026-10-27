// Command ingest turns cwevent rows into the integer per-play CSV that
// bin/re24 replays: one row per event in innings 1-8, with the play written
// as four destination characters in slot order r3 r2 r1 batter.
package main

import (
	"bufio"
	"encoding/csv"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"strconv"
)

// columns lists the cwevent fields ingest reads, by header name.
var columns = []string{
	"GAME_ID", "AWAY_TEAM_ID", "INN_CT", "OUTS_CT", "EVENT_CD", "BAT_EVENT_FL",
	"EVENT_OUTS_CT", "BAT_DEST_ID", "RUN1_DEST_ID", "RUN2_DEST_ID", "RUN3_DEST_ID",
	"BAT_LAST_ID", "START_BASES_CD", "END_BASES_CD", "EVENT_RUNS_CT", "FATE_RUNS_CT",
}

// event is one cwevent row with its numeric fields parsed.
type event struct {
	gameID    string
	awayTeam  string
	inn       int
	outs      int
	eventCD   int
	batEvent  bool
	eventOuts int
	batDest   int
	runDest   [4]int // runDest[k] for the runner who began on base k (1..3)
	half      int
	bases     int
	endBases  int
	eventRuns int
	fateRuns  int
}

// parse reads an event from named fields; line is the input line for errors.
func parse(f map[string]string, line int) (event, error) {
	e := event{gameID: f["GAME_ID"], awayTeam: f["AWAY_TEAM_ID"]}
	num := func(name string, dst *int) error {
		v, err := strconv.Atoi(f[name])
		if err != nil {
			return fmt.Errorf("ingest: %s row %d: bad %s %q", e.gameID, line, name, f[name])
		}
		*dst = v
		return nil
	}
	ints := []struct {
		name string
		dst  *int
	}{
		{"INN_CT", &e.inn}, {"OUTS_CT", &e.outs}, {"EVENT_CD", &e.eventCD},
		{"EVENT_OUTS_CT", &e.eventOuts}, {"BAT_DEST_ID", &e.batDest},
		{"RUN1_DEST_ID", &e.runDest[1]}, {"RUN2_DEST_ID", &e.runDest[2]},
		{"RUN3_DEST_ID", &e.runDest[3]}, {"BAT_LAST_ID", &e.half},
		{"START_BASES_CD", &e.bases}, {"END_BASES_CD", &e.endBases},
		{"EVENT_RUNS_CT", &e.eventRuns}, {"FATE_RUNS_CT", &e.fateRuns},
	}
	for _, c := range ints {
		if err := num(c.name, c.dst); err != nil {
			return event{}, err
		}
	}
	switch f["BAT_EVENT_FL"] {
	case "T":
		e.batEvent = true
	case "F":
	default:
		return event{}, fmt.Errorf("ingest: %s row %d: bad BAT_EVENT_FL %q", e.gameID, line, f["BAT_EVENT_FL"])
	}
	return e, nil
}

// slot is the index in the play string of the runner who began on base k.
func slot(k int) int { return 3 - k }

// bit is base k's bit in Chadwick's base code.
var bit = [4]int{0, 1, 2, 4}

// encode writes the play as r3 r2 r1 batter, each one of - X R 1 2 3.
func encode(e event) ([]byte, error) {
	p := []byte("----")
	for k := 3; k >= 1; k-- {
		d := e.runDest[k]
		if e.bases&bit[k] == 0 {
			if d != 0 {
				return nil, fmt.Errorf("dest %d set on empty base %d", d, k)
			}
			continue
		}
		switch {
		case d == 0:
			p[slot(k)] = 'X'
		case d >= 4:
			p[slot(k)] = 'R'
		case d == k:
		default:
			// Backward moves stay literal so the scorebook's legality gate rejects them.
			p[slot(k)] = byte('0' + d)
		}
	}
	switch {
	case !e.batEvent:
		if e.batDest != 0 {
			return nil, fmt.Errorf("batter dest %d on a non-batter event", e.batDest)
		}
	case e.batDest == 0:
		p[3] = 'X'
	case e.batDest >= 4:
		p[3] = 'R'
	default:
		p[3] = byte('0' + e.batDest)
	}
	return p, nil
}

// repair restores the forced advances Retrosheet omits on third-out force
// plays: a runner shown staying on base k while another runner is placed on
// k must have moved up one. It reports whether it changed the play. A runner
// forced off third is ambiguous, so such a play is left as it was.
func repair(e event, p []byte) ([]byte, bool) {
	if !e.batEvent || e.outs+e.eventOuts != 3 {
		return p, false
	}
	q := append([]byte(nil), p...)
	changed := false
	for k := 1; k <= 3; k++ {
		if e.bases&bit[k] == 0 || q[slot(k)] != '-' {
			continue
		}
		taken := false
		for s := range q {
			if s != slot(k) && q[s] == byte('0'+k) {
				taken = true
			}
		}
		if !taken {
			continue
		}
		if k == 3 {
			return p, false
		}
		q[slot(k)] = byte('0' + k + 1)
		changed = true
	}
	return q, changed
}

type stats struct{ games, plays, repairs int }

// run reads cwevent CSV from in and writes the plays and games CSVs.
func run(in io.Reader, plays, games io.Writer) (stats, error) {
	var st stats
	r := csv.NewReader(in)
	header, err := r.Read()
	if err != nil {
		return st, fmt.Errorf("ingest: reading header: %w", err)
	}
	col := map[string]int{}
	for i, h := range header {
		col[h] = i
	}
	for _, c := range columns {
		if _, ok := col[c]; !ok {
			return st, fmt.Errorf("ingest: missing column %s", c)
		}
	}
	pw := bufio.NewWriter(plays)
	gw := bufio.NewWriter(games)
	fmt.Fprintln(pw, "game,inn,half,outs,bases,play,end_bases,event_outs,event_runs,fate_runs,event_cd")
	fmt.Fprintln(gw, "game,game_id,away_team")
	index := map[string]int{}
	cur := ""
	line := 1
	fields := make(map[string]string, len(columns))
	for {
		rec, err := r.Read()
		if errors.Is(err, io.EOF) {
			break
		}
		line++
		if err != nil {
			return st, fmt.Errorf("ingest: row %d: %w", line, err)
		}
		for _, c := range columns {
			fields[c] = rec[col[c]]
		}
		e, err := parse(fields, line)
		if err != nil {
			return st, err
		}
		if e.gameID != cur {
			if _, seen := index[e.gameID]; seen {
				return st, fmt.Errorf("ingest: %s row %d: game rows are not contiguous", e.gameID, line)
			}
			index[e.gameID] = st.games
			fmt.Fprintf(gw, "%d,%s,%s\n", st.games, e.gameID, e.awayTeam)
			st.games++
			cur = e.gameID
		}
		if e.inn > 8 {
			continue
		}
		p, err := encode(e)
		if err != nil {
			return st, fmt.Errorf("ingest: %s row %d: %v", e.gameID, line, err)
		}
		p, fixed := repair(e, p)
		if fixed {
			st.repairs++
		}
		fmt.Fprintf(pw, "%d,%d,%d,%d,%d,%s,%d,%d,%d,%d,%d\n", index[e.gameID], e.inn, e.half,
			e.outs, e.bases, p, e.endBases, e.eventOuts, e.eventRuns, e.fateRuns, e.eventCD)
		st.plays++
	}
	if err := pw.Flush(); err != nil {
		return st, err
	}
	return st, gw.Flush()
}

func main() {
	in := flag.String("in", "", "cwevent CSV")
	playsPath := flag.String("plays", "", "plays CSV to write")
	gamesPath := flag.String("games", "", "games CSV to write")
	flag.Parse()
	if *in == "" || *playsPath == "" || *gamesPath == "" {
		fmt.Fprintln(os.Stderr, "usage: ingest -in <cwevent.csv> -plays <plays.csv> -games <games.csv>")
		os.Exit(2)
	}
	if err := ingest(*in, *playsPath, *gamesPath); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func ingest(inPath, playsPath, gamesPath string) error {
	in, err := os.Open(inPath)
	if err != nil {
		return fmt.Errorf("ingest: %w", err)
	}
	defer in.Close()
	plays, err := os.Create(playsPath)
	if err != nil {
		return fmt.Errorf("ingest: %w", err)
	}
	defer plays.Close()
	games, err := os.Create(gamesPath)
	if err != nil {
		return fmt.Errorf("ingest: %w", err)
	}
	defer games.Close()
	st, err := run(in, plays, games)
	if err != nil {
		return err
	}
	if err := plays.Close(); err != nil {
		return fmt.Errorf("ingest: %w", err)
	}
	if err := games.Close(); err != nil {
		return fmt.Errorf("ingest: %w", err)
	}
	fmt.Fprintf(os.Stderr, "ingest: %d games, %d plays (innings 1-8), %d forced-advance repairs\n",
		st.games, st.plays, st.repairs)
	return nil
}
