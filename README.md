# Project Wallace

Mainline Linux on a MacBook Pro 14" M4 Pro (t6040 "Brava Chop",
Mac16,8 / J614s). It boots into Alpine/OpenRC with the internal panel,
keyboard, watchdog, and a remote DebugUSB development loop.

This repo is the umbrella. The code lives in four sibling repos and the knowledge kept getting smeared across them so everything that guides the work now lives here: plans, scripts, kernel patches, post-mortems.

## Status (2026-07-24)

The tethered B0 release object now boots a self-contained Alpine 3.24/OpenRC
system from one raw m1n1 object. The internal panel reaches a local shell, the
internal keyboard echoes, the watchdog stays serviced, and the storage-disabled
health report passes. A dual-mode enrollment candidate has also been built; it
still needs independent review and volume identity/backup completion. Its
hardware trigger validation belongs to the maintainer-executed cold-boot
experiment (ticket 101), not the offline preflight. That plan is approved but
remains `runnable=false` until its identity, backup, and review gates close.

Core bring-up is solid: m1n1 sees all 14 active cores, PMGR's 214-domain
topology is understood, Linux boots reliably at `maxcpus=1`, fbcon and
DockChannel polling console work, and the internal keyboard is usable.
The first exact `maxcpus=2` proof (005) reached kernel vectoring but produced
no Linux output, so 122/123 now own the diagnosis/replacement before all-core
120/121 or cpufreq 006. Interrupt-driven DockChannel on measured AIC input 816
has passed with stable bidirectional shell traffic. Trackpad motion remains an
attended physical-input test.

The right-side USB-C path has crossed its first hardware-management boundary.
The exact right HPM2 endpoint accepted WAKEUP, reported state `0x07`, accepted
the public-driver `SSPS` sequence, and reported S0 (`0x00`). That does not yet
establish connector role, VBUS, repeater/ATC PHY, xHCI enumeration, or block
access. The attached memory stick has therefore **not** enumerated on the M4
and has not been written. A host-verified OpenRC GPT/ext4 root image is ready,
but flashing and read-write boot tests remain behind the staged USB link
experiments.

Internal NVMe remains blocked by Apple's SPTM/CoastGuard guarded state. We have
decoded the protected operation contracts, but raw boot has no supported path
to acquire the required execution/domain context. Work here stays static and
host-only unless a documented, non-mutating guarded-entry route appears.

PCIe, which carries WiFi/BT and the SD reader, still stalls at operation 115,
the first PHY-IP PLL read. Ticket 068 proved the newly decoded clkgen sequence
locks its PLL, but the read still hangs; offline ticket 124 owns the next
paired-driver precondition trace.

DebugUSB/KIS remains the practical remote console. The post-SSPS recovery
control passed after a power cycle and several later reboot/reattach cycles
returned healthy proxies. Ticket 118 records the exact fail-closed checklist;
the earlier VDM failure is not attributed to SSPS.

Polling remains the conservative DockChannel fallback, while the corrected
IRQ-816 path is now independently reviewed and live-proven.

The blow-by-blow lives in [DEVLOG.md](docs/DEVLOG.md), and the current plan of attack is [NEXT_STEPS.md](docs/NEXT_STEPS.md).

## The repos

| Path | What |
|---|---|
| `~/Code/wallace` | this repo: docs, `scripts/`, `patches/`, `dts/`, `done/` |
| `~/Code/m1n1` | m1n1 fork (bootloader + proxyclient); safety rules live in its `AGENTS.md` |
| `~/Code/m1n1-clean` | worktree of branch `t6040-bringup`, the curated upstream-shaped commit series |
| `~/Code/linux` | `damsleth/linux` fork, branch `wallace/t6040-bringup`, based on AsahiLinux `asahi-wip`; t6040 DTs live here |
| `~/Code/linux-build-out` | build artifacts, mounted as `/out` in the build container |
| `~/Code/macvdmtool` | patched fork: DebugUSB entry + remote reboot |
| `~/Code/kisd` | AsahiLinux kisd, bridges DebugUSB to a pty on the host |

## The loop

```sh
bash scripts/t6040-debugusb-console.sh reboot   # reboot into m1n1, drain console, attach kisd -> /tmp/m1n1
bash scripts/t6040-boot-dcuart.sh               # chainload m1n1 + boot Linux to a shell on /dev/ttydc0
printf 'uname -a\n' > /tmp/m1n1                 # type into the running machine
tail -f ~/Code/linux-build-out/dcuart-console.log
```

Kernel rebuild (arm64-native in a podman container, because macOS's case-insensitive filesystem corrupts a kernel tree in about four files):

```sh
cp scripts/t6040-kbuild.sh patches/*.patch ~/Code/linux-build-out/
podman exec -e DOCKCHANNEL=1 -e BUILD_DIR=/build/linux-keyboard kbuild \
    bash /out/t6040-kbuild.sh image
```

Before touching any of this, read the pty-discipline rules in [DEVLOG.md](docs/DEVLOG.md). The link looks completely dead if you handle the pty wrong, and we burned an hour learning that.

## Reading order

1. [AGENTS.md](AGENTS.md), the map (repos, roles, hard rules)
2. [NEXT_STEPS.md](docs/NEXT_STEPS.md), the work queue
3. [DEVLOG.md](docs/DEVLOG.md), recipes, solved blockers, dead ends
4. [ROADMAP.md](docs/ROADMAP.md), stages A through H, from first light to daily driver

`done/` holds the finished per-topic plans and session write-ups. They're kept because the dead ends are half the value: SBU serial, RAM-dump post-mortems, and per-domain pmgr bisection are all documented graves, so nobody digs them up twice.
