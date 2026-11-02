package vsbook

import (
	"strings"
	"testing"

	"github.com/harlanljones/bend-re24/internal/bendout"
)

func i64(n int64) *int64 { return &n }

func TestGrade(t *testing.T) {
	games := []Game{{
		Index: 0, ID: "ANA202404050", AwayTeam: "BOS", HomeTeam: "ANA",
		AwayMgr: "coraa001", AwayName: "Alex Cora",
		HomeMgr: "washr001", HomeName: "Ron Washington",
	}}
	book := &bendout.Output{
		BreakEvens: []bendout.BreakEven{
			{Kind: "steal2", State: bendout.State{Bases: 1, Outs: 0}, BP: i64(7000)},
			{Kind: "bunt", State: bendout.State{Bases: 1, Outs: 0}, BP: i64(20000)},
		},
		DeltaREs: []bendout.DeltaRE{
			{Kind: "ibb", State: bendout.State{Bases: 0, Outs: 0}, Value: i64(4005000)},
		},
	}
	attempts := []Attempt{
		{Game: 0, Half: 0, Outs: 0, Bases: 1, Play: "--2-", EventCD: 4},
		{Game: 0, Half: 0, Outs: 0, Bases: 1, Play: "--X-", EventCD: 6},
		{Game: 0, Half: 0, Outs: 0, Bases: 4, Play: "R---", EventCD: 4},
		{Game: 0, Half: 1, Outs: 0, Bases: 1, Play: "--2X", EventCD: 2, SH: true},
		{Game: 0, Half: 0, Outs: 0, Bases: 0, Play: "---1", EventCD: 15},
	}
	rows, err := Grade(attempts, games, book)
	if err != nil {
		t.Fatal(err)
	}
	want := []Row{
		{ID: "coraa001", Name: "Alex Cora", Kind: "steal2", Attempts: 2, Graded: 2, Successes: 1, MarginBP: i64(10000 - 7000 - 7000)},
		{ID: "coraa001", Name: "Alex Cora", Kind: "steal", Attempts: 1},
		{ID: "washr001", Name: "Ron Washington", Kind: "bunt", Attempts: 1, Graded: 1, Successes: 1, MarginBP: i64(10000 - 20000)},
		{ID: "washr001", Name: "Ron Washington", Kind: "ibb", Attempts: 1, Graded: 1, RunCost7: i64(4005000)},
	}
	if len(rows) != len(want) {
		t.Fatalf("rows = %+v", rows)
	}
	for i := range want {
		got := rows[i]
		if got.ID != want[i].ID || got.Kind != want[i].Kind || got.Attempts != want[i].Attempts || got.Graded != want[i].Graded || got.Successes != want[i].Successes {
			t.Errorf("row %d = %+v, want %+v", i, got, want[i])
		}
		if !same(got.MarginBP, want[i].MarginBP) || !same(got.RunCost7, want[i].RunCost7) {
			t.Errorf("row %d values = margin %v cost %v", i, p(got.MarginBP), p(got.RunCost7))
		}
	}
}

func same(a, b *int64) bool {
	if a == nil || b == nil {
		return a == nil && b == nil
	}
	return *a == *b
}

func p(n *int64) any {
	if n == nil {
		return nil
	}
	return *n
}

func TestLoadAndUngradedBunt(t *testing.T) {
	attempts, err := LoadAttempts(strings.NewReader("game,half,outs,bases,play,event_cd,sh,bunt\n0,1,1,1,--XX,2,1,1\n"))
	if err != nil {
		t.Fatal(err)
	}
	games, err := LoadGames(strings.NewReader("game,game_id,away_team\n0,AAA202404010,BBB\n"))
	if err != nil {
		t.Fatal(err)
	}
	rows, err := Grade(attempts, games, &bendout.Output{
		BreakEvens: []bendout.BreakEven{{Kind: "bunt", State: bendout.State{Bases: 1, Outs: 1}, BP: i64(10000)}},
	})
	if err != nil {
		t.Fatal(err)
	}
	// A bunt whose play is not the book's success or failure is counted and not scored.
	// The home team is batting, and the short games file has no manager id.
	if len(rows) != 1 || rows[0].ID != "unknown" || rows[0].Kind != "bunt" || rows[0].Attempts != 1 || rows[0].Graded != 0 || rows[0].MarginBP != nil {
		t.Fatalf("rows = %+v", rows)
	}
}

func TestLoadRejects(t *testing.T) {
	if _, err := LoadAttempts(strings.NewReader("game,play\n")); err == nil {
		t.Fatal("bad marks header was accepted")
	}
	if _, err := LoadGames(strings.NewReader("nope\n")); err == nil {
		t.Fatal("bad games header was accepted")
	}
	if _, err := Grade([]Attempt{{Game: 3, Half: 0, Outs: 0, Bases: 1, Play: "--2-", EventCD: 4}}, nil, &bendout.Output{}); err == nil {
		t.Fatal("missing game was accepted")
	}
}
