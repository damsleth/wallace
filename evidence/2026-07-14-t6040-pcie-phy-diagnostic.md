# T6040 guarded shared-PHY diagnostic

Prepared and run 2026-07-14. **Approved once; bounded failure.** This continued the live-proven
Apple-ordered 105-operation clock/tunable prefix through shared PHY setup, then
returns before the first per-port operation.

## Exact build

- m1n1 main code commit: `b5ced9ba` (`v1.6.0-81-gb5ced9ba`)
- main `build/m1n1.bin` SHA-256:
  `add3cef43947dab1605bd95ad602b6dcbf8e89de0a3f1b43f278005cd52dd9da`
- curated code commit: `a620fa4f`
- curated `build/m1n1.bin` SHA-256:
  `f59e2c0035b4d77ba0fa44d072330454aa7b8216714b7dcc7e33d88f683a6eae`
- main and curated `src/pcie.c` are byte-identical; both builds completed.

Use only the main binary. Retain the proven 16 KiB upper log-buffer guard and
boot the PCIe-free base DTB, SHA-256
`e7691ee49ed88114154061aeaf29309e3d817ae3ae89d7196bf7ef02a9b3dc9a`.
The Image SHA-256 is
`14da8640398fc64b89d9241a75be0ffc8d4260b681068a3c27251cc79c3abaf4`;
the DebugUSB initramfs SHA-256 is
`512c69da94884f3ea83f9a6a4ea0731dcad6b5aaa87eb875ca5a6d7b24c317ca`.

## Exact write boundary

The deterministic ordered manifest is
`2026-07-14-t6040-pcie-phy-diagnostic.tsv`, SHA-256
`d4496968ee8fc1202bd4d47247fc6bbaa36f0a3f7cc872a81efabe72327c50fc`.
It contains 351 operations at 333 distinct addresses:

- operations 1–105: the live-proven PMGR, AXI, RC, CIO3, clkgen, and late
  `APCIE_PHY_SW` prefix;
- operations 106–110: five ADT `apcie-phy-tunables` RMWs;
- operations 111–114: shared PHY clock requests, reset release, and T8122
  pre-tunable control;
- operations 115–142: 28 ADT PHY-IP PLL RMWs;
- operations 143–346: 204 ADT PHY-IP AUSPMA RMWs;
- operations 347–351: T8122 post-tunable control, common clock mode, PHY
  control, and two RC initialization writes.

The existing initialization also performs five bounded read-only polls, which
do not appear in the write-only TSV:

| Order | Address | Condition | Timeout |
|---|---:|---:|---:|
| before operation 111 | `0x417004000` | bit 31 set (100 MHz reference) | 250000 |
| after operation 111 | `0x417008000` | bit 2 set (CLK0ACK) | 50000 |
| after operation 112 | `0x417008000` | bit 3 set (CLK1ACK) | 50000 |
| after operation 348 | `0x417008008` | bit 0 set (PHY clock enabled) | 250000 |
| after operation 351 | `0x414000058` | bit 0 set (RC acknowledged) | 250000 |

All addresses come from the committed J614s ADT plus existing T6031/T8122
offsets; there are no blind or new-offset probes. The ADT-supplied RMWs retain
the existing pre/`done` trace, `dsb sy`, and read-only L2-status sample. Added
phase markers identify each clock acknowledgement, reset release, completion of
the PHY-IP tunables, PHY-clock acknowledgement, and RC acknowledgement without
adding hardware accesses.

The controller returns before entering the port loop. Therefore manifest
operation 352 (`CLEAR 0x10000` at `0x416000600`) cannot run, nor can any port
register, port PHY, PERST#, RID2SID/MSIMAP, config-space, Linux PCIe, NVMe, or
storage access. The base DT has no PCIe host node.

Regenerate the exact subset with:

```sh
git -C ~/Code/linux show feature/m4-m5-minimal-device-trees:j614s.adt \
  | scripts/t6040-pcie-write-plan.py --stop-before-ports \
  > done/2026-07-14-t6040-pcie-phy-diagnostic.tsv
```

## Live result

The maintainer approved one live run of the exact main binary and manifest.
Operations 1–114 completed: the proven 105-operation prefix, all five
`apcie-phy-tunables` RMWs, reference-clock poll, CLK0/CLK1 request and
acknowledgement, reset release, and T8122 pre-tunable control. The pre-write
trace for operation 115 then printed:

```text
tunable: apcie-phy-ip-pll-tunables[0] addr=0x417040090 size=4 mask=0x1 value=0x1
```

No `done` line or exception followed, and proxyclient timed out waiting for the
kboot reply. Thus the bounded live boundary is the first PHY-IP PLL RMW; it does
not prove whether the read or write side of that RMW stalled. Operation 115 did
not complete observably, and operations 116–351 did not run. The hard return
still made all port operations unreachable. Linux did not hand off; no port,
PERST#, RID2SID/MSIMAP, config-space, Linux PCIe, NVMe, or storage access ran.

The sanctioned DebugUSB reboot restored a fresh, quiescent proxy. Transcript:
`../logs/t6040-console-20260714-pcie-shared-phy.log`, SHA-256
`b567ab1353682787549a1e666b489dd46228a960a23cb5248e14c0a5221668bb`
(432 lines, 27,927 bytes).

Any follow-up that changes or isolates the operation-115 access requires its
own exact review and fresh explicit approval. Do not mount, repair, format, or
otherwise access storage.
