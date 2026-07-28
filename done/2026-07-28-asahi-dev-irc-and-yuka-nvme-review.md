# Asahi-dev 2026-07-26..28 + yuka NVMe/USB review

Offline research only. No rig action, hardware access, or external post.

Primary sources:

- https://oftc.catirclogs.org/asahi-dev/2026-07-26
- https://oftc.catirclogs.org/asahi-dev/2026-07-27
- https://oftc.catirclogs.org/asahi-dev/2026-07-28
- https://github.com/yuyuyureka/m1n1/commits/feature/t8132-nvme
- https://github.com/AsahiLinux/m1n1/pull/594
- https://github.com/AsahiLinux/m1n1/pull/639

## Verdict

There are two load-bearing results.

1. Yuka's four NVMe commits genuinely reopen Wallace's raw-m1n1 NVMe route. They invalidate
   the *evidence* previously used to declare that route SPTM-blocked, but they do not yet prove
   end-to-end T6040 I/O. Claude independently recorded the ADT/fault-address re-derivation in
   `done/2026-07-28-upstream-review-nvme-reopened-pcie-d2-confirmed.md`; I agree with the
   arithmetic and the reopen, with the qualification below.
2. The IRC discussion independently confirms that T6040 ATC is not a safe T8103/T8122 fallback.
   Yuka stopped the proposed T604x USB test after finding a materially different PHY/tunable set.
   This supports ticket 170's disabled, T6040-native DT staging and its refusal to bind the old
   driver.

No new unattended rig experiment follows from either result.

## 1. Exact review of yuka's last four NVMe commits

The branch head and four commits, oldest first:

| commit | change | Wallace consequence |
|---|---|---|
| `dc067af47ee26c2f7166f78e3156bf73c9696371` | `cdw12 = 0` for a one-block read because NLB is zero-based | Required for newer firmware; an I/O correctness fix, not a bring-up proof. |
| `fd8832414172cf62b1396c73eacbf6ec08524192` | Skip `NVME_LINEAR_SQ_CTRL +0x24908` and `NVME_UNKNOWN_CTRL +0x24008` writes on firmware >= 15.0 | The first skipped write is the exact offset of Wallace's 2026-07-25 SError. |
| `8874ce87c0f159beaa8246d54993dac35da43546` | Keep NVMMU at ANS `reg[3]`; use ANS `reg[9]` for the NVMe controller when the extended layout exists | Matches J614s's ten-entry ANS ADT and reclassifies our previously observed 64 KiB `reg[9]` window as controller MMIO. |
| `11158bbb2de15377ab26956020aabf74765e41fa` | Write IO CQ/SQ addresses to controller offsets `0x1208`/`0x1200` | Marked by the author as needed on M4 and later; required in the candidate if the goal includes an actual read. |

Independent checks:

- Wallace's recorded fault gives
  `low36(0x28360040dce4908) - 0x40dcc0000 = 0x24908`, exactly
  `NVME_LINEAR_SQ_CTRL`. The old run died on the legacy write that `fd883241` now skips.
- m1n1's `adt_getprop(..., &len)` returns the property's byte size
  (`rust/src/adt.rs` assigns `p.size`), and other m1n1 callers divide a `reg` length by 16.
  Therefore `8874ce87`'s `if (reg_len >= 10)` test is a real compatibility bug: even one
  16-byte `reg` entry satisfies it. The candidate must use `reg_len >= 10 * 16` or
  `reg_len / 16 >= 10`, not import the branch unchanged.

Qualification to the reopen:

- At 22:51 on July 26, enverbalalic reported that NVMe in m1n1 was "not complaining".
  The log does not show a successful `nvme_read()`, namespace identity, or returned data.
- The earlier Linux SError was later attributed to swapped `pmgr`/`pmgr1` labels; after fixing
  that, Linux no longer SErrored but still exposed no `/dev/nvme*`.
- Consequently the correct state is **prior SPTM no-go evidence refuted; raw route reopened;
  end-to-end T6040 I/O unproven**. It is too early to claim that NVMe is generally
  "not SPTM-blocked."

Ticket 174's candidate should contain all four changes plus the `reg_len` fix. Its live test
still needs fresh CJ approval: a nominally read-only LBA probe cycles controller `CC.EN`,
rewrites queue pointers, and can reset ANS on an error path. Those are controller/PMGR writes
against the internal boot SSD, even though no namespace write command exists.

## 2. T6040 USB/ATC: do not use the T8132 patch as proof

The July 26 discussion is unusually direct:

- T6040 has `tunable_CIO4PLL_CORE` and TB5/CIO changes.
- Yuka first reported 53 tunables on T8132 versus 25 on T6040, then corrected an
  over-broad extraction again. The final corrected inventories are 44 versus 17; the 17-entry
  T6040 list is preserved in `done/2026-07-28-asahi-dev-irc-review-0726-0728.md`.
- T8132 worked by reusing the T8122 table and aliasing
  `tunable_ATC0AXI2AF` to `tunable_ATCAXI2AF`.
- T6040 lacks the old lane-USB tunable set; Yuka said "I doubt USB3 will work" as-is and
  withdrew the proposed T604x USB test for the time being.
- The proposed next RE method was to map each tunable to its actual aperture, potentially by
  applying a recognizable marker under macOS, and to add an ATC "reset-only" mode.

PR 639 confirms the scope. Commit `a4d02bc07bb3102ba12c1388f7f0dd55666bff46` only:

- recognizes `atc-phy,t8132`;
- reuses `atc_tunables_t8122`; and
- adds the AXI2AF property-name alias.

It does not recognize `atc-phy,t6040`, decode the 44-bank T6040 layout, or prove any T6040
runtime sequence. It is a kboot DT-tunable forwarding change, not a new Linux ATC PHY driver.

This independently supports ticket 170's current posture:

- keep the T6040-native compatible;
- do not add `apple,t8103-atcphy` as a fallback;
- keep ATC/DWC3/retimer functional nodes disabled until the T6040 runtime sequence and
  retimer ownership are grounded.

## 3. The SPMI HPM PR is not a Wallace VBUS shortcut

PR 594 is useful upstream work, but its head cannot be imported wholesale under Wallace's
safety policy:

- `tps6598x_foreach_hpm()` scans every compatible HPM across I2C and SPMI buses;
- the normal USB init path calls `SSPS`, writes nine `0xff` bytes to W1C
  `INT_CLEAR1 0x18`, and replaces `INT_MASK1 0x16`;
- it sends SPMI WAKEUP/SHUTDOWN around each matched endpoint;
- the path contains no source/sink power-role command and does not establish VBUS sourcing.

Wallace permits only the exact right endpoint `/arm-io/nub-spmi-a1/hpm2`, forbids generic HPM
iteration, and has not approved those W1C/mask writes. PR 594 is therefore an upstream design
reference, not a runnable candidate and not a fix for the SWDF-vs-source-role gap.

## 4. Other useful log facts

- T6040's `ps_ans` always-on domain was reported to fix the five-minute watchdog/reboot issue,
  matching Wallace's already-working watchdog direction but not proving storage I/O.
- Yuka reported newer DebugUSB/CS firmware may accept VDM actions only if the CS cable was
  present at boot; a Ctrl-X disconnect then required a DUT reboot. Preserve the project's
  fresh-window/reboot discipline and do not use disconnect as a harmless recovery action.
- On July 28, flokli confirmed the locked sysreg used by the tracing work is accessible on
  T6040 with 26.6 firmware. Sven's new SPTM/TXM hypervisor work (m1n1 PR 643) had not yet been
  exercised on M4. This is a future static/trace lead, not a reason to retry GENTER now.
- The logs contain no new T6040 PCIe link-up, BCM4388/WiFi success, or macOS-compatible Linux
  USB-gadget networking result.
