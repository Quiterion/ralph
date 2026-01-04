# wiggum - Multi-Agent Orchestration Harness
#
# Installation targets

PREFIX ?= /usr/local
BINDIR := $(PREFIX)/bin

.PHONY: install uninstall test check help

help:
	@echo "wiggum - Multi-Agent Orchestration Harness"
	@echo ""
	@echo "Usage:"
	@echo "  make install    Install wiggum (symlink to $(BINDIR))"
	@echo "  make uninstall  Remove wiggum from $(BINDIR)"
	@echo "  make test       Run test suite"
	@echo "  make check      Run shellcheck on all scripts"
	@echo ""
	@echo "Options:"
	@echo "  PREFIX=/path    Install prefix (default: /usr/local)"
	@echo ""
	@echo "Examples:"
	@echo "  make install                  # Install to /usr/local/bin"
	@echo "  make install PREFIX=~/.local  # Install to ~/.local/bin"
	@echo "  sudo make install             # System-wide install"

install:
	@echo "Installing wiggum to $(BINDIR)..."
	@mkdir -p $(BINDIR)
	@ln -sf $(CURDIR)/bin/wiggum $(BINDIR)/wiggum
	@echo "Done. Make sure $(BINDIR) is in your PATH."

uninstall:
	@echo "Removing wiggum from $(BINDIR)..."
	@rm -f $(BINDIR)/wiggum
	@echo "Done."

test:
	@bash tests/test_wiggum.sh

check:
	@shellcheck --severity=warning lib/*.sh tests/*.sh bin/wiggum
	@echo "All checks passed."
