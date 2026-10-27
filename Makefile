BEND ?= $(HOME)/.bend/bin/bend
YEAR = 2024
RETRO_SHA = 118094bb3fc2ca292c25fccf54e7541762887bf6
CHADWICK_VER = 0.11.0
CHADWICK_SHA256 = c80d24dfd37707719c3e81883417a57339c4d60865e39ae73aebdbbfe2190259
CWEVENT = .tools/chadwick/bin/cwevent
SEED ?= 2024

.PHONY: fetch

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
