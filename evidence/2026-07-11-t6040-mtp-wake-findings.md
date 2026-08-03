# MTP wake failure — root-cause investigation (2026-07-11, session 4)

## ✅ OUTCOME: INTERNAL KEYBOARD WORKS (maintainer-confirmed, boot test #4)

Boot test #4 (Image cc2b3de1… with the dchid_stop fix + kbd DTB 101611f1… +
fixed m1n1): no oops, userspace stable, and **typing on the built-in keyboard
works at the BusyBox shell**. Three independent bugs, all fixed:

1. m1n1 skipped dart-mtp DAPF programming (misattributed async SError) —
   src/dapf.c now runs dart-mtp on t6040.
2. t6040.dtsi mailbox IRQ names pairwise swapped (Apple ADT lists not-empty
   first) — fixed to ascending 792..795.
3. dockchannel-hid missing hid_ll_driver .stop → NULL-branch oops —
   .plans/t6040-dockchannel-fixes.patch.

All findings below are from the live ADT (fetched over proxy, no MMIO beyond the
six approved baseline reads), local m1n1/Linux source, and the dockchannel git
series. No new hardware writes were performed.

## Status-initramfs boot result (photo received)

The clean retry (`t6040-j614s-kbd.dtb` + `initramfs-keyboard-status.cpio.gz`)
halted at `Demotion targets for Node 0: null` **from a verified pristine MTP
baseline and with NO DART IRQ-40 storm** (DART initialized cleanly, bypass
forced). Conclusions:

- The Demotion-targets halt is NOT MTP contamination — it happens clean.
- It is the known layout/timing-sensitive early halt; the only delta vs. the
  full-HID boot that reached userspace is the status initramfs itself.
- Determinism still unverified (N=1).
- After the watchdog reset the six read-only baseline reads all returned the
  pristine values (`0x6a`, mailboxes `0x00020001`, TCR `0x1`, DART error `0x0`).

## Why the coprocessor won't wake — the evidence chain

1. **The driver's wake path is exactly what the proxy pulse reproduced.**
   `apple_dockchannel_hid.c` probe: `writel(BIT(4), asc + 0x44)` then
   `apple_rtkit_wake()` waits for the RTKit hello. On t8112/t8122 that is
   sufficient. On t6040, RUN unhalts (STOPPED clears) but the fw never talks.

2. **MTP power-state registers exist but are hidden from the AP.** The t6040
   pmgr ADT uses the new group+offset format (no `ps-regs`). The MTP devices:

   | device | id | PS address (group 3 = nub pmgr 0x508300000) |
   |---|---|---|
   | MTP_FABRIC | 371 | 0x50830c000 |
   | MTP_GPIO | 372 | 0x50830c008 |
   | MTP_BASE | 373 | 0x50830c010 |
   | MTP_PERIPH | 374 | 0x50830c018 |
   | MTP_CPU | 375 | 0x50830c020 |
   | MTP_SHIM_PCLK | 376 | 0x50830c028 |
   | MTP_SCM_FABRIC | 377 | 0x50830c030 |
   | MTP_SPI0/1, I2CM0, UART0 | 378–381 | 0x50830c038–0x50830c050 |
   | MTP_SRAM | 382 | 0x50830c058 |
   | MTP_DMA | 383 | 0x50830c060 |

   All are flagged `no_ps` (= m1n1's `PMGR_FLAG_VIRTUAL`, bit 0x10), so neither
   m1n1's pmgr cleanup nor anything else has ever read/written them. Parent
   NUB_FABRIC (0x508300100) is on (0x0f0000ff). On t602x MacBook Pros the
   equivalent `ps_mtp_*` are ordinary AP-managed AON-bank power-controllers
   (asahi t602x-pmgr.dtsi @b0..; `apple,always-on`, parent ps_nub_fabric) — on
   the M4 generation Apple moved them behind `no_ps`.

3. **dart-mtp's DAPF exists precisely to give the MTP coprocessor access to its
   own PS registers.** `dapf-instance-0` rules (all r0=0x3:0x1, r20=0x1):

   - 0x50830c000..0x50830c06f  ← exactly the MTP PS block above
   - 0x508320880..0x508320a27
   - 0x5081e40d0..0x5081e40d3
   - 0x508360100..0x50836010b
   - 0x508900014..0x508900017
   - 0x508338020..0x508338023

   DAPF config regs = dart-mtp reg[1] = 0x514810000 (what m1n1's
   `dapf_init(dart-mtp, 1)` writes).

4. **On t8132 (the other M4), yuka found MTP NEEDS its DAPF programmed** and
   there the dart-mtp DAPF init works (see comment in src/dapf.c). On t6040 the
   same writes raise the async L2C SError — and notably the SError arrives
   *after* "Initialized dart-mtp" prints, i.e. async fabric error, which is what
   writes into a powered-off fabric segment look like. Since the MTP domains are
   OFF at m1n1 time (status 0x6a) and dart-mtp has no clock-gates for
   `dapf_init` to power first, a plausible unified story:

   **MTP domains off → DAPF config block unreachable (async SError) → m1n1
   skips DAPF → even if RUN unhalts the CPU, the fw can't reach its PS regs /
   nub windows → no RTKit hello → -ETIME.**

5. **Our Linux DT is missing pieces the ADT declares:**
   - `/arm-io/mtp` has a SECOND reg block: 0x514050000 size 0x4000
     (ascwrap-v6 wrap block?) — not mapped in t6040.dtsi.
   - `dockchannel-mtp` has 6 reg blocks (0x514b00000, 0x514b14000, 0x514b30000,
     0x514b34000, 0x514b28000, 0x514b2c000) — we map only irq/config/data.
   - No `power-domains` on any mtp node (t602x precedent has them, but on t6040
     the domains are no_ps, so a DT power-domain fix alone can't work today).
   - MTP fw `__OS_LOG` segment phys = 0x100045bc000 — inside the iBoot kdata
     carveout that m1n1/Linux reuse. TEXT/DATA are in SRAM (0x514c00000,
     iova base 0x1000000).

6. `/arm-io/pmp` exists (iop,ascwrap-v6) — the M4 power-management coprocessor;
   `notify_pmp` flag exists on pmgr devices. Possibly relevant to who normally
   flips no_ps domains (macOS: likely the ASCWrap driver/PMP/SPTM cooperation).

## Hardware results (approved reads, this session)

1. **All 14 MTP PS registers read fine and the domains are ON** (guarded reads,
   proxy healthy throughout): MTP_FABRIC 0x1f0000ff, BASE/CPU/SCM_FABRIC/SRAM
   0x0f0000ff, GPIO/PERIPH/SHIM_PCLK/SPI0/SPI1/UART0/DMA 0x…02ff (actual=0xf),
   I2CM0 0x00000244 (clock-gated). **The "domains are off" theory is dead.**
2. **MTP wrap block 0x514050000 (first 0x100 bytes)**: word[0]=0x14c00001,
   word[1]=0x00000005, rest zero. That is the **boot vector 0x514c00000
   (preloaded SRAM __TEXT) + valid bit** — already programmed.

So: power on, vector set, firmware preloaded, RUN accepted (STOPPED clears) —
and still no RTKit hello and RUNNING never sets. Remaining suspects:
- SPTM/PMP gates the actual CPU start on M4 (raw RUN write filtered).
- A start/clock bit in the unread rest of the wrap block (0x514050100+).
- CPU executes but wedges instantly (distinguishable via the __OS_LOG probe:
  DRAM at 0x100045bc000 is scrubbed to zero by iBoot on watchdog reset; any
  content appearing there after a RUN pulse proves execution).

## RUN pulse #2 with memory diff (approved): THE CPU EXECUTES

Baseline pristine (0x6a). Snapshot of __OS_LOG DRAM (0x100045bc000, 64 KiB;
57004 nonzero bytes pre-pulse — iBoot does NOT scrub this kdata region),
SRAM header (15 nonzero bytes, unchanged) and __DATA start (all zero pre).

Wrote 0x514600044 = 0x10. Status went 0x6a -> **0x68** (STOPPED cleared; note:
NOT 0x6c like pulse #1 — IRQ_NOT_PEND did not set this time). Mailboxes stayed
empty, OS_LOG unchanged. But **__DATA changed**:

- 0x514c5e000 = 0x0000000514c00483
- 0x514c5e008 = 0x0000000514c01483

Two pointers into __TEXT (+0x483 / +0x1483). 0x480 is an AArch64 exception
vector offset — this looks like an early exception/park record. **So the MTP
CPU does fetch and execute** and wedges almost immediately.

Restored control to 0; status stays 0x68 (contaminated until hardware reset,
as with pulse #1).

## Revised theory (v2)

The firmware starts and faults early. Prime suspect: its first MMIO access to
the six nub windows (its own PS regs etc.) is blocked because the dart-mtp
DAPF was never programmed (m1n1 skips ALL DAPF on t6040). Two supporting facts:

- On t8132, MTP requires its DAPF programmed and dart-mtp DAPF init works.
- The t6040 evidence against dart-mtp is weak: the async L2C SError arrived
  *after* "Initialized dart-mtp" printed — with an imprecise async error the
  true trigger may have been the NEXT entry's writes (dart-pmp). dart-mtp's
  DAPF writes may be fine here too.

## RESOLVED: DAPF programming + RUN boots the firmware (session 4, approved)

DAPF config readback at 0x514810000: readable, NO fault, content = unprogrammed
reset garbage (enable bits clear). After a maintainer power-cycle (pristine
0x6a), the six dart-mtp DAPF rules were programmed from the proxy exactly as
m1n1's dapf_init_t8110a would — **all writes succeeded, no SError** — verified
by readback. Then one RUN pulse:

- CPU status 0x6a -> **0x4d (RUNNING set)**
- I2A mailbox control 0x20001 -> **0x100101 (firmware sent the RTKit hello)**
- __DATA now holds a full table of per-page tagged pointers
  (0x514c00483 + n*0x1000, 1123 bytes changed) — in the failed pulse it built
  exactly two entries before faulting on the blocked nub window.

**Root cause: t6040 MTP firmware requires the dart-mtp DAPF windows; m1n1
skipped ALL DAPF on t6040 because the async SError had been misattributed to
dart-mtp.** The actual SError source is a later entry (dart-pmp/aop/isp —
untested individually; still skipped).

Fix committed to the working tree: src/dapf.c `dapf_skip_entry()` now runs
dart-mtp on t6040 and keeps skipping the rest. Build verified.

## Next hardware test

Power-cycle (MTP currently left RUNNING with a stale hello in its FIFO from
the proxy pulse), then:

```sh
bash .plans/t6040-bootcap-fb.sh t6040-j614s-kbd.dtb initramfs-keyboard.cpio.gz
```

This chainloads the fixed m1n1 (kboot now programs the dart-mtp DAPF), boots
the full HID DTB, and dockchannel-hid should get its hello instead of -ETIME.
Watch the screen for the probe result / input devices. Avoid
initramfs-keyboard-status (Demotion-targets halt, cause unrelated).

## Boot test #2 with fixed m1n1: DAPF programmed, still -ETIME → second bug found

The fixed m1n1 ran (`dapf: Initialized /arm-io/dart-mtp`, aop/pmp/isp skipped,
no SError, Linux reached userspace), but dockchannel-hid still hit -ETIME.
Post-mortem-by-code-review found a SECOND, independent bug:

**The ASC mailbox IRQ order in t6040.dtsi was pairwise swapped.** The ADT lists
mtp interrupts as [793 792 795 794]. EVERY ascwrap node in the J614s ADT shows
the same [n+1, n, n+3, n+2] pattern (aop, sio, pmp, sep, ans, smc, dcp,
dcpext0/1, gfx-asc) → Apple's ADT convention is *not-empty first* in each
pair, while the actual lines ascending are send-empty, send-not-empty,
recv-empty, recv-not-empty (the order every upstream Apple DT uses).
t6040.dtsi had copied the raw ADT order positionally, so:

- "recv-not-empty" (what drivers/soc/apple/mailbox.c requests for RX) pointed
  at the recv-EMPTY line: asserted while idle (IRQ storm at probe — likely the
  earlier "Disabling IRQ 40"), and NO interrupt when the hello arrives.
- "send-empty" pointed at send-not-empty (also wrong).

So in boot test #2 the firmware very likely booted and sent its hello — Linux
just never got the interrupt.

Fix: t6040.dtsi mtp_mbox interrupts now 792,793,794,795 ascending (with a
comment documenting the ADT convention). Rebuilt DTBs:

- `t6040-j614s-kbd.dtb`
  SHA-256 101611f1e233779cb17b84b3ebb5c169cd060743b1b797da668ef4e4dc5c3bb3
- `t6040-j614s-kbd-infra.dtb`
  SHA-256 79f30bdcc1347c7fa865650a37f9c792523c9b3f88420252ab8efc93f3251b57

NOTE for upstreaming: any other t6040 DT node whose interrupts were copied
positionally from a multi-IRQ ADT entry should be re-checked against this
convention (dockchannel/dart single IRQs are unaffected).

## Boot test #3 (fixed m1n1 + fixed IRQ DTB): MTP FULLY UP — then a driver oops

With both fixes, the whole HID stack came alive:

- `RTKit: Initializing (protocol version 12)`; syslog: **"MTP Says Hello"**,
  AppleMTPFirmwareMac-5340.61.4~438, personality MTP_SYS.
- All 7 comm interfaces initialized (comm, multi-touch, keyboard, stm,
  actuator, tp-accel, mtp); Grape (touch) + keyboard + ST all ready.
- **input0 = Apple DockChannel Multi-touch, input1 = Apple DockChannel
  Keyboard** registered as real input devices.

Then: `Unable to handle kernel NULL pointer dereference at virtual address 0`,
ESR EC=0x21 (instruction abort, current EL) — the kernel branched to NULL.

Root cause (found by inspection, matches perfectly): **dchid_ll in
apple_dockchannel_hid.c defines no .stop callback, and hid_hw_stop() calls
hdev->ll_driver->stop(hdev) unconditionally** (drivers/hid/hid-core.c:2447).
An unnamed subdevice (0019:0000:0000.0001, bogus report_size 16384) failed
probe with -22; the first error path reaching hid_hw_stop() jumped to NULL.

Fix: no-op dchid_stop + `.stop = dchid_stop` in dchid_ll.
`.plans/t6040-dockchannel-fixes.patch` (also in /out; kbuild.sh now applies it
with DOCKCHANNEL=1). The stale MTPDBG debug patch was removed from the
container tree at the same time. It later resurfaced because the build clone
was reused; `patches/t6040-remove-mtpdbg.patch` now makes that cleanup
deterministic. Known-good build #15 contains no MTPDBG strings and boots to
BusyBox with the keyboard registered.

New artifacts:
- `Image` / `Image-keyboard`
  SHA-256 cc2b3de15efbf4fbf5c4d7ac7d6b8155e5c4c52e0deabd9e012ffa379b37fb58
  (previous Image backed up as `Image-prev`)
- DTBs unchanged from boot #3 (kbd 101611f1…, kbd-infra 79f30bdc…)

Worth noting for later: the unnamed 0000:0000 interface that fails probe is
likely one of stm/actuator/tp-accel/mtp with a descriptor the transport
mishandles — benign once the stop fix is in, but worth understanding before
upstreaming.

## Superseded proposals (kept for the record)

1. **Guarded read of the 14 MTP PS regs** 0x50830c000..0x50830c068 (read-only,
   virgin MMIO — async-SError wedge risk; maintainer ready to power-cycle).
   Expected: actual=0 target=0 (off). This confirms/kills the power theory.
2. If off: **gated write experiment** from proxy, in parent order
   (FABRIC → BASE/GPIO/SCM_FABRIC → CPU/SRAM/PERIPH/DMA/...): set target 0xf,
   poll actual. Each write shown individually first.
3. If domains power up: **retry dart-mtp DAPF init** (the 6 windows above) —
   the t6040 SError may vanish with the fabric powered.
4. Then the RUN pulse (0x514600044 = 0x10) and watch I2A mailbox/status for the
   RTKit hello.
5. If that works live, encode the same sequence in m1n1 (pmgr on + dapf + leave
   MTP for Linux) and re-test the full HID DTB.

## Boot-halt track (parallel, cheap)

- Re-run the SAME status-initramfs boot once to establish determinism of the
  Demotion-targets halt before trusting any single-shot result.
- If deterministic, suspect initramfs size/placement; consider padding the
  status initramfs to match the known-good initramfs size.
