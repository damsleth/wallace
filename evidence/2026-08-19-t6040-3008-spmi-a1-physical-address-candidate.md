# Ticket 3008: corrected a1 physical-address DTB candidate

Date: 2026-08-19. Builder: sol. Scope: offline build and static inspection
only. No lease, rig command, MMIO, SPMI transaction, enrollment, or storage
access occurred.

## Result

PASS for offline construction. Two fresh source exports produced byte-identical
DTBs with the ticket-3000 address correction:

```text
eaf8cceb8c22d19f71ea0175397a96bd41ff6ebf56ab0719da7da0272f068acf  t6040-j614s-dcuart-usb2-native-right-pd-physfix.buildA.dtb
eaf8cceb8c22d19f71ea0175397a96bd41ff6ebf56ab0719da7da0272f068acf  t6040-j614s-dcuart-usb2-native-right-pd-physfix.buildB.dtb
```

`cmp` reports the files are byte-identical. This artifact is **not approved to
boot**: ticket 305 may resume only after an independent reviewer checks the
exact `eaf8cceb...` DTB and the composed fixture.

## Effective correction

Ticket 3000 proves that the ADT value `0x309198000` is the raw `/arm-io` child
address. `/arm-io/ranges` adds `0x200000000`, yielding CPU physical
`0x509198000`. Linux `/soc` uses identity addressing, so the PD fixture now has:

```dts
nub_spmi_a1: spmi@509198000 {
	compatible = "apple,t6040-spmi", "apple,spmi";
	reg = <0x5 0x09198000 0x0 0x4000>;
	power-domains = <&ps_nub_spmi_a1>;
	status = "okay";

	hpm2: usb-pd@c {
		compatible = "usbc,sn201202x,spmi";
		reg = <0xc SPMI_USID>;
	};
};
```

No kernel rebuild is needed: the driver and transaction envelope are unchanged
from the already reviewed ticket-305 image.

## Clean-build method

Both builds started from separate `git archive HEAD` exports of Linux commit:

```text
4f2429104009e3964ddcc326d8490ac25bfb1a5c
```

The exports were independent and contained no prior build objects. The exact
T6040 include closure was then copied from the shared source tree, matching the
previous ticket-305 fixture, and the corrected Wallace wrapper was added. Each
tree independently ran `make ARCH=arm64 defconfig` followed by the single DTB
target. Build directories were:

```text
/build/t3008-A-archive.DPzZ0r
/build/t3008-B-archive.Evxfg4
```

The two source manifests are byte-identical. Their hashes are:

```text
02e6060225aa7712604fca98331c02c2d2b14acca1c7d90d7c6216ee18767fc0  t6040-pmgr.dtsi
edfe80b145fa0ba1f2ca0a24d1ac2b25a839f1065c0bed9610f9563bc32d9f06  t6040.dtsi
a8048e982b63fe19a346318ef7c51f076a3df70b7b9b0fea153ea9446142ae6f  t6040-j614s-dcuart.dts
ecf6df1ff634621c66be43689f3a46f8bc6ef182b24300c80b0325c52630fd58  t6040-j614s-dcuart-pcie.dts
60bddf64d8a16d79113cd904a826b37286cac733feb1bd868d6ae82d177506b4  t6040-j614s-dcuart-wifi.dts
f045e2e13b685a2409d025b476d327fa53c5781b486f8cb687d2188aa8f00301  t6040-j614s-dcuart-wifi-usb2-native-right.dts
46cbb243c560a7c5bd33a5543060e6eda4901f4b00869ed965b972dd952db35c  t6040-j614s-dcuart-usb2-native-right-pd.dts
```

## Compiled-DTB audit

Decompilation of build A (`c5379e83...`) proves the binary contract:

| Check | Compiled result |
|---|---|
| a1 controller node | exactly one `/soc/spmi@509198000` |
| a1 controller resource | `<0x05 0x09198000 0x00 0x4000>` |
| stale raw-address node | zero `spmi@309198000` nodes |
| a1 genpd | phandle resolves to `label = "nub_spmi_a1"` |
| PD endpoints | exactly one `usbc,sn201202x,spmi` |
| endpoint | `usb-pd@c`, SID `0x0c`, USID `0x00` |
| connector policy | `power-role = "source"`, `data-role = "host"` |
| internal NVMe | `/soc/nvme@44dcc0000 status = "disabled"` |
| primary SPMI | unchanged at `/soc/spmi@509014000`, with its bounded abbey node |

The primary SPMI endpoint remains within Entry 2 of `docs/SPMI_SAFETY.md`; the
new a1 endpoint remains limited to Entry 1's right-port hpm2 envelope. No other
HPM or SID is described.

## Reused, pinned fixture components

```text
5a136710684dbda738cfb51ea0149b9cf64d2ca58c15f1c66a1d6b0310ad9af8  Image-usb2pd.buildA
51aa40f0df95a6938d7067f107f7b4aa0d614bea6c2c269a4e1b10a9e745b2d1  config-usb2pd.buildA
4cc6513365803f161100d93b9dd9ae7c1a75d0a82e2d196ba7e776f8bb93f672  initramfs-sdroot-hardened.cpio.gz
9dcb4606e6385815dafa29f2690cf5cc29021d07387da78b55a09d4385b28350  0001-usb-typec-tps6598x-add-SPMI-transport-for-T6040-SN20.patch
```

`scripts/t6040-image-preflight.sh` passed the pinned Image and initramfs: the
kernel contains `pcie-apple`, `macsmc`, and `dockchannel-hid`; the initramfs
contains and loads the Norwegian keymap, contains `fsck.exfat`, and includes
the required WiFi/BT firmware.

## Review and live gate

An independent reviewer must compare the exact DTB hash above against ticket
3000 and the ticket-305 envelope, then record PASS before any boot. The attended
ticket-305 run must retain `maxcpus=1`, the existing consoles and stop
conditions, the seated passive S128 stick, and the prohibition on block reads
or mounts. Tickets 1000 and 1002 are fallback investigations only if this
address-corrected candidate still stalls.
