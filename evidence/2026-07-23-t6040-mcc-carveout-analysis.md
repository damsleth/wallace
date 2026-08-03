# T6040 MCC carveout and cache-enable closure

Ticket 020 (offline, P2), 2026-07-23. This was a static/source audit only. The
rig was not leased or touched; no MCC MMIO read or write was performed.

## Outcome

The unresolved T6041 TrustZone-register offset is **not a Linux boot-image
blocker**. Linux is given only the boot-argument normal-RAM interval, and both
MCC-protected regions used by m1n1's older-SoC logic lie outside it. Failure to
discover and unmap those regions therefore leaves an m1n1 EL2 hardening gap,
not memory which Linux can allocate.

The `mcc_enable_cache()` write is also no longer experimental. It writes the
already-observed value `1` to the already-enabled plane-0 cache-control
register, then polls the hardware-verified T6041 status `0x00010101`. That path
completed in the first Stage-C handoff and has preceded the project's many
subsequent BusyBox and Alpine boots.

Ticket 020 is closed with no new hardware experiment. A future upstream-quality
MCC series should still improve the EL2 carveout handling, but B0/B1 bootable
image work must not wait for it.

## 1. Exact J614s memory boundary

Source capture:

- `/Users/damsleth/Code/linux-build-out/j614s-usb-port-map-20260721.adt`
- size: 606,208 bytes
- SHA-256:
  `7a92e6e4d16cb1b5a5858beb22b22acc8e5ed4b36ed5d5ccde9b251f1da55c84`

The captured `/chosen` node reports 24 GiB at DRAM base
`0x10000000000`. The boot arguments observed in the saved chainload log give:

```text
phys_base: 0x100032a8000
mem_size:  0x5cb500000
top:       0x105ce7a8000
```

The same top appears repeatedly in the later log-buffer controls. kboot's
`dt_set_memory()` starts the Linux `/memory` range at `phys_base` and ends it at
the current `phys_base + mem_size` (usually slightly lower after top-down
allocations).

The two regions named by the existing m1n1 MCC comment are:

| ADT region | interval | relation to Linux RAM |
|---|---|---|
| region-id-4 | `0x105ce7a8000..0x105d06d8000` | begins exactly at the original exclusive normal-RAM limit |
| region-id-2 | `0x105d9ce4000..0x105ff4e4000` | entirely above the normal-RAM limit |

Therefore neither interval is in Linux `/memory`; reserved-memory nodes are not
needed to keep Linux away from them. This also explains why all later kernels
remain stable despite the all-zero T603x TZ register reads.

There is still an m1n1-local issue. `mmu_add_default_mappings()` initially maps
all `mem_size_actual`, including carveouts, into the broad EL2 identity mapping
and then calls `mcc_unmap_carveouts()`. On T6041, the reused T603x register
description finds zero enabled entries, so those ranges remain addressable to
m1n1. No current path intentionally accesses them, but an upstream patch should
restore least-privilege behavior.

## 2. Cache-enable write analysis

The live Phase-2 observations remain internally consistent:

- four AMCCs from ADT `reg[12..15]`;
- one backed cache plane per AMCC;
- `PLANE_CACHE_ENABLE` (`+0x1c00`) already reads `1`;
- `PLANE_CACHE_STATUS` (`+0x1c04`) reads `0x00010101` on all four.

For T6041, `mcc_enable_cache()` performs exactly four identical operations:

1. write `1` to plane 0 at `AMCC base + 0x1c00`;
2. poll `(status & 0x00010101) == 0x00010101` at `base + 0x1c04`.

There is no plane-1 iteration and `cache_disable` is zero. The operation is
idempotent relative to the iBoot state. The first Stage-C run printed
`MCC: System level cache enabled`; disabling the call did not alter the old
L2C SError, which was later isolated to `dapf_init_all()`. The standard call has
since been part of every successful kboot handoff.

Conclusion: keep this exact write/poll path. It does **not** authorize other
T6041 MCC writes, DCS accesses, way-mask changes, or guessed offsets.

## 3. Static Apple-firmware cross-check

The canonical paired restore used for the trackpad extraction was reused:

```text
UniversalMac_26.5.2_25F84_Restore.ipsw
BuildManifest SHA-256:
a6e764ca158e10ea2ace9b74701f445eefbf012c9cdb5aaa616aa10a0b5197ef
identity: j614sap / macOS Customer / Erase
```

That identity selects `kernelcache.release.mac16j` and
`Firmware/all_flash/iBoot.j614s.RELEASE.im4p`.

| Artifact (temporary; not committed) | Size | SHA-256 |
|---|---:|---|
| kernelcache IM4P | 31,827,787 | `4cc018b4ab925d879a0f039bf1f83cdbd11dc0bd906910afd1f9d15befabad1b` |
| decompressed kernelcache | 119,209,984 | `ed556fe62efc2c229f3d4c7ebbbcd21fd5c8d099fbb4d9b5ae636dd78b61d3f6` |
| extracted `com.apple.driver.AppleT6041MCC` | 325,720 | `155f888625b8a9c271f51e1a45035bd577930787d5f17352fb4a1108f7944b2e` |
| iBoot IM4P | 1,254,415 | `df93365c9346561cbaac7634be92955a86871d6f3d68ab0e5361eb07c552ec3f` |
| decompressed mBoot 18000.121.3 | 3,943,104 | `aa52ca22bae0ad87ef01f01e96f13ec69c1e96850e525c005980fdd61af7a689` |

The AppleT6041MCC kext is symbol-rich. Its T6041 subclass `start()` installs
performance-counter tables and delegates to the generic memory-cache
controller. The binary contains no TZ/carveout/region-id strings and no direct
memory operand at the old `0x6d8/0x6dc/0x6e4` offsets. This is useful negative
evidence: the macOS runtime driver is not an easy source for the boot-time
protection-register map. It is not proof that the hardware has no such
registers.

mBoot contains `chosen/carveout-memory-map`, `tz0..tz3`, and related security
region strings and constructs the carveout map dynamically. The exact
J614s region page values do not occur as literal constants. A bounded static
reconstruction of the responsible iBoot routine remains possible, but is no
longer on the Linux boot critical path.

## 4. Safe follow-up shape

Preferred future implementation, under ticket 046 review:

1. give T6041 an explicit carveout strategy instead of silently reusing
   `t603x_tz_regs`;
2. read region-id-2 and region-id-4 from the already-captured ADT;
3. reject absent, overflowing, unaligned, or in-normal-RAM intervals;
4. remove only the validated intervals from m1n1's four EL mappings and expose
   them through `mcc_carveouts`;
5. compare behavior against older SoCs and format/build-test before any rig run.

This is a safer route than a live AMCC value sweep and does not require an MMIO
access. Alternatively, finish static iBoot reconstruction and use the real
T6041 register description. **Do not blind-probe the AMCC window.**

One comment in the current local MCC commit also needs correction during ticket
046: a fault at the T6031 *plane-1* address (`base + 0x40000 + 0x1c00`) proves
that plane stride is invalid, but does not prove that every higher sparse
aperture such as global `+0x100000` or DCS `+0x400000` is unbacked. Those
offsets remain unverified—not disproven.
