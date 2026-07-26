# Ticket 147 dietcap-kernel smoke: object staged, metadata reconciled (2026-07-26)

Enabler 146 is satisfied (maintainer enrolled `rollback-m1n1-1394c345.bin`), so the tethered
KIS smokes are unblocked. This records the staged 147 object and four metadata corrections.

## The staged object

`~/Code/linux-build-out/m1n1-b0-dietcap-smoke.bin`
`ac24d4bfb562f9de7a138a4a3f37b95fb8526e89ab22cc5ffdbc314db23b6546`
**14,893,056 B = 909 × 16 KiB** (aligned; 14,820 bytes of pad added by the packer).

Built exactly to the ticket's spec — every input hash-matched **before** packing:

| Member | Hash | Note |
|---|---|---|
| m1n1 v7 (window-free) | `ecd264a5…` | matches ticket |
| kernel `Image-b0-dietcap.xz` | `9b4aa351…` | raw `e11296cd…`, 33.75 MiB / 9.85 MiB xz |
| DTB `t6040-j614s-dcuart.dtb` | `2782b922…` | storage-disabled |
| initrd `initramfs-alpine-b0-nb2.cpio.xz` | `d7fcc795…` | the PROVEN Alpine OpenRC RAM root |

`t6040-raw-object-verify.py --strict` → **PASS**, `entry=0x800`, runtime payload reserve
50,088,587 B.

## Bootargs are provably identical to the proven B0 set

The milestone writeups elide the bootargs as `3659a0da…`, so rather than retyping them the exact
string was recovered from the proven object `m1n1-b0-diet-aligned.bin` itself and reconciled:

```
maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 fbcon=font:TER16x32 ignore_loglevel rdinit=/sbin/init
```

`sha256("chosen.bootargs=" + args + "\n")` = `3659a0da253c7059…` — the documented value, and the
verifier reports that same hash embedded in the new object. So bootargs are **byte-identical** to
the proven set, as the ticket requires.

## The page-size premise is confirmed, not assumed

The whole point of 147 is isolating the 4 KiB→16 KiB ABI change. Verified from the **arm64 Image
header** (`flags` @ offset 24, bits 1-2 encode page size), not from build logs:

| Kernel | flags | page size |
|---|---|---|
| `Image-b0-diet` (proven B0) | `0xa` | **4K** |
| `Image-b0-dietcap` | `0xc` | **16K** |

A `strings` scan was misleading here — it reports a literal `4K pages` inside
`Image-b0-dietcap` (an unrelated kernel message string). The header is authoritative; **do not
page-size a kernel by `strings`.**

XZ member is minilzlib-safe: 1 stream, 1 block, CRC32, no BCJ filter.

## Metadata corrections

The 14x tickets all carried `deps: []` and `runnable: false` even though their text named
enabler 146, so ordering was not machine-visible.

- **146** → `done`, with the live confirmation (cold boot reaches `Running proxy`, proxy attaches,
  `No valid payload found` ⇒ payload-free as required).
- **147** → `deps: ["146"]`, `runnable: true`, staged object recorded.
- **148** → `deps: ["146"]`, `runnable: true`.
- **149** → `deps: ["146","147"]`, stays `runnable: false`.

**A factual error in 147's own text was corrected.** It read "tickets 147/148 results must not be
attributed to their own payloads". But **148 uses the PROVEN 4 KiB diet kernel `efba5999`** — it is
not affected by the page-size change at all. The ticket that shares the 16 KiB kernel is **149**
(whose own text already says "DEPENDS ON 147"). Left uncorrected this would have wrongly cast doubt
on a dwm result and wrongly cleared a ram0 result. Now: 147 gates **149**, not 148.

## Why this was not run autonomously

Every pass criterion — OpenRC default runlevel, health report begin→end, `event0` keyboard echo,
`watchdog0=present`, empty `/proc/partitions`, Norwegian keymap — is a panel/keyboard observation.
KIS and the USB gadget are mutually exclusive on the DFU port, so the agent-side gadget cannot
observe a `console=tty0` image. **Needs the maintainer at the panel.**

## To run it

```sh
bash scripts/t6040-debugusb-console.sh reboot     # into m1n1, attach kisd -> /tmp/m1n1
M1N1DEVICE=/tmp/m1n1 bash scripts/t6040-boot-raw-object.sh \
    ~/Code/linux-build-out/m1n1-b0-dietcap-smoke.bin
```

If it fails, the 16 KiB page change is the cause — and 149 must not then be attributed to its own
payload.
