# Gravity Linux local clones review (claude, 2026-10-30)

Read `/Volumes/CaseSensitive/gravitylinux/{linux,bootloader}`. `linux` is a depth-1
clone of `gravity-m4` only (the `replacement/*` branches are not local); `bootloader` is
a full clone of `main`. Follows [the earlier API-only review](2026-10-30-gravitylinux-second-review.md).

## Headline: Flush may have failed on a TCB encoding upstream has since corrected

5006 and 211 run 1 concluded "ANS2 rejects Flush" (status 2, `fast decode err 0x7`).
Compare the encodings:

| encoding | opcode in TCB | dma_flags for a command with no PRP | result |
|---|---|---|---|
| Wallace kernel driver (the M1 `apple.c`, as built into 2234baad) | cmd opcode | `FROM_DEVICE` (not a write) | BAD_CMD (211 run 1) |
| 5006 m1n1 probe (old m1n1 encoding) | cmd opcode | `3` (both) | status 2 |
| `t6040-nvme-apple-flush-tcb.patch` | cmd opcode | `3` (both) | never built into a tested image |
| mainline, Yuka, Asahi 7.2.12-2, Gravity `gravity-m4` | `0` | `0` | works on M1 to M4 mini |
| m1n1 `c16d3c7` + `e1a1088` (Sven Peter, 2026-08-06) | `0` | `0` | same |

Sven's commit message: a DMA direction on a command with no transfer "likely triggered
the PRP NULL check". Provenance checked offline against the captured sources in
`2026-10-24-upstream-convergence/sources/`: `tcb->opcode = 0` and `dma_flags = 0` are in
the mainline, Yuka and Asahi `apple.c`, so this is upstream, not Gravity-only. Our local
driver is the outlier. The delayed-flush throttle (`flush_interval`, `flush_dwork`) is in
the Asahi file only (10 hits), not mainline or Yuka; it only matters if Flush works.

Not established: that this fixes Flush on T6040. `patches/t6040-nvme-apple-flush-nodma.patch`
sets `dma_flags = 0` when `prp1` is empty and leaves the opcode and the read/write path
alone (Flush's opcode is 0 anyway). Opt-in `NVME_FLUSH_NODMA=1` in `t6040-kbuild.sh`,
exclusive with `NVME_FLUSH_TCB`. It builds on the reconstructed base. Build `flushtest`
(Image `c8db676a`, same size as the 2234baad-equivalent build, brcmf and apple-nvme strings
present) also carries the two items below. It is not in the 5019 object. Ticket **5023**
(rig, proposed, not approved) covers the probe: m1n1-side Flush with `dma_flags = 0` first,
no writes; then the kernel build behind the 5008 gates. If Flush works, the write-through
caveat in NEXT_STEPS §3 goes away.

## Other kernel items wired in (opt-in, build-tested only)

- `T6040_RTKIT_GFP_NOIO=1` (5017): `t6040-rtkit-crashlog-gfp-noio.patch` applies and compiles.
- `T6040_BRCMFMAC_GRAVITY=1` (5016): of the three patches in `patches/brcmfmac-gravity-v1/`,
  only 0002 (msgbuf packet IDs) applies on the 7.1.3 base. 0001 (core.c) and 0003 do not;
  0003 fixes a commit this base does not have (it has no SAE/PSK `cfg80211_port_authorized`
  report at all), so skipping it is right. 0002 targets the 7.3 DMA-direction regression;
  whether it is neutral on 7.1.3 is untested. Keep it off the daily image.

## Bootloader (m1n1 fork): document only

No m1n1 source tree exists on this machine, so none of this is built or applied.

- `e1a1088`, `c16d3c7`, `ed52dde` (Sven Peter): the TCB changes above, and dropping the
  PRP NULL check chicken bit ("disappeared starting with macOS 15"). Our enrolled m1n1
  (`7de07c71`, `bf4b2462`) uses the old encoding. The m1n1 Flush probe for 5023 needs these.
- `e528d40` (Yureka): `cdw12` = 1 block for newer (26.x) firmware, M3 and M4.
- `eb6cab7`, plus Asahi `a735ea2`/`442c7a2`/`00b8814`: CTRR_C reservation, already exported as
  `patches/m1n1-ctrr-c-v1/` (5015). Still the lead for fault 205.
- `954f80c` (`mmu_secondary_setup`: `dsb sy` and invalidate the stack cache before enabling the
  MMU), `c22ca84` (clear `CYC_OVRD_DISABLE_WFI_RET`), `e268dd5`/`918a627` (hv secondary
  state): secondary-start fixes. Worth reading against 205, not yet compared with our fork.
- `0c1ba6b` `pcie: Add t8132/t6040 support`, `14704b0`/`b967af9` SPMI gen 4: check whether our
  fork already has them (the series in `patches/m1n1-t6040-upstream-v1/` overlaps).
- `7243b81` clears the PMU panic counter: SPMI write, outside SPMI_SAFETY, do not import.

## Not done

- No boot, rig, push or enrollment. Nothing committed.
- The rest of `gravity-m4` (T8132 fixes) and the `replacement/*` branches were not read.
- m1n1 changes need a buildable m1n1 tree, which only the M1 had.
