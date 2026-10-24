# Ticket 6001 run 1 (2026-10-24): parked at its own identity gate, so the read test never ran

Run by the claude session under the `astra` lease handle, on CJ's
instruction ("astra isn't active, run 6001 under astra"), with CJ present.
The exact reviewed launcher `scripts/t6040-run-nvme-ioq.py --run` was used
unmodified against manifest `14ba1600…` (all 241 pinned files verified).
Ticket approved by CJ and marked ready with reviewer `nvme_review`. The
lease was released **healthy** at `Running proxy`.

## Result: STOP at the gate, no hardware fault

- m1n1 adopted and quiesced the live ANS and reset it. Linux booted
  (`[GATED ANS/NVMe probe]` DT) and nvme-apple came up:
  `nvme0n1: p1 p2 p3`. ANS RTKit is alive; its only syslog was a benign
  "PANICLOG not yet written".
- The init printed `NVME-READONLY STOP: unexpected namespace/controller`,
  then `PARKED`. **The read test never started**: no
  `blockdev --setro`, no direct reads, and no CQ-wrap exercise. The only
  storage access was the kernel's own partition-table scan.
- No SError, DART fault, panic, assert, ANS crash or reset.
  `t6040-check-nvme-ioq-transcript.py` reports STOP with no test start.

## Cause: the gate assumes a single namespace

The gate stops if `/dev/nvme0n2` or `/dev/nvme1` exists. Read-only
inspection from the operator shell (`ls` and sysfs) shows one controller
with **three namespaces**:

| node | 512 B sectors | note |
|---|---|---|
| nvme0n1 | 1,954,210,120 | main 1 TB disk, partitions p1–p3 |
| nvme0n2 | 6,144 (3 MiB) | Apple auxiliary namespace |
| nvme0n3 | 262,144 (128 MiB) | Apple auxiliary namespace |

model `APPLE SSD AP1024Z`, transport `apple-nvme`, no `nvme1`. The gate's
assumption was wrong for this machine, so the payload as reviewed cannot run
its test.

## Fix required (new artifact, so new review)

Pin the expected topology instead of rejecting any second namespace: exactly
`nvme0`, with n1 at 1,954,210,120 sectors and n2/n3 at exactly 6,144 and
262,144 sectors; stop on anything else, including any `nvme1`. Set n2/n3
read-only too, and keep the test confined to n1. This changes the initramfs
and therefore the manifest, so it needs two clean builds and an independent
review before a second attempt.

## Transcripts

`linux-build-out/nvme-ioq-20260920/runs/20261024T204758.068603Z/`: `t6040-console-20261024-claude-astra-6001-gate-park.log`
`8db6324e…` (also `console-at-park.log` `09382958…`); chainload/boot logs
alongside, hashed in the run directory listing.
