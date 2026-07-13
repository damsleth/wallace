# AGENTS.md — Project Wallace (T6040 / M4 Pro Linux bring-up)

The umbrella project for bringing mainline Linux to an **Apple MacBook Pro 14"
M4 Pro (T6040 "Brava Chop", Mac16,8 / J614s)** — a real, tethered daily-driver
machine. This repo holds all plans, documentation, host-side scripts, and
kernel patches. The code lives in sibling repos under `~/Code/` (below).

**Start here, in this order:**
1. This file (the map).
2. `NEXT_STEPS.md` — what to do next, nothing else.
3. `DEVLOG.md` — how to operate the rig (boot/build recipes, the DebugUSB
   pty-discipline rules — read those BEFORE touching the hardware), solved
   blockers, dead ends.
4. `roadmap.md` — the long game (stages A–H) and the current snapshot.

## The repos

| Path | What | Role here |
|---|---|---|
| `~/Code/wallace` | this repo | plans, docs, scripts/, patches/, dts/, done/ |
| `~/Code/m1n1` | m1n1 fork (branch `main`) | bootloader + proxyclient; per-dir AGENTS.md files carry the **hardware safety rules** and code-level knowledge |
| `~/Code/m1n1-clean` | worktree, branch `t6040-bringup` | curated code-only commit series (upstream-shaped); keep in sync with m1n1 `src/` changes |
| `~/Code/linux` | kernel tree, branch `feature/m4-m5-minimal-device-trees` (yuka) | t6040 DT files live here (partly uncommitted); code changes go via `patches/` applied by kbuild — NOT as tree edits (builds use committed state + copied DT files only) |
| `~/Code/linux-build-out` | build artifacts (`/out` in the kbuild container) | Image/DTBs/initramfs; copy `scripts/t6040-kbuild.sh` + `patches/*.patch` here before building |
| `~/Code/macvdmtool` | patched fork | DebugUSB entry + remote reboot (`sudo -n /usr/local/bin/macvdmtool`, NOPASSWD) |
| `~/Code/kisd` | AsahiLinux/kisd | host daemon bridging DebugUSB → pty (`/tmp/m1n1`) |

## Non-negotiables (full rules in `~/Code/m1n1/AGENTS.md`)

- Never write SPMI/PMU/charger/NVRAM. MMIO writes outside known-safe paths are
  gated on the maintainer. Never blind-probe MMIO offsets — wrong offsets raise
  **async SErrors** that kill m1n1 (derive addresses from the ADT).
- Never post externally (GitHub/IRC) — draft only; the maintainer posts.
- The remote dev loop is sanctioned: reboot/chainload/boot via
  `scripts/t6040-debugusb-console.sh [reboot]` + `scripts/t6040-boot-dcuart.sh`.
  Follow DEVLOG's pty discipline or the link will look dead.

## Host-local agent memory (not in any repo)

`~/.claude/projects/-Users-damsleth-Code-m1n1/memory/` — SMP topology,
broken_wfi, build env, DebugUSB console facts. Verify against reality before
acting; update it when you learn durable facts.
