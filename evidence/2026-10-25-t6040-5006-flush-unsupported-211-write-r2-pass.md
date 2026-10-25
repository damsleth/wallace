# 5006 flush probe: ANS2 rejects NVMe Flush outright. 211/5003b write-through write: PASS

claude, lease `claude`, 2026-10-25 07:4x CET. CJ killed `deviceinterfaced` and
approved 5006. Reviews: Mythos PASS for 5006 (with the fixture must-fix done)
and PASS-with-notes for 5003b.

## 5006: m1n1 proxy flush probe (`/Users/damsleth/Code/linux-build-out/nvme-flush-probe-20261025/run1/flush-probe.log`)

The m1n1 was the hash-verified chainloaded `7de07c71`, not the rollback.
Identity gate OK, then `nvme_init` OK and `read(nsid=1, lba=0)` OK. Then:

```text
nvme: command failed with status 2
FLUSH-PROBE nsid=0x1 -> FAILED
nvme: command failed with status 2
FLUSH-PROBE nsid=0xffffffff -> FAILED
  re-read(nsid=1, lba=0) -> 1, identical=True
FLUSH-PROBE RESULT nsid1=False broadcast=False link_alive=True
```

m1n1's own encoding also fails: it zeroes the TCB, sets `dma_flags=3` and a
minimal SQE. That rules out the TCB theory. The firmware rejects NVMe Flush
(status 2, Invalid Field) whether the NSID is 1 or broadcast. m1n1's admin
delete-SQ/CQ commands fail with status 2 as well. `t6040-nvme-apple-flush-tcb.patch`
is therefore **not** the fix; it stays opt-in and unused. How macOS makes ANS2
durable is unknown, possibly a vendor command. That is an open RE item.

## 211 stage 1 retry: 5003b, `nvmewritedir=r2 nvmewc=through`

Console `/Users/damsleth/Code/linux-build-out/nvme-exfat-write-20261025b/runs/write-r2/t6040-console-20261025-claude-211-write-r2.log`. Checker:
**PASS** (`write_cache=write through`).

- Pins OK, then `fsck.exfat -n (before)` clean. 18 directories and 96 files:
  **run 1's test directory and file are gone.** The parked shell after run 1
  showed 19/97, but that did not survive the hard reset (`macvdmtool reboot`).
  What run 1 wrote without a working flush was lost.
- 1 GiB written in 2.6 s (about 410 MB/s). sha256 `e26c3c8a…`.
  `fsck -n` clean after the write. After `drop_caches` the read-back hash
  matches (about 210 MB/s, sha256-bound at maxcpus=1). Final fsck clean, 19/98.
- Sectors written: disk 2,097,552 = p3 2,097,552. Others unchanged. **No**
  BAD_CMD, flush or I/O-error lines.

## Durability: what comes next

The hard-reset verify (`nvmewrite=verify nvmewritedir=r2 nvmewc=through`) is
the real test. Run 1 shows that unflushed data can be lost on a hard reset even
minutes later. If r2 also fails to survive, write-through alone does not make
the NVMe a safe daily-driver root. Durability would then depend on a controller
shutdown (CC.SHN) at clean poweroff, which needs its own test, or on finding
Apple's real flush.

The recovery reboot at 07:51:07 happened about 1–2 minutes after the PASS.
After it the M4 showed iBoot trace output and then fell silent: no m1n1 proxy,
and the second recovery reboot did not help. kisd panicked once
(`bytes.rs split_to out of bounds`) and was restarted. CJ has been asked to
check the screen.
