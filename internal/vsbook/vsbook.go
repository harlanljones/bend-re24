// Package vsbook grades steal, bunt, and intentional-walk attempts against
// the decision book bin/re24 prints. Break-evens and intentional-walk run
// costs come from that output. This package only counts attempts and sums
// those integers; it does not recompute a run expectancy.
package vsbook

import (
	"encoding/csv"
	"fmt"
	"io"
	"sort"
	"strconv"
	"strings"

	"github.com/harlanljones/bend-re24/internal/bendout"
)

const (
	eventSB  = 4
	eventCS  = 6
	eventIBB = 15
)

// Attempt is one decision-shaped event from ingest's marks file.
type Attempt struct {
	Game, Half, Outs, Bases int
	Play                    string
	EventCD                 int
	SH, Bunt                bool
}

// Game is one row of the games CSV. Manager ids and names are empty when
// the game log did not have the game.
type Game struct {
	Index                                int
	ID, AwayTeam, HomeTeam               string
	AwayMgr, AwayName, HomeMgr, HomeName string
}

// Row is one manager's aggregate for one decision kind.
//
// MarginBP, when set, is the sum over graded steals and bunts of
// (10000 on a success, 0 on a failure) minus that state's break-even in
// basis points. A positive sum means the results beat the book.
// RunCost7, when set, is the sum of the book's intentional-walk ΔRE in
// units of 10^-7 runs. An intentional walk has no break-even.
type Row struct {
	ID, Name, Kind              string
	Attempts, Graded, Successes int
	MarginBP, RunCost7          *int64
}

// LoadAttempts reads the marks CSV ingest writes.
func LoadAttempts(r io.Reader) ([]Attempt, error) {
	rows, err := readCSV(r)
	if err != nil {
		return nil, err
	}
	const header = "game,half,outs,bases,play,event_cd,sh,bunt"
	if len(rows) == 0 || strings.Join(rows[0], ",") != header {
		return nil, fmt.Errorf("vsbook: marks want header %s", header)
	}
	var out []Attempt
	for i, row := range rows[1:] {
		a, err := attempt(row)
		if err != nil {
			return nil, fmt.Errorf("vsbook: marks row %d: %w", i+2, err)
		}
		out = append(out, a)
	}
	return out, nil
}

func attempt(row []string) (Attempt, error) {
	if len(row) != 8 {
		return Attempt{}, fmt.Errorf("%d fields", len(row))
	}
	n := func(s string) (int, error) { return strconv.Atoi(s) }
	g, errG := n(row[0])
	h, errH := n(row[1])
	o, errO := n(row[2])
	b, errB := n(row[3])
	cd, errC := n(row[5])
	sh, errS := bit(row[6])
	bu, errU := bit(row[7])
	if errG != nil || errH != nil || errO != nil || errB != nil || errC != nil || errS != nil || errU != nil {
		return Attempt{}, fmt.Errorf("bad integer")
	}
	if h != 0 && h != 1 || o < 0 || o > 2 || b < 0 || b > 7 || row[4] == "" {
		return Attempt{}, fmt.Errorf("bad half, state, or play")
	}
	return Attempt{g, h, o, b, row[4], cd, sh, bu}, nil
}

func bit(s string) (bool, error) {
	switch s {
	case "1":
		return true, nil
	case "0":
		return false, nil
	default:
		return false, fmt.Errorf("bad flag %q", s)
	}
}

// LoadGames reads the games CSV. The four manager columns may be absent;
// a file that has them may leave them empty.
func LoadGames(r io.Reader) ([]Game, error) {
	rows, err := readCSV(r)
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, fmt.Errorf("vsbook: games: empty")
	}
	head := strings.Join(rows[0], ",")
	wide := head == "game,game_id,away_team,home_team,away_mgr_id,away_mgr_name,home_mgr_id,home_mgr_name"
	short := head == "game,game_id,away_team"
	if !wide && !short {
		return nil, fmt.Errorf("vsbook: games: unrecognized header %q", head)
	}
	var out []Game
	for i, row := range rows[1:] {
		g, err := game(row, wide)
		if err != nil {
			return nil, fmt.Errorf("vsbook: games row %d: %w", i+2, err)
		}
		out = append(out, g)
	}
	return out, nil
}

func game(row []string, wide bool) (Game, error) {
	want := 3
	if wide {
		want = 8
	}
	if len(row) != want {
		return Game{}, fmt.Errorf("%d fields", len(row))
	}
	idx, err := strconv.Atoi(row[0])
	if err != nil {
		return Game{}, fmt.Errorf("bad game index")
	}
	g := Game{Index: idx, ID: row[1], AwayTeam: row[2]}
	if wide {
		g.HomeTeam, g.AwayMgr, g.AwayName, g.HomeMgr, g.HomeName = row[3], row[4], row[5], row[6], row[7]
	}
	return g, nil
}

func readCSV(r io.Reader) ([][]string, error) {
	rows, err := csv.NewReader(r).ReadAll()
	if err != nil {
		return nil, err
	}
	return rows, nil
}

type hit struct {
	kind            string
	state           bendout.State
	graded, success bool
	ibb             bool
}

func classify(a Attempt) []hit {
	var out []hit
	if a.EventCD == eventSB || a.EventCD == eventCS {
		out = append(out, classifySteal(a))
	}
	if a.SH || a.Bunt {
		out = append(out, classifyBunt(a))
	}
	if a.EventCD == eventIBB {
		out = append(out, hit{kind: "ibb", state: bendout.State{Bases: a.Bases, Outs: a.Outs}, ibb: true})
	}
	return out
}

func classifySteal(a Attempt) hit {
	st := bendout.State{Bases: a.Bases, Outs: a.Outs}
	switch {
	case (a.Bases == 1 || a.Bases == 5) && (a.Play == "--2-" || a.Play == "--X-"):
		return hit{kind: "steal2", state: st, graded: true, success: a.Play == "--2-"}
	case (a.Bases == 2 || a.Bases == 3) && (a.Play == "-3--" || a.Play == "-X--"):
		return hit{kind: "steal3", state: st, graded: true, success: a.Play == "-3--"}
	case a.Bases == 1 || a.Bases == 5:
		return hit{kind: "steal2", state: st}
	case a.Bases == 2 || a.Bases == 3:
		return hit{kind: "steal3", state: st}
	default:
		return hit{kind: "steal", state: st}
	}
}

func classifyBunt(a Attempt) hit {
	st := bendout.State{Bases: a.Bases, Outs: a.Outs}
	win, lose, ok := buntPlays(a.Bases)
	if a.Outs <= 1 && ok && (a.Play == win || a.Play == lose) {
		return hit{kind: "bunt", state: st, graded: true, success: a.Play == win}
	}
	return hit{kind: "bunt", state: st}
}

func buntPlays(bases int) (win, lose string, ok bool) {
	switch bases {
	case 1:
		return "--2X", "--X1", true
	case 2:
		return "-3-X", "-X-1", true
	case 3:
		return "-32X", "-X21", true
	default:
		return "", "", false
	}
}

type tally struct {
	id, name, kind     string
	attempts, graded   int
	successes          int
	margin, cost       int64
	hasMargin, hasCost bool
}

func decider(g Game, half int, kind string) (id, name string) {
	// Steals and bunts belong to the batting manager. An intentional walk
	// belongs to the fielding manager. Half 0 is the top: the away team bats.
	awayBats := half == 0
	if kind == "ibb" {
		awayBats = !awayBats
	}
	if awayBats {
		id, name = g.AwayMgr, g.AwayName
	} else {
		id, name = g.HomeMgr, g.HomeName
	}
	if id == "" {
		id = "unknown"
	}
	if name == "" {
		name = id
	}
	return id, name
}

func (t *tally) add(h hit, be int64, beOK bool, dre int64, dreOK bool) {
	t.attempts++
	if h.ibb {
		if !dreOK {
			return
		}
		t.graded++
		t.cost += dre
		t.hasCost = true
		return
	}
	if !h.graded || !beOK {
		return
	}
	t.graded++
	credit := int64(0)
	if h.success {
		t.successes++
		credit = 10000
	}
	t.margin += credit - be
	t.hasMargin = true
}

// Grade aggregates attempts by the manager who made the decision.
func Grade(attempts []Attempt, games []Game, book *bendout.Output) ([]Row, error) {
	by := make(map[int]Game, len(games))
	for _, g := range games {
		by[g.Index] = g
	}
	acc := map[string]*tally{}
	for i, a := range attempts {
		g, ok := by[a.Game]
		if !ok {
			return nil, fmt.Errorf("vsbook: attempt %d: game %d is not in the games file", i+1, a.Game)
		}
		for _, h := range classify(a) {
			id, name := decider(g, a.Half, h.kind)
			key := id + "\x00" + h.kind
			t := acc[key]
			if t == nil {
				t = &tally{id: id, name: name, kind: h.kind}
				acc[key] = t
			}
			be, beOK := breakEven(book, h.kind, h.state)
			dre, dreOK := deltaRE(book, h.kind, h.state)
			t.add(h, be, beOK, dre, dreOK)
		}
	}
	rows := make([]Row, 0, len(acc))
	for _, t := range acc {
		row := Row{ID: t.id, Name: t.name, Kind: t.kind, Attempts: t.attempts, Graded: t.graded, Successes: t.successes}
		if t.hasMargin {
			v := t.margin
			row.MarginBP = &v
		}
		if t.hasCost {
			v := t.cost
			row.RunCost7 = &v
		}
		rows = append(rows, row)
	}
	sort.Slice(rows, func(i, j int) bool {
		if rows[i].Name != rows[j].Name {
			return rows[i].Name < rows[j].Name
		}
		if rows[i].ID != rows[j].ID {
			return rows[i].ID < rows[j].ID
		}
		return kindRank(rows[i].Kind) < kindRank(rows[j].Kind)
	})
	return rows, nil
}

func kindRank(k string) int {
	switch k {
	case "steal2":
		return 0
	case "steal3":
		return 1
	case "bunt":
		return 2
	case "ibb":
		return 3
	default:
		return 4
	}
}

func breakEven(book *bendout.Output, kind string, s bendout.State) (int64, bool) {
	if book == nil {
		return 0, false
	}
	for _, be := range book.BreakEvens {
		if be.Kind == kind && be.State == s && be.BP != nil {
			return *be.BP, true
		}
	}
	return 0, false
}

func deltaRE(book *bendout.Output, kind string, s bendout.State) (int64, bool) {
	if book == nil {
		return 0, false
	}
	for _, d := range book.DeltaREs {
		if d.Kind == kind && d.State == s && d.Value != nil {
			return *d.Value, true
		}
	}
	return 0, false
}
