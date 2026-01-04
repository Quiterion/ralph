# ralphs - Multi-Agent Orchestration Harness
#
# Installation targets

PREFIX ?= /usr/local
BINDIR := $(PREFIX)/bin

.PHONY: install uninstall test check help

help:
	@echo "ralphs - Multi-Agent Orchestration Harness"
	@echo ""
	@echo "Usage:"
	@echo "  make install    Install ralphs (symlink to $(BINDIR))"
	@echo "  make uninstall  Remove ralphs from $(BINDIR)"
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
	@echo "Installing ralphs to $(BINDIR)..."
	@mkdir -p $(BINDIR)
	@ln -sf $(CURDIR)/bin/ralphs $(BINDIR)/ralphs
	@echo "Done. Make sure $(BINDIR) is in your PATH."

uninstall:
	@echo "Removing ralphs from $(BINDIR)..."
	@rm -f $(BINDIR)/ralphs
	@echo "Done."

test:
	@bash tests/test_ralphs.sh

check:
	@shellcheck --severity=warning lib/*.sh tests/*.sh bin/ralphs
	@echo "All checks passed."
