# Ticket 3000: the Linux a1 SPMI stall is a raw-vs-CPU-physical address error

Date: 2026-08-19. Agent: sol. Scope: offline static analysis only. No lease,
rig command, MMIO, SPMI transaction, build, or target/storage mutation occurred.

## Result

Ticket 305 did not establish that the real `nub-spmi-a1` controller is
inaccessible from Linux. Runs 1--4 mapped and accessed the ADT's **raw
`/arm-io` bus address** `0x309198000`, not the translated CPU physical address
`0x509198000` that the July m1n1 experiments used successfully.

The minimal grounded correction is DT-only:

```diff
- nub_spmi_a1: spmi@309198000 {
-     reg = <0x3 0x09198000 0x0 0x4000>;
+ nub_spmi_a1: spmi@509198000 {
+     reg = <0x5 0x09198000 0x0 0x4000>;
```

The existing `power-domains = <&ps_nub_spmi_a1>` correction remains required.
No Linux driver or AppleSPMIController initialization change is justified
before a reviewed candidate tries the corrected physical address.

## Address proof

Both captured 606,208-byte ADTs give `/arm-io` this first range:

```text
child bus 0x000000000 -> parent CPU physical 0x200000000, size 0x480000000
```

`/arm-io/nub-spmi-a1` has three raw `reg` tuples:

| bank | raw `/arm-io` address | CPU physical after `ranges` | size |
|---:|---:|---:|---:|
| 0 | `0x309198000` | `0x509198000` | `0x4000` |
| 1 | `0x309194000` | `0x509194000` | `0x4000` |
| 2 | `0x309190000` | `0x509190000` | `0x4000` |

This was already byte-proved during ticket 093: attempt 2 failed closed
because it compared `adt_get_reg()`'s translated result to the raw tuple, and
commit `471700035efd` corrected the identity gate to validate both forms.
Attempt 3 then ACKed real SPMI commands. Ticket 095 subsequently completed
WAKEUP, selector/data-window traffic, and SSPS-to-S0 on the translated bank.

The topology is identical in both captured inputs:

```text
7a92e6e4d16cb1b5a5858beb22b22acc8e5ed4b36ed5d5ccde9b251f1da55c84  j614s-usb-port-map-20260721.adt
2fe477c613c67e44550ded1bbb6cad9cf4fffc62393b47b39edc6c11281df4ba  j614s-full-20260728.adt
```

## What each software stack maps

### July m1n1: translated physical `0x509198000`

`src/t6040_hpm2.c` obtains the bus with
`spmi_init_strict("/arm-io/nub-spmi-a1")`. `src/spmi.c` calls
`adt_get_reg(..., 0, &base, ...)`; the Rust `adt_get_reg()` implementation walks
parent `ranges`, so `dev->base` is `0x509198000`. The exact ticket-095 artifact
was:

```text
commit 276f4059d8c4130ce56525f263afa1ef110447d1
23737cd31407c1046fb3c4e56e3a34f898ea845b8e98b978a98166eafe32b271  m1n1.bin
630fe61aa8d8701a3e39968470cdc9a9789077d454a1a0749c09f76aee2272a5  hpm2-r2-ssps-s0-20260724.log
```

That transcript records validated Gen3 commands and replies through hpm2 SID
`0x0c`, ending with power state `0x00` and `class R2 PASS`.

### Rollback m1n1: same MMU translation and attributes

The enrolled rollback binary is reproducibly built from m1n1 commit
`a61fd09926c9660593715d7a9ce8e93b914390b9`:

```text
1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b  rollback-m1n1-1394c345.bin
```

Between `a61fd099` and the live-proven `276f4059`, `src/memory.c` and
`rust/src/adt.rs` are byte-identical:

```text
a61cd78a4efc500db89562ee10e2af7c7e98c1ad7a0f86cf84f340f4edfc8e73  src/memory.c
3771322ab6ab7b9c28807857fa77672ae6b09bb58588d46d94bc58f144afdd97  rust/src/adt.rs
```

`mmu_map_mmio()` maps the **parent** `/arm-io` ranges identity with
Device-nGnRnE. The first mapping is CPU physical
`0x200000000..0x680000000`, covering both the correct `0x509198000` and the
incorrect `0x309198000`. Therefore ticket 305's suggestion that the rollback
proxy exception was probably an unmapped-address fault is refuted by source.
The probe is still inconclusive about hardware because it mixed a powered-state
question with addresses, and its complete ESR/FAR/order was not captured.

### Linux ticket-305 DTB: wrong physical `0x309198000`

Linux `t6040.dtsi` defines `/soc` with an empty `ranges;`, so child addresses
are already CPU physical. The known-working primary controller follows this
rule:

```text
/soc/spmi@509014000 reg = <0x5 0x09014000 0x0 0x100>
```

In contrast, the ticket-305 source and compiled run-5 discriminator contain:

```text
/soc/spmi@309198000 reg = <0x3 0x09198000 0x0 0x4000>
```

Exact artifacts inspected:

```text
5e21a0ece2b5f6a93604c0f8207f52d7bee7173bb2ec3fecb20f7f4ef6ea8a16  dts/t6040-j614s-dcuart-usb2-native-right-pd.dts
db1299ea082086fd5f3b6b8dd247f17f0e6eb6d89d49b10199db09f8823c5a50  t6040-j614s-dcuart-usb2-native-right-pd.dtb
5a136710684dbda738cfb51ea0149b9cf64d2ca58c15f1c66a1d6b0310ad9af8  Image-usb2pd.buildA
```

`fdtget` returns `3 9198000 0 4000` for that DTB. The platform resource is
passed unchanged to `devm_platform_ioremap_resource()`, which maps it as arm64
Device-nGnRE. The attribute difference from m1n1 is not the discriminator:
the same Linux driver and mapping attribute work on `spmi@509014000` in ticket
305 run 5. The physical address is the load-bearing mismatch.

## Verdict on ticket 305 runs 1--5

| Question | Verdict |
|---|---|
| ADT raw tuple correct? | Yes: `0x309198000/0x4000`. |
| CPU physical address correct in the Linux DT? | **No:** must be `0x509198000/0x4000`. |
| Linux and m1n1 touched the same controller bank? | **No.** |
| Did runs 3/4 prove the real a1 block stalls when powered? | **No.** They accessed the wrong physical address. |
| Is an Apple-specific init write currently required? | Not established; ticket 1002 becomes fallback work only if the corrected address still stalls. |
| Is ticket 1000's print-only stall localization the next run? | No. First test the corrected DT-only address; instrument only if that still stalls. |

This explains the otherwise puzzling combination of facts: the July m1n1
traffic worked, Linux `nub-spmi0` worked, the a1 domain reported on, and every
Linux access to its purported a1 address hung. Linux was never addressing the
real a1 bank.

## Next action

Create a new offline candidate from the already-reviewed ticket-305 fixture
with only these effective changes:

1. rename the node to `spmi@509198000` and set `reg` to
   `<0x5 0x09198000 0x0 0x4000>`;
2. retain `power-domains = <&ps_nub_spmi_a1>`;
3. re-enable only hpm2/SID `0x0c`; keep ANS/NVMe disabled;
4. build the DTB twice from clean trees and decompile both;
5. prove the Image, initramfs, driver patch, endpoint, transaction envelope,
   bootargs, and fixture are otherwise unchanged;
6. obtain independent exact-artifact review before resuming attended ticket
   305.

No new kernel build is technically required for the address correction; the
pinned `Image-usb2pd.buildA` may be reused if the review confirms it is exactly
the already-approved image. A boot remains rig work and is not authorized by
this offline result.
