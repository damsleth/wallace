# T6040 Alpine HID trace auto-reporter

Date: 2026-07-23  
Offline ticket: 075  
Result: **implemented and host-verified; no rig run**

## Purpose

Ticket 074 proved that the observation image can transmit the Alpine banner
and prompt over ttydc0, but ttydc0 RX would not accept the first approved
command. This replacement removes that dependency. It automatically emits the
same bounded read-only inventory over the already-working TX path only when
the exact kernel command-line token below is present:

```text
t6040.hid_trace_auto=1
```

Without that token the helper exits silently and the existing interactive
shell behavior continues.

## Bounded report

After ttydc0 is open and a fixed two-second delay, the reporter prints:

- kernel and Alpine release/architecture;
- at most the last 200 `HIDTRACE` kernel-log lines;
- every readable sysfs file named `dc_trace` or `hid_trace`;
- `/proc/bus/input/devices`;
- an `ls -la` inventory of `/dev/input`;
- `/proc/partitions`;
- explicit begin/end markers.

It does not load modules, discover or mount storage, configure networking,
probe hardware, write sysfs, access MMIO, or change any kernel code or control
flow. The initramfs still mounts only proc, sysfs, devtmpfs, and its existing
RAM-backed tmpfs mounts.

## Implementation and host checks

The reporter is installed as
`/usr/local/sbin/t6040-hid-trace-auto-report` and runs synchronously before the
DockChannel shell is spawned, preventing shell output from interleaving with
the bounded report.

`scripts/t6040-test-hid-trace-auto-report.sh` builds a temporary fake proc,
sysfs, and device inventory. It verified:

- no output without the bootarg;
- begin/end markers with the bootarg;
- both bounded `HIDTRACE` fixtures;
- both `dc_trace` and `hid_trace` fixtures;
- input-device, `/dev/input`, and partition fixtures.

The gate test also rejects a near-name and value `10`, and a 205-line fixture
confirms that only the last 200 matching log lines are emitted. `sh -n`,
`bash -n`, ShellCheck (when installed), and `git diff --check` pass.
The build script now creates `/usr/local/sbin`, requires the helper in the
archive inventory, and derives the contents-list name from `DEST` so this
variant does not overwrite the standard inventory. It writes to a sibling
temporary file, validates the gzip stream, and atomically renames it over
`DEST`, preventing readers from observing a partial rebuild.

## Exact reproducible artifact

Two consecutive builds with:

```sh
DEST=/Users/damsleth/Code/linux-build-out/initramfs-alpine-hid-trace-auto.cpio.gz \
    scripts/t6040-build-alpine-ramroot.sh
```

produced the same initramfs hash. The existing ticket-074 RAM-root remains
unchanged at `fc473c67672cd1596fac133759ed1b3ba18c716f42a400e3cfab9d4ad59cbb9b`.

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `scripts/t6040-init-alpine-ramroot` | — | `24a5106f50e1b42c8c93725b0afd07c064267407f18af6dfac412c4e8cec5cd8` |
| `scripts/t6040-hid-trace-auto-report` | — | `7cea5aaae62887bf0881d4e8c7a1f288e0d387729ce7ac1a4d5032c30458c0b0` |
| `scripts/t6040-build-alpine-ramroot.sh` | — | `641cba1597171ed8e42563d8d27aa03947953a03bb64f27bb1735ec071e30173` |
| `scripts/t6040-test-hid-trace-auto-report.sh` | — | `70001cd08f3dbd7dd261e0cfa6d22e476e797f0282f3630e0a49278ea6e20639` |
| `initramfs-alpine-hid-trace-auto.cpio.gz` | 4,043,233 | `d5b790c63276816a3d69071797da459918717924885174d2a8b84225c6b24093` |
| `initramfs-alpine-hid-trace-auto.contents` | — | `3394ec4b2d4478b43c9f0766f9c8d0d5c865b2ceff22ebb8bb6ca75015c10e08` |

The uncompressed newc archive is 8,768,512 bytes with 518 inventory entries.
Both embedded scripts are byte-identical to the tracked sources.

Independent reviewer `usb_smoke_cross_review` validated the finalized
`d5b790c6...` archive, exact token gate (including near-miss rejection),
TX-only scope, 200-line bound, root ownership/modes, zero block/character
nodes and kernel modules, Alpine/BusyBox portability, and absence of new
mounts, networking, probing, device writes, MMIO, or control operations.
Result: **PASS**; the rig was untouched.

One non-blocking review note remains: the helper recursively walks sysfs to
locate exact-name `dc_trace`/`hid_trace` attributes because the concrete device
path can vary. It only reads those two attribute names and invokes no unrelated
show handler. If their stable platform-device paths are established later,
narrowing the traversal would make the bound more literal; it is not a blocker
for this reviewed archive.
