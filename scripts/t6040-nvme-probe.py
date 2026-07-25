#!/usr/bin/env python3
"""T6040 m1n1-side NVMe probe — READ-ONLY, bounded, fail-closed.

Question: does m1n1's OWN pre-Linux NVMe path (ANS + SART over RTKit) work on
T6040? If yes, the upstream Asahi boot architecture opens up: a small enrolled
stage-1 m1n1 + `chainload=` stage 2 read from storage, which removes the
appended-payload limitation root-caused in
done/2026-07-25-t6040-enrolled-payload-rootcause.md.

Safety properties (by construction):
  * The m1n1 proxy exposes NO write opcode for NVMe. P_NVME_INIT / P_NVME_READ /
    P_NVME_FLUSH / P_NVME_SHUTDOWN are the entire surface; there is no
    P_NVME_WRITE. This script uses INIT, READ and SHUTDOWN only and never calls
    FLUSH. It therefore cannot modify the internal SSD.
  * Runs against the already-enrolled, live-proven bare m1n1 (1394c345). No new
    firmware, no enrollment change, no boot-policy change, no APFS action.
  * Fail-closed identity gate: refuses unless the live ADT is J614s / chip 0x6040
    and both /arm-io/ans and /arm-io/sart-ans exist.
  * Reads at most a few LBAs and only prints them; no filesystem is mounted or
    parsed, no partition is written.
  * macOS is not running at this point (m1n1 has replaced iBoot), so the device
    is quiescent.

Residual risk: ANS/RTKit bring-up on an untested SoC can hang or raise an SError,
which would wedge m1n1 and require a recovery boot. No data-loss path exists.

Usage (hold the rig lease first):
    M1N1DEVICE=/dev/cu.usbmodemJ22GYCN4YG1 \
        venv/bin/python scripts/t6040-nvme-probe.py [--lbas N]
"""

from __future__ import annotations

import argparse
import sys

sys.path.insert(0, "/Users/damsleth/Code/m1n1/proxyclient")

from m1n1.setup import *  # noqa: E402,F403  (provides u, p, iface)


EXPECT_CHIP_ID = 0x6040
EXPECT_BOARD_ID = 4
EXPECT_TARGET = "J614s"
EXPECT_MODEL = "Mac16,8"


def gate() -> bool:
    """Fail-closed identity + node presence check. No NVMe touch happens here."""
    ok = True

    # NB: the ADT root node is `u.adt` itself; u.adt["/"] raises KeyError.
    def get(fn):
        try:
            return fn()
        except Exception:
            return None

    target = get(lambda: u.adt.target_type)
    model = get(lambda: u.adt.model)
    chip = get(lambda: u.adt["/chosen"].chip_id)
    board = get(lambda: u.adt["/chosen"].board_id)

    print(f"  target-type = {target!r} (expect {EXPECT_TARGET!r})")
    print(f"  model       = {model!r} (expect {EXPECT_MODEL!r})")
    print("  chip-id     = " + (f"{chip:#x}" if isinstance(chip, int) else repr(chip))
          + f" (expect {EXPECT_CHIP_ID:#x})")
    print(f"  board-id    = {board!r} (expect {EXPECT_BOARD_ID!r})")
    if (target != EXPECT_TARGET or model != EXPECT_MODEL
            or chip != EXPECT_CHIP_ID or board != EXPECT_BOARD_ID):
        print("  GATE FAIL: not the exact J614s/T6040 target")
        ok = False

    for path in ("/arm-io/ans", "/arm-io/sart-ans"):
        try:
            u.adt[path]
            print(f"  {path}: present")
        except Exception:
            print(f"  {path}: MISSING")
            ok = False

    return ok


def dump(label: str, data: bytes) -> None:
    print(f"  {label}:")
    for off in range(0, min(len(data), 64), 16):
        chunk = data[off:off + 16]
        hexs = " ".join(f"{b:02x}" for b in chunk)
        text = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        print(f"    {off:04x}  {hexs:<47}  {text}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--lbas", type=int, default=1,
                    help="how many 4 KiB LBAs to read from nsid 1 (default 1)")
    ap.add_argument("--nsid", type=int, default=1)
    args = ap.parse_args()

    if args.lbas < 1 or args.lbas > 8:
        print("refusing: --lbas must be 1..8 (bounded probe)")
        return 2

    print("== identity gate (no NVMe access yet) ==")
    if not gate():
        print("\nGATE FAILED -> zero NVMe transactions performed.")
        return 1

    print("\n== nvme_init() — ANS + SART + RTKit bring-up ==")
    print("  (if this hangs, the link is wedged: recover with a reboot; no write path exists)")
    ret = p.nvme_init()
    print(f"  nvme_init() -> {ret}")
    if not ret:
        print("\nRESULT: m1n1's NVMe path does NOT come up on T6040.")
        print("        The chainload=-from-NVMe architecture is unavailable.")
        return 3

    print("\n== bounded read-only LBA read(s) from nsid %d ==" % args.nsid)
    buf = u.memalign(0x4000, 0x1000 * args.lbas)
    rc = 0
    try:
        for lba in range(args.lbas):
            got = p.nvme_read(args.nsid, lba, buf + lba * 0x1000)
            print(f"  nvme_read(nsid={args.nsid}, lba={lba}) -> {got}")
            if not got:
                rc = 4
                continue
            data = iface.readmem(buf + lba * 0x1000, 512)
            dump(f"lba {lba} (first 64 of 4096 bytes)", data)
            if lba == 0:
                # Purely informational identification, no parsing/mounting.
                if data[510:512] == b"\x55\xaa":
                    print("    -> looks like a protective MBR (GPT disk)")
                if b"NXSB" in data[:64]:
                    print("    -> APFS container superblock magic (NXSB) present")
    finally:
        print("\n== nvme_shutdown() ==")
        try:
            p.nvme_shutdown()
            print("  shutdown ok")
        except Exception as exc:  # noqa: BLE001
            print(f"  shutdown raised: {exc}")

    if rc == 0:
        print("\nRESULT: m1n1's NVMe path WORKS on T6040.")
        print("        -> chainload= stage 2 from internal storage is viable;")
        print("           this removes the enrolled appended-payload blocker.")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
