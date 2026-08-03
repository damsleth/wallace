# T6040/J614s DCP upstream watch and DT preparation (ticket 022)

Date checked: 2026-07-23

This is an offline, read-only checkpoint. It did not touch the rig and did not
edit `~/Code/linux`, whose `t6040-j614s-dcuart.dts` already has an unrelated
user modification.

## Upstream state pinned

Primary sources:

- AsahiLinux/m1n1 PR 630,
  [`DCP: Add initial 14.7/14.8.3 ABI`](https://github.com/AsahiLinux/m1n1/pull/630):
  still open at `7e391ffde033bf2fa0e22cc5bda575f83d2d584b`, nine commits,
  updated 2026-07-22.
- chadmed/linux branch
  [`dcp/14.8.3`](https://github.com/chadmed/linux/tree/dcp/14.8.3):
  `f4df8984b39affb6d661ac67d097c131132b8f26`.

PR 630 is m1n1/proxyclient protocol-description and tracing groundwork. The
Linux branch adds a 14.7-compatible method/structure set and selects it for
14.7-era firmware. Its ABI commit
`62e19ee7fe23b123b3cf38e5607f1625f53d1ad0` explicitly remains WIP: overlay
surfaces are broken, machines whose default is not `surface0` are not covered,
some new fields/offsets are uncertain, and the swap structure has unexplained
tail data. The branch tip defines plane/compression parameters but does not
remove those firmware-ABI qualifications.

This is useful evidence that the driver can be extended across DCP firmware
generations. It is **not** T6040 or macOS 26.x support. No source checked here
accepts a 26.x `apple,firmware-compat`, defines the J614s method table, or
accounts for the extra target MMIO/interrupt shape below.

## Target evidence

The source is the captured, byte-exact J614s ADT:

```text
/Users/damsleth/Code/linux-build-out/j614s-usb-port-map-20260721.adt
SHA-256 7a92e6e4d16cb1b5a5858beb22b22acc8e5ed4b36ed5d5ccde9b251f1da55c84
```

It was parsed offline with the current m1n1 `adt.py`.

### Internal display

| ADT node | Registers | IRQs / translation |
|---|---|---|
| `disp0` | `0x200000000/0x4000000`, `0x202240000/0x10000`, `0x2023a8000/0x4000`, `0x202800000/0x800000`, **`0x304800000/0xbc000`** | inputs 1080–1089 plus 1100 (1081 appears twice); compatible `disp0,t604x` |
| `dart-disp0` | `0x202300000/0xc000`, `0x202314000/0x4000`, shared error reflector `0x300578000/0x4000` | input 1090; 32 SIDs; 16 KiB pages; DART ID 17 |
| `dcp` | ASC wrapper `0x202e00000/0x88000`, secondary window `0x202850000/0x4000` | eight inputs: 1144, 1143, 1146, 1145, 1148, 1147, 1150, 1149; power gate 430 |
| `dart-dcp` | `0x202340000/0x20000`, shared error reflector `0x300578000/0x4000` | input 1090; firmware SID 23; 32 SIDs; 16 KiB pages; DART ID 18 |
| `dcp0-expert` | `0x2023a8050/4`, `0x202374000/0x40`, `0x202370000/0x40` | input 1085 |

The `dcp/iop-dcp-nub` firmware is preloaded and running. Its segment table is
available to m1n1 for the normal reserved-memory handoff.

### External display engines

Only `dcpext0` and `dcpext1` exist even though stale ADT aliases for
`dcpext2/3` remain:

| engine | ASC wrapper | DCP DART | display DART | shared IRQ |
|---|---|---|---|---|
| `dcpext0` | `0x1a2e00000/0x88000`, `0x1a2850000/0x4000`; ASC inputs 1218–1225 | `0x1a2340000/0x20000` + reflector | `0x1a2300000/0xc000`, `0x1a2314000/0x4000` + reflector | 1165 |
| `dcpext1` | `0x402e00000/0x88000`, `0x402850000/0x4000`; ASC inputs 1290–1297 | `0x402340000/0xc000` + reflector | `0x402300000/0xc000`, `0x402314000/0x4000` + reflector | 1237 |

The target PMGR data already has the internal `disp_sys → disp_fe → disp_cpu`
and external `dispextN_sys → dispextN_fe → dispextN_cpu` chains. The current
raw-boot DT intentionally leaves `ps_disp_cpu` disabled to preserve the
firmware-owned scanout; enabling a DCP driver cannot silently undo that proven
PMGR safety policy.

## Prepared Linux DT shape

The existing t602x nodes give the structural template. A future T6040 patch
should add, initially disabled:

1. `dart-disp0` and `dart-dcp`, preserving all target register banks rather
   than truncating them to the older one-bank form.
2. An ASC mailbox node inside the `0x202e00000/0x88000` wrapper contract.
3. The DCP node with the target SID established from the ADT and driver
   contract (the DART node declares 23, rather than the older DTs' common SID
   5), the display DART `piodma` child, and the target PMGR domain/reset
   relationship.
4. `display-subsystem` with `iommus = <&disp0_dart 0>`.
5. FDT aliases `dcp = &dcp` and `disp0 = &display`. These names are the m1n1
   kboot contract; the target ADT spelling `dcp0` does not replace them.
6. External nodes only after the internal engine works and ATC/DP routing is
   described.

m1n1 already does the loader half when those FDT aliases exist:

- its T6040 branch reuses the verified t602x display carveouts
  (region IDs 49, 50, 57, 94, 95 and 157);
- it attaches the boot framebuffer and DCP data mappings;
- it reserves preloaded `dcpext0/1` ASC firmware segments;
- it writes the firmware version/compat properties; and
- it enables the relevant DART/DCP nodes only after the mappings exist.

## Blockers before authoring an enabled node

1. **Firmware ABI:** the J614s 26.x DCP method and structure set is absent.
   Adding a compatible string or borrowing the 14.7 table would be dishonest.
2. **Binding/MMIO delta:** `disp0` has a fifth `0x304800000/0xbc000` window
   beyond the current `disp-0` through `disp-3` contract. Its role and whether
   the driver needs a fifth resource must be established upstream.
3. **ASC interrupt delta:** the target wrapper exposes eight paired inputs;
   the old `apple,asc-mailbox-v4` DT shape has four. The correct selection or
   mailbox-binding extension must be proven, not guessed.
4. **DART shape/SID:** T6040 DARTs have extra register banks and the running
   DCP mapping uses SID 23, while older DCP DTs commonly use SID 5.
5. **Raw-boot PMGR ownership:** `ps_disp_cpu` is deliberately isolated while
   simpledrm consumes firmware scanout. A DCP test requires a separate,
   reviewed ownership-transition plan.

## Decision

Keep ticket 022 open as an upstream watch. The DT preparation half is now
bounded and reproducible, but there is no safe or useful local DCP build to
test yet. `simpledrm`/fbcon remains the correct B0 and daily-driver interim:
it already renders the firmware framebuffer and avoids all five unresolved
DCP ownership/ABI boundaries.
