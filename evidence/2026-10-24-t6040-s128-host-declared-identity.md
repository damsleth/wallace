# S128 USB stick: host-side declared identity (2026-10-24)

Claude. Read-only metadata from macOS (`diskutil info`, `diskutil list`,
`system_profiler SPUSBDataType`, `ioreg`, `df`) while the stick was attached
to the M1 host as `/Volumes/S128`. No raw block reads, no file listing, no
mount changes and no writes. These values are **declared expectations** for
ticket 109 to confirm on the M4, not a substitute for its on-target identity
read.

| Field | Value |
|---|---|
| USB vendor / product | `0x0781` (SanDisk) / `0x55fd` ("SanDisk 3.2 Gen1") |
| USB serial | `03043930012326064731` |
| bcdDevice | `0x0100` |
| Link on the M1 host | USB 3.2 Gen 1 (5 Gb/s). The M4 right port's proven path is USB2, so expect high-speed there |
| Media size | 123,048,296,448 bytes = 240,328,704 × 512-byte sectors |
| Partitioning | **MBR (FDisk)**, one partition `disk4s1`: DOS_FAT_32, label `S128`, volume UUID `80E9569A-0FF4-3B5B-B070-0B1127312D88`, 123,048,280,064 bytes |
| Usage | 1,224,992 KiB of 120,135,008 KiB used (about 2%) |

## Consequences

- **The stick does not hold the USB-root image.** Ticket 098's image
  (`1c493fad…`, GPT disk GUID `192409a8…`) is not on it. Ticket 109's "compare
  expected identities" must expect an MBR+FAT32 layout unless the stick is
  flashed first, and the 6005 identity template's GUID fields describe an image
  that is not installed.
- **Criterion 1 (USB-stick root) requires flashing this stick, which destroys
  its FAT32 volume and the ~1.2 GB on it.** Ticket 110 owns that procedure; CJ
  decides whether the current contents matter, and must give an exact erase
  confirmation.
- 305 is unaffected: its PASS needs only enumeration and child persistence. 109
  and 4001's reporter can pin `0781:55fd`, the serial and the 240,328,704-sector
  size, and must refuse anything else.
