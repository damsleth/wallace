# Permanent review: m1n1 stage-2 log-ring upper guard

Reviewed 2026-07-14 for ticket 042. The live-proven fix is already retained as
a normal code change on both m1n1 worktrees, not merely in an abandoned
diagnostic build. No additional code churn or rig run is needed.

## Permanent state

- m1n1 main fix: `a61fd09926c9660593715d7a9ce8e93b914390b9`
- curated `t6040-bringup` fix:
  `cb64c3a0c2b5b2ad2cf1dbf0bf27c352492c696d`
- both commits are ancestors of the current respective heads
- current main and curated `src/kboot.c` are byte-identical
- both commits have author and Signed-off-by identity
  `CJ Damsleth <kim@damsleth.no>`
- the current op-115 candidate builds in both worktrees while retaining the
  guard, confirming it has survived the later PCIe diagnostic series

The implementation asks `top_of_memory_alloc()` for 32 KiB, exposes only the
lower 16 KiB as `m1n1_stage2.log`, and leaves the upper 16 KiB unused. The
allocator removes the entire allocation (plus its existing lower guard page)
from `cur_boot_args.mem_size` before `dt_set_memory()` constructs Linux's
`/memory` node. Only the active lower page receives a phram reserved-memory
node. The unused upper page is therefore neither part of Linux RAM nor an MTD
device.

This is a general kboot safety property even though it was diagnosed on T6040:
the first top-of-memory allocation can occupy the final physical page because
the allocator's pre-existing guard is inserted below that allocation. An upper
slack page prevents a wrapping log writer from touching the exclusive RAM
boundary. It costs 16 KiB and adds no MMIO, system-register access, firmware
call, or hardware write.

## Evidence review

The prior unguarded layout placed the active ring at
`0x105ce7a4000..0x105ce7a8000`, exactly ending at top of RAM. Its first 8 KiB
wrap completed, then a delayed L2C access-fault SError appeared 1,082 log bytes
later. This false attribution consumed four traced PCIe runs even though the
zero-write control performed no PCIe MMIO.

The explicitly approved guarded control observed:

```text
FDT: Usable memory is ...0x105ce79c000
FDT: Adding reserved-memory node flash@105ce7a0000
     (105ce7a0000..105ce7a4000) to RAM map
```

All 77 dry-run tunable entries printed through completion, m1n1 handed off to
Linux, and the DockChannel console reached a shell without SError. Transcript
and artifact hashes remain pinned in
`done/2026-07-14-t6040-logbuf-upper-guard-control.md`.

The review found no overlap or hidden semantic expansion:

- `LOGBUF_SIZE` and the phram-visible size remain 16 KiB;
- only the allocator request grows to 32 KiB;
- the ring modulo and copies still use `LOGBUF_SIZE`;
- the guard is applied on every kboot target, with no T6040 runtime branch;
- subsequent PCIe builds retain the same `src/kboot.c` fix.

## Upstream note draft

Draft only; CJ posts or mails it.

Subject: `kboot: keep the stage-2 log ring below the top-of-RAM boundary`

> `top_of_memory_alloc()` can return the final physical pages of RAM for its
> first allocation; its existing guard page is below that allocation. The
> stage-2 log ring was consequently placed at the exclusive top-of-RAM
> boundary on a T6040 J614s. After the 16 KiB ring wrapped, the machine raised
> a delayed L2C access-fault SError. A zero-MMIO control reproduced the failure,
> while reserving one unused 16 KiB page above the active ring eliminated it
> and booted Linux cleanly. Allocate 32 KiB for the log backing but advertise
> and use only the lower 16 KiB. Both pages remain outside Linux's memory node;
> the extra cost is 16 KiB and there are no hardware accesses.

Suggested evidence footer:

```text
Tested-on: Apple MacBook Pro (14-inch, M4 Pro, J614s/T6040)
Active ring: 0x105ce7a0000..0x105ce7a4000
Unused upper guard: 0x105ce7a4000..0x105ce7a8000
Result: 77-entry zero-MMIO trace wrapped and booted Linux without SError
```

The existing single-file commits above are already upstream-shaped. Do not
attach the proprietary transcript or imply that the delayed SError was caused
by PCIe; the zero-write control disproved that attribution.
