PREFIX ?= $(HOME)/.local
SHARE_DIR ?= $(PREFIX)/share/raff-module
BIN_DIR ?= $(PREFIX)/bin

.PHONY: help test lint install uninstall

help:
	@printf 'Targets:\n'
	@printf '  make test       Run the smoke test suite\n'
	@printf '  make lint       Check shell syntax\n'
	@printf '  make install    Install to $(PREFIX)\n'
	@printf '  make uninstall  Remove the installed copy\n'

test:
	./tests/run.sh

lint:
	bash -n raff-module
	bash -n lib/*.sh
	bash -n tests/run.sh
	bash -n install.sh

install:
	PREFIX="$(PREFIX)" SHARE_DIR="$(SHARE_DIR)" BIN_DIR="$(BIN_DIR)" ./install.sh

uninstall:
	rm -f "$(BIN_DIR)/raff-module"
	rm -rf "$(SHARE_DIR)"
	@printf 'Removed %s\n' "$(SHARE_DIR)"
