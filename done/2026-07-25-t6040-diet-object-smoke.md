# T6040 diet object chainload smoke — PASS, and two retractions (2026-07-25)

## Diet object `b5c9bfc8` (9.01 MiB) boots

Chainloaded onto the enrolled 14 MiB probe m1n1. `diet-chainload.log`:

- `Found an XZ compressed payload` x2 (kernel, initramfs) — minilzlib fine
- `Linux wallace-b0 7.1.3-g246843ff67a8-dirty #1 SMP PREEMPT` — the **diet
  kernel** (16.8 MiB raw, 67% smaller) reaches userspace
- `input0` + `H: Handlers=sysrq kbd leds event0` (05ac:0359) — dockchannel HID
  survived the diet
- `watchdog0=present`, `/proc/partitions` empty, no network runlevel,
  health report begin->end, `wallace-b0:~#`

So the 31-symbol assertion held in practice: nothing boot-essential was lost.

## m1n1 v2 unconditional proxy window works

```text
Boot policy: sip0 = 0
Bringing up USB for early debug...
Waiting for proxy connection... ..... Timed out
```

The window armed **despite `sip0 = 0`** (upstream's gate would have skipped it),
waited 5 s, timed out, and auto-booted the payload. That is exactly the intended
dual-mode behavior, and it gives a **cold-boot debug door**: with v2 enrolled,
every cold boot offers 5 s in which a host can attach a proxy *before* the Linux
handoff — a live m1n1 shell at cold boot, which is precisely what is needed to
debug the enrolled-payload failure.

Not verified remotely: the Norwegian keymap service. OpenRC's `ebegin` output
goes to the console (tty0/panel), not ttydc0, so it needs maintainer eyes on the
panel. **Improvement to make:** have `t6040-b0-health-report` echo the active
keymap (e.g. `cat /etc/wallace-keymap` + `dumpkeys`-style check) so it lands in
the ttydc0 transcript.

## Retraction 1 — "m1n1 never runs when enrolled" was not proven

Basis was 0 bytes of console during the loop. But a later run showed DebugUSB
entry itself can fail (`Switching target into debug USB mode... Failed to send
VDM`), and debug mode very likely does not survive the loop's repeated resets —
which is why the standard procedure is `macvdmtool reboot debugusb` (enter debug
mode *during* boot). So 0 bytes is fully explained by "no debug mode across
resets" and says nothing about whether m1n1 executed. Unresolved.

## Retraction 2 — "the object tail overwrites iBoot structures" is dead

The enrolled 14 MiB non-zero probe printed:

```text
MMU: RAM base: 0x10000000000   Top of normal RAM: 0x105ce7a8000
Unknown payload at 0x10005f18000 (magic: a5a5a5a5)
No valid payload found
Running proxy...
```

m1n1 loads at ~`0x10005E0C000` and **read the full 14 MiB tail** (it reported the
`0xA5` filler), with ~23 GB of RAM above it. There is nothing for the tail to
collide with, and iBoot loads a 14 MiB object completely.

## Where the mystery actually stands

| Enrolled object | Payload | Size | Result |
|---|---|---|---|
| `0xA5` filler probe | no | 14.0 MiB | boots, m1n1 scans tail |
| xz B0 | **yes** | 15.2 MiB | loop |
| gz B0 | **yes** | 22.2 MB | loop |

Size is effectively excluded (14 MiB loads fine; a 14->15.2 MiB wall is
implausible and would not explain much). The surviving discriminator is
**"carries a real, parseable payload"**, i.e. the enrolled path's *Linux handoff*
differs from the chainload path. Leading hypothesis: chainload does explicit
SEPFW relocation + ADT fixups (`chainload_image()` copies SEPFW and rewrites
`/chosen/memory-map`) that a directly-enrolled m1n1 never performs, so a direct
enrolled boot may hand Linux a different/incorrect firmware memory picture and
panic-reset before any visible output.

## Next experiment (cheap, decisive)

Enroll the **diet v2 object `b5c9bfc8`** (9.01 MiB):

- **Boots** -> milestone B0, and size was the factor after all.
- **Loops** -> payload-carrying is the discriminator. Then capture properly: run
  `t6040-debugusb-console.sh reboot` *while it is looping* so debug mode is
  entered during boot, and/or attach a proxy inside v2's 5 s window to get a live
  m1n1 shell at cold boot. Either yields the first real console from a failing
  enrolled-payload boot.
