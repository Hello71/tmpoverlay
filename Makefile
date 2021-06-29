prefix ?= /usr/local
bindir ?= $(prefix)/bin

tmpoverlay: tmpoverlay.sh
	sed -e '1p;1t;/^ *#.*/d' $< > $@
	chmod +x $@

clean:
	rm -f tmpoverlay

install:
	install -Dm755 tmpoverlay $(DESTDIR)$(bindir)/tmpoverlay

.PHONY: clean install
