# Ticket 230: trackpad finger test — PASS (live, CJ's finger)

Date: 2026-08-19. Agent: opus (rig handle renamed from `fable` this session —
see the mandate memory; a sibling `fable` session concurrently holds the 108
lane). Lease held as `opus`. CJ physically present for the finger test.

## Result — PASS, decisively

The second half of ticket 230's pass criterion (a human finger during a watch
window, `bytes>0 events>0` plus a hex dump) is met:

```text
T6040_INPUT_WATCH_RESULT dev=/dev/input/event0 bytes=910800 events=37950
T6040_INPUT_EVENTS_PRESENT
```

`event0` = "Apple DockChannel Multi-touch". CJ moved a finger across the pad
for the 60 s window; the reporter captured **37,950 input events / 910,800
bytes**, with a hex dump of genuine multi-touch reports (the `a1 … 09 b0 03 …`
records carry changing X/Y/pressure fields, e.g. `39 00`, `30 00 c4 01`,
`31 00 2e 02`, `34 00 71 e9 ff ff`). The pre-patch failure mode (open() → rc=1,
no touch pipeline) is gone; touch data flows end to end into Linux input.

## Bonus, not previously seen in bring-up: haptic click works

CJ reports **definitive haptic click feedback** (the Taptic Engine vibration
emulating a physical click) when pressing the pad — which never happened
before during bring-up. The boot log corroborates the actuator coming up in
the dockchannel-hid enumeration:

```text
actuator_cr.c:84: Actuator interface configuration completed
actuator.c:71:    Actuator ready
```

So the full trackpad experience — multi-touch input and force-click haptics —
is live, not just the touch transport.

## Fixture (exactly the 230-pinned artifacts; kernel/DTB/initramfs verified)

- Image `Image-trackpad-reset-contract` sha256 `80c15f58…` (boot-guard markers
  present: pcie-apple, macsmc, dockchannel-hid).
- initramfs `initramfs-dcuart-trackpad-230.cpio.gz` sha256 `87442995…`.
- DTB `t6040-j614s-dcuart.dtb` — decompiled and checked this session: has the
  `multi-touch { firmware-name = "apple/tpmtfw-j614s.bin"; }` node and NVMe
  `status = "disabled"` (no ticket-227 hazard). Not hash-pinned by 230; content
  verified.
- Kernel version `7.1.3-g4f2429104009-dirty`, `maxcpus=1`.
- Boot via `IMAGE=Image-trackpad-reset-contract scripts/t6040-boot-dcuart.sh
  t6040-j614s-dcuart.dtb initramfs-dcuart-trackpad-230.cpio.gz` over the
  enrolled rollback proxy (`$OUT/Image` was stale `43e1a7d4`, so `IMAGE=` was
  passed explicitly — the freshness trap was avoided).

## Transcript

`linux-build-out/230-finger-test-opus-20260819.console.log` sha256
`1c2e2eb272fc1d42b7d63cf351566f339854cea5414c6675ac26ee2aee9c5016`.

## Safety / scope (as approved)

Ticket-126 volatile-upload exception for blob `a1f4131d` only: volatile DMA
firmware upload to the MTP coprocessor, no flash, no persistent write; no
SMC/SPMI/PMU/charger/NVRAM write; storage-disabled RAM root (nothing
persistent). No SError, DART fault, firmware panic, unexpected reset, or
console loss during the run. Rig recovered to a clean m1n1 proxy from the
enrolled rollback before the chainload.

## Coordination note

The rig-lease collision that preceded this run (a shared `fable` handle across
two sessions let `acquire fable` silently renew+relabel an already-held lease)
is why CJ renamed this session's handle to `opus`. The run itself was executed
cleanly under the distinct `opus` lease after the sibling `fable` released.

## Status

Ticket 230 closed: `v2-accepted-live` (2026-08-04) + finger confirmation
(2026-08-19) = both halves of PASS met. The trackpad is a working input device
with haptics on the T6040 daily driver.
