# Thin facade over stl.ps1 for people used to make: every target calls the CLI.
# The real logic lives in stl.ps1 / tools/lib; use ".\stl.ps1 <command>" directly without make.

STL := powershell -NoProfile -ExecutionPolicy Bypass -File stl.ps1

.PHONY: all build scripts strings ui link unlink run package clean distclean doctor help

all: build

build:
	$(STL) build all

scripts strings ui:
	$(STL) build $@

link unlink run package clean doctor help:
	$(STL) $@

distclean:
	$(STL) clean -All
