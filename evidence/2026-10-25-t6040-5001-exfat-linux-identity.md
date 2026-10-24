# Ticket 5001 (2026-10-25): identity of the rebuilt exFAT "linux" partition

Claude, CJ present. Read-only probe v2 (Sonnet review PASS-with-notes):
kernel `6eef9eef…`, DTB `a96d04a7…`, m1n1 `7de07c71…`, initramfs `b29b7a83…`,
`maxcpus=1`, `printk.devkmsg=on`. Every block device was set read-only before
the first read; **writes stayed 0**. The rig returned to `Running proxy`. Console
`linux-build-out/nvme-p3id-20261024/runs/run1/t6040-console-20261025-claude-5001-run1.log`
`d6dd8a14…`.

## Pins for the 211/5003 write gate

| Field | Value |
|---|---|
| controller / namespace | `apple-nvme`, `APPLE SSD AP1024Z`; n1 1,954,210,120 / n2 6,144 / n3 262,144 (512-byte units) |
| logical block size | **4096** |
| partition | `nvme0n1p3` = GPT entry index 3 (array slot 2) |
| GPT type GUID | `EBD0A0A2-B9E5-4433-87C0-68B6B72699C7` (Microsoft Basic Data) |
| GPT unique GUID | `EA0DA6DB-2935-49CB-A996-B982DD646F24` |
| GPT first/last LBA (4 KiB) | 198,364,672 / 242,965,503 |
| sysfs start/size (512 B) | 1,586,917,376 / 356,806,656 (182.68 GB) |
| GPT partition name | *(empty)*: use the exFAT label, not PARTNAME |
| exFAT label | `linux` (root-directory `0x83` entry) |
| exFAT serial | `0x6add2caf` (matches Disk Utility) |
| exFAT geometry | 4096 B sectors (shift 12), 128 KiB clusters (spc shift 5), heap 1792, root cluster 5 |
| VolumeFlags | 0 (clean) |
| boot sector sha256 | `bb426fe05c2faaf1a3c4d174aed5ed90b69ba1c9771833f02fc5913616cc8ec8` |

Full layout: p1 `iBootSystemContainer`, p2 the macOS APFS container (unnamed
GPT entry), **p3 exFAT `linux`**, p4 `RecoveryOSContainer`.

## Probe defect (recorded, not blocking)

v2 read the GPT at 512-byte offsets, but this namespace uses 4096-byte
logical blocks, so its `gpt-header`/`gpt-entry` lines were all zero. The
same reads were repeated at the correct offsets (header at byte 4096,
entries from byte 8192) from the parked operator shell, with the devices
still read-only (`ro=1`, writes 0). The table above comes from that. The
5003 gate must derive offsets from
`/sys/block/nvme0n1/queue/logical_block_size`, not assume 512.
