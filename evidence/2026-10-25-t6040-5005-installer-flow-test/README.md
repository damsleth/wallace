# Ticket 5005 installer flow test (claude, 2026-10-25, offline)

Runs `scripts/t6040-init-nvme-root-install`'s copy/adapt/commit section
(`flow-section.sh`, extracted unchanged; only `/sys/block/nvme0n1/` is replaced
by the loop device) chrooted in the installer initramfs `9e8d0d0b…` (built twice,
identical). It uses that initramfs's own BusyBox 1.37.0, e2fsprogs 1.47.4 and static
`fsck.exfat`. The partition and SD identity pins are not exercised, because they
are real-device values.

- `run-in-podman.sh`: p3 is exFAT on a 4 KiB-sector GPT loop, and the source is an
  `SD64` exFAT loop holding an ext4 `wallace-root.img` with UUID 4c41b99c. The run
  is scaled to a 1 GiB source grown to 3 GiB (`SRC_BYTES`/`ROOT_BYTES` overridden).
  Two ext4 variants were tested: the mke2fs default (metadata_csum_seed,
  resize_inode) and `^metadata_csum_seed,^resize_inode`. Both: install PASS,
  in-stream hash = re-read hash, all e2fsprogs steps rc=0, disk writes = p3
  writes, a second run refuses (`already exists`).
- `fullsize-adapt.sh`: the adapt sequence at full scale, 6 GiB grown to 16 GiB, on
  a sparse file. All steps rc=0, new UUID visible to `findfs`, 17179869184 bytes,
  state clean.

Incident: the first versions of both harnesses cleaned up with `umount -R`, which
BusyBox lacks, followed by `rm -rf`. This deleted podman-VM devtmpfs nodes
through the bind-mounted `/dev` and broke new podman sessions until the VM was
restarted. The scripts now detach each mount separately and refuse to `rm` while
anything is still mounted under the work directory. The test results above are
unaffected: the noise lines were removed from `output.txt`.
