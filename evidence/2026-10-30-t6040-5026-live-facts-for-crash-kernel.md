# 5026 input: live facts for the crash-kernel design (claude, on the M4, 2026-10-30)

These are read-only reads on the running 5019 kernel (`/proc/config.gz`, `/proc/iomem`,
`/sys/kernel/kexec_crash_*`). This file is not the design; it supplies the inputs 5026 asks for.

## Config

`CONFIG_KEXEC_CORE=y`, `KEXEC=y`, `KEXEC_FILE=y`, `CRASH_RESERVE=y`, `CRASH_DUMP=y`,
`PROC_VMCORE=y`, `RELOCATABLE=y`, `ARCH_SUPPORTS_CRASH_DUMP=y`, `ZONE_DMA=y`, `ZONE_DMA32=y`.
The 5019 kernel can be a crash kernel and can load one.

## No crash reservation on this boot

`/sys/kernel/kexec_crash_size` = 0, `kexec_crash_loaded` = 0, and there is no "Crash kernel"
entry in `/proc/iomem`: the cmdline has no `crashkernel=`. Loading a crash kernel (`kexec -p`)
needs a new object with a reservation; it can't be tried on the running kernel.

## Memory map (top level and reservations)

| range | what |
|---|---|
| `0x100032a8000-0x102ffffffff` | System RAM (first block, about 12 GiB) |
| `0x100040f0000-0x10004183fff` | ADT (phram) |
| `0x10004184000-0x100041e3fff` | **allocatable RAM, the CTRR_C candidate window (5015)** |
| `0x100041e4000-0x100042effff` | m1n1 stage 2 |
| `0x10005000000-0x10006ffffff` | reserved, 32 MiB |
| `0x10008000000-0x1000adeffff` | **Kernel code** |
| `0x1000adf0000-0x1000bf6ffff` | reserved (inside the kernel image) |
| `0x1000bf70000-0x1000c76ffff` | **Kernel data** |
| `0x1000c800000-0x1000dd43fff` | initrd |
| `0x1000dd48000-0x1000de33fff` | 13 per-secondary blocks of 64 KiB |
| `0x1000de38000-0x1000de5ffff` | FDT |
| `0x10300000000-0x103001fffff` | ramoops (no-map) |
| `0x10300200000-0x105ce79bfff` | System RAM (second block, about 11 GiB) |
| `0x10458000000-0x1045dcfffff` | reserved, about 93 MiB |
| `0x105c8928000-0x105ce79bfff` | reserved (firmware, about 95 MiB in pieces) |
| `0x105ce7a0000-0x105ce7a3fff` | m1n1 stage-2 log (phram) |
| `0x105d306a880-0x105d4637eff` | simpledrm framebuffer |

**There is no RAM below 4 GiB.** All RAM starts at `0x100_0000_0000`.

## Consequences for 5026

1. **Plain `crashkernel=<size>` will probably fail or land oddly.** On arm64 it first tries a
   low (DMA32) allocation, and this machine has no memory below 4 GiB. Use an explicit base in
   the second RAM block, clear of every reservation above, e.g. `crashkernel=512M@0x10500000000`
   (`0x10500000000-0x1051fffffff`: above the 93 MiB block, below the firmware blocks at
   `0x105c8928000`). Or use `crashkernel=<size>,high`. Either has to be checked against a fresh
   `/proc/iomem` on the boot that carries it.
2. **Kernel load address.** The running kernel's code starts at `0x10008000000`. 5026's text gives
   m1n1's payload area as kernel `0x10008400000` / FDT `0x10008600000`. Those may be m1n1's
   staging addresses rather than where Linux ends up, but the design should name which is which.
3. **The crash kernel must not use `maxcpus=1` alone.** It must run with `nr_cpus=1` (5024).
   arm64 skips the stuck-CPU refusal for `KEXEC_TYPE_CRASH`, but the crash kernel itself must
   not try to bring up spin-table secondaries that the panicked kernel never released.
4. **The CTRR window `[adt_end, adt_end + 0x60000)` is in the first RAM block.** Keep the crash
   region in the second block so the two don't interact.
