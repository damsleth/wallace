# T6040 remote-loop host-tools upstream preparation (2026-07-24)

Ticket 048 (offline, P2, cross-cut). The two remaining local host-tool changes
are now clean signed-off branches and mail drafts. The requested kisd T6040
support needs no patch: it is already in current AsahiLinux kisd upstream.
Nothing was posted, pushed, installed, or run on the M4.

## m1n1 proxyclient PTY transport

- upstream base: `7c7716b6a196c7e601f9f22bb8af335c1b8173ce`
- branch: `codex/proxyclient-pty`
- tip: `13c52b61f2b3bb2a6524a198899b762096aa73ce`
- tree: `99d2196f8ebc0d4c67c5a560cd2cedd5653eec79`
- mail: `patches/m1n1-proxyclient-pty-v1/`

The patch makes pyserial usable with the PTY allocated by kisd. It forces the
slave raw after open so echo and CR/LF translations cannot corrupt m1n1's
binary proxy protocol, and tolerates unsupported baud-rate ioctls on PTYs.
This is deliberately separate from the T6040 firmware series: it is generic
host transport support and changes no target behavior.

Validation:

- `python -m py_compile proxyclient/m1n1/proxy.py`: pass;
- a local pseudo-terminal test preserved `00 0d 0a ff` and `11 0d 0a fe`
  byte-for-byte in both directions and confirmed `ECHO`/`ICANON` were clear;
- the exported mail applied with `git am` to the exact upstream base and
  reproduced tree `99d2196f8ebc0d4c67c5a560cd2cedd5653eec79`.

## macvdmtool ACE3 commands

- upstream base: `b22ae51eb43a0e1daa21d41616ac899f28e7bf8a`
- branch: `codex/ace3-host-tools`
- tip: `3e2038ee1981d74f5cf0560033a5dcc9fdb2e9f5`
- tree: `fd359f3aa8e37638a4b569232c3865dbcde520bf`
- mail: `patches/macvdmtool-ace3-tools-v1/`

The draft adds:

- `actions`, which issues Get Action List and Get Action Info VDMs;
- `vdm`, a bounded raw target-VDM diagnostic;
- `dven`, a bounded raw local-action diagnostic;
- `localserial`, which enters serial mode only on the host side for ACE3
  targets that reject the target-side serial VDM.

The original local implementation was tightened for review: both raw
interfaces reject invalid 32-bit hex input and payloads that exceed their
register capacity before issuing a command, and the source usage plus README
document all four commands. The clean build passed with only the two existing
`kIOMasterPortDefault` deprecation warnings. Built binary SHA-256:
`68c81cfdfb5b49cc0629e03dd27f87df0bd68e79d3e88023d95d2f6bcf6d440f`.
The exported mail applied with `git am` to the exact upstream base and
reproduced tree `fd359f3aa8e37638a4b569232c3865dbcde520bf`.

The repository's NOPASSWD `/usr/local/bin/macvdmtool` flow remains a local
operator policy documented in `docs/DEVLOG.md` and the Wallace harness. It is
not appropriate content for the upstream program patch.

## kisd upstream disposition

Current AsahiLinux kisd upstream is
`d36655c24b2172ffe0999800be3baa8650870928`. The needed work is already
merged:

- `09db62580e04` recognizes M4 Pro on KIS protocol/bcdDevice 4.00;
- `6490172b8519` tries the Pro/Max descriptor-relative base offsets and
  validates each through the DockChannel TX-free register;
- `8069b32e0e72` records T6040/M4 Pro as auto-detected.

The current README records the verified T6040 base as `0x548700000`, matching
this rig. A duplicate kisd patch would be wrong, so the upstream-ready output
for that component is this no-change disposition.

Every new patch is authored and signed off as
`CJ Damsleth <kim@damsleth.no>`. CJ decides whether and where to post the two
mail drafts.
