# T6040 HPM2 status R0 — paired decode and exact-artifact preflight

Date: 2026-07-29  
Author: `sol`  
Tickets: 176 (offline decode), 178 (proposed rig capture)  
Hardware touched: **none**

## Result

The paired Apple software does **not** provide evidence for the generic
TPS6598x `SWSr`/`SWSk` power-role commands. Exhaustive byte searches of both
the complete paired 25F84 kernelcache and the extracted `AppleHPM` executable
find zero ASCII and zero UTF-16LE instances of either 4CC:

| Corpus | SHA-256 | `SWSr` | `SWSk` | `SWDF` | `SWUF` |
|---|---|---:|---:|---:|---:|
| `t6040-kernelcache-25F84.raw` (119,209,984 bytes) | `ed556fe62efc2c229f3d4c7ebbbcd21fd5c8d099fbb4d9b5ae636dd78b61d3f6` | 0 | 0 | 1 UTF-16LE | 1 UTF-16LE |
| extracted `com.apple.driver.AppleHPM` (836,032 bytes) | `b6eab85a4478fe354c29d4a274fa1ea23ced1c051e3b320fdfad54d65dce381d` | 0 | 0 | 1 UTF-16LE | 1 UTF-16LE |

Linux's generic TPS6598x driver and the old m1n1 I2C experiment do use
`SWSr`/`SWSk`, but that is not enough to derive a safe transaction for this
SPMI-attached Apple controller. Ticket 176 therefore closes with a negative
finding: do not build or run an `SWSr` write candidate from generic-driver
semantics.

The paired executable does establish a passive state path:

- `AppleHPMDeviceHAL::getStatus(HPMType1Status *)` at
  `0xfffffe000954b7fc` passes logical register `0x1a` to the logical-read
  vtable operation.
- `AppleHPMDeviceHAL::setStatus` at `0xfffffe000954b8f4` loads four bytes and
  treats lengths of five bytes or more as abnormal.
- Linux's TPS6598x definitions decode this ordinary status value as plug
  present (bit 0), connection state (bits 3:1), orientation (bit 4),
  power role (bit 5), data role (bit 6), VCONN (bit 7), PP5V state
  (bits 9:8), power source (bits 19:18), and VBUS state (bits 21:20).

This status register is not a W1C, event, or mask register. The SPMI logical
selector protocol still requires a selector write, so ticket 178 remains an
attended, exact-artifact-reviewed operation under `docs/SPMI_SAFETY.md`.

## Exact candidate

Source:

- m1n1 worktree: `/Users/damsleth/Code/m1n1-hpm2`
- branch: `codex/t6040-hpm2-status-r0`
- commit: `baf2c20dd7614c1e9ecc7923b5cab6aa9dd69b0e`
- commit carries `Signed-off-by: CJ Damsleth <kim@damsleth.no>`

Artifact:

- path:
  `/Users/damsleth/Code/linux-build-out/t6040-hpm2-status-baf2c20dd761/r0-status/m1n1.bin`
- SHA-256:
  `d012adcf524c18600c749ba41409639a1b990e4065f5d95f3a14d79b6414307f`
- size: 360,448 bytes
- build script: `scripts/t6040-build-hpm2-status-r0.sh`
- build result: two clean builds, byte-identical for the binary, Mach-O,
  both ELFs, experiment object, symbols, and object disassembly

The build also pins captured ADT SHA-256
`7a92e6e4d16cb1b5a5858beb22b22acc8e5ed4b36ed5d5ccde9b251f1da55c84`.

## Re-derived transaction surface

The class-5 preprocessor boundaries exclude the class-1 wake path, class-2
SSPS path, and class-3/4 role-swap paths from the candidate.

After the full identity gate succeeds, the experiment object's relocations
and immediates show exactly:

1. `spmi_init_strict("/arm-io/nub-spmi-a1")`;
2. one `spmi_reg0_write`, SID `0x0c`, value `0x1a`;
3. a selector poll of register `0x00`, SID `0x0c`, one byte, bounded to
   100 attempts with 1 ms between pending values;
4. one `spmi_ext_read`, SID `0x0c`, register `0x20`, length 4;
5. local `spmi_shutdown` cleanup and the existing forced warm reboot.

The candidate's linked symbol table contains no `spmi_ext_write`,
`spmi_send_wakeup`, `spmi_send_reset`, `spmi_send_sleep`,
`spmi_send_shutdown`, or long-form SPMI transfer. It contains no status
write, CMD1/DATA1 command, SSPS, role transition, or retry after a failure.

The identity gate remains before `spmi_init_strict` and validates:

- J614s / Mac16,8 / chip `0x6040` / board `4`;
- exact bus `/arm-io/nub-spmi-a1`, Gen3, sole child `hpm2`;
- raw controller tuples beginning at `0x309198000` and independently
  translated CPU-physical bases beginning at `0x509198000`;
- compatible `usbc,sn201202x,spmi`, SID `0x0c`, RID 2, port 3,
  HPM class 10, location `right`, and no children.

Any mismatch stops before the first SPMI transaction.

## Expected transcript and interpretation

On success the candidate prints the raw four bytes and decoded:

```text
t6040-hpm2: status raw=........ bytes=.. .. .. ..
t6040-hpm2: plug=. conn=. orientation=... power-role=... data-role=... vconn=.
t6040-hpm2: pp5v=. power-source=. vbus=...(.)
```

This observation can distinguish whether the blind R3 run changed only data
role, also changed power role/VBUS, or changed nothing. It does not alter or
restore the port state.

## Gate and next step

Ticket 178 is only **proposed**. Before running it:

1. Claude independently reviews commit `baf2c20d`, the exact binary hash, ADT
   gate ordering, and the shipped object disassembly.
2. CJ explicitly approves ticket 178.
3. The passive stick stays on the right port and DebugUSB stays on the left.
4. `sol` acquires the rig lease immediately before the attended run and
   releases it only after a quiescent `Running proxy` is restored.

The newly enrolled rollback object provides the indefinite KIS proxy needed
to capture this transcript. No rig action was taken while producing this
preflight.
