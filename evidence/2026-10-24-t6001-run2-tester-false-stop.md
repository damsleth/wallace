# Ticket 6001 run 2 (2026-10-24): gate passed; the tester's log watchdog false-stopped before its first read

Claude session under the `astra` lease handle (CJ's instruction), with CJ
present. Gate-fixed manifest `84b0275f…`; payload initramfs `c76063ac…`;
Image/DTB/m1n1 identical to the reviewed payload. Lease released **healthy**
at `Running proxy`. Transcript
`linux-build-out/nvme-ioq-20261024/runs/20261024T210002.623144Z/t6040-console-20261024-claude-astra-6001-run2-tester-falsestop.log`
(`51451988…`).

## What happened

- The new gate passed: `namespaces n1=1954210120 n2=6144 n3=262144
  sectors`, `identity transport=apple-nvme model=APPLE SSD AP1024Z`, and n1,
  its partitions, n2 and n3 were set read-only.
- The tester stopped at its startup kernel-log scan, **before opening the
  namespace**: `kernel stop: 6,5,0,-;printk: debug: ignoring loglevel
  setting.`. Counters before and after are identical: n1 13 reads / 104
  sectors (the kernel's partition scan), n2/n3 unchanged, zero writes.
- No SError, DART fault, ANS crash, assert or reset.

## Cause

`strcasestr(line, "BUG:")` matches `de` **`bug:`** in the kernel's
`printk: debug: ignoring loglevel setting.`, which is printed because the
payload's own bootargs contain `ignore_loglevel`. Every boot of this payload
false-stops, so run 1 would have hit it too had its gate passed. The host
checker has the same defect (`re.I`), and with `panic` it would also have
matched ANS's benign `element=PANICLOG not yet written`.

## Fix (in progress)

`scripts/t6040-nvme-readonly-test.c` and
`scripts/t6040-check-nvme-ioq-transcript.py`: upper-case tokens (`SError`,
`panic`, `BUG:`, `Oops:`, new `RTKit: Exception`) are matched
case-sensitively. Lower-case fault phrases stay case-insensitive (`assert`,
`I/O error`, `timed out`, `timeout:`, `timeout while`, `controller is down`,
`crashed`, `translation fault`). Linux's RTKit and nvme-apple crash/timeout
strings at 4f24291 are all lower-case, so nothing is lost. The tester must be
rebuilt (static aarch64), then the initramfs twice, a new manifest, and
review before run 3.

## Run-3 payload (built)

- Tester rebuilt in the kbuild container with GCC 12.2.0 (Debian),
  `-O2 -static -Wall -Wextra -Werror`, from source named
  `t6040-nvme-readonly-test.c`. The same command on the **original** source
  reproduces the reviewed binary `0ffb3e55…` byte-for-byte, so the flags
  match. The fixed source (`9372f143…`) builds `aef24ab9…` twice,
  identically.
- Initramfs built twice from the pinned base and the fixed tester:
  `524d94c3…`, identical. Candidate `linux-build-out/nvme-ioq-20261024b/`,
  manifest `c34f4391…`. Against the gate-fixed manifest `84b0275f…`, exactly
  initramfs, checker (`0481319f…`) and tester source changed. Image, DTB and
  m1n1 are unchanged. The reviewed launcher's verify-only pass: all 241 files
  verified, preflight OK.
- Checker against synthetic transcripts: passes with both real false
  positives present (`printk: debug:` and `PANICLOG`). It stops on a kernel
  panic, a kernel `BUG:`, an RTKit "co-processor has crashed" and an RTKit
  exception dump.
