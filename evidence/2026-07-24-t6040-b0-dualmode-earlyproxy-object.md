# T6040 B0 dual-mode (EARLY_PROXY_TIMEOUT) object — build + provenance (2026-07-24)

Goal (maintainer request): a B0 enrollment object that gives **both worlds** —
a normal cold boot auto-boots Alpine untethered, *and* a `macvdmtool reboot
debugusb` boot opens an m1n1 proxy window so the fast chainload/debug loop
survives. This replaces `2371ee5d` (pure auto-boot) as the enrollment candidate
for tickets 082/101, **pending Sol cross-review and the on-M4 trigger validation
below**. Offline build only; nothing touched the rig or the M4.

## The mechanism (already in m1n1)

`src/main.c` `run_actions()`, gated on `#ifdef EARLY_PROXY_TIMEOUT`:

```c
if (!cur_boot_args.video.display && lp_sip0 == 127) {
    // usb_init(); wait EARLY_PROXY_TIMEOUT s for a proxy connection
    //   connected → uartproxy_run(); return   (host takes over — chainload/debug)
    //   timed out → fall through to payload_run() (auto-boot the embedded Alpine)
}
```

- **Normal cold boot** (boot picker, lid open → `video.display` set) → condition
  false → window skipped → auto-boots Alpine. Untethered, instant.
- **`macvdmtool reboot debugusb`** (headless dev boot → no display, Permissive
  `lp-sip0==127`) → opens the window → connect the proxy and chainload as today.

This is the upstream Asahi release-m1n1 mechanism (end-user boot auto-continues,
DFU/dev boot waits for proxy). Worst case if the normal cold boot were to report
no-display: a 5 s delay before auto-boot (no host connected → timeout), never a
lockout — so the untethered milestone is robust regardless.

## Provenance — the delta is exactly one compile define

| Artifact | SHA-256 | Note |
|---|---|---|
| base m1n1 `1394c345` (reproduced) | `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b` | clean `make` at `a61fd099` reproduced it **byte-for-byte** |
| **dual-mode m1n1** | `11f6fbf1d9bfd4b5d4ea6308444beffc8063446553d48791c3a34e20c1458b91` | same source + `EXTRA_CFLAGS=-DEARLY_PROXY_TIMEOUT=5`; **byte-reproducible** across two clean builds |
| **dual-mode B0 object** | `46237ade7e314cd752e1482930e21b62319e1b0b707a0f23e86392701555f0c9` | 22,183,563 B, entry 0x800; **byte-reproducible** |

Build recipe (worktree `/private/tmp/m1n1-earlyproxy` at detached `a61fd099`):

```sh
# nightly is required; the rustup DEFAULT is stale 1.58.0 and fails on dep: features
export PATH="$HOME/.cargo/bin:$PATH" RUSTUP_TOOLCHAIN=nightly
make clean
EXTRA_CFLAGS="-Wstack-usage=2048 -DEARLY_PROXY_TIMEOUT=5" make -j8   # → build/m1n1.bin
```

Why the delta is provably minimal:

- Clean `make` at `a61fd099` (default config) reproduces `1394c345` **exactly**
  — so the base recipe is confirmed, and "logbuf/upper-guard/dryrun" were just
  descriptive names for the `a61fd099` source (no special flags).
- The dual-mode build changes only `EXTRA_CFLAGS` (adds `-DEARLY_PROXY_TIMEOUT=5`;
  `-Wstack-usage=2048` is the codegen-neutral default warning flag, preserved).
- The git tree stays clean, so the embedded version tag is **unchanged**:
  `##m1n1_ver##v1.6.0-75-ga61fd099` on both. The new binary simply gains the
  `EARLY_PROXY_TIMEOUT` block (verified: it contains the `Waiting for proxy
  connection` string; `1394c345` does not) and is the same size (1,097,728 B).

## Object provenance — identical to the proven object except the prefix

Built with `scripts/t6040-build-raw-object.py` feeding the **exact** ticket-100
members (the packer uses a pre-gzipped kernel verbatim):

- kernel `d76463e5…` (078 HID-fix), DTB `2782b922…` (storage-disabled),
  initramfs `ddd98171…` (OpenRC B0 root, 699 entries / 0 block nodes),
  bootargs `3659a0da…` (`… rdinit=/sbin/init maxcpus=1 idle=nop`, no
  root/USB/SMP/PCIe/storage).
- Strict verifier: **PASS** (all member offsets/hashes, entry 0x800, 64 MiB
  policy, reserve 67,911,671 B).
- **`cmp` proof:** every byte after the 1,097,728 B m1n1 prefix is **byte-for-byte
  identical to `2371ee5d`**. The dual-mode object is the ticket-100 release
  object with only the m1n1 prefix swapped — so the entire live-proven userland
  and boot payload are unchanged.

## Required before enroll/cold boot

1. **Sol cross-review** (COORDINATION.md two-model gate; I am the author). Suggested
   check, mirroring the R0 review: rebuild `a61fd099` + `-DEARLY_PROXY_TIMEOUT=5`
   in a fresh tree, reproduce `11f6fbf1` and `46237ade`, and confirm the base
   reproduces `1394c345`, i.e. the delta is exactly the define.
2. **On-M4 trigger validation** (part of the ticket-101 cold-boot session, with
   the maintainer present):
   - normal boot-picker cold boot (panel/lid open) → **auto-boots Alpine, no
     proxy wait** (display present → window skipped);
   - `macvdmtool reboot debugusb` → **the ~5 s proxy window opens** and a proxy
     connects (headless → window opens). If the debugusb path unexpectedly
     reports display-present, the window won't open; fall back is the pure
     auto-boot `2371ee5d` plus rollback, or a two-volume split — the untethered
     milestone itself is unaffected.

## Enrollment-candidate update

Tickets 082/101 should enroll **`46237ade`** (this dual-mode object), not
`2371ee5d`, once (1) and (2) pass. The 082 procedure is otherwise unchanged: same
`kmutil configure-boot --raw --entry-point 2048 --lowest-virtual-address 0 -v
/Volumes/m1n1`, same identity guard, same `1394c345` rollback object, same
boot-picker cold boot. `EARLY_PROXY_TIMEOUT=5` is a first tunable; bump if 5 s
proves too short for the debug proxy to connect (it only affects the debug path,
never the untethered boot time).

Artifacts staged in `linux-build-out/`:
`m1n1-t6040-earlyproxy5-a61fd099.bin` (`11f6fbf1`),
`m1n1-b0-alpine-openrc-earlyproxy.bin` (`46237ade`).
