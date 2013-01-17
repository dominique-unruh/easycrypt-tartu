# -*- Makefile -*-

# --------------------------------------------------------------------
CONFIG           = _tags myocamlbuild.ml
OCAMLBUILD_BIN   = ocamlbuild
OCAMLBUILD_EXTRA = -classic-display

# In Emacs, use classic display to enable error jumping.
ifeq ($(shell echo $$TERM), dumb)
 OCAMLBUILD_EXTRA += -classic-display
endif
OCAMLBUILD := $(OCAMLBUILD_BIN) $(OCAMLBUILD_EXTRA)

# --------------------------------------------------------------------
.PHONY: all build byte native check clean tags
.PHONY: %.ml

all: build

build: byte

byte: tags
	$(OCAMLBUILD) src/ec.byte

native: tags
	$(OCAMLBUILD) src/ec.native

check: byte
	./scripts/runtest.py     \
	  --bin=./ec.byte        \
	  --ok-dir=tests/success \
	  --ok-dir=theories      \
	  --ko-dir=tests/fail

clean:
	$(OCAMLBUILD) -clean
	set -e; for i in $(CONFIG); do [ \! -h "$$i" ] || rm -f "$$i"; done

tags:
	set -e; for i in $(CONFIG); do [ -e "$$i" ] || ln -s config/"$$i" $$i; done

# --------------------------------------------------------------------
%.ml:
	$(OCAMLBUILD) src/$*.cmo