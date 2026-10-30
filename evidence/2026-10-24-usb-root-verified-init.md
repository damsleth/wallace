# Verified right-port USB-root preparation — ticket 6005

Astra, 2026-10-24. Offline source preparation and contained host tests only.
The full daily-driver objective remains active; no USB-root hardware result,
image qualification, enrollment, or permission to erase a stick is claimed.

## Concrete progress

The legacy `t6040-init-usb-root` accepts PARTUUID/LABEL/UUID/device-path roots
and mounts the resolved device read-write without proving USB ancestry or
stick identity. Its assertion that internal NVMe is invisible is obsolete.
It also spawns a diagnostic shell without loading the Norwegian map.
The existing 305/6001 payloads and legacy init were left unchanged.

Prepared a **separate** source candidate:

- `scripts/t6040-usb-root-select.sh`: no generic resolver. Requires exactly one
  directly attached, removable disk under the known right-port
  `392280000.usb` controller, with exact VID/PID, serial, route and capacity.
  Binds partition1 to that physical disk and verifies its kernel start/length
  against the GPT, checks mountinfo, rejects aliases,
  ambiguous matches and arbitrary root selectors, and ignores NVMe/SD devices.
  No metadata read occurs before these sysfs gates. Config is parsed through
  an explicit field allowlist, never sourced/evaluated.
- `scripts/t6040-usb-root-metadata.c`: bounded read-only GPT/ext4 verifier.
  Checks protective MBR, both header/array CRCs, matching primary/backup
  geometry and disk GUID, exactly one Linux filesystem partition with pinned
  PARTUUID, start/label/attributes, ext4 UUID/label/size and clean/no-replay
  state. `--image` only accepts regular files; `--disk` only accepts Linux
  block devices and requires the expected sysfs device number. No writable
  open, mount, fsck repair or controller transaction exists in this helper.
- `scripts/t6040-init-usb-root-verified`: pins and loads the Norwegian map
  before any shell; requires one online CPU and packaged metadata/selector/
  e2fsck helpers. It retries discovery only, stops at metadata failures, runs
  `e2fsck -f -n`, inspects the root `ro,noload`, checks OpenRC, root identity,
  Norwegian OpenRC/Xorg and the root-RO shutdown service, unmounts the RO view,
  rechecks identity and only then permits the reviewed root's RW handoff.
- `scripts/t6040-usb-root.identity.example`: intentionally unusable until exact
  physical identity is recovered through 109 after 305. Its historical 098
  GUIDs are regression inputs, not approval of that image as the final root.

The init does not change DT/SPMI/SMC policy. The eventual kernel/DT must use
305's corrected hpm2-only PD path and only the transactions allowed by
SPMI_SAFETY. No blanket HPM scan, role-swap command or additional endpoint is
introduced. The SD shutdown work completed concurrently in 3006 was not edited.
The direct ext4 USB root uses OpenRC's root-RO shutdown contract; the nested
SD exFAT/loop path remains a separately tested fallback.

## Actual verification

`python3 scripts/t6040-test-usb-root-gates.py` runs the real C parser and shell
selector against synthetic **regular files** and fake sysfs/mountinfo. The
synthetic ext4 superblock fixtures are not complete filesystems. Passing them
is metadata-policy coverage, not fsck or filesystem validation.

48 cases pass on Linux/aarch64, including corrupt primary/backup GPT and array
CRCs, valid-CRC backup disagreement, wrong GUID/type/extent, extra partitions,
dirty/error/replay state, filesystem overrun, truncated media, aliases,
wrong serial/USB IDs/controller/hub route, mounted devices, duplicate sticks,
root= aliases, partition-to-disk mismatch and NVMe/SD exclusion. The same
48 cases pass on macOS/arm64 with AddressSanitizer and UndefinedBehaviorSanitizer.
No block device, mount, loop device, fsck or rig was accessed by these tests.

The existing ticket 098 regular-file image was separately hashed and passed
metadata verification. Its SHA remains
`1c493fad1d1b44520d9265c5946c8ac00b867b3d47fac93f88d1f55cde25060e`.
Its GPT ext4 root extent is LBA2048–2097118. That confirms this parser agrees
with the preserved image's earlier independent GPT/ext4 record; no real stick
identity is inferred from it.

A native static aarch64 helper is saved at:

`/Users/damsleth/code/linux-build-out/usb-root-6005/t6040-usb-root-metadata-4ccc71af-aarch64`

SHA-256 `4ccc71af7bf764c3439a991acd6fd4560ec1bb9e6636700de6682fca148b895f`.
Built once in the pinned Alpine container
`sha256:2c9d26f410d032d5b1525aa8a873e238b05b90c4ae8618743d4311f0cc827e37`
using gcc14.2.0-r6 / musl1.2.5-r13 and linux-headers6.14.2-r0. The first
compile lacked `linux/fs.h`; adding linux-headers resolved that build dependency.
Compiler/package manifests and Linux results are saved with the
[source/artifact manifest](2026-10-24-usb-root-gates/manifest.json).

Evidence: [native cases](2026-10-24-usb-root-gates/linux-tests.json),
[sanitizer cases](2026-10-24-usb-root-gates-sanitizer-tests.json),
[098 regular-file check](2026-10-24-usb-root-gates/ticket-098-regular-file-check.txt).
Shell syntax checks pass for the new shell sources. The production metadata
block-device branch compiled but was deliberately not exercised on a device.

### Actual init control-flow regression

The actual init and selector now run as PID1 in a fresh chroot/PID namespace
inside the pinned Linux/aarch64 container. Mounts, metadata reads, fsck,
loadkmap and switch_root are intercepted; dummy device nodes are used for
stat/type binding only and are never opened. This is control-flow coverage,
not real ext4 handoff or a physical USB result.

The harness found and fixed three source defects: the Xorg expression rejected
valid quoted `Option "XkbLayout" "no"` syntax; initial directory/devtmpfs setup
errors were ignored; and handoff-directory creation errors were ignored.
After the Xorg correction, the valid setup-error baseline passed 31/34 cases;
its three failures reached handoff after an injected failed command. The
checked-setup version passed 34/34. These before/after traces are retained in
[startup evidence](2026-10-24-usb-root-gates/startup/).

The current root-profile contract adds seven cases, for **41/41 PASS**:
root marker, root map presence/hash, root keymap service/link and shutdown
wrapper/entry. Missing or corrupt preconditions stop before RW; failures after
RW require a RO remount and unmount, with no handoff. A matched metadata failure
is terminal and is not retried. Missing/unloadable initial map never opens a
shell. The successful case performs two identity checks, read-only fsck and
inspection before the intercepted handoff. Results and exact source hashes are
[saved here](2026-10-24-usb-root-gates/startup/profile/results.tsv).

### Separate daily-root staging profile

`scripts/t6040-stage-usb-daily-root.py` stages a separate root from the preserved
WiFi/OBEX v4 archive, SHA256
`b04ccc1e96dde2fcf6fb536a5cbd951045cac1069384cfb284eb295cd6936092`.
Its actual package DB has Alpine3.24, BusyBox1.37.0-r31 and OpenRC0.63.2;
WiFi/DHCP/BlueZ/OBEX/D-Bus tools and paired BCM4388 files are present. The
profile copies only the proven `a1f4131d…` J614s trackpad blob, adds the pinned
Norwegian map and OpenRC service, `keymap="no"`, Xorg layout and nb_NO profile.
It replaces the old RAM `/init` and diagnostic login policy, enables a single
OpenRC wpa_supplicant/dhcpcd ownership path (no networking service), waits for
wlan0, enables dbus/bluetooth and installs the existing explicit OBEX helper.
No automatic pairing/discoverability/receive action runs. Credentials are
refreshed from the host config, never printed or included in repository evidence.

The direct-ext4 shutdown runlevel includes killprocs/mount-ro. A separate
`t6040-usb-root-openrc` shutdown wrapper checks OpenRC's result, syncs, explicitly
remounts `/` RO and verifies the actual ext4 mountinfo before returning to
BusyBox init. On failure it keeps init waiting; a rescue shell requires the
hash-verified Norwegian map. Presence of a mount-ro link alone is insufficient
to establish a clean shutdown.

Two fresh staging trees and deterministic root archives match byte-for-byte:
24,620,287 bytes, SHA256
`fca28f358be77c472d0c77ff5f6ff23c77eb5cfa2aaa88efd967705305378d13`.
They remain private regular files under `/Users/damsleth/code/linux-build-out/usb-root-6005/`;
neither is a GPT image, approved flash input or qualified initramfs. The
historical098 PARTUUID is used only as an offline regression value. Seven
negative staging gates reject nonempty/symlink outputs and invalid UUID,
archive, map, firmware or WPA input before extraction. Full redacted
[profile manifest](2026-10-24-usb-root-gates/daily-root-profile.manifest.json),
[two staging results](2026-10-24-usb-root-gates/daily-root-builds.json) and
[failure gates](2026-10-24-usb-root-gates/stage-negative-results.json) are saved.

### Real OpenRC/direct-ext4 shutdown gate

Six cases pass in the contained Linux/aarch64 harness. Each starts from a
fresh scratch ext4 file populated from the staged root and mounted via a
VM-owned loop device. A new PID/mount/UTS/IPC/network namespace switch_roots
into it; a shell is PID1 and runs **the actual OpenRC0.63.2** sysinit, boot,
default and shutdown commands. The production shutdown wrapper is unmodified.
The fixture disables network/getty/keymap startup, skips VM-global sysctl,
module and dmesg operations, and intercepts loadkmap/rescue shells. Real
ext4 mount/remount and OpenRC mount-ro/killprocs run. Power applets are blocked
and a seccomp policy denies the reboot syscall. No power action is sent.

- Clean and no-mount-ro-link cases return0 only with an observed real
  read-only ext4 root. The latter proves the explicit wrapper gate provides a
  fallback; it does not relax the production init's required shutdown link.
- OpenRC failure, explicit remount failure and a failed final mountinfo check
  never return to the shutdown caller. The failure injection must actually
  fire. Missing keymap during an OpenRC failure withholds the rescue shell.
- Namespace teardown and loop detach complete before `e2fsck -f -n` on each
  fixture file. Every case checks clean. For injected failures this clean fsck
  follows harness teardown and is **not** evidence of successful shutdown.

The [results, console logs and traces](2026-10-24-usb-root-gates/shutdown/results.tsv)
retain the actual final mountinfo, fsck results, package inventory and input
hashes. The initial harness lacked a loop node in its bootstrap; the next
incorrectly classified `halt -w` (wtmp accounting) as a power action and
exposed asynchronous loop autoclear after namespace death. Those harness
defects were fixed before the cited six-case run. The earlier fixture also
allowed normal boot's VM-global sysctl/hostname effects; the final run isolates
UTS/IPC/network and skips sysctl/modules/dmesg. No M4/physical stick was accessed.

This tests real OpenRC/filesystem behavior with a **shell PID1**, not BusyBox
init's signal dispatch or the final poweroff syscall. The actual verified
USB init's identity path remains the separately mocked 41-case test. Actual
stick enumeration, block metadata I/O, end-to-end BusyBox init handoff and
three cold boots/post-poweroff checks remain live acceptance gates.

## Required next work, retained in 6005 / existing queue

1. Preserve the passed metadata/startup/real-OpenRC shutdown gates. Complete
   root dependency review (the inherited archive has no `dev` service provider;
   OpenRC reports warnings for unselected services) and paired kernel/module
   assertions. A devtmpfs console profile does not establish an Xorg/udev stack.
2. Qualify the separately staged root profile with the final kernel and stick
   pins. The historical098 image is unchanged and remains unsuitable for the
   full daily goal. Fresh root archive equality is not a reproducible raw GPT/
   ext4-image claim; its formatter/metadata and final target still need review.
3. Package pinned static e2fsck and the selector/helper/identity in a new
   initramfs. Use two fresh builds, exact member hashes and image preflight.
   The helper currently has one build, not a reproducibility claim. Alpine3.22's
   `e2fsprogs-static-1.47.2-r2` was inspected: it contains static libraries
   (`libcom_err`, `libe2p`, `libext2fs`, `libss`), no e2fsck executable. Installing
   that package alone cannot meet the current static-e2fsck packaging contract.
   The native package listing is retained in
   [this log](2026-10-24-usb-root-gates/e2fsprogs-static-fetch2.log).
4. Keep 305 and 109 as hardware prerequisites for actual stick identity.
   110/111 still own the separately reviewed exact flash target/erase approval;
   do not silently replace their pinned image. 112 owns tethered root/persistence,
   and 113 needs a refreshed exact enrolled-object/rollback review plus the
   three cold boots and clean post-poweroff fsck required by the current goal.
5. The goal's final single image also needs6001 NVMe reads, separately gated
   label+GPT-type-bound NVMe writes, WiFi after cold boot, bidirectional OBEX,
   trackpad touch/haptics and repaired SD fallback. Startup metadata checks
   establish none of those hardware outcomes. Keep maxcpus=1; U-Boot USB3018
   and fault205 are stretch work, not prerequisites for direct-m1n1 USB root.

## Limits that must remain visible

- Metadata clean-state inspection is not a substitute for `e2fsck -f -n`.
- Rechecking identity narrows substitution risk; it is not an atomic hot-unplug
  guarantee. The reviewed fixture must remain seated during handoff.
- A raw image's GPT layout can be smaller than the physical stick. The gate
  pins **both** media capacity and layout length; it does not relocate GPT or
  resize anything automatically. 110/111 must record the actual post-flash form.
- The new source is not selected by existing builders. No new Image, DTB,
  qualified initramfs, raw object or GPT disk image was published or booted.
  Ticket6005 stays in progress for final root/identity/tool packaging, two
  clean initramfs builds, preflight and separate exact-artifact review.
