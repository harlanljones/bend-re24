package main

import (
	"bytes"
	"strings"
	"testing"
)

// row builds an event from the fields a case names; the rest are batter
// events with every count and destination zero.
func row(t *testing.T, f map[string]string) event {
	t.Helper()
	full := map[string]string{"GAME_ID": "TST202404010", "AWAY_TEAM_ID": "AWY", "BAT_EVENT_FL": "T"}
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

func TestRunEndToEnd(t *testing.T) {
	in := strings.Join([]string{
		`"GAME_ID","AWAY_TEAM_ID","INN_CT","OUTS_CT","EVENT_CD","BAT_EVENT_FL","EVENT_OUTS_CT","BAT_DEST_ID","RUN1_DEST_ID","RUN2_DEST_ID","RUN3_DEST_ID","BAT_LAST_ID","START_BASES_CD","END_BASES_CD","EVENT_RUNS_CT","FATE_RUNS_CT"`,
		`"AAA202404010","BBB",1,0,20,"T",0,1,0,0,0,0,0,1,0,1`,
		`"AAA202404010","BBB",9,0,2,"T",1,0,0,0,0,1,0,0,0,0`,
		`"CCC202404010","DDD",1,0,4,"F",0,0,2,0,0,0,1,2,0,0`,
		`"CCC202404010","DDD",8,2,23,"T",0,4,4,0,0,1,1,0,2,0`,
	}, "\n") + "\n"
	var plays, games bytes.Buffer
	st, err := run(strings.NewReader(in), &plays, &games)
	if err != nil {
		t.Fatal(err)
	}
	wantPlays := "game,inn,half,outs,bases,play,end_bases,event_outs,event_runs,fate_runs,event_cd\n" +
		"0,1,0,0,0,---1,1,0,0,1,20\n" +
		"1,1,0,0,1,--2-,2,0,0,0,4\n" +
		"1,8,1,2,1,--RR,0,0,2,0,23\n"
	wantGames := "game,game_id,away_team\n0,AAA202404010,BBB\n1,CCC202404010,DDD\n"
	if plays.String() != wantPlays {
		t.Errorf("plays:\n%s\nwant:\n%s", plays.String(), wantPlays)
	}
	if games.String() != wantGames {
		t.Errorf("games:\n%s\nwant:\n%s", games.String(), wantGames)
	}
	if st != (stats{games: 2, plays: 3, repairs: 0}) {
		t.Errorf("stats = %+v", st)
	}
}
