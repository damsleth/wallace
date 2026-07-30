# Ticket 174 preflight — NVMe two-base probe candidate (CJ-approved, incl. CC.EN cycle)

Author: `claude`, 2026-07-30. Hardware touched at build time: none.

## Approval scope

CJ approved on 2026-07-30 (attended question round): **the read-only NVMe probe including the
`CC.EN` cycle on the controller holding macOS**, with the cleanup reset path. No namespace-write
opcode exists in the NVMe-specific dispatch (`nvme_read` only in this script); that dispatch also
contains FLUSH, which the probe does not call. Cleanup attempts both the `ANS` and `ANS2` PMGR
device names. This closes the approval gap flagged in
`done/2026-07-28-upstream-review-nvme-reopened-pcie-d2-confirmed.md`.

## The candidate

`m1n1-t6040-nvme-two-base-ae4a8f28.bin`
SHA-256 `ae4a8f28cbe5f66c7603f5f9a95fe81b819e8279e76de089652617c240a2bea3`, 1,097,728 B.
Branch `wallace/t6040-nvme-two-base` in `~/Code/m1n1`, head `1702259f`, built with
`M1N1_VERSION_TAG=t6040-nvme-two-base-1702259f`. Chainload-only candidate — never enrolled, so no
enroll-guard entry.

Carries yuka's four `feature/t8132-nvme` commits, cherry-picked clean:

| upstream | local | what |
|---|---|---|
| `dc067af4` | `b00183ed` | cdw12 NLB: read 1 block (zero-based) |
| `fd883241` | `25935b79` | skip LINEAR_SQ_CTRL/UNKNOWN_CTRL for FW >= 15.0 |
| `8874ce87` | `e9a29b93` | reg[3] = NVMMU window, reg[9] = NVMe controller aperture |
| `11158bbb` | `6ebe47e8` | M4 IOQ cmd/cqe pointer writes at nvme+0x1200/0x1208 |

Plus our own `1702259f` with **two fixes, the second of which is load-bearing on this machine**:

1. **reg-entry count**: `adt_getprop` returns bytes; `reg_len >= 10` is true on every machine.
   Now `reg_len / 16 >= 10` (16 B per 2+2-cell entry). Our ADT has exactly 10 entries → M4 branch.
2. **V_UNKNOWN fail-safe**: `detect_firmware` returns `V_UNKNOWN` (=0) for any iBoot string not in
   the exhaustive table, and `V_UNKNOWN < V15_0B1` would re-enable the legacy writes. **Our machine
   reports `OS FW version: unknown (mBoot-18000.121.3)`** (verified live in
   `linux-build-out/dcuart-chainload.log`) — so yuka's gate as written would have executed the
   exact `reg[3]+0x24908` LINEAR_SQ_CTRL write that SError'd us on 2026-07-25, and the probe would
   have failed identically, falsely "refuting" the two-base theory. For this exact machine,
   `mBoot-18000.121.3` is numerically newer than the 15.0 threshold, so skipping was correct.
   `V_UNKNOWN` itself has no chronological meaning: an unlisted old string also maps to zero, so
   upstream needs a parsed build-number or hardware-capability comparison.

## Run plan (rig, unattended-OK per CJ blanket rig approval + explicit 174 approval)

1. `scripts/t6040-debugusb-console.sh reboot` → rollback loader proxy.
2. Chainload `m1n1-t6040-nvme-two-base-ae4a8f28.bin` over the proxy.
3. `scripts/t6040-nvme-probe.py` (existing, read-only: `nvme_init` → `nvme_read` LBA 0 → CSTS/
   status dump → `nvme_shutdown`).
4. Capture full transcript; on SError, capture L2C_ERR_ADR and compare against reg[3]/reg[9]
   offsets before concluding anything.

## Expected outcomes

- **PASS**: `nvme: ANS is on die 0`, boot status OK, admin identify + 1-block read complete. First
  internal-storage read on T6040 from a non-Apple OS. Follow-up: bounded read-only dump ticket.
- **FAIL, SError at reg[9]+X**: the controller aperture is genuinely protected → SPTM route back
  on the table; document offset.
- **FAIL, SError at reg[3]+0x24908 again**: the FW gate did not hold (would mean `os_firmware`
  detection changed) — abort and re-check, do not re-run.
- **FAIL, rtkit/boot-status**: regression vs 07-25 (those stages passed then); suspect the
  cherry-picks, not the theory.

## Rollback

Candidate is chainloaded only; a plain `macvdmtool reboot` returns to the enrolled rollback
loader. macOS re-initializes ANS on its next boot either way; the 07-25 SError run already
demonstrated macOS recovers from a mid-init ANS state.
