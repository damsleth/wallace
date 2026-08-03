# T6040 m1n1-side NVMe probe — preflight (2026-07-25)

**Not run.** Built and audited; needs cross-review + maintainer approval because
it is the first experiment that touches the **internal SSD controller** — a new
risk class on a daily-driver machine.

## Question

Does m1n1's **own** pre-Linux NVMe path (ANS + SART over RTKit) work on T6040?

This matters because the enrolled appended-payload route is now root-caused as
unusable (`evidence/2026-07-25-t6040-enrolled-payload-rootcause.md`: the payload scan
address holds m1n1's own `.rodata`). The upstream Asahi architecture avoids
appended payloads entirely:

```text
enrolled: small m1n1 stage 1 (~1 MiB — already proven to boot)  + chainload=<spec>
   -> chainload_load() -> nvme_init() + rust_load_image(spec)
   -> stage 2 (m1n1 + kernel + DTB + Alpine) read from storage
   -> untethered boot, no size/layout coupling to iBoot
```

The Linux NVMe blocker (tickets 051/052/054/055) is the **SPTM-guarded ABI**, a
Linux-side problem. m1n1's `src/nvme.c` is **not SoC-gated**: it binds the generic
ADT paths `/arm-io/ans` + `/arm-io/sart-ans` over RTKit. Whether that works on
T6040 is a separate, untested question.

## What it needs: nothing new on the target

`nvme.o` is unconditionally in m1n1's Makefile and the proxy already exposes the
opcodes, so the **already-enrolled, live-proven bare loader `1394c345` can do this
today**. No rebuild, no enrollment change, no boot-policy or APFS action.

## Safety analysis

- **No write path exists.** The entire proxy NVMe surface is `P_NVME_INIT`
  (0xf00), `P_NVME_SHUTDOWN` (0xf01), `P_NVME_READ` (0xf02), `P_NVME_FLUSH`
  (0xf03). **There is no `P_NVME_WRITE`.** The script calls only `nvme_init`,
  `nvme_read`, `nvme_shutdown` (audited: three call sites) and never `nvme_flush`.
  It therefore *cannot* modify the SSD.
- **Fail-closed gate before any NVMe touch:** requires live ADT `target-type ==
  J614s` and `chip-id == 0x6040`, and both `/arm-io/ans` and `/arm-io/sart-ans`
  present; otherwise zero NVMe transactions.
- **Bounded:** `--lbas` clamped to 1..8 4 KiB reads from `nsid 1`, printed as hex
  only. No filesystem mount, no partition parsing beyond noting a protective-MBR
  or `NXSB` signature for identification.
- **Quiescent device:** m1n1 has replaced iBoot and macOS is not running.
- **Always shuts down:** `nvme_shutdown()` in a `finally`.

**Residual risk:** ANS/RTKit bring-up on an untested SoC may hang or raise an
SError, wedging m1n1 and requiring a recovery boot. That is the known, cheap
failure mode. **No data-loss path exists** given the absent write opcode.

## Artifact

`scripts/t6040-nvme-probe.py` (read-only, bounded, fail-closed). Run with the rig
lease held:

```sh
M1N1DEVICE=/dev/cu.usbmodemJ22GYCN4YG1 \
  /Users/damsleth/Code/m1n1/venv/bin/python scripts/t6040-nvme-probe.py
```

## Outcomes

- **`nvme_init()` returns true + LBA reads succeed** -> m1n1 NVMe works on T6040.
  The `chainload=` architecture becomes available and the untethered-boot blocker
  is removed. Follow-up: decide where stage 2 lives and what `spec` format
  `rust_load_image()` accepts.
- **`nvme_init()` returns false** -> cleanly answered: that route is closed. Falls
  back to USB stage 2 (needs Sol's R3 ATC/HPM link *and* mass-storage/FAT in m1n1,
  which does not exist — U-Boot has it, ticket 025/B1), or accepting tethered
  chainload for now.
- **Hang/SError** -> recovery boot; also an answer (ANS bring-up unsupported).

Requires: rig lease, independent cross-review (Sol), and explicit maintainer
approval for the first internal-storage-controller touch.
