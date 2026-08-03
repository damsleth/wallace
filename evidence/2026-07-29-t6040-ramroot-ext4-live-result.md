# Ticket 149 RESULT: writable ext4 root on `/dev/ram0` — PASS

On 2026-07-29, with CJ's enrolled `rollback-m1n1-1394c345.bin` holding an
indefinite KIS proxy, Sol chainloaded the approved and reviewed ticket-149
object:

```text
m1n1-b0-ramroot-ext4.bin
sha256  ec111c6dffff6928645157f9cda95238d4cd71b9370d6064f32c55d53da869cc
size    78,594,048 B = 4,797 × 16 KiB
```

The exact artifact and its wrapped ext4 member were reverified before the
boot. The inner 64 MiB filesystem was
`4e589df0bfcd024ad5a3f09a20eb63e4f937bc7b40a975deb88ac003752a9fbc`,
matching the staged record.

## Acceptance evidence

The kernel booted Alpine/OpenRC and reached the `wallace-ramroot-ext4` shell.
The standard B0 report completed and observed the internal keyboard,
`watchdog0`, and Norwegian keymap:

```text
Linux wallace-ramroot-ext4 7.1.3-g246843ff67a8-dirty ... aarch64 Linux
watchdog0=present
loaded no-mac.bmap
=== t6040 B0 health report end ===
```

The root-report service was installed in the default runlevel and reported
`started`. Its output was collected by invoking the same installed reporter
from the live DockChannel shell:

```text
=== t6040 ext4 root report begin ===
-- root device --
/dev/root ext4
-- block devices --
major minor  #blocks  name

   1        0      65536 ram0
  31        0         16 mtdblock0
  31        1        592 mtdblock1
-- writable? --
root is WRITABLE
-- ext4 in use? --
ext4 mounted
-- keymap --
loaded no-mac.bmap
=== t6040 ext4 root report end ===
```

`/proc/mounts` uses the normal `/dev/root` alias rather than spelling the
bootarg's `/dev/ram0` name. This is not a different device: live mountinfo
reported root device `1:0`, and sysfs resolved that exact device number to
`/sys/devices/virtual/block/ram0`:

```text
root=/dev/ram0 rw ramdisk_size=65536
ROOT_MOUNT /dev/root ext4 rw,relatime
ROOT_MOUNTINFO_DEV 1:0
25 1 1:0 / / rw,relatime - ext4 /dev/root rw
/sys/devices/virtual/block/ram0
```

The write criterion was exercised directly on the mounted root with a bounded
create, `sync`, and delete of `/root/.wallace-ticket149-wtest`; it printed
`root is WRITABLE` and left no test file behind.

Therefore all substantive ticket-149 criteria pass:

- a real 64 MiB `ram0` block device is mounted as `/`;
- the filesystem is ext4 and read/write;
- OpenRC reaches the default runlevel from that mounted filesystem;
- the installed root reporter runs successfully;
- the Norwegian keymap status survives the real-root transition.

This closes the Linux root-filesystem half of USB-root bring-up. Once USB
VBUS and the right-port data path enumerate a storage device, root mounting,
ext4, OpenRC, and read/write operation are no longer simultaneous unknowns.

## Non-blocking observation

`rc-status default` showed `t6040-watchdog` as `crashed`, although the B0
health report positively found `watchdog0=present`. Ticket 149 does not test
the old image's watchdog service, and this does not weaken the ext4/root
result, but it must not be silently promoted as a clean current daily-driver
image result.

## Recovery and transcripts

After the test, `t6040-debugusb-console.sh reboot` returned the enrolled
rollback object to `Running proxy`. The console size remained unchanged at
15,125 bytes for the quiescence check, and the rig lease was released
`healthy`.

Host-local transcripts:

```text
raw-object-chainload.log     26863fe61f5f4b00281ec389c4e64e96630ae0d012c955ceb09c278b78fadb51
                              27,987 B
/tmp/t149-console-manual.log b0934d02bb18560a6f7c9448b83155e28089757304e2ece3075424acb22ed1b6
                               2,067 B
/tmp/t149-rootdev-proof.log   758b245907bfcdbaee221e8dd350c2d48e3579352fbc744cea665514932c9e2c
                                 471 B
```
