package bendout

import (
	"strings"
	"testing"
)

const sample = `GAMES 2 1 1
HALVES 16 0
PLAYS 78
BADGAME 1 25 runs
RE 0 0 19970 40650 491
RE 4 1 0 0 NA
T 1 0 0 3 0 12
BE steal2 1 0 7325
BE bunt 2 1 NA
DRE bunt 1 0 -2043713
BOOT 1024 2024 2429
CI RE 0 0 4800000 5000000
CI BE steal3 2 2 9100 NA
`

func TestParseSample(t *testing.T) {
	o, err := Parse(strings.NewReader(sample))
	if err != nil {
		t.Fatal(err)
	}
	if o.Games != (Games{2, 1, 1}) || o.Halves != (Halves{16, 0}) || o.Plays != 78 {
		t.Errorf("summary = %+v %+v %d", o.Games, o.Halves, o.Plays)
	}
	if len(o.BadGames) != 1 || o.BadGames[0] != (BadGame{1, 25, "runs"}) {
		t.Errorf("badgames = %+v", o.BadGames)
	}
	re, ok := o.REAt(State{0, 0})
	if !ok || re.Runs != 19970 || re.N != 40650 || re.Milli == nil || *re.Milli != 491 {
		t.Errorf("RE 0/0 = %+v", re)
	}
	if re, ok := o.REAt(State{4, 1}); !ok || re.Milli != nil {
		t.Errorf("RE 4/1 = %+v, want NA", re)
	}
	if len(o.Transitions) != 1 || o.Transitions[0] != (Transition{State{1, 0}, State{0, 3}, 0, 12}) {
		t.Errorf("transitions = %+v", o.Transitions)
	}
	if len(o.BreakEvens) != 2 || *o.BreakEvens[0].BP != 7325 || o.BreakEvens[1].BP != nil {
		t.Errorf("break-evens = %+v", o.BreakEvens)
	}
	if len(o.DeltaREs) != 1 || o.DeltaREs[0].Value != -2043713 {
		t.Errorf("DRE = %+v", o.DeltaREs)
	}
	if o.Boot != (Boot{1024, 2024, 2429}) {
		t.Errorf("boot = %+v", o.Boot)
	}
	c, ok := o.CIAt("BE", "steal3", State{2, 2})
	if !ok || *c.Lo != 9100 || c.Hi != nil {
		t.Errorf("CI BE steal3 2/2 = %+v", c)
	}
	if c, ok := o.CIAt("RE", "", State{0, 0}); !ok || *c.Lo != 4800000 || *c.Hi != 5000000 {
		t.Errorf("CI RE 0/0 = %+v", c)
	}
}

func TestParseErrorLine(t *testing.T) {
	for _, bad := range []string{"RE 0 0 19970", "XX 1", "RE 0 0 1 2 3 4", "CI RE 0 0 x 5"} {
		_, err := Parse(strings.NewReader("GAMES 1 1 0\n\n" + bad + "\n"))
		if err == nil || !strings.Contains(err.Error(), "line 3:") {
			t.Errorf("%q: err = %v, want line 3", bad, err)
		}
	}
}
