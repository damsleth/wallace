# Ticket 170: the t6040 Type-C topology, mapped from the live ADT

Parsed the full J614s ADT (`j614s-usb-port-map-20260721.adt`, 162 arm-io nodes — the complete tree,
not a subset) offline with m1n1's `adt.py`. No rig, no writes. This is the authoritative address map
and it both confirms and **corrects** last night's DT-only optimism.

## The PHY + controller + DART half: t6040-native, and adaptable from the M2 template

Apple's ADT carries **t6040-specific compatibles**, so the register layout is a known quantity:

| node | compatible | base |
|---|---|---|
| `atc-phy2` (right port) | **`atc-phy,t6040`** | `0x193000000` (44 regs) |
| `usb-drd2` (right port) | **`usb-drd,t6040`, `usb-drd,t8132`** | `0x192280000` (9 regs) |
| `dart-usb2` | `dart,t8110` | `0x192f00000` + `0x192f80000` (**two** instances) |

The upstream atcphy driver's five `reg-names` map cleanly onto the ADT (offsets match the t602x template's
low bits, confirming the shared layout):

| upstream reg-name | t602x template offset | t6040 right-port address |
|---|---|---|
| `core` | `0x03000000` | `0x193000000` (atc-phy2 reg[2]) |
| `usb2phy` | `0x02a90000` | `0x192a90000` (atc-phy2 reg[0]) |
| `pipehandler` | `0x02a84000` | `0x192a84000` (usb-drd2 reg[3]) |
| `axi2af` | `0x00000000` | `0x190000000` (atc-phy2 reg[41]) |
| `lpdptx` | `0x03050000` | in the `atc2-dpxbar`/dp nodes (DP path) |

`dart-usb2` has **two** DART instances, matching the article's "two DART iommu instances for dwc3".
`usb-drd,t8132` is the t6040 dwc3 lineage — the compatible our dwc3 node should carry.

So the PHY/controller/DART nodes are genuinely adaptable from `t602x-dieX.dtsi`, with real addresses
now in hand. Full extraction: `/private/tmp/t6040-typec-adt-map.txt` (regenerate with
`M1N1DEVICE=none venv/bin/python /private/tmp/adt-usb3.py`).

## The correction: the PD controller is on SPMI, not I2C

Last night's plan assumed the upstream `apple,cd321x` **I2C** PD driver would apply. The ADT says
otherwise. Enumerating every I2C child:

```
i2c1/2/3  audio codecs (sn012776, cs42l84)
i2c4      sd-card (0x20)
i2c6      uatcrt0/1/2  "atcrt"  @ 0x18/0x19/0x1a   <- ATC RETIMERS (eUSB2/USB3 repeaters)
i2c8      pcon0 @ 0x08
```

There is **no CD321x / HPM / Type-C PD node on any I2C bus.** The PD controller appears instead as
SPMI: `nub-spmi0..4`, `nub-spmi-a0/a1`, all `aapl,spmi`. That is consistent with everything we already
knew — the 092–097 HPM work was SPMI-based, and `m1n1-hpm2` carries `tps6598x.c` — but it **contradicts
the upstream Type-C model**, where `tipd`/cd321x is an I2C driver. So on t6040 the VBUS/role-sourcing
controller is a TPS6598x-family part on **SPMI**, and the merged upstream I2C PD driver will not bind it.

### What this means for USB read/write

- The **data path** (atcphy + dwc3 + retimers + DARTs) is DT-describable from t6040-native ADT nodes.
- The **VBUS/role path** still runs through the SPMI PD controller — the same wall as the HPM 4CC work,
  whose role-swap sequence is still not decoded (096). Describing the PHY in DT does **not** by itself
  source VBUS to a bus-powered stick.

So last night's "DT-only, replaces HPM R3" hope is **half right**: the PHY half yes, the PD half no. The
honest split:

1. **Offline, high-value now:** author the atcphy/dwc3/dart/retimer DT nodes (all addresses known) so the
   USB3 data path is ready — this is a prerequisite either way and needs no PD decode.
2. **Still blocked:** VBUS sourcing, which needs either the SPMI PD controller driven (HPM path, 096
   decode) or a self-powered device on the port (the no-writes discriminator, maintainer-only).

## New finding worth its own note: ATC retimers

`uatcrt0/1/2` (`atcrt`, i2c6 @ 0x18/0x19/0x1a) are **ATC retimers** — eUSB2/USB3 signal repeaters in the
data path that our `apple,force-host-mode` DT never touched. If the data path needs the retimer
initialised (plausible for USB3; maybe not for USB2), that is a second missing piece independent of VBUS,
and it is I2C — describable with an upstream retimer binding if one exists. Tracked on ticket 170.
