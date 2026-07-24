# T6040 B0 enrolled cold-boot preflight (ticket 082)

Date: 2026-07-24
Ticket: 082 — **prepare, do not execute**. Enrollment and the cold boot are
separate explicit maintainer approvals and are maintainer-executed on the M4.
Scope of this document: procedure, guards, and rollback only. No APFS, Boot
Policy, `kmutil`, `bputil`, or enrollment action is performed by authoring it.

> **Current amendment:** ticket 100's tethered proof passed. The preferred
> enrollment candidate is now dual-mode object
> `46237ade7e314cd752e1482930e21b62319e1b0b707a0f23e86392701555f0c9`,
> conditionally passed by ticket 119 for bounded hardware validation. Exact
> packing and post-prefix identity pass; pin the exact version tag and
> 2026-07-09 Rust nightly before calling the m1n1 build fully reproducible.
> Its normal-boot versus DebugUSB behavior is validated during ticket 101. The live-proven
> pure-autoboot object `2371ee5d...` remains the fallback. Substitute neither
> hash silently. The post-095 recovery control and later proxy cycles pass;
> still run the standard health preflight before ticket 101. Later commands naming
> `2371ee5d` describe the fallback unless the reviewed 082/101 manifest
> explicitly selects `46237ade`.

## Current M4 state (maintainer-confirmed 2026-07-24)

The M4 already has the Asahi-style dual setup:

- a **dedicated m1n1 macOS volume** (`/Volumes/m1n1` in the bring-up plan) with
  **per-volume Permissive Security** already enabled in 1TR; the **main macOS
  volume is untouched and stays Full Security**;
- that volume is currently enrolled (via `kmutil configure-boot --raw`) with a
  **bare, proxy-waiting m1n1**. Every reboot boots it → `Running proxy…`, which
  is what lets us `chainload.py -r` a payload for the fast dev loop.

So the 1TR / Permissive-Security prerequisite is **already satisfied**; 082 does
not need a new macOS install or a security-policy change. It is a **re-enroll**
of the m1n1 volume's boot object.

## Goal and the one-way change it makes

Replace the enrolled boot object with the proven **B0 release object**:

```text
m1n1-b0-alpine-openrc.bin
SHA-256 2371ee5dfbfab591397fc333e7da212fb7582bfb2eaddaa6438005f5bb41759b
size 22,183,563 B, raw entry 0x800   (ticket-100 live-proven, cross-reviewed)
```

After enrollment, a **cold boot of the m1n1 volume auto-boots straight into
Alpine/OpenRC** (this object deliberately lacks the proxy-wait /
`EARLY_PROXY_TIMEOUT` path) — the untethered B0 milestone. Consequence to accept
going in: **that volume no longer presents `Running proxy` / the chainload dev
loop** while the B0 object is enrolled. Fully reversible (see Rollback); the
DebugUSB chainload path itself is unaffected for other work.

## Prerequisite verification (maintainer, on the M4's MAIN macOS, read-only)

Run from the **main macOS** booted normally (Full Security), not from within the
m1n1-enrolled boot. These are read-only inventory steps:

1. Identify and record the m1n1 volume identity — mount point, volume name, and
   **APFS UUID** — e.g. `diskutil apfs list` / `diskutil info /Volumes/m1n1`.
   Record the UUID; it anchors the identity guard below.
2. Confirm its security posture read-only: `bputil -d -v /Volumes/m1n1`
   (display only — **no** `-n`/`-nc` write here; Permissive is already set).
3. Locate the **currently-enrolled** boot object so it can be backed up. In the
   Asahi model this is the exact `m1n1.bin` last passed to
   `kmutil configure-boot -c … -v /Volumes/m1n1`. Confirm which artifact that
   was (maintainer knows the original); copy it aside and record its SHA-256:

   ```sh
   cp <current-enrolled-m1n1.bin> ~/m1n1-enrolled-backup-$(date +%Y%m%d).bin
   shasum -a 256 ~/m1n1-enrolled-backup-*.bin   # record for rollback
   ```

   (If the exact current object cannot be located, treat the known-good
   upper-guard `m1n1-t6040-logbuf-upper-guard-dryrun.bin` `1394c345…` as the
   rollback object — it is the safe proxy-waiting m1n1 and re-enrolling it
   restores the dev loop.)

## Stage the B0 object on the M4 + verify

The object lives on the M1 (`linux-build-out/m1n1-b0-alpine-openrc.bin`).
Transfer it to the M4 (scp/USB/AirDrop) and verify **before** enrolling:

```sh
shasum -a 256 /path/on/m4/m1n1-b0-alpine-openrc.bin
# MUST equal 2371ee5dfbfab591397fc333e7da212fb7582bfb2eaddaa6438005f5bb41759b
```

Refuse to proceed on any mismatch.

## Identity guard (make targeting the main volume impossible)

Before the enroll command, assert the target is the m1n1 volume and nothing
else. Wrap the enroll in a guard that refuses unless all hold:

- the target path is exactly `/Volumes/m1n1` (the confirmed mount), never `/`;
- `diskutil info` on the target reports the **recorded m1n1-volume UUID**;
- the target's volume name matches the recorded name and its APFS role is **not**
  System or Data of the main container.

If any check fails → **abort, enroll nothing**. This is the same fail-closed
posture as the R0 SPMI ADT gate: no ambiguous target ever gets written.

## Enrollment command (maintainer-executed, after explicit approval)

From the main macOS, after the guard passes:

```sh
kmutil configure-boot \
  -c /path/on/m4/m1n1-b0-alpine-openrc.bin \
  --raw --entry-point 2048 --lowest-virtual-address 0 \
  -v /Volumes/m1n1
```

`--entry-point 2048` (`0x800`) and `--lowest-virtual-address 0` are the raw
m1n1 contract from ticket 080, identical to how the current bare m1n1 is
enrolled — the object's verified entry is `0x800`. This writes only the m1n1
volume's boot configuration; the main volume and its Full Security are untouched.

## Cold-boot proof (maintainer-executed; this is the untethered test)

1. Shut the M4 down fully.
2. Power on holding the power button → **Options/Startup Manager (boot picker)**;
   select the **m1n1 volume**. No cable, no `macvdmtool`, no `chainload.py` —
   the enrolled B0 object boots itself.
3. Expected: m1n1 → Linux → **Alpine/OpenRC on the internal panel**, default
   runlevel, watchdog active, internal keyboard echoes locally (the ticket-100
   acceptance state, now with zero host involvement).

### Observation-only KIS (optional, must not be load-bearing)

You may attach `kisd` read-only to capture the console during the cold boot, but
**supply no payload and send no proxy handshake** — the B0 object auto-boots and
does not wait for a proxy. B0 success is judged on the **panel + keyboard**, not
on KIS (exactly as ticket 100). Do not run `chainload.py`/`linux.py`.

## Pass / stop

**Pass (milestone B0):** boot picker → m1n1 → Linux → Alpine login on the panel
with simpledrm/fbcon, internal keyboard echo, OpenRC default runlevel, and
watchdog — **with no host payload transfer of any kind**.

**Stop / rollback triggers:** volume does not boot, kernel panic, reset loop,
no panel output, or any behavior worse than the tethered ticket-100 run.

## Rollback (always available; main volume never at risk)

The boot picker always still works, so the main macOS is always reachable:

1. Power on → boot picker → **main macOS volume** (boots normally, Full
   Security).
2. Re-enroll the backed-up known-good proxy-m1n1:

   ```sh
   kmutil configure-boot -c ~/m1n1-enrolled-backup-YYYYMMDD.bin \
     --raw --entry-point 2048 --lowest-virtual-address 0 -v /Volumes/m1n1
   ```

   This restores the `Running proxy` + chainload dev loop.
3. Alternative (heavier): delete the m1n1 volume entirely from the main macOS —
   the main install is unaffected either way.

No `bputil` change is needed to roll back (Permissive Security stays as-is on
the m1n1 volume; that is not the risk surface — the boot object is).

## Approvals and division of labor

- **Authoring (this doc): done, offline, no machine touched.**
- **Enrollment** (`kmutil configure-boot` of `2371ee5d`) and the **cold boot**
  are **separate explicit maintainer approvals** and are **maintainer-executed
  on the M4**. The agent is on the M1 and does not run `kmutil`/`bputil`, does
  not modify boot/security settings, and does not perform the cold boot.
- The agent's role at execution time is limited to: staging/hashing the object,
  read-only KIS observation if requested, and recording the result.

## Closure boundary

Close 082 when the volume identity, rollback backup/hash, selected-object
manifest, and action split are complete. Ticket 119's conditional review is
complete. Ticket 101 depends on the remaining preflight and exclusively owns
the live enrolled cold boot and trigger validation.

## Open items for maintainer confirmation

1. Exact current-enrolled object path on the M4 (for the rollback backup) — or
   accept the `1394c345…` upper-guard as the rollback object.
2. The m1n1 volume's exact mount/name/UUID (fills the identity guard).
3. Whether to split approval into (a) enroll + (b) cold boot, or approve both.
