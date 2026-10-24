# Ticket 211 stage 1 / 5003 write run 1 (2026-10-25): ANS2 rejects NVMe Flush

claude, lease `claude`, unattended under CJ's autonomous mandate. The payload was
the reviewed 5003 payload (Mythos exact-artifact review PASS-with-notes,
`evidence/2026-10-25-review-5003-payload-exact.md`). Kernel builds 1 and 2 are
byte-identical (Image `4fadb8d3`, System.map `48f2d81d`, config `1b19daba`).
The run used `scripts/t6040-run-nvme-write.sh write`, which enforces a 300 s
post-handoff deadline. Console:
`linux-build-out/nvme-exfat-write-20261025/runs/write1/t6040-console-20261025-claude-211-write1-flush-badcmd.log`,
`3c70abb1d567178a0eb0d4ead19c45b838aa0016b18bc972bf1b16d4bf8493e9`.

## Result: STOP (the gate worked), and Flush is the defect

- All gates passed: topology, identity and all p3 pins, then
  `fsck.exfat -n (before) rc=0` (18 directories, 96 files).
- The first **Flush** command (`flags 0x20800` = SYNC|PREFLUSH on the exFAT
  boot-sector write at p3 sector 0) was rejected by the firmware:
  ```text
  RTKit: syslog message: host_ans2.c:1616: cmd parsing error for tag 20 fast decode err 0x7
  nvme0n1: I/O Cmd(0x0) @ LBA 2305843009213693951, 0 blocks, I/O Error (sct 0x0 / sc 0x2)
  operation not supported error, dev nvme0n1, sector 1586917376 op 0x1:(WRITE) flags 0x20800
  Buffer I/O error on dev nvme0n1p3, logical block 0, lost sync page write
  RTKit: syslog message: host_ans2.c:1509: tag 20, completed with err BAD_CMD-
  nvme-apple 44dcc0000.nvme: Deferred flush failed: 2
  ```
  `sc 0x2` is Invalid Field in Command. Every failing request carried
  PREFLUSH. No plain write reported an error.
- `dd … conv=fsync` failed at its fsync (another flush), so the script
  stopped with `NVME-WRITE STOP: write failed` at 3.59 s and parked.
- At the parked shell, read-only:
  ```text
  p3:   55 72 2288 71 1045 38 2097520 53215 0 588 53287 0 0 0 0 0 0
  disk: 71 72 2584 77 1045 38 2097520 53215 0 576 53302 0 0 0 0 2 8
  ```
  The p3 and whole-disk write counters are equal (1045 I/Os, 2,097,520
  sectors), so **nothing was written outside p3**. The disk line shows 2 flush
  requests.
- `write_cache` = `write back`, `fua` = 1. The on-disk exFAT VolumeFlags are
  `00 00` (clean; the dirty-bit write was the lost sync write). After the
  automatic unmount, `fsck.exfat -n` reports clean, 19 directories, 97 files:
  the test directory and `pattern.bin` exist.
- **Data content is unverified.** The write requests were issued and counted
  with no I/O-error lines, but `conv=fsync` failed before the hash was
  computed, so there is no `pattern.sha256` and no reference for the urandom
  data. This run does not show "1 GiB written intact".
- Also seen at handoff, from m1n1 itself: `nvme: command failed with status 2`
  for delete SQ/CQ. That is the same status code, on m1n1's own shutdown of the
  iBoot-live ANS. Noted, not chased.

## What it means

Linux NVMe data writes reach the controller on T6040. Flush, as
`drivers/nvme/host/apple.c` encodes it, does not: it is opcode 0 with the
namespace NSID, and the TCB has `dma_flags=FROM_DEVICE`, length 0, PRPs 0 and
is not zeroed. m1n1's `nvme_flush` differs: it zeroes the TCB and uses
`dma_flags=3`. There is no flush-specific fix in asahi-wip, asahi, or yuka's M4
branches.

## Next

1. A proxy flush probe (new ticket): m1n1 `nvme_flush(1)`, then
   `nvme_flush(0xFFFFFFFF)`, with syslog. It writes no data. The outcome picks
   the fix: a TCB-level fix, an NSID-level fix, or unsupported on this firmware
   (then write-through).
2. Plan B: the same test with `write through` set on `nvme0n1`, run only if the
   probe says flush is unsupported. The reboot verify is then the real
   persistence test. `macvdmtool reboot` is a hard reset with no NVMe shutdown.
3. The existing `wallace-write-test` directory makes `nvmewrite=write` refuse.
   The next init takes a directory suffix from the cmdline, rather than
   deleting anything.

Host: kisd lost the Debug USB device to `deviceinterfaced` on the
re-enumeration after the recovery reboot, even though kisd held it before. The
"kisd before macvdmtool" mitigation does not survive a reboot. Every rig cycle
currently needs CJ's `sudo kill -9 $(pgrep -x deviceinterfaced)`.
