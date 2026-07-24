# T6040 Alpine/OpenRC single-object preflight

Date: 2026-07-24  
Ticket: 081, artifact/procedure ready; independent review outstanding  
Live state: **not proposed and not approved**

## Exact candidate

Use only:

```text
/Users/damsleth/Code/linux-build-out/m1n1-b0-alpine-openrc.bin
SHA-256 2371ee5dfbfab591397fc333e7da212fb7582bfb2eaddaa6438005f5bb41759b
size 22,183,563 bytes
entry 0x800
```

Its components, offsets, expansion bounds, two-build result, and service
surface are in `done/2026-07-24-t6040-alpine-b0-release-bundle.md`.
`m1n1-b0-alpine-openrc.build2.bin` byte-matches. The strict raw-object verifier
passes with the exact expected command line and the initramfs verifier reports
699 entries and zero block nodes.

Relevant committed scripts at `9a2fec85df5e77fd22cbcab474189a51f7340827`:

| Script | SHA-256 |
|---|---|
| `scripts/t6040-boot-raw-object.sh` | `65763ee2166a3f9c56937e3e0563a605a247618a674da5ed539592559b40f4fa` |
| `scripts/t6040-build-raw-object.py` | `cfde0e054aec3f1e306258017179b06fbc8bf85aec1d6abb7b72ff1d2cc778e6` |
| `scripts/t6040-raw-object-verify.py` | `03b6a0569b8fdff96c65e72107d3dcc08c433839cefc89598190295a802b0975` |
| `scripts/t6040-build-alpine-b0.sh` | `34e4d88c03f99d34bf011e503f5683a20528f600e1fca29bc319fe08e634cfca` |
| `scripts/t6040-verify-alpine-b0.py` | `a3669b9af8f0d9e669144ed34b3db15864d3ba21b5c78541ff2ba0ea28cad283` |

## Review gate

Before creating a rig ticket, another reviewer must confirm:

1. the object begins with safe m1n1 `1394c345...`, not current dirty
   `/Users/damsleth/Code/m1n1/build/m1n1.bin` `3e0c90af...`;
2. the DTB is storage-disabled `2782b922...`, not the current changed
   `t6040-j614s-dcuart.dtb` `b3858f60...`;
3. the kernel is ticket-078's live-proven `df7657c...`;
4. `rdinit=/sbin/init`, `maxcpus=1`, and `idle=nop` are exact, with no
   `root=`, USB, SMP, cpufreq, PCIe, or storage delta;
5. the delivery script invokes `chainload.py -r` once and contains no
   `linux.py`, target shell command, APFS, Boot Policy, or enrollment action;
6. the OpenRC runlevel list has only the four sysinit services, two boot
   services, watchdog, and bounded health report documented in the result.

## Eventual one-shot invocation

This command is recorded for review; do not run it without a new approved rig
ticket and the lease:

```sh
RIG_AGENT=codex \
OBJECT=/Users/damsleth/Code/linux-build-out/m1n1-b0-alpine-openrc.bin \
OBJECT_SHA=2371ee5dfbfab591397fc333e7da212fb7582bfb2eaddaa6438005f5bb41759b \
CONLOG=/Users/damsleth/Code/linux-build-out/alpine-openrc-console.log \
CHAINLOAD_LOG=/Users/damsleth/Code/linux-build-out/alpine-openrc-chainload.log \
scripts/t6040-boot-raw-object.sh
```

Start only from stable `Running proxy`, with KIS attached and no competing PTY
reader. After the one upload, KIS is observational only; do not reconnect
proxyclient or send a second payload.

## Pass and stop contract

Pass requires all of:

- embedded kernel/DTB/initramfs discovery and Linux handoff;
- OpenRC reaches the default runlevel with watchdog active;
- the health report reaches its end marker and shows `input0/event0`;
- `/proc/partitions` has no entries;
- the internal panel displays the tty0 Alpine diagnostic shell;
- a short maintainer-typed line echoes correctly from the internal keyboard;
- ttydc0 output remains available but is not required for panel interaction.

Stop and recover to stable proxy on hash mismatch, upload failure, SError,
reset loop, DART/USB/storage probe, missing health-report end marker, absent
watchdog, lost framebuffer, or any attempt to access storage. A successful
tethered proof still authorizes neither enrollment nor cold boot; ticket 082
remains separately gated.
