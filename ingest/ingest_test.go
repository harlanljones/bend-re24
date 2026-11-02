package main

import (
	"bytes"
	"os"
	"strings"
	"testing"
)

// row builds an event from the fields a case names; the rest are batter
// events with every count and destination zero.
func row(t *testing.T, f map[string]string) event {
	t.Helper()
	full := map[string]string{
		"GAME_ID": "TST202404010", "AWAY_TEAM_ID": "AWY",
		"BAT_EVENT_FL": "T", "SH_FL": "F", "BUNT_FL": "F",
	}
	for _, c := range columns {
		if _, ok := full[c]; !ok {
			full[c] = "0"
		}
	}
	for k, v := range f {
		full[k] = v
	}
	e, err := parse(full, 2)
	if err != nil {
		t.Fatal(err)
	}
	return e
}

func TestEncodeRepair(t *testing.T) {
	cases := []struct {
		name    string
		fields  map[string]string
		want    string
		repairs bool
		fails   bool
	}{
		{name: "single scores from 3rd, 1st to 3rd",
			fields: map[string]string{"START_BASES_CD": "5", "RUN3_DEST_ID": "4", "RUN1_DEST_ID": "3", "BAT_DEST_ID": "1"},
			want:   "R-31"},
		{name: "GDP 64(1)3",
			fields: map[string]string{"START_BASES_CD": "1", "RUN1_DEST_ID": "0", "BAT_DEST_ID": "0", "OUTS_CT": "0", "EVENT_OUTS_CT": "2"},
			want:   "--XX"},
		{name: "grand slam",
			fields: map[string]string{"START_BASES_CD": "7", "RUN3_DEST_ID": "4", "RUN2_DEST_ID": "4", "RUN1_DEST_ID": "4", "BAT_DEST_ID": "4"},
			want:   "RRRR"},
		{name: "stolen base",
			fields: map[string]string{"BAT_EVENT_FL": "F", "START_BASES_CD": "1", "RUN1_DEST_ID": "2"},
			want:   "--2-"},
		{name: "repair 1B+2B third-out force",
			fields: map[string]string{"START_BASES_CD": "3", "OUTS_CT": "2", "EVENT_OUTS_CT": "1", "RUN2_DEST_ID": "0", "RUN1_DEST_ID": "1", "BAT_DEST_ID": "1"},
			want:   "-X21", repairs: true},
		{name: "repair loaded third-out force",
			fields: map[string]string{"START_BASES_CD": "7", "OUTS_CT": "2", "EVENT_OUTS_CT": "1", "RUN3_DEST_ID": "0", "RUN2_DEST_ID": "2", "RUN1_DEST_ID": "1", "BAT_DEST_ID": "1"},
			want:   "X321", repairs: true},
		{name: "no repair before the third out",
			fields: map[string]string{"START_BASES_CD": "3", "OUTS_CT": "0", "EVENT_OUTS_CT": "1", "RUN2_DEST_ID": "0", "RUN1_DEST_ID": "1", "BAT_DEST_ID": "1"},
			want:   "-X-1"},
		{name: "dest set on empty base",
			fields: map[string]string{"START_BASES_CD": "1", "RUN1_DEST_ID": "2", "RUN2_DEST_ID": "3"},
			fails:  true},
		{name: "non-batter event with batter dest",
			fields: map[string]string{"BAT_EVENT_FL": "F", "START_BASES_CD": "1", "RUN1_DEST_ID": "2", "BAT_DEST_ID": "2"},
			fails:  true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			e := row(t, c.fields)
			p, err := encode(e)
			if c.fails {
				if err == nil {
					t.Fatalf("encode = %q, want error", p)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			p, fixed := repair(e, p)
			if string(p) != c.want || fixed != c.repairs {
				t.Fatalf("play = %q repaired %v, want %q repaired %v", p, fixed, c.want, c.repairs)
			}
		})
	}
}

func eventHeader() string {
	return `"GAME_ID","AWAY_TEAM_ID","INN_CT","OUTS_CT","EVENT_CD","BAT_EVENT_FL","SH_FL","BUNT_FL","EVENT_OUTS_CT","BAT_DEST_ID","RUN1_DEST_ID","RUN2_DEST_ID","RUN3_DEST_ID","BAT_LAST_ID","START_BASES_CD","END_BASES_CD","EVENT_RUNS_CT","FATE_RUNS_CT"`
}

func TestRunEndToEnd(t *testing.T) {
	in := strings.Join([]string{
		eventHeader(),
		`"AAA202404010","BBB",1,0,20,"T","F","F",0,1,0,0,0,0,0,1,0,1`,
		`"AAA202404010","BBB",9,0,2,"T","F","F",1,0,0,0,0,1,0,0,0,0`,
		`"CCC202404010","DDD",1,0,4,"F","F","F",0,0,2,0,0,0,1,2,0,0`,
		`"CCC202404010","DDD",8,2,23,"T","T","F",0,4,4,0,0,1,1,0,2,0`,
	}, "\n") + "\n"
	var plays, games, marks bytes.Buffer
	st, err := run(strings.NewReader(in), &plays, &games, &marks, nil)
	if err != nil {
		t.Fatal(err)
	}
	wantPlays := "game,inn,half,outs,bases,play,end_bases,event_outs,event_runs,fate_runs,event_cd\n" +
		"0,1,0,0,0,---1,1,0,0,1,20\n" +
		"1,1,0,0,1,--2-,2,0,0,0,4\n" +
		"1,8,1,2,1,--RR,0,0,2,0,23\n"
	wantGames := "game,game_id,away_team,home_team,away_mgr_id,away_mgr_name,home_mgr_id,home_mgr_name\n" +
		"0,AAA202404010,BBB,AAA,,,,\n" +
		"1,CCC202404010,DDD,CCC,,,,\n"
	wantMarks := "game,half,outs,bases,play,event_cd,sh,bunt\n" +
		"1,0,0,1,--2-,4,0,0\n" +
		"1,1,2,1,--RR,23,1,0\n"
	if plays.String() != wantPlays {
		t.Errorf("plays:\n%s\nwant:\n%s", plays.String(), wantPlays)
	}
	if games.String() != wantGames {
		t.Errorf("games:\n%s\nwant:\n%s", games.String(), wantGames)
	}
	if marks.String() != wantMarks {
		t.Errorf("marks:\n%s\nwant:\n%s", marks.String(), wantMarks)
	}
	if st != (stats{games: 2, plays: 3, repairs: 0, marks: 2}) {
		t.Errorf("stats = %+v", st)
	}
}

// logLine builds one Retrosheet game-log row. Manager ids are the 90th and
// 92nd fields (1-based); the game id is home team + date + game number.
func logLine(date, num, home, awayID, awayName, homeID, homeName string) string {
	f := make([]string, 93)
	for i := range f {
		f[i] = "0"
	}
	f[0], f[1], f[6] = date, num, home
	f[89], f[90], f[91], f[92] = awayID, awayName, homeID, homeName
	return strings.Join(f, ",")
}

func TestRunManagers(t *testing.T) {
	in := strings.Join([]string{
		eventHeader(),
		`"AAA202404010","BBB",1,0,15,"T","F","F",0,1,0,0,0,0,0,1,0,0`,
		`"CCC202404010","DDD",1,0,2,"T","F","F",1,0,0,0,0,0,0,0,0,0`,
	}, "\n") + "\n"
	log := logLine("20240401", "0", "AAA", "coraa001", "Alex Cora", "washr001", "Ron Washington") + "\n"
	var plays, games, marks bytes.Buffer
	st, err := run(strings.NewReader(in), &plays, &games, &marks, strings.NewReader(log))
	if err != nil {
		t.Fatal(err)
	}
	wantGames := "game,game_id,away_team,home_team,away_mgr_id,away_mgr_name,home_mgr_id,home_mgr_name\n" +
		"0,AAA202404010,BBB,AAA,coraa001,Alex Cora,washr001,Ron Washington\n" +
		"1,CCC202404010,DDD,CCC,,,,\n"
	if games.String() != wantGames {
		t.Errorf("games:\n%s\nwant:\n%s", games.String(), wantGames)
	}
	wantMarks := "game,half,outs,bases,play,event_cd,sh,bunt\n0,0,0,0,---1,15,0,0\n"
	if marks.String() != wantMarks {
		t.Errorf("marks:\n%s\nwant:\n%s", marks.String(), wantMarks)
	}
	if st.mgrGames != 1 || st.marks != 1 || st.games != 2 {
		t.Errorf("stats = %+v", st)
	}
}

func TestFixtureMini(t *testing.T) {
	in, err := os.Open("../fixtures/cwevent-mini.csv")
	if err != nil {
		t.Fatal(err)
	}
	defer in.Close()
	logf, err := os.Open("../fixtures/gamelog-mini.csv")
	if err != nil {
		t.Fatal(err)
	}
	defer logf.Close()
	var plays, games, marks bytes.Buffer
	st, err := run(in, &plays, &games, &marks, logf)
	if err != nil {
		t.Fatal(err)
	}
	wantPlays, err := os.ReadFile("../fixtures/plays-mini.csv")
	if err != nil {
		t.Fatal(err)
	}
	if plays.String() != string(wantPlays) {
		t.Fatal("plays-mini.csv changed")
	}
	for _, name := range []string{"games-mini.csv", "marks-mini.csv"} {
		want, err := os.ReadFile("../fixtures/" + name)
		if err != nil {
			t.Fatal(err)
		}
		got := games.String()
		if name == "marks-mini.csv" {
			got = marks.String()
		}
		if got != string(want) {
			t.Fatalf("%s diverged:\n%s", name, got)
		}
	}
	if st != (stats{games: 2, plays: 148, repairs: 1, marks: 1, mgrGames: 2}) {
		t.Fatalf("stats = %+v", st)
	}
}
