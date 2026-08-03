# R3 SWDF ran BLIND — command issued, no transcript captured (2026-07-28, attended)

**Outcome: INCONCLUSIVE, and it must not be repeated this way.** The R3 binary was entered and
executed on the M4 with CJ at the keyboard, but its transcript was captured **nowhere**, so
whether the SWDF role swap succeeded, was rejected with `!CMD`, or never ran a single SPMI
transaction (ADT gate fail) is **unknown**. This is an agent process failure, recorded in full
so it cannot recur.

## What was run

- Artifact: `linux-build-out/t6040-hpm2-e41cf6e4ee8f/r3/m1n1.bin`, SHA-256
  `a106f8cd36a6068fc9586924028b9a64aca986a8e635e1bb0964422ec7345c4e` (hash verified before
  upload), m1n1-hpm2 commit `e41cf6e4`, experiment class 3 (SWDF → DFP/host).
- Authorization: CJ explicitly approved the attended run and was at the keyboard. Note the
  cross-agent exact-artifact review (`sol`) had **not** happened; CJ's go was taken as
  superseding it, which is CJ's prerogative but is a deviation worth recording.
- Transcript file: `linux-build-out/hpm2-r3-swdf-20260728.log` (132 lines — it contains the
  chainload and the *enrolled* object's boots, and **no** `t6040-hpm2:` line at all).

## Proof that R3 actually executed

From the log, in order:

```text
found /dev/cu.usbmodemJ22GYCN4YG1 after 61 polls; chainloading R3
TTY> Waiting for proxy connection... . Connected!      <- enrolled dual-mode window caught
m1n1 base: 0x1000424c000 … Loading kernel image (0x58004 bytes) … Pushing ADT (596296 bytes)
Reloading into stub at 0x10011128200
TTY> Preparing to run next stage at 0x10011128200...   <- control transferred INTO R3
Waiting for reconnection... (95 dots) Connected        <- R3 ran, then warm-rebooted
TTY> … MCCs … MMU … AIC … pmgr … display … Bringing up USB for early debug …
TTY> Waiting for proxy connection...  Connected!       <- the ENROLLED object, post-reboot
Proxy is alive again        (chainload.py rc=0)
```

`Preparing to run next stage` is the old m1n1 vectoring into the uploaded image, so R3 ran. The
~95-poll reconnection gap is R3 executing and calling `flush_and_reboot()`; the boot that follows
is the enrolled daily driver (display + early-debug window), not R3.

## Why there is no transcript — the actual mechanism

The run was performed over the **USB gadget** (`/dev/cu.usbmodem*`), because the enrolled
dual-mode daily driver's 10 s proxy door is on the gadget and KIS/DebugUSB is mutually exclusive
with it on the DFU port. But:

- R3 prints from `t6040_hpm2_experiment()`, called in `m1n1_main()` immediately after
  `pmgr_init()` — i.e. **before** `run_actions()`, which is the only thing that brings up the
  USB console (`usb_init()`/`usb_iodev_init()`), and R3 then calls `flush_and_reboot()`.
- So R3's output could only reach the DockChannel UART (readable **only** via KIS, which was
  detached) and m1n1's retained console backlog — which is never flushed to USB because USB
  console never comes up, and is discarded by the warm reboot.

**The reasoning error:** I used ticket 095's R2 transcript as evidence that "chainload.py relays
the experiment output as `TTY>` lines". It does — but R2 was run over **KIS** (`/tmp/m1n1`),
where the proxy device *is* m1n1's console device, so early pre-USB output is relayed for free.
Over the gadget the proxy device and the early console are different channels. The `TTY>` prefix
looks identical in both cases, which is exactly what disguised the difference. I verified the
relay existed; I did not verify *which device* produced it.

## Consequences and current state

- **The SWDF 4CC was probably issued to the right-port HPM, with the outcome unobserved.** All
  three outcomes (PASS, `!CMD` rejection, ADT-gate FAIL with zero SPMI transactions) end in the
  same warm reboot and are indistinguishable from the host.
- The right port may now be in DFP/source state with VBUS on the passive stick. Per
  `done/2026-07-25-t6040-r3-risk-calibration.md` that state is volatile and clears on a **power
  cycle**; two warm reboots have happened since and warm reset is not guaranteed to clear it.
  This is not a hazard (VBUS into a passive sink is the designed host operation, and the M1↔M4
  cable is on the left DFU port) but it does mean the HPM's pre-state for any *next* run is
  unknown — an R0-class read must establish it before R3 is repeated.
- The machine was left booted into the enrolled dwm daily driver (normal, usable). Rig lease
  released healthy.
- No enumeration was possible even on success: the daily driver's DT does not describe the
  right-port xHCI/host path (that is the separate force-host DTB), so a VBUS success would not
  have produced an `sd*` device in this boot regardless.

## The structural lesson: gadget vs KIS observability

**Over the gadget, ANY m1n1 experiment that prints before `run_actions()` and then reboots is
unobservable — including a read-only R0 probe.** This is not specific to R3. Options, and why
only one is good:

1. **Run over KIS (recommended).** Requires a proxy reachable on KIS, i.e. the payload-free
   loader `rollback-m1n1-1394c345.bin` enrolled (1TR, CJ-only). This reproduces exactly the
   conditions under which R0/R1/R2 captured clean transcripts, and it also fixes the PCIe
   candidate's observability, which has the same problem.
2. **Let the experiment fall through to `run_actions()` instead of rebooting**, so the retained
   backlog flushes when the USB console comes up. Rejected: `usb_init()` initializes USB0/1/2 —
   including **USB2/ATC3, the right port under test** — which both confounds the HPM experiment
   and is on the build audit's forbidden-symbol list for these candidates.
3. **Framebuffer console** (display init before the experiment): viable only with a human at the
   panel, and it changes the experiment's init order.
4. **Drive SPMI from the host over the existing gadget proxy** with proxyclient: gives perfect
   observability but bypasses the reviewed C candidate's fail-closed ADT identity gate. Not
   acceptable without its own review.

## What must happen before R3 is run again

1. Enroll `rollback-m1n1-1394c345.bin` (CJ, 1TR) to restore the KIS tethered-dev loop —
   `scripts/t6040-debugusb-console.sh reboot` then reaches a real `Running proxy`.
2. Run an **R0-class read first** to establish the HPM's current power state (it may be S0 and/or
   DFP from this blind run — the pre-state assumption "state 0x07 after WAKEUP" may no longer
   hold).
3. Then R3 over KIS, unchanged binary `a106f8cd…`, with the full transcript.
4. `sol`'s exact-artifact review should still be recorded, per COORDINATION.md.
