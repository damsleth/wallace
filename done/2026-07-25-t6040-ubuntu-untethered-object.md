# T6040 untethered Ubuntu object (ticket 136) — built (2026-07-25)

```text
m1n1-b0-ubuntu-untethered.bin
SHA-256 6b5060d04388b91335416c1f524330a79b974ce76bbdf853228e420aa5f816aa
23,691,264 B = 22.59 MiB = 1446 x 16 KiB pages (auto-padded, aligned)
```

| Member | SHA-256 | Size |
|---|---|---|
| m1n1 v3 (fb console forced on) | `c59d5820…` | 1.05 MiB |
| diet kernel (xz) | `efba5999…` | 4.68 MiB |
| storage-disabled DTB | `2782b922…` | 0.05 MiB |
| **Ubuntu 24.04 RAM root (xz)** | `e02e9a88…` | **16.81 MiB** |
| bootargs `5a24d959…` | — | `… rdinit=/init` |

Strict verifier PASS. Headroom against the measured 64 MiB ceiling: **41.4 MiB**.

## Notes

- The Ubuntu root is the ticket-091 live-proven image (`initramfs-ubuntu-ramroot-no.cpio.gz`,
  `0987cb7c…`) **re-compressed as minilzlib-safe xz** (`-9e --check=crc32 -T1`):
  28.0 MiB gz → **16.8 MiB xz**, saving 11.2 MiB. Content is unchanged (same cpio bytes).
- `rdinit=/init` — this image boots its custom `/init` at the root, not `/sbin/init`
  (unlike the Alpine/OpenRC B0 root). Confirmed present in the archive.
- Its keymap path differs from Alpine's too: Ubuntu ships a real `usr/bin/loadkeys` plus
  `usr/share/keymaps/i386/qwerty/no-latin1.kmap.gz`, so it uses `loadkeys`, not BusyBox
  `loadkmap`.
- The kernel will unpack a **97.3 MiB** cpio into RAM. m1n1's xz decoder advertises a
  1 GiB ceiling and the machine has ~23 GiB, so this should be fine — but it is the
  first large-payload decompression on this path and is the one genuinely untested
  aspect (iBoot's *load* ceiling and m1n1's *decompress* capacity are different limits).
  Expect a visibly slower boot than the 3.4 MiB Alpine root.

## Test order

1. **Tethered chainload smoke** (`scripts/t6040-boot-raw-object.sh` with this object) —
   proves the diet kernel + Ubuntu root + large xz decompression before spending an
   enroll cycle. Requires a working loader enrolled.
2. **Enroll + cold boot** (1TR, maintainer) → untethered Ubuntu on the panel.

Pass: Ubuntu userspace on the internal panel, Norwegian keymap loaded, watchdog fed,
`/proc/partitions` empty.
