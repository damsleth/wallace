# XNU-shim (M4 internal-NVMe route) — scaffold build.
#
# This does NOT build a loadable kext yet: Phase 2 needs the Apple kernelcache/kext toolchain
# and a Permissive-Security signing path that does not exist on this project (docs/signing-path.md).
# For now `make check` only syntax-checks the skeleton against the interface header so the
# offline foundation stays consistent as tickets 051/053 fill in the TBDs.
#
# Real kext build (future, Phase 2): -target arm64-apple-macos, no libc, kernelcache-linked.

CC      ?= clang
CFLAGS  := -Iinclude -Wall -Wextra -ffreestanding -fno-builtin -std=c11 -target arm64-apple-macos11
SRCS    := $(wildcard src/*.c)

.PHONY: check
check:                       ## syntax-only check of the skeleton (no linking, no kext)
	@for f in $(SRCS); do echo "  CHECK $$f"; $(CC) $(CFLAGS) -fsyntax-only $$f || exit 1; done
	@echo "OK — skeleton consistent with include/sptm_nvme_iface.h"

.PHONY: help
help:
	@echo "make check   syntax-check the P0 skeleton (does not build a kext)"
