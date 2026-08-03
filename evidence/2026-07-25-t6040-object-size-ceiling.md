# T6040 enrolled boot-object size ceiling — ≥64 MiB, fully loaded (2026-07-25)

## Result

`probe-graded-64M.bin` (`df1075b963a1913aa1c078d424c9783f4ea8c70609c1db55ae0824a954629fa9`,
exactly **64.00 MiB = 4096 pages**, 1007 self-describing 64 KiB stamps) enrolls, boots to
`Running proxy`, and reads back intact:

```text
m1n1 base = 0x1000557c000   top_of_kernel_data = 0x10009bec000 (base+0x4670000)
Unknown payload at 0x10005688000 (magic: 574c4f46)   <- "WLOF" stamp at +0x10C000
HIGHEST LOADED OFFSET SEEN: 0x3f0c000 (63.05 MiB)
```

Every sampled block through 63 MiB carries its own correct offset stamp (the scan steps
1 MiB past the first MiB, so 63.05 MiB is the last sample of a 64 MiB object). **iBoot
loads the entire 64 MiB object.** The ceiling is therefore **≥64 MiB and was not
reached**; page alignment (ticket 129) was the only real constraint.

`top_of_kernel_data` again scales with the object: base+`0x77C000` (7.5 MiB) for the
1.05 MiB bare loader, base+`0x1a7c000` (26.5 MiB) for the 20 MiB probe, and
base+`0x4670000` (73.4 MiB) here — a consistent ~6.5-9.4 MiB of boot data after the
object, so it is not a cap.

## Correction to the record

The earlier "22.2 MB object fails" data point is **confounded and must not be cited as a
size limit**: that object was 1353.977 x 16 KiB, i.e. non-page-aligned, so it failed for
the ticket-129 reason. Before this measurement there was **no** valid evidence of any
size ceiling, and ticket 080's "conservative 64 MiB complete raw object policy" was an
assumption. 64 MiB is now measured-good rather than assumed-safe.

## What the headroom buys

Current B0 object is 9.02 MiB, so there is at least ~55 MiB of proven headroom. That is
enough for a much larger userland — notably the **Ubuntu 24.04 RAM root** already built
and live-proven tethered earlier in this project
(`initramfs-ubuntu-ramroot-no.cpio.gz`, `0987cb7c…`, 29 MB gzip, glibc, with the
Norwegian keymap and the held-fd watchdog ping):

| Member | Size |
|---|---|
| m1n1 | 1.05 MiB |
| diet kernel (xz) | 4.68 MiB |
| DTB | 0.05 MiB |
| Ubuntu initramfs (gz 29 MB; smaller re-compressed as xz) | ~24-29 MiB |
| **projected object** | **~30-35 MiB, well inside the proven 64 MiB** |

So an **untethered Ubuntu** boot is now a size-feasible next milestone, using the same
enrollment path that produced B0.

## Not yet known

- The true ceiling above 64 MiB (a 128 MiB graded probe would settle it; cheap, one
  enroll, and only worth doing if a payload ever needs it).
- m1n1's *decompression* capacity is a separate question from iBoot's load ceiling: the
  heap starts at `top_of_kernel_data` and grows into ~23 GB of RAM, so it is unlikely to
  bind, but it has not been measured with a large payload.

## 256 MiB also loads in full — no ceiling found

`probe-graded-256M.bin` (`c7fcfa71015979391c5c9b85243fe9b04f996877e6b78dd5daa1615edad87cc3`,
exactly **256 MiB = 16384 pages**, 4079 stamps) enrolls, boots (gadget up in ~3 s), and
reads back intact:

```text
m1n1 base = 0x10005320000   top_of_kernel_data = 0x10015990000 (base+0x10670000)
Unknown payload at 0x1000542c000 (magic: 574c4f46)
HIGHEST LOADED OFFSET SEEN: 0xff0c000 (255.05 MiB)
```

`top_of_kernel_data` scaled once more — base+`0x10670000` (262.4 MiB) for a 256 MiB
object, i.e. the same constant ~6.4 MiB of boot data after the object.

### Measured ceilings, in order

| Object size | Loaded in full? |
|---|---|
| 1.05 MiB (bare loader) | yes |
| 14 / 16 / 20.05 MiB fillers | yes |
| **64.00 MiB** | yes |
| **256.00 MiB** | **yes** |

**No enrolled-object size ceiling has been found.** Page alignment to 16 KiB (ticket 129)
remains the only demonstrated constraint.

### Practical consequence

The binding limit is no longer the object — it is **RAM for the unpacked root**. A 256 MiB
xz payload expands to roughly 0.7-1 GB, against ~23 GiB of usable RAM, so even that is
far from the wall. For reference the current Alpine B0 object is 9.03 MiB and the Ubuntu
one 22.59 MiB; both are trivially inside anything demonstrated.

Recommendation: keep a **policy** ceiling in the builder for sanity (a runaway object is
still a bug worth catching), but raise it from the assumed 64 MiB to 256 MiB
measured-good, and stop treating object size as a design constraint when choosing a
distro or userland.

### Consequence for the distro choice

Alpine's main advantage was size, and size no longer constrains anything. The real
trade-offs are now **iteration speed** (Alpine `apk` in seconds vs Gentoo builds in hours)
and **musl vs glibc** compatibility. Gentoo + dwl is size-feasible; it is an
effort/iteration decision, not a space one.
