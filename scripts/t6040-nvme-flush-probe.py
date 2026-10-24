#!/usr/bin/env python3
"""T6040 m1n1-side NVMe FLUSH probe (ticket 5006). Writes no data.

Question: does the ANS2 firmware accept an NVMe Flush at all, and with which
NSID? Linux's flush (opcode 0, nsid 1, TCB dma_flags=FROM_DEVICE, not zeroed)
fails with "cmd parsing error ... fast decode err 0x7" / BAD_CMD
(evidence/2026-10-25-t6040-211-write1-flush-badcmd.md). m1n1's nvme_flush
zeroes the TCB and uses dma_flags=3.

Sequence: identity gate -> nvme_init -> read LBA 0 of nsid 1 (sanity) ->
flush(nsid=1) -> flush(nsid=0xFFFFFFFF) -> read LBA 0 again (link still alive,
same bytes) -> nvme_shutdown. The proxy has no NVMe write opcode; Flush only
commits the controller's volatile cache and carries no data. ANS syslog lines
appear in the m1n1 console output.

Usage (hold the rig lease):
    M1N1DEVICE=/tmp/m1n1 venv/bin/python scripts/t6040-nvme-flush-probe.py
"""

from __future__ import annotations

import sys

sys.path.insert(0, "/Users/damsleth/Code/m1n1/proxyclient")
sys.path.insert(0, "/Users/damsleth/Code/wallace/scripts")

from m1n1.setup import *  # noqa: E402,F403  (provides u, p, iface)
from m1n1.proxy import M1N1Proxy  # noqa: E402

import importlib.util  # noqa: E402

_spec = importlib.util.spec_from_file_location(
    "probe", "/Users/damsleth/Code/wallace/scripts/t6040-nvme-probe.py")
_probe = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_probe)


def main() -> int:
    print("== identity gate (no NVMe access yet) ==")
    if not _probe.gate():
        print("GATE FAILED -> zero NVMe transactions performed.")
        return 1
    print("\n== nvme_init() ==")
    if not p.nvme_init():
        print("RESULT: nvme_init failed; no flush attempted")
        return 3
    buf = u.memalign(0x4000, 0x1000)
    rc = 0
    try:
        ok = p.nvme_read(1, 0, buf)
        before = iface.readmem(buf, 4096) if ok else None
        print(f"  read(nsid=1, lba=0) -> {ok}")
        if not ok:
            return 4
        results = {}
        for nsid in (1, 0xFFFFFFFF):
            r = p.request(M1N1Proxy.P_NVME_FLUSH, nsid)
            results[nsid] = bool(r)
            print(f"FLUSH-PROBE nsid={nsid:#x} -> {'OK' if r else 'FAILED'}")
        ok = p.nvme_read(1, 0, buf)
        after = iface.readmem(buf, 4096) if ok else None
        same = ok and after == before
        print(f"  re-read(nsid=1, lba=0) -> {ok}, identical={same}")
        if not same:
            rc = 5
        print("FLUSH-PROBE RESULT nsid1=%s broadcast=%s link_alive=%s" % (
            results[1], results[0xFFFFFFFF], bool(ok)))
    except Exception as exc:  # noqa: BLE001
        print(f"FLUSH-PROBE PROXY DIED: {exc}")
        return 6
    finally:
        try:
            p.nvme_shutdown()
            print("  nvme_shutdown ok")
        except Exception as exc:  # noqa: BLE001
            print(f"  nvme_shutdown raised: {exc}")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
