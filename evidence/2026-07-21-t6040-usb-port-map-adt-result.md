# T6040 USB physical-port ADT capture result (2026-07-21)

Ticket 057 completed after moving the DebugUSB tether to the previously proven
top-left/rear Type-C port and cold-starting the M4. `kisd` attached immediately,
the reviewed RAM-read-only helper ran successfully, and the proxy was restored
without booting Linux or initializing USB, MMIO, PMU/SPMI/NVRAM, or storage.

## Capture

- Raw ADT: host-local
  `/Users/damsleth/Code/linux-build-out/j614s-usb-port-map-20260721.adt`
- Size: 606208 bytes
- SHA-256: `7a92e6e4d16cb1b5a5858beb22b22acc8e5ed4b36ed5d5ccde9b251f1da55c84`
- Filtered host-local log:
  `/Users/damsleth/Code/linux-build-out/j614s-usb-port-map-20260721.log`

The raw capture and verbose log are intentionally not copied into this repo;
the ADT contains device-specific security and identity properties.

## Authoritative port map

Each DWC3 high-speed child carries `usb-c-port-number`, and the HPM nodes map
the same number to `port-location`:

| Linux/ADT controller | `usb-c-port-number` | HPM location | Decision |
|---|---:|---|---|
| `usb-drd0` / ATC0 | 1 | `left-back` | DebugUSB tether; keep disabled in Linux |
| `usb-drd1` / ATC1 | 2 | `left-front` | safe one-port host candidate |
| `usb-drd2` / ATC2 | 3 | `right` | safe one-port host candidate |

The observed working top-left/rear DebugUSB connection agrees with
`left-back`, so enabling all three controllers is no longer justified.

## Continuation

Build and hash a one-port DTB for the physical port carrying the external
drive, leaving `usb-drd0` and its DARTs disabled. Repeat static/cross-agent
review, then propose the no-`root=` USB enumeration smoke. Do not mount or
populate the external filesystem until enumeration remains stable for ten
seconds.
