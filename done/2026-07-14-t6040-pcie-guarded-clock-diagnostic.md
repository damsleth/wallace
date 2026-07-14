# T6040 guarded PCIe clock diagnostic

Prepared and run 2026-07-14. **Approved once; successful.** This was the first
write-bearing PCIe retry after the upper log-buffer guard proved that every
earlier traced `[70]` SError was a logging artifact.

## Exact build

- m1n1 main commit: `f46d6e35` (`v1.6.0-78-gf46d6e35`)
- main `build/m1n1.bin` SHA-256:
  `8fd7319047187f9ca05a6924462a4f24360fcc1d9e4279b089dc83a5acb05744`
- curated commit: `f8725409`
- curated `build/m1n1.bin` SHA-256:
  `2675c12d5305f2c585d008affaa6d1593ffc4463a7dbd1ca7f747561e0a128f2`
- main and curated relevant sources are byte-identical.

Use only the main binary. Boot the proven PCIe-free base DTB, SHA-256
`e7691ee49ed88114154061aeaf29309e3d817ae3ae89d7196bf7ef02a9b3dc9a`.

## Exact write boundary

The ordered PCIe operation set is unchanged from
`2026-07-14-t6040-pcie-clock-diagnostic.tsv`, SHA-256
`ce86e51aa3d278da1d9ef9eb35fca3208859f4993480de5b6af3268dc03ef4e6`:

- operations 1–12: recursive PMGR RMWs for clock gates 0–6;
- operations 13–89: 77 ADT-supplied AXI RMWs;
- operation 90: the existing RC `+0x4` write;
- operations 91–97: seven CIO3 PLL RMWs;
- operation 98: one PCIe clkgen RMW;
- operations 99–105: recursive PMGR RMWs ending at the late
  `APCIE_PHY_SW` gate.

The sequence matches Apple's gate order. Every traced tunable RMW retains its
`dsb sy` and read-only `L2C_ERR_STS` sample; a nonzero sample aborts without
clearing status. The proven 16 KiB upper guard remains above the active stage-2
log ring.

The controller returns immediately after operation 105. It cannot execute
operation 106, the first PHY write, or reach PHY polling, ports, PERST#,
RID2SID/MSIMAP, or Linux PCIe. The base DT has no PCIe host node. NVMe and
storage remain outside the path.

## Live result

The maintainer approved one live run of the exact main binary and manifest
above. All 105 operations completed in order: AXI `[0..76]`, the RC write,
CIO3 `[0..6]`, clkgen `[0]`, and the late PHY clock gate. m1n1 printed:

```text
pcie: T6040 PHY clock gate enabled
pcie: T6040 clock-tunable diagnostic complete; stopping before PHY
```

There was no nonzero L2 status and no SError. The intentional return prevented
operation 106 and all later PHY/port work. The PCIe-free base kernel then
reached BusyBox. No PHY, port, PERST#, RID2SID/MSIMAP, Linux PCIe, NVMe, or
storage access occurred.

- m1n1 transcript: `../logs/t6040-console-20260714-pcie-guarded-clock.log`,
  SHA-256
  `8dac965aadfb8f5bd92cf2c0e17ceefaea3f74de11790d8089121d527f54b175`
  (402 lines, 26,188 bytes)
- Linux transcript: `../logs/t6040-linux-20260714-pcie-guarded-clock.log`,
  SHA-256
  `b1caef2f4b6612675f329402bc0d9f87813494a98c28a84bb09033471d792063`
  (36 lines, 2,255 bytes)
- boot artifacts: Image
  `14da8640398fc64b89d9241a75be0ffc8d4260b681068a3c27251cc79c3abaf4`,
  base DTB
  `e7691ee49ed88114154061aeaf29309e3d817ae3ae89d7196bf7ef02a9b3dc9a`,
  initramfs
  `512c69da94884f3ea83f9a6a4ea0731dcad6b5aaa87eb875ca5a6d7b24c317ca`

The next bounded diagnostic may continue through shared PHY setup, but needs a
new exact stop before the first per-port write and fresh explicit approval.
