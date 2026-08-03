# T6040 U-Boot stage-2 banner chainload — RESULT (2026-07-25)

Ticket 131, approved by cj (cross-review waived in chat, sol unavailable;
author self-review recorded on the ticket, including the wdt pass-condition
catch). Run tethered under lease `claude`, evidence in
`~/Code/linux-build-out/t131-chainload.log`.

## Result: PASS on every machine-verifiable criterion

`chainload.py -r uboot-stage2-banner-chainload.bin` (`a787e38e…`,
2,181,175 B) over the enrolled `1394c345` proxy. The new m1n1 v3 instance
(`c59d5820…`) came up over the tether and its log shows the full expected
sequence:

```text
dapf: Skipping /arm-io/dart-aop (async L2C SError on this M4 SoC)   [expected skips]
WDT: armed for ~20s (warm reset on hang)
Preparing to boot kernel at 0x10008400000 with fdt at 0x10008600000
Valid payload found
Preparing to run next stage at 0x10008400000...
USB0: shutdown / USB1: shutdown / USB2: shutdown
MMU: shutting down...
Vectoring to next stage...
```

- **Payload discovery works when chainloaded** — the same DTB+U-Boot payload
  shape that is undiscoverable when *enrolled* (payload-scan root cause) is
  found and staged correctly by `chainload_image()`. `Valid payload found` +
  the DTB handed to the next stage at `0x10008600000` is the direct proof.
- **U-Boot was entered.** m1n1 shut down its gadgets and MMU and vectored to
  the U-Boot Image entry. The subsequent `chainload.py` NOP timeout is the
  expected outcome (U-Boot does not speak the proxy protocol).
- **Self-recovery works as redesigned.** The 20 s watchdog (armed by m1n1,
  never petted by the WDT-less U-Boot) warm-reset the machine; the enrolled
  loader and proxy returned without a power-cycle — verified live with a
  proxy NOP + base read (`m1n1 base: 0x10005144000`). Rig released
  `--state healthy`, reader restored.

## Caveat, stated honestly

The **panel** (U-Boot banner/model line) was not visually observed during the
~20 s window — nobody was looking at the screen. The pty evidence proves m1n1
vectored into U-Boot and the system stayed alive until the wdt fired ~20 s
later (a crashing payload would more likely have raised an exception m1n1
v3's FB console would have shown, or reset sooner via SError). Visual
confirmation is one 30-second rerun whenever eyes are on the panel:

```bash
cd ~/Code/m1n1 && M1N1DEVICE=/tmp/m1n1 venv/bin/python proxyclient/tools/chainload.py -r ~/Code/linux-build-out/uboot-stage2-banner-chainload.bin
```

(Kill the `/tmp/m1n1-console.log` reader first; it steals proxy replies —
that was the cause of the first-attempt `UartTimeout`, fixed by re-running
`t6040-debugusb-console.sh` and killing the reader before the chainload.)

## Operational notes for every future U-Boot cycle

1. Each U-Boot run is a **bounded 20 s self-recovering probe** — wdt warm
   reset back to proxy, no manual recovery. This makes U-Boot iteration on
   this rig fast and safe.
2. The console-log reader must be stopped before any manual proxyclient use.
3. m1n1's `USB0/1/2: shutdown` before the jump means U-Boot inherits *shut
   down* gadgets — further confirmation that U-Boot starts from a cold,
   non-host port state on T6040 (consistent with the Q1 = NO analysis).

## Staged next (ticket 132, NOT run — paused for CJ's manual experiment)

USB-probe variant: same stage-2 build + `CONFIG_PREBOOT="usb info; usb
start; usb tree"`, double-built byte-identical
(`u-boot-nodtb` `f3da1c17…`, 550,624 B, image_size 1,031,760, pad 481,136).
Composed probe image `uboot-stage2-probe-chainload.bin` = m1n1 v3 + same DTB
+ probe U-Boot + pad, 2,181,215 B, `4069efa9…`, structure machine-verified.
Expected on-panel result: xHCI + root hubs, **zero devices** (HPM2 host
transition still missing = R3), all within the 20 s window.
