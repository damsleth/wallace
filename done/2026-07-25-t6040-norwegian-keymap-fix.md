# T6040 B0 Norwegian keymap — root cause + fix, live-verified (2026-07-25)

Maintainer reported on the panel: `no Norwegian keymap could be loaded` /
`failed to load t6040 keymap`, console still US.

## Root cause: wrong tool, wrong input channel

The service called `loadkeys "$map"`. Two independent errors:

1. **BusyBox has no `loadkeys`.** `loadkeys` is kbd's *text*-keymap compiler.
   BusyBox provides **`loadkmap`**, which reads a **binary** keymap from
   **stdin** — `loadkmap < file`, never `loadkmap file`.
2. **No applet symlink.** Alpine's minirootfs ships the busybox binary with
   `loadkmap`/`dumpkmap` compiled in (confirmed by string inspection) but creates
   **no** `bin/loadkmap` symlink, so even the right name would not resolve on
   `PATH`. It must be invoked through the multiplexer: `busybox loadkmap`.

The `.bmap` binary keymaps themselves were correct all along (Alpine
`kbd-bkeymaps`, the format `loadkmap` expects).

## Fix

`scripts/t6040-b0-keymap.initd` (now tracked):

```sh
for map in /usr/share/bkeymaps/no/no-mac.bmap /usr/share/bkeymaps/no/no.bmap; do
    [ -f "$map" ] || continue
    if busybox loadkmap < "$map" 2>/dev/null; then
        printf 'loaded %s\n' "${map##*/}" > /run/wallace-keymap-status
        eend 0; return 0
    fi
done
printf 'FAILED (no keymap loaded; console stays US)\n' > /run/wallace-keymap-status
```

Also — the reason this shipped broken — the failure was only visible on the
**panel** (OpenRC `ebegin` goes to the console), so the remote ttydc0 transcript
could not falsify it. `scripts/t6040-b0-health-report` now prints:

```text
-- console keymap --
<contents of /run/wallace-keymap-status>
```

so keymap success/failure lands in the remote log and is agent-verifiable.

## Live verification

Object `m1n1-b0-diet-nb2.bin`
`d645bf95d6efea5833458bc33dd1b576822af643d19164da3f75e9a055a850ef`
(9.02 MiB) chainloaded; `nb2-chainload.log`:

```text
-- console keymap --
loaded no-mac.bmap
=== t6040 B0 health report end ===
```

plus `event0` HID, `watchdog0=present`, empty partitions, `wallace-b0:~#`.
Initramfs `d7fcc795` (707 entries, 0 block nodes, invariants preserved).

`no-mac` is the **Apple** Norwegian layout (differs from PC Norwegian on several
symbol positions); plain `no` is the automatic fallback and a one-line swap if
the physical layout disagrees. Still needs maintainer eyes on the panel to
confirm the *physical* mapping (æ ø å and symbol keys) — loading is proven, key
positions are not something the remote log can show.

## Lesson recorded

Any B0 userland assertion that can only be observed on the panel must also be
mirrored into the ttydc0 health report, or it cannot be verified without the
maintainer.
