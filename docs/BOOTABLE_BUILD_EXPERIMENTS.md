# Bootable-build milestones

Current as of 2026-08-03. The original B0 experiment ladder is complete; its
full evidence remains in `done/`.

## B0 — untethered self-contained Linux

Status: **complete**

An enrolled raw object cold-boots m1n1, Linux, a J614s DTB, and Alpine without
a host-provided payload. The internal panel, keyboard, and watchdog work.

Settled constraints:

- raw entry point is `0x800`;
- the total enrolled object must be a multiple of 16 KiB;
- kernel, DTB, initramfs, and bootargs are hash-verifiable members;
- minilzlib-compatible XZ members use one stream, one block, and CRC32;
- expanded initramfs stays below the project’s 128 MiB policy limit;
- enrollment is a maintainer-only, separately approved action with rollback.

Primary evidence:

- `done/2026-07-25-t6040-B0-MILESTONE.md`
- `done/2026-07-25-t6040-enrolled-payload-rootcause.md`
- `done/2026-07-23-t6040-raw-boot-object-layout.md`

## B1 — maintainable stage 2

Status: **optional design work**

The current appended-payload object works, so a standard EFI/U-Boot flow is
not a prerequisite. Ticket 191 may design a smaller enrolled stage 1 that
loads and hash-verifies stage 2 from storage.

Candidate media:

- internal NVMe: raw m1n1 reads are proven, but Linux NVMe is not stable;
- SD: read/write is proven, but U-Boot has no exFAT support and would require
  a FAT32 partition or raw reserved area.

Do not repartition or reformat the maintainer’s SD fixture without approval.
The design must fail closed on missing, truncated, or hash-mismatched stage 2
and retain a recovery path.

## B2 — persistent distro

Status: **partially complete through SD**

The active architecture is a small switch-root initramfs plus a 6 GiB ext4
loop image stored on the existing exFAT SD partition. Mount, loop setup,
`switch_root`, and OpenRC startup work. Console, SSH, networking, and the
graphical session remain to be stabilized under ticket 204.

USB root is no longer the primary persistence plan. Internal NVMe may replace
SD later, after the Linux CQ-wrap assert is fixed.

## Rules retained from the experiment ladder

- One new live boundary per ticket.
- Exact hashes, independent review, completed dependencies, approval, and a
  lease precede every rig run.
- Enrollment and storage writes are separate authorization boundaries.
- Keep rollback available and stop on the first unexpected fault.
- Historical candidate objects are evidence, not current defaults.
