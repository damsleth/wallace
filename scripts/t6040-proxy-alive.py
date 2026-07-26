#!/usr/bin/env python3
"""Is there a LIVE m1n1 proxy behind this device? Exit 0 if yes, 1 if no.

Ticket 151/157. `[ -e /tmp/m1n1 ]` only proves a symlink exists. On 2026-07-26 that check
passed three times against a pty with nothing behind it — once a stale kisd from an earlier
session, twice because a previous chainload had already booted Linux and consumed the proxy
it needed. Each cost a silent 5-minute `timeout 300` wait with a 0-byte log, because Python
block-buffers stdout to a file so not even the banner appeared.

This asks the proxy to prove it is there: one REQ_NOP with a short timeout. Read-only — a NOP
changes no target state.

Usage:  t6040-proxy-alive.py [--device /tmp/m1n1] [--timeout 5]
"""
import argparse
import os
import sys

sys.path.insert(0, "/Users/damsleth/Code/m1n1/proxyclient")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--device", default=os.environ.get("M1N1DEVICE", "/tmp/m1n1"))
    ap.add_argument("--timeout", type=float, default=5.0)
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    def say(msg: str) -> None:
        if not args.quiet:
            print(msg)

    if not os.path.exists(args.device):
        say(f"proxy-alive: NO — {args.device} does not exist")
        return 1

    # Import inside main so a missing venv is reported as a clear message, not a traceback.
    try:
        from m1n1.proxy import M1N1Proxy, UartInterface, UartTimeout
    except Exception as exc:  # noqa: BLE001
        say(f"proxy-alive: UNKNOWN — cannot import proxyclient ({exc})")
        say("  run with the m1n1 venv python: ~/Code/m1n1/venv/bin/python")
        return 1

    try:
        iface = UartInterface(args.device, debug=False)
        iface.dev.timeout = args.timeout
        M1N1Proxy(iface, debug=False)
        iface.nop()
    except UartTimeout:
        say(f"proxy-alive: NO — no reply from {args.device} within {args.timeout:g}s")
        say("  m1n1 is not sitting in uartproxy. A previous chainload that booted Linux")
        say("  CONSUMES the proxy, so re-enter it before every chainload:")
        say("    bash scripts/t6040-debugusb-console.sh reboot")
        return 1
    except Exception as exc:  # noqa: BLE001
        say(f"proxy-alive: NO — {type(exc).__name__}: {exc}")
        return 1

    say(f"proxy-alive: YES — {args.device} answered a NOP")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
