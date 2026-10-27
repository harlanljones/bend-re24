BEND ?= $(HOME)/.bend/bin/bend
YEAR = 2024
RETRO_SHA = 118094bb3fc2ca292c25fccf54e7541762887bf6
CHADWICK_VER = 0.11.0
CHADWICK_SHA256 = c80d24dfd37707719c3e81883417a57339c4d60865e39ae73aebdbbfe2190259
CWEVENT = .tools/chadwick/bin/cwevent
SEED ?= 2024

BEND_SRC = main.bend $(wildcard src/*.bend)

.PHONY: fetch ingest build proofs run check

build: bin/re24

bin/re24: $(BEND_SRC)
	mkdir -p bin
	$(BEND) main.bend -o bin/re24

proofs:
	BEND=$(BEND) ./check.sh

check:
	BEND=$(BEND) ./check.sh && go test ./...

run: bin/re24 data/plays-$(YEAR).csv
	mkdir -p out
	bin/re24 run data/plays-$(YEAR).csv > out/run-$(YEAR).txt

$(CWEVENT):
	mkdir -p .tools/src
	curl -fsSL -o .tools/src/chadwick-$(CHADWICK_VER).tar.gz \
	  https://github.com/chadwickbureau/chadwick/releases/download/v$(CHADWICK_VER)/chadwick-$(CHADWICK_VER).tar.gz
	cd .tools/src && echo "$(CHADWICK_SHA256)  chadwick-$(CHADWICK_VER).tar.gz" | sha256sum -c -
	cd .tools/src && tar xzf chadwick-$(CHADWICK_VER).tar.gz
	cd .tools/src/chadwick-$(CHADWICK_VER) && ./configure --prefix=$(abspath .tools/chadwick) --disable-shared && $(MAKE) && $(MAKE) install

fetch: data/raw/$(YEAR)/TEAM$(YEAR)

data/raw/$(YEAR)/TEAM$(YEAR):
	ingest/fetch.sh $(RETRO_SHA) $(YEAR) data/raw/$(YEAR)

ingest: data/plays-$(YEAR).csv

data/cwevent-$(YEAR).csv: $(CWEVENT) data/raw/$(YEAR)/TEAM$(YEAR)
	cd data/raw/$(YEAR) && $(abspath $(CWEVENT)) -Q -n -y $(YEAR) -f 0,1,2,4,34,35,40,58-61 -x 3,13,14,45,55 $(YEAR)*.EV? > ../../cwevent-$(YEAR).csv

data/plays-$(YEAR).csv: data/cwevent-$(YEAR).csv ingest/main.go
	go run ./ingest -in data/cwevent-$(YEAR).csv -plays data/plays-$(YEAR).csv -games data/games-$(YEAR).csv
