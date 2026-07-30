# Ticket 174 adversarial exact-artifact review — GO with corrections

Reviewer: `sol`, 2026-07-30. Review scope was strictly offline. I did not
acquire the rig lease, touch DebugUSB, reboot, chainload, enroll, or access the
machine.

## Verdict

**GO for building the next read-only and Linux/chainload work on the verified
T6040 read path.** I could not refute the central result: the candidate is
byte-for-byte attributable to the stated source, its T6040 path selects
`reg[9]` as the controller aperture, and its only namespace data-transfer
opcode is READ. The `EFI PART` bytes reported for LBA 1 are consistent with a
real GPT header read.

This is not an unqualified confirmation of every claim in the original
write-ups. Four corrections are required:

1. `V_UNKNOWN` does **not** mean “newer” in general; it means “not an exact
   table match.” The local fail-safe is correct for this machine's
   `mBoot-18000.121.3`, but unsafe as a universal pre-/post-15 test.
2. The NVMe-specific proxy surface is INIT / SHUTDOWN / READ / **FLUSH**, not
   only INIT / READ / SHUTDOWN. The exact probe did not invoke FLUSH and there
   is no NVMe namespace-write command exposed.
3. Shutdown status `2` is Invalid Field, not Invalid Opcode. The “26.x removed
   delete-queue opcodes” hypothesis is not supported.
4. The full probe transcript was not preserved in a durable, hash-pinned file.
   The current `/private/tmp/m1n1-console.log` is from a different proxy boot,
   so the result excerpt cannot now be independently tied to the candidate by
   transcript alone. The next run must correct that evidence gap.

None of those corrections invalidates the architecture result on J614s:
raw-m1n1 ANS/SART/RTKit setup, controller initialization through `reg[9]`,
queue creation, and a namespace READ completed.

## Exact artifact and source provenance

Candidate:

```
/Users/damsleth/Code/linux-build-out/m1n1-t6040-nvme-two-base-ae4a8f28.bin
size    1097728
sha256  ae4a8f28cbe5f66c7603f5f9a95fe81b819e8279e76de089652617c240a2bea3
tag     t6040-nvme-two-base-1702259f
```

The m1n1 worktree was clean at
`1702259f444fd745f8604ca6b086a948f3cedb13`. A clean build from that commit
with the current nightly compiler did **not** reproduce the candidate: it
produced the same size but SHA-256 `326167d7…`. The difference was the Rust
toolchain, not source drift:

- candidate toolchain: `rustc 1.99.0-nightly (af3d95584 2026-07-09)`;
- current toolchain: `rustc 1.99.0-nightly (6f72b5dd5 2026-07-22)`.

I then clean-built all C/assembly objects from `1702259f`, restored the
archived old Rust library
`librust.a` SHA-256
`10782c88eec61431c4713aa11499d95c8e6827067416578f699d8d3fca046174`,
and relinked with the stated `M1N1_VERSION_TAG`. The output was byte-identical
to the candidate (`cmp` success, candidate SHA-256 above). This closes the
source-to-binary attribution, while exposing a reproducibility weakness:
future manifests must pin the Rust compiler/archive as well as the commit and
version tag.

## Cherry-pick fidelity

`git range-diff dc067af4^..11158bbb b00183ed^..6ebe47e8` paired all four
commits with `=`. Stable patch IDs also match pairwise:

| Yuka | local | stable patch ID |
|---|---|---|
| `dc067af4` | `b00183ed` | `c8f8d93483a771aec82ebb5b715e458bd0ea3cbc` |
| `fd883241` | `25935b79` | `f320fafbc35b390527f44f68695359c38d7d8a99` |
| `8874ce87` | `e9a29b93` | `389f8904c55ce3e54c67d72df97ccc5472d9a512` |
| `11158bbb` | `6ebe47e8` | `68f4bb38d0c386c58b475f39fb3da02db6cdf5d9` |

There is no content drift in the four cherry-picks.

## `reg` length and captured ADT

The count fix is correct:

- `adt_getprop()` returns the property byte length (`p.size` in
  `rust/src/adt.rs`);
- other m1n1 callers divide an ADT `reg` length by 16;
- `/arm-io/ans` uses two address cells plus two size cells, 16 bytes per
  entry.

Offline parsing of
`/Users/damsleth/Code/linux-build-out/j614s-usb-port-map-20260721.adt`
(SHA-256
`7a92e6e4d16cb1b5a5858beb22b22acc8e5ed4b36ed5d5ccde9b251f1da55c84`)
found exactly ten entries / 160 bytes:

| index | ADT address | size |
|---:|---:|---:|
| 0 | `0x209600000` | `0x88000` |
| 1 | `0x209050000` | `0x4000` |
| 2 | `0` | `0` |
| 3 | `0x20dcc0000` | `0x60010` |
| 4 | `0x20b000000` | `0x18000` |
| 5 | `0x20db90000` | `0xc000` |
| 6 | `0x20dd47c00` | `0x4000` |
| 7 | `0` | `0` |
| 8 | `0` | `0` |
| 9 | `0x24dcc0000` | `0x10000` |

With the ADT bus translation, those become CPU addresses
`reg[3]=0x40dcc0000` and `reg[9]=0x44dcc0000`. Yuka's original
`reg_len >= 10` test takes the extended-layout branch even for a single
16-byte entry and therefore breaks pre-M4 layouts. `reg_len / 16 >= 10` (or
more directly `reg_len >= 10 * 16`) fixes it.

## Firmware gate: target-correct, globally unsafe

`detect_firmware()` compares the complete firmware string with `strcmp()` and
falls back to `fw_versions[V_UNKNOWN]`; `V_UNKNOWN` is enum value zero.
The captured boot log reports:

```
OS FW version: unknown (mBoot-18000.121.3)
System FW version: unknown (mBoot-18000.121.3)
```

Consequently Yuka's plain `os_firmware.version < V15_0B1` is true and would
execute the legacy LINEAR_SQ_CTRL/UNKNOWN_CTRL accesses. On this J614s that is
wrong: `mBoot-18000.121.3` is numerically later than the table's 15.0
threshold (`iBoot-11881…`), and the 2026-07-25 fault was the
LINEAR_SQ_CTRL access at `reg[3]+0x24908`. Skipping it was load-bearing and
correct for the reviewed run.

The local comment “every historical version is enumerated” is not a valid
upstream invariant. An unlisted beta, security update, vendor build, or old
release also maps to `V_UNKNOWN`; treating all such values as new can skip
register setup required on a genuinely pre-15 machine. The upstream fix
should compare parsed iBoot/mBoot build numbers across unknown exact strings,
or gate on a hardware/ADT feature that directly describes the register
contract. m1n1 already has `firmware_sfw_in_range()` for parsed system
firmware; maintainers should first decide whether ANS behavior tracks system
or OS firmware and use/add the corresponding parsed-string helper.

## Reachable proxy and command safety

The exact `scripts/t6040-nvme-probe.py` invokes only:

```
nvme_init()
nvme_read(nsid=1, lba=N, buffer)
nvme_shutdown()
```

Its CLI bounds `--lbas` to 1–8. `nvme_read()` always submits opcode `0x02`
with zero-based NLB `cdw12=0`, i.e. one block. No `nvme_write()` or
`P_NVME_WRITE` exists.

The broader NVMe proxy API also exposes `P_NVME_FLUSH`, implemented with
opcode `0x00`. FLUSH is not a namespace data-write opcode, but it is an
additional reachable controller command and was not called by the probe.
The general m1n1 proxy of course also has unrelated raw memory/MMIO
primitives; the defensible safety statement is about the exact script and
NVMe-specific dispatch, not the entire generic proxy.

INIT and SHUTDOWN are state-changing even without a namespace write:
controller `CC.EN`, admin/I/O queue registers, IOQ pointer registers, and
cleanup resets are touched. Cleanup attempts both `pmgr_reset(..., "ANS")`
and `pmgr_reset(..., "ANS2")`. Those reset attempts and the CC.EN cycle were
inside CJ's recorded 2026-07-30 approval.

The NVMMU TCB sets `dma_flags=3` for all commands, permitting controller DMA
read and write to the allocated PRP pages. That is broader buffer permission
than the READ command requires, but it does not change the submitted
namespace opcode and does not expose a namespace-write command.

## Shutdown anomaly

`nvme_exec_command()` shifts the raw completion status right by one before
printing it. In the NVMe generic status set:

- `0x01` = Invalid Command Opcode;
- `0x02` = Invalid Field in Command.

Thus both delete failures reported **Invalid Field**, not unsupported opcode.
The current “firmware dropped the legacy delete admin opcodes” explanation
should be retired.

Observed successful commands establish that this path accepts Create I/O
Completion Queue (`0x05`) and Create I/O Submission Queue (`0x01`), followed
by the I/O READ (`0x02`). The reviewed m1n1 init does not issue Identify.
The two Delete I/O Queue commands (`0x00`, `0x04`) are recognized only far
enough to return Invalid Field; the current evidence cannot identify which
field/state was rejected.

The best next lead is a queue-state/teardown-order mismatch around the
M4-specific IOQ pointer registers or firmware-managed queues. Yuka's current
Linux branch `feature/m4-m5-nvme` at `5515c2fbc` contains a separate 26.x
warning: Set Features / Number of Queues crashes ANS, so that call is
temporarily disabled (`9a6a6bd18`). Her branch does not yet explain the
delete failure. The 25F84 kernelcache contains generic
`IONVMeController::{Delete,Disable}{Submission,Completion}Queue` paths and
CoastGuard-v2 queue-enable overrides, but symbols alone do not prove the
wire-level teardown sequence. No new admin-opcode experiment is justified
from this offline review.

## Linux reference shape

Yuka's `feature/m4-m5-nvme` has:

- `ad8908064`: `apple,t8132-nvme-ans2` support, separate `mmio_nvmmu`,
  M4 IOQ pointer registers, and an M4 hardware descriptor;
- `1b87d7b84`: T6041 DT nodes.

The T6041 node is a three-resource design:

```
compatible = "apple,t6041-nvme-ans2", "apple,t8132-nvme-ans2";
reg = <... 0x4dcc0000 ... 0x10000>,  /* nvme: ADT reg[9] */
      <... 0x09600000 ... 0x4000>,   /* ans mailbox/coproc */
      <... 0x0dcc0000 ... 0x60000>;  /* nvmmu: ADT reg[3] */
reg-names = "nvme", "ans", "nvmmu";
```

It also supplies `apple,sart`, four mailbox interrupts, ANS/APCIE power
domains, and the ANS reset. This is the correct starting shape for Wallace's
Linux port, not a blind copy: the branch explicitly labels the M4/M5 NVMe
commits untested and carries the 26.x hacks above.

## The reg[3] caveat is preserved

The candidate does not assert that `reg[3]` is a pure, architecturally clean
NVMMU window. It assigns current controller accesses to `reg[9]` and NVMMU
TCB accesses to `reg[3]`, which is enough for this path. Historical evidence
still stands: `reg[3]+0x1300` was readable during the 07-25 boot-status path,
while `reg[3]+0x1210` faulted. Do not generalize the working split into a
claim that every offset belongs exclusively to one window.

## Evidence caveat and follow-up gate

The result document preserved the decisive excerpt, but not the full raw
transcript as a durable artifact. Its LBA 0 note also calls zeroes in the
first 64 bytes a “protective MBR”; those bytes alone do not establish a
protective MBR—the partition entry and `0x55aa` signature are later in the
sector. LBA 1's `EFI PART` signature is the stronger recorded media evidence.

The next bounded read must save the complete console/probe output before
reboot, hash the transcript and every dumped byte range, record the exact
command line and candidate hash in the ticket, and separately validate the
protective MBR and GPT header CRCs. Until then, cite the current result as
“GPT header signature reported from LBA 1,” not as a fully archived GPT
validation.

## Follow-up disposition

Three separate tickets should own the next work:

1. a maintainer-approved, bounded, read-only GPT + first-N-MiB dump with
   immutable hashes and a durable transcript;
2. an offline `chainload=` stage-2 architecture spike with a fail-closed
   location/size/hash format and no hardware action;
3. an offline Linux `nvme-apple` T6041/reg[9] port based on Yuka's three-region
   DT shape, retaining the reg[3] caveat and excluding live writes/boots until
   separately reviewed.
