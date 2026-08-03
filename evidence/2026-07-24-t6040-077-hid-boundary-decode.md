# T6040 ticket 077 HID boundary decode

Date: 2026-07-24  
Scope: offline only; no rig or hardware access

## Result

Ticket 076 proves that the MTP DockChannel transport and the complete DCHID
interface-creation lifecycle work. It does not prove that any created HID bus
device binds a HID driver or reaches `hidinput_connect()`.

| Boundary | Exact observation | Conclusion |
|---|---:|---|
| DockChannel IRQ | calls 26, wakes 19, RX runs 19 | IRQ delivery works |
| DockChannel FIFO | 13 batches, 1,396 bytes | FIFO drain works |
| DCHID receive | 13 callbacks, 1,396 bytes | mailbox-client delivery works |
| DCHID parse | 19 packets: 8 command, 11 report | packet parsing works |
| ACK matching | 8 ACKs, 8 matches | command/response matching works |
| lifecycle events | 11 events | work dispatch works |
| INIT | `0x7e` (interfaces 1–6) | all six descriptors received |
| READY | `0x7c` (interfaces 2–6) | STM and keyboard ready observed |
| STM identity | returns 34/23; `05ac:0359:0510` | identity acquisition works |
| create queued | `0x7e` | all six HID creations queued |
| `hid_add_device()` | `create_ok=0x7e`; each return 0 | parse and `device_add()` returned success |
| Linux input | empty `/proc/bus/input/devices`; no `/dev/input` | no input device registered |

`hid_add_device()` returning zero is not the same as a HID driver probe
succeeding. In the 7.1.3 HID core it parses the descriptor and calls
`device_add()`. Driver binding occurs through `hid_device_probe()`; a later
driver-probe failure does not turn the already successful `device_add()` into
an error returned to the DockChannel worker.

## Working-versus-failing comparison

The known-good `Image-keyboard`
(`cc2b3de15efbf4fbf5c4d7ac7d6b8155e5c4c52e0deabd9e012ffa379b37fb58`)
and failing trace kernel have identical relevant settings:

```text
CONFIG_INPUT=y
CONFIG_INPUT_EVDEV=y
CONFIG_INPUT_KEYBOARD=y
CONFIG_HID=y
CONFIG_HID_GENERIC=y
CONFIG_HID_APPLE=y
CONFIG_HID_MULTITOUCH=m
CONFIG_APPLE_DOCKCHANNEL_HID=y
```

Both System.map files contain `hid_add_device`, `hid_device_probe`,
`hid_hw_start`, `hidinput_connect`, `apple_probe`, and
`apple_input_mapping`. The two imported DockChannel HID commits
`356985c33ceb` and `79ddb8fc3b49` contain byte-identical driver and Kconfig
files:

```text
apple_dockchannel_hid.c
bc2b36b9c4506127f168baaf5e50a9223ef16e9b3f589328c75510f2ad9c0e59
Kconfig
fb5d756e4c5642dcce94621ea071a29f5648b465dc4285f8efefb4bf72123b38
```

The initial ticket-076 claim of a demonstrated transport-driver regression was
too broad, but comparing the *surrounding* HID driver supplies the missing
causal delta:

- mainline v7.2-rc2 (the working kernel line) has no Apple `BUS_HOST` match;
  `hid-generic` can bind the DockChannel keyboard;
- the failing Asahi 7.1.3 line adds a wildcard Apple `BUS_HOST` entry;
- that line's `apple_probe()` returns `-ENODEV` unless
  `hdev->type == HID_TYPE_SPI_KEYBOARD`;
- active `apple_dockchannel_hid.c` never sets `hid->type`, so it remains
  `HID_TYPE_OTHER`;
- `hid-generic` declines whenever another HID driver matches, even if that
  driver's probe then rejects the device.

The newer sibling `drivers/hid/dockchannel-hid/dockchannel-hid.c` confirms the
intended contract: it sets `HID_TYPE_SPI_KEYBOARD` for `"keyboard"` and
`HID_TYPE_SPI_MOUSE` for `"multi-touch"` before `hid_add_device()`.

## Minimal fix and falsification

`patches/t6040-dockchannel-hid-type.patch`
(`8692c4554f2db232fa57ee4fbc2e3ac529b1a8d36c44629612a478c30d8a455c`)
copies only those type assignments into the active transport. It adds no
hardware access or control-flow change below HID registration.

Falsification condition: with the exact ticket-076 config, DT, initramfs, and
boot arguments, the patch would be disproven if the Apple keyboard still
failed to appear as a bound input device/event node.

Ticket 078's live run did not falsify it: `Apple DockChannel Keyboard`
registered as `input0`, handlers `sysrq kbd leds event0`, with
`/dev/input/event0` present and partitions still empty. Exact result:
`done/2026-07-24-t6040-hid-type-fix-result.md`.

The reporter's additional ordinary probe/sysfs inventory remains a useful
host-tested diagnostic, but no extra observation run is required for this
resolved boundary.
