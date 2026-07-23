# T6040 PCIe op-115 clkgen-PLL candidate — rig preflight (2026-07-23)

Pre-approval packet for a single **read-only** retest of the op-115 boundary with
the PCIe-PLL bring-up that `_configPciePLLs` performs and m1n1 omitted. Grounded
decode + rationale: `done/2026-07-21-t6040-pcie-op115-routefind.md` (ticket 058).
This changes m1n1 only; it still stops at the existing op-115 read-only
diagnostic (reads `0x417040090` once, returns before any PHY-IP write). Awaiting
independent cross-review + CJ approval; not booted.

## The change (m1n1 commit `e4671e08`, one hunk in `src/pcie.c`)

After the `apcie-pcieclkgen-tunables` apply and before the PHY clock gate, on the
`regs_t6040` path only, replay the decoded clkgen (ADT `reg[6]`) sequence:

```c
set32(clkgen_base + 0x4, 0x80000000);   /* PLL enable (bit 31) */
mask32(clkgen_base + 0x0, 0x7, 0x1);    /* low field <- 1 */
if (poll32(clkgen_base + 0x0, 0x80000000, 0, 250000)) { /* wait PLL lock */
    printf("pcie: T6040 clkgen PLL did not lock\n"); return -1;
}
```

`clkgen_base` = `adt_get_reg(reg[APCIE_T6040_PCIECLKGEN_IDX=6])` — ADT-derived,
not hardcoded. Offsets `0x0`/`0x4` and values `0x80000000`/`0x1`/mask `0x7` are
read directly from `ApplePCIEBaseT8132::_configPciePLLs` (anchors in the 058
writeup). The existing `regs_t6040` op-115 read-only stop
(`tunables_read_first_local_addr_trace(...); return -1`) is unchanged.

## Exact live inputs (pinned)

| Input | SHA-256 |
|---|---|
| `m1n1.bin` (candidate, commit `e4671e08` on `16b1f61f`) | `3e0c90af77e1f13930e432f3ed124215d2ddeb6de050c8b29b90173a2818f31f` |
| `m1n1.macho` | `2373e435677d5cf97ba9e2eee065abb7d659a7badcc7bd687896f1ae59ea5ae3` |
| PCIe-free `t6040-j614s-dcuart.dtb` (reviewed base, unchanged) | `b3858f60aa96ab81f7314659284174cb10ddcec061140c1c67d397f52d617814` |
| `initramfs-dcuart.cpio.gz` (unchanged) | `512c69da94884f3ea83f9a6a4ea0731dcad6b5aaa87eb875ca5a6d7b24c317ca` |
| Linux `Image` (liveness only; any proven base kernel) | pin at run; current base `aca9a55614b1a588e33cf8a41ad01108d0d3de15b77c8b047991bd04b8b44000` |

Note on the Image: op-115 executes entirely in m1n1 (kboot) before Linux hands
off, so the diagnostic outcome cannot depend on the kernel; the Image only
confirms the machine survived to BusyBox. The DTB has no PCIe host node
(PCIe-free), so Linux never touches the controller.

## Static safety review surface

- **Only new MMIO is the three clkgen (reg[6]) ops above**, all inside the
  existing `regs_t6040` guard. No PMU/SPMI/charger/NVRAM. No blind sweep — the
  clkgen base is ADT-derived and the offsets/values come from the paired driver.
- **Read-only w.r.t. the PHY-IP aperture:** the op-115 stop still returns before
  the first PHY-IP *write*; the only reg[3] access is the single 32-bit read at
  `0x417040090` this test is measuring.
- No port/PERST/RID2SID/config-space/link-up access (returns before all of it).
- No ANS/SART/NVMe (PCIe-free DTB; those nodes absent).
- The 16 KiB log-ring upper guard from the prior op-115 runs remains in effect.

## Pass / stop conditions

- **Pass (hypothesis confirmed):** the sequence prints `clkgen PLL locked`, then
  the op-115 read prints a value and the `stopping before write` line — i.e.
  `0x417040090` **reads back** instead of hanging. Record the value.
- **Negative (still hangs):** `clkgen PLL locked` prints but no op-115 value/`done`
  follows → the PLL enable was necessary-but-not-sufficient; capture and stop.
- **PLL no-lock:** `clkgen PLL did not lock` → the enable value/field is wrong for
  this board; stop, do not retry unchanged.
- **Stop immediately** on any async SError, watchdog reset, or nonzero L2C status;
  restore `Running proxy`, release the lease healthy (or wedged if unsure).

## Run (after cross-review + CJ approval only)

```sh
scripts/rig-lease.sh acquire <agent> "op-115 clkgen-PLL read-only retest" e4671e08
RIG_AGENT=<agent> bash scripts/t6040-debugusb-console.sh reboot   # recover first (rig was NEEDS_RECOVERY)
RIG_AGENT=<agent> M1N1_BIN=<candidate m1n1.bin> \
  bash scripts/t6040-boot-dcuart.sh t6040-j614s-dcuart.dtb initramfs-dcuart.cpio.gz
```

Single boot. Do not add PHY-IP writes, ports, or a second candidate in the same
run. Competes with Sol for the one rig — queue behind whatever Sol holds.

Review status: **awaiting independent cross-review; not approved for the rig.**
