# Review 5006: m1n1 proxy NVMe Flush probe (`scripts/t6040-nvme-flush-probe.py`, `cf109b3`) — PASS with one must-fix (the fixture)

Date: 2026-10-25. Reviewer: claude (Mythos Wallace session), offline, host
only; nothing edited. Requested by Opus Wallace after 211 write run 1
(`evidence/2026-10-25-t6040-211-write1-flush-badcmd.md`).

Reviewed: `scripts/t6040-nvme-flush-probe.py` (sha256 `bc1e922d…`, equals
the ticket pin), its imported gate `scripts/t6040-nvme-probe.py`
(`66534e22…`, equals the pin), and m1n1 `src/nvme.c` / `src/proxy.c` /
`proxyclient/m1n1/proxy.py` at `80badc91` (`~/code/m1n1`).

## Verdict

**The script cannot write data and its failure handling is sound. The
ticket's fixture is wrong and must change before the run:** "runs on the
enrolled rollback proxy, no boot, no chainload" would execute `nvme_init`
on the July-14 rollback object (`rollback-m1n1-1394c345.bin`, m1n1
`a61fd099`), which predates the July-30 NVMe fixes and is the code path
that produced the July-25 fatal SError. Every successful m1n1-side NVMe
operation on this machine (174, 5001, 6001) ran on an NVMe-fixed m1n1
**chainloaded over the rollback proxy**; 5001 and 6001 pin that object as
`m1n1.bin 7de07c71…`. The probe must do the same.

## 1. Can it write data? No.

- **Proxy surface.** `src/proxy.h:162-165` / `proxy.py:687-690`: the
  entire NVMe surface is `P_NVME_INIT`, `P_NVME_SHUTDOWN`, `P_NVME_READ`,
  `P_NVME_FLUSH`. `NVME_CMD_WRITE` is a `#define` in `nvme.c:68` with no
  caller; there is no write function to reach.
- **What each call does on the media.** `nvme_init` (`nvme.c:325`): ANS
  bring-up, admin identify, create SQ/CQ, no namespace I/O. `nvme_read`
  (`nvme.c:615`): opcode READ, `cdw12 = 0` (one 4 KiB block), into a
  4 KiB-aligned m1n1 heap buffer (`u.memalign(0x4000, 0x1000)`; the
  function refuses unaligned buffers). `nvme_flush` (`nvme.c:601`): opcode
  FLUSH with the given NSID, PRPs 0, length 0; Flush commits the
  controller's volatile cache and carries no host data. `nvme_shutdown`
  (`nvme.c:550`): delete SQ/CQ, `CC.SHN`, RTKit sleep, PMGR reset; no
  namespace I/O. The identity `gate()` reads the ADT only.
- **The script issues exactly:** gate → `nvme_init` → `nvme_read(1, 0)` →
  `nvme_flush(1)` → `nvme_flush(0xFFFFFFFF)` → `nvme_read(1, 0)` →
  `nvme_shutdown`. LBA 0 of namespace 1 is the protective MBR; it is read
  twice and compared, never written. The broadcast NSID flush is a
  standard NVMe form and, like the NSID-1 flush, can only commit cached
  data that iBoot/the firmware already hold; it cannot alter any byte the
  host did not write. Nothing touches n2/n3 beyond the broadcast flush.

## 2. Failure handling

| Path | Behaviour | Verdict |
|---|---|---|
| gate fails | returns 1 before any NVMe transaction | correct |
| `nvme_init` returns false | returns 3; no shutdown call | correct: `nvme_init`'s error paths already PMGR-reset ANS (`nvme_shutdown` comment, `nvme.c:552-562`) |
| first read fails | returns 4; `finally` runs `nvme_shutdown` | correct |
| flush returns false (BAD_CMD, as in write 1) | logged as `FAILED`, not fatal; sequence continues | correct and intended: `nvme_exec_command` consumed the CQE and advanced the head (`nvme.c:262-283`), so the queue is consistent for the re-read |
| re-read differs or fails | rc 5, RESULT line still printed | correct |
| proxy exception (hang, SError) | rc 6, shutdown attempted and its exception swallowed | correct; recovery is the documented warm reboot |
| rc semantics | rc 0 even if both flushes FAILED | acceptable because the verdict is the `FLUSH-PROBE RESULT nsid1=… broadcast=… link_alive=…` line; the evidence write-up must key on that line, not the exit code (note 2) |

One case the script cannot handle, and should state: a flush that **times
out** (no completion at all, `nvme.c:310`) leaves m1n1's single-tag queue
out of step; the re-read then reports "invalid tag in CQ" or fails and the
shutdown's delete SQ/CQ fail. The script still reaches `nvme_shutdown`,
which PMGR-resets ANS regardless, and the machine is then warm-rebooted.
That is the same recovery as every proxy probe so far; it is a reporting
caveat, not a defect.

Module import: `exec_module` of `t6040-nvme-probe.py` runs only its
definitions (its `main()` is behind `if __name__ == "__main__"`), and its
`from m1n1.setup import *` reuses the already-connected module. No second
proxy connection, no argument parsing side effects.

## 3. Must-fix: the fixture

`nvme_init` on T6040 needs the two July-30 fixes (reg-entry count
`reg_len/16 >= 10`, and the FW `V_UNKNOWN` skip of the legacy
`LINEAR_SQ_CTRL` write at `reg[3]+0x24908`; see
`evidence/2026-07-30-t6040-NVME-READ-WORKS.md` and the memory note). The
enrolled rollback `1394c345` is the July-14 `a61fd099` build and does not
have them; on it, `nvme_init` is the path that raised the July-25 fatal
SError. The probe therefore runs **over a chainloaded NVMe-fixed m1n1**,
exactly as 174 (`ae4a8f28`), 5001 and 6001 (`7de07c71`) did:

1. Chainload `m1n1.bin 7de07c71…` (the 5001/6001 pin; verify the hash) over
   the enrolled rollback proxy and wait for its `Running proxy`.
2. Run the probe against that proxy.
3. The ticket text and its `target` hash entry should say so; "no boot" is
   right, "no chainload" is not.

If a newer Wallace m1n1 is preferred, pin it by hash and confirm by
`git log` that it contains `1702259f`'s fixes.

## Notes (non-blocking)

1. The outcome discriminates firmware acceptance of a **zeroed TCB with
   `dma_flags = 3`** (m1n1's encoding, `nvme.c:238-240`) by NSID; it does
   not by itself say which of the three Linux differences (TCB not zeroed,
   `dma_flags = FROM_DEVICE`, NSID) is the one the firmware rejects. The
   ticket's decision tree (nsid1 OK → TCB-level fix; only broadcast OK →
   NSID fix; both fail → write-through) is the right reading of it.
2. Key the evidence on the `FLUSH-PROBE RESULT` line and on the ANS syslog
   lines around each `FLUSH-PROBE nsid=` line (`host_ans2.c:1616 … fast
   decode err` would show the same rejection as under Linux); hash the
   full console transcript before the reboot.
3. `before`/`after` compare 4096 bytes; a flush cannot change LBA 0, so a
   mismatch would indicate a transport problem, not a flush effect. The
   message could say so.
