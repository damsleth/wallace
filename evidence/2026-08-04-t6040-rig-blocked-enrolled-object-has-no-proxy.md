# The rig is blocked for autonomous work: the enrolled object leaves no proxy

Date: 2026-08-04. Agent: fable. Lease: acquired (reclaimed an expired hold),
two sanctioned recovery boots, released **wedged**. No chainload ran, no
experiment ran, no storage was deliberately written.

## Headline

**No tethered chainload is possible until CJ re-enrolls the always-proxy
rollback object from 1TR.** The currently enrolled object is
`m1n1 t6040-e11-tag2`, which vectors straight into Linux, and booting Linux
consumes the proxy. So every cold boot ends with no `uartproxy` for a host to
talk to, and `t6040-boot-dcuart.sh` / `t6040-boot-raw-object.sh` have nothing
to chainload over.

This blocks tickets **215** (SD repair), **228** (BT OBEX) and the trackpad
reset-contract test — all of which are otherwise built, hash-pinned and
reviewed. The unblock is one 1TR trip, not any further engineering.

## What was observed

`t6040-debugusb-console.sh reboot` twice reported
`m1n1 did not reach Running proxy within 25s`. The link itself is healthy:
macvdmtool drove DBMa/normal/debug-USB cleanly both times, kisd opened the
device and guessed base `0x548700000`, and the console captured a complete
118 KB boot transcript. `t6040-proxy-alive.py` returned NO and diagnosed it
correctly — "a previous chainload that booted Linux CONSUMES the proxy". Here
it is the *enrolled* object doing that, on every boot, so the usual remedy
(re-enter the proxy with a recovery reboot) cannot work.

Transcript preserved before any further reboot:

```text
4a5e2f3e259f9e6442e25ab9c9b323de0b09f1f46dcb8490ba77bfe21be7ad49  118771 bytes
  linux-build-out/transcripts/t6040-console-20260804-fable-enrolled-boot-227-uaf.log
```

Boot chain in that transcript: iBootStage1 → iBootStage2 → `m1n1 t6040-e11-tag2`
→ `Vectoring to next stage...` → Linux. Writing to `/tmp/m1n1` produced no
console growth at all, so the machine is not merely proxy-less, it is wedged.

## Why it wedges — a clean reproduction of tickets 206 and 227

The transcript is an unattended, fresh reproduction of the whole failure chain,
which makes it useful evidence rather than just a blocked session:

| t (s) | event |
|---|---|
| 2.79 | `mmcblk0: mmc0:0001 SD 58.2 GiB`, `p1` — the GL9755 SD reader works |
| 3.61 | `Buffer I/O error` on `nvme0n1p1`–`p4` — ANS is already dead (ticket 206) |
| 4.47 | `Workqueue: nvme-wq apple_nvme_remove_dead_ctrl_work` → `apple_nvme_remove+0x50/0xa8` — the ticket-227 teardown |
| 4.55 | `EXT4-fs (loop0): mounted filesystem 4c41b99c-7747-4688-85a5-397bc5d784a2 r/w` |
| 4.57 | `EXT4-fs (loop0): unmounting filesystem` |
| 8.19 | `blk_mq_timeout_work+0x1cc/0x238` oops — kblockd dies, all block I/O with it |
| 12.0 | `apple-pmgr-pwrstate … sync_state() pending`, then silence |

So ticket 227's "takes down ALL block I/O, not just NVMe" is confirmed from a
cold boot: NVMe dies first, its dead-controller teardown corrupts block-layer
state, and `switch_root` onto the SD root can never complete.

## A side effect worth stating plainly

Each cold boot of this enrolled object **mounts the SD ext4 root read-write**
(UUID `4c41b99c-…`, the exact image ticket 215 is meant to repair) and then
loses block I/O a few seconds later. My two recovery reboots each did that.

That was not avoidable — a recovery boot is the sanctioned response to
`NEEDS_RECOVERY`, and the behaviour was only discoverable by reading the
resulting transcript — but it means:

1. the ext4 root may have been re-dirtied, so ticket 215 should assume the
   worst and re-assess rather than trust any earlier clean claim; and
2. **nobody should keep rebooting this machine to "try again"**. Every attempt
   is another unclean r/w mount of CJ's root image for no information gain.
   That is why this session stopped after two attempts and released wedged.

It also contradicts NEXT_STEPS §2's instruction not to mount the SD root
read-write before ticket 215 passes — not because an agent did so, but because
the *enrolled object itself* does it unattended on every power-on.

## What CJ needs to do (one 1TR trip)

Re-enroll the rollback / always-proxy object, after which every prepared
ticket becomes runnable:

```text
rollback-m1n1-1394c345.bin
  1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b
```

Use `scripts/t6040-enroll-guard.sh <object.bin>` from 1TR (1TR is root, no
sudo; `-c` accepts any path, so the object needn't be copied to the m1n1
volume). Then `rig-lease.sh recovered <agent>` after the first healthy proxy.

Ready and waiting behind that single step: ticket 215 (object `bf395c6e`,
strict-verified, preflight OK), ticket 228 (initramfs `b04ccc1e`, pending a
re-review), and the trackpad reset-contract kernel.

## Discipline notes for the next holder

- `NEEDS_RECOVERY` is set and the lease was released **wedged**. The link is
  actually fine; what is missing is an enrolled object that offers a proxy.
  Do not read "wedged" here as a broken KIS link.
- The expired lease was reclaimed from `claude` by the queue tool's own stale
  detection after ~75 minutes with no console activity and no rig process
  beyond the normal `kisd` bridge. COORDINATION.md's guidance that the lease
  is "for rig-touching, not for thinking" is worth re-reading: holding it
  through a long offline analysis is what produced the stale hold.
