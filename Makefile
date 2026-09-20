# avoe - build, test and install
#
#   make                                 build bin/avoe
#   make test                            run the test suite
#   make screenshots                     remake the README pictures
#   make format                          reformat the C sources now (clang-format)
#   sudo make install                    install under /usr/local
#   make install PREFIX=~/.local         install for yourself, no root needed
#   make install DESTDIR=pkg PREFIX=/usr stage files for a package

PREFIX     ?= /usr/local
DESTDIR    ?=
BINDIR     ?= $(PREFIX)/bin
DATADIR    ?= $(PREFIX)/share/avoe
DOCDIR     ?= $(PREFIX)/share/doc/avoe
MANDIR     ?= $(PREFIX)/share/man/man1
# Packages installed to /usr keep their configuration in /etc
SYSCONFDIR ?= $(if $(filter /usr,$(PREFIX)),/etc,$(PREFIX)/etc)

INSTALL ?= install

.PHONY: all clean run test install uninstall screenshots format format-soft

# The C sources are formatted before each build when clang-format is
# installed.  Turn it off with: make AUTOFORMAT=no
AUTOFORMAT ?= yes

all: $(if $(filter yes,$(AUTOFORMAT)),format-soft)
	gprbuild -p -P avoe.gpr

format-soft:
	@command -v clang-format >/dev/null 2>&1 && clang-format -i src/*.c || true

test: all
	cd tests && for t in test_basics test_editing test_scripts test_modes test_c_mode \
	                     test_python_shell test_install test_safety test_minibuffer \
	                     test_regex test_editing2 test_shell test_ada_tools \
	                     test_script_data test_robustness test_editing3 test_exit test_line_numbers test_startup test_integrity \
	                     test_keyboard_model test_fuzz; do \
	  echo "== $$t"; python3 $$t.py || exit 1; done

install: all
	$(INSTALL) -d $(DESTDIR)$(BINDIR) $(DESTDIR)$(DATADIR) $(DESTDIR)$(DOCDIR) \
	              $(DESTDIR)$(MANDIR) $(DESTDIR)$(SYSCONFDIR)/avoe
	$(INSTALL) -m 755 bin/avoe $(DESTDIR)$(BINDIR)/avoe
	rm -f $(DESTDIR)$(DATADIR)/*.avoe
	$(INSTALL) -m 644 share/avoe/*.avoe $(DESTDIR)$(DATADIR)/
	$(INSTALL) -m 644 README.md CHANGELOG.md LICENSE docs/avoe-script.md examples/avoerc.avoe $(DESTDIR)$(DOCDIR)/
	$(INSTALL) -m 644 docs/avoe.1 $(DESTDIR)$(MANDIR)/avoe.1
	@if [ -e $(DESTDIR)$(SYSCONFDIR)/avoe/site.avoe ]; then \
	  echo "Keeping existing $(DESTDIR)$(SYSCONFDIR)/avoe/site.avoe"; \
	else \
	  $(INSTALL) -m 644 etc/site.avoe $(DESTDIR)$(SYSCONFDIR)/avoe/site.avoe; \
	fi

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/avoe $(DESTDIR)$(MANDIR)/avoe.1
	rm -rf $(DESTDIR)$(DATADIR) $(DESTDIR)$(DOCDIR)
	@echo "Kept the site configuration in $(DESTDIR)$(SYSCONFDIR)/avoe"

format:
	@command -v clang-format >/dev/null || { echo "clang-format is not installed"; exit 1; }
	clang-format -i src/*.c
	@echo "Formatted src/*.c with the rules in .clang-format"

screenshots: all
	python3 tools/screenshot.py

clean:
	gprclean -P avoe.gpr

run: all
	./bin/avoe
