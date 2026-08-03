# Ticket 147 dietcap-kernel smoke: object staged, metadata reconciled (2026-07-26)

Enabler 146 is satisfied (maintainer enrolled `rollback-m1n1-1394c345.bin`), so the tethered
KIS smokes are unblocked. This records the staged 147 object and four metadata corrections.

## The staged object

`~/Code/linux-build-out/m1n1-b0-dietcap-smoke.bin`
`ac24d4bfb562f9de7a138a4a3f37b95fb8526e89ab22cc5ffdbc314db23b6546`
**14,893,056 B = 909 × 16 KiB** (aligned; 14,820 bytes of pad added by the packer).

Built exactly to the ticket's spec — every input hash-matched **before** packing:

| Member | Hash | Note |
|---|---|---|
| m1n1 v7 (window-free) | `ecd264a5…` | matches ticket |
| kernel `Image-b0-dietcap.xz` | `9b4aa351…` | raw `e11296cd…`, 33.75 MiB / 9.85 MiB xz |
| DTB `t6040-j614s-dcuart.dtb` | `2782b922…` | storage-disabled |
| initrd `initramfs-alpine-b0-nb2.cpio.xz` | `d7fcc795…` | the PROVEN Alpine OpenRC RAM root |

`t6040-raw-object-verify.py --strict` → **PASS**, `entry=0x800`, runtime payload reserve
50,088,587 B.

## Bootargs are provably identical to the proven B0 set

The milestone writeups elide the bootargs as `3659a0da…`, so rather than retyping them the exact
string was recovered from the proven object `m1n1-b0-diet-aligned.bin` itself and reconciled:

```
maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 fbcon=font:TER16x32 ignore_loglevel rdinit=/sbin/init
```

`sha256("chosen.bootargs=" + args + "\n")` = `3659a0da253c7059…` — the documented value, and the
verifier reports that same hash embedded in the new object. So bootargs are **byte-identical** to
the proven set, as the ticket requires.

## The page-size premise is confirmed, not assumed

The whole point of 147 is isolating the 4 KiB→16 KiB ABI change. Verified from the **arm64 Image
header** (`flags` @ offset 24, bits 1-2 encode page size), not from build logs:

| Kernel | flags | page size |
|---|---|---|
| `Image-b0-diet` (proven B0) | `0xa` | **4K** |
| `Image-b0-dietcap` | `0xc` | **16K** |

A `strings` scan was misleading here — it reports a literal `4K pages` inside
`Image-b0-dietcap` (an unrelated kernel message string). The header is authoritative; **do not
page-size a kernel by `strings`.**

XZ member is minilzlib-safe: 1 stream, 1 block, CRC32, no BCJ filter.

## Metadata corrections

The 14x tickets all carried `deps: []` and `runnable: false` even though their text named
enabler 146, so ordering was not machine-visible.

- **146** → `done`, with the live confirmation (cold boot reaches `Running proxy`, proxy attaches,
  `No valid payload found` ⇒ payload-free as required).
- **147** → `deps: ["146"]`, `runnable: true`, staged object recorded.
- **148** → `deps: ["146"]`, `runnable: true`.
- **149** → `deps: ["146","147"]`, stays `runnable: false`.

**A factual error in 147's own text was corrected.** It read "tickets 147/148 results must not be
attributed to their own payloads". But **148 uses the PROVEN 4 KiB diet kernel `efba5999`** — it is
not affected by the page-size change at all. The ticket that shares the 16 KiB kernel is **149**
(whose own text already says "DEPENDS ON 147"). Left uncorrected this would have wrongly cast doubt
on a dwm result and wrongly cleared a ram0 result. Now: 147 gates **149**, not 148.

## Why this was not run autonomously

Every pass criterion — OpenRC default runlevel, health report begin→end, `event0` keyboard echo,
`watchdog0=present`, empty `/proc/partitions`, Norwegian keymap — is a panel/keyboard observation.
KIS and the USB gadget are mutually exclusive on the DFU port, so the agent-side gadget cannot
observe a `console=tty0` image. **Needs the maintainer at the panel.**

## To run it

```sh
bash scripts/t6040-debugusb-console.sh reboot     # into m1n1, attach kisd -> /tmp/m1n1
bash scripts/t6040-boot-raw-object.sh \
    ~/Code/linux-build-out/m1n1-b0-dietcap-smoke.bin \
    ac24d4bfb562f9de7a138a4a3f37b95fb8526e89ab22cc5ffdbc314db23b6546
```

Positional form is preferred: it survives being pasted with `;` between values, which env-var
assignments do not.

If it fails, the 16 KiB page change is the cause — and 149 must not then be attributed to its own
payload.

## Incident: first attempt booted the wrong object (agent error)

**The 2026-07-26 12:07 run did NOT test this object, and 147 remains untested.**

`scripts/t6040-boot-raw-object.sh` took its object from the `OBJECT` **environment variable** and
**ignored positional arguments**. The run used a positional path, so the argument was dropped and
the script booted its hardcoded default `m1n1-b0-alpine-hid-restored.bin` instead. The failure was
silent in the worst way: the script's SHA guard *passed*, because it validated the default object
(`b50f52ab`) that it had actually selected.

Identified from `raw-object-chainload.log`, which reported `Loading kernel image (0x14b8f13 bytes)`
= 21,729,043 B. `chainload.py` does `image = read_bytes() + b"\x00\x00\x00\x00"`, so the file was
21,729,039 B — exactly `m1n1-b0-alpine-hid-restored.bin`, not this object's 14,893,056 B. That run
reached a shell with `event0` and empty `/proc/partitions` (the trailing `?U??…` garbage and closing
`UartTimeout` are the known console-contention artifact, not a boot failure), but it re-proved an
already-proven July 24 object and produced no new information.

**Fix applied to the script** so this cannot recur:

- a positional `OBJECT_PATH` is now accepted;
- **extra/unknown arguments are a hard error** (exit 2) instead of being ignored;
- a positional path that disagrees with `OBJECT=` is a hard error, rather than silently preferring one;
- overriding the object **without** an explicit `OBJECT_SHA` is refused, and the error prints the
  computed hash to paste back — previously this fell through to the *default* hash and could only
  ever produce a confusing "mismatch" against a file the caller never named;
- `--help` documents both forms.

Verified: the old broken command now exits 2 with `refusing to boot a non-default object without an
explicit OBJECT_SHA`; extra args, conflicting args, unknown options and a wrong hash all exit
non-zero.

**Lesson (same shape as the 16 KiB root cause):** a guard that validates a value the script chose
for itself proves nothing about the value the caller intended. The hash gate must be pinned to the
*named* input, and an ignored argument must fail rather than defaulting.

## Incident 2: the default object struck again (2026-07-26, attempt 2)

Attempt 2 also booted `m1n1-b0-alpine-hid-restored.bin`. **147 is still untested.**

The invocation was `OBJECT=...; OBJECT_SHA=...; M1N1DEVICE=...; bash script.sh` — with
**semicolons**. That is four separate commands: each `VAR=value` sets a *shell-local* variable that
is never exported, so the script ran with none of them in its environment. Prefix assignments only
reach a child process when they are space-separated on the same command.

Incident 1's hardening did not catch it: that guard only fired when `OBJECT` *was* overridden. With
an empty environment the script took its default path, which looked entirely valid — same silent
wrong-object outcome by a different route.

Confirmed three independent ways, including the panel itself:

| Source | Evidence |
|---|---|
| script stdout | `one-object chainload: …/m1n1-b0-alpine-hid-restored.bin` |
| chainload log | `0x14b8f13` = 21,729,039 + 4 = hid-restored, not 14,893,056 |
| **on-screen `uname`** | `7.1.3-g96ac043df12f-dirty`, built **Jul 24** — dietcap is `7.1.3-g246843ff67a8-dirty` |

### Real fix: the hardcoded default object is gone

Both wasted cycles ended in "silently booted the default", so the default itself was the hazard. The
script now has **no default object**; the object **and** its sha256 must be named on every run, and
a positional two-argument form is preferred because it survives semicolon-pasting:

```sh
bash scripts/t6040-boot-raw-object.sh <path> <sha256>
```

A bare run with an empty environment — the exact shape of incident 2 — now exits 2 with
`no object given: name the object explicitly (there is no default)` instead of booting a July 24
object. Env form still works, spaces only.

**Lesson, sharper than incident 1's:** a convenience default is a silent-wrong-answer generator on a
rig where each run costs a reboot cycle. For an operation whose whole purpose is *which bytes ran*,
there should be no value the script can supply on the caller's behalf.
