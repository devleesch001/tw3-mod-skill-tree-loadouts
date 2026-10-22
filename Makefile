# Thin facade over cli.ps1 for people used to make: every target calls the CLI.
# The real logic lives in cli.ps1 / tools/lib; use ".\cli.ps1 <command>" directly without make.

CLI := powershell -NoProfile -ExecutionPolicy Bypass -File cli.ps1

.PHONY: all build scripts strings ui link unlink run package clean distclean doctor help

all: build

build:
	$(CLI) build all

scripts strings ui:
	$(CLI) build $@

link unlink run package clean doctor help:
	$(CLI) $@

distclean:
	$(CLI) clean -All
