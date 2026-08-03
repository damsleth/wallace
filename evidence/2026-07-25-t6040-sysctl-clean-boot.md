# T6040 B0 sysctl boot noise — root-caused and fixed in the builder (2026-07-25)

Ticket 135. The untethered B0 boot prints 13 lines like:

```text
sysctl: error: 'net/ipv4/tcp_syncookies' is an unknown key
sysctl: error: 'kernel.unprivileged_bpf_disabled' is an unknown key
```

## Cause

Alpine ships `/usr/lib/sysctl.d/00-alpine.conf`, and its OpenRC `sysctl` service runs in the
**boot** runlevel. That file sets exactly **13** keys that do not exist when the kernel is built
with `CONFIG_NET=n` and BPF disabled — which is the case for the `DIET` B0 kernel, deliberately,
since the B0 root has zero network services. Counted in the shipped root: 13 `net.*` /
`kernel.unprivileged_bpf` keys, matching the 13 error lines exactly.

Harmless — `sysctl` reports and continues — but it is noise on a boot screen that should be
readable.

## Fix

`scripts/t6040-build-alpine-b0.sh` now comments those keys out by default, keeping the useful
non-network hardening:

| Kept | Commented out |
|---|---|
| `kernel.panic = 120`, `fs.protected_hardlinks`, `fs.protected_symlinks` | the 13 `net.*` and `kernel.unprivileged_bpf_disabled` keys |

Set `NET_SYSCTL=1` when building a root destined for a networking-capable kernel
(`DIET_CAPABLE`) to leave them intact.

Verified on a copy of the real file: 13 lines commented, exactly the three non-network keys still
active.

### A BSD-sed trap worth recording

The first version used `s|...|...|` while the pattern itself contained a `|` alternation. This
build step runs **host-side on macOS**, where BSD sed rejects it:

```text
sed: 1: "s|^([[:space:]]*(net\.| ...": RE error: parentheses not balanced
```

It silently commented **0** keys, which a quick "it ran without error" glance would have missed.
Switched to a `#` delimiter and re-tested against the real file. Lesson: verify a sed against
real input and count the result, rather than trusting a clean exit.

## Deliberately not regenerating the proven image

The currently enrolled/proven B0 roots (`initramfs-alpine-b0-nb2.cpio.xz` `d7fcc795` and the
objects built from it) are **left untouched**. Rebuilding them would change hashes that are cited
in `done/` write-ups and pinned in tickets, purely for cosmetics. The fix applies to the next
build of that root; the noise remains in the current image and is documented as expected.
