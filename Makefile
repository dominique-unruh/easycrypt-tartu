# -*- Makefile -*-

# --------------------------------------------------------------------
OCAMLBUILD_BIN   = ocamlbuild -use-ocamlfind
OCAMLBUILD_EXTRA = -classic-display

# In Emacs, use classic display to enable error jumping.
ifeq ($(shell echo $$TERM), dumb)
 OCAMLBUILD_EXTRA += -classic-display
endif
ifeq ($(LINT),1)
 OCAMLBUILD_EXTRA += -tag lint
endif

OCAMLBUILD := $(OCAMLBUILD_BIN) $(OCAMLBUILD_EXTRA)

DESTDIR    ?=
PREFIX     ?= /usr/local
VERSION    ?= $(shell date '+%F')
DISTDIR    := easycrypt-$(VERSION)
INSTALL    := scripts/install/install-sh
PWD        := $(shell pwd)

include Makefile.system

# --------------------------------------------------------------------
BINDIR := $(PREFIX)/bin
LIBDIR := $(PREFIX)/lib/easycrypt
SYSDIR := $(LIBDIR)/system

# --------------------------------------------------------------------
XUNITOUT ?= xunit.xml
ECARGS   ?=
ECTOUT   ?= 3
CHECK    := scripts/testing/runtest
CHECK    += --bin-args="$(ECARGS)" --timeout="$(ECTOUT)"
CHECK    += config/tests.config

# --------------------------------------------------------------------
.PHONY: all build byte native tests check check-xunit examples
.PHONY: clean install uninstall uninstall-purge dist distcheck
.PHONY: callprover pg toolchain update-toolchain provers
.PHONY: %.ml %.mli %.inferred.mli

all: build
	@true

build: callprover native

define do-build
	rm -f "$(1)$(EXE)"
	$(OCAMLBUILD) "src/$(1)"
	if [ ! -z "$(EXE)" ]; then \
	  cp "_build/src/$(1)" "$(1)$(EXE)"; \
	fi
endef

byte:
	$(call do-build,ec.byte)

native:
	$(call do-build,ec.native)

callprover:
	$(MAKE) -C system

define check-for-staled-files
	if [ -d "$(DESTDIR)$(PREFIX)/lib/easycrypt/" ]; then   \
	  cd "$(DESTDIR)$(LIBDIR)/" &&           \
	    find theories -type f -name '*.ec' 2>/dev/null |   \
	    sed 's/^/!! FOUND STALED FILE: /';                 \
	fi
endef

install: ec.native uninstall
	-@$(call check-for-staled-files)
	$(INSTALL) -m 0755 -d $(DESTDIR)$(BINDIR)
	$(INSTALL) -m 0755 -T ec.native $(DESTDIR)$(BINDIR)/easycrypt$(EXE)
	$(INSTALL) -m 0755 -d $(DESTDIR)$(SYSDIR)
	$(INSTALL) -m 0755 -T system/callprover$(EXE) $(DESTDIR)$(SYSDIR)/callprover$(EXE)
	for i in $$(find theories -type d); do \
	  $(INSTALL) -m 0755 -d $(DESTDIR)$(LIBDIR)/$$i ';'; \
	  $(INSTALL) -m 0644 -t $(DESTDIR)$(LIBDIR)/$$i $$i/*.ec; \
	done

define rmdir
	-@if [ -d "$(1)" ]; then rmdir "$(1)"; fi
endef

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/easycrypt
	rm -f $(DESTDIR)$(SYSDIR)/callprover
	$(call rmdir,$(DESTDIR)$(SYSDIR))
	for i in $$(find theories -depth -type d); do \
	  for j in $$i/*.ec; do rm -f $(DESTDIR)$(LIBDIR)/$$j; done; \
	  rmdir $(DESTDIR)$(LIBDIR)/$$i 2>/dev/null || true; \
	done

uninstall-purge:
	rm  -f $(DESTDIR)$(BINDIR)/easycrypt
	rm -rf $(DESTDIR)$(LIBDIR)

tests: check

examples:
	$(CHECK) examples

fullcheck: ec.native
	$(CHECK) prelude core theories realized examples unit

check: ec.native
	$(CHECK) prelude theories realized unit

check-xunit: ec.native
	$(CHECK) --xunit="$(XUNITOUT)" prelude core theories realized unit

checklibs: ec.native
	$(CHECK) --xunit=libresults.xml prelude core theories realized

clean:
	$(OCAMLBUILD) -clean
	rm -f ec.native ec.byte
	rm -f ec.native.exe ec.byte.exe
	$(MAKE) -C system clean

# --------------------------------------------------------------------
dist:
	if [ -e $(DISTDIR) ]; then rm -rf $(DISTDIR); fi
	./scripts/install/distribution $(DISTDIR) MANIFEST
	BZIP2=-9 tar -cjf $(DISTDIR).tar.bz2 --owner=0 --group=0 $(DISTDIR)
	rm -rf $(DISTDIR)

distcheck: dist
	tar -xof $(DISTDIR).tar.bz2
	set -x; \
	     $(MAKE) -C $(DISTDIR) \
	  && $(MAKE) -C $(DISTDIR) dist \
	  && mkdir $(DISTDIR)/dist1 $(DISTDIR)/dist2 \
	  && ( cd $(DISTDIR)/dist1 && tar -xof ../$(DISTDIR).tar.bz2 ) \
	  && ( cd $(DISTDIR)/dist2 && tar -xof ../../$(DISTDIR).tar.bz2 ) \
	  && diff -rq $(DISTDIR)/dist1 $(DISTDIR)/dist2 \
	  || exit 1
	rm -rf $(DISTDIR)
	@echo "$(DISTDIR) is ready for distribution" | \
	  sed -e 1h -e 1s/./=/g -e 1p -e 1x -e '$$p' -e '$$x'

# --------------------------------------------------------------------
%.ml:
	$(call do-build,src/$*.cmo)

# --------------------------------------------------------------------
%.mli:
	$(call do-build,src/$*.cmi)

# --------------------------------------------------------------------
%.inferred.mli:
	$(call do-build,src/$@) && cat _build/src/$@

# --------------------------------------------------------------------
pg:
	@if [ "$$EC_TOOLCHAIN_ACTIVATED" = "" -a -d _tools ]; then \
	  EC_SRC_ROOT="$(PWD)/scripts" \
	    . ./scripts/activate-toolchain.sh 2>/dev/null; \
	  if [ "$$EC_TOOLCHAIN_ACTIVATED" = "" ]; then \
	    echo "Toolchain activation failed" >&2; \
	  fi; \
	fi; $(MAKE) -C proofgeneral run-local

# --------------------------------------------------------------------
toolchain:
	export OPAMVERBOSE=1; bash ./scripts/toolchain/ec-build-toolchain

update-toolchain:
	@[ "$$EC_TOOLCHAIN_ACTIVATED" != "" ] || { \
	  echo "Activate the EasyCrypt toolchain first" >&2; false; \
	}
	export OPAMVERBOSE=1; \
             opam update  -y \
	  && opam remove  -y ec-toolchain \
	  && opam install -y ec-toolchain

provers:
	@[ "$$EC_TOOLCHAIN_ACTIVATED" != "" ] || { \
	  echo "Activate the EasyCrypt toolchain first" >&2; false; \
	}
	export OPAMVERBOSE=1; \
	     opam update  -y \
	  && opam remove  -y ec-provers \
	  && opam install -y ec-provers \
	  && rm -f _tools/why3.local.conf \
	  && why3config --detect -C _tools/why3.local.conf
