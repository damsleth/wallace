# Bluetooth OBEX capability image, and two reproducibility bugs it exposed

Date: 2026-08-04. Agent: fable (second worker). Rig use: **none** — host-side
container builds and archive inspection only. No lease, no hardware, no
storage, no SMC/SPMI/PMU/NVRAM/firmware operation.

## Why

CJ defined the Bluetooth acceptance test on 2026-08-04: an **OBEX file transfer
between the M1 host and the M4, either direction**. `hci0` already works, so the
gap is OBEX userspace, not the driver.

Deliberate design choice: build this on the **headless WiFi/BT RAM root**
(`scripts/t6040-build-alpine-wifi.sh`), not the SD root. That decouples the
Bluetooth capability from the dirty-filesystem gate that blocks tickets 215/216,
and keeps the experiment read-only with respect to all storage. Ticket **228**
owns the live run.

## What was missing

`bluez` was already in the image builders; **`bluez-obexd` was in none of them**.
Added behind `T6040_OBEX=1` (opt-in, because obexd pulls libical/ICU — roughly
35 MB of RAM root we do not want in every boot). The default image is unchanged.

## Alpine 3.24 facts the helper had to encode

Three assumptions failed against the real package set; the builder's
member-presence gate caught each one before any rig time was spent:

1. **obexd is at `/usr/lib/bluetooth/obexd`**, not `/usr/libexec/bluetooth/obexd`.
2. **There is no `obexctl`** in Alpine's bluez. So `scripts/t6040-bt-obex.sh`
   drives `org.bluez.obex` over **`gdbus`** (chosen over `dbus-send` because it
   accepts variant syntax for the `a{sv}` session dictionary):
   `Client1.CreateSession` → `ObjectPush1.SendFile` → poll `Transfer1.Status`
   until `complete`/`error`.
3. **obexd is a SESSION-bus service** (`org.bluez.obex.service`, `Exec=obexd -n`)
   while bluetoothd is on the system bus. A session bus must exist and every
   later invocation must join *the same* one, or the client reports
   `org.bluez.obex` not provided. The helper caches the address in
   `/run/t6040-obex-session-bus` and liveness-checks it before reuse.

Note the packaged activation entry carries no `--root`/`--auto-accept`, so the
helper starts obexd explicitly and thereby owns the bus name before any
on-demand activation can win with the wrong flags.

## Two reproducibility bugs, found by building twice

Both were found only because the image was built twice and compared — the
project's stated invariant. Neither would have been visible from one build.

### 1. `dbus` bakes a random `/etc/machine-id`

Two otherwise identical builds differed in exactly one cpio member:
`./etc/machine-id` (33 bytes, random UUID written by the dbus post-install
trigger). Fixed by removing it at build time; the helper now creates a volatile
one at runtime via `dbus-uuidgen --ensure` before starting the system bus.

### 2. `scripts/t6040-build-alpine-wifi.sh` used bare `gzip -9`

After fixing the machine-id, the archives still differed while the
**uncompressed cpio streams were byte-identical** (`02967c37…` both). The
difference was 4 bytes in the gzip header: the MTIME field, i.e. the build
clock.

```text
1f8b 0800 041b 716a 0203   build 1
1f8b 0800 101b 716a 0203   build 2
```

`gzip -n` suppresses it. **Every other Wallace builder already used
`gzip -n -9`; this one was the sole outlier**, which means no hash pinned from
this builder could ever have been reproduced, and any past "two builds differ"
observation against a WiFi image was this bug rather than real nondeterminism.
Worth remembering as a build invariant: *compare the payload before blaming the
content* — a differing archive hash with identical members is a container
problem.

## Result

Two clean builds are now byte-identical:

```text
6de5abfea4ca552c608667031f8a6f92da2dd5894823d22c9b802910d9005c41  initramfs-alpine-wifi-obex.v3build1.cpio.gz
6de5abfea4ca552c608667031f8a6f92da2dd5894823d22c9b802910d9005c41  initramfs-alpine-wifi-obex.v3build2.cpio.gz
```

Paired members for the ticket-228 tethered chainload (`maxcpus=1`):

```text
43e1a7d4656b7cd692b7217fdccb77bf68c96a28b79e8579dad1d73ee369b8e5  Image  (Linux 7.1.3-g4f2429104009, pcie-apple/macsmc/brcmfmac/hci_bcm4377 builtin)
7fea8942aadb47ed83915f95e210c489d64264ca1420913a13635ca48d702cfa  t6040-j614s-dcuart-wifi-cpufreq.dtb
6de5abfea4ca552c608667031f8a6f92da2dd5894823d22c9b802910d9005c41  initramfs-alpine-wifi-obex.v3build1.cpio.gz
```

## The transfer direction matters, and one half needs CJ

The M1's controller is `F8:4D:89:6C:92:CB` (BCM_4387, powered on, currently not
discoverable). Its advertised services are
`HFP AVRCP A2DP HID Braille LEA AACP GATT SerialPort` — **no OBEX Object Push**,
because macOS only advertises OPP when **Bluetooth Sharing** is enabled in
System Settings.

Consequently:

- **M1 → M4 is the preferred direction.** macOS can send *outbound* without
  enabling Bluetooth Sharing (Bluetooth File Exchange), and the M4 side is fully
  automatable: obexd with `--auto-accept --root`, adapter discoverable, a
  `NoInputNoOutput` agent so pairing takes the JustWorks path with no local
  input.
- **M4 → M1 additionally requires Bluetooth Sharing switched on** on the Mac,
  which is a system-settings change and therefore CJ's to make, not an agent's.

So the honest boundary of what an agent can prove unattended is *everything up
to the remote push*: hci0 up, `org.bluez.obex` present on the session bus, the
OPP UUID advertised, the adapter discoverable and pairable, and a bounded inbox
ready. The final send is one GUI action, or one Sharing toggle plus a scripted
`t6040-bt-obex send`. Pairing may also raise a confirmation dialog on the Mac.

## Not claimed

No OBEX transfer has run yet. `hci0` working is prior art
(evidence/2026-07-29-t6040-WIFI-AND-BLUETOOTH-WORKING.md); this document adds
only the userspace path and its artifacts. RAM-root pairing keys live on tmpfs
and do not survive a reboot, so nothing here is persistent.
