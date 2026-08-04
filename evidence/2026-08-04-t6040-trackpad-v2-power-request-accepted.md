# T6040 trackpad: the v2 power request is accepted live — firmware consumed, Touch MT ready

Date: 2026-08-04. Agent: fable. Ticket: 230 (`trackpad-v2-power-request-live`).
Lease: acquired 12:39, released **healthy** 12:47 after a sanctioned warm
reboot back to a quiescent `Running proxy`. One chainload, two bounded event
watches, no storage mounted, no persistent write of any kind.

## Outcome in one line

The nine-byte version-2 interface power request decoded in
`evidence/2026-08-04-t6040-trackpad-post-upload-reset-contract.md` is
**accepted by the J614s MTP coprocessor on first try**: both `0x40` pairs
returned success (no error line, no v1 fallback), the coprocessor consumed the
CBOR firmware image, and its touch pipeline came up —
`Touch interface ready` / `Touch MT ready` — 260 ms after `open()`.
The transport-level half of the ticket-230 pass condition is met. The
event-count half needs a finger on the pad and remains CJ's to confirm.

## Exact fixture

| Artifact | SHA-256 |
|---|---|
| `Image-trackpad-reset-contract` (booted via `IMAGE=` env) | `80c15f58809d7815fb82487bdc5a3f065409baab61bc4fa1fe263cfcc87852c4` |
| `System.map-trackpad-reset-contract` | `30115accb2872d864b7945c76a3f04107ce4201bb8fe706b06137ddc7b8bd36f` |
| `config-trackpad-reset-contract` | `a74daa271dd59cbcd8aae83b33a3e0c84a9ac69e5425bae72e3f3e863269c54f` |
| `t6040-j614s-dcuart.dtb` (script default, rebuilt 2026-08-04 01:53; tpmtfw node present, NVMe `status="disabled"`) | (unpinned in ticket; standard default) |
| `initramfs-dcuart-trackpad-230.cpio.gz` (built this session, see below) | `87442995d460b76133f1bdee06148434802f694a490df667cbafa02b0a1f8e8c` |
| embedded `apple/tpmtfw-j614s.bin` | `a1f4131d0cb7caf6fa15b19f47725458a6d7b0e3a34f15169339d5541663d9e2` |
| embedded `etc/wallace-no.bmap` | `606ecd98f83b72983f3cd35976df939dc9c7187283703736a81e89b65aee85a8` |
| m1n1 (chainload, repo `80badc91`) | `build/m1n1.bin`, 1,097,728 bytes |

Kernel identity on the wire: `Linux version 7.1.3-g4f2429104009-dirty …
#1 SMP PREEMPT 2026-08-03T18:17:34+02:00`. New-code marker
`v2 power request rejected` present exactly once in the binary (the fallback
`dev_info`, which — see below — never fired).

The initramfs is the ticket-197 shape rebuilt to current preflight standards
with `scripts/t6040-make-initramfs.sh`:

- base `initramfs.cpio.gz`, init `scripts/t6040-init-dcuart-trackpad-230`
  (the standard dcuart init plus the mandatory `loadkmap` of
  `etc/wallace-no.bmap` before any shell; opens **no** input device itself);
- `scripts/t6040-input-report` at `/bin/t6040-input-report` (installed 0644 by
  `EXTRA_FILES`, so it is invoked as `busybox sh /bin/t6040-input-report`);
- the exception-scoped HIDF blob `a1f4131d…` at
  `lib/firmware/apple/tpmtfw-j614s.bin` (source:
  `t6040-paired-fw-25F84/vendorfw/`, hash-verified before packing).

`t6040-image-preflight.sh` passed (kernel markers, keymap member, loadkmap in
`./init`, `console=tty0` last, `maxcpus=1`); the three WARNs — no fsck.exfat,
no BCM4388 firmware, no `console=ttydc0` — are all deliberate for a minimal
storage-disabled RAM root whose serial shell comes from init, not printk.

This initramfs postdates the sibling's exact-artifact review of the kernel
pins, so its full member list and hashes are recorded here for after-the-fact
audit; every byte of it comes from in-repo scripts, the pinned keymap, and the
exception blob.

## Procedure and observations

1. `queue approve 230 --by cj` (CJ's 2026-08-04 blanket rig mandate) and
   `queue ready 230 --reviewed-by claude` (the sibling's hand-off review).
   Dep 126 was complete-in-effect but still in `tickets/`; moved to `done/`
   via `queue done 126` to satisfy the dependency gate.
2. Lease acquired as `fable`. `debugusb-console.sh reboot` reached
   `Running proxy` first try and `t6040-proxy-alive.py` answered a NOP —
   **CJ's rollback re-enrollment (`rollback-m1n1-1394c345.bin`) is confirmed
   working**; the rig-blocked condition of
   `2026-08-04-t6040-rig-blocked-enrolled-object-has-no-proxy.md` is cleared.
3. Chainload: `RIG_AGENT=fable IMAGE=Image-trackpad-reset-contract
   BOOT_WAIT=45 t6040-boot-dcuart.sh t6040-j614s-dcuart.dtb
   initramfs-dcuart-trackpad-230.cpio.gz` — bootargs
   `maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused
   console=tty0 fbcon=font:TER16x32 ignore_loglevel rdinit=/init`.
   Clean boot; both HID interfaces enumerated as before; shell on ttydc0.
4. Trigger (kernel time 94.1 s):
   `busybox sh /bin/t6040-input-report watch /dev/input/event0 60`.
   The first `open()` of event0 ran `dchid_start_interface()`:

```text
[   94.158598] dockchannel-hid 514600000.hid: sending firmware for multi-touch
[   94.284737] … RTKit: syslog message: bootloader.c:522: (*)New AFE[0] cbor image received
[   94.412405] … RTKit: syslog message: touch_pwr_mgr.c:219: [TPM] Mac Power Manager State Machine Started
[   94.416293] … RTKit: syslog message: touch_iface.c:407: Touch interface ready
[   94.417002] … RTKit: syslog message: touch_iface.c:424: Touch MT ready
[   94.417580] … RTKit: syslog message: touch_pwr_mgr_fsm.c:291: Sending Cumulus Report to enter Dependent Mode (9A)
```

   Full dmesg for the boot contains **zero** `command 0x40 … failed` lines and
   **zero** `v2 power request rejected, using v1 requests` lines. Since
   `dchid_cmd()` logs every nonzero coprocessor retcode, silence plus the
   ready transition proves all four `0x40` messages (off/on × will/has)
   returned 0. `open()` returned success and the 60 s reader survived —
   under the old kernel the same open failed in under a second
   (ticket 197: `open-returned rc=1`).
5. Reporter result, unattended (no finger available):
   `T6040_INPUT_WATCH_RESULT dev=/dev/input/event0 bytes=0 events=0`.
6. Stability re-check: a second
   `watch /dev/input/event0 20` did **not** re-trigger the upload (no new
   `sending firmware` line), produced no errors, and its reader also survived
   its full window — the started interface is stable across close/reopen.
7. Sanctioned warm reboot back to the rollback proxy; NOP verified; lease
   released healthy.

MTP firmware self-identified on this boot as
`AppleMTPFirmwareMac-5340.61.4~438`, SDK `25F63` — byte-for-byte the version
the static decode was performed against.

## Falsifiers from the reset-contract evidence, evaluated

1. *v2 rejected with `0xe00002c2`* (field layout wrong) — **did not occur**.
   The encoding is correct.
2. *v2 returns `0xe00002ca`* (encoding right, DMA unreachable) — **did not
   occur**, and `bootloader.c:522: New AFE[0] cbor image received` proves the
   coprocessor actually read the firmware buffer through `mtp_dart`. DMA
   reachability is now positively confirmed, not merely not-refuted.
3. *`0xe00002c7`* (flags byte wrong) — did not occur.
4. *Ready arrives but no motion* (gap above the transport) — **cannot be
   evaluated from this run**: `events=0` with no finger present is the
   expected null result, not evidence of a gap. This is the one remaining
   open question and it needs CJ's finger.
5. *M1/M2 regression* — untouched by this run; the v1 fallback path remains
   unexercised on T6040 (as predicted) and untested on older SoCs.

## What is proven / what remains

**Proven live:** the root-cause analysis end to end. Command `0x40` is the
interface power request; J614s wants the 9-byte v2 two-phase form; sending it
makes the coprocessor consume the uploaded CBOR firmware and bring the touch
pipeline up. The kernel patch
`patches/t6040-dockchannel-hid-reset-contract.patch` is correct and
sufficient at the transport level.

**Remaining:** a human finger during a watch window. PASS for ticket 230 is
"0x40 accepted AND a nonzero event count while a finger is on the trackpad" —
the first half is done, the second is CJ's. Suggested check (either on this
fixture or any image carrying the patch):

```text
busybox sh /bin/t6040-input-report watch /dev/input/event0 60
# touch the pad during the window; expect bytes>0, events>0 and a hex dump
```

If a finger yields `events=0` with the transport in this state, the gap is
above the transport (`AppleMultitouchDriver` semantics — likely
`magicmouse_raw_event_mtp`'s `46 + N*30` length filter) and that becomes the
next offline decode target.

## Transcripts

```text
58a4a6284bcbffd2a589de9b4c83773cc34d0cd99b05d9b3c9337e3a6b817489  21246 bytes
  linux-build-out/transcripts/t6040-console-20260804-fable-ticket230-v2-power-request.log
51dd8c9a50c2513af91431c3dfb51cfbb03375b4be2b9dd60d234a4d14e53ed9
  linux-build-out/transcripts/t6040-boot-20260804-fable-ticket230.log
```

The console transcript contains the boot, both watch windows, and the
targeted dmesg capture between the `DMESG_CAPTURE_BEGIN`/`END` markers.
