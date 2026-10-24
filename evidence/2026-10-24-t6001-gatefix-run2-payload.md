# Ticket 6001: run-2 payload with a corrected namespace gate

Claude, 2026-10-24, offline. Follows
[run 1](2026-10-24-t6001-run1-gate-parked-three-namespaces.md), which parked
because the gate rejected Apple's auxiliary namespaces.

## Change (only /init and the checker)

- `scripts/t6040-init-nvme-ioq-readonly` (`91d94421…`): exactly one
  controller (no `/dev/nvme1`), and namespaces pinned to the live AP1024Z
  topology: n1 1,954,210,120, n2 6,144 and n3 262,144 sectors, with no
  `nvme0n4`. It waits up to 10 s for n2/n3 and otherwise parks before any test
  read. It also sets n2/n3 read-only (n1 and its partitions already were) and
  logs `aux stats before/after` for n2/n3. The tester is unchanged: it opens
  only `/dev/nvme0n1`, `O_RDONLY|O_DIRECT`.
- `scripts/t6040-check-nvme-ioq-transcript.py` (`78889c1d…`): additionally
  requires the pinned topology line and identical before/after n2/n3 stats.

## Verification (host only)

- The gate fragment ran under BusyBox in a mount namespace against fake
  `/sys/block` + `/dev`: exact topology passes; an extra `nvme0n4`, an
  `nvme1`, a wrong n1 size and a wrong n3 size each park.
- The checker run on synthetic transcripts: a clean run passes; an n2 I/O
  change → NOT VALIDATED; a missing topology line → NOT VALIDATED. The run-1
  transcript still fails (STOP).
- Initramfs built twice from the same pinned base (`4cc65133…`) and tester
  (`0ffb3e55…`): both `c76063ac…`, with embedded `/init` = `91d94421…`.
- New candidate `linux-build-out/nvme-ioq-20261024/`, manifest `84b0275f…`
  (241 files). Against the reviewed `nvme-ioq-20260920` manifest (`14ba1600…`),
  exactly three entries changed: initramfs, init, checker. Image `6eef9eef…`,
  DTB `a96d04a7…` and m1n1 `7de07c71…` are byte-identical. The unmodified
  reviewed launcher's verify-only pass: all files verified, preflight OK.

## Gate to run 2

An independent delta review (non-claude) of the two script diffs and the
three changed hashes, then `queue ready 6001`. CJ's approval stands.
