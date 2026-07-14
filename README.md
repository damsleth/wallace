# Project Wallace

Mainline Linux on a MacBook Pro 14" M4 Pro (t6040 "Brava Chop", Mac16,8 / J614s). It boots. BusyBox userspace, working internal keyboard, and a fully remote dev loop over a single USB-C cable: reboot, chainload, boot, interactive shell, all from the host, no fingers on the power button.

This repo is the umbrella. The code lives in four sibling repos, and the knowledge kept getting smeared across them, so everything that guides the work now lives here: plans, scripts, kernel patches, post-mortems.

## Status (2026-07-12)

Works: raw boot via m1n1 (kmutil raw enrollment, SPTM allows nothing else), all 14 cores in the proxy, BusyBox shell on mainline 7.2-rc2 plus 3 small patches, internal keyboard, watchdog handover, fbcon on the panel, and a two-way serial console over DebugUSB (`/dev/ttydc0`).

The current blocker is pmgr: the full 214-domain power-domain DT hangs the kernel before any console exists. That fight is documented in [DEVLOG.md](docs/DEVLOG.md), and the plan of attack is [NEXT_STEPS.md](docs/NEXT_STEPS.md).

The console deserves a sentence. M4 raw-boot has no serial port, no hypervisor tricks (SPTM killed those), and the SBU pins are a confirmed dead end on ACE3. The one path is DebugUSB/KIS through the DFU port.

Linux currently polls the DebugUSB DockChannel FIFO every 5 ms. The earlier
"dead interrupt" conclusion is provisional: its 4096-input AIC scan used MTP's
RX BIT(3), while new evidence identifies UART RX as BIT(1). One bounded BIT(1)
run still produced TX-only output, but could not report whether IRQ 360 fired.
Polling remains the proven fallback while a TX-only counter diagnostic is
prepared.

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

## A warning

This is a real, tethered daily-driver machine, and M4 raw-boot punishes curiosity: a read from the wrong MMIO offset raises an async SError that kills the bootloader outright. Addresses come from the ADT, never from sweeping. The full rules are in `~/Code/m1n1/AGENTS.md` and they're binding.

## Standing on shoulders

None of this happens without [Asahi Linux](https://asahilinux.org/) (m1n1, kisd, a decade of collective RE), yuka's minimal M4/M5 device trees, and flokli's t6040 groundwork. The goal is to feed everything back upstream.
