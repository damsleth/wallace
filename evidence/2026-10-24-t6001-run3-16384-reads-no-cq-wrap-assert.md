# Ticket 6001 run 3 (2026-10-24): 16,384 direct reads complete; no CQ-wrap assert

Claude session under the `astra` lease handle (CJ's instruction), CJ
present. Reviewed manifest `c34f4391…` (testerfix; Sonnet review
PASS-with-notes, `evidence/2026-10-24-review-6001-tester-fix.md`). Image
`6eef9eef…` with the **zero-based ANS2 IOQ size** (ticket 6000), DTB
`a96d04a7…`, initramfs `524d94c3…`, `maxcpus=1`. Lease released
**healthy** at `Running proxy`.

## Result: the reads PASS on every substantive check

- Gate: `namespaces n1=1954210120 n2=6144 n3=262144`,
  `APPLE SSD AP1024Z`/`apple-nvme`, n1 + partitions + n2/n3 read-only.
- `START bytes=67108864 chunk=16384 passes=4 … ro=1` → `test exit=0`
  at 3.36 s.
- **Block counters, n1:** reads 13 → 16,397 (**+16,384**); sectors
  104 → 524,392 (**+524,288 = 256 MiB**); writes, discards and flushes 0;
  in-flight 0. **n2/n3:** unchanged.
- The tester returns 0 only after all 4 passes, with every read length checked
  and passes 2–4 byte-compared against pass 1. Every failure, including a
  detected kernel-log fault, exits 1. So exit 0 means
  `repeated_bytes_match=yes` for all 16,384 reads.
- Full kernel log (358 lines, `dmesg-run3-full.txt` `77094cef…`): **no**
  assert, crash, timeout, I/O error, SError, DART fault, panic or Oops.
- 16,384 completions on 64-entry I/O queues means the completion queue
  wrapped about 256 times. Every earlier Linux attempt asserted at the
  **first** wrap. That supports the 2026-09-20 finding: the driver wrote 64
  into the zero-based ANS2 IOQ-size field, while upstream and m1n1 write 63.

## Formal checker: NOT VALIDATED, for a logging reason only

`t6040-check-nvme-ioq-transcript.py` failed with "missing/duplicate complete
test PASS". Neither the console nor the ring buffer contains the
`NVME-READONLY PASS` line or the later progress lines, because
`/dev/kmsg` is rate-limited by default (`printk_devkmsg=ratelimit`) and the
kernel logged `printk: init: 60 output lines suppressed due to ratelimiting`.
The tester's stdout goes through `/dev/kmsg`. For a formal PASS the payload
should boot with `printk.devkmsg=on` (or rate-limit progress output), so
the PASS line cannot be dropped. That changes the bootargs, so it needs a
small re-review if CJ wants the formal checker green.

## Files

`linux-build-out/nvme-ioq-20261024b/runs/20261024T212008.670212Z/`: console
`t6040-console-20261024-claude-astra-6001-run3.log` `9dbabe75…`;
full dmesg `dmesg-run3-full.txt` `77094cef…`.

## What this does and does not establish

It establishes Linux NVMe **reads** through repeated CQ wraps at
`maxcpus=1` on this machine. It does not establish sustained or long-running
reads, writes (211), multi-CPU behaviour, or anything about the 227 teardown
UAF, which requires a dead controller and was not triggered.
