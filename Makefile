#
# Makefile to build BabaChess in a standard GNU/Make environment.
#
# BabaChess is Ada 2012 + C, built with gprbuild; this Makefile is a thin
# driver over gprbuild that adds host-CPU detection and ISA selection, in the
# spirit of the RubiChess Makefile. gprbuild stays the source of truth for
# the compile/link flags (see babachess.gpr); the Makefile only supplies the
# CPU-dependent switches through the BABA_ARCH_FLAGS project external.
#
# Targets:
#   make                 release build, ISA detected from the host CPU
#   make release         same as above
#   make portable        generic x86-64 build (software PEXT, no BMI2/POPCNT)
#   make debug           assertions + all warnings (the only mode with them)
#   make ARCH=native     force -march=native instead of the detected level
#   make ARCH=v3         force an x86-64 level (v1..v4)
#   make ARCH=skylake    force any GCC -march= name
#   make ARCH=generic    no extra ISA switch (the .gpr default)
#   make test            build release and run --selftest
#   make bench [DEPTH=9] build release and run --bench
#   make info            show the detected CPU and chosen switches
#   make clean           remove obj/ and bin/
#   make help            this help
#
# Notes:
#   * "release"/"portable" share obj/ through gprbuild: every build starts
#     from a clean obj/ so switching modes never links stale objects.
#   * There is no PGO target: a measured attempt was slower than the plain
#     -O3 build (see src/doc/build-and-cpu.md), so it is not offered.
#

MAKEFLAGS += --no-print-directory

# --- Toolchain ------------------------------------------------------------
GPRBUILD ?= gprbuild
GPR      ?= babachess.gpr
GCC      ?= gcc
OBJ_DIR  ?= obj
BIN_DIR  ?= bin
EXE      ?= $(BIN_DIR)/babachess

# --- CPU detection --------------------------------------------------------
# ARCH controls the extra ISA switches handed to the compiler:
#   auto    (default) pick the best x86-64-vN level the CPU supports
#   native  pass -march=native (measured slower here; opt in explicitly)
#   v1..v4  force an x86-64 level
#   generic no extra switch
#   <name>  any GCC -march= argument (skylake, haswell, znver3, ...)
ARCH ?= auto

# Probe the host CPU once. We map it to the portable x86-64-vN levels rather
# than using -march=native: -march=native also sets -mtune=<this exact CPU>,
# which measured ~2.5% SLOWER than the level switches (which keep
# -mtune=generic). See src/doc/build-and-cpu.md.
HOST_MACROS := $(shell $(GCC) -march=native -dM -E - </dev/null 2>/dev/null)
ifneq (,$(findstring __AVX512F__,$(HOST_MACROS)))
  DETECTED_LEVEL := v4
else ifneq (,$(findstring __AVX2__,$(HOST_MACROS)))
  DETECTED_LEVEL := v3
else ifneq (,$(findstring __SSE4_2__,$(HOST_MACROS)))
  DETECTED_LEVEL := v2
else
  DETECTED_LEVEL := v1
endif

ifeq ($(ARCH),auto)
  ARCH_SEL := x86-64-$(DETECTED_LEVEL)
else
  ARCH_SEL := $(ARCH)
endif

ifeq ($(ARCH_SEL),generic)
  ARCH_FLAGS :=
else
  ARCH_FLAGS := -march=$(ARCH_SEL)
endif

ARCH_OPT := $(if $(strip $(ARCH_FLAGS)),-XBABA_ARCH_FLAGS=$(ARCH_FLAGS),)

# Build from a clean obj/: gprbuild resolves -gnatep relative to the object
# directory and the mode switches differ, so a shared obj/ would be unsound.
define do_build
	rm -rf $(OBJ_DIR)
	$(GPRBUILD) -P $(GPR) -XMode=$(1) $(ARCH_OPT)
endef

.PHONY: all release portable debug test bench info clean help

all: release

release:
	@echo "== BabaChess release ($(ARCH_SEL)$(if $(ARCH_FLAGS), : $(ARCH_FLAGS))) =="
	$(call do_build,release)
	@echo "   -> $(EXE)"

portable:
	@echo "== BabaChess portable (generic x86-64) =="
	$(call do_build,portable)
	@echo "   -> $(EXE)"

debug:
	@echo "== BabaChess debug (assertions + warnings) =="
	$(call do_build,debug)
	@echo "   -> $(EXE)"

test: release
	$(EXE) --selftest

bench: release
	$(EXE) --bench $(if $(DEPTH),$(DEPTH),9)

info:
	@echo "GPRBUILD : $(GPRBUILD)"
	@echo "ARCH     : $(ARCH_SEL)"
	@echo "ARCHFLAGS: $(if $(ARCH_FLAGS),$(ARCH_FLAGS),<none>)"
	@echo "detected : x86-64-$(DETECTED_LEVEL) (probe: $(GCC) -march=native)"

clean:
	rm -rf $(OBJ_DIR) $(BIN_DIR)

help:
	@echo "BabaChess build targets"
	@echo "  make [ARCH=...]   release build (default: ISA auto-detected)"
	@echo "  make portable     generic x86-64 (software PEXT)"
	@echo "  make debug        assertions + all warnings"
	@echo "  make test         release + --selftest"
	@echo "  make bench        release + --bench [DEPTH=n]"
	@echo "  make info         show the detected CPU / chosen switches"
	@echo "  make clean        remove obj/ and bin/"
	@echo ""
	@echo "ARCH picks the ISA switches: auto (default), generic, native,"
	@echo "v2/v3/v4 (x86-64 levels) or any GCC -march= name (skylake, ...)."
	@echo "See src/doc/build-and-cpu.md for the measured trade-offs."
